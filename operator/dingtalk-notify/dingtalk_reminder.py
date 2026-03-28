# dingtalk_issue_reminder.py
# -*- coding: utf-8 -*-
import base64
import hashlib
import hmac
import os
import sys
import time
from pathlib import Path
from urllib.parse import quote_plus

import requests

ENV_FILE = Path(__file__).resolve().parent / ".env"


def load_env_file(env_path: Path):
    """Load simple KEY=VALUE pairs from .env into os.environ if key is absent."""
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


def get_scene_config(scene: str):
    scene_upper = scene.upper()
    webhook_key = f"{scene_upper}_WEBHOOK_URL"
    secret_key = f"{scene_upper}_SECRET"

    webhook_url = os.getenv(webhook_key)
    secret = os.getenv(secret_key)

    if not webhook_url or not secret:
        print(
            f"场景配置缺失: {scene}，请在 .env 中配置 {webhook_key} 和 {secret_key}",
            file=sys.stderr,
        )
        sys.exit(1)

    return webhook_url, secret


def parse_bool_flag(flag: str):
    normalized = flag.strip().lower()
    if normalized in {"true", "1", "yes"}:
        return True
    if normalized in {"false", "flase", "0", "no"}:
        return False

    print("第二个参数必须是 True 或 False", file=sys.stderr)
    sys.exit(1)


def get_receiver_user_ids(scene: str):
    scene_upper = scene.upper()
    receiver_key = f"{scene_upper}_RECEIVER"
    receiver_value = os.getenv(receiver_key)

    if receiver_value is None:
        print(
            f"接收者配置缺失: {scene}，请在 .env 中配置 {receiver_key}",
            file=sys.stderr,
        )
        sys.exit(1)

    user_ids = [m.strip() for m in receiver_value.split(",") if m.strip()]
    return user_ids


def send_dingtalk_msg(scene: str, need_at: bool, content: str):
    """发送消息到钉钉群"""
    webhook_url, secret = get_scene_config(scene)
    at_user_ids = get_receiver_user_ids(scene) if need_at else []

    timestamp = str(round(time.time() * 1000))
    secret_enc = secret.encode("utf-8")
    string_to_sign = f"{timestamp}\n{secret}"
    hmac_code = hmac.new(
        secret_enc,
        string_to_sign.encode("utf-8"),
        digestmod=hashlib.sha256,
    ).digest()
    sign = quote_plus(base64.b64encode(hmac_code))

    url = f"{webhook_url}&timestamp={timestamp}&sign={sign}"
    headers = {"Content-Type": "application/json"}

    data = {
        "msgtype": "text",
        "text": {"content": content},
        "at": {"atUserIds": at_user_ids, "isAtAll": False},
    }

    response = requests.post(url, json=data, headers=headers)
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] 发送结果: {response.status_code}, {response.text}")
    return response.ok


def main():
    load_env_file(ENV_FILE)

    if len(sys.argv) not in {3, 4}:
        print("用法: python dingtalk_reminder.py <scene> [True|False] <message>")
        print("示例1: python dingtalk_reminder.py create_package \"创建包流程开始\"")
        print("示例2: python dingtalk_reminder.py create_package True \"创建包流程开始\"")
        print("支持场景: create_package, upgrade_service")
        sys.exit(1)

    scene = sys.argv[1]
    if len(sys.argv) == 3:
        need_at = False
        content = sys.argv[2]
    else:
        need_at = parse_bool_flag(sys.argv[2])
        content = sys.argv[3]

    if scene not in {"create_package", "upgrade_service"}:
        print("参数错误，暂不支持此场景，仅支持: create_package, upgrade_service")
        sys.exit(1)

    send_dingtalk_msg(scene, need_at, content)


if __name__ == "__main__":
    main()
