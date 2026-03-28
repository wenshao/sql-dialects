# SQL 标准: 类型转换

> 参考资料:
> - [ISO/IEC 9075-2: SQL Foundation - CAST](https://www.iso.org/standard/76584.html)
> - [SQL:2016 Foundation - Data Type Conversions](https://www.iso.org/standard/63556.html)

## CAST (SQL 标准核心类型转换)

```sql
SELECT CAST(42 AS VARCHAR(10));                 -- '42'
SELECT CAST('42' AS INTEGER);                   -- 42
SELECT CAST(3.14 AS INTEGER);                   -- 3
SELECT CAST('2024-01-15' AS DATE);              -- DATE
SELECT CAST('2024-01-15 10:30:00' AS TIMESTAMP); -- TIMESTAMP
SELECT CAST(1 AS BOOLEAN);                      -- TRUE
```

## 隐式转换规则 (SQL 标准)

数值类型之间自动转换: SMALLINT -> INTEGER -> BIGINT -> DECIMAL -> FLOAT
字符串到数值: 需要显式 CAST
字符串到日期: 需要显式 CAST
数值到字符串: 某些场景下隐式转换

## 常见转换模式

字符串 ↔ 数字
```sql
SELECT CAST('123.45' AS DECIMAL(10,2));         -- 123.45
SELECT CAST(123.45 AS VARCHAR(20));             -- '123.45'
```

字符串 ↔ 日期
```sql
SELECT CAST('2024-01-15' AS DATE);              -- DATE
SELECT CAST(DATE '2024-01-15' AS VARCHAR(20));  -- '2024-01-15'
```

数字 ↔ 布尔
```sql
SELECT CAST(0 AS BOOLEAN);                      -- FALSE
SELECT CAST(1 AS BOOLEAN);                      -- TRUE
```

- **注意：CAST 是 SQL 标准的核心类型转换函数**
- **注意：CONVERT 不在 SQL 标准中（MySQL 和 SQL Server 各有不同实现）**
- **注意：:: 运算符不在 SQL 标准中（PostgreSQL 特有）**
- **注意：TRY_CAST 不在 SQL 标准中**
- **注意：隐式转换规则因实现而异**
