# 整数除法、算术溢出与精度规则：各 SQL 方言行为全对比

> 参考资料:
> - [MySQL 8.0 - Arithmetic Operators](https://dev.mysql.com/doc/refman/8.0/en/arithmetic-functions.html)
> - [PostgreSQL - Mathematical Functions](https://www.postgresql.org/docs/current/functions-math.html)
> - [SQL Server - Data Type Precedence](https://learn.microsoft.com/en-us/sql/t-sql/data-types/data-type-precedence-transact-sql)
> - [Oracle - Numeric Datatypes](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Data-Types.html)
> - [BigQuery - Mathematical Functions](https://cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions)
> - [ClickHouse - Arithmetic Functions](https://clickhouse.com/docs/sql-reference/functions/arithmetic-functions)
> - [Hive - Operators and UDFs](https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF)
> - [Spark SQL - ANSI Compliance](https://spark.apache.org/docs/latest/sql-ref-ansi-compliance.html)

整数除法的结果类型和算术溢出的处理方式是 SQL 方言间差异最大、迁移风险最高的领域之一。`SELECT 5/2` 在 PostgreSQL 返回 `2`，在 MySQL 返回 `2.5`——这个差异可能导致金融计算中的严重错误。

---

## 1. 整数除法 `SELECT 5/2`

这是**最危险的跨引擎差异之一**。从 MySQL/BigQuery 迁移到 PostgreSQL/SQL Server 时，所有整数除法的结果都会变化。

| 方言 | `5/2` 结果 | 结果类型 | 整数除法运算符 |
|------|-----------|---------|-------------|
| **MySQL** | `2.5` | DECIMAL | `DIV`（`5 DIV 2 = 2`） |
| **PostgreSQL** | `2` | INTEGER | `/` 即整数除（整数操作数时） |
| **Oracle** | `2.5` | NUMBER | 无（用 `TRUNC(5/2)`） |
| **SQL Server** | `2` | INT | `/` 即整数除（整数操作数时） |
| **BigQuery** | `2.5` | FLOAT64 | `DIV(a, b)` 函数（`DIV(5, 2) = 2`） |
| **Snowflake** | `2.500000` | NUMBER(7,6) | 无内置整数除运算符（用 `TRUNC(5/2)`） |
| **ClickHouse** | `2` | Int | `intDiv(5, 2) = 2`；`/` 对整数是整数除 |
| **Hive** | `2.5` | DOUBLE | `DIV`（`5 DIV 2 = 2`） |
| **Spark SQL** | `2.5` | DOUBLE | `DIV`（`5 DIV 2 = 2`） |
| **MaxCompute** | `2.5` | DOUBLE | 无标准整数除法运算符 |
| **StarRocks** | `2.5` | DOUBLE | `DIV`（`5 DIV 2 = 2`） |
| **Doris** | `2.5` | DOUBLE | `DIV`（`5 DIV 2 = 2`） |
| **Trino** | `2` | INTEGER | `/` 对整数是整数除 |
| **DuckDB** | `2` | INTEGER | `/` 对整数是整数除；`//` 整数除法运算符（`5 // 2 = 2`） |
| **Flink SQL** | `2` | INT | `/` 对整数是整数除 |
| **Redshift** | `2` | INTEGER | `/` 对整数是整数除（PG 兼容） |
| **Databricks** | `2.5` | DOUBLE | `DIV`（同 Spark） |
| **Impala** | `2.5` | DOUBLE | `DIV` 运算符（`5 DIV 2 = 2`） |
| **Teradata** | `2` | INTEGER | `/` 对整数是整数除 |
| **Db2** | `2` | INTEGER | `/` 对整数是整数除 |
| **SAP HANA** | `2` | INTEGER | `/` 对整数是整数除 |
| **Vertica** | `2` | INTEGER | `/` 对整数是整数除（PG 派生） |
| **SQLite** | `2` | INTEGER | `/` 对整数是整数除 |

### 分组总结

| INT/INT = INT（截断） | INT/INT = DECIMAL/FLOAT（真除法） |
|---|---|
| PostgreSQL, SQL Server, ClickHouse, Trino, DuckDB, Flink, Redshift, Teradata, Db2, SAP HANA, Vertica, SQLite | MySQL, Oracle, BigQuery, Snowflake, Hive, Spark, MaxCompute, Databricks, Impala, StarRocks, Doris |

**对引擎开发者**: 这是必须在设计之初明确的决策。两种选择都有道理——PostgreSQL 方式与大多数编程语言一致（C/Java/Python 3 的 `//`），MySQL 方式更符合数学直觉。但**迁移时必须逐一检查所有除法表达式**。

---

## 2. 除零行为 `SELECT 1/0`

| 方言 | `1/0`（整数） | `1.0/0`（浮点） | `0/0` | 安全替代 |
|------|-------------|---------------|------|---------|
| **MySQL** | NULL（+ 警告） | NULL | NULL | `NULLIF` 预防 |
| **PostgreSQL** | ERROR | ERROR | ERROR | `1.0 / NULLIF(0, 0)` |
| **Oracle** | ERROR（ORA-01476） | ERROR | ERROR | `CASE` / `NULLIF` |
| **SQL Server** | ERROR | ERROR | ERROR | `NULLIF`；`TRY_CATCH` |
| **BigQuery** | ERROR | ERROR | ERROR | `SAFE_DIVIDE(1,0)` = NULL；`IEEE_DIVIDE(1,0)` = Inf |
| **Snowflake** | ERROR | ERROR | ERROR | `DIV0(10,0)` = 0；`DIV0NULL(10,0)` = NULL |
| **ClickHouse** | Inf（Float）/ ERROR（Int） | Inf | NaN | `intDivOrZero()`，`moduloOrZero()` |
| **Hive** | NULL | NULL | NULL | 内置 NULL 行为 |
| **Spark SQL** | NULL（ANSI=off）/ ERROR（ANSI=on） | 同左 | 同左 | `try_divide(1, 0)` = NULL |
| **MaxCompute** | NULL | NULL | NULL | 内置 NULL 行为 |
| **StarRocks** | NULL | NULL | NULL | 内置 NULL 行为 |
| **Doris** | NULL | NULL | NULL | 内置 NULL 行为 |
| **Trino** | ERROR | ERROR | ERROR | `TRY(1/0)` = NULL |
| **DuckDB** | ERROR | ERROR | ERROR | `NULLIF` 预防 |
| **Flink SQL** | NULL（整数）/ ERROR（DECIMAL） | 视类型 | 视类型 | 无标准安全函数 |
| **Redshift** | ERROR | ERROR | ERROR | `NULLIF` 预防 |

### 分组总结

| 静默返回 NULL | 抛出 ERROR | 返回 Inf/NaN（IEEE 754） |
|---|---|---|
| MySQL, Hive, MaxCompute, StarRocks, Doris, Spark（ANSI=off）, Flink（整数） | PostgreSQL, Oracle, SQL Server, BigQuery, Snowflake, Trino, DuckDB, Redshift, Spark（ANSI=on） | ClickHouse（浮点除法） |

**对引擎开发者**: BigQuery 的 `SAFE_DIVIDE` / `IEEE_DIVIDE` 双轨设计最优雅——让用户显式选择"安全但丢失信息"还是"IEEE 语义"。Snowflake 的 `DIV0`（返回 0）在报表场景很实用但在计算场景危险。

---

## 3. 整数溢出 `SELECT 2147483647 + 1`（INT 最大值 +1）

| 方言 | INT 溢出 | BIGINT 溢出 | 安全替代 |
|------|---------|-----------|---------|
| **MySQL** | ERROR（严格模式，8.0 默认）| ERROR | 无 |
| **PostgreSQL** | ERROR（始终） | ERROR | 无 |
| **Oracle** | N/A（NUMBER 自动扩展，最大 38 位） | N/A | 不存在此问题 |
| **SQL Server** | ERROR（Arithmetic overflow） | ERROR | `TRY_CAST` |
| **BigQuery** | N/A（只有 INT64，无 INT32） | ERROR | `SAFE_ADD()` 返回 NULL |
| **Snowflake** | N/A（NUMBER(38,0)，范围极大） | N/A | 不存在此问题 |
| **ClickHouse** | N/A（≤32 位自动提升到 Int64） | **静默回绕**（Int64 边界） | 无 |
| **Hive** | **静默回绕**（Java 原生整数运算） | **静默回绕** | 无 |
| **Spark SQL** | **静默回绕**（ANSI=off）/ ERROR（ANSI=on） | 同左 | `try_add()` 返回 NULL |
| **MaxCompute** | **静默回绕**（1.0）/ ERROR（2.0） | 同左 | 取决于版本 |
| **StarRocks** | ERROR | ERROR | 无 |
| **Doris** | ERROR | ERROR | 无 |
| **Trino** | ERROR（始终） | ERROR | 无 |
| **DuckDB** | ERROR | ERROR | 无 |
| **Flink SQL** | **静默回绕** | **静默回绕** | 无 |
| **Redshift** | ERROR | ERROR | 无 |

### 分组总结

| 始终 ERROR | 静默回绕（危险!） | 返回 NULL | 不存在问题（大范围类型） |
|---|---|---|---|
| PostgreSQL, SQL Server, BigQuery, Trino, DuckDB, Redshift, StarRocks, Doris | Hive, ClickHouse（Int64 边界）, Spark 3.x（ANSI=off）, Flink, MaxCompute 1.0 | — | Oracle（NUMBER）, Snowflake（NUMBER(38,0)）, ClickHouse（≤32 位自动提升） |

**⚠️ 静默回绕是最危险的行为** —— Hive/Flink 中 `2147483647 + 1` 返回 `-2147483648`（Java 整数回绕），ClickHouse 对 ≤32 位类型自动提升到 Int64 避免了此问题，但 Int64 边界 `9223372036854775807 + 1` 仍然静默回绕。

---

## 4. 取模与负数 `SELECT -7 % 3`

| 方言 | `-7 % 3` | 规则 | 正模函数 |
|------|---------|------|---------|
| **所有方言** | **-1** | 符号跟随被除数（截断除法） | — |
| **Hive / Spark** | -1 | 同上 | `PMOD(-7, 3) = 2`（始终非负） |
| **MaxCompute** | -1 | 同上 | 同 Hive |

**结论**: 所有 SQL 方言对 `-7 % 3` 返回 `-1`（符号跟随被除数），与 SQL 标准一致。Hive/Spark 额外提供 `PMOD()` 始终返回非负结果，适用于 Hash 分桶场景。

---

## 5. 浮点精度 `SELECT 0.1 + 0.2 = 0.3`

| 方言 | 裸字面量 `0.1` 的类型 | `0.1 + 0.2 = 0.3` | 说明 |
|------|---------------------|-------------------|------|
| **MySQL** | DECIMAL | **TRUE** | 裸小数字面量按 DECIMAL（精确）处理 |
| **PostgreSQL** | NUMERIC | **TRUE** | 裸小数字面量按 NUMERIC（精确）处理 |
| **Oracle** | NUMBER | **TRUE** | NUMBER 是精确类型 |
| **SQL Server** | DECIMAL | **TRUE** | 裸小数字面量按 DECIMAL 处理 |
| **BigQuery** | FLOAT64 | **FALSE** | 裸小数字面量按 FLOAT64（IEEE 754）处理 |
| **Snowflake** | NUMBER | **TRUE** | NUMBER 是精确类型 |
| **ClickHouse** | Float64 | **FALSE** | 裸小数字面量按 Float64 处理 |
| **Hive** | DOUBLE | **FALSE** | 裸小数字面量按 DOUBLE 处理 |
| **Spark SQL** | DECIMAL（3.0+） | **TRUE** | 3.0+ 改为 DECIMAL；旧版本是 DOUBLE |
| **MaxCompute** | DOUBLE | **FALSE** | 裸小数字面量按 DOUBLE 处理 |
| **StarRocks** | DOUBLE | **FALSE** | 裸小数字面量按 DOUBLE 处理 |
| **Doris** | DOUBLE | **FALSE** | 裸小数字面量按 DOUBLE 处理 |
| **Trino** | DECIMAL | **TRUE** | 裸小数字面量按 DECIMAL 处理 |
| **DuckDB** | DECIMAL | **TRUE** | 裸小数字面量按 DECIMAL 处理 |
| **Flink SQL** | DECIMAL | **TRUE** | 裸小数字面量按 DECIMAL 处理 |
| **Redshift** | NUMERIC | **TRUE** | PG 兼容 |

### 分组总结

| `0.1` = DECIMAL/NUMERIC（精确，`0.1+0.2=0.3` TRUE） | `0.1` = FLOAT/DOUBLE（IEEE 754，`0.1+0.2=0.3` FALSE） |
|---|---|
| MySQL, PostgreSQL, Oracle, SQL Server, Snowflake, Spark 3.0+, Trino, DuckDB, Flink, Redshift | BigQuery, ClickHouse, Hive, MaxCompute, StarRocks, Doris |

**对引擎开发者**: 裸小数字面量的默认类型是一个关键设计决策。选择 DECIMAL 更安全（用户直觉 `0.1+0.2=0.3`），但 FLOAT64 性能更好。BigQuery 选择了 FLOAT64 并因此经常被用户吐槽。

---

## 6. DECIMAL 算术精度规则

### 加法 `DECIMAL(p1,s1) + DECIMAL(p2,s2)`

SQL 标准规则（大多数引擎遵循）:
- 结果小数位: `max(s1, s2)`
- 结果精度: `max(p1-s1, p2-s2) + 1 + max(s1, s2)`

示例: `DECIMAL(10,2) + DECIMAL(10,4)`:
- 小数位 = max(2,4) = 4
- 精度 = max(8,6) + 1 + 4 = 13
- 结果: `DECIMAL(13, 4)`

### 乘法 `DECIMAL(p1,s1) * DECIMAL(p2,s2)`

| 方言 | 精度规则 | `DECIMAL(10,2) * DECIMAL(10,2)` 结果 | 精度上限 |
|------|---------|--------------------------------------|---------|
| **MySQL** | `p1+p2`, `s1+s2` | DECIMAL(20, 4) | p=65 |
| **PostgreSQL** | 任意精度（自动扩展） | 自动适配 | 无上限 |
| **Oracle** | `p1+p2`, `s1+s2` | NUMBER 自动调整 | p=38 |
| **SQL Server** | `p1+p2+1`, `s1+s2` | DECIMAL(21, 4) | p=38（超限时缩减小数位） |
| **BigQuery** | 固定 NUMERIC(38,9) | NUMERIC(38,9) | p=38, s=9 |
| **Snowflake** | SQL 标准 | NUMBER(21, 4) | p=38 |
| **ClickHouse** | 自动选择最小容纳 Decimal 宽度 | Decimal128 或 Decimal256 | 256 位 |
| **Hive / Spark** | `p1+p2+1`, `s1+s2` | DECIMAL(21, 4) | p=38 |
| **MaxCompute** | `p1+p2+1`, `s1+s2` | DECIMAL(21, 4) | p=36 |
| **StarRocks / Doris** | 类似 Hive | DECIMAL(21, 4) | p=38 |
| **Trino / DuckDB / Flink** | `p1+p2+1`, `s1+s2` | DECIMAL(21, 4) | p=38 |
| **Redshift** | PG 规则 | DECIMAL(21, 4) | p=38 |

**精度超限时的行为**: 大多数引擎先缩减小数位（牺牲精度），仍然超限则报错。PostgreSQL 例外——无精度上限，自动扩展。

---

## 横向总结：最危险的跨引擎差异

| 排名 | 差异 | 影响 | 受影响方言 |
|------|------|------|-----------|
| 1 | 整数除法结果类型 | 金融计算错误 | PG/SS: `5/2=2`（截断），MySQL/Oracle: `5/2=2.5`（真除法） |
| 2 | 整数溢出静默回绕 | 累加器/计数器翻转为负数 | ClickHouse、Spark 3.x、Flink |
| 3 | 除零静默返回 NULL | 错误被掩盖 | MySQL、Hive、StarRocks、Doris |
| 4 | 裸字面量 `0.1` 的类型 | `0.1+0.2≠0.3` | BigQuery、ClickHouse、Hive |
| 5 | DECIMAL 精度上限 | 乘法连锁后精度溢出 | 除 PG 外所有引擎（p=38 上限） |

---

## 对引擎开发者的设计建议

1. **整数除法**: 推荐 PostgreSQL 方式（INT/INT=INT），与编程语言一致。提供 `DIV` 或 `IDIV` 函数作为显式选择
2. **除零**: 推荐 ERROR（SQL 标准），提供 `SAFE_DIVIDE()` 安全变体（BigQuery 模式）
3. **溢出**: **绝不静默回绕**——这是 ClickHouse/Flink 的设计缺陷。推荐 ERROR + 提供 `try_add()` 安全变体
4. **裸字面量**: 推荐 `0.1` 解析为 DECIMAL（精确），避免 `0.1+0.2≠0.3` 的用户困惑
5. **DECIMAL 精度**: p=38 是合理上限，但乘法链溢出时应报错而非静默截断

---

*注：本页信息均来自各引擎官方文档。具体行为可能随版本变化，建议以目标版本的官方文档为准。*
