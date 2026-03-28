# 隐式与显式类型转换：各 SQL 方言转换矩阵全对比

> 参考资料:
> - [MySQL 8.0 - Type Conversion in Expression Evaluation](https://dev.mysql.com/doc/refman/8.0/en/type-conversion.html)
> - [PostgreSQL - pg_cast System Catalog](https://www.postgresql.org/docs/current/catalog-pg-cast.html)
> - [SQL Server - Data Type Conversion](https://learn.microsoft.com/en-us/sql/t-sql/data-types/data-type-conversion-database-engine)
> - [Oracle - Implicit and Explicit Data Conversion](https://docs.oracle.com/cd/B19306_01/server.102/b14200/sql_elements002.htm)
> - [BigQuery - Conversion Rules](https://cloud.google.com/bigquery/docs/reference/standard-sql/conversion_rules)
> - [Snowflake - Data Type Conversion](https://docs.snowflake.com/en/sql-reference/data-type-conversion)
> - [ClickHouse - Type Conversion Functions](https://clickhouse.com/docs/sql-reference/functions/type-conversion-functions)
> - [Hive - Language Manual Types](https://hive.apache.org/docs/latest/language/languagemanual-types/)
> - [Spark SQL - ANSI Compliance](https://spark.apache.org/docs/latest/sql-ref-ansi-compliance.html)

本文为每个主要 SQL 方言提供 Hive 官方文档风格的完整二维隐式类型转换矩阵，方便横向对比各引擎的差异。

**图例**：✅ = 允许隐式转换 | ❌ = 不允许（需要显式 CAST 或完全不支持）

---

## 1. MySQL 8.0 — 隐式类型转换矩阵

MySQL 是最宽松的传统 RDBMS。核心规则：不同类型比较时，双方转为 DOUBLE——这是 `'abc' = 0` 返回 TRUE 的根源。

> 来源: [MySQL 8.0 Type Conversion](https://dev.mysql.com/doc/refman/8.0/en/type-conversion.html)

| From ↓ \ To → | TINYINT | INT | BIGINT | FLOAT | DOUBLE | DECIMAL | VARCHAR | DATE | DATETIME | TIMESTAMP | JSON |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **TINYINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **INT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **BIGINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **FLOAT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **DOUBLE** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **DECIMAL** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **VARCHAR** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **DATE** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **DATETIME** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **TIMESTAMP** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **JSON** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

**⚠️ MySQL 独有陷阱：**

- **VARCHAR → 数字全部 ✅，但极其危险**: `'abc'` 隐式转为 `0`，`'42abc'` 转为 `42`。`SELECT 0 = 'abc'` 返回 TRUE
- **数字之间双向 ✅**: 包括窄化（BIGINT→TINYINT），可能溢出但不报错
- **JSON 完全孤立**: 进出都需要显式 CAST/`->>`，这反而是好设计
- **BOOL = TINYINT(1)**: 矩阵中未单列 BOOLEAN，因为它就是 TINYINT

---

## 2. PostgreSQL — 隐式类型转换矩阵

PostgreSQL 是最严格的传统 RDBMS。8.3（2008）移除了大量隐式转换。`pg_cast` 的 `castcontext` 分三级：`i`（隐式）、`a`（赋值时允许）、`e`（显式 CAST）。本表仅标注 `castcontext='i'` 的隐式转换。

> 来源: [PostgreSQL pg_cast](https://www.postgresql.org/docs/current/catalog-pg-cast.html)

| From ↓ \ To → | SMALLINT | INTEGER | BIGINT | REAL | FLOAT8 | NUMERIC | TEXT | DATE | TIMESTAMP | BOOLEAN | JSONB |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **SMALLINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **INTEGER** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **BIGINT** | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **REAL** | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **FLOAT8** | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **NUMERIC** | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **TEXT** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **DATE** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ |
| **TIMESTAMP** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| **BOOLEAN** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **JSONB** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

**关键差异（与 MySQL 对比）：**

- **TEXT → 任何非 TEXT = 全部 ❌**: `SELECT '1' + 2` 直接报错。这是与 MySQL 最大的区别
- **数字族仅单向提升 ✅**: `int → bigint` 隐式，但 `bigint → int` 需要 CAST
- **NUMERIC → FLOAT8 = ✅**: 但 **FLOAT8 → NUMERIC = ❌**（浮点到精确数需要显式）
- **DATE → TIMESTAMP = ✅**: 添加午夜时间，无损
- **BOOLEAN 完全孤立**: 不能隐式转为数字（不像 C 语言）

---

## 3. Oracle — 隐式类型转换矩阵

Oracle 介于 MySQL 和 PostgreSQL 之间。VARCHAR2 → NUMBER 在比较中隐式转换，但非数字字符串运行时报 ORA-01722。

> 来源: [Oracle Data Type Comparison Rules](https://docs.oracle.com/cd/B19306_01/server.102/b14200/sql_elements002.htm)

| From ↓ \ To → | NUMBER | BINARY_FLOAT | BINARY_DOUBLE | VARCHAR2 | CHAR | DATE | TIMESTAMP | CLOB |
|---|---|---|---|---|---|---|---|---|
| **NUMBER** | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **BINARY_FLOAT** | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **BINARY_DOUBLE** | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **VARCHAR2** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **CHAR** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **DATE** | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **TIMESTAMP** | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **CLOB** | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ✅ |

**⚠️ Oracle 独有特性：**

- **VARCHAR2 → NUMBER = ✅**: `WHERE number_col = '42'` 无需 CAST。但 `'abc'` 运行时抛 ORA-01722
- **VARCHAR2 → DATE = ✅**: 依赖 `NLS_DATE_FORMAT` 会话参数——格式因环境而异，强大但危险
- **'' = NULL**: Oracle 将零长度 VARCHAR2 视为 NULL，违反 SQL 标准
- **NUMBER 是统一类型**: INTEGER/DECIMAL 都是 NUMBER(p,s) 的别名，内部全是 ✅

---

## 4. SQL Server — 隐式类型转换矩阵

SQL Server 使用数据类型优先级决定转换方向。几乎所有数字 ↔ 字符串的转换都是隐式的。

> 来源: [SQL Server Data Type Conversion](https://learn.microsoft.com/en-us/sql/t-sql/data-types/data-type-conversion-database-engine)

| From ↓ \ To → | TINYINT | INT | BIGINT | FLOAT | DECIMAL | VARCHAR | NVARCHAR | DATE | DATETIME2 | BIT |
|---|---|---|---|---|---|---|---|---|---|---|
| **TINYINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| **INT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| **BIGINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| **FLOAT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| **DECIMAL** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| **VARCHAR** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **NVARCHAR** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **DATE** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **DATETIME2** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **BIT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |

**⚠️ SQL Server 关键陷阱：**

- **数字之间全部双向 ✅**: 包括窄化，与 MySQL 类似
- **VARCHAR → 数字 = ✅**: 隐式转换。但按数据类型优先级，`WHERE varchar_col = 123` 中 INT 优先级高于 VARCHAR，列值被转换 → **索引失效**
- **VARCHAR/NVARCHAR → DATE = ✅**: 识别多种格式（`'2024-01-15'`、`'Jan 15 2024'`）
- **BIT 即 BOOLEAN**: 与所有数字和字符串类型隐式互转

---

## 5. BigQuery — 隐式类型转换矩阵

BigQuery 非常严格。仅数字族内向上提升（用于 UNION/CASE/COALESCE 超类型解析）是隐式的。

> 来源: [BigQuery Conversion Rules](https://cloud.google.com/bigquery/docs/reference/standard-sql/conversion_rules)

| From ↓ \ To → | INT64 | FLOAT64 | NUMERIC | BIGNUMERIC | BOOL | STRING | DATE | TIMESTAMP | DATETIME | JSON |
|---|---|---|---|---|---|---|---|---|---|---|
| **INT64** | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **FLOAT64** | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **NUMERIC** | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **BIGNUMERIC** | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **BOOL** | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **STRING** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **DATE** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| **TIMESTAMP** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| **DATETIME** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **JSON** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

**关键特点：**

- **几乎全部 ❌**: 只有数字族内向上提升（INT64→FLOAT64、NUMERIC→FLOAT64 等）
- **STRING → 任何 = ❌**: `'42' + 1` 报错，必须 `CAST('42' AS INT64) + 1`
- **DATE ↛ TIMESTAMP = ❌**: 不像 PostgreSQL/Snowflake 那样隐式提升
- **SAFE_CAST**: 转换失败返回 NULL，`SAFE.` 前缀可用于任何函数

---

## 6. Snowflake — 隐式类型转换矩阵

Snowflake 中等严格。VARIANT 是万能供体，可隐式转为几乎所有标量类型。

> 来源: [Snowflake Data Type Conversion](https://docs.snowflake.com/en/sql-reference/data-type-conversion)

| From ↓ \ To → | NUMBER | FLOAT | VARCHAR | BOOLEAN | DATE | TIMESTAMP_NTZ | TIMESTAMP_LTZ | VARIANT |
|---|---|---|---|---|---|---|---|---|
| **NUMBER** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **FLOAT** | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **VARCHAR** | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **BOOLEAN** | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ |
| **DATE** | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ |
| **TIMESTAMP_NTZ** | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ |
| **TIMESTAMP_LTZ** | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **VARIANT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

**关键特点：**

- **VARIANT → 所有 = ✅**: 运行时根据实际值类型转换，值不兼容则报错
- **BOOLEAN → FLOAT/VARCHAR = ✅**: `TRUE` → `1.0` / `'true'`
- **DATE → TIMESTAMP_NTZ/LTZ = ✅**: 添加午夜时间
- **时间类型 → VARCHAR = ✅**: 所有时间类型可隐式转为字符串
- **VARCHAR → 数字 = ❌**: 不像 MySQL/Oracle 那样隐式转换
- **NUMBER ↔ FLOAT = ❌**: 需要显式 CAST

---

## 7. ClickHouse — 隐式类型转换矩阵

ClickHouse 是最严格的分析引擎。隐式转换仅限算术运算中的数字族提升，遵循 C++ 提升规则。

> 来源: [ClickHouse Type Conversion Functions](https://clickhouse.com/docs/sql-reference/functions/type-conversion-functions)

| From ↓ \ To → | Int8 | Int32 | Int64 | UInt64 | Float32 | Float64 | Decimal | String | Date | DateTime | Bool |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **Int8** | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Int32** | ❌ | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Int64** | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **UInt64** | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Float32** | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Float64** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Decimal** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **String** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| **Date** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| **DateTime** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **Bool** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

**关键特点：**

- **极度严格**: 只有整数/浮点族内的向上提升是隐式的
- **Decimal ↔ Float = ❌❌（禁止）**: `toDecimal64(1.5,2) + toFloat64(1.0)` 直接报错
- **String → 任何数字 = ❌**: `'42' + 1` 报错
- **首选语法**: `toInt64(x)` / `toString(x)` 而非 CAST
- **安全变体**: `toTypeOrNull()`（失败返回 NULL）、`toTypeOrZero()`（失败返回零值）

---

## 8. Hive — 隐式类型转换矩阵

Hive 在大数据引擎中相对宽松，遵循单向数字提升链。CAST 失败返回 NULL（永不报错）。

> 来源: [Hive Language Manual - Types](https://hive.apache.org/docs/latest/language/languagemanual-types/)

| From ↓ \ To → | TINYINT | SMALLINT | INT | BIGINT | FLOAT | DOUBLE | DECIMAL | STRING | VARCHAR | TIMESTAMP | DATE | BOOLEAN | BINARY |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **TINYINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **SMALLINT** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **INT** | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **BIGINT** | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **FLOAT** | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **DOUBLE** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **DECIMAL** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **STRING** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **VARCHAR** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **TIMESTAMP** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **DATE** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |
| **BOOLEAN** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **BINARY** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

**关键特点：**

- **单向提升链**: `TINYINT → SMALLINT → INT → BIGINT → FLOAT → DOUBLE → DECIMAL → STRING`
- **STRING → DOUBLE/DECIMAL = ✅**: 但 STRING → INT/BIGINT = ❌（不能跳级）
- **BOOLEAN 完全孤立**: 不能隐式转为数字或字符串
- **DATE ↛ TIMESTAMP = ❌**: 日期不能隐式转为时间戳
- **CAST 失败 = NULL**: Hive 的 CAST 永远不报错，因此不需要 TRY_CAST

---

## 9. Spark SQL — 隐式类型转换矩阵

Spark 有两套规则。4.0 起默认 ANSI 严格模式。

> 来源: [Spark SQL ANSI Compliance](https://spark.apache.org/docs/latest/sql-ref-ansi-compliance.html)

### ANSI 模式（`spark.sql.ansi.enabled=true`，4.0 默认）

| From ↓ \ To → | BYTE | SHORT | INT | LONG | FLOAT | DOUBLE | DECIMAL | STRING | DATE | TIMESTAMP | BOOLEAN |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **BYTE** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **SHORT** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **INT** | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **LONG** | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **FLOAT** | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **DOUBLE** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **DECIMAL** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **STRING** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| **DATE** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ |
| **TIMESTAMP** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **BOOLEAN** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

### Hive 模式（`spark.sql.ansi.enabled=false`）— 与 ANSI 模式的差异

| 场景 | ANSI 模式 | Hive 模式 |
|------|----------|----------|
| STRING → 数字隐式转换 | ❌ | ✅（同 Hive） |
| `CAST('abc' AS INT)` | 抛出异常 | 返回 NULL |
| `2147483647 + 1` 溢出 | 抛出异常 | 返回 `-2147483648`（静默溢出） |
| `INSERT INTO int_table VALUES('1')` | 报错 | 成功 |
| Float 跳过（LCT 解析） | 是（Int+Float→Double） | 否（Int+Float→Float） |

---

## 10. 横向对比速查表

### 各引擎严格度排名

| 排名 | 引擎 | STRING→NUMBER 隐式 | CAST 失败行为 |
|------|------|-------------------|-------------|
| 1（最松） | MySQL | ✅（`'abc'→0`） | 静默转为 0/NULL |
| 2 | SQL Server | ✅（运行时报错） | 运行时报错 |
| 3 | Oracle | ✅（运行时报错） | ORA-01722 |
| 4 | Hive | ✅（→DOUBLE） | 返回 NULL |
| 5 | Snowflake | ❌ | TRY_CAST 返回 NULL |
| 6 | Spark ANSI | ❌ | 抛出异常 |
| 7 | BigQuery | ❌ | SAFE_CAST 返回 NULL |
| 8 | ClickHouse | ❌ | toTypeOrNull 返回 NULL |
| 9（最严） | PostgreSQL | ❌ | 报错 |

### `SELECT 1/3` 整数除法

| 结果 = `0`（整数截断） | 结果 = `0.333...`（小数） |
|---|---|
| PostgreSQL、SQL Server、Spark ANSI | MySQL、Oracle、BigQuery、Snowflake、ClickHouse、Hive |

### TRY_CAST / SAFE_CAST 支持

| 引擎 | 语法 | 引入版本 |
|------|------|---------|
| SQL Server | `TRY_CAST(x AS type)` | 2012 |
| BigQuery | `SAFE_CAST(x AS type)` | GA |
| Snowflake | `TRY_CAST(x AS type)` | GA |
| Trino | `TRY_CAST(x AS type)` | 早期版本 |
| DuckDB | `TRY_CAST(x AS type)` | 0.8.0+ |
| Spark | `TRY_CAST(x AS type)` | 4.0 |
| Flink | `TRY_CAST(x AS type)` | 1.15+ |
| ClickHouse | `toTypeOrNull(x)` | 早期版本 |
| Hive | **不需要**（CAST 已返回 NULL） | — |
| PostgreSQL | **无内置** | — |
| MySQL | **无内置** | — |

---

## 对引擎开发者的设计建议

### 推荐的三级转换模型（借鉴 PostgreSQL pg_cast）

| 级别 | 触发条件 | 设计原则 | 示例 |
|------|---------|---------|------|
| **隐式** | 任何表达式自动触发 | 仅限同族**无损**转换 | `int → bigint`, `float32 → float64` |
| **赋值** | 仅 INSERT/UPDATE 时自动 | 可能截断但语义合理 | `varchar(100) → varchar(50)`, `timestamp → date` |
| **显式** | 必须 CAST | 可能丢失信息 | `text → integer`, `float → int` |

### 核心设计原则

1. **隐式转换必须无损**: 只在同类型族内提升，不允许跨类型族（MySQL 的 STRING→DOUBLE 是反面教材）
2. **比较时转常量不转列**: `WHERE int_col = '123'` 应转 `'123'` 为 int，而非列值转 string（SQL Server 按优先级转列值致索引失效）
3. **整数除法行为必须明确**: INT/INT 结果类型在设计之初确定，文档清楚标注
4. **TRY_CAST 从第一天支持**: 后期添加需改造整个表达式求值路径
5. **转换矩阵完整文档化**: 像 Hive 一样提供完整的二维矩阵，每对类型都有明确分类

---

*注：本页信息均来自各引擎官方文档。具体行为可能随版本变化，建议以目标版本的官方文档为准。*
