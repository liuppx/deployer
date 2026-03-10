# 环境变量配置

在当前目录创建 `.env` 文件，并配置 Redis 密码：

```bash
REDIS_PASSWORD=YourStrongPassword123!
```

然后启动服务：

```bash
docker compose up -d
```

使用密码连接 Redis：

```bash
docker compose exec redis redis-cli -a "$REDIS_PASSWORD"
```

# Redis 集群可用性测试

在 `.env` 中配置：

```bash
REDIS_PASSWORD=YourStrongPassword123!
# 可选，默认 127.0.0.1:6379
REDIS_NODES=127.0.0.1:6379,127.0.0.1:6380,127.0.0.1:6381
# 可选，默认 auto（优先本地 redis-cli，不存在则使用 docker compose exec）
REDIS_CLI_MODE=auto
# 可选，默认 auto（自动识别 cluster/standalone）
REDIS_EXPECT_MODE=auto
```

说明：
- 当前这个目录下的 `docker-compose.yml` 是单机 Redis，不是 Redis Cluster。
- 若你要“必须是集群才通过”，设置 `REDIS_EXPECT_MODE=cluster`。
- 若单机和集群都可接受，保持默认 `REDIS_EXPECT_MODE=auto`。

执行测试脚本：

```bash
chmod +x ./test-redis-cluster.sh
./test-redis-cluster.sh
```


# 登陆redis容器

docker compose exec redis sh

# 命令行模式
redis-cli

# 数据库操作
select 0                            # 切换数据库
flushdb                             # 清空当前数据库
flushall                            # 清空所有数据库
dbsize                              # 当前数据库键数量

# 查看键
keys *                              # 查看所有键（生产环境慎用）
keys user:*                         # 查看匹配模式的键
scan 0 match user:* count 100       # 安全地扫描键
exists mykey                        # 检查键是否存在
type mykey                          # 查看键的数据类型

# 字符串操作
get mykey   			    # 获取单个键的值
mget key1 key2 key3 		    # 获取多个键的值
getrange mykey 0 4  		    # 获取索引0到4的字符
