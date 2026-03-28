# SQL Server: 迁移速查表

> 参考资料:
> - [SQL Server Migration Assistant (SSMA)](https://learn.microsoft.com/en-us/sql/ssma/)

## 从 MySQL 迁移到 SQL Server

数据类型映射:
  TINYINT(无符号)      → SMALLINT（SQL Server TINYINT 也是无符号但范围更小 0-255）
  INT/BIGINT           → INT/BIGINT
  TEXT/LONGTEXT        → NVARCHAR(MAX)
  DATETIME             → DATETIME2（精度更高）
  JSON                 → NVARCHAR(MAX)（无原生 JSON 类型）
  ENUM/SET             → 无等价（用 CHECK 约束或查找表）
  AUTO_INCREMENT       → IDENTITY(1,1)
  BOOLEAN              → BIT

函数映射:
  IFNULL()             → ISNULL() 或 COALESCE()
  NOW()                → GETDATE() 或 SYSDATETIME()
  CONCAT()             → CONCAT()（但 NULL 处理不同！MySQL 传播 NULL, SQL Server 不）
  GROUP_CONCAT()       → STRING_AGG()（2017+）或 FOR XML PATH
  LIMIT 10             → TOP 10 或 OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY
  LIMIT 10 OFFSET 20   → OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY
  IF(cond, a, b)       → IIF(cond, a, b)
  DATE_FORMAT()        → FORMAT() 或 CONVERT(VARCHAR, date, style)

语法陷阱:
  反引号 `table`       → 方括号 [table] 或双引号 "table"
  存储过程语法          → 完全不同（DELIMITER 不需要, BEGIN/END 结构不同）
  ON UPDATE CURRENT_TIMESTAMP → 需要触发器（SQL Server 无此列级功能）

## 从 Oracle 迁移到 SQL Server

数据类型映射:
  NUMBER(p,s)          → DECIMAL(p,s) 或 INT/BIGINT
  VARCHAR2(n)          → NVARCHAR(n)（注意: Oracle 默认 n 是字节数）
  CLOB                 → NVARCHAR(MAX)
  DATE（含时间!）       → DATETIME2（Oracle DATE 含时分秒）
  SEQUENCE             → IDENTITY 或 SEQUENCE（2012+）

函数映射:
  NVL()                → ISNULL() 或 COALESCE()
  SYSDATE              → GETDATE()
  DECODE()             → IIF() 或 CASE
  TO_CHAR(date, fmt)   → FORMAT(date, fmt) 或 CONVERT(VARCHAR, date, style)
  TO_NUMBER()          → CAST(x AS INT/DECIMAL)
  ROWNUM               → TOP 或 ROW_NUMBER() OVER(...)
  ||                   → + 或 CONCAT()
  CONNECT BY           → WITH 递归 CTE
  MINUS                → EXCEPT
  DUAL                 → 不需要（SELECT 1 不需要 FROM）

关键陷阱:
  Oracle '' = NULL      → SQL Server '' != NULL（空串和 NULL 不同）
  PL/SQL 包             → 无等价（改为 Schema + 多个存储过程）
  隐式提交（DDL）       → SQL Server DDL 是事务性的（可回滚）

## 从 PostgreSQL 迁移到 SQL Server

数据类型映射:
  SERIAL/BIGSERIAL     → IDENTITY(1,1)
  BOOLEAN              → BIT
  TEXT                 → NVARCHAR(MAX)
  BYTEA                → VARBINARY(MAX)
  UUID                 → UNIQUEIDENTIFIER
  JSONB                → NVARCHAR(MAX)（无二进制 JSON）
  ARRAY                → 无等价（用 JSON 数组或 TVP）
  INTERVAL             → 无等价（用 DATEADD 函数代替）

函数映射:
  ||                   → + 或 CONCAT()
  NOW()                → GETDATE()
  STRING_AGG()         → STRING_AGG()（2017+）
  regexp_replace()     → 无原生正则（2025 预览有）
  generate_series()    → 无等价（递归 CTE 或数字表）
  unnest()             → OPENJSON() 或 STRING_SPLIT()

关键陷阱:
  LATERAL              → CROSS APPLY / OUTER APPLY
```sql
  CREATE TEMP TABLE    → CREATE TABLE #temp
```

  PL/pgSQL             → T-SQL（完全重写）
  PostgreSQL 类型严格   → SQL Server 较宽松（隐式转换更多）

## 常用函数速查

当前时间
```sql
SELECT GETDATE(), SYSDATETIME(), SYSUTCDATETIME();
```

日期操作
```sql
SELECT DATEADD(DAY, 1, GETDATE());
SELECT DATEDIFF(DAY, '2024-01-01', '2024-12-31');
SELECT FORMAT(GETDATE(), 'yyyy-MM-dd HH:mm:ss');
```

字符串
```sql
SELECT LEN(N'hello'), DATALENGTH(N'hello');
SELECT SUBSTRING(N'hello', 2, 3);
SELECT REPLACE(N'hello', N'l', N'r');
SELECT CHARINDEX(N'lo', N'hello');
SELECT CONCAT(N'hello', N' world');
SELECT STRING_AGG(name, N', ') FROM users;  -- 2017+
SELECT value FROM STRING_SPLIT(N'a,b,c', N',');  -- 2016+
```

类型转换
```sql
SELECT CAST('42' AS INT), TRY_CAST('abc' AS INT);
SELECT CONVERT(VARCHAR(10), GETDATE(), 120);
```

NULL 处理
```sql
SELECT ISNULL(phone, 'N/A'), COALESCE(phone, email, 'unknown');
SELECT NULLIF(age, 0);
```

自增
```sql
CREATE TABLE t (id BIGINT IDENTITY(1,1) PRIMARY KEY);
CREATE SEQUENCE my_seq START WITH 1 INCREMENT BY 1;
SELECT NEXT VALUE FOR my_seq;
```

## SQL Server 独有特性（其他数据库没有的）

CROSS APPLY / OUTER APPLY（早于 LATERAL）
OUTPUT 子句（INSERT/UPDATE/DELETE/MERGE 中返回受影响行）
表变量 DECLARE @t TABLE (...)
锁提示 WITH (NOLOCK/UPDLOCK/HOLDLOCK)
聚集索引（数据物理排列顺序）
列存储索引（HTAP 场景）
时态表（系统版本化, 2016+）
In-Memory OLTP（Hekaton, 2014+）
事务性 DDL（可在事务中回滚 CREATE/ALTER/DROP）
IDENTITY_INSERT（手动插入自增列的开关）
sp_executesql（参数化动态 SQL）
GO 批分隔符（客户端工具命令，不是 SQL）
