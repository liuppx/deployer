# OpenClaw 集成验证（v2rayN 就绪后）

## 1. Router 连通性

```bash
curl -sS https://test-router.yeying.pub/v1/models \
  -H "Authorization: Bearer <ROUTER_API_KEY>"
```

## 2. OpenClaw 关键配置检查

```bash
grep -nE 'baseUrl|apiKey|"api"|gpt-5.3-codex' ~/.openclaw/openclaw.json
```

确保：
- `baseUrl = https://test-router.yeying.pub/v1`
- `api = openai-responses`
- model 包含 `gpt-5.3-codex`

## 3. WhatsApp 渠道状态

```bash
openclaw channels status
openclaw gateway --token <GATEWAY_TOKEN> health
```

目标状态：

```text
WhatsApp default: enabled, configured, linked, running, connected
Gateway Health: OK
```
