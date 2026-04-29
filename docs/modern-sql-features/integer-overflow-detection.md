# 整数溢出检测 (Integer Overflow Detection)

`INT_MAX + 1` 在不同数据库里可能返回 `-2147483648`，可能抛 `ERROR 22003`，也可能因为类型自动提升而正常算出 `2147483648`——同一行 SQL 三种命运。整数溢出的运行时检测策略，是数据库正确性、安全性和性能之间最隐蔽也最关键的权衡之一。

## SQL:2003 标准定义

SQL:2003 标准（ISO/IEC 9075-2, Section 6.27 `<numeric value expression>`）对数值算术运算的溢出处理有明确规定：

```
If the result of a numeric value expression cannot be represented exactly
in the data type of the result, then a completion condition is raised:
exception condition - data exception - numeric value out of range
SQLSTATE: 22003
```

标准的核心要点：

1. **溢出 = 异常**：当算术结果超出目标类型可表示范围时，必须抛出 `data exception - numeric value out of range`
2. **SQLSTATE 22003**：标准化的错误代码，所有 SQL 92/99/2003 兼容数据库都应使用
3. **同样适用于 CAST**：`CAST(value AS smaller_type)` 时若值超出目标范围，也必须抛 22003
4. **不允许静默回绕**：标准明确禁止 wraparound（即 C 语言 `INT_MAX + 1 == INT_MIN` 这种行为）作为合法实现
5. **聚合函数同等约束**：`SUM`、`AVG` 等聚合算子在累加器溢出时同样必须抛异常

但标准只规定语义，不规定**检测机制**。引擎可以选择：

- 编译期类型推断（cast 加宽到不会溢出的类型）
- 运行时硬件标志检测（x86 OF 标志、ARM V 标志）
- 编译器内建函数（GCC `__builtin_add_overflow`）
- 软件检查（前置范围比较）
- 完全不检测（性能优先）

不同引擎的选择构成了本文要对比的核心差异。

## 安全意涵：为什么这不只是性能问题

整数溢出在数据库中不仅是数据损坏问题，还是**严重的安全漏洞来源**：

```sql
-- 经典的负余额漏洞（伪 SQL）
UPDATE accounts SET balance = balance - 9999999999
WHERE user_id = 1;
-- 如果 balance 是 INT 且未检测溢出，可能从 100 变为 ~21 亿正数
-- 攻击者可借此"创造"金钱

-- 另一个例子：分页参数溢出
SELECT * FROM logs LIMIT 100 OFFSET 4294967300;
-- 如果 OFFSET 截断为 32 位无符号，可能绕过权限边界

-- 累加器漏洞
SELECT SUM(suspicious_value) FROM tx_log;
-- 攻击者插入大量数据使 SUM 溢出回绕，造成审计记录失真
```

CWE-190（Integer Overflow or Wraparound）和 CWE-191（Integer Underflow）每年都出现在 OWASP Top 25 中。CVE-2007-4559（Python tarfile 路径整数溢出）、CVE-2018-1000156（GNU patch 整数溢出 RCE）等都源于未检测的整数运算。**对数据库而言，溢出检测是安全栈的一部分**，而不只是数据完整性问题。

## CHECK CONSTRAINT vs DBMS-级运行时检测

许多用户误以为 `CHECK (col >= 0)` 这类约束可以替代溢出检测——这是危险的误解：

```sql
CREATE TABLE accounts (
    balance INT CHECK (balance >= 0)
);

-- 假设 balance 当前为 1，执行：
UPDATE accounts SET balance = balance - 2147483647 WHERE user_id = 1;
-- 数学结果: 1 - 2147483647 = -2147483646（应被 CHECK 拦截）
-- 但若引擎在计算 balance - 2147483647 时已经发生 INT 溢出回绕，
-- 计算结果可能是 +X，反而通过了 CHECK！
```

**关键区别**：

| 维度 | CHECK CONSTRAINT | DBMS 运行时溢出检测 |
|------|----------------|------------------|
| 触发时机 | 行写入前 | 表达式求值时 |
| 检测对象 | 最终列值 | 每个算术中间结果 |
| 防御目标 | 业务规则违反 | 数据类型边界违反 |
| 可绕过性 | 表达式溢出后值"看起来"合法即可绕过 | 引擎层强制，无法绕过 |
| 性能开销 | 每行一次比较 | 每次算术运算检查 |
| 标准要求 | SQL-92 可选 | SQL:2003 强制（22003） |

正确的安全模型是**两者结合**：CHECK 约束防御业务规则，DBMS 溢出检测防御类型边界。本文聚焦后者。

## 三种基本策略：error / wrap / saturate

数据库对溢出的运行时响应可归为三大类：

### 1. Error（错误派）—— SQL 标准遵循者

`SELECT 2147483647::INT + 1` → 抛 `22003 numeric value out of range`，事务回滚或语句失败。

代表：PostgreSQL、SQL Server、Oracle、DuckDB、CockroachDB、Trino、Db2、Vertica、Teradata。

哲学：正确性优先于性能。引擎宁可让查询失败，也不返回错误数据。

### 2. Wrap（回绕派）—— 性能/底层映射优先

`SELECT 2147483647::Int32 + 1` → `-2147483648`（C 语言模 2^N 行为），无错误无警告。

代表：ClickHouse（默认）、Hive、Spark SQL（ANSI=off，默认到 3.4 之前）、Flink SQL、MySQL pre-5.7（默认 SQL_MODE 为空）、MaxCompute 1.0、SQLite（部分情况）。

哲学：直接映射底层硬件/JVM 行为，最高性能，把责任交给应用层。

### 3. Saturate（饱和派）—— 边界停留

`SELECT 2147483647::INT + 1` → `2147483647`（停在最大值），不报错不回绕。

代表：罕见。某些 DSP/嵌入式数据库（H2 部分情况）、特殊配置下的 ClickHouse。SQL 主流引擎中几乎不存在。

哲学：源自信号处理领域，把溢出值"压回"最近的有效边界，确保结果"方向正确"。但 SQL 中实践极少。

> 本文聚焦 error 与 wrap 两大主流，saturate 只在个别引擎角落出现。

## 支持矩阵 1：默认溢出行为（45+ 引擎）

> 所有列均假设 32 位 INT，未启用任何严格模式之外的特殊设置；测试表达式：`INT 2147483647 + 1`。
>
> "ERROR" = 抛 SQLSTATE 22003 或等价异常；"WRAP" = 返回 -2147483648（模 2^32）；"WIDEN" = 自动提升到 BIGINT/Int64 后正确返回 2147483648；"NULL" = 静默返回 NULL。

