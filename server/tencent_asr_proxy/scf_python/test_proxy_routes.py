"""Local TCP/WebSocket checks; never contacts a paid ASR provider."""
import asyncio
import json
import os
import unittest
from unittest.mock import patch

from websockets.client import connect
from websockets.exceptions import ConnectionClosedError, InvalidStatusCode
from websockets.server import serve

import app


class RoutesTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.environment = patch.dict(os.environ, {"PROXY_AUTH_TOKEN": "test-only"}, clear=True)
        self.environment.start()
        self.server = await serve(app._handle_client, "127.0.0.1", 0,
                                  process_request=app._process_request)
        self.port = self.server.sockets[0].getsockname()[1]

    async def asyncTearDown(self):
        self.server.close()
        await self.server.wait_closed()
        self.environment.stop()

    async def test_unconfigured_aliyun_returns_clear_error(self):
        async with connect(f"ws://127.0.0.1:{self.port}{app.ALIYUN_PATH}",
                           extra_headers={"Authorization": "Bearer test-only"}) as ws:
            result = json.loads(await ws.recv())
            self.assertEqual(result["type"], "proxy.error")
            self.assertIn("尚未配置", result["message"])

    async def test_both_routes_require_auth_even_when_unconfigured(self):
        for path in (app.CLIENT_PATH, app.ALIYUN_PATH, app.DOUBAO_PATH):
            async with connect(f"ws://127.0.0.1:{self.port}{path}") as ws:
                with self.assertRaises(ConnectionClosedError) as caught:
                    await ws.recv()
                self.assertEqual(caught.exception.code, 1008)

    async def test_unknown_route_is_not_a_provider_proxy(self):
        with self.assertRaises(InvalidStatusCode) as caught:
            async with connect(f"ws://127.0.0.1:{self.port}/arbitrary-host"):
                pass
        self.assertEqual(caught.exception.status_code, 404)

    async def test_health_has_readiness_without_secrets(self):
        reader, writer = await asyncio.open_connection("127.0.0.1", self.port)
        writer.write(b"GET /health HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        await writer.drain()
        response = await reader.read()
        writer.close()
        await writer.wait_closed()
        body = json.loads(response.split(b"\r\n\r\n", 1)[1])
        self.assertEqual(body["providers"], {"tencent": False, "aliyun": False, "doubao": False})
        self.assertNotIn(b"test-only", response)


if __name__ == "__main__":
    unittest.main()
