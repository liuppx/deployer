# v2rayN 安装与基础配置

## 1. 客户端安装

- 下载地址：<https://github.com/2dust/v2rayN/releases>
- 下载后解压即可运行，无需安装。

## 2. 添加节点（示例字段）

在 v2rayN 中添加 VMess（或你实际使用的协议）时，按提供商信息填写：

- 备注：自定义
- 地址（Server）：`<server_host>`
- 端口（Port）：`<server_port>`
- 用户ID（UUID）：`<uuid>`
- AlterId：`0`（按服务端要求）
- 加密：按服务端要求
- 传输协议：按服务端要求
- TLS：按服务端要求

> 注意：不要把真实节点地址、UUID、密钥提交到仓库。

## 3. 启用代理能力

- 设为活动服务器
- 打开「自动配置系统代理」
- 打开「TUN 模式」

## 4. 验证

```powershell
# Windows 验证出口
curl.exe -x socks5h://127.0.0.1:10808 https://api.ipify.org
```

## 5. 下一步

继续阅读：
- `portproxy.md`（WSL 代理桥接）
- `wsl-network.md`（WSL DNS 与代理）
- `openclaw-integration.md`（OpenClaw 联调）
