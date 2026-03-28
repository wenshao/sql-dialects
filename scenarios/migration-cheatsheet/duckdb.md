# DuckDB: 迁移速查表

> 参考资料:
> - [DuckDB Documentation](https://duckdb.org/docs/)
> - [DuckDB SQL Reference](https://duckdb.org/docs/sql/introduction)

**引擎定位**: 嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法。

## 一、从其他数据库迁移到 DuckDB

数据类型: INT→INTEGER, BIGINT→BIGINT, FLOAT→FLOAT, DOUBLE→DOUBLE,
          VARCHAR→VARCHAR, TEXT→VARCHAR, DECIMAL→DECIMAL(p,s),
          BOOLEAN→BOOLEAN, DATE→DATE, TIMESTAMP→TIMESTAMP,
          BLOB→BLOB, JSON→JSON, ARRAY→T[](原生数组),
          STRUCT→STRUCT, MAP→MAP
函数: IFNULL→IFNULL/COALESCE, NOW()→NOW()/CURRENT_TIMESTAMP,
       CONCAT→CONCAT或||, GROUP_CONCAT→STRING_AGG或LIST_AGG,
       DATEDIFF→DATE_DIFF, DATE_ADD→DATE_ADD或+INTERVAL
陷阱: 嵌入式数据库(无客户端-服务器模式), 面向 OLAP,
       可直接读取 CSV/Parquet/JSON 文件, 支持 PostgreSQL 语法,
       LIST 类型(PostgreSQL ARRAY 的超集), STRUCT 原生支持

二、自增: CREATE TABLE t (id INTEGER PRIMARY KEY);  -- ROWID 自动分配
三、日期: SELECT NOW(); SELECT CURRENT_DATE;
          SELECT CURRENT_DATE + INTERVAL 1 DAY;
          SELECT DATE_DIFF('day', DATE '2024-01-01', DATE '2024-12-31');
四、字符串: LENGTH, UPPER, LOWER, TRIM, SUBSTRING(s,start,len),
           REPLACE, POSITION(sub IN s), ||, STRING_AGG, STRING_SPLIT

## 五、数据类型映射（从 PostgreSQL/MySQL 到 DuckDB）

PostgreSQL → DuckDB: 高度兼容
  INTEGER → INTEGER, TEXT → VARCHAR, SERIAL → 不直接支持,
  BOOLEAN → BOOLEAN, JSONB → JSON,
  ARRAY → T[] (原生数组), BYTEA → BLOB,
  TIMESTAMPTZ → TIMESTAMPTZ, NUMERIC → DECIMAL,
  UUID → UUID
MySQL → DuckDB:
  INT → INTEGER, BIGINT → BIGINT, FLOAT → FLOAT,
  DOUBLE → DOUBLE, DECIMAL(p,s) → DECIMAL(p,s),
  VARCHAR(n) → VARCHAR, TEXT → VARCHAR,
  DATETIME → TIMESTAMP, DATE → DATE,
  BOOLEAN → BOOLEAN, JSON → JSON,
  AUTO_INCREMENT → 不直接支持,
  BLOB → BLOB, ENUM → ENUM (DuckDB 支持)

六、函数等价映射
MySQL → DuckDB:
  IFNULL → IFNULL/COALESCE, NOW() → NOW(),
  DATE_FORMAT → strftime, CONCAT → CONCAT/||,
  GROUP_CONCAT → STRING_AGG/LIST_AGG,
  LIMIT → LIMIT, STR_TO_DATE → strptime

七、常见陷阱补充
  嵌入式数据库（无客户端-服务器模式）
  面向 OLAP（不适合高并发 OLTP）
  可直接读取 CSV/Parquet/JSON 文件
  兼容 PostgreSQL 语法（大部分）
  LIST 类型（PostgreSQL ARRAY 的超集）
  STRUCT、MAP 原生支持
  支持窗口函数的 QUALIFY 子句
  httpfs 扩展可读取远程文件 (S3/HTTP)

八、NULL 处理
IFNULL(a, b); COALESCE(a, b, c);
NULLIF(a, b);
IS DISTINCT FROM / IS NOT DISTINCT FROM

九、分页语法
SELECT * FROM t ORDER BY id LIMIT 10 OFFSET 20;

十、直接文件查询
SELECT * FROM 'data.csv';
SELECT * FROM 'data.parquet';
SELECT * FROM read_json_auto('data.json');
