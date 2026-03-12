# 故障排查

## 1) WSL 出网失败

按顺序检查：
1. v2rayN 是否运行、是否开启系统代理和 TUN
2. `netstat -ano | findstr :10808`
3. `netsh interface portproxy show v4tov4`
4. `curl --socks5-hostname "$HOST_IP:10810" https://api.ipify.org`

## 2) Router 请求报 503/超时

- 先验证代理与 DNS
- 再检查 key 是否有效
- 再检查 OpenClaw 配置 `models.providers.router.api=openai-responses`

## 3) WhatsApp 扫码后不稳定

- 检查 `openclaw channels status`
- 检查 `openclaw channels logs --channel whatsapp --lines 120`
- 若出现 405 类错误，按 Bot 仓库脚本补丁流程修复
