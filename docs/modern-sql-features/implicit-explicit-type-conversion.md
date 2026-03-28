# 隐式与显式类型转换：各 SQL 方言转换矩阵全对比

> 参考资料:
> - [MySQL 8.0 - Type Conversion in Expression Evaluation](https://dev.mysql.com/doc/refman/8.0/en/type-conversion.html)
> - [PostgreSQL - pg_cast System Catalog](https://www.postgresql.org/docs/current/catalog-pg-cast.html)
> - [PostgreSQL - Type Conversion](https://www.postgresql.org/docs/current/typeconv.html)
> - [SQL Server - Data Type Conversion](https://learn.microsoft.com/en-us/sql/t-sql/data-types/data-type-conversion-database-engine)
> - [SQL Server - Data Type Precedence](https://learn.microsoft.com/en-us/sql/t-sql/data-types/data-type-precedence-transact-sql)
> - [Oracle - Implicit and Explicit Data Conversion](https://docs.oracle.com/cd/B19306_01/server.102/b14200/sql_elements002.htm)
> - [BigQuery - Conversion Rules](https://cloud.google.com/bigquery/docs/reference/standard-sql/conversion_rules)
> - [Snowflake - Data Type Conversion](https://docs.snowflake.com/en/sql-reference/data-type-conversion)
> - [ClickHouse - Type Conversion Functions](https://clickhouse.com/docs/sql-reference/functions/type-conversion-functions)
> - [Hive - Language Manual Types](https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Types)
> - [Spark SQL - ANSI Compliance](https://spark.apache.org/docs/latest/sql-ref-ansi-compliance.html)

隐式类型转换的宽松程度是 SQL 引擎设计中最具争议的决策之一。本文为每个主要 SQL 方言提供完整的二维类型转换矩阵，方便横向对比各引擎的差异。

**图例说明**（适用于所有矩阵）:

| 符号 | 含义 |
|------|------|
| **I** | 隐式转换（Implicit）——自动完成，无需 CAST |
| **A** | 赋值转换（Assignment）——仅在 INSERT/UPDATE 时自动，表达式中需要 CAST |
| **E** | 显式转换（Explicit）——必须使用 CAST / :: / TO_*() |
| **X** | 不允许转换 |
| **I!** | 隐式但有陷阱（数据丢失、精度损失、或行为诡异） |

---

## 一、各方言转换矩阵

### 1. MySQL 8.0

MySQL 是**最宽松**的传统 RDBMS。核心规则：当字符串和数字比较时，双方都转为 DOUBLE——这是 `'abc' = 0` 返回 TRUE 的根源。

> 来源: [MySQL 8.0 Type Conversion in Expression Evaluation](https://dev.mysql.com/doc/refman/8.0/en/type-conversion.html)

| Source ↓ \ Target → | INT | BIGINT | FLOAT | DOUBLE | DECIMAL | VARCHAR | DATE | DATETIME | TIMESTAMP | BOOL | JSON |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **INT** | - | I | I | I | I | I! | X | X | X | I! | E |
| **BIGINT** | I! | - | I! | I! | I | I! | X | X | X | I! | E |
| **FLOAT** | I! | I! | - | I | I! | I! | X | X | X | I! | E |
| **DOUBLE** | I! | I! | I! | - | I! | I! | X | X | X | I! | E |
| **DECIMAL** | I! | I! | I! | I | - | I! | X | X | X | I! | E |
| **VARCHAR** | **I!** | **I!** | **I!** | **I!** | **I!** | - | I! | I! | I! | I! | E |
| **DATE** | X | X | X | X | X | I | - | I | I | X | E |
| **DATETIME** | X | X | X | X | X | I | I! | - | I | X | E |
| **TIMESTAMP** | X | X | X | X | X | I | I! | I | - | X | E |
| **BOOL** | I | I | I | I | I | I! | X | X | X | - | E |
| **JSON** | E | E | E | E | E | E | E | E | E | E | - |

**MySQL 的关键陷阱:**

- **VARCHAR → 数字 = I!（危险的隐式转换）**: `'abc'` 转为 `0`，`'42abc'` 转为 `42`。`SELECT 0 = 'abc'` 返回 `1`（TRUE）
- **BOOL = TINYINT(1)**: 不是真正的布尔类型，`42` 也是合法的 BOOLEAN 值
- **大整数精度丢失**: `'9223372036854775807' = 9223372036854775806` 返回 TRUE（两边都转为 DOUBLE，超过 2^53 精度丢失）
- **DATE + 0 = 数字**: `CURDATE() + 1` 返回 `20240116`（不是"明天"，只是数字+1）
- **JSON 是孤岛**: 进出都需要显式转换，这反而是好设计
- **严格模式影响 INSERT**: `STRICT_TRANS_TABLES` 下 `INSERT INTO t(int_col) VALUES('abc')` 报错；非严格模式下静默插入 `0`

### 2. PostgreSQL

PostgreSQL 是**最严格**的传统 RDBMS。8.3 版本（2008）是分水岭——移除了 `text → integer` 等隐式转换。通过 `pg_cast` 系统表的 `castcontext` 字段定义三级转换。

> 来源: [PostgreSQL pg_cast Catalog](https://www.postgresql.org/docs/current/catalog-pg-cast.html)

| Source ↓ \ Target → | INTEGER | BIGINT | FLOAT8 | NUMERIC | TEXT | DATE | TIMESTAMP | BOOLEAN | JSONB |
|---|---|---|---|---|---|---|---|---|---|
| **INTEGER** | - | **I** | **I** | **I** | A | X | X | E | X |
| **BIGINT** | A | - | **I** | **I** | A | X | X | E | X |
| **FLOAT8** | A | A | - | A | A | X | X | X | X |
| **NUMERIC** | A | A | **I** | - | A | X | X | X | X |
| **TEXT** | **E** | **E** | **E** | **E** | - | **E** | **E** | **E** | **E** |
| **DATE** | X | X | X | X | A | - | **I** | X | X |
| **TIMESTAMP** | X | X | X | X | A | A | - | X | X |
| **BOOLEAN** | E | E | X | X | A | X | X | - | X |
| **JSONB** | X | X | X | X | A | X | X | X | - |

**PostgreSQL 的关键规则:**

- **TEXT → 任何类型 = E（始终需要显式 CAST）**: `SELECT '1' + 2` 直接报错 `ERROR: operator does not exist: text + integer`
- **数字族内无损提升 = I**: `int → bigint → numeric → float8` 都是隐式的
- **可能丢失精度 = A**: `bigint → int`、`float8 → int` 只在 INSERT/UPDATE 时允许
- **DATE → TIMESTAMP = I**: 加上午夜时间，无损
- **TIMESTAMP → DATE = A**: 截断时间部分，仅赋值时允许
- **BOOLEAN ↔ INTEGER = E**: 不像 C 语言自动转换
- **可扩展**: 自定义类型通过 `CREATE CAST ... AS IMPLICIT/ASSIGNMENT` 注册转换规则

### 3. Oracle

Oracle 介于 MySQL 和 PostgreSQL 之间。VARCHAR2 → NUMBER 在比较中是隐式的，但非数字字符串运行时报错（不像 MySQL 静默转为 0）。

> 来源: [Oracle SQL Language Reference - Data Type Comparison Rules](https://docs.oracle.com/cd/B19306_01/server.102/b14200/sql_elements002.htm)

| Source ↓ \ Target → | NUMBER | BINARY_FLOAT | VARCHAR2 | DATE | TIMESTAMP | BOOLEAN(23c) |
|---|---|---|---|---|---|---|
| **NUMBER** | - | I | **I** | X | X | X |
| **BINARY_FLOAT** | I | - | **I** | X | X | X |
| **VARCHAR2** | **I** | **I** | - | **I** | **I** | X |
| **DATE** | X | X | **I** | - | I | X |
| **TIMESTAMP** | X | X | **I** | I | - | X |
| **BOOLEAN(23c)** | I | X | I | X | X | - |

**Oracle 的关键特性:**

- **VARCHAR2 → NUMBER = I**: `WHERE number_col = '42'` 无需 CAST。但 `'abc'` 运行时抛 ORA-01722
- **VARCHAR2 → DATE = I**: 依赖 `NLS_DATE_FORMAT` 会话参数，格式因环境而异——强大但危险
- **'' = NULL**: Oracle 将零长度 VARCHAR2 视为 NULL。`WHERE col = ''` 等价于 `WHERE col IS NULL`——违反 SQL 标准
- **NUMBER 是统一类型**: INTEGER、BIGINT、DECIMAL 都是 `NUMBER(p,s)` 的别名，内部转换始终隐式

### 4. SQL Server

SQL Server 使用**数据类型优先级**决定转换方向：低优先级类型转为高优先级类型。几乎所有数字↔字符串转换都是隐式的。

> 来源: [SQL Server Data Type Precedence](https://learn.microsoft.com/en-us/sql/t-sql/data-types/data-type-precedence-transact-sql)

| Source ↓ \ Target → | INT | BIGINT | FLOAT | DECIMAL | VARCHAR | DATE | DATETIME2 | BIT |
|---|---|---|---|---|---|---|---|---|
| **INT** | - | I | I | I | **I** | X | X | I |
| **BIGINT** | I | - | I | I | **I** | X | X | I |
| **FLOAT** | I | I | - | I | **I** | X | X | I |
| **DECIMAL** | I | I | I | - | **I** | X | X | I |
| **VARCHAR** | **I** | **I** | **I** | **I** | - | **I** | **I** | **I** |
| **DATE** | X | X | X | X | **I** | - | I | X |
| **DATETIME2** | X | X | X | X | **I** | I | - | X |
| **BIT** | I | I | I | I | **I** | X | X | - |

**SQL Server 的关键陷阱:**

- **VARCHAR → INT = I（按优先级转列值）**: `WHERE varchar_col = 123`，INT 优先级高于 VARCHAR，所以列值被转为 INT——**索引失效**
- **VARCHAR ↔ DATE = I**: 识别多种日期格式（`'2024-01-15'`、`'Jan 15 2024'`、`'20240115'`）
- **BIT 即 BOOLEAN**: 与所有数字和字符串类型隐式互转
- **NVARCHAR vs VARCHAR**: `WHERE varchar_col = N'text'`（NVARCHAR 参数），NVARCHAR 优先级更高，但此时是参数被转换，索引可用

### 5. BigQuery

BigQuery 非常严格——只有数字族内的向上提升是隐式的，跨类型一律需要 CAST。

> 来源: [BigQuery Conversion Rules](https://cloud.google.com/bigquery/docs/reference/standard-sql/conversion_rules)

| Source ↓ \ Target → | INT64 | FLOAT64 | NUMERIC | STRING | BOOL | DATE | TIMESTAMP | JSON |
|---|---|---|---|---|---|---|---|---|
| **INT64** | - | E | E | E | E | X | X | E |
| **FLOAT64** | E | - | E | E | X | X | X | E |
| **NUMERIC** | E | E | - | E | X | X | X | E |
| **STRING** | E | E | E | - | E | E | E | E |
| **BOOL** | E | X | X | E | - | X | X | X |
| **DATE** | X | X | X | E | X | - | E | X |
| **TIMESTAMP** | X | X | X | E | X | E | - | X |
| **JSON** | E | E | E | E | E | X | X | - |

**隐式提升（仅限超类型解析，用于 UNION/CASE/IF/COALESCE）:**

| 类型 A | 类型 B | 超类型 |
|--------|--------|--------|
| INT64 | FLOAT64 | FLOAT64 |
| INT64 | NUMERIC | NUMERIC |
| NUMERIC | FLOAT64 | FLOAT64 |
| STRING | 任何非 STRING | **无超类型（报错）** |

**BigQuery 的关键特性:**

- **几乎全部需要显式 CAST**: `'42' + 1` 报错，必须 `CAST('42' AS INT64) + 1`
- **SAFE_CAST**: 转换失败返回 NULL。`SAFE.` 前缀可用于任何函数（如 `SAFE.PARSE_DATE(...)`）——最优雅的安全转换设计
- **STRING ↔ 任何非 STRING 无超类型**: UNION 中 `SELECT 1 UNION ALL SELECT 'a'` 直接报错

### 6. Snowflake

Snowflake 介于中等严格度。VARIANT 类型是"万能供体"，可隐式转为几乎所有标量类型。

> 来源: [Snowflake Data Type Conversion](https://docs.snowflake.com/en/sql-reference/data-type-conversion)

| Source ↓ \ Target → | NUMBER | FLOAT | VARCHAR | BOOLEAN | DATE | TIMESTAMP_NTZ | VARIANT |
|---|---|---|---|---|---|---|---|
| **NUMBER** | - | E | E | E | X | X | E |
| **FLOAT** | E | - | E | E | X | X | E |
| **VARCHAR** | E | E | - | E | E | E | E |
| **BOOLEAN** | E | **I** | **I** | - | X | X | **I** |
| **DATE** | X | X | **I** | X | - | **I** | E |
| **TIMESTAMP_NTZ** | X | X | **I** | X | I | - | E |
| **VARIANT** | **I** | **I** | **I** | **I** | **I** | **I** | - |

**Snowflake 的关键特性:**

- **VARIANT 隐式转出**: 运行时根据实际值类型自动转换，值不兼容时报错
- **BOOLEAN → FLOAT/VARCHAR = I**: `TRUE` → `1.0` / `'true'`
- **DATE → TIMESTAMP = I**: 添加午夜时间
- **VARCHAR → NUMBER = E**: 不像 MySQL/Oracle 那样隐式转换
- **TRY_CAST / TRY_TO_*()**: 失败返回 NULL
- **三种语法**: `CAST(x AS type)` / `x::type` / `TO_TYPE(x)` 等价

### 7. ClickHouse

ClickHouse 是**最严格的分析引擎**。隐式转换仅限算术运算中的数字族提升，遵循 C++ 类型提升规则。

> 来源: [ClickHouse Type Conversion Functions](https://clickhouse.com/docs/sql-reference/functions/type-conversion-functions)

| Source ↓ \ Target → | Int32 | Int64 | Float64 | Decimal | String | Date | DateTime | Bool |
|---|---|---|---|---|---|---|---|---|
| **Int32** | - | I(算术) | I(算术) | E | E | X | X | E |
| **Int64** | E | - | I(算术) | E | E | X | X | E |
| **Float64** | E | E | - | **X!** | E | X | X | E |
| **Decimal** | E | E | **X!** | - | E | X | X | X |
| **String** | E | E | E | E | - | E | E | E |
| **Date** | X | X | X | X | E | - | E | X |
| **DateTime** | X | X | X | X | E | E | - | X |
| **Bool** | E | E | E | X | E | X | X | - |

**X!** = **Decimal ↔ Float 被禁止**: `SELECT toDecimal64(1.5, 2) + toFloat64(1.0)` 直接报错，必须先显式转换一侧。

**ClickHouse 的关键特性:**

- **无隐式 STRING ↔ 数字转换**: `'42' + 1` 报错
- **算术提升遵循 C++ 规则**: `Int8 + Int32 → Int64`，`Int32 + Float32 → Float64`
- **首选语法**: `toInt64(x)` / `toFloat64(x)` / `toString(x)` 而非 CAST
- **安全变体**: 每个 `toType()` 都有 `toTypeOrNull()` 和 `toTypeOrZero()` 版本
- **Decimal ↔ Float 禁止隐式**: 必须显式选择精度模型，防止意外精度丢失

### 8. Hive

Hive 在大数据引擎中相对宽松。隐式转换沿着数字提升链单向进行。CAST 失败返回 NULL（不报错），因此不需要 TRY_CAST。

> 来源: [Hive Language Manual - Types](https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Types)

| Source ↓ \ Target → | TINYINT | INT | BIGINT | FLOAT | DOUBLE | DECIMAL | STRING | DATE | TIMESTAMP | BOOLEAN |
|---|---|---|---|---|---|---|---|---|---|---|
| **TINYINT** | - | I | I | I | I | I | I | X | X | X |
| **INT** | X | - | I | I | I | I | I | X | X | X |
| **BIGINT** | X | X | - | I | I | I | I | X | X | X |
| **FLOAT** | X | X | X | - | I | I | I | X | X | X |
| **DOUBLE** | X | X | X | X | - | I | I | X | X | X |
| **DECIMAL** | X | X | X | X | X | - | I | X | X | X |
| **STRING** | X | X | X | X | **I** | **I** | - | X | X | X |
| **DATE** | X | X | X | X | X | X | I | - | X | X |
| **TIMESTAMP** | X | X | X | X | X | X | I | X | - | X |
| **BOOLEAN** | X | X | X | X | X | X | X | X | X | - |

**Hive 的关键特性:**

- **单向提升链**: `TINYINT → SMALLINT → INT → BIGINT → FLOAT → DOUBLE → DECIMAL → STRING`
- **STRING → DOUBLE/DECIMAL = I**: 字符串在算术上下文隐式转为 DOUBLE
- **STRING → INT/BIGINT = X**: 不能直接隐式转为整数（必须先到 DOUBLE 再截断）
- **BOOLEAN 完全孤立**: 不能隐式转为任何其他类型
- **CAST 失败 = NULL**: Hive 的 CAST 永远不会报错，失败直接返回 NULL
- **DATE ↛ TIMESTAMP**: 日期不能隐式转为时间戳（与 PostgreSQL/Snowflake 不同）

### 9. Spark SQL（ANSI 模式 vs Hive 模式）

Spark SQL 有两套转换规则。4.0 起默认 ANSI 严格模式。

> 来源: [Spark SQL ANSI Compliance](https://spark.apache.org/docs/latest/sql-ref-ansi-compliance.html)

**ANSI 模式**（`spark.sql.ansi.enabled=true`，4.0 默认）:

| Source ↓ \ Target → | Int | Long | Float | Double | Decimal | String | Date | Timestamp | Boolean |
|---|---|---|---|---|---|---|---|---|---|
| **Int** | - | I | I | I | I | A | X | X | X |
| **Long** | A | - | I | I | I | A | X | X | X |
| **Float** | A | A | - | I | A | A | X | X | X |
| **Double** | A | A | A | - | A | A | X | X | X |
| **Decimal** | A | A | A | A | - | A | X | X | X |
| **String** | **X** | **X** | **X** | **X** | **X** | - | X | X | X |
| **Date** | X | X | X | X | X | A | - | I | X |
| **Timestamp** | X | X | X | X | X | A | A | - | X |
| **Boolean** | X | X | X | X | X | A | X | X | - |

**Hive 模式**（`spark.sql.ansi.enabled=false`）——关键差异:

| 行为 | ANSI 模式 | Hive 模式 |
|------|----------|----------|
| `CAST('abc' AS INT)` | 抛出 `SparkNumberFormatException` | 返回 `NULL` |
| `2147483647 + 1`（溢出） | 抛出 `SparkArithmeticException` | 返回 `-2147483648`（静默溢出） |
| `INSERT INTO int_table VALUES('1')` | 报错（String → Int 禁止） | 成功（隐式转换） |
| `'42' + 0` | 报错 | 返回 `42.0` |
| String → 数字隐式 | **禁止** | **允许**（类似 Hive） |

**Spark ANSI 类型提升链**:

```
Byte → Short → Int → Long → Decimal → Float* → Double
                                         ↑
                                   Float 被跳过（避免精度丢失）
                                   Int + Float → Double（不是 Float）
```

---

## 二、关键场景横向对比

### `'abc' + 0` 的行为

| 引擎 | 结果 | 说明 |
|------|------|------|
| MySQL | `0` | `'abc'` 隐式转为 DOUBLE `0.0` |
| PostgreSQL | **ERROR** | `operator does not exist: text + integer` |
| Oracle | **ERROR** | `ORA-01722: invalid number` |
| SQL Server | **ERROR** | `Conversion failed` |
| BigQuery | **ERROR** | 无隐式 STRING → INT64 |
| Snowflake | **ERROR** | 非数字字符串不能转换 |
| ClickHouse | **ERROR** | 无隐式 String → 数字 |
| Hive | `0.0` | STRING → DOUBLE 隐式，`'abc'` → `NULL` → `0.0` |
| Spark ANSI | **ERROR** | 禁止 String → 数字隐式转换 |
| Spark Hive | `NULL` | CAST 失败返回 NULL |

### `SELECT 1/3` 整数除法

| 引擎 | 结果 | 结果类型 |
|------|------|---------|
| **PostgreSQL** | `0` | INTEGER（截断） |
| **SQL Server** | `0` | INT（截断） |
| **Spark (ANSI)** | `0` | INT（截断） |
| **MySQL** | `0.3333` | DECIMAL |
| **Oracle** | `0.333...` | NUMBER |
| **BigQuery** | `0.333...` | FLOAT64 |
| **Snowflake** | `0.333...` | NUMBER |
| **ClickHouse** | `0.333...` | Float64 |
| **Hive** | `0.333...` | DOUBLE |

### VARCHAR 列与数字比较的索引影响

```sql
WHERE varchar_col = 123
```

| 引擎 | 转换方向 | 索引是否可用 |
|------|---------|-------------|
| MySQL | 列值转为 DOUBLE | **索引失效** |
| PostgreSQL | **报错**（类型不匹配） | — |
| Oracle | 列值转为 NUMBER | **索引失效** |
| SQL Server | 列值转为 INT（INT 优先级更高） | **索引失效** |
| BigQuery | **报错** | — |
| Snowflake | **报错** | — |

### TRY_CAST / SAFE_CAST 支持

| 引擎 | 语法 | 引入版本 |
|------|------|---------|
| SQL Server | `TRY_CAST(x AS type)` | 2012 |
| BigQuery | `SAFE_CAST(x AS type)` / `SAFE.func()` | GA |
| Snowflake | `TRY_CAST(x AS type)` / `TRY_TO_*()` | GA |
| Trino | `TRY_CAST(x AS type)` / `TRY(expr)` | 早期版本 |
| DuckDB | `TRY_CAST(x AS type)` | 0.8.0+ |
| Databricks | `TRY_CAST(x AS type)` | Runtime 11.2+ |
| Spark | `TRY_CAST(x AS type)` | 4.0 |
| Flink | `TRY_CAST(x AS type)` | 1.15+ |
| ClickHouse | `toTypeOrNull(x)` / `toTypeOrZero(x)` | 早期版本 |
| Oracle | `VALIDATE_CONVERSION(x AS type)` 返回 0/1 | 12c R2 |
| PostgreSQL | **无内置**（需自定义 PL/pgSQL 函数） | — |
| MySQL | **无内置**（需 CASE + REGEXP 模拟） | — |
| Hive | **不需要**（CAST 失败已经返回 NULL） | — |

---

## 三、对引擎开发者的设计建议

### 推荐的三级转换模型（借鉴 PostgreSQL）

| 级别 | 触发条件 | 设计原则 | 示例 |
|------|---------|---------|------|
| **隐式 (I)** | 任何表达式自动触发 | 仅限同族**无损**转换 | `int → bigint`, `float32 → float64` |
| **赋值 (A)** | 仅 INSERT/UPDATE 时自动 | 可能截断但语义合理 | `varchar(100) → varchar(50)`, `timestamp → date` |
| **显式 (E)** | 必须 CAST | 可能丢失信息 | `text → integer`, `float → int` |

### 推荐的数字类型提升路径

```
INT8 → INT16 → INT32 → INT64 → DECIMAL ─┬→ FLOAT32 → FLOAT64
                                          │
                                    在这里截断隐式提升
                                    DECIMAL → FLOAT 应需要显式 CAST
                                    （浮点精度丢失不可逆）
```

### 核心原则

| 原则 | 说明 | 反面教材 |
|------|------|---------|
| 隐式转换必须无损 | 只在同类型族内提升 | MySQL `STRING → DOUBLE` |
| 比较时转常量不转列 | `WHERE int_col = '123'` 转 `'123'` 为 int | SQL Server 按优先级转列值致索引失效 |
| 整数除法行为必须明确 | INT/INT 结果类型在设计之初确定 | PG 返回 `0`，MySQL 返回 `0.33` |
| TRY_CAST 从第一天支持 | 后期添加需改造整个求值路径 | PostgreSQL/MySQL 至今无原生 TRY_CAST |
| 转换矩阵完整文档化 | 每对类型都有明确分类 | 未文档化的边界 case 导致不可预测行为 |

---

*注：本页信息均来自各引擎官方文档。具体行为可能随版本变化，建议以目标版本的官方文档为准。*
