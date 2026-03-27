# 安全函数 / TRY 语义

失败时返回 NULL 而非抛出错误——各引擎对数据转换和计算容错的不同设计策略。

## 支持矩阵

| 引擎 | 模式 | 典型函数 | 版本 |
|------|------|---------|------|
| BigQuery | `SAFE_` 前缀 / `SAFE.` 函数前缀 | `SAFE_CAST`, `SAFE_DIVIDE`, `SAFE.PARSE_DATE` | GA |
| SQL Server | `TRY_` 前缀 | `TRY_CAST`, `TRY_CONVERT`, `TRY_PARSE` | 2012+ |
| Snowflake | `TRY_` 前缀 | `TRY_TO_NUMBER`, `TRY_TO_DATE`, `TRY_TO_TIMESTAMP` | GA |
| ClickHouse | `OrNull` / `OrZero` 后缀 | `toInt32OrNull`, `toDateOrNull`, `toFloat64OrZero` | 早期 |
| Oracle | `VALIDATE_CONVERSION` | `VALIDATE_CONVERSION(expr AS type)` 返回 0/1 | 12c R2+ |
| Databricks | `TRY_` 前缀 | `TRY_CAST`, `TRY_TO_NUMBER`, `TRY_DIVIDE` | Runtime 11.2+ |
| Trino | `TRY_CAST` + `TRY` 函数 | `TRY_CAST`, `TRY(expr)` | 早期 |
| DuckDB | `TRY_CAST` | `TRY_CAST(expr AS type)` | 0.8.0+ |
| PostgreSQL | 无内置 | 需自定义函数 | - |
| MySQL | 无内置 | 需 CASE + REGEXP 变通 | - |
| MariaDB | 无内置 | 同 MySQL | - |
| SQLite | 无内置 | SQLite 本身类型宽松，较少报错 | - |

## 设计动机

### 问题: 一行脏数据导致整个查询失败

```sql
-- 数据表中有脏数据
-- prices: ['29.99', '49.50', 'N/A', '19.99', 'TBD', '39.00']

-- 一个 CAST 错误就终止整个查询
SELECT CAST(price AS DECIMAL(10,2)) FROM products;
-- 错误: Cannot cast 'N/A' to DECIMAL

-- 日期解析同样脆弱
SELECT CAST(date_str AS DATE) FROM logs;
-- 错误: Cannot cast '2024-02-30' to DATE (无效日期)

-- 除法也可能出错
SELECT revenue / cost AS margin FROM orders;
-- 错误: Division by zero (当 cost = 0 时)
```

在 ETL 管道和数据分析中，数据质量无法保证。一行脏数据导致百万行查询全部失败，这是不可接受的。

### 解决方案: 安全函数

安全函数在遇到错误时返回 NULL（或默认值）而非抛出异常，允许查询继续执行：

```sql
-- BigQuery
SELECT SAFE_CAST(price AS FLOAT64) FROM products;
-- 'N/A' → NULL, '29.99' → 29.99

-- SQL Server
SELECT TRY_CAST(price AS DECIMAL(10,2)) FROM products;
-- 'N/A' → NULL, '29.99' → 29.99

-- ClickHouse
SELECT toFloat64OrNull(price) FROM products;
-- 'N/A' → NULL, '29.99' → 29.99
```

## 各引擎详解

### BigQuery: SAFE_ 前缀 + SAFE. 函数前缀

BigQuery 提供两种安全函数机制：

```sql
-- 1. SAFE_CAST: 安全类型转换
SELECT SAFE_CAST('123' AS INT64);          -- 123
SELECT SAFE_CAST('abc' AS INT64);          -- NULL
SELECT SAFE_CAST('2024-02-30' AS DATE);    -- NULL

-- 2. SAFE_DIVIDE: 安全除法
SELECT SAFE_DIVIDE(100, 0);      -- NULL (不是错误)
SELECT SAFE_DIVIDE(100, 3);      -- 33.333...

-- 3. SAFE. 前缀: 任意函数的安全版本
SELECT SAFE.PARSE_DATE('%Y-%m-%d', '2024-13-01');  -- NULL (无效月份)
SELECT SAFE.PARSE_TIMESTAMP('%Y', 'abc');           -- NULL
SELECT SAFE.LOG(0);                                 -- NULL (log(0) 未定义)
SELECT SAFE.SUBSTR('hello', 10, 5);                 -- NULL 或 '' (取决于函数)

-- SAFE. 前缀是一个通用机制: 在任何函数前加 SAFE. 即可
-- 如果函数正常执行，返回正常结果
-- 如果函数抛出错误，返回 NULL
```

BigQuery 的 `SAFE.` 前缀是最优雅的设计——它不需要为每个函数创建安全变体，而是作为一个通用修饰符。

### SQL Server: TRY_ 前缀

