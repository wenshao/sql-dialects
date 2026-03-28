# TiDB: 数据库与用户管理

> 参考资料:
> - [TiDB Documentation - CREATE DATABASE](https://docs.pingcap.com/tidb/stable/sql-statement-create-database)
> - [TiDB Documentation - CREATE USER](https://docs.pingcap.com/tidb/stable/sql-statement-create-user)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

## TiDB 兼容 MySQL 协议

DATABASE 和 SCHEMA 是同义词（同 MySQL）
命名层级: cluster > database(schema) > object
## 数据库管理

```sql
CREATE DATABASE myapp;
CREATE DATABASE IF NOT EXISTS myapp;

CREATE DATABASE myapp
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_general_ci;

```

TiDB 特有: Placement Rules（数据放置规则）
```sql
CREATE DATABASE myapp
    PLACEMENT POLICY = tiflash_policy;          -- TiDB 6.0+

```

修改数据库
```sql
ALTER DATABASE myapp CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
ALTER DATABASE myapp PLACEMENT POLICY = new_policy;

```

删除数据库
```sql
DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp;

```

切换数据库
```sql
USE myapp;

SHOW DATABASES;

```

## 用户管理（兼容 MySQL）


```sql
CREATE USER 'myuser'@'%' IDENTIFIED BY 'secret123';
CREATE USER IF NOT EXISTS 'myuser'@'%' IDENTIFIED BY 'secret123';

```

认证插件
```sql
CREATE USER 'myuser'@'%' IDENTIFIED WITH mysql_native_password BY 'secret123';
CREATE USER 'myuser'@'%' IDENTIFIED WITH auth_token;  -- Token 认证（TiDB Cloud）

```

资源组绑定（TiDB 7.1+）
```sql
CREATE USER 'myuser'@'%' IDENTIFIED BY 'secret123'
    RESOURCE GROUP rg_oltp;

```

修改用户
```sql
ALTER USER 'myuser'@'%' IDENTIFIED BY 'newsecret';
ALTER USER 'myuser'@'%' ACCOUNT LOCK;
ALTER USER 'myuser'@'%' ACCOUNT UNLOCK;
ALTER USER 'myuser'@'%' PASSWORD EXPIRE;
ALTER USER 'myuser'@'%' RESOURCE GROUP rg_batch;

RENAME USER 'myuser'@'%' TO 'newuser'@'%';

```

删除用户
```sql
DROP USER 'myuser'@'%';

```

## 角色管理


```sql
CREATE ROLE 'analyst', 'developer';

GRANT 'analyst' TO 'myuser'@'%';
SET DEFAULT ROLE 'analyst' TO 'myuser'@'%';

SET ROLE 'analyst';
SET ROLE ALL;

REVOKE 'analyst' FROM 'myuser'@'%';
DROP ROLE 'analyst';

```

## 权限管理


```sql
GRANT ALL PRIVILEGES ON *.* TO 'myuser'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON myapp.* TO 'myuser'@'%';
GRANT SELECT ON myapp.users TO 'myuser'@'%';

```

TiDB 动态权限（5.1+）
```sql
GRANT BACKUP_ADMIN TO 'myuser'@'%';
GRANT RESTORE_ADMIN TO 'myuser'@'%';
GRANT RESOURCE_GROUP_ADMIN TO 'myuser'@'%';

SHOW GRANTS FOR 'myuser'@'%';
REVOKE INSERT ON myapp.* FROM 'myuser'@'%';

FLUSH PRIVILEGES;

```

## 资源控制（TiDB 7.1+）


```sql
CREATE RESOURCE GROUP rg_oltp
    RU_PER_SEC = 1000                           -- 每秒请求单元
    PRIORITY = HIGH
    BURSTABLE;

CREATE RESOURCE GROUP rg_batch
    RU_PER_SEC = 500
    PRIORITY = LOW;

ALTER RESOURCE GROUP rg_oltp RU_PER_SEC = 2000;
DROP RESOURCE GROUP rg_batch;

```

## Placement Rules（数据放置）


创建放置策略
```sql
CREATE PLACEMENT POLICY tiflash_policy
    LEARNERS = 1                                -- TiFlash 副本
    LEARNER_CONSTRAINTS = '[+engine=tiflash]';

CREATE PLACEMENT POLICY region_cn
    PRIMARY_REGION = 'cn-east-1'
    REGIONS = 'cn-east-1,cn-west-1';

```

应用到数据库
```sql
ALTER DATABASE myapp PLACEMENT POLICY = tiflash_policy;

DROP PLACEMENT POLICY tiflash_policy;

```

## 查询元数据


```sql
SELECT DATABASE(), USER(), CURRENT_USER();

SELECT * FROM information_schema.schemata;
SELECT user, host, account_locked FROM mysql.user;

```

TiDB 特有
```sql
SELECT * FROM information_schema.cluster_info;
SELECT * FROM information_schema.resource_groups;
SELECT * FROM information_schema.placement_policies;

```
