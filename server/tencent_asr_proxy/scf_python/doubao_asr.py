"""SAUC protocol adapter; reference: volcengine/ai-app-lab arkitect ASR.

Independent implementation of the documented wire format, with bounded parsing.
"""
import asyncio
import gzip
import json
import struct
import zlib

MAX_RESPONSE = 1024 * 1024


def frame(payload, kind=2, flags=0, sequence=None):
    encoded = json.dumps(payload).encode() if isinstance(payload, dict) else payload
    compressed = gzip.compress(encoded)
    serialization = 1 if isinstance(payload, dict) else 0
    prefix = bytes((0x11, (kind << 4) | flags, (serialization << 4) | 1, 0))
    if sequence is not None:
        prefix += struct.pack(">i", sequence)
    return prefix + struct.pack(">I", len(compressed)) + compressed


def parse_frame(message):
    if not isinstance(message, bytes) or len(message) < 8 or message[0] >> 4 != 1:
        raise ValueError("Invalid SAUC frame")
    offset = (message[0] & 15) * 4
    kind, flags = message[1] >> 4, message[1] & 15
    if offset < 4 or kind not in (9, 15) or flags > 3:
        raise ValueError("Unsupported SAUC header")
    if flags & 1:
        offset += 4
    if kind == 15:
        # Do not expose provider payloads, which may include request data.
        raise ValueError("SAUC provider rejected request")
    if len(message) < offset + 4:
        raise ValueError("Truncated SAUC frame")
    length = struct.unpack_from(">I", message, offset)[0]
    payload = message[offset + 4:]
    if length != len(payload) or length > MAX_RESPONSE:
        raise ValueError("Invalid SAUC payload length")
    compression = message[2] & 15
    if compression == 1:
        decoder = zlib.decompressobj(16 + zlib.MAX_WBITS)
        payload = decoder.decompress(payload, MAX_RESPONSE + 1)
        if len(payload) > MAX_RESPONSE or not decoder.eof or decoder.unused_data:
            raise ValueError("Invalid or oversized gzip payload")
    elif compression != 0:
        raise ValueError("Unsupported compression")
    if message[2] >> 4 != 1:
        raise ValueError("Expected JSON response")
    data = json.loads(payload)
    if not isinstance(data, dict):
        raise ValueError("Expected object response")
    return data, bool(flags & 2)


def transcripts(data, seen):
    for sentence in data.get("result", {}).get("utterances", []):
        text = sentence.get("text", "").strip()
        if not text:
            continue
        start, end = sentence.get("start_time"), sentence.get("end_time")
        if type(start) is not int or type(end) is not int or start < 0 or end < start:
            raise ValueError("Invalid utterance timestamps")
        final = sentence.get("definite") is True
        identity = (start, end, text, final)
        if seen.get(start) == identity:
            continue
        seen[start] = identity
        yield {"type": "transcript", "sentenceId": start, "text": text,
               "startMs": start, "endMs": end, "isFinal": final}


async def relay(client, upstream, vocabulary_id=""):
    request = {"model_name": "bigmodel", "enable_itn": True, "enable_punc": True,
               "show_utterances": True, "result_type": "full"}
    if vocabulary_id:
        request["corpus"] = {"boosting_table_id": vocabulary_id}
    await upstream.send(frame({
        "user": {"uid": "sync-notes"},
        "audio": {"format": "pcm", "codec": "raw", "rate": 16000,
                  "sample_rate": 16000, "bits": 16, "channel": 1},
        "request": request,
    }, kind=1, flags=1, sequence=1))
    _, terminal = parse_frame(await asyncio.wait_for(upstream.recv(), 8))
    if terminal:
        raise ValueError("SAUC terminated during initialization")
    await client.send(json.dumps({"type": "proxy.ready"}))
    seen = {}

    async def upload():
        async for message in client:
            if isinstance(message, bytes):
                if len(message) % 2:
                    raise ValueError("Incomplete PCM sample")
                await upstream.send(frame(message))
            elif json.loads(message).get("type") == "end":
                await upstream.send(frame(b"", flags=2))
                return
            else:
                raise ValueError("Unsupported client event")
        raise ConnectionError("Client disconnected before end")

    async def download():
        async for message in upstream:
            data, terminal = parse_frame(message)
            for result in transcripts(data, seen):
                await client.send(json.dumps(result))
            if terminal:
                await client.send(json.dumps({"type": "proxy.finished"}))
                return
        raise ConnectionError("SAUC disconnected before final response")

    sender, receiver = asyncio.create_task(upload()), asyncio.create_task(download())
    try:
        done, _ = await asyncio.wait({sender, receiver}, return_when=asyncio.FIRST_COMPLETED)
        for task in done:
            task.result()
        if receiver not in done:
            await asyncio.wait_for(receiver, 10)
    finally:
        for task in (sender, receiver):
            if not task.done():
                task.cancel()
        await asyncio.gather(sender, receiver, return_exceptions=True)