| 引擎 | INT + 1 溢出 | BIGINT 溢出 | UNSIGNED 溢出 | CAST 缩窄溢出 | 默认错误代码 |
|------|------------|------------|--------------|--------------|-----------|
| **PostgreSQL** | ERROR | ERROR | n/a（无 UNSIGNED） | ERROR | 22003 |
| **MySQL 8.0** | ERROR（strict） | ERROR | ERROR（NO_UNSIGNED_SUBTRACTION） | ERROR | 1264 ER_WARN_DATA_OUT_OF_RANGE |
| **MySQL 5.7** | ERROR（strict 默认开） | ERROR | ERROR | ERROR | 1264 |
| **MySQL 5.6 及以前** | WRAP（默认 SQL_MODE 空） | WRAP | WRAP | 截断 | 仅警告 |
| **MariaDB 10.x** | ERROR（strict 默认） | ERROR | ERROR | ERROR | 1264 |
| **Oracle** | n/a（NUMBER 自动扩展到 38 位） | n/a | n/a | ERROR (ORA-01438) | ORA-01426 在 PL/SQL |
| **SQL Server** | ERROR | ERROR | n/a | ERROR | 8115 Arithmetic overflow |
| **Db2 (LUW)** | ERROR | ERROR | n/a | ERROR | SQLSTATE 22003 |
| **SQLite** | WIDEN（动态类型→DOUBLE） | WIDEN | n/a | 静默回绕（type affinity） | 无 |
| **DuckDB** | ERROR | ERROR | ERROR | ERROR | 22003 |
| **ClickHouse** | WRAP（默认） | WRAP | WRAP | WRAP（默认） | 无；可配置抛错 |
| **Snowflake** | n/a（NUMBER(38,0)） | n/a | n/a | ERROR | 100036 |
| **BigQuery** | n/a（INT64 唯一类型） | ERROR | n/a | ERROR | OUT_OF_RANGE |
| **Redshift** | ERROR | ERROR | n/a | ERROR | 22003 |
| **Vertica** | ERROR | ERROR | n/a | ERROR | 22003 |
| **Greenplum** | ERROR（继承 PG） | ERROR | n/a | ERROR | 22003 |
| **YugabyteDB** | ERROR（继承 PG） | ERROR | n/a | ERROR | 22003 |
| **CockroachDB** | ERROR（v1+） | ERROR | n/a | ERROR | 22003 |
| **TiDB** | ERROR（默认 strict） | ERROR | ERROR | ERROR | 1264 |
| **OceanBase（MySQL 模式）** | ERROR | ERROR | ERROR | ERROR | 1264 |
| **PolarDB-X** | ERROR | ERROR | ERROR | ERROR | 1264 |
| **TDSQL / GoldenDB** | ERROR | ERROR | ERROR | ERROR | 1264 |
| **Spark SQL 3.4+** | WRAP（ANSI=off） / ERROR（ANSI=on） | 同上 | n/a | 同上 | INTEGER_OVERFLOW (SparkArithmeticException) |
| **Spark SQL 3.0–3.3** | WRAP（ANSI=off 默认） | WRAP | n/a | WRAP | n/a |
| **Hive** | WRAP（Java 原生整数） | WRAP | n/a | WRAP | 无 |
| **Trino** | ERROR | ERROR | n/a | ERROR | NUMERIC_VALUE_OUT_OF_RANGE |
| **Presto** | ERROR | ERROR | n/a | ERROR | 同上 |
| **Impala** | WRAP（早期）/ ERROR（4.0+ 部分情况） | WRAP | n/a | WRAP/ERROR | -- |
| **Flink SQL** | WRAP（INT 算术） / ERROR（DECIMAL） | WRAP | n/a | WRAP | -- |
| **Databricks** | 继承 Spark 配置 | 同 Spark | n/a | 同 Spark | INTEGER_OVERFLOW |
| **Doris** | ERROR | ERROR | n/a | ERROR | -- |
| **StarRocks** | ERROR | ERROR | n/a | ERROR | -- |
| **MaxCompute 1.0** | WRAP | WRAP | n/a | WRAP | -- |
| **MaxCompute 2.0** | ERROR（type 2.0 模式） | ERROR | n/a | ERROR | -- |
| **Teradata** | ERROR | ERROR | n/a | ERROR | 2616 Numeric overflow |
| **SAP HANA** | ERROR | ERROR | n/a | ERROR | SQL error 1339 / 22003 |
| **Informix** | ERROR | ERROR | n/a | ERROR | -1226 |
| **Firebird** | ERROR | ERROR | n/a | ERROR | -802 |
| **Firebolt** | ERROR | ERROR | n/a | ERROR | 22003 |
| **Yellowbrick** | ERROR | ERROR | n/a | ERROR | 22003 |
| **DatabendDB** | ERROR | ERROR | ERROR | ERROR | -- |
| **SingleStore (MemSQL)** | WRAP（默认）/ 可配置 | WRAP | WRAP | 可配 | -- |
| **H2** | ERROR | ERROR | n/a | ERROR | 22003 |
| **HSQLDB** | ERROR | ERROR | n/a | ERROR | 22003 |
| **Apache Derby** | ERROR | ERROR | n/a | ERROR | 22003 |
| **Sybase ASE** | ERROR（默认） / WRAP（@@arithabort=0 在某些上下文） | ERROR | n/a | ERROR | 3606 |
| **Sybase IQ** | ERROR | ERROR | n/a | ERROR | -- |
| **Amazon Athena** | ERROR（继承 Trino） | ERROR | n/a | ERROR | 同 Trino |
| **Azure Synapse** | ERROR | ERROR | n/a | ERROR | 8115 |
| **Google Spanner** | n/a（INT64 唯一） | ERROR | n/a | ERROR | OUT_OF_RANGE |
| **Materialize** | ERROR | ERROR | n/a | ERROR | 22003 |
| **RisingWave** | ERROR | ERROR | n/a | ERROR | 22003 |
| **QuestDB** | WRAP | WRAP | n/a | WRAP | -- |
| **CrateDB** | ERROR | ERROR | n/a | ERROR | 22003 |
| **TimescaleDB** | ERROR（继承 PG） | ERROR | n/a | ERROR | 22003 |
| **Exasol** | ERROR | ERROR | n/a | ERROR | 22003 |
| **MonetDB** | ERROR | ERROR | n/a | ERROR | 22003 |
| **InfluxDB (SQL)** | WRAP | WRAP | n/a | WRAP | -- |

> 统计：约 **40 个引擎默认抛错**（SQL 标准遵循），约 **8 个引擎默认静默回绕**（ClickHouse、Hive、Spark ANSI=off、Flink、QuestDB、SingleStore、Impala 旧版、InfluxDB），约 **3 个引擎不存在该问题**（Oracle/Snowflake/SQLite 通过类型设计回避）。
>
> MySQL 是历史关键转折点：**5.7 之前默认 wrap，5.7+ 默认 strict 抛错**。

## 支持矩阵 2：MySQL SQL_MODE 与溢出行为

MySQL 的溢出行为完全由 SQL_MODE 控制，没有任何其他单一引擎像 MySQL 这样把溢出策略变成会话级开关：

| SQL_MODE | 整数 INSERT 溢出 | 整数算术溢出 | UNSIGNED 减法 | DECIMAL 溢出 | DATE 越界 |
|----------|----------------|--------------|--------------|--------------|----------|
| `''`（空，5.6 默认） | 截断 + 警告 | WRAP + 警告 | 转 BIGINT UNSIGNED | 截断 | `0000-00-00` 或截断 |
| `STRICT_TRANS_TABLES` | ERROR（事务表） / 截断（非事务） | ERROR | 行为不变 | ERROR | ERROR |
| `STRICT_ALL_TABLES` | ERROR（所有表） | ERROR | 行为不变 | ERROR | ERROR |
| `NO_UNSIGNED_SUBTRACTION` | 同上 | 同上 | UNSIGNED a - b 可返回负数（提升为 BIGINT） | 同上 | 同上 |
| `TRADITIONAL` | ERROR | ERROR | 行为不变 | ERROR | ERROR |
| `ANSI` | 警告（非严格） | 警告 | 默认行为 | 警告 | 警告 |
| 5.7+ 默认 | `STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION,...` 包含 STRICT |
| 8.0 默认 | 同上，进一步加入 `NO_ZERO_DATE`、`ERROR_FOR_DIVISION_BY_ZERO` |

关键点：

