# README 模板说明

## 目标

统一项目 `README.md` 的基本结构，确保开发者、维护者和使用者在首次进入项目目录时，能够快速回答以下问题：

- 这个项目是做什么的
- 需要哪些依赖
- 如何快速启动
- 如何配置
- 如何开发和调试
- 如何打包和发布

本模板优先服务当前仓库的实际场景：部署、脚本、容器、中间件、工具和带前端的完整项目。相比通用 README 模板，更强调命令可执行、路径清晰、运维信息完整。

## 编写原则

- 优先写“怎么跑起来”，再写背景介绍。
- 所有命令都应尽量可直接执行，避免只给概念不给命令。
- 所有路径、脚本名、环境变量名保持与仓库实际一致。
- 不写空洞营销文案，不写当前项目并不存在的能力。
- 如果项目依赖外部服务，必须写清依赖项、初始化方式和验证方式。
- 如果项目包含脚本、容器或打包流程，README 中必须给出入口命令。

## 必选章节

每个项目 README 至少应包含以下内容：

### 1. 项目名称

使用项目目录名或仓库名作为一级标题。

### 2. 项目简介

用 2 到 5 行说明：

- 项目用途
- 适用场景
- 核心依赖或运行形态

### 3. 目录说明

列出关键目录和文件，尤其是：

- `scripts/`
- `config/`
- `web/`
- `output/`
- `.env.template`
- `docker-compose.yml`

### 4. 环境要求

写清运行或开发所需依赖，例如：

- 操作系统
- Docker / Docker Compose
- Node.js / Go / Python / Java
- 数据库、中间件、浏览器或 CLI 工具

### 5. 快速开始

必须覆盖从零启动的最短路径，通常包括：

- 克隆代码
- 初始化配置
- 安装依赖
- 启动服务
- 验证服务是否正常

### 6. 配置说明

必须说明：

- 是否需要 `.env`
- 如何从 `.env.template` 生成配置
- 关键环境变量的用途
- 哪些配置必须修改，哪些可使用默认值

### 7. 启动与停止

如果项目提供启动脚本，必须明确入口，例如：

```bash
./scripts/starter.sh
./scripts/starter.sh start
./scripts/starter.sh stop
./scripts/starter.sh restart
```

如果项目使用 Docker，也应写明：

```bash
docker compose up -d
docker compose down
```

### 8. 验证方式

README 必须告诉使用者如何确认项目真的启动成功，例如：

- 访问哪个 URL
- 执行哪个健康检查命令
- 查看哪个日志文件
- 检查哪个端口或接口

### 9. 常见问题

至少列出 2 到 3 个最常见问题，尤其是：

- 依赖未安装
- 配置文件缺失
- 端口占用
- 权限问题
- 数据目录未初始化

## 可选章节

按项目实际情况补充，避免为了凑模板而硬加：

- 本地开发
- 前端构建
- API 文档
- 数据初始化
- 打包发布
- 备份与恢复
- 升级说明
- 贡献指南

如果项目包含打包脚本，建议在 README 中链接或引用 [PACKAGING.md](/Users/liuxin2/Workspace/opensource/deployer/specification/PACKAGING.md)。

如果项目涉及社区协作和 PR 流程，建议引用：

- [GITHUB_FORK.md](/Users/liuxin2/Workspace/opensource/deployer/specification/GITHUB_FORK.md)
- [GITHUB_PULL_REQUEST.md](/Users/liuxin2/Workspace/opensource/deployer/specification/GITHUB_PULL_REQUEST.md)

## 推荐结构

推荐按下面顺序组织 README：

1. 项目名称
2. 项目简介
3. 目录说明
4. 环境要求
5. 快速开始
6. 配置说明
7. 启动与停止
8. 开发说明
9. 打包发布
10. 验证方式
11. 常见问题

这个顺序适合当前仓库中的大多数项目，因为它优先回答“怎么启动”，再展开“怎么开发”和“怎么发布”。

## README 模板

下面是一份建议模板，可直接作为项目 `README.md` 的起点：

~~~~markdown
# <project-name>

## 项目简介

简要说明项目的用途、场景和运行方式。

示例：

- 提供什么能力
- 适合什么场景
- 依赖哪些关键组件

## 目录说明

```text
.
├── scripts/             # 启动、停止、打包等脚本
├── config/              # 配置文件目录
├── web/                 # 前端目录（如有）
├── output/              # 打包输出目录（如有）
├── .env.template        # 环境变量模板
├── docker-compose.yml   # 容器编排文件（如有）
└── README.md
```

## 环境要求

- Docker / Docker Compose
- Node.js 20.x
- PostgreSQL 16
- 其他依赖

## 快速开始

### 1. 克隆代码

```bash
git clone <repo-url>
cd <project-name>
```

### 2. 初始化配置

```bash
cp .env.template .env
```

根据项目需要编辑 `.env`。

### 3. 安装依赖

如果项目有前端：

```bash
cd web
npm install
cd ..
```

如果项目有后端依赖，也应在这里补充安装命令。

### 4. 启动项目

```bash
./scripts/starter.sh
```

或：

```bash
docker compose up -d
```

## 配置说明

说明关键配置项：

```text
APP_PORT=8080
DB_HOST=127.0.0.1
DB_PORT=5432
DB_NAME=app
DB_USER=app_user
DB_PASSWORD=******
```

建议对下列内容逐一说明：

- 变量名
- 默认值
- 是否必填
- 作用范围

## 启动与停止

```bash
./scripts/starter.sh start
./scripts/starter.sh stop
./scripts/starter.sh restart
```

## 开发说明

如适用，可补充：

- 本地开发命令
- 热更新方式
- 日志查看方式
- 调试入口

## 打包发布

如果项目支持打包，应写明：

```bash
./scripts/package.sh
./scripts/package.sh v1.0.1
```

并说明：

- 打包产物位置
- 安装包命名规则
- 是否会自动创建 TAG

详细规则可参考 `specification/PACKAGING.md`。

## 验证方式

启动后建议通过以下方式验证：

```bash
curl http://127.0.0.1:8080/health
```

或：

- 访问 Web 页面
- 检查日志输出
- 检查端口监听

## 常见问题

### 配置文件不存在

先执行：

```bash
cp .env.template .env
```

### 端口已占用

修改 `.env` 中端口配置，或停止占用进程。

### 依赖安装失败

确认网络、代理和依赖版本满足要求后重新执行安装命令。
~~~~

## 不推荐的写法

- 只有项目介绍，没有启动命令。
- 只有 `docker compose up -d`，但没有配置说明。
- 把所有内容都塞到一个“快速开始”章节，没有结构。
- 写了 API、部署、开发、打包等标题，但没有实际内容。
- README 与项目真实脚本不一致，例如 README 写 `./start.sh`，仓库里实际只有 `./scripts/starter.sh`。
