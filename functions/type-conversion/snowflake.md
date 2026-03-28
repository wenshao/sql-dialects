# Snowflake: 类型转换

> 参考资料:
> - [1] Snowflake SQL Reference - Conversion Functions
>   https://docs.snowflake.com/en/sql-reference/functions-conversion
> - [2] Snowflake SQL Reference - TRY_CAST
>   https://docs.snowflake.com/en/sql-reference/functions/try_cast


## 1. 三种转换方式


方式 1: CAST（SQL 标准）

```sql
SELECT CAST(42 AS VARCHAR);
SELECT CAST('42' AS INTEGER);
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('3.14' AS NUMBER(10,2));

```

方式 2: :: 运算符（PostgreSQL 风格）

```sql
SELECT 42::VARCHAR;
SELECT '42'::INTEGER;
SELECT '2024-01-15'::DATE;
SELECT CURRENT_TIMESTAMP()::VARCHAR;

```

方式 3: TO_* 函数（Oracle 风格）

```sql
SELECT TO_VARCHAR(42);
SELECT TO_NUMBER('123.45', '999.99');
SELECT TO_DECIMAL('3.14', 10, 2);
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_CHAR(CURRENT_TIMESTAMP(), 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_BOOLEAN('true');

```

## 2. 语法设计分析（对 SQL 引擎开发者）


### 2.1 三种语法共存: 历史兼容性的选择

 Snowflake 同时支持三种类型转换语法，这是兼容多种方言的策略:
   CAST(x AS type)  → SQL 标准，所有数据库都支持
   x::type           → PostgreSQL 风格，简洁
   TO_TYPE(x, fmt)   → Oracle 风格，支持格式化字符串

 对比各数据库的偏好:
   PostgreSQL: 三种都支持，推荐 ::
   MySQL:      只支持 CAST（不支持 :: 和 TO_*）
   Oracle:     TO_NUMBER/TO_CHAR/TO_DATE（不支持 :: ）
   SQL Server: CAST + CONVERT（不支持 :: 和 TO_*）
   BigQuery:   只支持 CAST 和 SAFE_CAST（不支持 :: 和 TO_*）

 对引擎开发者的启示:
   CAST 是必须支持的（SQL 标准）。
   :: 语法实现简单（解析器中添加后缀运算符）且非常受欢迎。
   TO_* 函数支持格式化字符串（如日期格式），是 CAST 无法替代的。
   推荐三种都支持（如 Snowflake/PostgreSQL），以降低迁移成本。

### 2.2 TRY_CAST / TRY_TO_*: 安全转换

传统 CAST 在转换失败时报错，终止查询。
TRY_* 系列在失败时返回 NULL，不中断执行。

```sql
SELECT TRY_CAST('abc' AS INTEGER);        -- NULL（不报错）
SELECT TRY_CAST('42' AS INTEGER);         -- 42
SELECT TRY_CAST('bad-date' AS DATE);      -- NULL

SELECT TRY_TO_NUMBER('abc');              -- NULL
SELECT TRY_TO_DATE('bad-date');           -- NULL
SELECT TRY_TO_TIMESTAMP('bad-ts');        -- NULL
SELECT TRY_TO_DECIMAL('abc', 10, 2);     -- NULL
SELECT TRY_TO_BOOLEAN('maybe');           -- NULL

```

 设计意义:
   在 ETL/数据清洗场景中，源数据质量无法保证。
   传统方案: CASE WHEN regexp_match(...) THEN CAST ... ELSE NULL（繁琐且脆弱）
   TRY_* 方案: TRY_CAST(val AS INTEGER)（简洁且完备）

 对比:
   SQL Server: TRY_CAST / TRY_CONVERT（与 Snowflake 最接近）
   BigQuery:   SAFE_CAST（功能相同，名称不同）
   PostgreSQL: 无原生 TRY_CAST（需要自定义函数或 EXCEPTION 块）
   MySQL:      无原生 TRY_CAST
   Oracle:     无原生 TRY_CAST（需要 EXCEPTION 块）

 对引擎开发者的启示:
   TRY_* 系列是现代 SQL 引擎的标配功能。
   实现方式: 在类型转换函数中捕获异常 → 返回 NULL（而非传播错误）。
   PostgreSQL 社区多年讨论添加 TRY_CAST 但至今未实现，是一个遗憾。

