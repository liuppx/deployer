# v2rayN 运维文档（Windows + WSL）

本目录统一维护 v2rayN 在国内 Windows 主机上的部署与运维文档，供 OpenClaw/Bot 项目引用。

## 文档索引

- `install.md`：v2rayN 客户端安装与基础节点配置
- `portproxy.md`：Windows `netsh portproxy` 代理桥接（WSL -> v2rayN）
- `wsl-network.md`：WSL DNS/代理环境配置
- `openclaw-integration.md`：OpenClaw/Router 联动验证步骤
- `troubleshooting.md`：常见故障排查与修复

## 推荐最小流程

1. 先完成 `install.md` 基础连接。
2. 再按 `portproxy.md` 配置 WSL 代理桥。
3. 执行 `wsl-network.md` 修复 DNS + 验证出网。
4. 按 `openclaw-integration.md` 做 OpenClaw 联调。
5. 出现异常时按 `troubleshooting.md` 排查。
