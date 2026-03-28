# MySQL: 迁移速查表

> 参考资料:
> - [MySQL 8.0 Reference Manual - SQL Differences](https://dev.mysql.com/doc/refman/8.0/en/differences-from-ansi.html)
> - [MySQL 8.0 - Migrating to MySQL](https://dev.mysql.com/doc/refman/8.0/en/migration-guide.html)

## 一、从 PostgreSQL 迁移到 MySQL

1. 数据类型映射
   PostgreSQL           → MySQL
   SERIAL               → INT AUTO_INCREMENT
   BIGSERIAL            → BIGINT AUTO_INCREMENT
   BOOLEAN              → TINYINT(1) 或 BOOL
   TEXT                 → TEXT / LONGTEXT
   BYTEA                → BLOB / LONGBLOB
   TIMESTAMPTZ          → DATETIME（MySQL 8.0.19+ 支持时区）
   NUMERIC(p,s)         → DECIMAL(p,s)
   REAL                 → FLOAT
   DOUBLE PRECISION     → DOUBLE
   UUID                 → CHAR(36) 或 BINARY(16)
   JSONB                → JSON
   ARRAY                → JSON 数组 或 关联表
   INTERVAL             → 无直接等价，用函数处理
   INET / CIDR          → VARCHAR(45)
   ENUM type            → ENUM('a','b','c')（列级定义）

2. 函数等价映射
   PostgreSQL           → MySQL
   NOW()                → NOW()
   CURRENT_TIMESTAMP    → CURRENT_TIMESTAMP / NOW()
   a || b               → CONCAT(a, b)
   STRING_AGG(c, ',')   → GROUP_CONCAT(c SEPARATOR ',')
   EXTRACT(part FROM d) → EXTRACT(part FROM d)（基本相同）
   TO_CHAR(d, fmt)      → DATE_FORMAT(d, fmt)  -- 格式符不同
   COALESCE(a, b)       → COALESCE(a, b) 或 IFNULL(a, b)
   NULLIF(a, b)         → NULLIF(a, b)
   "identifier"         → `identifier`
   LIMIT n OFFSET m     → LIMIT m, n  或  LIMIT n OFFSET m
   GENERATE_SERIES()    → WITH RECURSIVE 或数字表
   UNNEST(array)        → JSON_TABLE
   regexp_replace()     → REGEXP_REPLACE()（MySQL 8.0+）

3. 常见陷阱
   - MySQL 默认大小写行为取决于操作系统和 lower_case_table_names
   - MySQL 5.7.5+ 默认开启 ONLY_FULL_GROUP_BY（旧版本默认宽松）
   - MySQL 不支持 RETURNING 子句（8.0 不支持，MariaDB 10.5+ 支持）
   - MySQL 不支持 FULL OUTER JOIN
   - MySQL 的 ENUM 是列级定义，不是类型级
   - MySQL 不支持数组类型
   - MySQL 8.0.14+ 支持 LATERAL（更早版本不支持）
   - MySQL 事务中单条失败不会回滚整个事务

## 二、从 SQL Server 迁移到 MySQL

1. 数据类型映射
   SQL Server           → MySQL
   NVARCHAR(n)          → VARCHAR(n) CHARACTER SET utf8mb4
   NVARCHAR(MAX)        → LONGTEXT
   BIT                  → TINYINT(1)
   UNIQUEIDENTIFIER     → CHAR(36)
   DATETIME2            → DATETIME(6)
   DATETIMEOFFSET       → DATETIME (时区需应用层处理)
   MONEY                → DECIMAL(19,4)
   VARBINARY(MAX)       → LONGBLOB
   XML                  → TEXT（无原生 XML 类型）
   IDENTITY(1,1)        → AUTO_INCREMENT

2. 函数等价映射
   SQL Server           → MySQL
   ISNULL(a, b)         → IFNULL(a, b)
   GETDATE()            → NOW()
   CHARINDEX(sub, s)    → LOCATE(sub, s)
   LEN(s)               → CHAR_LENGTH(s)
   TOP n                → LIMIT n
   NEWID()              → UUID()
   CONVERT(type, val)   → CAST(val AS type) 或 CONVERT(val, type)
   IIF(cond, t, f)      → IF(cond, t, f)
   STRING_SPLIT()       → JSON_TABLE + REPLACE

3. 常见陷阱
   - SQL Server 存储过程（T-SQL）需要完全重写
   - SQL Server 的 CROSS APPLY → MySQL 8.0.14+ LATERAL
   - 临时表: #temp → CREATE TEMPORARY TABLE
   - SQL Server 的 CTE 递归限制不同
   - MySQL AUTO_INCREMENT 必须是主键或唯一索引的一部分

## 三、自增/序列迁移

```sql
CREATE TABLE t (id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY);
```

MySQL 没有独立的 SEQUENCE（MariaDB 10.3+ 有）
AUTO_INCREMENT 值查看: SHOW TABLE STATUS LIKE 'table_name';

## 四、日期/时间函数映射

```sql
SELECT NOW();                           -- 当前日期时间
SELECT CURDATE();                       -- 当前日期
SELECT CURTIME();                       -- 当前时间
SELECT DATE_ADD(NOW(), INTERVAL 1 DAY); -- 加一天
SELECT DATE_SUB(NOW(), INTERVAL 2 HOUR);-- 减两小时
SELECT DATEDIFF('2024-12-31', '2024-01-01'); -- 日期差
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s'); -- 格式化
-- 格式: %Y=4位年, %m=月, %d=日, %H=24小时, %i=分, %s=秒
```

## 五、字符串函数映射

```sql
SELECT CHAR_LENGTH('hello');        -- 字符长度
SELECT LENGTH('hello');             -- 字节长度
SELECT UPPER('hello');              -- 大写
SELECT LOWER('HELLO');              -- 小写
SELECT TRIM('  hello  ');           -- 去空格
SELECT SUBSTRING('hello', 2, 3);   -- 子串 → 'ell'
SELECT REPLACE('hello', 'l', 'r'); -- 替换
SELECT LOCATE('lo', 'hello');      -- 位置 → 4
SELECT CONCAT('hello', ' world');  -- 连接
SELECT GROUP_CONCAT(name SEPARATOR ', ') FROM users; -- 聚合连接
SELECT SUBSTRING_INDEX('a,b,c', ',', 2); -- → 'a,b'
```
