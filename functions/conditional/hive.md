# Hive: 条件函数

> 参考资料:
> - [1] Apache Hive - Conditional Functions
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF#LanguageManualUDF-ConditionalFunctions
> - [2] Apache Hive Language Manual - UDF
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF


## 1. CASE WHEN: 标准条件表达式

搜索型 CASE

```sql
SELECT username,
    CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END AS category
FROM users;

```

简单型 CASE

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

## 2. IF 函数: Hive 特有的三元条件

```sql
SELECT IF(age >= 18, 'adult', 'minor') AS category FROM users;
SELECT IF(amount > 0, amount, 0) AS positive_amount FROM orders;

```

嵌套 IF

```sql
SELECT IF(age < 18, 'minor', IF(age < 65, 'adult', 'senior')) FROM users;

```

 设计分析: IF 函数 vs CASE WHEN
 IF 是 Hive（和 MySQL）的语法糖，等价于简单的二分支 CASE WHEN。
 PostgreSQL/SQL Server 不支持 IF 函数（使用 CASE WHEN）。
 Spark SQL 继承了 Hive 的 IF 函数。

## 3. NULL 处理函数

COALESCE: 返回第一个非 NULL 值

```sql
SELECT COALESCE(phone, mobile, email, 'no_contact') FROM users;

```

NVL: 两参数的 COALESCE（0.11+）

```sql
SELECT NVL(phone, 'no phone') FROM users;
```

等价于 COALESCE(phone, 'no phone')

NULLIF: 两值相等则返回 NULL

```sql
SELECT NULLIF(age, 0) FROM users;
```

age=0 → NULL; age≠0 → age

NULL 判断

```sql
SELECT * FROM users WHERE phone IS NULL;
SELECT * FROM users WHERE phone IS NOT NULL;
SELECT ISNULL(phone) FROM users;           -- 返回 BOOLEAN
SELECT ISNOTNULL(phone) FROM users;        -- 返回 BOOLEAN

```

 设计分析: NVL 的来源
 NVL 是 Oracle 函数，Hive 引入它是为了方便 Oracle SQL 迁移。
 MySQL 没有 NVL（使用 IFNULL），PostgreSQL 也没有（使用 COALESCE）。
 推荐使用 COALESCE（SQL 标准，跨引擎兼容）。

## 4. GREATEST / LEAST

```sql
SELECT GREATEST(1, 3, 2);                  -- 返回 3
SELECT LEAST(1, 3, 2);                     -- 返回 1
SELECT GREATEST(a, b, c) FROM scores;      -- 多列取最大

```

 注意: 包含 NULL 时行为
 GREATEST(1, NULL, 3) → NULL（Hive 对 NULL 敏感）
 对比: MySQL 的 GREATEST 忽略 NULL

## 5. 类型转换: CAST

```sql
SELECT CAST('123' AS INT);
SELECT CAST(123 AS STRING);
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('2024-01-15 10:30:00' AS TIMESTAMP);
SELECT CAST('true' AS BOOLEAN);

```

 Hive CAST 失败行为: 返回 NULL（静默失败，不报错）
 SELECT CAST('abc' AS INT) → NULL
 这与 PostgreSQL 不同（PostgreSQL 的 CAST 失败会报错）

 对比:
   PostgreSQL: CAST 失败报错; 有 :: 简写语法
   BigQuery:   SAFE_CAST 失败返回 NULL（显式安全版本）
   Spark SQL:  TRY_CAST 失败返回 NULL（3.0+）
   Hive:       CAST 默认就是"安全"的（失败返回 NULL）

 隐式类型转换规则:
 STRING 可以隐式转为数值: '123' + 0 = 123
 提升方向: TINYINT → SMALLINT → INT → BIGINT → FLOAT → DOUBLE → DECIMAL
 BOOLEAN 不参与隐式转换

## 6. ASSERT_TRUE: 数据质量断言 (Hive 特有)

```sql
SELECT ASSERT_TRUE(age > 0) FROM users;    -- age<=0 时查询报错
SELECT ASSERT_TRUE(COUNT(*) > 0) FROM orders WHERE dt='2024-01-15';

```

 ASSERT_TRUE 的使用场景: 在 ETL 管道中嵌入数据质量检查
 替代了需要在应用层做的数据验证

## 7. IN / BETWEEN

```sql
SELECT * FROM users WHERE city IN ('Beijing', 'Shanghai', 'Guangzhou');
SELECT * FROM orders WHERE amount BETWEEN 100 AND 1000;

```

## 8. 跨引擎对比: 条件函数

 函数        Hive          MySQL        PostgreSQL   BigQuery
 CASE WHEN   标准          标准         标准         标准
 IF()        IF(a,b,c)     IF(a,b,c)    不支持       IF(a,b,c)
 NVL()       支持(0.11+)   不支持       不支持       不支持
 IFNULL()    不支持        支持         不支持       IFNULL
 COALESCE    支持          支持         支持         支持
 NULLIF      支持          支持         支持         支持
 DECODE      不支持        不支持       不支持       不支持
 CAST        静默失败      静默失败     失败报错     失败报错
 SAFE_CAST   无(CAST即安全) 无          无           SAFE_CAST
 ASSERT_TRUE Hive特有       无          无           ERROR()

## 9. 对引擎开发者的启示

1. CAST 的失败行为需要明确设计:

    静默返回 NULL (Hive/MySQL) vs 报错 (PostgreSQL) 各有道理。
    BigQuery 的 SAFE_CAST 提供了两种选择，是最灵活的方案。
2. IF 函数是有用的语法糖: 比 CASE WHEN 简洁，值得支持

3. ASSERT_TRUE 是数据质量检查的好模式:

    在 SQL 中嵌入断言比 try/catch 更直观
4. NULL 处理函数应该丰富:

COALESCE/NVL/NULLIF/IFNULL 覆盖了常见的 NULL 处理场景

