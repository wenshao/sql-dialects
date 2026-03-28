# Spark SQL: 类型转换 (Type Conversion)

> 参考资料:
> - [1] Spark SQL - CAST
>   https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-cast.html
> - [2] Spark SQL - Type Coercion
>   https://spark.apache.org/docs/latest/sql-ref-ansi-compliance.html


## 1. CAST: 显式类型转换（SQL 标准）

```sql
SELECT CAST(42 AS STRING);                               -- '42'
SELECT CAST('42' AS INT);                                -- 42
SELECT CAST('3.14' AS DOUBLE);                           -- 3.14
SELECT CAST('3.14' AS DECIMAL(10,2));                    -- 3.14
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('2024-01-15 10:30:00' AS TIMESTAMP);
SELECT CAST(TRUE AS INT);                                -- 1
SELECT CAST(1 AS BOOLEAN);                               -- true

```

## 2. TRY_CAST: 安全转换（Spark 3.0+）

```sql
SELECT TRY_CAST('abc' AS INT);                           -- NULL (不报错)
SELECT TRY_CAST('42' AS INT);                            -- 42
SELECT TRY_CAST('2024-13-45' AS DATE);                   -- NULL

```

 TRY_CAST 的设计意义:
   在 ETL 管道中处理脏数据时，CAST 失败会导致整个作业失败。
   TRY_CAST 将错误转为 NULL，配合 COALESCE 可以优雅处理脏数据。

 对比:
   PostgreSQL: 无 TRY_CAST（社区长期讨论但未实现）——需要自定义函数
   MySQL:      隐式转换极宽松（不需要 TRY_CAST），但可能产生错误结果
   BigQuery:   SAFE_CAST（等价于 TRY_CAST）
   SQL Server: TRY_CAST / TRY_CONVERT（2012+）

## 3. 函数式转换（Spark 特色）

```sql
SELECT INT('123');                                       -- 123
SELECT DOUBLE('3.14');                                   -- 3.14
SELECT STRING(123);                                      -- '123'
SELECT BOOLEAN('true');                                  -- true
SELECT DECIMAL(123.456);                                 -- 123.456

```

 这是 Spark 独有的简写语法:
   INT(x) 等价于 CAST(x AS INT)
   其他引擎不支持（迁移时需改为标准 CAST）

## 4. :: 运算符（Spark 3.4+）

 SELECT 42::STRING;                                    -- '42'
 SELECT '42'::INT;                                     -- 42
 SELECT '2024-01-15'::DATE;

 :: 运算符源自 PostgreSQL，Spark 3.4+ 引入
 对比: PostgreSQL 从第一版就支持 ::（这是 PG 的标志性语法之一）
 MySQL 不支持 ::（只有 CAST）

## 5. 日期/时间转换

```sql
SELECT DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd');
SELECT TO_DATE('2024/01/15', 'yyyy/MM/dd');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');
SELECT FROM_UNIXTIME(1705276800, 'yyyy-MM-dd HH:mm:ss');
SELECT UNIX_TIMESTAMP('2024-01-15', 'yyyy-MM-dd');

```

安全时间戳解析（Spark 3.4+）

```sql
SELECT TRY_TO_TIMESTAMP('invalid_date', 'yyyy-MM-dd');   -- NULL

```

## 6. 隐式转换: ANSI 模式的影响


ANSI=false (Spark 3.x 默认): 宽松转换

```sql
SELECT '42' + 0;                                         -- 42 (字符串隐式转为数字)
SELECT CONCAT('val: ', 42);                              -- 'val: 42' (数字隐式转为字符串)

```

 ANSI=true (Spark 4.0 默认): 严格转换
 某些隐式转换在 ANSI 模式下不再允许
 SET spark.sql.ansi.enabled = true;

 类型提升（Type Widening）规则:
   TINYINT -> SMALLINT -> INT -> BIGINT -> DECIMAL -> FLOAT -> DOUBLE
   Spark 在混合类型运算时自动向上提升
   例如: INT + BIGINT -> BIGINT, INT + DOUBLE -> DOUBLE

 对比隐式转换的严格度:
   PostgreSQL: 最严格——需要显式 CAST（'123'::INTEGER）
   MySQL:      最宽松——几乎任何类型都隐式转换（可能导致静默错误）
   Spark:      中等——ANSI=false 时较宽松，ANSI=true 时较严格
   SQLite:     极度宽松（动态类型系统，任何列可以存任何类型）

 对引擎开发者的启示:
   隐式转换的严格度是引擎设计的重要决策。
   过于宽松（MySQL）导致静默错误；过于严格（PostgreSQL）降低用户体验。
   Spark 通过 ANSI 模式开关让用户选择——这是一个好的折中方案。
   但 ANSI 模式切换导致行为不一致——同一条 SQL 在不同模式下结果不同——这增加了复杂度。

## 7. 特殊转换场景


数值精度转换

```sql
SELECT CAST(3.14159 AS DECIMAL(4,2));                    -- 3.14 (截断)
SELECT CAST(99999 AS TINYINT);                           -- ANSI=false: 溢出回绕, ANSI=true: 报错

```

布尔转换

```sql
SELECT CAST('true' AS BOOLEAN);                          -- true
SELECT CAST('false' AS BOOLEAN);                         -- false
SELECT CAST('yes' AS BOOLEAN);                           -- ANSI=false: NULL, ANSI=true: 报错

```

二进制转换

```sql
SELECT CAST('hello' AS BINARY);
SELECT CAST(CAST('hello' AS BINARY) AS STRING);

```

## 8. 脏数据处理模式


TRY_CAST + COALESCE 模式（最常用的脏数据处理）

```sql
SELECT
    id,
    COALESCE(TRY_CAST(age_str AS INT), -1) AS age,
    COALESCE(TRY_CAST(price_str AS DOUBLE), 0.0) AS price,
    COALESCE(TRY_TO_TIMESTAMP(date_str, 'yyyy-MM-dd'), TIMESTAMP '1970-01-01') AS dt
FROM raw_data;

```

## 9. 版本演进

Spark 2.0: CAST, 函数式转换（INT()/STRING()/...）
Spark 3.0: TRY_CAST, ANSI 模式（默认关闭）
Spark 3.4: :: 运算符, TRY_TO_TIMESTAMP
Spark 4.0: ANSI 模式默认开启

限制:
日期模式使用 Java SimpleDateFormat/DateTimeFormatter（不是 SQL 标准格式）
TO_NUMBER 支持有限（Spark 3.4+ 部分支持）
:: 运算符仅 Spark 3.4+
函数式转换（INT()/STRING()）是 Spark 特有的非标准语法
ANSI 模式切换可能导致存量 SQL 行为变化（特别是溢出和 NULL 处理）

