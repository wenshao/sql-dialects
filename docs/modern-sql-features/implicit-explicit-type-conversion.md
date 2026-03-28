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

## 10. IBM Db2 — 隐式类型转换矩阵

Db2 的隐式转换较为严格，遵循类型兼容性规则。数字族内单向提升。字符串可在赋值上下文隐式转为数字/日期，但在表达式中通常需要显式 CAST。

> 来源: [IBM Db2 12.1 - Promotion of Data Types](https://www.ibm.com/docs/en/db2/12.1?topic=rules-promotion-data-types)
> [IBM Db2 - Casting Between Data Types](https://www.ibm.com/docs/en/db2/12.1?topic=rules-casting-between-data-types)

| From ↓ \ To → | SMALLINT | INTEGER | BIGINT | REAL | DOUBLE | DECIMAL | VARCHAR | CHAR | CLOB | DATE | TIMESTAMP | BOOLEAN | XML | JSON |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **SMALLINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **INTEGER** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **BIGINT** | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **REAL** | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **DOUBLE** | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **DECIMAL** | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **VARCHAR** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **CHAR** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **CLOB** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **DATE** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **TIMESTAMP** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| **BOOLEAN** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| **XML** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **JSON** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

**关键特点：**

- **数字族单向提升**: `SMALLINT → INTEGER → BIGINT → DOUBLE`，`DECIMAL → DOUBLE`
- **REAL → DOUBLE = ✅**: 但 REAL/DOUBLE → DECIMAL = ❌（浮点到精确数不允许隐式）
- **字符串 → 数字 = ❌**: Db2 在表达式上下文中不允许 `'42' + 1`，需要显式 CAST
- **VARCHAR ↔ CHAR = ✅**: 定长和变长字符串之间可互转
- **VARCHAR/CHAR → CLOB = ✅**: 字符串到大对象单向提升
- **DATE → TIMESTAMP = ✅**: 添加午夜时间（`00:00:00`），无损
- **BOOLEAN/XML/JSON 完全孤立**: 不与任何其他类型隐式互转
- **Db2 11.1+ BOOLEAN**: 早期版本无原生 BOOLEAN，使用 SMALLINT 替代

---

## 11. SAP HANA — 隐式类型转换矩阵

SAP HANA 的隐式转换介于 PostgreSQL 和 Oracle 之间。数字族内向上提升，字符串在比较上下文可隐式转为数字和日期。

> 来源: [SAP HANA - Data Type Conversion](https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/20a1569675191014b285e3e53b215cda.html)

| From ↓ \ To → | TINYINT | SMALLINT | INT | BIGINT | REAL | DOUBLE | DECIMAL | VARCHAR | NVARCHAR | DATE | TIMESTAMP | BOOLEAN | VARBINARY |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **TINYINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **SMALLINT** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **INT** | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **BIGINT** | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **REAL** | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **DOUBLE** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **DECIMAL** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **VARCHAR** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| **NVARCHAR** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| **DATE** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ |
| **TIMESTAMP** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| **BOOLEAN** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **VARBINARY** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

**关键特点：**

- **数字族单向提升**: `TINYINT → SMALLINT → INT → BIGINT → DOUBLE`，`DECIMAL → DOUBLE`
- **VARCHAR/NVARCHAR → 数字 = ✅**: 在比较上下文中，`WHERE int_col = '42'` 自动转换。非数字字符串运行时报错
- **VARCHAR/NVARCHAR → DATE/TIMESTAMP = ✅**: 依赖字符串格式，格式不匹配运行时报错
- **VARCHAR ↔ NVARCHAR = ✅**: 两种字符串类型之间双向隐式转换
- **REAL/DOUBLE → DECIMAL = ❌**: 浮点到精确数需要显式 CAST
- **DATE → TIMESTAMP = ✅**: 添加午夜时间，无损
- **BOOLEAN/VARBINARY 完全孤立**: 不与其他类型隐式互转
- **NVARCHAR 是默认字符类型**: SAP HANA 列存储默认使用 Unicode

---

## 12. Teradata — 隐式类型转换矩阵

Teradata 隐式转换中等严格。数字族内双向转换较宽松（含窄化），字符串在比较上下文可转数字。DATE 内部存储为 INTEGER。

> 来源: [Teradata Vantage - Data Type Conversions](https://docs.teradata.com/r/Teradata-VantageTM-Data-Types-and-Literals/)

| From ↓ \ To → | BYTEINT | SMALLINT | INTEGER | BIGINT | FLOAT | DECIMAL | VARCHAR | CHAR | DATE | TIMESTAMP | BYTE |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **BYTEINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **SMALLINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **INTEGER** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **BIGINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **FLOAT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **DECIMAL** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **VARCHAR** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **CHAR** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **DATE** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **TIMESTAMP** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ |
| **BYTE** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

**关键特点：**

- **数字族全部双向 ✅**: 包括窄化（BIGINT→BYTEINT），可能溢出运行时报错。与 SQL Server 类似
- **VARCHAR/CHAR → 数字 = ✅**: `WHERE int_col = '42'` 隐式转换。非数字字符串运行时报错
- **VARCHAR/CHAR → DATE/TIMESTAMP = ✅**: 依赖会话 DATE FORMAT 设置
- **DATE → VARCHAR/CHAR = ✅**: 日期可隐式格式化为字符串
- **TIMESTAMP → VARCHAR/CHAR = ✅**: 时间戳可隐式格式化为字符串
- **DATE → TIMESTAMP = ✅**: 添加午夜时间
- **TIMESTAMP → DATE = ❌**: 需要显式 CAST（截断时间部分是有损操作）
- **DATE 内部 = INTEGER**: Teradata 的 DATE 内部以整数存储（`(year - 1900) * 10000 + month * 100 + day`），但不允许隐式互转
- **BYTE 完全孤立**: 二进制类型不与其他类型隐式互转
- **TRY_CAST**: Teradata 16.20+ 支持 TRY_CAST（转换失败返回 NULL）

---

## 13. Vertica — 隐式类型转换矩阵

Vertica 派生自 PostgreSQL，隐式转换规则较严格。数字族内单向提升，字符串不会隐式转为数字。

> 来源: [Vertica Documentation - Data Type Coercion](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/DataTypes/DataTypeCoercionChart.htm)

| From ↓ \ To → | INT | FLOAT | NUMERIC | VARCHAR | BOOLEAN | DATE | TIMESTAMP | VARBINARY |
|---|---|---|---|---|---|---|---|---|
| **INT** | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **FLOAT** | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **NUMERIC** | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **VARCHAR** | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **BOOLEAN** | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| **DATE** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ |
| **TIMESTAMP** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **VARBINARY** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

**关键特点：**

- **继承 PostgreSQL 严格性**: 隐式转换非常保守，仅限同族无损提升
- **INT → FLOAT/NUMERIC = ✅**: 整数到浮点/精确数无损提升
- **NUMERIC → FLOAT = ✅**: 精确数到浮点（可能丢失精度但允许）
- **FLOAT → NUMERIC = ❌**: 浮点到精确数需要显式 CAST
- **VARCHAR → 任何非 VARCHAR = ❌**: `'42' + 1` 报错，必须显式 CAST
- **DATE → TIMESTAMP = ✅**: 添加午夜时间，无损
- **BOOLEAN 完全孤立**: 不能隐式转为数字或字符串（PostgreSQL 风格）
- **VARBINARY 完全孤立**: 二进制类型不与其他类型隐式互转
- **支持 :: 语法**: `'42'::INT` 等价于 `CAST('42' AS INT)`，继承自 PostgreSQL
- **无 TRY_CAST**: 转换失败直接报错，建议用 CASE + REGEXP_LIKE 预验证

---

## 14. TiDB — 隐式类型转换矩阵

TiDB 高度兼容 MySQL，官方文档明确声明类型转换规则与 MySQL 相同。核心规则：不同类型比较时双方转为 DOUBLE，继承了 MySQL 的 `'abc' = 0` 陷阱。BOOLEAN 是 TINYINT(1) 的别名。

> 来源: [TiDB Type Conversion in Expression Evaluation](https://docs.pingcap.com/tidb/stable/type-conversion-in-expression-evaluation/)
> [TiDB Avoid Implicit Type Conversions](https://docs.pingcap.com/tidb/stable/dev-guide-implicit-type-conversion/)

| From ↓ \ To → | TINYINT | INT | BIGINT | FLOAT | DOUBLE | DECIMAL | VARCHAR | TEXT | DATE | DATETIME | TIMESTAMP | BOOLEAN | JSON |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **TINYINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **INT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **BIGINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **FLOAT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **DOUBLE** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **DECIMAL** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **VARCHAR** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **TEXT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **DATE** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| **DATETIME** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| **TIMESTAMP** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| **BOOLEAN** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **JSON** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

**与 MySQL 的关系及 TiDB 特有注意事项：**

- **规则与 MySQL 相同**: TiDB 官方文档声明 "TiDB behaves the same as MySQL"，上述矩阵继承自 MySQL 8.0 规则
- **BOOLEAN = TINYINT(1)**: 与 MySQL 完全一致，BOOLEAN 与所有数字类型双向隐式转换
- **VARCHAR/TEXT → 数字 = ✅（但危险）**: 继承 MySQL 的 `'abc' → 0` 行为，`SELECT 0 = 'abc'` 返回 TRUE
- **DECIMAL + VARCHAR 比较陷阱**: TiDB 中 `DECIMAL(32,0)` 列与字符串比较时，双方都转为 DOUBLE，可能丢失精度导致错误匹配
- **索引失效**: 当 VARCHAR 主键与数字比较时（`WHERE varchar_pk = 12345`），隐式转换导致无法使用索引——TiDB 文档专门警告此问题
- **JSON 完全孤立**: 进出都需要显式转换或 `->>` 操作符
- **Float 精度差异**: TiDB 允许 `FLOAT(1-255)` 而 MySQL 仅支持 `FLOAT(1-53)`，可能导致迁移时精度不一致
- **DOUBLE 显示差异**: `DOUBLE(5,3)` 列，MySQL 返回 `'1.000'`，TiDB 返回 `'1'`

---

## 15. OceanBase（MySQL 模式）— 隐式类型转换矩阵

OceanBase MySQL 模式遵循 MySQL 5.7/8.0 的类型转换规则。在 MySQL 模式下，OceanBase 兼容 MySQL 的协议、语法和表达式求值行为，包括隐式类型转换规则。

> 来源: [OceanBase MySQL Compatibility](https://en.oceanbase.com/docs/common-oceanbase-database-10000000001970955)
> [OceanBase Type Conversion Functions](https://en.oceanbase.com/docs/common-oceanbase-database-10000000000829714)

| From ↓ \ To → | TINYINT | INT | BIGINT | FLOAT | DOUBLE | DECIMAL | VARCHAR | TEXT | DATE | DATETIME | TIMESTAMP | BOOLEAN | JSON |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **TINYINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **INT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **BIGINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **FLOAT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **DOUBLE** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **DECIMAL** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **VARCHAR** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **TEXT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **DATE** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| **DATETIME** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| **TIMESTAMP** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| **BOOLEAN** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **JSON** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

**OceanBase MySQL 模式关键特点：**

- **与 MySQL 规则一致**: MySQL 模式下的隐式转换规则继承自 MySQL 5.7/8.0，矩阵与 MySQL/TiDB 相同
- **双模架构**: OceanBase 同一集群中不同租户可运行 MySQL 模式或 Oracle 模式，Oracle 模式下矩阵参考本文 Oracle 章节
- **VARCHAR → 数字 = ✅（继承 MySQL 陷阱）**: `'abc'` 隐式转为 `0`，`SELECT 0 = 'abc'` 返回 TRUE
- **BOOLEAN = TINYINT(1)**: 与 MySQL 完全一致
- **JSON 完全孤立**: 与 MySQL 行为一致，进出需要显式转换
- **数字族双向 ✅**: 包括窄化转换（BIGINT→TINYINT），继承 MySQL 的宽松策略
- **迁移注意**: OMS（OceanBase Migration Service）在数据迁移时，若源端类型不被目标支持可能触发额外的隐式转换，导致源端和目标端列类型不一致

---

## 16. CockroachDB — 隐式类型转换矩阵

CockroachDB 兼容 PostgreSQL，但比 PostgreSQL 更严格。设计哲学是"避免隐式类型强制转换"——使用上下文感知的多态字面量类型解析代替隐式转换。支持三级转换上下文：隐式（Implicit）、赋值（Assignment）、显式（Explicit），与 PostgreSQL 的 `pg_cast.castcontext` 一致。

> 来源: [CockroachDB Data Types](https://www.cockroachlabs.com/docs/stable/data-types)
> [CockroachDB cast_map.go](https://github.com/cockroachdb/cockroach/blob/master/pkg/sql/sem/cast/cast_map.go)
> [Revisiting SQL Typing in CockroachDB](https://www.cockroachlabs.com/blog/revisiting-sql-typing-in-cockroachdb/)

**图例**：✅ = 隐式转换（Implicit） | A = 仅赋值上下文（Assignment，INSERT/UPDATE 时自动） | ❌ = 需要显式 CAST

| From ↓ \ To → | INT | INT8 | FLOAT | DECIMAL | STRING | BYTES | DATE | TIMESTAMP | TIMESTAMPTZ | BOOL | JSONB | UUID |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **INT** | ✅ | ✅ | ✅ | ✅ | A | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **INT8** | A | ✅ | ✅ | ✅ | A | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **FLOAT** | A | A | ✅ | A | A | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **DECIMAL** | A | A | ✅ | ✅ | A | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **STRING** | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **BYTES** | ❌ | ❌ | ❌ | ❌ | A | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **DATE** | ❌ | ❌ | ❌ | ❌ | A | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **TIMESTAMP** | ❌ | ❌ | ❌ | ❌ | A | ❌ | A | ✅ | ✅ | ❌ | ❌ | ❌ |
| **TIMESTAMPTZ** | ❌ | ❌ | ❌ | ❌ | A | ❌ | A | A | ✅ | ❌ | ❌ | ❌ |
| **BOOL** | ❌ | ❌ | ❌ | ❌ | A | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| **JSONB** | ❌ | ❌ | ❌ | ❌ | A | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **UUID** | ❌ | ❌ | ❌ | ❌ | A | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

**CockroachDB 关键特点：**

- **比 PostgreSQL 更严格**: 设计团队明确表示"nothing good comes out of a language that allows implicit type coercions"
- **STRING → 非 STRING = 全部 ❌**: `'42' + 1` 报错，与 PostgreSQL 一致。但字面量 `42` 可根据上下文自动解析为 INT/FLOAT/DECIMAL（多态字面量，非隐式转换）
- **赋值上下文（A）广泛存在**: `INSERT INTO float_col VALUES (42)` 成功——整数字面量在赋值时自动转为 FLOAT。这是 v22.1 引入的 PostgreSQL 兼容性改进
- **数字族隐式提升**: `INT→INT8→DECIMAL` 和 `INT→FLOAT` 为隐式，但 `FLOAT→INT` 和 `FLOAT→DECIMAL` 仅在赋值上下文
- **DECIMAL→FLOAT = ✅（隐式）**: 与 PostgreSQL 的 `NUMERIC→FLOAT8` 隐式转换一致
- **DATE→TIMESTAMP/TIMESTAMPTZ = ✅（隐式）**: 添加午夜时间，与 PostgreSQL 一致
- **TIMESTAMP→TIMESTAMPTZ = ✅（隐式）**: 使用会话时区，与 PostgreSQL 一致
- **TIMESTAMPTZ→TIMESTAMP = A（仅赋值）**: 反向转换丢失时区信息，需赋值上下文
- **BOOL 完全孤立**: `BOOL→INT` 需要显式 CAST（PostgreSQL 也不允许隐式）。但 CockroachDB 允许 BOOL 显式转为更多数字类型
- **JSONB 完全孤立**: 仅 `JSONB→STRING` 在赋值上下文可用，提取值需要 `->>` 操作符
- **UUID→STRING = A**: UUID 在赋值上下文自动格式化为字符串

---

## 17. SQLite — 隐式类型转换矩阵

SQLite 使用动态类型系统，值有五种存储类（NULL、INTEGER、REAL、TEXT、BLOB），列有类型亲和性（affinity）而非严格类型。亲和性只是「偏好」，不是约束。比较操作和运算会按亲和性规则自动转换操作数。

> 来源: [SQLite Datatypes - Type Affinity](https://sqlite.org/datatype3.html)

| From ↓ \ To → | INTEGER | REAL | TEXT | BLOB | NULL |
|---|---|---|---|---|---|
| **INTEGER** | ✅ | ✅ | ✅ | ❌ | ❌ |
| **REAL** | ✅ | ✅ | ✅ | ❌ | ❌ |
| **TEXT** | ✅ | ✅ | ✅ | ❌ | ❌ |
| **BLOB** | ❌ | ❌ | ❌ | ✅ | ❌ |
| **NULL** | ❌ | ❌ | ❌ | ❌ | ✅ |

**⚠️ SQLite 独有特性：**

- **极度宽松的动态类型**: 任何列可以存储任何类型的值（STRICT 表除外）。矩阵反映的是比较/运算时的隐式类型强制转换行为
- **TEXT → INTEGER/REAL = ✅（条件性）**: 当 TEXT 值是合法的整数/实数字面量时自动转换；非数字文本转为 `0`，不报错
- **INTEGER ↔ REAL = ✅**: 双向隐式转换。`1 = 1.0` 返回 TRUE
- **INTEGER/REAL → TEXT = ✅**: 数字与 TEXT 亲和性列比较时，数字转为文本表示
- **BLOB 孤立**: BLOB 不参与隐式转换，比较时使用 `memcmp()`
- **NULL 特殊**: NULL 不等于任何值（包括 NULL 本身），遵循三值逻辑
- **比较中的亲和性规则**: 若一方有 INTEGER/REAL/NUMERIC 亲和性而另一方有 TEXT 或无亲和性，则 NUMERIC 亲和性应用于后者
- **无 BOOLEAN 类型**: `TRUE`/`FALSE` 就是 `1`/`0`（INTEGER）
- **无 DATE/TIMESTAMP 类型**: 日期时间用 TEXT（ISO-8601）、REAL（Julian day）或 INTEGER（Unix timestamp）表示

---

## 18. MariaDB — 隐式类型转换矩阵

MariaDB 的隐式类型转换规则与 MySQL 8.0 高度一致，核心差异在于 MariaDB 独有的 INET6 和 UUID 类型。

> 来源: [MariaDB Type Conversion](https://mariadb.com/kb/en/type-conversion/)

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

**⚠️ MariaDB 与 MySQL 8.0 的差异：**

- **矩阵本体几乎一致**: 隐式转换规则（数字互转、VARCHAR→数字、时间族互转）与 MySQL 8.0 相同
- **MariaDB 独有类型 — INET6**: 不参与隐式转换。从 VARCHAR 到 INET6 或反向均需显式 CAST
- **MariaDB 独有类型 — UUID**: 不参与隐式转换。必须通过 CAST 与 VARCHAR 互转
- **JSON 实现差异**: MariaDB 中 JSON 是 `LONGTEXT` 的别名（非独立二进制类型），但隐式转换行为与 MySQL 相同——进出 JSON 都需要 CAST/JSON 函数
- **算术运算规则相同**: STRING + 数字 → DOUBLE；DECIMAL + FLOAT → DOUBLE
- **`'abc' = 0` 陷阱相同**: MariaDB 与 MySQL 一样，VARCHAR→数字隐式转换时非数字字符串变为 `0`

---

## 19. Azure Synapse Analytics — 隐式类型转换矩阵

Azure Synapse（专用 SQL 池）基于 T-SQL，转换规则与 SQL Server 高度一致。主要差异在于不支持某些 SQL Server 数据类型。

> 来源: [SQL Server Data Type Conversion](https://learn.microsoft.com/en-us/sql/t-sql/data-types/data-type-conversion-database-engine) | [Azure Synapse Table Data Types](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql-data-warehouse/sql-data-warehouse-tables-data-types)

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

**⚠️ Azure Synapse 与 SQL Server 的差异：**

- **矩阵本体一致**: 隐式转换规则完全继承自 SQL Server T-SQL 引擎
- **不支持的类型**: `geography`、`geometry`、`hierarchyid`、`image`、`text`、`ntext`、`sql_variant`、`xml` 在 Synapse 中不可用——SQL Server 矩阵中涉及这些类型的行/列不适用
- **VARCHAR(MAX) 限制**: 聚集列存储索引（CCI）表不支持 `VARCHAR(MAX)` / `NVARCHAR(MAX)`，需指定明确长度
- **CTAS 陷阱**: `CREATE TABLE AS SELECT` 中无法设置列的类型和可空性，必须在 SELECT 中显式 CAST，否则类型推导可能出错
- **无 USER-DEFINED TYPES**: `CREATE TYPE` 不可用，SQL Server 中依赖 UDT 的转换逻辑不适用
- **TRY_CAST 可用**: 与 SQL Server 一致，支持 `TRY_CAST(x AS type)` 安全转换

---

## 20. Impala — 隐式类型转换矩阵

Impala 比 Hive 更严格。数字族内仅允许向上提升（窄→宽），STRING 不能隐式转为数字，但可隐式转为 TIMESTAMP。

> 来源: [Impala Data Types](https://impala.apache.org/docs/build/html/topics/impala_datatypes.html) | [Impala Type Conversion Functions](https://impala.apache.org/docs/build/html/topics/impala_conversion_functions.html)

| From ↓ \ To → | TINYINT | SMALLINT | INT | BIGINT | FLOAT | DOUBLE | DECIMAL | STRING | VARCHAR | CHAR | BOOLEAN | TIMESTAMP | DATE |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **TINYINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **SMALLINT** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **INT** | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **BIGINT** | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **FLOAT** | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **DOUBLE** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **DECIMAL** | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **STRING** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ |
| **VARCHAR** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **CHAR** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **BOOLEAN** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| **TIMESTAMP** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ |
| **DATE** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ |

**⚠️ Impala 与 Hive 的关键差异：**

- **STRING → 数字 = ❌**: Hive 允许 `STRING → DOUBLE/DECIMAL` 隐式转换，Impala 全部禁止。这是最大差异
- **STRING → TIMESTAMP = ✅**: Impala 自动识别 `'yyyy-MM-dd HH:mm:ss.SSSSSS'` 格式的字符串并隐式转为 TIMESTAMP
- **FLOAT/DOUBLE → DECIMAL = ❌**: 浮点到精确数禁止隐式转换，会报错（非返回 NULL）
- **DECIMAL → FLOAT/DOUBLE = ✅**: 反向允许，即使可能丢失精度
- **整数 → DECIMAL = ✅（条件性）**: 仅当 DECIMAL 精度足以容纳所有整数位时才允许
- **BOOLEAN 完全孤立**: 不能隐式转为任何类型，也不能从任何类型隐式转入
- **TIMESTAMP ↔ STRING = ✅**: 双向隐式转换（Hive 中 TIMESTAMP→STRING ✅ 但 STRING→TIMESTAMP ❌）
- **TIMESTAMP → DATE = ✅**: 截断时间部分
- **DATE → TIMESTAMP = ✅**: 添加午夜时间
- **CAST 失败 = NULL**: 与 Hive 一致，CAST 转换失败返回 NULL

---

## 21. StarRocks — 隐式类型转换矩阵

StarRocks 是最宽松的分析引擎之一。内部维护一个极大的 `IMPLICIT_CAST_MAP`，几乎所有标量类型之间都允许隐式转换。与 MySQL 的宽松风格一脉相承。

> 来源: [StarRocks 源码 PrimitiveType.java IMPLICIT_CAST_MAP](https://github.com/StarRocks/starrocks/blob/main/fe/fe-type/src/main/java/com/starrocks/type/PrimitiveType.java)

| From ↓ \ To → | BOOLEAN | TINYINT | SMALLINT | INT | BIGINT | LARGEINT | FLOAT | DOUBLE | DECIMAL | VARCHAR | CHAR | DATE | DATETIME | JSON |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **BOOLEAN** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **TINYINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **SMALLINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **INT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **BIGINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **LARGEINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **FLOAT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **DOUBLE** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **DECIMAL** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **VARCHAR** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **CHAR** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **DATE** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **DATETIME** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **JSON** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ | ❌ | ✅ |

**关键特点：**

- **极度宽松**: `IMPLICIT_CAST_MAP` 允许几乎所有标量类型之间的隐式转换，仅 DECIMAL 和 JSON 有限制
- **BOOLEAN/整数/浮点/字符串/日期 之间全部双向 ✅**: 包括 `DATE → INT`、`BOOLEAN → VARCHAR` 等跨族转换
- **DECIMAL 特殊处理**: DECIMAL 可以隐式转为所有数字类型和字符串，但不能转为 DATE/DATETIME/JSON
- **JSON 半隔离**: JSON 可以隐式转为 BOOLEAN、所有数字类型、字符串，但不能转为 DATE/DATETIME
- **与 MySQL 相似**: StarRocks 定位为 MySQL 兼容分析引擎，隐式转换同样激进
- **运行时报错**: 宽松的隐式转换不代表安全——`CAST('abc' AS INT)` 运行时会报错

---

## 22. Apache Doris — 隐式类型转换矩阵

Doris 与 StarRocks 同源（均来自百度 Palo），但 Doris 的新优化器（Nereids）中隐式转换规则显著更保守。核心逻辑在 `TypeCoercionUtils.implicitCast()` 中。

> 来源: [Doris 源码 TypeCoercionUtils.java](https://github.com/apache/doris/blob/master/fe/fe-core/src/main/java/org/apache/doris/nereids/util/TypeCoercionUtils.java)
> [Doris 类型转换文档](https://github.com/apache/doris-website/tree/master/docs/sql-manual/basic-element/sql-data-types/conversion)

| From ↓ \ To → | BOOLEAN | TINYINT | SMALLINT | INT | BIGINT | LARGEINT | FLOAT | DOUBLE | DECIMAL | VARCHAR | CHAR | DATE | DATETIME | JSON |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **BOOLEAN** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **TINYINT** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ |
| **SMALLINT** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ |
| **INT** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ |
| **BIGINT** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ |
| **LARGEINT** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ |
| **FLOAT** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ |
| **DOUBLE** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ |
| **DECIMAL** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ |
| **VARCHAR** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| **CHAR** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| **DATE** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **DATETIME** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ |
| **JSON** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

**关键特点：**

- **数字族内全双向 ✅**: 包括窄化（BIGINT→TINYINT），与 StarRocks 相同
- **数字 → DATETIME = ✅**: 数字可隐式转为时间戳（如 `20240115` → `2024-01-15 00:00:00`）
- **VARCHAR/CHAR → 数字/DECIMAL/DATETIME/JSON = ✅**: 字符串可以隐式转为大多数类型
- **DATE → DATETIME = ✅**: 添加午夜时间，无损
- **BOOLEAN 较孤立**: 只能隐式转为字符串，不能转为数字（与 StarRocks 不同）
- **JSON 完全孤立**: 只能自转自（进出都需要显式 CAST），不像 StarRocks 那样开放
- **PrimitiveType → 字符串 = ✅**: 所有基本类型都可以隐式转为 VARCHAR/CHAR
- **与 StarRocks 的分歧**: 虽然同源，但 Doris 显著更保守——BOOLEAN 不能转数字，JSON 完全孤立，DATE/DATETIME 不能转数字

---

## 23. Google Cloud Spanner — 隐式类型转换矩阵

Spanner（GoogleSQL）是最严格的引擎之一，与 BigQuery 同源。隐式转换仅限数字族内的向上提升和 DATE→TIMESTAMP。

> 来源: [Spanner Conversion Rules](https://cloud.google.com/spanner/docs/reference/standard-sql/conversion_rules)

| From ↓ \ To → | BOOL | INT64 | FLOAT32 | FLOAT64 | NUMERIC | STRING | BYTES | DATE | TIMESTAMP | JSON | ARRAY |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **BOOL** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **INT64** | ❌ | ✅ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **FLOAT32** | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **FLOAT64** | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **NUMERIC** | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **STRING** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **BYTES** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **DATE** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ |
| **TIMESTAMP** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| **JSON** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **ARRAY** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

**关键特点：**

- **极度严格（Google 风格）**: 与 BigQuery 几乎完全相同，只有数字族内向上提升和 DATE→TIMESTAMP
- **INT64 → NUMERIC/FLOAT64 = ✅**: 整数可隐式提升为精确数或浮点数
- **INT64 → FLOAT32 = ❌**: 与 BigQuery 相同，INT64 不能隐式转为 FLOAT32（避免精度损失，INT64 最大值超出 FLOAT32 精度）
- **FLOAT32 → FLOAT64 = ✅**: 单精度到双精度无损提升
- **NUMERIC → FLOAT64 = ✅**: 精确数到浮点提升（可能丢失精度但域更大）
- **STRING → 任何 = ❌**: `'42' + 1` 报错，必须 `CAST('42' AS INT64) + 1`
- **DATE → TIMESTAMP = ✅**: 添加午夜时间（使用会话时区）
- **BOOL/STRING/BYTES/JSON/ARRAY 完全孤立**: 只能自转自
- **超类型（Supertype）机制**: Spanner 区分隐式转换和超类型解析——UNION/CASE/COALESCE 使用超类型规则（INT64 的超类型包括 FLOAT32），但超类型不等于隐式转换
- **SAFE_CAST**: `SAFE_CAST(x AS type)` 转换失败返回 NULL

---

## 24. MaxCompute — 隐式类型转换矩阵

MaxCompute 源自 Hive 但有自己的扩展。单向数字提升链，STRING 可隐式转为 DOUBLE/DECIMAL，BOOLEAN 完全孤立。

> 来源: [MaxCompute 数据类型](https://help.aliyun.com/zh/maxcompute/user-guide/data-type-editions)

| From ↓ \ To → | TINYINT | SMALLINT | INT | BIGINT | FLOAT | DOUBLE | DECIMAL | STRING | VARCHAR | DATE | DATETIME | TIMESTAMP | BOOLEAN | BINARY |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **TINYINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **SMALLINT** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **INT** | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **BIGINT** | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **FLOAT** | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **DOUBLE** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **DECIMAL** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **STRING** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **VARCHAR** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **DATE** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| **DATETIME** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ | ❌ |
| **TIMESTAMP** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ |
| **BOOLEAN** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **BINARY** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

**与 Hive 的差异**: MaxCompute 支持 DATE→DATETIME→TIMESTAMP 隐式提升链（Hive 的 DATE↛TIMESTAMP）。BOOLEAN 和 BINARY 同样完全孤立。

---

## 25. Hologres — 隐式类型转换矩阵

Hologres 兼容 PostgreSQL，继承 PG 的 `pg_cast` 三级体系。隐式转换规则与 PostgreSQL 基本一致。

> 来源: [Hologres 数据类型](https://help.aliyun.com/zh/hologres/user-guide/data-types)

矩阵与 [PostgreSQL（第 2 节）](#2-postgresql--隐式类型转换矩阵) 一致。参见 PostgreSQL 矩阵。

---

## 26. Flink SQL — 隐式类型转换矩阵

Flink 比 Hive 更宽松：VARCHAR/CHAR 是"万能源"，可隐式转为几乎所有类型。支持 TRY_CAST（1.15+）。

> 来源: [Flink SQL Data Types](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/)

| From ↓ \ To → | TINYINT | SMALLINT | INT | BIGINT | FLOAT | DOUBLE | DECIMAL | VARCHAR | BOOLEAN | DATE | TIMESTAMP |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **TINYINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **SMALLINT** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **INT** | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **BIGINT** | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **FLOAT** | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **DOUBLE** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **DECIMAL** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **VARCHAR** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **BOOLEAN** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ |
| **DATE** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ |
| **TIMESTAMP** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ |

**关键特点**: VARCHAR 是"万能源"（全行 ✅），所有类型也都可隐式转为 VARCHAR。DATE↔TIMESTAMP 双向隐式。TRY_CAST（1.15+）失败返回 NULL。

---

## 27. Trino — 隐式类型转换矩阵

Trino 严格，仅数字族向上提升和 DATE→TIMESTAMP 是隐式的。无 `::` 运算符。

> 来源: [Trino Conversion Functions](https://trino.io/docs/current/functions/conversion.html)

| From ↓ \ To → | TINYINT | SMALLINT | INTEGER | BIGINT | REAL | DOUBLE | DECIMAL | VARCHAR | DATE | TIMESTAMP | BOOLEAN |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **TINYINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **SMALLINT** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **INTEGER** | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **BIGINT** | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **REAL** | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **DOUBLE** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **DECIMAL** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **VARCHAR** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| **DATE** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ |
| **TIMESTAMP** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **BOOLEAN** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

**关键特点**: BIGINT→REAL = ❌（防止精度丢失）。TRY_CAST 和 TRY(expr) 都支持。

---

## 28. DuckDB — 隐式类型转换矩阵

DuckDB 0.10+ 类似 PostgreSQL 严格度。VARCHAR 列不再隐式转为其他类型（字符串字面量仍可以）。

> 来源: [DuckDB Typecasting](https://duckdb.org/docs/stable/sql/data_types/typecasting)

| From ↓ \ To → | TINYINT | SMALLINT | INTEGER | BIGINT | FLOAT | DOUBLE | DECIMAL | VARCHAR | DATE | TIMESTAMP | BOOLEAN |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **TINYINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **SMALLINT** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **INTEGER** | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **BIGINT** | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **FLOAT** | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **DOUBLE** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **DECIMAL** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **VARCHAR** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| **DATE** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ |
| **TIMESTAMP** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **BOOLEAN** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

**关键特点**: 0.10 前 VARCHAR→数字是隐式的，0.10 后改为严格（`old_implicit_casting` 可回退）。支持 TRY_CAST 和 `::` 运算符。

---

## 29. Databricks SQL — 隐式类型转换矩阵

基于 Spark，默认 ANSI 模式但增加了隐式降级转换（downcast）和 STRING 跨类型转换。比原版 Spark ANSI 更宽松。

> 来源: [Databricks SQL Data Type Rules](https://docs.databricks.com/sql/language-manual/sql-ref-datatype-rules)

| From ↓ \ To → | TINYINT | INT | BIGINT | FLOAT | DOUBLE | DECIMAL | STRING | DATE | TIMESTAMP | BOOLEAN |
|---|---|---|---|---|---|---|---|---|---|---|
| **TINYINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **INT** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **BIGINT** | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **FLOAT** | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ |
| **DOUBLE** | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ |
| **DECIMAL** | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **STRING** | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ |
| **DATE** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ |
| **TIMESTAMP** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ |
| **BOOLEAN** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ |

**与 Spark ANSI 差异**: STRING→BIGINT/DOUBLE/BOOLEAN/DATE/TIMESTAMP 隐式（Spark ANSI 中全部 ❌）。支持函数调用时的隐式降级（DOUBLE→INT 等）。

---

## 30. Redshift — 隐式类型转换矩阵

基于 PostgreSQL 但远比 PG 宽松。数字之间双向隐式（含窄化），VARCHAR→数字隐式，BOOLEAN↔整数隐式。

> 来源: [Redshift Type Conversion](https://docs.aws.amazon.com/redshift/latest/dg/r_Type_conversion.html)

| From ↓ \ To → | SMALLINT | INTEGER | BIGINT | REAL | DOUBLE | DECIMAL | VARCHAR | DATE | TIMESTAMP | BOOLEAN |
|---|---|---|---|---|---|---|---|---|---|---|
| **SMALLINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| **INTEGER** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| **BIGINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| **REAL** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **DOUBLE** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **DECIMAL** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **VARCHAR** | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **DATE** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ |
| **TIMESTAMP** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ |
| **BOOLEAN** | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ |

**与 PostgreSQL 的差异**: 数字双向隐式（PG 只允许向上），VARCHAR→数字隐式（PG 需要 CAST），BOOLEAN↔整数隐式（PG 需要 CAST）。

---

## 31. 兼容族方言（继承父引擎规则）

以下方言的隐式转换矩阵与其父引擎一致，仅列出差异：

### MySQL 兼容族

| 方言 | 矩阵 | 与 MySQL 的差异 |
|------|------|----------------|
| **MariaDB** | 同 [MySQL（第 1 节）](#1-mysql-80--隐式类型转换矩阵) | JSON 内部为 LONGTEXT（非二进制）；新增 INET6/UUID 类型不参与隐式转换 |
| **TiDB** | 同 [MySQL（第 1 节）](#1-mysql-80--隐式类型转换矩阵) | DECIMAL+VARCHAR 比较时两边先转 DOUBLE 再比较（可能精度丢失） |
| **OceanBase MySQL 模式** | 同 [MySQL（第 1 节）](#1-mysql-80--隐式类型转换矩阵) | Oracle 模式租户应参考 [Oracle（第 3 节）](#3-oracle--隐式类型转换矩阵) |
| **PolarDB** | 同 [MySQL（第 1 节）](#1-mysql-80--隐式类型转换矩阵) | 无已知差异 |
| **TDSQL** | 同 [MySQL（第 1 节）](#1-mysql-80--隐式类型转换矩阵) | 无已知差异 |

### PostgreSQL 兼容族

| 方言 | 矩阵 | 与 PostgreSQL 的差异 |
|------|------|---------------------|
| **Greenplum** | 同 [PostgreSQL（第 2 节）](#2-postgresql--隐式类型转换矩阵) | 无差异（基于 PG 代码库） |
| **YugabyteDB** | 同 [PostgreSQL（第 2 节）](#2-postgresql--隐式类型转换矩阵) | 无差异（复用 PG 查询层） |
| **TimescaleDB** | 同 [PostgreSQL（第 2 节）](#2-postgresql--隐式类型转换矩阵) | 无差异（PG 扩展） |
| **Materialize** | 同 [PostgreSQL（第 2 节）](#2-postgresql--隐式类型转换矩阵) | pg_cast 子集实现；自有 LIST/MAP 类型有独立规则 |
| **openGauss** | 同 [PostgreSQL（第 2 节）](#2-postgresql--隐式类型转换矩阵)（PG 模式） | Oracle 兼容模式（`dbcompatibility='A'`）下 VARCHAR→NUMBER 隐式、`''=NULL` |
| **KingbaseES（人大金仓）** | 同 [PostgreSQL（第 2 节）](#2-postgresql--隐式类型转换矩阵)（PG 模式） | Oracle 模式下放宽：VARCHAR→NUMBER 隐式、DATE 含时间分量 |

### Oracle 兼容族

| 方言 | 矩阵 | 与 Oracle 的差异 |
|------|------|-----------------|
| **达梦（DamengDB）** | 同 [Oracle（第 3 节）](#3-oracle--隐式类型转换矩阵) | 不支持 BINARY_FLOAT/BINARY_DOUBLE；继承 `''=NULL` 行为 |

### SQL Server 兼容族

| 方言 | 矩阵 | 与 SQL Server 的差异 |
|------|------|---------------------|
| **Azure Synapse** | 同 [SQL Server（第 4 节）](#4-sql-server--隐式类型转换矩阵) | 不支持 geography/geometry/xml/sql_variant；VARCHAR(MAX) 在 CCI 表上有限制 |

---

## 32. 小众 / 专用引擎

### SQLite

动态类型系统，类型属于值而非列。5 种存储类，极度宽松。

| From ↓ \ To → | INTEGER | REAL | TEXT | BLOB |
|---|---|---|---|---|
| **INTEGER** | ✅ | ✅ | ✅ | ❌ |
| **REAL** | ✅ | ✅ | ✅ | ❌ |
| **TEXT** | ✅ | ✅ | ✅ | ❌ |
| **BLOB** | ❌ | ❌ | ❌ | ✅ |

**注意**: SQLite 无 BOOLEAN/DATE/TIMESTAMP 类型。STRICT 表（3.37+）可强制类型检查。

### TDengine

时序数据库，类型系统极简。仅数字族内向上提升和 BOOL→整数。

| From ↓ \ To → | INT | BIGINT | FLOAT | DOUBLE | BOOL | BINARY | NCHAR | TIMESTAMP |
|---|---|---|---|---|---|---|---|---|
| **INT** | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **BIGINT** | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **FLOAT** | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **DOUBLE** | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **BOOL** | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| **BINARY** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ |
| **NCHAR** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **TIMESTAMP** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

### ksqlDB

流处理 SQL，类型系统严格。仅数字向上提升。

| From ↓ \ To → | INT | BIGINT | DOUBLE | DECIMAL | VARCHAR | BOOLEAN | TIMESTAMP |
|---|---|---|---|---|---|---|---|
| **INT** | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **BIGINT** | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **DOUBLE** | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **DECIMAL** | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| **VARCHAR** | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| **BOOLEAN** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **TIMESTAMP** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

### H2

Java 嵌入式数据库，遵循 SQL 标准。支持兼容模式切换（MODE=MySQL 时放宽规则）。

| From ↓ \ To → | SMALLINT | INT | BIGINT | REAL | DOUBLE | DECIMAL | VARCHAR | DATE | TIMESTAMP | BOOLEAN |
|---|---|---|---|---|---|---|---|---|---|---|
| **SMALLINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **INT** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **BIGINT** | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **REAL** | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **DOUBLE** | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **DECIMAL** | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **VARCHAR** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| **DATE** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ |
| **TIMESTAMP** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **BOOLEAN** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

### Derby

Java 嵌入式数据库，严格遵循 SQL 标准，与 PostgreSQL 类似。

矩阵与 [H2（上方）](#h2) 一致。

### Firebird

中等严格，遵循 SQL 标准。数字族提升 + CHAR↔VARCHAR 互转 + DATE→TIMESTAMP。

| From ↓ \ To → | SMALLINT | INTEGER | BIGINT | FLOAT | DOUBLE | DECIMAL | VARCHAR | CHAR | DATE | TIMESTAMP | BOOLEAN |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **SMALLINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **INTEGER** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **BIGINT** | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **FLOAT** | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **DOUBLE** | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **DECIMAL** | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **VARCHAR** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **CHAR** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **DATE** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ |
| **TIMESTAMP** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **BOOLEAN** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

### SQL 标准（SQL:2003+）

SQL 标准定义的隐式转换仅限数字族内无损提升和 DATE→TIMESTAMP。

| From ↓ \ To → | SMALLINT | INTEGER | BIGINT | REAL | DOUBLE | DECIMAL | VARCHAR | DATE | TIMESTAMP | BOOLEAN |
|---|---|---|---|---|---|---|---|---|---|---|
| **SMALLINT** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **INTEGER** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **BIGINT** | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **REAL** | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **DOUBLE** | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **DECIMAL** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **VARCHAR** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| **DATE** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ |
| **TIMESTAMP** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **BOOLEAN** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

---

## 33. 横向对比速查表（全部 45 方言）

### 各引擎严格度排名

| 排名 | 引擎 | STRING→NUMBER 隐式 | CAST 失败行为 |
|------|------|-------------------|-------------|
| 1（最松） | SQLite | ✅（动态类型） | 静默转为 0 |
| 2 | MySQL / MariaDB / TiDB / OceanBase(MySQL) / PolarDB / TDSQL | ✅（`'abc'→0`） | 静默转为 0/NULL |
| 3 | Redshift | ✅（运行时报错） | 运行时报错 / TRY_CAST |
| 4 | SQL Server / Azure Synapse | ✅（运行时报错） | 运行时报错 / TRY_CAST |
| 5 | Teradata | ✅（运行时报错） | 运行时报错 / TRY_CAST |
| 6 | Oracle / 达梦 | ✅（运行时报错） | ORA-01722 |
| 7 | SAP HANA | ✅（运行时报错） | 运行时报错 |
| 8 | StarRocks / Doris | ✅（运行时报错） | 运行时报错 |
| 9 | Hive / MaxCompute | ✅（→DOUBLE） | 返回 NULL |
| 10 | Flink SQL | ✅（VARCHAR 万能源） | TRY_CAST 返回 NULL |
| 11 | Databricks | ✅（跨类型转换） | TRY_CAST 返回 NULL |
| 12 | Impala | ❌ | 返回 NULL |
| 13 | Db2 | ❌ | 运行时报错 |
| 14 | Snowflake | ❌ | TRY_CAST 返回 NULL |
| 15 | Spark ANSI | ❌ | 抛出异常 / TRY_CAST |
| 16 | BigQuery / Spanner | ❌ | SAFE_CAST 返回 NULL |
| 17 | Trino / DuckDB | ❌ | TRY_CAST 返回 NULL |
| 18 | ClickHouse | ❌ | toTypeOrNull 返回 NULL |
| 19 | H2 / Derby / Firebird | ❌ | 报错 |
| 20 | Vertica | ❌ | 报错 |
| 21 | PostgreSQL / Greenplum / YugabyteDB / TimescaleDB / Materialize / Hologres | ❌ | 报错 |
| 22 | openGauss / KingbaseES（PG 模式） | ❌ | 报错 |
| 23 | ksqlDB / TDengine | ❌ | 报错 |
| 24（最严） | CockroachDB | ❌ | 报错 |

### `SELECT 1/3` 整数除法

| 结果 = `0`（整数截断） | 结果 = `0.333...`（小数） |
|---|---|
| PostgreSQL、CockroachDB、Greenplum、YugabyteDB、Hologres、SQL Server、Azure Synapse、Spark ANSI、Db2、Teradata、Vertica、H2、Derby、Firebird | MySQL、MariaDB、TiDB、OceanBase、PolarDB、TDSQL、Oracle、达梦、BigQuery、Spanner、Snowflake、ClickHouse、Hive、MaxCompute、StarRocks、Doris、Redshift |

### TRY_CAST / SAFE_CAST 支持

| 引擎 | 语法 | 引入版本 |
|------|------|---------|
| SQL Server / Azure Synapse | `TRY_CAST(x AS type)` | 2012 |
| BigQuery / Spanner | `SAFE_CAST(x AS type)` | GA |
| Snowflake | `TRY_CAST(x AS type)` / `TRY_TO_*()` | GA |
| Trino | `TRY_CAST(x AS type)` / `TRY(expr)` | 早期版本 |
| DuckDB | `TRY_CAST(x AS type)` | 0.8.0+ |
| Databricks / Spark | `TRY_CAST(x AS type)` | 4.0 / Runtime 11.2+ |
| Flink | `TRY_CAST(x AS type)` | 1.15+ |
| ClickHouse | `toTypeOrNull(x)` / `toTypeOrZero(x)` | 早期版本 |
| Teradata | `TRY_CAST(x AS type)` | 16.20+ |
| Redshift | `TRY_CAST(x AS type)` | 近期版本 |
| Oracle | `VALIDATE_CONVERSION(x AS type)` | 12c R2 |
| Hive / MaxCompute | **不需要**（CAST 失败已返回 NULL） | — |
| PostgreSQL 族（PG/Greenplum/YugabyteDB/TimescaleDB/Hologres/Materialize/CockroachDB） | **无内置** | — |
| MySQL 族（MySQL/MariaDB/TiDB/OceanBase/PolarDB/TDSQL） | **无内置** | — |
| 其他（Db2/SAP HANA/Vertica/StarRocks/Doris/Impala） | **无内置** | — |

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
