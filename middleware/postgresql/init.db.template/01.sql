-- 创建数据库
CREATE DATABASE postgres;

-- 创建用户
CREATE USER app_user WITH PASSWORD 'app_password';

-- 授权
GRANT ALL PRIVILEGES ON DATABASE postgres TO app_user;

-- 安装 btree_gist 插件到默认数据库，是 PostgreSQL 的一个核心扩展，它为 GiST (Generalized Search Tree) 索引提供了对标准数据类型的支持。 
CREATE EXTENSION IF NOT EXISTS btree_gist;
-- 如果要安装到其他数据库test_db，需要先切换。查看是否安装，需要先登录数据库，然后执行 \dx
-- \c test_db
-- CREATE EXTENSION IF NOT EXISTS btree_gist;

