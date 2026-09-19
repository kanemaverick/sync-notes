import asyncio
import gzip
import json
import struct
import unittest

from doubao_asr import frame, parse_frame, transcripts, relay
from test_aliyun_asr import FakeSocket


def response(data, final=False):
    payload = json.dumps(data).encode()
    return bytes((0x11, 0x93 if final else 0x91, 0x10, 0)) + struct.pack(
        ">iI", -1 if final else 1, len(payload)) + payload


class BinaryProtocolTest(unittest.TestCase):
    def test_audio_and_final_wire_headers(self):
        audio = b"\x01\x00" * 640
        encoded = frame(audio)
        self.assertEqual(encoded[:4], b"\x11\x20\x01\x00")
        self.assertEqual(struct.unpack(">I", encoded[4:8])[0], len(encoded) - 8)
        self.assertEqual(gzip.decompress(encoded[8:]), audio)
        last = frame(b"", flags=2)
        self.assertEqual(last[:4], b"\x11\x22\x01\x00")
        self.assertEqual(gzip.decompress(last[8:]), b"")

    def test_server_sequence_final_and_compression(self):
        self.assertEqual(parse_frame(response({"result": {}}, True)), ({"result": {}}, True))
        self.assertEqual(parse_frame(frame({"result": {}}, kind=9)), ({"result": {}}, False))

    def test_malformed_or_oversized_frames_rejected(self):
        for message in (b"", b"\x11\x90\x10\x00", response({})[:-1],
                        frame({"text": "a" * (1024 * 1024 + 1)}, kind=9),
                        b"\x11\xf0\x10\x00" + b"\x00" * 8):
            with self.assertRaises(ValueError):
                parse_frame(message)

    def test_repeated_full_results_do_not_duplicate_final_sentences(self):
        seen = {}
        data = {"result": {"utterances": [{"text": "Transformer", "start_time": 10,
                                         "end_time": 450, "definite": False}]}}
        partial = list(transcripts(data, seen))
        self.assertFalse(partial[0]["isFinal"])
        data["result"]["utterances"][0]["definite"] = True
        final = list(transcripts(data, seen))
        self.assertEqual(final[0]["sentenceId"], partial[0]["sentenceId"])
        self.assertTrue(final[0]["isFinal"])
        self.assertEqual(list(transcripts(data, seen)), [])


class RelayTest(unittest.IsolatedAsyncioTestCase):
    async def test_handshake_pcm_end_and_trailing_sentence(self):
        client, upstream = FakeSocket(), FakeSocket()
        client.inbox.put_nowait(b"\x00\x00" * 640)
        client.inbox.put_nowait('{"type":"end"}')
        task = asyncio.create_task(relay(client, upstream))
        await asyncio.sleep(0.01)
        self.assertEqual(len(upstream.sent), 1)
        initial = upstream.sent[0]
        self.assertEqual(initial[:4], b"\x11\x11\x11\x00")
        self.assertEqual(json.loads(gzip.decompress(initial[12:]))["request"]["model_name"], "bigmodel")
        upstream.inbox.put_nowait(response({}))
        await asyncio.sleep(0.01)
        self.assertEqual(upstream.sent[-1][1], 0x22)
        self.assertFalse(task.done())
        upstream.inbox.put_nowait(response({"result": {"utterances": [
            {"start_time": 0, "end_time": 40, "text": "最后一句", "definite": True}]}}, True))
        await asyncio.wait_for(task, 1)
        messages = [json.loads(m) for m in client.sent]
        self.assertEqual([m["type"] for m in messages], ["proxy.ready", "transcript", "proxy.finished"])


if __name__ == "__main__":
    unittest.main()
