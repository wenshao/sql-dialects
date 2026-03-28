# Spark SQL: 条件函数 (Conditional Functions)

> 参考资料:
> - [1] Spark SQL - Built-in Functions
>   https://spark.apache.org/docs/latest/sql-ref-functions-builtin.html


## 1. CASE WHEN: SQL 标准条件表达式


Searched CASE

```sql
SELECT username,
    CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END AS category
FROM users;

```

Simple CASE

```sql
SELECT username,
    CASE status
        WHEN 0 THEN 'inactive'
        WHEN 1 THEN 'active'
        WHEN 2 THEN 'deleted'
        ELSE 'unknown'
    END AS status_name
FROM users;

```

## 2. IF / IIF: Spark 的三元表达式


```sql
SELECT IF(age >= 18, 'adult', 'minor') FROM users;
SELECT IIF(age >= 18, 'adult', 'minor') FROM users;      -- Spark 3.2+, IF 的别名

```

 IF 是 Spark/Hive 特色语法，传统 SQL 标准中没有 IF 表达式
 对比:
   MySQL:      IF(cond, true_val, false_val) — 与 Spark 完全一致
   PostgreSQL: 不支持 IF 表达式（用 CASE WHEN）
   Oracle:     不支持 IF 表达式（用 CASE WHEN 或 DECODE）
   SQL Server: IIF(cond, true_val, false_val) — 2012+ 引入

## 3. NULL 处理函数


COALESCE: 返回第一个非 NULL 值（SQL 标准）

```sql
SELECT COALESCE(phone, email, 'unknown') FROM users;

```

NULLIF: 两值相等返回 NULL（SQL 标准）

```sql
SELECT NULLIF(age, 0) FROM users;

```

IFNULL / NVL: COALESCE 的两参数简写

```sql
SELECT IFNULL(phone, 'N/A') FROM users;                  -- Spark 2.4+
SELECT NVL(phone, 'N/A') FROM users;                     -- Hive 兼容

```

NVL2: 三值 NULL 判断（非标准，Oracle/Hive 兼容）

```sql
SELECT NVL2(phone, 'has phone', 'no phone') FROM users;  -- Spark 2.4+
```

NVL2(expr, not_null_result, null_result)
对比 Oracle: NVL2 语义完全一致

NANVL: 处理 NaN（浮点数特有）

```sql
SELECT NANVL(DOUBLE('NaN'), 0.0);                        -- 0.0

```

NULL 检测

```sql
SELECT * FROM users WHERE age IS NULL;
SELECT * FROM users WHERE age IS NOT NULL;
SELECT * FROM users WHERE ISNULL(age);                   -- 函数形式
SELECT * FROM users WHERE ISNOTNULL(age);                -- 函数形式

```

IS DISTINCT FROM（Spark 3.2+, SQL 标准 NULL-safe 比较）

```sql
SELECT * FROM users WHERE phone IS DISTINCT FROM 'unknown';
SELECT * FROM users WHERE phone IS NOT DISTINCT FROM NULL;

```

 设计分析:
   IS DISTINCT FROM 解决了 NULL 比较的"三值逻辑"问题:
   NULL = NULL -> NULL (unknown), 但 NULL IS NOT DISTINCT FROM NULL -> TRUE
   MySQL 用 <=> 运算符实现类似语义（NULL-safe equality）
   PostgreSQL 的 IS DISTINCT FROM 是标准做法

## 4. GREATEST / LEAST

```sql
SELECT GREATEST(1, 3, 2);                                -- 3
SELECT LEAST(1, 3, 2);                                   -- 1
```

 注意: 任何参数为 NULL 则返回 NULL（Spark/Hive 行为）
 对比: PostgreSQL/MySQL 的 GREATEST/LEAST 忽略 NULL（返回非 NULL 最大值）
 这是 Spark 与其他引擎的重要行为差异

## 5. 类型转换


```sql
SELECT CAST('123' AS INT);
SELECT INT('123');                                        -- 函数式转换（Spark 特色）
SELECT DOUBLE('3.14');
SELECT STRING(123);
SELECT BOOLEAN('true');
SELECT CAST('2024-01-15' AS DATE);

```

TRY_CAST: 转换失败返回 NULL（Spark 3.0+）

```sql
SELECT TRY_CAST('abc' AS INT);                           -- NULL
SELECT TRY_CAST('2024-13-45' AS DATE);                   -- NULL

```

:: 运算符（Spark 3.4+, PostgreSQL 风格）
SELECT 42::STRING;
SELECT '42'::INT;

TYPEOF: 查看表达式类型（Spark 3.0+）

```sql
SELECT TYPEOF(42);                                        -- 'int'
SELECT TYPEOF('hello');                                   -- 'string'

```

## 6. DECODE: Oracle 兼容的条件表达式


```sql
SELECT DECODE(status, 0, 'inactive', 1, 'active', 2, 'deleted', 'unknown') FROM users;

```

 DECODE 等价于:
 CASE status WHEN 0 THEN 'inactive' WHEN 1 THEN 'active' WHEN 2 THEN 'deleted' ELSE 'unknown' END
 继承自 Hive（Hive 继承自 Oracle 的语法）

## 7. 条件聚合


```sql
SELECT
    SUM(CASE WHEN age < 30 THEN 1 ELSE 0 END) AS young,
    SUM(IF(status = 1, amount, 0)) AS active_total,
    COUNT_IF(age >= 30) AS senior_count                  -- Spark 3.0+
FROM users;

SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE age < 30) AS young            -- Spark 3.2+
FROM users;

```

## 8. ASSERT_TRUE: 运行时断言（Spark 3.1+）


 条件不满足时抛出异常（用于数据质量检查）
 SELECT ASSERT_TRUE(age >= 0, 'Age must be non-negative') FROM users;

## 9. stack: 列转行函数

```sql
SELECT stack(2, 'name', username, 'email', email) AS (field, value)
FROM users;

```

## 10. 版本演进

Spark 2.0: CASE, IF, COALESCE, NVL, DECODE, GREATEST, LEAST
Spark 2.4: IFNULL, NVL2
Spark 3.0: TYPEOF, COUNT_IF, TRY_CAST
Spark 3.1: ASSERT_TRUE
Spark 3.2: IIF, IS DISTINCT FROM, FILTER 子句
Spark 3.4: :: 运算符

限制:
无 :: 转换运算符（3.4 之前，使用 CAST 或函数式转换）
GREATEST/LEAST 遇到 NULL 返回 NULL（与 MySQL/PostgreSQL 不同）
DECODE 是非标准语法（Oracle/Hive 兼容，推荐用 CASE WHEN）
无 ILIKE（大小写不敏感 LIKE），需用 LOWER() + LIKE