1. **MySQL 的 strict mode 是会话级**：可以 `SET SESSION sql_mode = ''` 临时关闭检测
2. **STRICT_TRANS_TABLES 只对事务表生效**：MyISAM 表即使打开 strict 也只警告
3. **5.7 之前的迁移陷阱**：从 5.6 升级到 5.7 后，原来"成功"的 INSERT 突然报错
4. **ER_WARN_DATA_OUT_OF_RANGE (1264)**：MySQL 专属错误代码，与 SQLSTATE 22003 对应

## 支持矩阵 3：CAST 溢出（窄化转换）

`CAST(value AS smaller_type)` 是溢出最常见的入口，因为隐式 CAST 也走相同路径：

| 引擎 | `CAST(2147483648 AS INT)` | `CAST('99999' AS TINYINT)` | `CAST(1e20 AS BIGINT)` | TRY_CAST 安全版本 |
|------|--------------------------|--------------------------|---------------------|----------------|
| PostgreSQL | ERROR | ERROR | ERROR | 无 TRY_CAST，可用 `cast(... as text)::int` 配合异常处理 |
| MySQL（strict） | ERROR | ERROR | ERROR | -- |
| MySQL（非 strict） | 截断到 INT_MAX | 截断到 127 | 截断到 BIGINT_MAX | -- |
| Oracle | n/a | ERROR | ERROR | 无 |
| SQL Server | ERROR | ERROR | ERROR | `TRY_CAST` 返 NULL |
| BigQuery | ERROR | n/a（无 TINYINT） | ERROR | `SAFE_CAST` 返 NULL |
| Snowflake | ERROR | n/a | ERROR | `TRY_CAST` 返 NULL |
| ClickHouse | WRAP（默认） | WRAP | WRAP / Inf | `toInt32OrNull()`、`toInt32OrZero()`、`toInt32OrDefault()` |
| Spark SQL ANSI=on | ERROR | ERROR | ERROR | `try_cast()` 返 NULL（3.0+） |
| Spark SQL ANSI=off | WRAP / NULL | WRAP / NULL | WRAP / NULL | -- |
| Hive | WRAP / NULL | WRAP / NULL | WRAP / NULL | -- |
| Trino | ERROR | ERROR | ERROR | `TRY(cast)` 返 NULL |
| DuckDB | ERROR | ERROR | ERROR | `TRY_CAST` 返 NULL（0.10+） |
| CockroachDB | ERROR | ERROR | ERROR | -- |
| Redshift | ERROR | n/a | ERROR | -- |
| Vertica | ERROR | n/a | ERROR | -- |
| Teradata | ERROR | ERROR | ERROR | -- |
| Db2 | ERROR | ERROR | ERROR | -- |
| Doris | ERROR | ERROR | ERROR | -- |
| StarRocks | ERROR | ERROR | ERROR | -- |
| Flink SQL | NULL（默认） | NULL | NULL | `TRY_CAST` 等价行为 |
| Materialize | ERROR | ERROR | ERROR | -- |

## 支持矩阵 4：聚合函数溢出（SUM、AVG）

聚合函数对累加器溢出的处理是引擎差异最大的领域之一：

| 引擎 | `SUM(int_col)` 累加器类型 | 溢出行为 | 备注 |
|------|------------------------|---------|------|
| PostgreSQL | BIGINT (SMALLINT/INT 输入) / NUMERIC (BIGINT 输入) | ERROR | 自动加宽 |
| MySQL | DECIMAL（INT 输入提升） | ERROR（strict） | 自动加宽 |
| Oracle | NUMBER | n/a | NUMBER 范围极大 |
| SQL Server | BIGINT（INT 输入）/ NUMERIC（BIGINT 输入） | ERROR | 自动加宽 |
| BigQuery | INT64 | ERROR | 不加宽 |
| Snowflake | NUMBER(38, *) | ERROR（极少触发） | 自动加宽 |
| ClickHouse | 与输入同类型（默认） | WRAP（默认） | `sumWithOverflow()` 显式回绕；`sum()` 默认对 ≤32 位提升 Int64 |
| Spark SQL | BIGINT（INT 输入） | ERROR（ANSI=on）/ WRAP（ANSI=off） | 输入 BIGINT 仍可溢出 |
| Hive | BIGINT（INT 输入） | WRAP | 输入 BIGINT 仍可溢出 |
| Trino | BIGINT（INT 输入） | ERROR | 自动加宽 |
| DuckDB | HUGEINT（128 位） | 极少 ERROR | DuckDB 独有，几乎不溢出 |
| CockroachDB | DECIMAL | ERROR（极少） | 自动加宽 |
| Redshift | BIGINT / NUMERIC(38,0) | ERROR | 自动加宽 |
| Vertica | BIGINT / NUMERIC | ERROR | 自动加宽 |
| Teradata | BIGINT / NUMERIC(38) | ERROR | 自动加宽 |
| Doris | BIGINT / LARGEINT(128) | ERROR | LARGEINT 是 Doris 独有的 128 位类型 |
| StarRocks | BIGINT / LARGEINT(128) | ERROR | -- |
| TiDB | DECIMAL | ERROR | 兼容 MySQL |
| Flink SQL | 与输入同类型 | WRAP | 不加宽 |

> **DuckDB 的 HUGEINT 累加器**：DuckDB 在 SUM 聚合时使用 128 位整数作为累加器（INT64 输入也是），即使聚合 10^16 行 INT64 最大值也不会溢出。这是 DuckDB 设计上的"过度防御"，但消除了几乎所有现实场景下的溢出可能。
>
> **ClickHouse `sum` vs `sumWithOverflow`**：默认 `sum(Int32 col)` 会自动用 Int64 累加（避免溢出），但 `sum(Int64 col)` 仍然在 Int64 内累加（可能溢出）。`sumWithOverflow` 显式声明使用相同类型累加器，速度快但可能回绕。

## 支持矩阵 5：类型加宽提升（Widening Promotion）

不同引擎在算术运算前的类型加宽策略，决定了"看起来"会溢出的表达式实际是否会触发检测：

| 引擎 | INT + INT 结果类型 | INT * INT | SMALLINT + SMALLINT | UInt32 + UInt32 |
|------|------------------|-----------|--------------------|-----------------|
| PostgreSQL | INT | INT | SMALLINT | n/a |
| MySQL | BIGINT（自动加宽） | BIGINT | INT | BIGINT UNSIGNED |
| Oracle | NUMBER | NUMBER | NUMBER | n/a |
| SQL Server | INT | INT | INT（隐式提升） | n/a |
| ClickHouse | Int32（不加宽） | Int32（不加宽） | Int16（不加宽） | UInt32（不加宽） |
| BigQuery | INT64 | INT64 | n/a | n/a |
| Snowflake | NUMBER | NUMBER | NUMBER | n/a |
| Spark SQL | INT（不加宽） | INT | INT（隐式提升） | n/a |
| Hive | INT | INT | INT（隐式提升） | n/a |
| Trino | INTEGER（不加宽） | INTEGER | SMALLINT | n/a |
| DuckDB | INT（不加宽） | INT | SMALLINT | UINTEGER |
| Doris | BIGINT（自动加宽） | BIGINT | INT | -- |

> **MySQL 加宽 vs PostgreSQL 不加宽**：MySQL 把 `INT + INT` 自动加宽到 BIGINT，所以 `2147483647 + 1` 正常返回 `2147483648`（在 BIGINT 范围内）。PostgreSQL 不加宽，所以同样表达式抛 22003 错。这是两大主流引擎的根本设计差异。

## 各引擎深入分析

