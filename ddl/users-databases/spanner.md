# Spanner: 数据库与用户管理

> 参考资料:
> - [Cloud Spanner Documentation - DDL](https://cloud.google.com/spanner/docs/reference/standard-sql/data-definition-language)
> - [Cloud Spanner Documentation - IAM](https://cloud.google.com/spanner/docs/iam)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

## Spanner 命名层级: project > instance > database > schema > object

instance 和 database 通过 API/CLI 创建
schema 通过 DDL 创建（PostgreSQL 接口模式）
权限通过 GCP IAM 管理
## 实例和数据库管理（gcloud CLI）

创建实例
$ gcloud spanner instances create my-instance \
    --config=regional-us-central1 \
    --description="My Instance" \
    --processing-units=100

创建数据库
$ gcloud spanner databases create mydb --instance=my-instance

删除数据库
$ gcloud spanner databases delete mydb --instance=my-instance

不支持 SQL 的 CREATE DATABASE / DROP DATABASE

## Schema 管理（PostgreSQL 接口）


Spanner PostgreSQL 接口支持 schema
```sql
CREATE SCHEMA myschema;

DROP SCHEMA myschema;

```

GoogleSQL 接口不使用 schema 概念
所有表在同一命名空间下

## 用户与权限（IAM，非 SQL）


Spanner 使用 GCP IAM 管理权限
常用角色：
- roles/spanner.databaseReader  -- 读取
- roles/spanner.databaseUser    -- 读写
- roles/spanner.databaseAdmin   -- 管理
- roles/spanner.admin           -- 实例管理

gcloud CLI 授权：
$ gcloud spanner databases add-iam-policy-binding mydb \
    --instance=my-instance \
    --member="user:alice@example.com" \
    --role="roles/spanner.databaseReader"

## 细粒度访问控制（FGAC）


数据库角色（Spanner 特有的 FGAC）
```sql
CREATE ROLE analyst;
CREATE ROLE developer;

```

授予表权限
```sql
GRANT SELECT ON TABLE users TO ROLE analyst;
GRANT INSERT, UPDATE, DELETE ON TABLE users TO ROLE developer;
GRANT SELECT ON ALL TABLES IN SCHEMA myschema TO ROLE analyst;  -- PostgreSQL 接口

```

查看权限
通过 INFORMATION_SCHEMA
```sql
SELECT * FROM INFORMATION_SCHEMA.TABLE_PRIVILEGES;

```

授予角色给 IAM 成员（通过 gcloud）
$ gcloud spanner databases add-iam-policy-binding mydb \
    --instance=my-instance \
    --member="user:alice@example.com" \
    --role="roles/spanner.databaseRoleUser" \
    --condition="expression=resource.name.endsWith('/databaseRoles/analyst')"

删除角色
```sql
REVOKE SELECT ON TABLE users FROM ROLE analyst;
DROP ROLE analyst;

```

## Change Streams（变更流）


监控数据变更（Spanner 特有）
```sql
CREATE CHANGE STREAM user_changes
    FOR users;

CREATE CHANGE STREAM all_changes
    FOR ALL;

DROP CHANGE STREAM user_changes;

```

## 查询元数据


数据库信息
```sql
SELECT * FROM INFORMATION_SCHEMA.SCHEMATA;
SELECT * FROM INFORMATION_SCHEMA.TABLES;
SELECT * FROM INFORMATION_SCHEMA.COLUMNS;

```

数据库角色
```sql
SELECT * FROM INFORMATION_SCHEMA.ROLES;         -- PostgreSQL 接口

```

变更流
```sql
SELECT * FROM INFORMATION_SCHEMA.CHANGE_STREAMS;

```

**注意:** Spanner 不支持 CREATE USER、USE database
一个连接对应一个数据库
权限完全通过 IAM + 数据库角色管理
