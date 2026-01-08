
# 单实例启动

```bash

```

# 多实例启动

## 启动主节点

## 启动从节点
```bash
# 如果是在本地启动primary节点, 需要在/etc/hosts里面添加这行
127.0.0.1       mongo-primary

# 连接到主节点添加从节点
docker exec -it mongo-primary mongosh -u admin -p password

# 在 MongoDB shell 中执行：
rs.add("mongo-secondary:27017")
```