### PostgreSQL：始终抛错的标准范本

PostgreSQL 是 SQL:2003 溢出语义最严格的实现者：

```sql
-- 整数算术溢出
SELECT 2147483647::int + 1;
-- ERROR:  integer out of range
-- SQLSTATE: 22003

-- BIGINT 溢出
SELECT 9223372036854775807::bigint + 1;
-- ERROR:  bigint out of range

-- CAST 缩窄溢出
SELECT 99999::smallint;
-- ERROR:  smallint out of range

-- SUM 溢出（自动加宽到 BIGINT，但仍可溢出）
CREATE TABLE big (x bigint);
INSERT INTO big SELECT 9223372036854775000 FROM generate_series(1, 1000);
SELECT SUM(x) FROM big;
-- ERROR:  bigint out of range（聚合到 NUMERIC 后才安全）

-- 防御性写法
SELECT SUM(x::numeric) FROM big;  -- 提升到 NUMERIC，无溢出风险
```

PostgreSQL 实现细节：

- 检测使用 GCC 内建 `__builtin_add_overflow`、`__builtin_sub_overflow`、`__builtin_mul_overflow`（src/include/common/int.h）
- 在 `src/backend/utils/adt/int.c` 中所有算术函数都有 overflow 检查路径
- 没有"严格模式"开关——溢出始终抛错，无法关闭
- 错误是 ereport(ERROR)，会导致整个语句失败，事务进入 aborted 状态

### MySQL：strict mode 进化史

MySQL 是溢出处理变化最大的主流引擎：

```sql
-- MySQL 5.6 默认（SQL_MODE=''）
SELECT 2147483647 + 1;
-- 5.6: 自动提升到 BIGINT，返回 2147483648（实际不溢出，因为 MySQL 自动加宽）

-- 但插入到 INT 列：
CREATE TABLE t (x INT);
INSERT INTO t VALUES (2147483648);
-- 5.6 默认: 截断到 2147483647 + 警告（"Out of range value"）
-- 5.7+ strict: ERROR 1264

-- UNSIGNED 减法陷阱
SELECT CAST(1 AS UNSIGNED) - CAST(2 AS UNSIGNED);
-- 默认: 返回极大正数（18446744073709551615，模 2^64 回绕）
-- SET sql_mode = 'NO_UNSIGNED_SUBTRACTION':
--   返回 -1（提升到 BIGINT signed）

-- 强制溢出实验
SELECT CAST(9223372036854775807 AS UNSIGNED) + 1;
-- strict mode: ERROR 1690 BIGINT UNSIGNED value is out of range
-- 非 strict: 静默回绕到 0
```

MySQL strict mode 进化时间线：

| 版本 | 默认 SQL_MODE | 行为变化 |
|------|--------------|---------|
| 3.23（2001） | `''` | 完全无溢出检测，全部 wrap/截断 |
| 5.0（2005） | `''`（默认）但首次引入 STRICT_TRANS_TABLES | 用户可手动开启 |
| 5.5（2010） | `''` | strict 仍非默认 |
| 5.6（2013） | `NO_ENGINE_SUBSTITUTION` | strict 仍非默认；已有 ER_WARN_DATA_OUT_OF_RANGE 警告但不抛错 |
| **5.7（2015）** | `ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION` | **strict 默认开启** |
| 8.0（2018） | 类似 5.7（移除 NO_AUTO_CREATE_USER） | 默认含 STRICT_TRANS_TABLES |
| 8.4（2024） | 同 8.0 | 持续严格化 |

**5.6 → 5.7 的破坏性变化**：从 MySQL 5.6 升级到 5.7 是历史上最容易引发"突然报错"的迁移。原本 5.6 中默默截断的 INSERT 在 5.7 中直接抛 1264 错。许多生产数据库选择用 `sql_mode=''` 维持兼容性，但这等于关闭所有溢出检测。

### MariaDB：与 MySQL 的微妙分歧

MariaDB 整体兼容 MySQL 的 strict 模式，但有几个关键差异：

```sql
-- MariaDB 引入了 OLDLEVEL 兼容模式
SET sql_mode = 'MARIADB100' WHERE compat_level = 'mariadb_5_5';
-- 用于跨 MariaDB 版本兼容

-- MariaDB 默认更倾向于不丢数据
-- 但 strict_trans_tables 默认仍然开启
SHOW VARIABLES LIKE 'sql_mode';
-- STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION
```

### Oracle：NUMBER 的免疫性

Oracle 通过 NUMBER 类型设计回避了大部分整数溢出问题：

```sql
-- NUMBER 默认是 NUMBER(38, 0)，最大 10^38 - 1
SELECT 9999999999999999999999999999999999999 + 1 FROM DUAL;
-- 不报错（NUMBER 范围足够大）

-- 但 PL/SQL 的 PLS_INTEGER（绑定到 32 位 C int）会溢出
DECLARE
    x PLS_INTEGER := 2147483647;
BEGIN
    x := x + 1;  -- ORA-01426: numeric overflow
END;

-- BINARY_INTEGER 同样 32 位
DECLARE
    x BINARY_INTEGER := 2147483647;
BEGIN
    x := x + 1;  -- ORA-01426
END;

-- 隐式 CAST 到固定 NUMBER(p,s)
INSERT INTO t (col_number5) VALUES (1234567);  -- col 是 NUMBER(5)
-- ORA-01438: value larger than specified precision allowed for this column
```

Oracle 的关键洞察：**主表达式层面没有整数溢出**（NUMBER 自动扩展），但**列约束**（NUMBER(p,s)）和 **PL/SQL 标量类型**（PLS_INTEGER/BINARY_INTEGER）仍然会触发 ORA-01426 / ORA-01438。

### SQL Server：SET ARITHABORT 与 ARITHIGNORE

SQL Server 有两个独立的会话级设置控制溢出行为：

```sql
-- 默认行为
SELECT CAST(2147483647 AS INT) + 1;
-- 错误 8115: Arithmetic overflow error converting expression to data type int.

-- SET ARITHABORT ON（默认）：溢出抛错并终止 batch
SET ARITHABORT ON;
SELECT 2147483647 + 1;  -- 错误 8115，batch 终止

-- SET ARITHABORT OFF：不抛错，但配合 ARITHIGNORE 可改变行为
SET ARITHABORT OFF;
SET ARITHIGNORE OFF;  -- 默认
SELECT 2147483647 + 1;  -- 仍然抛错，但 batch 不立即终止

SET ARITHABORT OFF;
SET ARITHIGNORE ON;
SELECT 2147483647 + 1;  -- 返回 NULL，无错误，无警告

-- ANSI_WARNINGS 控制警告输出（不影响错误本身）
SET ANSI_WARNINGS ON;  -- 默认；显示截断/溢出警告
```

SQL Server 矩阵：

| ARITHABORT | ARITHIGNORE | 行为 |
|-----------|-------------|------|
| ON（默认） | 任意 | 溢出 → 错误 8115 + batch 终止 |
| OFF | OFF（默认） | 溢出 → 错误 + 警告，但 batch 继续 |
| OFF | ON | 溢出 → NULL，静默吞掉 |

`SET ARITHABORT ON` 是 SQL Server 推荐配置，同时也是部分场景（含索引视图、计算列索引、空间索引、Filtered indexes）的强制要求。

### ClickHouse：明确的"silent wrap"设计哲学

ClickHouse 是主流分析引擎中最坚定的"性能优先"派：

