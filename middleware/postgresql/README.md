# 启动数据库

## 设置首次启动的初始化命令（可选）

```shell
# 参考 init.db.template 目录里的文件写初始化脚本
mkdir init.db

# 添加要执行的sql语句（注意添加时按照序号依次递增）
vi init.db/01app-a.sql
vi init.db/02app-b.sql

# 需要说明的是，如果容器之前已经启动过，事后放入的脚本将不会执行，需要手动执行
# 如下命令
docker compose exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /docker-entrypoint-initdb.d/01app-a.sql
docker compose exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /docker-entrypoint-initdb.d/02app-b.sql
```

## 配置`.env`文件

```shell
cp .env.template .env
# 然后根据需要编辑 .env 文件，如果只是简单本地测试可以不用修改
```

`.env.template` 里的 `POSTGRES_DB` 只有一个值（例如 `postgres`），它只表示容器初始化时的默认数据库，不是各业务库映射配置，也不会自动为每个 SQL 文件分配不同数据库。

如果你需要 `01app-a.sql` 使用 `app_db_a`，`02app-b.sql` 使用 `app_db_b`，建议保留 `.env` 中的 `POSTGRES_DB=postgres` 作为默认库，然后在各自脚本中显式创建并切换数据库。

示例：

`init.db/01app-a.sql`

```sql
CREATE DATABASE app_db_a;
\c app_db_a
-- 这里写 app-a 的建表/初始化语句
```

`init.db/02app-b.sql`

```sql
CREATE DATABASE app_db_b;
\c app_db_b
-- 这里写 app-b 的建表/初始化语句
```

建议：不建议数据库名包含 `-`，推荐使用字母、数字和下划线（例如 `app_db_a`），这样在 SQL 中无需双引号，脚本更稳妥。

## 启动容器

```shell

docker compose up -d

# 如果需要重启
docker compose down -v && docker compose up -d

```

## 使用脚本创建业务库

```shell
./database.sh create-db -d app -u app_user
```

执行流程：

- 参考 `init.db.template/01.sql` 的结构，在 `init.db` 目录下生成新的 SQL 文件
- 如果 `init.db` 没有 SQL 文件，则从 `01` 开始；如果已有文件，则取当前最大序号加 1
- 例如已有 `01app.sql` 时，再创建 `bot` 数据库会生成 `init.db/02bot.sql`
- SQL 文件生成后，脚本会在容器内执行 `/docker-entrypoint-initdb.d/02bot.sql` 完成数据库创建

说明：

- `-u` 为必填参数
- 如果用户不存在，脚本会自动创建用户并输出随机密码
- 如果用户已存在，脚本会报错并提示更换用户名

## 常见问题

### 报错 `pq: database "app_db_a" does not exist`

这通常表示容器已启动，但业务库尚未创建。最常见原因是：`/var/lib/postgresql/data` 已有旧数据，导致 `init.db` 脚本没有再次执行。

```shell
# 查看现有数据库
docker compose exec postgres psql -U postgres -d postgres -c "\l"

# 手动创建业务库（一次即可）
docker compose exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c 'CREATE DATABASE app_db_a;'
docker compose exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c 'CREATE DATABASE app_db_b;'
```

如果你希望重新执行初始化脚本，请清理数据卷后重建：

```shell
docker compose down -v
rm -rf data
docker compose up -d
```

# 连接数据库

```shell
# 使用 docker exec
docker compose exec postgres psql -U postgres -d postgres

# 使用客户端工具
psql -h localhost -p 5432 -U postgres -d postgres
```

# 数据库常用命令

## 速查表
```text
命令            说明
\l              列出数据库
\c dbname       连接数据库
\dt             列出表
\dt *.*         列出所有 schema 的所有表
\dt app.*       列出所有 app schema 的所有表
\d table        查看表结构
\du             列出用户
\dn             列出 schema
\df             列出函数
\dv             列出视图
\di             列出索引
\x              切换显示模式
\timing         显示执行时间
\i file.sql     执行 SQL 文件
\o file         输出到文件
\q              退出
\?              帮助
```

# 安装插件

```shell
# 1. 登陆数据库
docker compose exec postgres psql -U postgres -d postgres

# 2. 创建数据库
create database test;

# 3. 切换数据库
\c test

# 4. 安装插件, 注意插件是数据库粒度，一定要确认当前所处的数据库
# btree_gist 为标准数据类型（int、text、timestamp等）提供 GiST索引 支持，让这些类型可以使用GiST索引的高级特性。
# 当你需要用排除约束防止数据重叠时，就需要 btree_gist，比如
# -- 示例：会议室预订，防止时间冲突
# CREATE TABLE bookings (
#     room_id int,
#     during tsrange,
#     EXCLUDE USING gist (
#         room_id WITH =,      -- 同一房间
#         during WITH &&       -- 时间段不能重叠
#     )
# );
create extension if not exists btree_gist;
```

# 备份和恢复

```shell
# 备份
docker compose exec -T postgres pg_dump -U postgres myapp > backup.sql

# 恢复
docker compose exec -T postgres psql -U postgres myapp < backup.sql

# 备份所有数据库
docker compose exec -T postgres pg_dumpall -U postgres > backup_all.sql
```
