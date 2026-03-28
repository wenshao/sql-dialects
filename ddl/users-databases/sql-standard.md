# SQL 标准: 数据库、模式与用户管理

> 参考资料:
> - [ISO/IEC 9075-1:2023 SQL Standard - Schema definition](https://www.iso.org/standard/76583.html)
> - [SQL:2016 / SQL:2023 - Catalog, Schema, Authorization](https://en.wikipedia.org/wiki/SQL:2016)

## 1. SQL 标准中的命名层级: Catalog > Schema > Object

catalog_name.schema_name.object_name
例: mydb.public.users

## 2. CREATE SCHEMA（SQL-92 引入）

```sql
CREATE SCHEMA my_schema;
```

```sql
CREATE SCHEMA my_schema AUTHORIZATION my_user;
```

带对象定义的 schema 创建
```sql
CREATE SCHEMA my_schema
    CREATE TABLE t1 (id INTEGER PRIMARY KEY)
    CREATE VIEW v1 AS SELECT * FROM t1;
```

## 3. DROP SCHEMA

```sql
DROP SCHEMA my_schema;                          -- 必须为空
DROP SCHEMA my_schema CASCADE;                  -- 级联删除所有对象
DROP SCHEMA my_schema RESTRICT;                 -- 非空则报错（默认）
```

## 4. SET SCHEMA（标准语法）

```sql
SET SCHEMA 'my_schema';                         -- SQL 标准方式
```

## 5. CREATE / DROP DATABASE

- **注意：SQL 标准中没有 CREATE DATABASE 语句**
DATABASE 的概念属于各实现的扩展
标准中 catalog 最接近 database 的概念

## 6. 用户与授权（SQL 标准）

SQL 标准定义了 AUTHORIZATION IDENTIFIER 概念
但具体的 CREATE USER 是各实现的扩展

权限管理（SQL-92 引入）
```sql
GRANT SELECT, INSERT ON my_schema.t1 TO some_user;
GRANT ALL PRIVILEGES ON my_schema.t1 TO some_user;
GRANT SELECT ON my_schema.t1 TO PUBLIC;
```

```sql
REVOKE INSERT ON my_schema.t1 FROM some_user;
```

角色（SQL:1999 引入）
```sql
CREATE ROLE analyst;
GRANT SELECT ON my_schema.t1 TO analyst;
GRANT analyst TO some_user;
DROP ROLE analyst;
```

## 7. 信息模式（INFORMATION_SCHEMA，SQL-92 引入）

查询所有 schema
```sql
SELECT schema_name
FROM information_schema.schemata;
```

查询所有表
```sql
SELECT table_schema, table_name
FROM information_schema.tables;
```

查询所有列
```sql
SELECT table_schema, table_name, column_name, data_type
FROM information_schema.columns;
```

## 总结：SQL 标准 vs 各实现

- SQL 标准定义了 catalog.schema.object 三层命名
- CREATE DATABASE 不在标准中，是各厂商扩展
- CREATE USER 不在标准中，标准只定义了 AUTHORIZATION
- CREATE ROLE 在 SQL:1999 标准中引入
- GRANT / REVOKE 在 SQL-92 中引入
- INFORMATION_SCHEMA 在 SQL-92 中引入