```sql
-- 默认行为：完全 wrap，不报错
SELECT toInt32(2147483647) + 1;
-- -2147483648（无错误，无警告）

SELECT toUInt8(255) + 1;
-- 0（UInt8 wrap）

-- 但 ClickHouse 有自动加宽规则保护小类型
SELECT toInt8(127) + toInt8(1);
-- 实际是 Int16 + Int16 → Int16 类型，结果 128（不 wrap）

-- 显式同类型聚合则会 wrap
SELECT sumWithOverflow(toInt8(127) + toInt8(1));
-- 可能 wrap，取决于聚合层

-- DECIMAL 检查可配置
SET decimal_check_overflow = 1;
SELECT toDecimal32(99, 0) * toDecimal32(99, 0);
-- DB::Exception: Decimal math overflow

SET decimal_check_overflow = 0;
SELECT toDecimal32(99, 0) * toDecimal32(99, 0);
-- 9801（在 Decimal32 范围内，不 wrap）
-- 但若结果超出 Decimal32 范围则 wrap

-- 整数检查相关 setting
SET arithmetic_max_value = 1000000;
-- 实验性 setting：硬性限制算术运算最大值

-- 显式安全函数
SELECT divideOrZero(10, 0);  -- 返回 0，不报错
SELECT moduloOrZero(10, 0);
SELECT toInt32OrZero('abc');  -- 0
SELECT toInt32OrNull('abc');  -- NULL
SELECT toInt32OrDefault('abc', -1);  -- -1
```

ClickHouse 的设计哲学（来自其官方文档）：

> "ClickHouse follows the C++ standard for integer arithmetic. Overflow is silent."

这是一个**有意的、显式的**设计选择，而非缺陷：

1. **性能**：每个加法都检查溢出在向量化执行中开销显著（流水线断裂、分支预测失败）
2. **OLAP 场景假设**：分析查询通常基于汇总后的数据，原始溢出可被业务逻辑容忍
3. **明确的安全函数**：提供 `*OrZero` / `*OrNull` / `*OrDefault` 系列让用户显式选择
4. **类型设计补偿**：通过 Int128/Int256/UInt128/UInt256 提供超大整数避免溢出

但代价是：迁移到 ClickHouse 时，**所有依赖溢出报错的安全检查都失效**。

### DuckDB：始终抛错 + HUGEINT 防御

DuckDB 在严格性和实用性之间做了细腻平衡：

```sql
-- INT 溢出：抛错
SELECT (2147483647::INT) + 1;
-- Error: Conversion Error: Type INT32 with value 2147483648 can't be cast
--        because the value is out of range for the destination type INT32

-- BIGINT 溢出：抛错
SELECT (9223372036854775807::BIGINT) + 1;
-- Conversion Error: Out of Range Error

-- HUGEINT (128 位)：扩展极大空间
SELECT (170141183460469231731687303715884105727::HUGEINT) + 1;
-- Error: Hugeint overflow
-- 但这需要 10^38 量级才会出现

-- TRY_CAST 安全版本（0.10.0+）
SELECT TRY_CAST('99999' AS TINYINT);  -- NULL
SELECT TRY_CAST(2147483648 AS INTEGER);  -- NULL

-- SUM 自动用 HUGEINT 累加（关键优势）
CREATE TABLE big_sum (x BIGINT);
INSERT INTO big_sum SELECT 9000000000000000000 FROM range(100);
SELECT SUM(x) FROM big_sum;
-- 900000000000000000000（HUGEINT 范围内，正确返回）
```

DuckDB 实现细节：

- 使用 GCC `__builtin_add_overflow` 系列内建函数
- 在 `src/common/operator/add.cpp`、`subtract.cpp`、`multiply.cpp` 中，每个类型组合都有专用 overflow 检查
- HUGEINT (`int128_t`) 是 DuckDB 独有特性，可作为聚合累加器
- 没有"strict mode"开关；溢出始终抛错

### SQLite：弱类型与隐式扩展

SQLite 因其弱类型 (type affinity) 系统，在溢出检测上行为非常独特：

```sql
-- INTEGER 溢出会自动转 REAL
SELECT 9223372036854775807 + 1;
-- 9.22337203685478e+18（自动转 DOUBLE，丢失精度）

-- INSERT 到 INTEGER 列
CREATE TABLE t (x INTEGER);
INSERT INTO t VALUES (9223372036854775807);
INSERT INTO t VALUES (9223372036854775808);  -- 超出 INT64
-- SQLite 会存储为 REAL（type affinity 允许）

-- 严格模式（3.37+）
CREATE TABLE t_strict (x INTEGER) STRICT;
INSERT INTO t_strict VALUES (9223372036854775808);
-- Runtime error: integer overflow

-- CAST 行为
SELECT CAST('99999999999999999999' AS INTEGER);
-- 在 SQLite 中是 9223372036854775807（INT64 截断到最大值）
-- 没有错误抛出

-- 算术表达式
SELECT (9223372036854775807 << 1);  -- 移位溢出
-- 0（截断）

-- SQLite 4 (实验性) 改用 Decimal 作为默认整数类型
```

SQLite 的关键特性：

1. **动态类型**：列声明类型只是 affinity 提示，不强制
2. **自动类型升级**：INT 溢出 → 自动转 REAL（双精度浮点）
3. **STRICT 模式（3.37, 2021）**：可选关键字让表强制类型，触发整数溢出错误
4. **CAST 截断**：把超出范围的字符串转 INTEGER 时截断到 INT64 边界，不报错

### Spark SQL：ANSI 模式与 Try* 函数

Spark 是 OLAP 引擎中溢出处理演进最快的：

```sql
-- 默认（ANSI=off）行为：wrap
SET spark.sql.ansi.enabled = false;  -- 历史默认
SELECT 2147483647 + 1;
-- -2147483648（Java 整数 wrap）

-- ANSI=on（3.0 引入，3.4+ 推荐）
SET spark.sql.ansi.enabled = true;
SELECT 2147483647 + 1;
-- org.apache.spark.SparkArithmeticException:
--   [ARITHMETIC_OVERFLOW] integer overflow

-- Try* 函数家族（3.4+，2023）
-- 即使 ANSI=off 也可以显式安全
SELECT try_add(2147483647, 1);  -- NULL
SELECT try_subtract(-2147483648, 1);  -- NULL
SELECT try_multiply(1000000, 1000000);  -- NULL（INT 溢出）
SELECT try_divide(10, 0);  -- NULL
SELECT try_cast('abc' AS INT);  -- NULL
SELECT try_to_number('99999999999999999999', '999...');  -- NULL

-- 4.0 进一步加入：
-- try_avg, try_sum, try_element_at, try_url_decode

-- 配置 Spark 4.0 默认
-- spark.sql.ansi.enabled = true 在 4.0 成为默认值
```

Spark Try\* 函数家族的引入时间表：

| Spark 版本 | 引入函数 | 备注 |
|-----------|---------|------|
| 3.0（2020） | `try_cast` | ANSI 模式开始可用 |
| 3.2（2021） | `try_add`, `try_subtract`, `try_multiply`, `try_divide` | 算术四则 |
| 3.3（2022） | `try_element_at`, `try_to_binary` | 数组与二进制 |
| 3.4（2023） | `try_to_number`, `try_to_timestamp` | 字符串解析 |
| 3.5（2023） | `try_aes_decrypt`, `try_url_decode` | 加密与编码 |
| 4.0（2025+） | `try_sum`, `try_avg`, `try_mod` | 聚合与取模 |

