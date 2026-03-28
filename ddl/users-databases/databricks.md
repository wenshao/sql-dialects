# Databricks: 数据库、模式与用户管理

> 参考资料:
> - [Databricks Documentation - Unity Catalog](https://docs.databricks.com/en/data-governance/unity-catalog/index.html)
> - [Databricks SQL Reference - CREATE CATALOG / SCHEMA](https://docs.databricks.com/en/sql/language-manual/sql-ref-syntax-ddl-create-catalog.html)


## Databricks 命名层级（Unity Catalog）:

metastore > catalog > schema(database) > object
DATABASE 和 SCHEMA 是同义词
Unity Catalog 引入了 catalog 层

## 1. Catalog 管理（Unity Catalog）


```sql
CREATE CATALOG myapp;
CREATE CATALOG IF NOT EXISTS myapp;

CREATE CATALOG myapp
    COMMENT 'Main application catalog';
```


修改 catalog
```sql
ALTER CATALOG myapp SET OWNER TO `data_team`;
ALTER CATALOG myapp SET COMMENT = 'Updated comment';
```


删除 catalog
```sql
DROP CATALOG myapp;
DROP CATALOG IF EXISTS myapp CASCADE;
```


切换 catalog
```sql
USE CATALOG myapp;
```


查看 catalog
```sql
SHOW CATALOGS;
DESCRIBE CATALOG myapp;
```


## 2. Schema / Database 管理


```sql
CREATE SCHEMA myapp.myschema;
CREATE SCHEMA IF NOT EXISTS myapp.myschema;
CREATE DATABASE myapp.myschema;                 -- 同义词

CREATE SCHEMA myapp.myschema
    COMMENT 'Application schema'
    MANAGED LOCATION 's3://bucket/myschema'     -- 托管存储位置
    WITH DBPROPERTIES ('env' = 'prod');
```


修改 schema
```sql
ALTER SCHEMA myapp.myschema SET OWNER TO `data_team`;
ALTER SCHEMA myapp.myschema SET COMMENT = 'Updated';
ALTER SCHEMA myapp.myschema SET DBPROPERTIES ('env' = 'staging');
```


删除 schema
```sql
DROP SCHEMA myapp.myschema;
DROP SCHEMA IF EXISTS myapp.myschema CASCADE;
```


切换 schema
```sql
USE SCHEMA myapp.myschema;
USE myapp.myschema;
```


查看 schema
```sql
SHOW SCHEMAS IN myapp;
DESCRIBE SCHEMA myapp.myschema;
```


## 3. 用户和组管理（通过 SCIM / Identity Provider）


Databricks 用户通过以下方式管理：
1. SCIM API（与 IdP 同步）
2. Databricks Admin Console
3. Terraform provider
不通过 SQL 创建用户

## 4. 权限管理（Unity Catalog）


Catalog 权限
```sql
GRANT USE CATALOG ON CATALOG myapp TO `analysts`;
GRANT CREATE SCHEMA ON CATALOG myapp TO `data_engineers`;
GRANT ALL PRIVILEGES ON CATALOG myapp TO `admins`;
```


Schema 权限
```sql
GRANT USE SCHEMA ON SCHEMA myapp.myschema TO `analysts`;
GRANT CREATE TABLE ON SCHEMA myapp.myschema TO `data_engineers`;
```


表权限
```sql
GRANT SELECT ON TABLE myapp.myschema.users TO `analysts`;
GRANT MODIFY ON TABLE myapp.myschema.users TO `data_engineers`;
GRANT ALL PRIVILEGES ON TABLE myapp.myschema.users TO `admins`;
```


查看权限
```sql
SHOW GRANTS ON CATALOG myapp;
SHOW GRANTS ON SCHEMA myapp.myschema;
SHOW GRANTS ON TABLE myapp.myschema.users;
SHOW GRANTS TO `analysts`;
```


收回权限
```sql
REVOKE SELECT ON TABLE myapp.myschema.users FROM `analysts`;
```


## 5. 行级和列级安全


行过滤器
```sql
CREATE FUNCTION myapp.myschema.region_filter(region STRING)
RETURN IF(IS_MEMBER('managers'), TRUE, region = CURRENT_USER());

ALTER TABLE myapp.myschema.sales
SET ROW FILTER myapp.myschema.region_filter ON (region);
```


列掩码
```sql
CREATE FUNCTION myapp.myschema.mask_email(email STRING)
RETURN IF(IS_MEMBER('admins'), email, 'xxx@xxx.com');

ALTER TABLE myapp.myschema.users
ALTER COLUMN email SET MASK myapp.myschema.mask_email;
```


## 6. 查询元数据


```sql
SELECT current_catalog(), current_database(), current_user();

SHOW CATALOGS;
SHOW SCHEMAS IN myapp;
SHOW TABLES IN myapp.myschema;
```


information_schema
```sql
SELECT * FROM myapp.information_schema.catalogs;
SELECT * FROM myapp.information_schema.schemata;
SELECT * FROM myapp.information_schema.tables;
```


## 7. 旧版 Hive Metastore 模式


如果不使用 Unity Catalog（旧版方式）
命名层级: database > table（没有 catalog 层）
默认 catalog 为 hive_metastore
```sql
USE CATALOG hive_metastore;
CREATE DATABASE legacy_db;
```