```sql
-- TRY_CAST: 安全类型转换 (SQL Server 2012+)
SELECT TRY_CAST('123' AS INT);        -- 123
SELECT TRY_CAST('abc' AS INT);        -- NULL
SELECT TRY_CAST('99999999999' AS INT); -- NULL (溢出)

-- TRY_CONVERT: 带格式的安全类型转换
SELECT TRY_CONVERT(DATE, '2024-02-30');      -- NULL
SELECT TRY_CONVERT(DATETIME, '20240101', 112); -- 2024-01-01

-- TRY_PARSE: 安全的区域感知解析
SELECT TRY_PARSE('€1.234,56' AS MONEY USING 'de-DE');  -- 1234.56
SELECT TRY_PARSE('invalid' AS MONEY USING 'de-DE');    -- NULL

-- TRY_CAST vs CAST 的行为差异
SELECT CAST('abc' AS INT);      -- 错误!
SELECT TRY_CAST('abc' AS INT);  -- NULL

-- 结合 COALESCE 提供默认值
SELECT COALESCE(TRY_CAST(user_input AS INT), 0) AS safe_value;
```

### Snowflake: TRY_ 前缀

```sql
-- TRY_TO_NUMBER / TRY_TO_DECIMAL
SELECT TRY_TO_NUMBER('123.45');         -- 123
SELECT TRY_TO_DECIMAL('abc', 10, 2);    -- NULL

-- TRY_TO_DATE / TRY_TO_TIMESTAMP
SELECT TRY_TO_DATE('2024-02-30');              -- NULL
SELECT TRY_TO_TIMESTAMP('not-a-date');         -- NULL
SELECT TRY_TO_DATE('20240115', 'YYYYMMDD');    -- 2024-01-15

-- TRY_TO_BOOLEAN
SELECT TRY_TO_BOOLEAN('true');   -- TRUE
SELECT TRY_TO_BOOLEAN('maybe');  -- NULL

-- TRY_CAST (通用)
SELECT TRY_CAST('hello' AS INTEGER);  -- NULL
```

### ClickHouse: OrNull / OrZero 后缀

ClickHouse 的设计独特——提供两种失败策略：

```sql
-- OrNull 系列: 失败返回 NULL
SELECT toInt32OrNull('123');    -- 123
SELECT toInt32OrNull('abc');    -- NULL
SELECT toDateOrNull('2024-02-30');  -- NULL
SELECT toFloat64OrNull('1.5');      -- 1.5

-- OrZero 系列: 失败返回类型的零值
SELECT toInt32OrZero('123');    -- 123
SELECT toInt32OrZero('abc');    -- 0
SELECT toDateOrZero('2024-02-30');  -- 1970-01-01 (Date 的零值)
SELECT toFloat64OrZero('1.5');      -- 1.5

-- OrDefault 系列 (较新): 失败返回指定默认值
SELECT toInt32OrDefault('abc', 42);  -- 42

-- 完整的函数命名模式:
-- toType(x)          -- 严格转换，失败报错
-- toTypeOrNull(x)    -- 失败返回 NULL
-- toTypeOrZero(x)    -- 失败返回零值
-- toTypeOrDefault(x, default)  -- 失败返回默认值
```

### Oracle: VALIDATE_CONVERSION

Oracle 没有 TRY_CAST，而是提供了一个验证函数：

```sql
-- VALIDATE_CONVERSION: 返回 1(可转换) 或 0(不可转换)
SELECT VALIDATE_CONVERSION('123' AS NUMBER);    -- 1
SELECT VALIDATE_CONVERSION('abc' AS NUMBER);    -- 0

-- 结合 CASE WHEN 使用
SELECT
    CASE WHEN VALIDATE_CONVERSION(price_str AS NUMBER) = 1
         THEN CAST(price_str AS NUMBER)
         ELSE NULL
    END AS safe_price
FROM products;

-- 也支持日期格式验证
SELECT VALIDATE_CONVERSION('2024-02-30' AS DATE, 'YYYY-MM-DD');  -- 0
SELECT VALIDATE_CONVERSION('2024-02-28' AS DATE, 'YYYY-MM-DD');  -- 1

-- Oracle 的设计哲学: 分离验证和转换
-- 优点: 验证结果可以用于多种决策（不只是返回 NULL）
-- 缺点: 两步操作，且实际上 CAST 执行了两次（验证一次，转换一次）
```

### Trino: TRY_CAST + TRY()

```sql
-- TRY_CAST: 安全类型转换
SELECT TRY_CAST('abc' AS INTEGER);  -- NULL

-- TRY(): 通用安全包装——任何表达式
SELECT TRY(1 / 0);                -- NULL
SELECT TRY(CAST('abc' AS INT));   -- NULL
SELECT TRY(DATE '2024-02-30');    -- NULL

-- TRY() 是通用机制，类似 BigQuery 的 SAFE. 前缀
-- 但 TRY() 是函数形式，SAFE. 是前缀形式
```

### PostgreSQL / MySQL（无内置支持）