Try\* 函数的设计哲学是 **never throw, return NULL**——比 ANSI=on 的"全局抛错"更细粒度，让用户在每个表达式选择安全或非安全。这与 Trino 的 `TRY()`、Snowflake 的 `TRY_*`、SQL Server 的 `TRY_*` 一脉相承。

### CockroachDB：始终抛错（v1+）

CockroachDB 从 v1.0 (2017) 起就实现了严格的溢出检测：

```sql
-- INT 溢出
SELECT (2147483647::INT4) + 1;
-- ERROR: integer out of range for type int4

-- INT8（默认 INT 类型）溢出
SELECT (9223372036854775807::INT) + 1;
-- ERROR: integer out of range for type int

-- DECIMAL 任意精度（无溢出）
SELECT 1e100::DECIMAL + 1;  -- 正常

-- CAST 缩窄
SELECT 99999::INT2;
-- ERROR: integer out of range for type int2
```

CockroachDB 实现细节：

- 内部以 64 位整数运算，使用类似 PostgreSQL 的 `addOverflow` 检查
- 始终抛错，没有 strict mode 开关
- DECIMAL 类型无精度上限（继承 `apd` Go 库），无溢出
- 这与其分布式 OLTP 定位一致：正确性 > 性能

### TiDB：MySQL 兼容的 strict 模式

TiDB 在 SQL 兼容上紧跟 MySQL，包括 SQL_MODE 和 strict 行为：

```sql
-- TiDB 默认 SQL_MODE
SHOW VARIABLES LIKE 'sql_mode';
-- ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,
-- NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,
-- NO_ENGINE_SUBSTITUTION

-- 与 MySQL 相同的溢出错误代码
INSERT INTO t (int_col) VALUES (9999999999);
-- ERROR 1264 (22003): Out of range value for column 'int_col'

-- 与 MySQL 相同的关闭 strict 方式
SET SESSION sql_mode = '';
INSERT INTO t (int_col) VALUES (9999999999);
-- 截断 + 警告（与 MySQL pre-5.7 行为一致）

-- 但 TiDB 默认行为是 strict（与 MySQL 5.7+ 一致）
```

TiDB 的特殊性：因为它是分布式数据库，溢出检测在每个 TiKV 节点的算子层都有独立实现，而不是单一的 SQL 解析器层。这意味着 strict 模式必须通过 session 变量在所有节点同步。

### OceanBase / TDSQL / PolarDB-X：MySQL 协议派

国产分布式数据库的 MySQL 兼容模式遵循相同模型：

| 引擎 | 默认 SQL_MODE | 特殊补充 |
|------|--------------|---------|
| OceanBase（MySQL 模式） | 包含 STRICT_TRANS_TABLES | 同时支持 Oracle 模式（NUMBER 无溢出） |
| TDSQL | 包含 STRICT_TRANS_TABLES | 100% 兼容 MySQL 5.7/8.0 |
| PolarDB-X | 包含 STRICT_TRANS_TABLES | DRDS 协议层兼容 MySQL |
| GoldenDB | 包含 STRICT_TRANS_TABLES | -- |

但是这些引擎在分布式 SUM 聚合时的累加器溢出处理可能有差异——分布式预聚合通常用 BIGINT 或 DECIMAL，最终汇总时可能再次溢出。

## MySQL strict mode 详细演进

MySQL strict mode 的演化是 SQL 数据库历史上一次重要的"默认行为变更"，影响了几乎所有基于 MySQL 的衍生引擎。

### 5.0（2005）：strict mode 首次出现

```sql
-- 5.0 引入了 SQL_MODE 概念
SET sql_mode = 'STRICT_TRANS_TABLES';
-- 默认仍然是空，需要手动开启

-- 但 5.0 同时引入了 ER_WARN_DATA_OUT_OF_RANGE 警告
-- 即使 SQL_MODE='' 也会在 SHOW WARNINGS 中显示
```

### 5.5–5.6（2010–2013）：渐进警告

5.5 和 5.6 期间，warning 数量增多，但默认仍非 strict：

```sql
-- 5.6 默认 SQL_MODE
SHOW VARIABLES LIKE 'sql_mode';
-- 'NO_ENGINE_SUBSTITUTION'

-- 默认下 INSERT 截断只警告
INSERT INTO t (int_col) VALUES (99999999999);
-- 1 row affected, 1 warning
-- SHOW WARNINGS:
-- Warning 1264 Out of range value for column 'int_col' at row 1
```

### 5.7（2015）：默认 strict 的历史拐点

```sql
-- 5.7 默认 SQL_MODE
SHOW VARIABLES LIKE 'sql_mode';
-- 'ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,
--  NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,
--  NO_ENGINE_SUBSTITUTION'

-- 同样的 INSERT 现在抛错
INSERT INTO t (int_col) VALUES (99999999999);
-- ERROR 1264 (22003): Out of range value for column 'int_col' at row 1
```

5.7 的发布说明明确警告了这一变化：

> "If strict mode is in effect, an error occurs and the value is rejected.
> The default SQL_MODE in MySQL 5.7 includes STRICT_TRANS_TABLES,
> ONLY_FULL_GROUP_BY, ERROR_FOR_DIVISION_BY_ZERO ..."

### 8.0（2018）：进一步严格化

```sql
-- 8.0 默认 SQL_MODE
-- 'ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,
--  NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION'

-- 移除 NO_AUTO_CREATE_USER（原本默认含），因为 CREATE USER 语义改变
-- 增加 ERROR_FOR_DIVISION_BY_ZERO 默认 strict
```

### 迁移影响实例

```sql
-- 5.6 → 5.7 升级常见报错
-- 1. UNSIGNED 减法
SELECT CAST(1 AS UNSIGNED) - CAST(2 AS UNSIGNED);
-- 5.6: 18446744073709551615（wrap）
-- 5.7: ERROR 1690 BIGINT UNSIGNED value is out of range

-- 2. INSERT 越界
INSERT INTO t_int VALUES (99999999999);
-- 5.6: 截断到 INT_MAX，警告
-- 5.7: ERROR 1264

-- 3. 0/0 除法
SELECT 1/0;
-- 5.6: NULL
-- 5.7: NULL（除非在 INSERT/UPDATE 中，则抛错）

-- 4. ZERO DATE
INSERT INTO t (date_col) VALUES ('0000-00-00');
-- 5.6: 接受
-- 5.7: ERROR 1292 Incorrect date value
```

许多生产环境的常见对策：保留 `sql_mode = ''` 兼容模式，等于关闭所有 strict 检测。这是历史遗留问题中最常见的反模式。

## ClickHouse 的设计哲学深入

ClickHouse 的"silent wrap"是少数与 SQL 标准明确背离的设计选择，值得详细分析。

### 性能驱动的本质

```cpp
// ClickHouse 加法实现（伪代码，src/Functions/FunctionBinaryArithmetic.h）
template <typename A, typename B, typename Result>
Result add_impl(A a, B b) {
    return static_cast<Result>(a) + static_cast<Result>(b);
    // 注意：没有 __builtin_add_overflow 检查
    // 直接利用硬件溢出语义（Intel x86 OF 标志被忽略）
}
```

ClickHouse 在向量化执行 (Block-at-a-time) 中，每个算术运算可能要在 32K 行的 batch 上执行。每行加 overflow 检查相当于：

- 流水线断裂（条件分支）
- 分支预测失败时的 ~15 周期惩罚
- SIMD 向量化失效（标量回退）

实测数据（ClickHouse 自身性能测试）显示，强制 overflow 检查在简单 SUM 查询上有 ~2x 性能损失。

### ClickHouse 的补偿机制

为了让"silent wrap"在实践中可接受，ClickHouse 提供了多层防御：

