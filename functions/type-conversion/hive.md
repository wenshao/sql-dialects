# Hive: 类型转换

> 参考资料:
> - [1] Apache Hive Language Manual - UDF: Type Conversion
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF
> - [2] Apache Hive - Data Types
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Types


## 1. CAST: 显式类型转换

数值转换

```sql
SELECT CAST('42' AS INT);                              -- 42
SELECT CAST('42' AS BIGINT);                           -- 42
SELECT CAST('3.14' AS DOUBLE);                         -- 3.14
SELECT CAST('3.14' AS DECIMAL(10,2));                  -- 3.14
SELECT CAST(3.14 AS INT);                              -- 3 (截断，非四舍五入)
SELECT CAST(TRUE AS INT);                              -- 1
SELECT CAST(0 AS BOOLEAN);                             -- false

```

字符串转换

```sql
SELECT CAST(42 AS STRING);                             -- '42'
SELECT CAST(3.14 AS STRING);                           -- '3.14'

```

日期时间转换

```sql
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('2024-01-15 10:30:00' AS TIMESTAMP);
SELECT CAST(CURRENT_TIMESTAMP AS DATE);                -- 提取日期部分
SELECT CAST(CURRENT_DATE AS TIMESTAMP);                -- 日期升为时间戳(00:00:00)

```

CAST 失败行为: 返回 NULL（静默失败）

```sql
SELECT CAST('abc' AS INT);                             -- NULL（不报错!）
SELECT CAST('not-a-date' AS DATE);                     -- NULL
SELECT CAST('' AS INT);                                -- NULL

```

 设计分析: 静默失败 vs 报错
 Hive 的 CAST 失败返回 NULL，这是宽松设计:
   优点: 批处理不会因为一行脏数据而整体失败
   缺点: 用户可能不知道转换失败了，导致静默的数据丢失
 对比:
   PostgreSQL: CAST 失败报错（严格模式）
   BigQuery:   CAST 报错，SAFE_CAST 返回 NULL（两种选择）
   Spark SQL:  TRY_CAST 返回 NULL（3.0+），CAST 报错
   MySQL:      CAST 不报错，可能返回 0 或截断值（比 NULL 更危险）

## 2. 日期/时间格式化转换

日期格式化

```sql
SELECT DATE_FORMAT(CURRENT_DATE, 'yyyy-MM-dd');
SELECT DATE_FORMAT(CURRENT_DATE, 'dd/MM/yyyy');
SELECT DATE_FORMAT(CURRENT_TIMESTAMP, 'yyyyMMdd');

```

Unix 时间戳互转

```sql
SELECT UNIX_TIMESTAMP('2024-01-15', 'yyyy-MM-dd');            -- STRING → Unix 秒
SELECT FROM_UNIXTIME(1705276800, 'yyyy-MM-dd HH:mm:ss');     -- Unix 秒 → STRING
SELECT TO_DATE('2024-01-15 10:30:00');                         -- 提取日期部分

```

 格式模式使用 Java SimpleDateFormat:
 yyyy: 年  MM: 月  dd: 日  HH: 24小时  mm: 分  ss: 秒
 对比: PostgreSQL TO_CHAR 使用 'YYYY-MM-DD'
 对比: MySQL DATE_FORMAT 使用 '%Y-%m-%d'

## 3. 隐式类型转换规则

```sql
SELECT '42' + 0;                    -- 42 (STRING → DOUBLE → 加法)
SELECT CONCAT('value: ', 42);       -- 'value: 42' (INT → STRING)
SELECT 1 + 1.5;                    -- 2.5 (INT → DOUBLE)
SELECT TRUE + 1;                   -- 2 (BOOLEAN → INT → 加法)

```

 隐式转换提升方向:
 TINYINT → SMALLINT → INT → BIGINT → FLOAT → DOUBLE → DECIMAL → STRING
 BOOLEAN 可以转为数值但不推荐
 STRING 可以隐式转为数值（在运算上下文中）

 设计分析: 宽松 vs 严格的隐式转换
 Hive 的隐式转换比较宽松:
   '123' + 0 = 123 (STRING 隐式转为数值)
 PostgreSQL 很严格:
   '123' + 0 → 报错（需要显式 CAST）
 宽松转换降低了用户负担但增加了 Bug 风险
 大数据引擎（Hive/Spark/MaxCompute）倾向宽松，OLTP 引擎倾向严格

## 4. 复合类型转换

ARRAY 类型转换

```sql
SELECT CAST(ARRAY(1, 2, 3) AS ARRAY<STRING>);         -- ARRAY<INT> → ARRAY<STRING>

```

JSON 字符串提取（不是类型转换，但常用于类型处理）

```sql
SELECT GET_JSON_OBJECT('{"a":1}', '$.a');               -- '1' (STRING)
SELECT CAST(GET_JSON_OBJECT('{"a":1}', '$.a') AS INT); -- 1

```

## 5. 跨引擎对比: 类型转换设计

 特性          Hive           MySQL          PostgreSQL      BigQuery
 CAST 失败     返回 NULL      返回 0/截断    报错            报错
 SAFE_CAST     无(默认安全)   无             无              SAFE_CAST
 TRY_CAST      无             无             无              无
 :: 语法       不支持         不支持         支持            不支持
 CONVERT       不支持         支持           不支持          不支持
 TO_NUMBER     不支持         不支持         支持            不支持
 隐式转换      宽松           宽松           严格            中等

 Spark SQL 3.0+ 引入了 TRY_CAST，是 Hive 用户迁移到 Spark 后可以使用的替代

## 6. 已知限制

### 1. 无 TRY_CAST / SAFE_CAST: Hive 的 CAST 已经是"安全"的（返回 NULL）

### 2. 无 :: 语法: 必须使用 CAST() 函数

### 3. 无 CONVERT / TO_NUMBER / TO_CHAR: PostgreSQL/Oracle 的转换函数不可用

### 4. CAST(DECIMAL) 可能丢失精度: CAST(9999999999.99 AS DECIMAL(10,2)) 溢出返回 NULL

### 5. STRING → TIMESTAMP 只支持特定格式: 'yyyy-MM-dd HH:mm:ss[.fffffffff]'

### 6. 不支持数值格式化: 无法直接将数值格式化为带千分位的字符串


## 7. 对引擎开发者的启示

### 1. CAST 失败行为需要明确设计策略:

    Hive(默认安全/NULL) vs PostgreSQL(默认报错) vs BigQuery(两种选择)
    BigQuery 的 CAST + SAFE_CAST 组合是最灵活的方案
### 2. 隐式转换的宽松程度是 trade-off:

    宽松降低用户门槛但增加错误风险; 严格保证正确性但增加 SQL 复杂度
### 3. 日期格式化字符串不统一是跨引擎迁移的痛点:

Java(yyyy-MM-dd) vs PostgreSQL(YYYY-MM-DD) vs MySQL(%Y-%m-%d)
如果设计新引擎，考虑同时支持多种格式模式

