# Trino: 数据库与用户管理

> 参考资料:
> - [Trino Documentation - CREATE SCHEMA](https://trino.io/docs/current/sql/create-schema.html)
> - [Trino Documentation - Security](https://trino.io/docs/current/security.html)

**引擎定位**: 分布式查询引擎（前身 Presto），不存储数据。通过 Connector 查询异构数据源（Hive/Iceberg/RDBMS）。

## Trino 命名层级: catalog > schema > object

catalog 对应一个数据源连接（通过配置文件定义）
schema 通过 SQL 创建
没有 CREATE DATABASE / CREATE CATALOG（通过配置文件）
## Catalog 管理

Catalog 通过配置文件定义（非 SQL）
文件位置: etc/catalog/<catalog_name>.properties
例: etc/catalog/hive.properties
connector.name=hive
hive.metastore.uri=thrift://metastore:9083

Trino 433+ 支持动态 catalog（CREATE CATALOG）
```sql
CREATE CATALOG my_pg USING postgresql
WITH (
    "connection-url" = 'jdbc:postgresql://host:5432/mydb',
    "connection-user" = 'trino',
    "connection-password" = 'secret'
);                                              -- Trino 433+

DROP CATALOG my_pg;                             -- Trino 433+

```

查看 catalog
```sql
SHOW CATALOGS;

```

## Schema 管理


```sql
CREATE SCHEMA hive.myschema;
CREATE SCHEMA IF NOT EXISTS hive.myschema;

CREATE SCHEMA hive.myschema
WITH (location = 's3://bucket/myschema/');       -- Hive connector

```

删除 schema
```sql
DROP SCHEMA hive.myschema;
DROP SCHEMA IF EXISTS hive.myschema CASCADE;    -- Trino 若支持

```

切换默认 catalog 和 schema
```sql
USE hive.myschema;
USE hive;

```

查看 schema
```sql
SHOW SCHEMAS FROM hive;
SHOW SCHEMAS FROM hive LIKE 'my%';

```

## 用户与认证


Trino 用户通过以下方式管理（非 SQL）：
## LDAP 认证

## Kerberos 认证

## Password file 认证

## OAuth2 / JWT 认证

## Certificate 认证


配置文件: etc/password-authenticator.properties
password-authenticator.name=ldap
ldap.url=ldap://ldap-server:389

## 权限管理


Trino 支持两种授权模式：
## file-based（配置文件）

## sql-standard（SQL 标准方式）


SQL 标准授权
```sql
GRANT SELECT ON hive.myschema.users TO USER alice;
GRANT INSERT ON hive.myschema.users TO ROLE developer;
GRANT ALL PRIVILEGES ON hive.myschema.users TO USER admin;

```

角色管理
```sql
CREATE ROLE analyst IN hive;
GRANT ROLE analyst TO USER alice IN hive;
GRANT SELECT ON hive.myschema.users TO ROLE analyst;

SET ROLE analyst IN hive;
SET ROLE ALL IN hive;

SHOW ROLES FROM hive;
SHOW ROLE GRANTS FROM hive;

REVOKE SELECT ON hive.myschema.users FROM USER alice;
DROP ROLE analyst IN hive;

```

## 查询元数据


```sql
SHOW CATALOGS;
SHOW SCHEMAS FROM hive;
SHOW TABLES FROM hive.myschema;

SELECT current_catalog, current_schema, current_user;

```

查看连接器属性（系统表）
```sql
SELECT * FROM system.metadata.catalogs;
SELECT * FROM hive.information_schema.schemata;
SELECT * FROM hive.information_schema.tables;

```

## 系统访问控制（配置文件方式）


文件: etc/access-control.properties
access-control.name=file
security.config-file=etc/rules.json

rules.json 示例:
{
  "catalogs": [
    { "user": "admin", "catalog": ".*", "allow": "all" },
    { "user": "analyst", "catalog": "hive", "allow": "read-only" }
  ]
}
