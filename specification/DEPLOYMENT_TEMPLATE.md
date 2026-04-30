# 部署文档模板（基于打包产物）

## 目标

本模板用于统一社区项目的部署文档写法。

适用前提只有一个：项目必须先按照 [PACKAGING.md](./PACKAGING.md) 完成打包，再将安装包拷贝到目标环境部署。

这意味着部署文档不再扩散到多种路径，而是固定回答下面这些问题：

- 打出来的安装包是什么
- 安装包要拷贝到哪里
- 目标机器需要准备什么
- 解压后如何配置和启动
- 如何验证部署成功
- 失败后如何回滚

## 编写原则

- 以“安装包部署”为唯一主线，不写源码开发态启动流程
- 先写部署步骤，再写背景介绍
- 所有命令必须可复制执行
- 所有路径、脚本名、目录名必须与安装包实际内容一致
- 必须写清验证方式和回滚方式
- 如果使用 AI 起草文档，必须记录人工修订点，防止虚构命令

## 强制约束

- 部署文档必须引用打包规范 [PACKAGING.md](./PACKAGING.md)
- 部署对象必须是安装包，而不是开发目录
- 启动入口必须是安装包内的 `scripts/starter.sh`
- 配置说明必须以安装包内实际提供的配置模板为准，例如 `.env.template`、`config.yaml.template`、`config.js.template`
- 文档中不得出现“直接在开发目录执行”的部署方式，除非明确标记为开发调试，不属于正式部署

## 必选章节

每份部署文档至少应包含以下内容：

### 1. 部署对象

- 项目/服务名称
- 对应安装包名称规则
- 适用环境（dev / test / staging / prod）

### 2. 安装包信息

- 安装包文件名示例
- 安装包生成方式
- 安装包来源（本地打包 / 制品库 / 发布附件）

### 3. 目标环境准备

- 操作系统版本
- 运行时依赖
- CPU / 内存 / 磁盘要求
- 目录准备
- 权限要求

### 4. 部署步骤

固定围绕以下顺序编写：

1. 获取安装包
2. 拷贝到目标机器
3. 解压安装包
4. 初始化配置
5. 执行启动脚本
6. 检查运行状态

### 5. 验证方式

必须说明如何确认安装包部署成功，例如：

- `scripts/starter.sh` 执行后服务正常启动
- 端口监听正常
- 日志中无启动失败信息
- 访问健康检查接口返回正常

### 6. 回滚方式

部署失败时至少应说明：

- 如何停止当前版本
- 如何切回上一个安装包
- 如何恢复旧配置
- 如何确认回滚后的服务状态

### 7. 常见问题

至少包含：

- 配置文件缺失或未替换
- 启动脚本执行失败
- 端口冲突
- 权限不足

## 推荐结构

推荐顺序如下：

1. 部署对象
2. 安装包信息
3. 目标环境准备
4. 部署步骤
5. 验证方式
6. 回滚方式
7. 常见问题
8. AI 协作记录

## 部署文档模板

下面是一份可以直接复制使用的模板：

~~~~markdown
# <project-name> 部署文档

> 文档状态：Draft / In Review / Approved / Deprecated  
> 版本：v0.1  
> 作者：@xxx  
> 维护人：@xxx  
> 适用环境：dev / test / staging / prod  
> 最后更新：YYYY-MM-DD  
> 打包规范：参见 `specification/PACKAGING.md`

## 1. 部署对象

- 服务名称：
- 部署环境：
- 安装包名称规则：
- 启动入口：`scripts/starter.sh`

## 2. 安装包信息

### 2.1 安装包生成方式

按打包规范执行：

```bash
./scripts/package.sh
```

或指定 TAG：

```bash
./scripts/package.sh v1.0.1
```

### 2.2 安装包文件名示例

```text
<project-name>-<tag-name>-<short-hash>.tar.gz
```

示例：

```text
webdav-v1.0.1-8a54401.tar.gz
```

### 2.3 安装包位置

```text
output/<package-name>.tar.gz
```

## 3. 目标环境准备

- 操作系统：
- CPU / 内存 / 磁盘要求：
- 运行时依赖：
- 部署目录：
- 运行账号：

如需提前创建目录，写清命令：

```bash
mkdir -p <deploy-dir>
```

## 4. 部署步骤

### 4.1 获取安装包

从本地 `output/` 目录、制品库或发布页面获取安装包：

```bash
ls output/
```

### 4.2 拷贝安装包到目标机器

```bash
scp output/<package-name>.tar.gz <user>@<host>:<deploy-dir>/
```

