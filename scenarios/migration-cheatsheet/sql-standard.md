# SQL 标准: 迁移速查表

> 参考资料:
> - ISO/IEC 9075 SQL Standard
> - SQL:1999, SQL:2003, SQL:2008, SQL:2011, SQL:2016, SQL:2023

## SQL 标准版本与主要引入特性

SQL:1992  基础SQL（SELECT, JOIN, UNION, 子查询）
SQL:1999  递归CTE, OLAP函数(窗口函数), 正则, BOOLEAN, ARRAY
SQL:2003  MERGE, 窗口函数扩展, SEQUENCE, IDENTITY, MULTISET
SQL:2006  XML支持（SQL/XML）
SQL:2008  TRUNCATE, FETCH FIRST, INSTEAD OF trigger
SQL:2011  时态表(temporal tables), PERIOD
SQL:2016  JSON支持（JSON_VALUE/JSON_TABLE/JSON_QUERY/JSON_EXISTS）
SQL:2023  属性图查询, JSON增强, GREATEST/LEAST标准化

## 各数据库对标准SQL的遵循度（相对排序）

高: PostgreSQL, DB2, Oracle, Firebird, CockroachDB
中: SQL Server, MariaDB, Trino, DuckDB, Snowflake
低: MySQL(历史原因), ClickHouse, Hive, TDengine

## 标准函数与各数据库的差异速查

NULL处理:
- **标准**: COALESCE(a,b), NULLIF(a,b)
- **MySQL**: IFNULL, Oracle: NVL, SQL Server: ISNULL

字符串连接:
- **标准**: a || b
- **MySQL**: CONCAT(a,b), SQL Server: CONCAT(a,b) 或 a + b

当前时间:
- **标准**: CURRENT_TIMESTAMP
- **MySQL**: NOW(), Oracle: SYSDATE, SQL Server: GETDATE()

结果限制:
- **标准**: FETCH FIRST n ROWS ONLY (SQL:2008)
- **MySQL/PG**: LIMIT n, SQL Server: TOP n, Oracle: ROWNUM

自增:
- **标准**: GENERATED ALWAYS AS IDENTITY (SQL:2003)
- **MySQL**: AUTO_INCREMENT, SQL Server: IDENTITY, Oracle: SEQUENCE

合并:
- **标准**: MERGE (SQL:2003)
- **MySQL**: INSERT ... ON DUPLICATE KEY UPDATE
- **PostgreSQL**: INSERT ... ON CONFLICT
