# release_notes.sh

`release_notes.sh` 会在脚本内直接调用 `codex --input ... --output ...`。  
流程是：先提取两个版本之间的原始变更数据，再让 Codex 生成最终中文 Markdown 发布说明。

## 设计目标

- 脚本内直接完成“数据提取 + Codex 生成最终报告”
- 保留可复用的原始数据输入文件（可选）
- 可在任意 Git 仓库复用

## 用法

```bash
./scripts/release_notes.sh <旧版本引用> <新版本引用|HEAD> [最终输出文件]
./scripts/release_notes.sh [最终输出文件]
./scripts/release_notes.sh --help
```

示例：

```bash
./scripts/release_notes.sh v0.0.1 v0.0.2
./scripts/release_notes.sh v0.0.1 HEAD /tmp/release-notes.md
./scripts/release_notes.sh
```

默认模式：

- 若 `HEAD` 正好是最新 tag：分析“上一个 tag..最新 tag”
- 否则：分析“最新 tag..HEAD”

## 脚本输出

最终输出是 Codex 生成的中文 Markdown 报告。  
脚本内部会先生成一份原始输入数据（默认临时文件），包含以下模块：

- 版本范围与提交范围
- 统计信息（提交数、文件数、+/- 行数、贡献者数）
- 贡献者列表
- 提交列表（不含 merge）
- 提交列表（含 merge）
- 变更文件（`git diff --name-status`）
- 高频变更文件 TOP 20

## 配置

脚本会尝试读取以下配置文件（按顺序）：

1. `$RELEASE_NOTES_ENV_FILE`
2. `scripts/release_notes.env`
3. `scripts/.env`

可配置项：

- `RELEASE_NOTES_TAG_GLOB`：默认 tag 匹配规则，默认 `v[0-9]*.[0-9]*.[0-9]*`
- `RELEASE_NOTES_CODEX_BIN`：Codex 命令名，默认 `codex`
- `RELEASE_NOTES_RAW_OUTPUT_FILE`：原始输入数据输出路径（可选）
- `RELEASE_NOTES_KEEP_RAW_INPUT`：是否保留自动创建的原始输入临时文件，默认 `false`
- `RELEASE_NOTES_KEEP_FINAL_TMP`：未传最终输出文件时，是否保留自动创建的最终报告临时文件，默认 `false`

模板见 [scripts/release_notes.env.template]

## 行为说明

1. 你传了“最终输出文件”：脚本会把最终 Markdown 写到该文件。
2. 你不传“最终输出文件”：脚本会使用临时文件生成，然后把结果打印到 stdout。
3. 若未安装或未登录 Codex CLI，脚本会直接报错退出。
