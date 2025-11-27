参考 [官网](https://docs.docker.com/engine/install/)

# 安装docker

1. 设置ubuntu docker仓库：

国内机器执行命令：./setup_aliyun.sh

国外机器执行命令：./setup_ubuntu.sh


2. 执行安装命令进行docker安装：

./install.sh

3. 执行安装命令进行docker buildx 多平台构建器安装（如有需要）：

./setup-buildx-multiarch.sh

# 构建镜像

```shell
# 支持更多架构
docker buildx build \
  --platform linux/amd64,linux/arm64,linux/arm/v7 \
  --tag your-username/your-app:latest \
  --push \
```

# 清理镜像

## 清理未使用的镜像

```shell
# 清理悬空镜像（dangling images）
docker image prune

# 清理所有未使用的镜像
docker image prune -a

# 强制清理，不询问确认
docker image prune -a -f
```

## 清理未使用的资源

```shell
# 清理未使用的镜像、容器、网络和构建缓存
docker system prune

# 清理所有未使用的资源（包括未使用的镜像）
docker system prune -a

# 强制清理
docker system prune -a -f
```

# 调用本地其他容器服务

举例说明：
当前服务是bookstack服务，需要引用本地postgresql服务，postgresql服务的网络名psql-network

修改bookstack服务的docker-compose.yml

1. 引入外部网络名，添加三行：
networks:
  psql-network:
    external: true
2. 在bookstack服务中引入这个网络名
services:
  bookstack:
    networks:
      - psql-network
3. 在bookstack服务中配置host时使用postgresql服务名即可，配置port时使用postgresql的内部端口；

# 用户和用户组

用户 (User): 在操作系统中，每个用户都有一个唯一的用户标识符 (UID)。用户可以是系统的管理员、普通用户或服务用户。用户的权限决定了他们可以执行的操作和访问的资源。
用户组 (Group): 用户组是一个用户的集合，允许一组用户共享相同的权限。每个用户可以属于一个或多个用户组。用户组也有一个唯一的组标识符 (GID)，用于管理组内的权限。

## 权限问题

容器内部的用户和用户组与宿主机的用户和用户组是分开的。当你在容器中使用卷 (volumes) 挂载宿主机的目录时，可能会遇到权限问题，例如，如果容器中的进程以某个用户身份运行，而该用户在宿主机上没有相应的权限，可能会导致无法访问或修改挂载的文件。

## 解决方案

在启动容器时指定用户的 PUID（用户 ID）和 PGID（组 ID）。这可以确保容器内的进程以宿主机上相应用户的身份运行，从而避免权限冲突。

1. 查找宿主机用户的 UID 和 GID:

id <your_user>

输出如下：uid=1000(your_user) gid=1000(your_user) groups=1000(your_user)

2. 在docker-compose.yml文件中设置PUID和PGID环境变量，以bookstack服务为例
services:
  bookstack:
    environment:
      - PUID=1000
      - PGID=1000
    volumes:
      - ./data:/app/data

3. 修改宿主机上的目录权限:
sudo chown -R 1000:1000 ./data

