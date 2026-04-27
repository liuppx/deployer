
# 容器里面检查端口是否打开

```shell
nc -zv host.docker.internal 5432
```

# 从容器内获取 host.docker.internal 的 IP 

```shell
docker run --rm alpine sh -c "getent hosts host.docker.internal | awk '{print \\$1}'"
```
