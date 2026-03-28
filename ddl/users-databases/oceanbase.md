# OceanBase: 数据库与用户管理

> 参考资料:
> - [OceanBase Documentation - CREATE DATABASE (MySQL 模式)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)
> - [OceanBase Documentation - CREATE USER](https://www.oceanbase.com/docs/common-oceanbase-database-cn)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

## OceanBase 支持两种兼容模式：

- MySQL 模式: 同 MySQL 语法
- Oracle 模式: 同 Oracle 语法
命名层级:
  集群 > 租户(Tenant) > 数据库/模式 > 对象
租户管理（系统租户下执行）
租户(Tenant)是 OceanBase 的多租户隔离单元
类似于一个独立的数据库实例

```sql
CREATE TENANT my_tenant
    RESOURCE_POOL_LIST = ('pool1')
    SET ob_tcp_invited_nodes = '%',
        ob_compatibility_mode = 'mysql';        -- 或 'oracle'

ALTER TENANT my_tenant SET RESOURCE_POOL_LIST = ('pool2');

DROP TENANT my_tenant;
DROP TENANT my_tenant FORCE;

```

## MySQL 模式


## 数据库管理

```sql
CREATE DATABASE myapp;
CREATE DATABASE IF NOT EXISTS myapp
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_general_ci;

ALTER DATABASE myapp DEFAULT CHARACTER SET utf8mb4;

DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp;

USE myapp;
SHOW DATABASES;

```

## 用户管理

```sql
CREATE USER 'myuser'@'%' IDENTIFIED BY 'secret123';
CREATE USER IF NOT EXISTS 'myuser'@'%' IDENTIFIED BY 'secret123';

ALTER USER 'myuser'@'%' IDENTIFIED BY 'newsecret';
ALTER USER 'myuser'@'%' ACCOUNT LOCK;
ALTER USER 'myuser'@'%' ACCOUNT UNLOCK;

DROP USER 'myuser'@'%';

```

## 角色管理

```sql
CREATE ROLE analyst;
GRANT analyst TO 'myuser'@'%';
SET DEFAULT ROLE analyst TO 'myuser'@'%';
REVOKE analyst FROM 'myuser'@'%';
DROP ROLE analyst;

```

## 权限管理

```sql
GRANT ALL PRIVILEGES ON *.* TO 'myuser'@'%';
GRANT SELECT, INSERT ON myapp.* TO 'myuser'@'%';
GRANT SELECT ON myapp.users TO 'myuser'@'%';

SHOW GRANTS FOR 'myuser'@'%';
REVOKE INSERT ON myapp.* FROM 'myuser'@'%';
FLUSH PRIVILEGES;

```

## Oracle 模式


1. 用户/模式管理（用户=模式，同 Oracle）
CREATE USER myuser IDENTIFIED BY "secret123"
    DEFAULT TABLESPACE obdefault
    QUOTA UNLIMITED ON obdefault;

ALTER USER myuser IDENTIFIED BY "newsecret";
ALTER USER myuser ACCOUNT LOCK;
DROP USER myuser CASCADE;

ALTER SESSION SET CURRENT_SCHEMA = myuser;

## 权限管理

GRANT CREATE SESSION TO myuser;
GRANT SELECT ON hr.employees TO myuser;
GRANT DBA TO myuser;
REVOKE CREATE SESSION FROM myuser;

## 查询元数据


MySQL 模式
```sql
SELECT DATABASE(), USER(), CURRENT_USER();
SELECT * FROM information_schema.schemata;

```

OceanBase 特有视图
```sql
SELECT * FROM oceanbase.DBA_OB_TENANTS;
SELECT * FROM oceanbase.DBA_OB_RESOURCE_POOLS;
SELECT * FROM oceanbase.DBA_OB_ZONES;

```
