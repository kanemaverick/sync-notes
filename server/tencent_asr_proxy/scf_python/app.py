import asyncio
import base64
import hashlib
import hmac
import json
import os
import random
import re
import time
from http import HTTPStatus
from urllib.parse import quote, urlencode, urlsplit

from websockets.client import connect
from websockets.exceptions import ConnectionClosed
from websockets.server import serve


TENCENT_ASR_HOST = "asr.cloud.tencent.com"
CLIENT_PATH = "/v1/asr/tencent/realtime"


def _environment():
    return {
        "app_id": os.environ.get("TENCENT_APP_ID", "").strip(),
        "secret_id": os.environ.get("TENCENT_SECRET_ID", "").strip(),
        "secret_key": os.environ.get("TENCENT_SECRET_KEY", "").strip(),
        "proxy_token": os.environ.get("PROXY_AUTH_TOKEN", "").strip(),
    }


def _is_configured(config):
    return all(config.values())


def _safe_id(value):
    sanitized = re.sub(r"[^a-zA-Z0-9_-]", "_", value)
    return (sanitized or "session")[:80]


def _tencent_asr_url(config, session_id):
    timestamp = int(time.time())
    voice_id = f"{_safe_id(session_id)}_{os.urandom(8).hex()}"
    path = f"/asr/v2/{config['app_id']}"
    parameters = {
        "convert_num_mode": "3",
        "engine_model_type": "16k_zh_en_2.0",
        "expired": str(timestamp + 3600),
        "filter_dirty": "0",
        "filter_modal": "0",
        "filter_punc": "0",
        "needvad": "1",
        "nonce": str(random.SystemRandom().randint(1, 2_000_000_000)),
        "secretid": config["secret_id"],
        "sentence_strategy": "0",
        "timestamp": str(timestamp),
        "voice_format": "1",
        "voice_id": voice_id,
    }
    query = urlencode(sorted(parameters.items()), quote_via=quote)
    source = f"{TENCENT_ASR_HOST}{path}?{query}"
    signature = base64.b64encode(
        hmac.new(
            config["secret_key"].encode("utf-8"),
            source.encode("utf-8"),
            hashlib.sha1,
        ).digest()
    ).decode("ascii")
    return f"wss://{source}&signature={quote(signature, safe='')}"


async def _process_request(path, _request_headers):
    if urlsplit(path).path == "/health":
        body = json.dumps(
            {"ok": True, "providerConfigured": _is_configured(_environment())},
            separators=(",", ":"),
        ).encode("utf-8")
        return (
            HTTPStatus.OK,
            [
                ("Content-Type", "application/json; charset=utf-8"),
                ("Content-Length", str(len(body))),
            ],
            body,
        )
    if urlsplit(path).path != CLIENT_PATH:
        body = b"Not found"
        return (
            HTTPStatus.NOT_FOUND,
            [("Content-Type", "text/plain"), ("Content-Length", str(len(body)))],
            body,
        )
    return None


async def _relay(source, destination):
    async for message in source:
        await destination.send(message)


async def _handle_client(client, path):
    config = _environment()
    if not _is_configured(config):
        await client.send(
            json.dumps({"type": "proxy.error", "message": "Provider not configured"})
        )
        await client.close(code=1011)
        return

    expected = f"Bearer {config['proxy_token']}"
    received = client.request_headers.get("Authorization", "")
    if not hmac.compare_digest(received, expected):
        await client.close(code=1008, reason="Unauthorized")
        return

    session_id = urlsplit(path).query
    query = dict(
        item.split("=", 1) if "=" in item else (item, "")
        for item in session_id.split("&")
        if item
    )
    upstream_url = _tencent_asr_url(config, query.get("session_id", "session"))

    try:
        async with connect(
            upstream_url,
            open_timeout=8,
            ping_interval=5,
            max_size=None,
        ) as upstream:
            await client.send(json.dumps({"type": "proxy.ready"}))
            client_to_upstream = asyncio.create_task(_relay(client, upstream))
            upstream_to_client = asyncio.create_task(_relay(upstream, client))
            done, pending = await asyncio.wait(
                {client_to_upstream, upstream_to_client},
                return_when=asyncio.FIRST_COMPLETED,
            )
            for task in pending:
                task.cancel()
            if client_to_upstream in done and not upstream.closed:
                await upstream.send(json.dumps({"type": "end"}))
    except ConnectionClosed:
        return
    except Exception as error:
        if not client.closed:
            await client.send(
                json.dumps({"type": "proxy.error", "message": str(error)})
            )
            await client.close(code=1011)


async def main():
    port = int(os.environ.get("PORT", "9000"))
    async with serve(
        _handle_client,
        "0.0.0.0",
        port,
        process_request=_process_request,
        ping_interval=5,
        max_size=None,
    ):
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
