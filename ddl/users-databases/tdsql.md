# TDSQL（腾讯云分布式数据库）: 数据库、模式与用户管理

> 参考资料:
> - [TDSQL for MySQL Documentation](https://cloud.tencent.com/document/product/557)
> - [TDSQL-C (TDSQL Serverless) Documentation](https://cloud.tencent.com/document/product/1003)


TDSQL 兼容 MySQL 协议
DATABASE 和 SCHEMA 是同义词
命名层级: 集群(实例) > 数据库 > 对象


## 数据库管理


```sql
CREATE DATABASE myapp;
CREATE DATABASE IF NOT EXISTS myapp;

CREATE DATABASE myapp
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_general_ci;

ALTER DATABASE myapp DEFAULT CHARACTER SET utf8mb4;

DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp;

USE myapp;
SHOW DATABASES;
```

## TDSQL 分布式版特有: 指定分片

CREATE DATABASE myapp OPTIONS (SHARDKEY=auto);

## 用户管理


```sql
CREATE USER 'myuser'@'%' IDENTIFIED BY 'secret123';
CREATE USER IF NOT EXISTS 'myuser'@'%' IDENTIFIED BY 'secret123';

ALTER USER 'myuser'@'%' IDENTIFIED BY 'newsecret';
ALTER USER 'myuser'@'%' ACCOUNT LOCK;
ALTER USER 'myuser'@'%' ACCOUNT UNLOCK;

RENAME USER 'myuser'@'%' TO 'newuser'@'%';

DROP USER 'myuser'@'%';
DROP USER IF EXISTS 'myuser'@'%';
```

## 权限管理


```sql
GRANT ALL PRIVILEGES ON *.* TO 'myuser'@'%' WITH GRANT OPTION;
GRANT SELECT, INSERT, UPDATE, DELETE ON myapp.* TO 'myuser'@'%';
GRANT SELECT ON myapp.users TO 'myuser'@'%';

SHOW GRANTS FOR 'myuser'@'%';

REVOKE INSERT ON myapp.* FROM 'myuser'@'%';
REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'myuser'@'%';

FLUSH PRIVILEGES;
```

## 查询元数据


```sql
SELECT DATABASE(), USER(), CURRENT_USER();

SHOW DATABASES;
SELECT user, host, account_locked FROM mysql.user;
SELECT schema_name FROM information_schema.schemata;
```

TDSQL 特有: 查看分片信息
SHOW SHARDS;
SHOW TABLE STATUS;
注意：TDSQL 有多个版本
TDSQL for MySQL（分布式版）
TDSQL-C for MySQL（云原生版，兼容 Aurora）
TDSQL for PostgreSQL（分布式版）
MySQL 版本语法与 MySQL 完全兼容
PostgreSQL 版本语法与 PostgreSQL 完全兼容
