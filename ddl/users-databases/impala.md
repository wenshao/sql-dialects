# Impala: 数据库、模式与用户管理

> 参考资料:
> - [Impala Documentation - CREATE DATABASE](https://impala.apache.org/docs/build/html/topics/impala_create_database.html)
> - [Impala Documentation - Authorization](https://impala.apache.org/docs/build/html/topics/impala_authorization.html)


## Impala 与 Hive 共享 Metastore

DATABASE 和 SCHEMA 是同义词
命名层级: database(schema) > table
默认数据库: default

## 1. 数据库管理


```sql
CREATE DATABASE myapp;
CREATE DATABASE IF NOT EXISTS myapp;

CREATE DATABASE myapp
    COMMENT 'Main application database'
    LOCATION '/user/impala/warehouse/myapp.db';
```


SCHEMA 是同义词
```sql
CREATE SCHEMA myapp;
```


修改数据库
```sql
ALTER DATABASE myapp SET OWNER USER alice;
ALTER DATABASE myapp SET OWNER ROLE analyst;
```


删除数据库
```sql
DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp;
DROP DATABASE myapp CASCADE;                    -- 级联删除所有表
```


切换数据库
```sql
USE myapp;

SHOW DATABASES;
SHOW DATABASES LIKE 'my*';
DESCRIBE DATABASE myapp;
```


## 2. 用户管理


Impala 不创建用户
用户由 OS / Kerberos / LDAP 管理
权限通过 Ranger 或 Sentry 管理

## 3. 角色管理（需要 Sentry 或 Ranger）


```sql
CREATE ROLE analyst;
CREATE ROLE developer;

GRANT ROLE analyst TO GROUP analyst_group;      -- 授予操作系统/LDAP 组

SHOW ROLES;
SHOW CURRENT ROLES;
SHOW ROLE GRANT GROUP analyst_group;

REVOKE ROLE analyst FROM GROUP analyst_group;
DROP ROLE analyst;
```


## 4. 权限管理


服务器权限
```sql
GRANT ALL ON SERVER TO ROLE admin;
```


数据库权限
```sql
GRANT ALL ON DATABASE myapp TO ROLE developer;
GRANT SELECT ON DATABASE myapp TO ROLE analyst;
```


表权限
```sql
GRANT SELECT ON TABLE myapp.users TO ROLE analyst;
GRANT INSERT ON TABLE myapp.users TO ROLE developer;
GRANT ALL ON TABLE myapp.users TO ROLE admin;
```


列权限
```sql
GRANT SELECT (id, username) ON TABLE myapp.users TO ROLE analyst;
```


URI 权限（访问 HDFS 路径）
```sql
GRANT ALL ON URI 'hdfs:///data/myapp/' TO ROLE developer;
```


查看权限
```sql
SHOW GRANT ROLE analyst;
SHOW GRANT ROLE analyst ON DATABASE myapp;
```


收回
```sql
REVOKE SELECT ON TABLE myapp.users FROM ROLE analyst;
```


## 5. 查询元数据


```sql
SELECT current_database();

SHOW DATABASES;
SHOW TABLES IN myapp;
DESCRIBE DATABASE myapp;
```


Impala 使用 Hive Metastore
在 Impala 中创建的数据库也能在 Hive 中看到
刷新元数据：
```sql
INVALIDATE METADATA;                            -- 全量刷新
INVALIDATE METADATA myapp.users;                -- 指定表
REFRESH myapp.users;                            -- 刷新数据（不刷新结构）
```