```sql
-- 1. 自动加宽（避免常见小类型溢出）
SELECT toInt8(127) + toInt8(127);
-- 结果是 Int16（254），不 wrap
-- 因为 ClickHouse 类型推导规则：Int8 + Int8 → Int16

SELECT toInt16(32767) + toInt16(1);
-- 结果是 Int32（32768），不 wrap

SELECT toInt32(2147483647) + toInt32(1);
-- 结果是 Int64（2147483648），不 wrap
-- !!! 但只有 ≤32 位类型自动加宽

SELECT toInt64(9223372036854775807) + toInt64(1);
-- 结果是 Int64（-9223372036854775808），wrap!!!
-- 64 位不再加宽

-- 2. Decimal 检查
SET decimal_check_overflow = 1;  -- 默认开启（视版本）
SELECT toDecimal128(...) * toDecimal128(...);
-- 抛错：DB::Exception: Decimal math overflow

-- 3. 大整数类型
SELECT toInt256(...) + toInt256(...);
-- Int256 = 256 位有符号整数，最大约 5.79e+76
-- 实践中不会溢出

-- 4. 显式安全函数
SELECT bitAnd(toInt32(...), toInt32(...));  -- 位运算总是安全
SELECT divideOrZero(...);
SELECT moduloOrZero(...);
```

### ClickHouse 配置项

```sql
-- 主要 setting
SHOW SETTINGS LIKE '%overflow%';

-- decimal_check_overflow: Decimal 算术溢出检查（默认 1）
-- 但只检查 Decimal，不检查 Int

-- arithmetic_max_value（实验性）：
SET arithmetic_max_value = 1000;
SELECT toInt32(2000) + toInt32(0);
-- 实验性 setting，可能在不同版本中行为不同

-- 函数级显式行为
SELECT addOrThrow(2147483647, 1, toInt32(0));  -- 显式抛错版本（部分构建可用）
SELECT sumWithOverflow(...);  -- 显式不加宽，可能 wrap
```

ClickHouse 的态度是：**"我们告诉你会 wrap，你自己决定怎么处理"**。这与 PG 的"我帮你拦住"形成鲜明对比。两种哲学都有合理性，关键是**用户必须知道自己用的是哪一种**。

## Spark Try* 函数完整目录

Spark SQL 的 Try* 函数家族是 OLAP 引擎中最完整的"显式安全"函数集，值得作为参考标杆：

| 函数 | 引入版本 | 替代的不安全函数 | 溢出/异常返回 |
|------|---------|----------------|--------------|
| `try_cast` | 3.0 | `cast` | NULL |
| `try_add` | 3.2 | `+` | NULL |
| `try_subtract` | 3.2 | `-` | NULL |
| `try_multiply` | 3.2 | `*` | NULL |
| `try_divide` | 3.2 | `/` | NULL |
| `try_element_at` | 3.3 | `element_at`、`[]` | NULL |
| `try_to_binary` | 3.3 | `to_binary` | NULL |
| `try_to_number` | 3.4 | `to_number` | NULL |
| `try_to_timestamp` | 3.4 | `to_timestamp` | NULL |
| `try_aes_decrypt` | 3.5 | `aes_decrypt` | NULL |
| `try_url_decode` | 3.5 | `url_decode` | NULL |
| `try_avg` | 4.0 | `avg` | NULL（聚合溢出） |
| `try_sum` | 4.0 | `sum` | NULL（聚合溢出） |
| `try_mod` | 4.0 | `%` / `mod` | NULL |

使用模式：

```sql
-- 基本使用
SELECT try_add(a, b) FROM t;

-- 与 ANSI 模式正交：即使 ANSI=on 也可用 try_*
SET spark.sql.ansi.enabled = true;
SELECT try_add(2147483647, 1);  -- NULL（不抛错）

-- 与 try_cast 链式使用
SELECT try_add(try_cast(s AS INT), 1) FROM t;

-- 聚合场景（4.0+）
SELECT try_sum(amount) FROM transactions GROUP BY user_id;
-- 即使某用户 SUM 溢出，该组返回 NULL，不影响其他组
```

Spark Try\* 函数解决了一个根本设计矛盾：**ANSI=on 提供安全性但全局抛错，ANSI=off 性能好但不安全**。Try\* 让用户在表达式级别选择，是最灵活的设计。

## DuckDB 的 HUGEINT 累加器

DuckDB 在聚合溢出问题上做了一个独特设计：所有 SUM 聚合默认用 128 位整数 (HUGEINT) 作为累加器：

```sql
-- 即使输入是 BIGINT，累加器是 HUGEINT
CREATE TABLE big (x BIGINT);
INSERT INTO big SELECT 9000000000000000000 FROM range(1000);
SELECT SUM(x) FROM big;
-- 9000000000000000000000（HUGEINT 范围内）
-- PG/MySQL 都会抛 BIGINT 溢出错

-- 但 HUGEINT 仍可溢出（理论上）
INSERT INTO big SELECT 9223372036854775807 FROM range(20000000000);
SELECT SUM(x) FROM big;
-- 接近 1.8e+29，仍在 HUGEINT 范围（最大 ~1.7e+38）

-- HUGEINT 上限
SELECT (170141183460469231731687303715884105727::HUGEINT) + 1;
-- Error: Hugeint overflow
```

实际上，对于现实数据规模，HUGEINT 累加器几乎不会溢出。DuckDB 这一选择换来的是：

- 不需要类型加宽（输入 BIGINT 累加器也是 HUGEINT）
- 不需要 strict mode（极少触发溢出）
- 内存代价：每个 GROUP 的累加器 16 字节而非 8 字节
- CPU 代价：128 位加法 = 2 次 64 位加法 + 1 次进位检查

## 关键发现

### 1. SQL 标准的"理想"与现实的"分裂"

SQL:2003 明确要求溢出抛 SQLSTATE 22003，但全球数据库可粗分为四个阵营：

- **严格派**（~38 引擎）：默认抛错，符合标准。代表 PG/Oracle/SQL Server/DuckDB/CockroachDB
- **可配置派**（~5 引擎）：通过 SQL_MODE 或 ANSI 开关控制。代表 MySQL/Spark
- **静默回绕派**（~6 引擎）：默认 wrap，性能优先。代表 ClickHouse/Hive/Flink/QuestDB
- **类型回避派**（~3 引擎）：用大类型免疫。代表 Oracle/Snowflake/SQLite

### 2. MySQL 5.7 是关键拐点

2015 年 MySQL 5.7 默认开启 STRICT_TRANS_TABLES，是 SQL 生态中最重大的"默认行为安全化"事件。十年过去，仍有大量遗留系统通过 `sql_mode=''` 关闭 strict——这是隐藏的安全债务。

### 3. OLAP 引擎普遍倾向 wrap

OLTP 数据库默认抛错（PG/MySQL strict/Oracle/SQL Server），OLAP 引擎默认 wrap（ClickHouse/Hive/Spark ANSI=off/Flink）。这反映了**"OLTP 关心单条记录正确性，OLAP 关心整体吞吐"**的哲学分歧。但 Spark 3.4+ 和 Databricks 推动 ANSI=on 是反向修正。

### 4. Try* 函数是最优雅的折衷

Spark `try_add`、Trino `TRY()`、SQL Server `TRY_CAST`、Snowflake `TRY_*`、BigQuery `SAFE_*` 等表达式级安全函数，让用户在每个运算选择策略。这避免了"全局开关一刀切"的粗粒度。**新引擎设计强烈推荐**实现 Try\* 函数家族。

