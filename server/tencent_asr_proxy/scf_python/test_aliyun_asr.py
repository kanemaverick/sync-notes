import asyncio
import json
import unittest

from aliyun_asr import command, normalize, relay


def event(name, sentence=None):
    return json.dumps({"header": {"event": name},
                       "payload": {"output": {"sentence": sentence or {}}}})


class FakeSocket:
    def __init__(self):
        self.inbox = asyncio.Queue()
        self.sent = []

    async def send(self, message):
        self.sent.append(message)

    async def recv(self):
        return await self.inbox.get()

    def __aiter__(self):
        return self

    async def __anext__(self):
        return await self.recv()


class ProtocolTest(unittest.TestCase):
    def test_run_and_finish_share_task(self):
        run = json.loads(command("run-task", "abc", vocabulary_id="vocabulary-1"))
        end = json.loads(command("finish-task", "abc"))
        self.assertEqual(run["header"]["task_id"], end["header"]["task_id"])
        self.assertEqual(run["payload"]["parameters"]["sample_rate"], 16000)
        self.assertEqual(run["payload"]["parameters"]["vocabulary_id"], "vocabulary-1")
        self.assertEqual(end["payload"], {"input": {}})

    def test_partial_timestamp_and_heartbeat(self):
        result = normalize(event("result-generated", {
            "sentence_id": 2, "begin_time": 50, "end_time": None,
            "text": "AI", "sentence_end": False,
            "words": [{"end_time": 240}],
        }))
        self.assertEqual(result["endMs"], 240)
        self.assertFalse(result["isFinal"])
        self.assertIsNone(normalize(event("result-generated", {"heartbeat": True})))

    def test_provider_failure_does_not_leak_payload(self):
        result = normalize(json.dumps({"header": {
            "event": "task-failed", "error_message": "secret-key-value"}}))
        self.assertNotIn("secret-key-value", json.dumps(result))
        self.assertEqual(result["type"], "proxy.error")

    def test_invalid_timestamp_rejected(self):
        with self.assertRaises(ValueError):
            normalize(event("result-generated", {
                "sentence_id": 0, "text": "test", "begin_time": 50, "end_time": 20}))


class RelayTest(unittest.IsolatedAsyncioTestCase):
    async def test_audio_waits_for_started_and_final_is_drained(self):
        client, upstream = FakeSocket(), FakeSocket()
        client.inbox.put_nowait(b"\x00\x00" * 640)
        client.inbox.put_nowait('{"type":"end"}')
        task = asyncio.create_task(relay(client, upstream))
        await asyncio.sleep(0.01)
        self.assertEqual(len(upstream.sent), 1)
        self.assertEqual(client.sent, [])
        upstream.inbox.put_nowait(event("task-started"))
        await asyncio.sleep(0.01)
        self.assertIsInstance(upstream.sent[1], bytes)
        self.assertEqual(json.loads(upstream.sent[2])["header"]["action"], "finish-task")
        self.assertFalse(task.done())
        upstream.inbox.put_nowait(event("result-generated", {
            "sentence_id": 0, "text": "最后一句 Transformer",
            "begin_time": 0, "end_time": 40, "sentence_end": True}))
        upstream.inbox.put_nowait(event("task-finished"))
        await asyncio.wait_for(task, 1)
        messages = [json.loads(message) for message in client.sent]
        self.assertEqual([m["type"] for m in messages],
                         ["proxy.ready", "transcript", "proxy.finished"])
        self.assertTrue(messages[1]["isFinal"])

    async def test_start_failure_sends_no_audio(self):
        client, upstream = FakeSocket(), FakeSocket()
        upstream.inbox.put_nowait(event("task-failed"))
        with self.assertRaises(ValueError):
            await relay(client, upstream)
        self.assertEqual(len(upstream.sent), 1)


if __name__ == "__main__":
    unittest.main()
