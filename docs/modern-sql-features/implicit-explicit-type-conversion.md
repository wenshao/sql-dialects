# 隐式与显式类型转换：引擎设计中最具争议的决策

> 参考资料:
> - [MySQL 8.0 - Type Conversion in Expression Evaluation](https://dev.mysql.com/doc/refman/8.0/en/type-conversion.html)
> - [PostgreSQL - Type Conversion](https://www.postgresql.org/docs/current/typeconv.html)
> - [PostgreSQL - pg_cast System Catalog](https://www.postgresql.org/docs/current/catalog-pg-cast.html)
> - [SQL Server - Data Type Precedence](https://learn.microsoft.com/en-us/sql/t-sql/data-types/data-type-precedence-transact-sql)
> - [Oracle - Datatype Comparison Rules](https://docs.oracle.com/cd/B19306_01/server.102/b14200/sql_elements002.htm)
> - [BigQuery - Conversion Rules](https://cloud.google.com/bigquery/docs/reference/standard-sql/conversion_rules)
> - [Spark SQL - ANSI Compliance](https://spark.apache.org/docs/latest/sql-ref-ansi-compliance.html)
> - [ClickHouse - Type Conversion Functions](https://clickhouse.com/docs/sql-reference/functions/type-conversion-functions)
> - [Snowflake - Data Type Conversion](https://docs.snowflake.com/en/sql-reference/data-type-conversion)

隐式类型转换的宽松程度是 SQL 引擎设计中最具争议的决策之一。MySQL 的 `'abc' = 0` 返回 TRUE 是臭名昭著的安全隐患，PostgreSQL 的 `'1' + 2` 直接报错又让初学者困惑。每个引擎都在"方便"和"安全"之间做出了不同的取舍，理解这些取舍是引擎开发者的必修课。

## 隐式转换的危险：真实的生产事故

### MySQL `'abc' = 0` 返回 TRUE

MySQL 最臭名昭著的行为：当字符串和数字比较时，MySQL 将字符串转为 DOUBLE。非数字字符串转为 `0`。

```sql
-- MySQL
SELECT 0 = 'abc';     -- 1 (TRUE! 'abc' 转为 0.0)
SELECT 1 > '6x';      -- 0 ('6x' 转为 6.0)
SELECT 0 = 'x6';      -- 1 ('x6' 转为 0.0)
SELECT '42abc' + 0;    -- 42 (取前导数字部分)
```

MySQL 8.0 官方文档（Section 14.3）明确说明规则：*"In all other cases, the arguments are compared as floating-point (double-precision) numbers."*

**安全漏洞实例**：如果表有 `session_id INT` 列，查询 `WHERE session_id = '929f9152-78aa-4a56-be59-...'`（UUID），MySQL 将 UUID 字符串转为数字 `929`（解析到第一个非数字字符停止），匹配到 session ID 929。这是一个已被记录的真实认证绕过向量。

> 来源: [Implicit type conversion in MySQL - tom.vg](https://tom.vg/2013/04/mysql-implicit-type-conversion/)

### 索引失效：隐式转换的性能陷阱

当 WHERE 子句比较 VARCHAR 列和数字字面量时：

```sql
-- MySQL / SQL Server / Oracle
WHERE varchar_col = 12345
```

引擎将每行的 `varchar_col` 转为数字进行比较（因为多个不同字符串可能转为同一个数字：`'1'`、`' 1'`、`'1a'` 都变成 `1`）。这意味着 `varchar_col` 上的索引**无法使用**，强制全表扫描。

SQL Server 的数据类型优先级规则也会导致同样的问题：INT 优先级高于 VARCHAR，所以 `WHERE varchar_col = 123` 会将列值转为 INT——索引失效。

> 来源: [MySQL Bug #83857](https://bugs.mysql.com/bug.php?id=83857), [SQL Server Data Type Precedence and Implicit Conversions](https://bertwagner.com/posts/data-type-precedence-and-implicit-conversions)

### Oracle `'' = NULL`：迁移噩梦

Oracle 将零长度 VARCHAR2 字符串视为 NULL，这违反 SQL 标准（标准明确定义 `''` 和 NULL 是不同的值）。

```sql
-- Oracle
SELECT CASE WHEN '' IS NULL THEN 'YES' ELSE 'NO' END FROM DUAL;  -- YES
```

Oracle 文档中至今保留着这句警告：*"Oracle Database currently treats a character value with a length of zero as null. However, this may not continue to be true in future releases."* 这个警告从 Oracle 7 开始就存在了——20 多年没改。

**迁移影响**：从 Oracle 迁移到 PostgreSQL / MySQL 时，每个 `WHERE col = ''` 都必须重写为 `WHERE col IS NULL`，每个 `WHERE col != ''` 都必须重写为 `WHERE col IS NOT NULL`。

### 大整数精度丢失

```sql
-- MySQL
SELECT '9223372036854775807' = 9223372036854775806;  -- 1 (TRUE, 错误!)
-- 两个值都转为 DOUBLE，超过 2^53 精度丢失
```

MySQL 文档明确警告此问题，建议使用 `CAST(... AS UNSIGNED)` 进行大整数比较。

## 各引擎隐式转换严格度谱系

从最宽松到最严格：

| 严格度 | 引擎 | `'abc'+0` | `0='abc'` | `'42'+1` | 设计哲学 |
|--------|------|-----------|-----------|----------|---------|
| 1 最松 | **SQLite** | `0` | `FALSE`* | `43` | 动态类型，类型属于值而非列 |
| 2 | **MySQL** | `0` | `TRUE` | `43` | 方便优先，极度宽松 |
| 3 | **Hive** | `0.0` | — | `43.0` | 隐式转为 DOUBLE |
| 4 | **SQL Server** | `ERROR` | `ERROR` | `43` | 有优先级规则，但字符串可转数字 |
| 5 | **Oracle** | `ERROR` | `ERROR` | `43` | VARCHAR2→NUMBER 隐式转换 |
| 6 | **Snowflake** | `ERROR` | `ERROR` | `43` | 可隐式转换但非数字字符串报错 |
| 7 | **Spark (ANSI)** | `ERROR` | `ERROR` | `ERROR` | 4.0 起默认 ANSI 严格模式 |
| 8 | **BigQuery** | `ERROR` | `ERROR` | `ERROR` | 超类型推导，不做跨类算术隐式转换 |
| 9 | **ClickHouse** | `ERROR` | `ERROR` | `ERROR` | 无隐式 STRING→NUMBER 转换 |
| 10 最严 | **PostgreSQL** | `ERROR` | `ERROR` | `ERROR` | 8.3 起移除了大量隐式转换 |

*注：SQLite 的 `0='abc'` 返回 FALSE 是因为 SQLite 的跨类型比较规则（数字 < 文本 < blob），而非类型转换。

**关键历史事件**：PostgreSQL 8.3（2008）是分水岭——移除了之前存在的 `text → integer` 等隐式转换。虽然导致大量应用报错，但长期来看大幅减少了隐式转换导致的 bug。

> 来源: [Peter Eisentraut - Readding implicit casts in PostgreSQL 8.3](http://petereisentraut.blogspot.com/2008/03/readding-implicit-casts-in-postgresql.html)

## 类型提升规则对比

类型提升（type promotion）决定了两个不同类型参与运算时结果是什么类型。

### INT + FLOAT

| 引擎 | `1 + 1.5` 的结果类型 | 说明 |
|------|---------------------|------|
| PostgreSQL | `NUMERIC` | INT 提升为 NUMERIC（不是 FLOAT，避免精度丢失） |
| MySQL | `DOUBLE` | 混合算术统一转 DOUBLE |
| Oracle | `NUMBER` | Oracle NUMBER 是任意精度 |
| SQL Server | `NUMERIC` | DECIMAL/NUMERIC 优先级高于 INT |
| BigQuery | `FLOAT64` | INT64 提升为 FLOAT64 |
| ClickHouse | `Float64` | 小类型提升为大类型 |
| Spark SQL | `DOUBLE` | Float 被跳过，直接到 DOUBLE 避免精度丢失 |
| Snowflake | `NUMBER` | 所有整数内部都是 NUMBER(38,0) |

### INT / INT 整数除法——最大的跨引擎陷阱

| 引擎 | `SELECT 1/3` | 结果 | 说明 |
|------|-------------|------|------|
| **PostgreSQL** | `0` | 整数截断 | 需要 `1::float/3` 得到 0.333 |
| **SQL Server** | `0` | 整数截断 | 需要 `CAST(1 AS FLOAT)/3` |
| **Spark SQL** | `0` | 整数截断（ANSI 模式） | INT/INT = INT |
| **MySQL** | `0.3333` | 返回 DECIMAL | `/` 做十进制除法；`DIV` 做整数除法 |
| **Oracle** | `0.333...` | NUMBER 除法 | Oracle NUMBER 处理 |
| **BigQuery** | `0.333...` | FLOAT64 | 除法总是返回 FLOAT64 |
| **Snowflake** | `0.333...` | NUMBER | 十进制除法 |
| **ClickHouse** | `0.333...` | Float64 | 除法返回浮点 |

这是**最危险的跨引擎差异之一**。从 MySQL/BigQuery 迁移到 PostgreSQL/SQL Server 时，所有整数除法的结果都会变化。金融计算中这可能导致严重的精度问题。

### STRING + INT

| 行为 | 引擎 |
|------|------|
| 返回 `43` | MySQL, Oracle, SQL Server, Snowflake, Hive |
| 报错 | PostgreSQL, BigQuery, ClickHouse, Spark (ANSI) |
| 返回 NULL | Spark (Hive 模式，转换失败时) |

**引擎开发者的选择**：推荐报错。MySQL 的 `'abc' + 0 = 0` 行为已经被证明是安全隐患。

## 转换矩阵设计：PostgreSQL 的三级体系

PostgreSQL 通过 `pg_cast` 系统表定义了最正式的类型转换架构。每个类型转换注册时指定 `castcontext`：

| 级别 | castcontext | 触发条件 | 设计原则 | 示例 |
|------|-------------|---------|---------|------|
| **隐式 (Implicit)** | `'i'` | 任何表达式上下文自动触发 | 仅限**无损**转换，同类型族内 | `int2 → int4`, `int4 → int8` |
| **赋值 (Assignment)** | `'a'` | 仅在 INSERT/UPDATE 赋值时自动触发 | 可能截断但语义合理 | `varchar(10) → varchar(5)`, `timestamp → date` |
| **显式 (Explicit)** | `'e'` | 必须使用 `CAST()` 或 `::` | 可能丢失信息或格式变化 | `text → integer`, `float8 → int4` |

```sql
-- 查看 integer 类型的所有注册转换
SELECT castsource::regtype, casttarget::regtype, castcontext
FROM pg_cast
WHERE castsource = 'integer'::regtype;
```

PostgreSQL 官方准则：*"A good rule of thumb is that implicit casts should never have surprising behaviors... information-preserving transformations between types in the same general type category."*

**可扩展性**：自定义类型（PostGIS `GEOMETRY`、pgvector `VECTOR`）通过 `CREATE CAST ... AS IMPLICIT/ASSIGNMENT` 注册自己的转换规则。这是 PostgreSQL 类型系统的核心架构优势。

> 来源: [PostgreSQL pg_cast Catalog](https://www.postgresql.org/docs/current/catalog-pg-cast.html), [PostgreSQL CREATE CAST](https://www.postgresql.org/docs/current/sql-createcast.html)

### SQL Server 的数据类型优先级

SQL Server 使用线性优先级列表决定隐式转换方向（高优先级部分）：

```
datetimeoffset > datetime2 > datetime > date > time
> float > real > decimal > money
> bigint > int > smallint > tinyint > bit
> nvarchar > nchar > varchar > char
```

当两个不同类型参与运算时，低优先级类型转为高优先级类型。这就是为什么 `WHERE varchar_col = 123` 会将 varchar 列转为 int（int 优先级高于 varchar）——导致索引失效。

> 来源: [SQL Server Data Type Precedence](https://learn.microsoft.com/en-us/sql/t-sql/data-types/data-type-precedence-transact-sql)

### Spark SQL 的双模式系统

Spark SQL 通过 `spark.sql.ansi.enabled` 切换两套转换规则（4.0 起默认 `true`）：

| 行为 | ANSI 模式（严格） | Hive 模式（宽松） |
|------|------------------|------------------|
| `CAST('a' AS INT)` | 抛出 `SparkNumberFormatException` | 返回 `NULL` |
| `2147483647 + 1` | 抛出 `SparkArithmeticException` | 返回 `-2147483648`（静默溢出） |
| 类型提升 | 严格的类型优先级列表 | 宽松，自动提升 |

**类型提升优先级**（ANSI 模式）：

```
Byte → Short → Int → Long → Decimal → Float* → Double
Date → Timestamp_NTZ → Timestamp
```

*注：Float 在最小公共类型推导中被跳过，直接到 Double，避免精度丢失。

> 来源: [Spark SQL ANSI Compliance](https://spark.apache.org/docs/latest/sql-ref-ansi-compliance.html)

## TRY_CAST / SAFE_CAST：安全转换设计

转换失败时返回 NULL 而非报错——ETL / 数据清洗场景中必不可少。

| 引擎 | 语法 | 引入版本 |
|------|------|---------|
| **SQL Server** | `TRY_CAST(expr AS type)`, `TRY_CONVERT(type, expr)` | 2012 |
| **BigQuery** | `SAFE_CAST(expr AS type)`, `SAFE.函数名()` | 标准 SQL 发布即支持 |
| **Snowflake** | `TRY_CAST(expr AS type)`, `TRY_TO_NUMBER()`, `TRY_TO_DATE()` | GA |
| **Trino** | `TRY_CAST(expr AS type)`, `TRY(expression)` | 早期版本（继承自 Presto） |
| **DuckDB** | `TRY_CAST(expr AS type)` | 0.8.0+ |
| **Databricks** | `TRY_CAST(expr AS type)`, `TRY_TO_NUMBER()` | Runtime 11.2+ |
| **Spark** | `TRY_CAST(expr AS type)` | 4.0（Databricks 更早支持） |
| **Flink** | `TRY_CAST(expr AS type)` | 1.15+ |
| **ClickHouse** | `toInt32OrNull(expr)`, `toInt32OrZero(expr)` | 早期版本 |
| **Oracle** | `VALIDATE_CONVERSION(expr AS type)` 返回 0/1 | 12c Release 2 |
| **PostgreSQL** | 无内置，需自定义 PL/pgSQL 函数 + `EXCEPTION WHEN` | — |
| **MySQL** | 无内置，需 `CASE + REGEXP` 模拟 | — |

**设计对比:**

- **BigQuery `SAFE.` 前缀**是最优雅的设计——作为通用修饰符适用于任何函数：`SAFE.PARSE_DATE(...)`、`SAFE.LOG(0)` 等。不仅限于类型转换
- **Trino `TRY(expression)`** 类似，但用函数语法：`TRY(CAST(x AS INT))` 等价于 `TRY_CAST(x AS INT)`
- **ClickHouse `OrNull/OrZero` 后缀**风格独特：`toInt32OrNull('abc')` 返回 NULL，`toInt32OrZero('abc')` 返回 0

**对引擎开发者**：推荐从第一天就支持 TRY_CAST——后期添加需要在整个表达式求值路径中加入错误捕获机制，改造成本高。BigQuery 的 `SAFE.` 前缀模式值得借鉴，但实现复杂度更高。

## 已知的生产陷阱

### 1. MySQL UUID 匹配——认证绕过

```sql
-- 表: session_id INT
WHERE session_id = '929f9152-78aa-4a56-be59-df3241e4a16e'
-- MySQL 将 UUID 转为 929，匹配到 session_id = 929
```

### 2. Hive DECIMAL-STRING 比较 Bug

Apache Hive JIRA [HIVE-24528](https://issues.apache.org/jira/browse/HIVE-24528) 记录了 DECIMAL 和 STRING 隐式转换产生错误比较结果的 bug。

### 3. Spark Hive 模式静默溢出

```sql
-- spark.sql.ansi.enabled=false
SELECT 2147483647 + 1;  -- 返回 -2147483648 (静默整数溢出)
-- spark.sql.ansi.enabled=true (4.0 默认)
-- 抛出 SparkArithmeticException
```

### 4. SQL Server 参数嗅探 + 隐式转换

当 `WHERE nvarchar_col = @varchar_param` 时，SQL Server 将参数转为 nvarchar（高优先级），索引可用。但 `WHERE varchar_col = @nvarchar_param` 时，列被转换，索引失效。参数类型的微小差异导致执行计划巨变。

## 对引擎开发者的设计建议

### 1. 推荐的转换规则设计

```
               三级分类（借鉴 PostgreSQL）
               ┌─────────────────────────────┐
  隐式 (Implicit)  │ 仅限同族无损转换              │
  ─────────────────┤ int8→int16→int32→int64→decimal │
                   │ float32→float64               │
               ├─────────────────────────────┤
  赋值 (Assignment)│ INSERT/UPDATE 时允许          │
  ─────────────────┤ varchar(100)→varchar(50)       │
                   │ timestamp→date                 │
               ├─────────────────────────────┤
  显式 (Explicit)  │ 必须 CAST()                   │
  ─────────────────┤ string→int, float→int          │
                   │ date→string                    │
               └─────────────────────────────┘
```

### 2. 核心原则

| 原则 | 说明 | 反面教材 |
|------|------|---------|
| **隐式转换必须无损** | 只在同类型族内提升，不允许跨类型族隐式转换 | MySQL `STRING→DOUBLE` |
| **比较时转常量，不转列** | `WHERE int_col = '123'` 应转 `'123'` 为 int，而非 `int_col` 转 string | SQL Server 按优先级转列值，索引失效 |
| **除法行为必须明确** | INT/INT 的结果类型在设计之初就确定，不能模糊 | PostgreSQL 返回 0，MySQL 返回 0.33——迁移灾难 |
| **TRY_CAST 从第一天支持** | 后期添加需要改造整个表达式求值路径 | PostgreSQL/MySQL 至今无原生 TRY_CAST |
| **转换矩阵完整文档化** | 每对类型组合都有明确分类：隐式/赋值/显式/禁止 | 未文档化的边界情况导致不可预测行为 |

### 3. 推荐的数值类型提升路径

```
INT8 → INT16 → INT32 → INT64 → DECIMAL → FLOAT32 → FLOAT64
                                   ↑
                              推荐在这里截断隐式提升
                              DECIMAL→FLOAT 应该需要显式 CAST
                              （因为浮点精度丢失不可逆）
```

### 4. 关于兼容模式

如果引擎需要兼容 MySQL（如 TiDB、OceanBase），隐式转换行为必须可通过 SQL 模式切换：

- **严格模式**（推荐默认）：类似 PostgreSQL，跨类型比较报错
- **兼容模式**：复现 MySQL 的 `STRING→DOUBLE` 隐式转换，用于迁移过渡
- 每条 SQL 执行时的 `sql_mode` 应影响类型转换行为

TiDB 的实践值得参考：默认开启严格模式，但提供 `tidb_enable_strict_double_type_check` 等细粒度开关。

---

*注：本页信息均来自各引擎官方文档和已发表的技术分析。具体行为可能随版本变化，建议以目标版本的官方文档为准。*
