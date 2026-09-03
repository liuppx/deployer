# Node Identity Trust Bundle

同步 Node issuer metadata 与 Ed25519 JWKS，供 Project 离线校验 presentation。成功后原子更新 `issuer-metadata.json`、`jwks.json`、`manifest.json`；失败保留旧文件。

依赖：`bash`、`curl`、`jq`、`sha256sum`（Linux）或 `shasum`（macOS）。

开发环境直接运行即可，默认连接 `http://localhost:8100`，输出到 `$HOME/.config/node`：
```sh
./sync-identity-trust.sh
```

Project 使用同一目录：

```sh
IDENTITY_TRUST_DIR="$HOME/.config/node"
```

生产环境显式指定固定目录：

```sh
PASSPORT_NODE_URL=https://node.yeying.pub \
IDENTITY_TRUST_DIR=/data/node \
./sync-identity-trust.sh
```

开发环境默认连接 `http://localhost:8100`。脚本只允许 `localhost` 和 `127.0.0.1` 使用 HTTP，非本机 Node 必须使用 HTTPS。

macOS 不要求安装定时任务。需要自动同步时，使用模板生成 `~/Library/LaunchAgents/com.yeying.identity-trust-sync.plist`，替换三个占位符后执行：
```sh
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.yeying.identity-trust-sync.plist
launchctl kickstart -k gui/$(id -u)/com.yeying.identity-trust-sync
```
Linux 复制 `cron.example` 到 crontab。生产目录建议 root 创建并授予 Project 用户读取权限。

验证：`jq . "$HOME/.config/node/manifest.json"`。Project 登录只读取本地目录，不实时请求 Node；Node 负责 JWKS 轮换兼容窗口。