## 3. 隐式转换规则


 Snowflake 的隐式转换相对保守（不如 MySQL 宽松）:
数字 → 字符串: 允许（SELECT 42 || 'abc' → '42abc'）
 字符串 → 数字: 部分允许（WHERE number_col = '42' → 隐式转换 '42' 为数字）
 日期/时间:     较严格（通常需要显式转换）

 对比:
   MySQL:      非常宽松（'123abc' + 0 = 123，静默截断）
   PostgreSQL: 最严格（几乎不做隐式转换，推荐显式 CAST）
   Oracle:     中等（TO_NUMBER/TO_CHAR 显式转换为主）
   Snowflake:  中等（比 MySQL 严格，比 PostgreSQL 宽松）

## 4. VARIANT 类型转换


VARIANT 内部值的类型转换:

```sql
SELECT data:name::STRING FROM events;           -- VARIANT → STRING
SELECT data:age::INTEGER FROM events;           -- VARIANT → INTEGER
SELECT TRY_CAST(data:age AS INTEGER) FROM events; -- 安全版本

```

VARIANT 的类型检查:

```sql
SELECT TYPEOF(data:name) FROM events;           -- 返回内部类型名
SELECT IS_NULL_VALUE(data:email) FROM events;   -- JSON null 判断
SELECT IS_OBJECT(data) FROM events;             -- 是否为对象
SELECT IS_ARRAY(data:tags) FROM events;         -- 是否为数组

```

TO_VARIANT / AS_*:

```sql
SELECT TO_VARIANT('hello');                     -- 任意值 → VARIANT
SELECT AS_INTEGER(data:age) FROM events;        -- VARIANT → INTEGER (严格)

```

 对引擎开发者的启示:
   VARIANT 类型转换需要两层:
   (a) 路径提取: data:field → VARIANT 子值
   (b) 类型转换: VARIANT → 目标类型
   :: 运算符同时完成两步: data:field::STRING
   这种组合语法是 Snowflake VARIANT 易用性的关键

## 5. 格式化字符串


TO_* 函数支持格式化:

```sql
SELECT TO_VARCHAR(CURRENT_TIMESTAMP(), 'DY, DD MON YYYY HH24:MI:SS');
SELECT TO_CHAR(1234567.89, '9,999,999.99');    -- '1,234,567.89'
SELECT TO_NUMBER('$1,234.56', '$9,999.99');    -- 1234.56

```

 格式化使用 Oracle 风格格式符:
   9 = 数字位, 0 = 零填充位, . = 小数点, , = 千分位
   $ = 美元符号, YYYY = 年, MM = 月, DD = 日

## 横向对比: 类型转换能力矩阵

| 能力           | Snowflake     | BigQuery    | PostgreSQL | MySQL  | Oracle |
|------|------|------|------|------|------|
| CAST           | 支持          | 支持        | 支持       | 支持   | 支持 |
| :: 运算符      | 支持          | 不支持      | 原创       | 不支持 | 不支持 |
| TO_* 函数      | 支持          | 不支持      | 支持       | 不支持 | 原创 |
| TRY_CAST       | 支持          | SAFE_CAST   | 不支持     | 不支持 | 不支持 |
| TRY_TO_*       | 完整系列      | 不支持      | 不支持     | 不支持 | 不支持 |
| 隐式转换       | 中等          | 严格        | 最严格     | 最宽松 | 中等 |
| 格式化字符串   | Oracle 风格   | 不支持      | 支持       | 不支持 | 原创 |
| VARIANT 转换   | :: + TRY_*    | N/A         | JSONB ->>  | ->/->> | 无 |