### 5. 类型加宽是隐式溢出保护

MySQL 把 `INT + INT` 自动加宽到 BIGINT，PostgreSQL 不加宽——这导致 `2147483647 + 1` 在 MySQL 中正常返回，在 PG 中抛错。**加宽是性能与正确性的平衡**：MySQL 牺牲计算速度换取"少出错"的用户体验，PG 反之。

### 6. CHECK 约束不能替代溢出检测

`CHECK (col >= 0)` 只在最终值上检查，但中间表达式的溢出可能让最终值"看起来合法"。**真正的安全栈必须 CHECK 约束 + DBMS 溢出检测两层叠加**。

### 7. 累加器溢出是隐藏陷阱

`SUM(int_col)` 在大表上的累加器溢出非常常见。各引擎策略：

- **加宽派**（PG/SQL Server/Spark/Trino）：INT 输入加宽到 BIGINT 累加，BIGINT 输入仍可溢出
- **任意精度派**（PG NUMERIC/Snowflake/Oracle）：累加器是 NUMERIC，几乎不溢出但慢
- **超大整数派**（DuckDB HUGEINT/Doris LARGEINT）：累加器是 128 位，几乎免疫
- **不加宽派**（ClickHouse `sum`/Hive/Flink）：累加器与输入同类型，最快但最危险

### 8. Saturate 几乎绝迹

理论上的"饱和"策略（溢出停在边界值）在 SQL 主流引擎中几乎完全消失。它源自 DSP 信号处理领域，但 SQL 用户更习惯 error 或 wrap 这两种"分立"语义。新引擎可以忽略此选项。

### 9. UNSIGNED 类型是溢出风险源

只有 MySQL/MariaDB/TiDB/OceanBase 等 MySQL 系支持 UNSIGNED。其他引擎（PG/Oracle/SQL Server）均不支持。UNSIGNED 减法是溢出最常见的来源（`a - b` 当 b > a 时回绕到极大值）。`NO_UNSIGNED_SUBTRACTION` SQL_MODE 通过提升到 BIGINT signed 来缓解。

### 10. 引擎设计建议

对实现新数据库引擎的开发者，溢出检测策略推荐：

1. **默认抛错**：符合 SQL:2003，符合用户最小惊讶原则
2. **使用 `__builtin_add_overflow` 系列**：GCC/Clang 内建，开销最小（~3% 比无检查）
3. **提供 Try\* 函数族**：表达式级安全降级，模仿 Spark/Trino
4. **聚合用大累加器**：DuckDB HUGEINT 模式，避免 SUM 溢出
5. **不要提供"关闭检测"开关**：会成为安全债务的源头（参考 MySQL `sql_mode=''`）
6. **错误消息要精确**：包含类型、值、运算，符合 SQLSTATE 22003

## 完整测试用例

以下查询可在任何引擎上验证溢出行为：

```sql
-- 测试 1: INT + 1 溢出
SELECT 2147483647 + 1;
-- 预期：error / -2147483648 / 2147483648（取决于加宽）

-- 测试 2: BIGINT 边界
SELECT 9223372036854775807 + 1;
-- 预期：error / -9223372036854775808

-- 测试 3: 缩窄 CAST
SELECT CAST(99999 AS SMALLINT);
-- 预期：error / 截断 / -31073（wrap）

-- 测试 4: UNSIGNED 减法（MySQL 系）
SELECT CAST(1 AS UNSIGNED) - CAST(2 AS UNSIGNED);
-- 预期：error / 18446744073709551615 / -1（NO_UNSIGNED_SUBTRACTION）

-- 测试 5: 乘法溢出
SELECT 100000 * 100000;
-- 预期：error / 1410065408（wrap）/ 10000000000（加宽）

-- 测试 6: 累加器溢出
WITH RECURSIVE nums(n) AS (
    SELECT 1 UNION ALL SELECT n+1 FROM nums WHERE n < 100
)
SELECT SUM(2147483647) FROM nums;
-- 预期：error / 加宽到 BIGINT 后正确

-- 测试 7: 浮点 vs 整数
SELECT 1.0e308 * 10;
-- 预期：Inf / overflow error（取决于 IEEE 754 处理）

-- 测试 8: TRY 函数（如可用）
SELECT try_add(2147483647, 1);
-- 预期：NULL（如果支持）

-- 测试 9: ABS 溢出（边角案例）
SELECT ABS(-2147483648);
-- 预期：error（INT_MIN 取绝对值溢出）/ -2147483648（保持原值）

-- 测试 10: CAST FLOAT → INT
SELECT CAST(2147483648.5 AS INT);
-- 预期：error / 2147483647（截断）/ -2147483648（wrap）
```

## 参考资料

- SQL:2003 标准: ISO/IEC 9075-2, Section 6.27 `<numeric value expression>` 与异常 22003
- PostgreSQL: [Numeric Types](https://www.postgresql.org/docs/current/datatype-numeric.html)
- PostgreSQL Source: `src/include/common/int.h`、`src/backend/utils/adt/int.c`
- MySQL: [Out-of-Range and Overflow Handling](https://dev.mysql.com/doc/refman/8.0/en/out-of-range-and-overflow.html)
- MySQL: [SQL Mode](https://dev.mysql.com/doc/refman/8.0/en/sql-mode.html)
- MySQL 5.7 Release Notes: [Default SQL_MODE Changes](https://dev.mysql.com/doc/refman/5.7/en/sql-mode.html#sql-mode-changes)
- Oracle: [PLS_INTEGER and BINARY_INTEGER](https://docs.oracle.com/en/database/oracle/oracle-database/19/lnpls/plsql-data-types.html)
- SQL Server: [SET ARITHABORT](https://learn.microsoft.com/en-us/sql/t-sql/statements/set-arithabort-transact-sql)
- SQL Server: [SET ARITHIGNORE](https://learn.microsoft.com/en-us/sql/t-sql/statements/set-arithignore-transact-sql)
- ClickHouse: [Arithmetic Functions](https://clickhouse.com/docs/sql-reference/functions/arithmetic-functions)
- ClickHouse: [Integer Settings](https://clickhouse.com/docs/operations/settings/settings#decimal_check_overflow)
- DuckDB: [Numeric Types](https://duckdb.org/docs/sql/data_types/numeric)
- DuckDB Source: `src/common/operator/add.cpp`
- Spark SQL: [ANSI Compliance](https://spark.apache.org/docs/latest/sql-ref-ansi-compliance.html)
- Spark SQL: [Try Functions](https://spark.apache.org/docs/latest/api/sql/index.html#try_add)
- Trino: [Conditional Expressions - TRY](https://trino.io/docs/current/functions/conditional.html#try)
- BigQuery: [SAFE Functions](https://cloud.google.com/bigquery/docs/reference/standard-sql/functions-and-operators#safe_prefix)
- Snowflake: [TRY_CAST](https://docs.snowflake.com/en/sql-reference/functions/try_cast)
- CockroachDB: [Numeric Types](https://www.cockroachlabs.com/docs/stable/int.html)
- TiDB: [SQL Mode](https://docs.pingcap.com/tidb/stable/sql-mode/)
- CWE-190: [Integer Overflow or Wraparound](https://cwe.mitre.org/data/definitions/190.html)
- CWE-191: [Integer Underflow](https://cwe.mitre.org/data/definitions/191.html)

---

*注：本页信息均来自各引擎官方文档与实测。具体行为可能随版本变化，建议以目标版本的官方文档为准。Saturate 策略在 SQL 主流引擎中已基本绝迹。*
