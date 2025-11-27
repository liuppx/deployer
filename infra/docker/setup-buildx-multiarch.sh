#!/usr//bin/env bash

set -euo pipefail  # 严格模式：出错即停、未定义变量报错、管道错误传播

BUILDER_NAME="multi-builder"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
    exit 1
}

index=1
log "step $index -- 检查当前环境操作系统类型"
os_type=$(grep PRETTY_NAME /etc/os-release | cut -d '"' -f 2)
if [[ ! $os_type =~ "Ubuntu" ]]; then
    error "此脚本仅适用于 Ubuntu 系统"
fi

index=$((index+1))
log "step $index -- 检查 Docker 是否已安装"
if ! command -v docker &> /dev/null; then
    error "Docker 未安装，请使用对应的脚本进行安装和配置"
fi

index=$((index+1))
log "step $index -- 确保当前用户有权限运行 docker（避免权限问题）"
if ! docker info &> /dev/null; then
    error "当前用户无法运行 docker 命令，请确保已加入 docker 组并重新登录"
fi


index=$((index+1))
log "step $index -- 检查 docker buildx 是否可用..."
if ! docker buildx version &> /dev/null; then
    error "buildx 未找到，应该是安装的docker版本太低，请重新安装docker或者手动安装buildx"
fi

index=$((index+1))
log "step $index -- 安装QUME支持"
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes

index=$((index+1))
log "step $index -- 创建多架构 builder: $BUILDER_NAME"
if docker buildx ls 2>&1 | grep -q "^${BUILDER_NAME}"; then
    log "builder '$BUILDER_NAME' 已存在，将旧的构建器删除"
    if ! docker buildx rm "$BUILDER_NAME"; then
        error "警告：删除 builder 失败，可能正在使用中"
    fi
fi
# 使用 docker-container 驱动以支持多平台模拟
docker buildx create --name "$BUILDER_NAME" --driver docker-container --use --bootstrap
log "builder '$BUILDER_NAME' 已创建并设为默认"

index=$((index+1))
log "step $index -- 验证多架构支持..."
docker buildx inspect "$BUILDER_NAME" --bootstrap


index=$((index+1))
log "step $index -- 提示信息"
cat <<EOF

✅ 多架构构建环境已就绪！

- Builder 名称: $BUILDER_NAME
- 使用命令示例:
    docker buildx build --platform linux/amd64,linux/arm64 -t myapp .

> 注意：首次构建不同架构镜像时，会自动拉取 QEMU 模拟器。

EOF