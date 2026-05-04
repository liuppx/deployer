#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import argparse
import base64
import hashlib
import hmac
import os
import sys
import time
from pathlib import Path

import requests

ENV_FILE = Path(__file__).resolve().parent / ".env"
SUPPORTED_SCENES = {"create_package", "upgrade_service", "monitor_service", "release_notes"}
DEFAULT_CHUNK_SIZE = 3000


def load_env_file(env_path: Path):
    if not env_path.exists():
        return

    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()

        if (value.startswith('"') and value.endswith('"')) or (
            value.startswith("'") and value.endswith("'")
        ):
            value = value[1:-1]

        os.environ.setdefault(key, value)


def parse_args():
    parser = argparse.ArgumentParser(description="send message to feishu ")
    parser.add_argument("scene", nargs="?")
    parser.add_argument("positional_message", nargs="?")
    parser.add_argument("--webhook", dest="webhook")
    parser.add_argument("--secret", dest="secret")
    parser.add_argument("--prefix", dest="prefix")
    parser.add_argument("--file", dest="file_path")
    parser.add_argument("--message", dest="message")
    parser.add_argument("--chunk-size", dest="chunk_size", type=int, default=DEFAULT_CHUNK_SIZE)
    return parser.parse_args()


def get_message(args):
    if args.message:
        return args.message.strip()
    if args.file_path:
        return Path(args.file_path).read_text(encoding="utf-8").strip()
    if args.positional_message:
        return args.positional_message.strip()
    print("必须提供消息内容", file=sys.stderr)
    sys.exit(1)


def get_scene_config(scene: str):
    scene_upper = scene.upper()
    webhook = os.getenv(f"{scene_upper}_WEBHOOK_URL", "")
    secret = os.getenv(f"{scene_upper}_SECRET", "")
    prefix = os.getenv(f"{scene_upper}_PREFIX", "")

    if not webhook:
        print(f"场景配置缺失: {scene}，请在 .env 中配置 {scene_upper}_WEBHOOK_URL", file=sys.stderr)
        sys.exit(1)

    return webhook, secret, prefix


def gen_sign(secret: str, timestamp: str) -> str:
    string_to_sign = f"{timestamp}\n{secret}"
    hmac_code = hmac.new(
        string_to_sign.encode("utf-8"),
        digestmod=hashlib.sha256,
    ).digest()
    return base64.b64encode(hmac_code).decode("utf-8")


def chunk_text(text: str, chunk_size: int):
    lines = text.splitlines()
    chunks = []
    current = []
    current_len = 0

    for line in lines:
        line_len = len(line) + 1
        if current and current_len + line_len > chunk_size:
            chunks.append("\n".join(current).strip())
            current = [line]
            current_len = line_len
            continue

        if not current and line_len > chunk_size:
            start = 0
            while start < len(line):
                chunks.append(line[start:start + chunk_size].strip())
                start += chunk_size
            current = []
            current_len = 0
            continue

        current.append(line)
        current_len += line_len

    if current:
        chunks.append("\n".join(current).strip())

    return [chunk for chunk in chunks if chunk]


def send_message(webhook: str, secret: str, text: str):
    payload = {
        "msg_type": "text",
        "content": {
            "text": text,
        },
    }

    if secret:
        timestamp = str(int(time.time()))
        payload["timestamp"] = timestamp
        payload["sign"] = gen_sign(secret, timestamp)

    response = requests.post(
        webhook,
        json=payload,
        headers={"Content-Type": "application/json"},
        timeout=15,
    )
    response.raise_for_status()
    result = response.json()
    if result.get("code", 0) != 0:
        raise RuntimeError(f"飞书机器人返回失败: {result}")


def main():
    load_env_file(ENV_FILE)
    args = parse_args()

    webhook = args.webhook
    secret = args.secret if args.secret is not None else ""
    prefix = args.prefix if args.prefix is not None else ""

    if args.scene:
        if args.scene not in SUPPORTED_SCENES:
            print(
                "参数错误，暂不支持此场景，仅支持: create_package, upgrade_service, monitor_service, release_notes",
                file=sys.stderr,
            )
            sys.exit(1)
        if not webhook:
            webhook, scene_secret, scene_prefix = get_scene_config(args.scene)
            if args.secret is None:
                secret = scene_secret
            if args.prefix is None:
                prefix = scene_prefix

    if not webhook:
        print("缺少 webhook 配置，请传入场景或使用 --webhook", file=sys.stderr)
        sys.exit(1)

    message = get_message(args)
    if prefix:
        message = f"{prefix}\n\n{message}".strip()
    chunks = chunk_text(message, max(500, args.chunk_size))

    for index, chunk in enumerate(chunks, start=1):
        content = chunk
        if len(chunks) > 1:
            content = f"{chunk}\n\n({index}/{len(chunks)})"
        send_message(webhook, secret, content)

    print(f"send message to feishu successful: scene={args.scene or 'custom'}, chunks={len(chunks)}")


if __name__ == "__main__":
    main()