### 4.3 登录目标机器并解压

```bash
ssh <user>@<host>
cd <deploy-dir>
tar -xzf <package-name>.tar.gz
cd <package-name-without-suffix>
```

### 4.4 初始化配置

如果安装包内提供 `.env.template`：

```bash
cp .env.template .env
```

如果安装包内提供 `config.yaml.template`、`config.js.template` 或其他配置模板，也要在这里写清复制或修改方式，例如：

```bash
cp config.yaml.template config.yaml
```

如需生成密码，可使用系统工具：

```bash
openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 24; echo
```

必须说明：

- 使用的是哪一种配置文件
- 哪些配置项必须修改
- 哪些配置项可以保留默认值
- 哪些配置项与目标环境强相关

### 4.5 启动服务

```bash
./scripts/starter.sh
```

或：

```bash
./scripts/starter.sh start
```

### 4.6 停止服务

```bash
./scripts/starter.sh stop
```

### 4.7 重启服务

```bash
./scripts/starter.sh restart
```

## 5. 验证方式

### 5.1 启动结果验证

```bash
./scripts/starter.sh status
```

如果项目没有 `status` 子命令，替换为实际验证命令。

### 5.2 端口或进程验证

```bash
<填写实际命令>
```

### 5.3 功能验证

```bash
<填写健康检查、接口调用或页面访问方式>
```

### 5.4 日志验证

```bash
<填写日志查看命令>
```

## 6. 回滚方式

### 6.1 停止当前版本

```bash
cd <current-release-dir>
./scripts/starter.sh stop
```

### 6.2 切回上一个安装包版本

```bash
cd <deploy-dir>
tar -xzf <previous-package-name>.tar.gz
cd <previous-release-dir>
./scripts/starter.sh start
```

### 6.3 恢复旧配置

```bash
cp <backup-env-file> .env
```

### 6.4 回滚后验证

```bash
<填写验证命令>
```

## 7. 常见问题

### 7.1 配置文件未正确初始化

现象：

解决方式：

### 7.2 `scripts/starter.sh` 执行失败

现象：

解决方式：

### 7.3 端口被占用

现象：

解决方式：

### 7.4 权限不足

现象：

解决方式：

## 8. AI 协作记录（必填）

### 8.1 使用范围

- 是否使用大模型起草：是 / 否
- 使用位置：部署步骤整理 / 配置说明整理 / FAQ / 回滚草稿

### 8.2 关键提示词

```text
请基于以下项目文件输出一份安装包部署文档：
- specification/PACKAGING.md
- scripts/package.sh
- scripts/starter.sh
- 实际配置模板文件，例如 .env.template、config.yaml.template、config.js.template
- README.md

要求：
- 只围绕“先打包，再拷贝安装包到目标环境部署”编写
- 不要输出源码开发态部署流程
- 不要虚构不存在的脚本、目录、环境变量和命令
- 不确定的部分标记为“需要人工确认”
```

### 8.3 人工修订记录

- 修订了哪些部署命令：
- 修订了哪些配置说明：
- 删除了哪些 AI 虚构内容：
- 最终人工确认人：
~~~~

## AI 编写建议

部署文档现在必须围绕打包产物来写，所以给大模型喂上下文时，至少提供以下文件：

- `specification/PACKAGING.md`
- `scripts/package.sh`
- `scripts/starter.sh`
- 实际配置模板文件，例如 `.env.template`、`config.yaml.template`、`config.js.template`
- `README.md`

不要只给模型一句“帮我写部署文档”，否则它很容易跳回源码部署、容器直接部署或编造不存在的脚本。

## 配套提示词模板

### 提示词 1：从打包规范反推部署文档

```text
请基于以下文件生成部署文档：
- specification/PACKAGING.md
- scripts/package.sh
- scripts/starter.sh
- 实际配置模板文件，例如 .env.template、config.yaml.template、config.js.template
- README.md

要求：
- 只允许输出“安装包部署”流程
- 部署顺序必须是：打包 -> 拷贝 -> 解压 -> 配置 -> 启动 -> 验证 -> 回滚
- 不要输出源码开发目录运行方式
- 不确定的内容标记为“需要人工确认”
```

### 提示词 2：检查部署文档是否偏离打包规范

```text
请审查下面这份部署文档，重点指出：
- 是否绕过了 PACKAGING.md
- 是否直接使用开发目录而不是安装包
- 是否遗漏 scripts/starter.sh
- 是否缺少回滚步骤
- 是否存在无法执行的命令
并给出最小修改建议。
```
