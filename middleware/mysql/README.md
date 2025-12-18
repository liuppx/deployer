
如何启动mysql容器？

第一步：创建环境变量，并修改配置
mv .env.template .env 

第二步：在目录`init.db`中，添加初始化脚本，可以是创建数据库，以及授权给某个用户

第三步：启动容器
docker compose up -d
# 设置初始化语句

1. 基于模版创建

```shell
cp -rf init.db.template init.db
```

2. 修改`01.sql`，或者新建`02.sql`

# 数据库常用操作

1. 进入容器
```bash
docker compose exec <service name, mysql> bash
# 或者
docker exec -it <container id> bash
```

2. 登录，以root用户登录

```bash
mysql -h localhost -u root -p
```

3. 建库，例如建库bookstack

```text
create database bookstack;
```

4. 创建用户，用户名和密码都是`yeying`

create user if not exists 'yeying'@'%' identified with caching_sha2_password BY 'yeying';

4. 授权，授权数据库`bookstack`给用户`yiying`

```text
grant all privileges on bookstack.* to 'yeying'@'%';
```

5. 查看数据库的所有者

```text
select * from information_schema.SCHEMA_PRIVILEGES;
```

5. 查看数据库的用户

```text
SELECT user, host FROM mysql.user;
```
