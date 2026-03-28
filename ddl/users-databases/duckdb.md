# DuckDB: 数据库与用户管理

> 参考资料:
> - [DuckDB Documentation - ATTACH](https://duckdb.org/docs/sql/statements/attach)
> - [DuckDB Documentation - CREATE SCHEMA](https://duckdb.org/docs/sql/statements/create_schema)

**引擎定位**: 嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法。

## DuckDB 特性：

- 嵌入式分析型数据库（类似 SQLite）
- 支持内存数据库和文件数据库
- 通过 ATTACH 管理多个数据库
- 没有用户/角色/权限管理
- 命名层级: database > schema > object
## 数据库管理

命令行创建数据库
$ duckdb myapp.duckdb

ATTACH 附加数据库（DuckDB 0.7.0+）
```sql
ATTACH 'myapp.duckdb' AS myapp;
ATTACH 'other.duckdb' AS other (READ_ONLY);
ATTACH ':memory:' AS memdb;

```

附加其他格式的数据库
```sql
ATTACH 'mydata.db' AS sqlitedb (TYPE SQLITE);  -- 附加 SQLite 数据库
ATTACH 'data.parquet' AS pq;                   -- 附加 Parquet（需要扩展）

```

ATTACH PostgreSQL（需要 postgres 扩展）
INSTALL postgres;
LOAD postgres;
ATTACH 'dbname=mydb' AS pg (TYPE POSTGRES);

ATTACH MySQL（需要 mysql 扩展）
INSTALL mysql;
LOAD mysql;
ATTACH 'host=localhost database=mydb user=root' AS my (TYPE MYSQL);

分离数据库
```sql
DETACH myapp;

```

切换默认数据库和模式
```sql
USE myapp;
USE myapp.myschema;

```

## 模式管理


```sql
CREATE SCHEMA myschema;
CREATE SCHEMA IF NOT EXISTS myschema;
CREATE SCHEMA myapp.myschema;                   -- 指定数据库

```

删除模式
```sql
DROP SCHEMA myschema;
DROP SCHEMA IF EXISTS myschema CASCADE;

```

默认模式为 main

## 用户与权限


DuckDB 没有内建的用户/角色/权限管理
它是嵌入式数据库，安全性依赖：
## 文件系统权限

## 应用层访问控制

## READ_ONLY 模式限制写入


只读方式打开
$ duckdb myapp.duckdb -readonly

## 数据库设置


内存限制
```sql
SET memory_limit = '4GB';

```

线程数
```sql
SET threads = 4;

```

临时目录
```sql
SET temp_directory = '/tmp/duckdb_temp';

```

默认排序规则
SET default_collation = 'nocase';

查看所有设置
```sql
SELECT * FROM duckdb_settings();

```

## 查询元数据


列出数据库
```sql
SELECT * FROM duckdb_databases();

```

列出模式
```sql
SELECT * FROM duckdb_schemas();
SELECT schema_name FROM information_schema.schemata;

```

列出表
```sql
SELECT * FROM duckdb_tables();
SELECT table_schema, table_name FROM information_schema.tables;

```

当前数据库和模式
```sql
SELECT current_database(), current_schema();

```

DuckDB 版本
```sql
SELECT version();

```

## 扩展管理（DuckDB 特色）


安装和加载扩展
```sql
INSTALL httpfs;                                 -- HTTP/S3 访问
LOAD httpfs;

INSTALL parquet;                                -- Parquet 支持（默认内置）
INSTALL json;                                   -- JSON 支持
INSTALL icu;                                    -- 国际化排序

```

查看已安装扩展
```sql
SELECT * FROM duckdb_extensions();

```

设置 S3 凭据
```sql
SET s3_region = 'us-east-1';
SET s3_access_key_id = 'your_key';
SET s3_secret_access_key = 'your_secret';

```

直接查询远程文件
```sql
SELECT * FROM read_parquet('s3://bucket/data.parquet');
SELECT * FROM read_csv('https://example.com/data.csv');

```

## 总结

DuckDB 是嵌入式 OLAP 数据库
一个数据库 = 一个文件（或内存）
通过 ATTACH 管理多个数据库（包括外部 PostgreSQL/MySQL/SQLite）
没有用户/角色/权限管理
支持丰富的扩展生态
