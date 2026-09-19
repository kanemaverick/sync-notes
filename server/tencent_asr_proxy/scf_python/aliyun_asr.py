"""Fun-ASR adapter. Secrets stay server-side; timestamps stay connection-relative."""
import asyncio
import json
import uuid


def command(action, task_id, model="fun-asr-realtime", vocabulary_id=""):
    payload = {"input": {}}
    if action == "run-task":
        parameters = {"format": "pcm", "sample_rate": 16000, "heartbeat": True}
        if vocabulary_id:
            parameters["vocabulary_id"] = vocabulary_id
        payload.update(task_group="audio", task="asr", function="recognition",
                       model=model, parameters=parameters)
    return json.dumps({"header": {"action": action, "task_id": task_id,
                                  "streaming": "duplex"}, "payload": payload})


def normalize(message):
    data = json.loads(message)
    event = data.get("header", {}).get("event")
    if event == "task-started":
        return {"type": "proxy.ready"}
    if event == "task-finished":
        return {"type": "proxy.finished"}
    if event == "task-failed":
        # Upstream error text can contain request details. Don't relay it verbatim.
        return {"type": "proxy.error", "message": "阿里云识别失败，请检查模型权限、额度及服务端配置"}
    if event != "result-generated":
        return None
    sentence = data.get("payload", {}).get("output", {}).get("sentence", {})
    if sentence.get("heartbeat") or not sentence.get("text", "").strip():
        return None
    start = sentence.get("begin_time")
    end = sentence.get("end_time")
    # Intermediate results may have no end_time; use the latest word boundary.
    if end is None:
        ends = [w.get("end_time") for w in sentence.get("words", [])]
        end = max([v for v in ends if isinstance(v, int)] + [start or 0])
    if not isinstance(start, int) or start < 0 or not isinstance(end, int) or end < start:
        raise ValueError("Invalid provider timestamps")
    return {"type": "transcript", "sentenceId": sentence["sentence_id"],
            "text": sentence["text"], "startMs": start, "endMs": end,
            "isFinal": sentence.get("sentence_end") is True}


async def relay(client, upstream, model="fun-asr-realtime", vocabulary_id=""):
    task_id = uuid.uuid4().hex
    await upstream.send(command("run-task", task_id, model, vocabulary_id))
    first = normalize(await asyncio.wait_for(upstream.recv(), timeout=8))
    if first != {"type": "proxy.ready"}:
        raise ValueError("Provider did not start task")
    await client.send(json.dumps(first))

    async def upload():
        async for message in client:
            if isinstance(message, bytes):
                if len(message) % 2:
                    raise ValueError("PCM must contain complete int16 samples")
                await upstream.send(message)
            elif json.loads(message).get("type") == "end":
                await upstream.send(command("finish-task", task_id))
                return
            else:
                raise ValueError("Unsupported client event")
        raise ConnectionError("Client disconnected before end")

    async def download():
        async for message in upstream:
            event = normalize(message)
            if event:
                await client.send(json.dumps(event))
                if event["type"] in ("proxy.finished", "proxy.error"):
                    return
        raise ConnectionError("Provider disconnected before final result")

    sender = asyncio.create_task(upload())
    receiver = asyncio.create_task(download())
    try:
        done, _ = await asyncio.wait({sender, receiver}, return_when=asyncio.FIRST_COMPLETED)
        for task in done:
            task.result()
        if receiver not in done:
            # Sending finish-task is not completion: preserve trailing stable sentences.
            await asyncio.wait_for(receiver, timeout=10)
    finally:
        for task in (sender, receiver):
            if not task.done():
                task.cancel()
        await asyncio.gather(sender, receiver, return_exceptions=True)
