# 使用 nvm 管理和切换 Node.js 版本

本文档介绍如何使用 **nvm (Node Version Manager)** 在同一台机器上安装多个 Node.js 版本，并在它们之间切换。

---

## 1. nvm 简介

- 作用：在用户目录下管理多个 Node.js 版本，不动系统级 Node。
- 优点：
  - 同一台机器上可以安装多个 Node 版本（如 14/16/18/20）。
  - 每个终端会话可以使用不同版本。
  - 可按项目指定 Node 版本（配合 `.nvmrc`）。

---

## 安装 nvm

### 官方脚本安装

如果是国内机器安装，在`/etc/hosts`添加一行`199.232.68.133  raw.githubusercontent.com`

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
```
# 或者

```bash
wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
```

### 加载终端配置

```bash
# bash
source ~/.bashrc

# zsh
source ~/.zshrc
```

---

## 使用 nvm 安装 node

### 查看可用版本

```bash
# 列出远程可用版本
nvm ls-remote

# 列出本机已安装的版本
nvm ls
```

### 安装指定版本

```bash
# 安装最新 LTS 版本（推荐生产使用）
nvm install --lts

# 安装特定版本
nvm install 18
nvm install 20.11.1
```

### 卸载指定版本

```bash
nvm uninstall 16
```

## 切换终端 Node 版本

### 查看当前使用的版本

```bash
node -v
nvm current
```

### 在当前终端会话中切换版本
```bash
# 使用指定版本
nvm use 18
nvm use 20
```

### 设置新开终端默认版本
```bash
# 设置默认使用最新 LTS
nvm alias default lts/*

# 设置默认使用某个具体版本
nvm alias default 18

# 查看已设置的别名
nvm alias
```

## 项目指定 Node 版本

### 创建 .nvmrc

在项目根目录：

```bash
echo "18" > .nvmrc
```

### 进入项目手动切换

```bash
nvm use        # 会读取当前目录的 .nvmrc

# 如果该版本尚未安装，nvm 会提示你先安装：
nvm install

```

# Node / npm 国内镜像配置

下面说明如何把 Node.js 和 npm 的下载源切到国内镜像。

---

## npm 包镜像

加速 `npm install`：

```bash
# 设置 npm registry（全局）
npm config set registry https://registry.npmmirror.com

# 验证
npm config get registry
# 输出应为 https://registry.npmmirror.com

# 恢复官方源：
npm config set registry https://registry.npmjs.org
```

## yarn 包镜像

```bash
yarn config set registry https://registry.npmmirror.com
```

## pnpm 包镜像

```bash
pnpm config set registry https://registry.npmmirror.com
```

## nvm node的国内镜像

```bash
# 临时设置（当前终端有效）
export NVM_NODEJS_ORG_MIRROR=https://npmmirror.com/mirrors/node

# bash
echo 'export NVM_NODEJS_ORG_MIRROR=https://npmmirror.com/mirrors/node' >> ~/.bashrc
source ~/.bashrc

# zsh
echo 'export NVM_NODEJS_ORG_MIRROR=https://npmmirror.com/mirrors/node' >> ~/.zshrc
source ~/.zshrc

```