```sql
-- PostgreSQL: 需要自定义函数
CREATE OR REPLACE FUNCTION try_cast_int(text) RETURNS integer AS $$
BEGIN
    RETURN $1::integer;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

SELECT try_cast_int('123');  -- 123
SELECT try_cast_int('abc');  -- NULL

-- MySQL: 用 REGEXP + CASE 变通
SELECT
    CASE WHEN price_str REGEXP '^[0-9]+\.?[0-9]*$'
         THEN CAST(price_str AS DECIMAL(10,2))
         ELSE NULL
    END AS safe_price
FROM products;
-- 注意: REGEXP 验证不完整，边界情况多
```

## 设计分析: 三种命名策略

| 策略 | 引擎 | 示例 | 优点 | 缺点 |
|------|------|------|------|------|
| 前缀 `SAFE_` / `TRY_` | BigQuery, SQL Server, Snowflake | `SAFE_CAST`, `TRY_CAST` | 直观，与原函数名对应 | 每个函数需要一个安全变体 |
| 通用修饰 `SAFE.` / `TRY()` | BigQuery, Trino | `SAFE.func()`, `TRY(expr)` | 一个机制覆盖所有函数 | 实现复杂（需要捕获任意异常） |
| 后缀 `OrNull` / `OrZero` | ClickHouse | `toInt32OrNull` | 明确指定失败行为 | 函数名变长，变体多 |

**推荐**: 同时支持特定的 `TRY_CAST` 和通用的 `TRY(expr)`。前者覆盖最常见的类型转换场景（高频使用，值得专用语法），后者提供通用兜底。

## 对引擎开发者的实现建议

### 1. 错误处理策略

引擎内部需要支持两种错误传播模式：

```
模式 1: 严格模式 (默认)
  → 遇到错误抛出异常，终止查询

模式 2: 安全模式 (TRY/SAFE)
  → 遇到错误返回 NULL，继续执行
```

实现方式：

**方式 A: 异常捕获**

```
TRY_CAST(expr AS type):
    try:
        return CAST(expr AS type)
    catch ConversionError:
        return NULL
```

简单直接，但异常处理有性能开销（尤其当大量行转换失败时）。

**方式 B: 先验证再转换**

```
TRY_CAST(expr AS type):
    if canConvert(expr, type):
        return CAST(expr AS type)
    else:
        return NULL
```

避免异常开销，但需要为每种类型实现验证逻辑（且验证和转换的逻辑可能不同步）。

**方式 C: 标志位传递**

```
CAST(expr AS type, safe=true):
    // 在转换函数内部检查 safe 标志
    // 遇到错误时根据标志决定抛异常还是返回 NULL
```

最灵活，避免代码重复，但需要修改所有转换函数的签名。

**推荐方式 C**，在函数执行器中增加 `error_mode` 参数。

### 2. TRY() 通用包装的实现

BigQuery 的 `SAFE.` 和 Trino 的 `TRY()` 是通用机制，需要在执行框架层面支持：

```
TRY(expression):
    保存当前错误处理上下文
    设置错误处理模式 = SAFE
    result = evaluate(expression)
    恢复错误处理上下文
    return result   // 或 NULL（如果 evaluate 内部遇到错误）
```

实现要点：
- 需要在表达式求值器中支持"错误吞噬"模式
- `TRY` 内部的子表达式（包括嵌套函数调用）都应使用安全模式
- 注意: `TRY` 不应吞噬所有错误——类型不匹配、语法错误等应正常报错

### 3. NULL 传播与安全函数的交互

安全函数的 NULL 传播规则需要明确定义：

```sql
-- 输入是 NULL 时，安全函数的行为:
SAFE_CAST(NULL AS INT)  →  NULL   (与 CAST(NULL AS INT) 一致)
TRY_CAST(NULL AS INT)   →  NULL

-- 安全除法:
SAFE_DIVIDE(NULL, 5)    →  NULL   (NULL 传播)
SAFE_DIVIDE(10, NULL)   →  NULL   (NULL 传播)
SAFE_DIVIDE(10, 0)      →  NULL   (安全语义)
SAFE_DIVIDE(NULL, 0)    →  NULL   (NULL 传播优先)
```

### 4. 性能考量

在大量脏数据场景中，安全函数可能频繁触发错误路径。优化建议：

- 使用方式 C（标志位）避免异常创建和捕获的开销
- 对字符串到数字的转换，使用高效的字符扫描（不要先正则匹配再转换）
- 考虑批量处理: 收集错误行的索引，批量设置 NULL

## 参考资料

- BigQuery: [SAFE_CAST](https://cloud.google.com/bigquery/docs/reference/standard-sql/functions-and-operators#safe_casting)
- SQL Server: [TRY_CAST](https://learn.microsoft.com/en-us/sql/t-sql/functions/try-cast-transact-sql)
- Snowflake: [TRY_TO_NUMBER](https://docs.snowflake.com/en/sql-reference/functions/try_to_number)
- ClickHouse: [Type Conversion Functions](https://clickhouse.com/docs/en/sql-reference/functions/type-conversion-functions)
- Oracle: [VALIDATE_CONVERSION](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/VALIDATE_CONVERSION.html)
- Trino: [TRY function](https://trino.io/docs/current/functions/conditional.html#try)
