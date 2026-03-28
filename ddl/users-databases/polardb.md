# PolarDB: 数据库、模式与用户管理

> 参考资料:
> - [PolarDB for PostgreSQL Documentation](https://www.alibabacloud.com/help/en/polardb-for-postgresql/)
> - [PolarDB for MySQL Documentation](https://www.alibabacloud.com/help/en/polardb-for-mysql/)


PolarDB 有两个版本：
PolarDB for MySQL: 兼容 MySQL
PolarDB for PostgreSQL: 兼容 PostgreSQL
以下分别展示两个版本的语法


## PolarDB for MySQL


## 数据库管理

```sql
CREATE DATABASE myapp;
CREATE DATABASE IF NOT EXISTS myapp
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_unicode_ci;

ALTER DATABASE myapp DEFAULT CHARACTER SET utf8mb4;

DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp;

USE myapp;
SHOW DATABASES;
```

## 用户管理

```sql
CREATE USER 'myuser'@'%' IDENTIFIED BY 'secret123';

ALTER USER 'myuser'@'%' IDENTIFIED BY 'newsecret';
ALTER USER 'myuser'@'%' ACCOUNT LOCK;
ALTER USER 'myuser'@'%' ACCOUNT UNLOCK;

DROP USER 'myuser'@'%';
```

## 权限管理

```sql
GRANT ALL PRIVILEGES ON myapp.* TO 'myuser'@'%';
GRANT SELECT ON myapp.users TO 'myuser'@'%';

SHOW GRANTS FOR 'myuser'@'%';
REVOKE ALL PRIVILEGES ON myapp.* FROM 'myuser'@'%';
FLUSH PRIVILEGES;
```

## PolarDB for MySQL 特有: 全局一致性读

SET GLOBAL innodb_global_consistent_read = ON;

## PolarDB for PostgreSQL


## 数据库管理

```sql
CREATE DATABASE myapp
    OWNER = myuser
    ENCODING = 'UTF8'
    TEMPLATE = template0;

ALTER DATABASE myapp SET timezone TO 'Asia/Shanghai';
ALTER DATABASE myapp OWNER TO newowner;

DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp;
```

## 模式管理

```sql
CREATE SCHEMA myschema;
CREATE SCHEMA IF NOT EXISTS myschema AUTHORIZATION myuser;

DROP SCHEMA myschema CASCADE;

SET search_path TO myschema, public;
```

## 用户管理

```sql
CREATE USER myuser WITH PASSWORD 'Secret123!';
CREATE ROLE analyst NOLOGIN;

ALTER USER myuser WITH PASSWORD 'NewSecret456!';
DROP USER myuser;
```

## 权限管理

```sql
GRANT CONNECT ON DATABASE myapp TO myuser;
GRANT USAGE ON SCHEMA myschema TO analyst;
GRANT SELECT ON ALL TABLES IN SCHEMA myschema TO analyst;

ALTER DEFAULT PRIVILEGES IN SCHEMA myschema
    GRANT SELECT ON TABLES TO analyst;

REVOKE ALL ON SCHEMA myschema FROM myuser;
GRANT analyst TO myuser;
```

## 查询元数据


## PolarDB for MySQL

```sql
SELECT DATABASE(), USER(), CURRENT_USER();
```

## PolarDB for PostgreSQL

```sql
SELECT current_database(), current_schema(), current_user;
```

## PolarDB 实例管理通过阿里云控制台

集群管理、读写分离、全球数据库网络等通过控制台操作
