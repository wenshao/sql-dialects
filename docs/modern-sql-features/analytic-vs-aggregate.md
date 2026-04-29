# 分析函数 vs 聚合函数 (Analytic vs Aggregate Functions)

`SUM(amount)` 与 `SUM(amount) OVER ()` 长得几乎一模一样，但前者把全表压缩成一行，后者保留每一行并附带一个全局总和——分析函数和聚合函数是 SQL 中名字最像、语义最不同的一对孪生兄弟，引擎开发者必须分清楚它们在执行管道中的位置。

## 同名异果：一行代码的本质区别

```sql
-- 聚合函数：分组后每组一行 (pre-grouping evaluation)
SELECT department_id, SUM(salary) AS total_salary
FROM employees
GROUP BY department_id;
-- 输出: 每个部门一行

-- 分析函数：保留所有行，附加聚合值 (post-grouping / windowed evaluation)
SELECT employee_id, salary,
       SUM(salary) OVER (PARTITION BY department_id) AS dept_total
FROM employees;
-- 输出: 原表每一行 + 部门总和列
```

两个 `SUM(salary)` 看上去一样，执行模型却截然不同：

1. **聚合函数（Aggregate Function）**：在 `GROUP BY` 之前求值，把多行折叠成一行。输出行数 ≤ 输入行数（极端情况下 1 行）。
2. **分析函数（Analytic Function）**：在 `WHERE`/`GROUP BY`/`HAVING` 之后、`ORDER BY` 之前求值，输出行数 = 输入行数（不折叠）。每行可以"看到"自己所在窗口（PARTITION）的全部行。

引擎实现上，前者走 `HashAggregate` / `SortAggregate` 算子，后者走 `WindowAgg` / `Window` 算子。理解两者的区别，是阅读 EXPLAIN 输出、设计执行计划、甚至排查"为什么我的 GROUP BY 报错"的前置知识。

## SQL 标准的演进

### SQL:1992 — 聚合函数的诞生

SQL-92（ISO/IEC 9075:1992）首次系统化定义了聚合函数：

```sql
COUNT(*) | COUNT([ALL | DISTINCT] expr)
SUM([ALL | DISTINCT] expr)
AVG([ALL | DISTINCT] expr)
MIN(expr)
MAX(expr)
```

核心约束：
1. 必须配合 `GROUP BY` 或作为标量聚合（无 GROUP BY 时全表归一）
2. 在 `WHERE` 之后、`HAVING` 之前求值
3. NULL 忽略（`COUNT(*)` 例外）
4. 不能嵌套（`SUM(AVG(x))` 非法）

### SQL:1999 — OLAP 函数的预热

SQL:1999 引入 `GROUPING SETS`/`CUBE`/`ROLLUP`，扩展了多维聚合，但尚未引入"窗口"概念。同年 Oracle 8i（1999）已经在产品中提供了完整的分析函数，比标准早了 4 年。

### SQL:2003 — 窗口函数（分析函数）正式入标

SQL:2003 标准（ISO/IEC 9075-2:2003）首次将"窗口函数"纳入 ANSI SQL，提供了：

```sql
-- 标准语法
function_name([arguments]) OVER (
    [PARTITION BY partition_expr_list]
    [ORDER BY order_expr_list]
    [frame_clause]
)

-- frame_clause:
-- ROWS | RANGE BETWEEN frame_start AND frame_end
```

新引入：
- **OVER 子句**：分析函数的语法标志
- **窗口聚合**（windowed aggregates）：所有 SQL-92 聚合函数都可以加 `OVER()` 变成分析函数
- **专用分析函数**：`ROW_NUMBER`、`RANK`、`DENSE_RANK`、`PERCENT_RANK`、`CUME_DIST`、`LAG`、`LEAD`、`FIRST_VALUE`、`LAST_VALUE`、`NTILE` 等
- **滑动窗口**：通过 `ROWS BETWEEN ... AND ...` 定义任意子集

### SQL:2011 — RANGE/GROUPS 与 EXCLUDE

SQL:2011 增强：`RANGE` 帧的数值/时间偏移、`GROUPS` 帧、`EXCLUDE CURRENT ROW` 等。

### SQL:2003 / SQL:2011 — FILTER 落地到窗口

SQL:2003 标准化 `FILTER (WHERE ...)` 子句（feature T611，作用于普通聚合），SQL:2011 进一步扩展到窗口聚合：

```sql
SUM(amount) FILTER (WHERE status = 'paid') OVER (PARTITION BY customer_id)
```

## 支持矩阵（45+ 引擎综合）

### 维度 1：基础聚合 + 窗口聚合（OVER）支持

| 引擎 | SUM/AVG/MIN/MAX | COUNT(*) | 聚合函数加 OVER() | 引入版本 |
|------|:---:|:---:|:---:|------|
| PostgreSQL | 是 | 是 | 全部聚合可作窗口 | 8.4 (2009) |
| MySQL | 是 | 是 | 是 | 8.0 (2018) |
| MariaDB | 是 | 是 | 是 | 10.2 (2017) |
| SQLite | 是 | 是 | 是 | 3.25 (2018) |
| Oracle | 是 | 是 | 全部聚合可作窗口 | 8i (1999) |
| SQL Server | 是 | 是 | 是 | 2012 (window aggregates) |
| DB2 | 是 | 是 | 是 | 8.0 (2002) |
| Snowflake | 是 | 是 | 是 | GA |
| BigQuery | 是 | 是 | 是 | GA |
| Redshift | 是 | 是 | 是 | GA |
| DuckDB | 是 | 是 | 是 | 0.1 (2019) |
| ClickHouse | 是 | 是 | 是 | 21.x+（专用 windowFunctions） |
| Trino | 是 | 是 | 是 | 早期 |
| Presto | 是 | 是 | 是 | 早期 |
| Spark SQL | 是 | 是 | 是 | 1.4+ |
| Hive | 是 | 是 | 是 | 0.11+ |
| Flink SQL | 是 | 是 | 是 (流式 OVER) | 1.7+ |
| Databricks | 是 | 是 | 是 | GA |
| Teradata | 是 | 是 | 是 | V2R5 (2002) |
| Greenplum | 是 | 是 | 是 | 继承 PG |
| CockroachDB | 是 | 是 | 是 | 2.0+ |
| TiDB | 是 | 是 | 是 | 5.0+ |
| OceanBase | 是 | 是 | 是 | 3.x+ |
| YugabyteDB | 是 | 是 | 是 | 继承 PG |
| SingleStore | 是 | 是 | 是 | GA |
| Vertica | 是 | 是 | 是 | 早期 |
| Impala | 是 | 是 | 是 | 2.0+ |
| StarRocks | 是 | 是 | 是 | 2.0+ |
| Doris | 是 | 是 | 是 | 1.0+ |
| MonetDB | 是 | 是 | 是 | Jul2015+ |
| CrateDB | 是 | 是 | 是 | 4.0+ |
| TimescaleDB | 是 | 是 | 是 | 继承 PG |
| QuestDB | 是 | 是 | 部分（SAMPLE BY 优先） | -- |
| Exasol | 是 | 是 | 是 | 6.0+ |
| SAP HANA | 是 | 是 | 是 | 1.0+ |
| Informix | 是 | 是 | 是 | 12.10+ |
| Firebird | 是 | 是 | 是 | 3.0+ |
| H2 | 是 | 是 | 是 | 1.4.198+ |
| HSQLDB | 是 | 是 | 是 | 2.5+ |
| Derby | 是 | 是 | 不支持 | 仅基础聚合 |
| Amazon Athena | 是 | 是 | 是 | 继承 Trino |
| Azure Synapse | 是 | 是 | 是 | GA |
| Google Spanner | 是 | 是 | 是 | GA |
| Materialize | 是 | 是 | 是 | 继承 PG |
| RisingWave | 是 | 是 | 流式 OVER | GA |
| InfluxDB (SQL) | 是 | 是 | 部分 | 时序专用 |
| DatabendDB | 是 | 是 | 是 | GA |
| Yellowbrick | 是 | 是 | 是 | GA |
| Firebolt | 是 | 是 | 是 | GA |

> 统计：48 个引擎中，47 个支持窗口聚合（`SUM(...) OVER ()`），仅 Apache Derby 至今未实现窗口函数。聚合函数本身（不带 OVER）则 100% 普及。

### 维度 2：纯分析函数族（专用窗口函数）

排序类：`ROW_NUMBER`、`RANK`、`DENSE_RANK`、`PERCENT_RANK`、`CUME_DIST`、`NTILE`
偏移类：`LAG`、`LEAD`
取值类：`FIRST_VALUE`、`LAST_VALUE`、`NTH_VALUE`

| 引擎 | ROW_NUMBER | RANK/DENSE_RANK | NTILE | LAG/LEAD | FIRST/LAST_VALUE | NTH_VALUE | PERCENT_RANK | CUME_DIST |
|------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| PostgreSQL | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| MySQL 8.0+ | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| MariaDB 10.2+ | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| SQLite 3.25+ | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Oracle | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| SQL Server | 是 | 是 | 是 | 是 | 是 | 不支持 | 是 | 是 |
| DB2 | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Snowflake | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| BigQuery | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Redshift | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| DuckDB | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| ClickHouse | 是 | 是 | 是 | 是 (lagInFrame) | 是 | 是 | 不支持 | 不支持 |
| Trino | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Presto | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Spark SQL | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Hive | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Flink SQL | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Databricks | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Teradata | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Greenplum | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| CockroachDB | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| TiDB | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| OceanBase | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| YugabyteDB | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| SingleStore | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Vertica | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Impala | 是 | 是 | 是 | 是 | 是 | 不支持 | 不支持 | 不支持 |
| StarRocks | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Doris | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| MonetDB | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| CrateDB | 是 | 是 | 是 | 是 | 是 | 是 | 不支持 | 不支持 |
| TimescaleDB | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| QuestDB | 是 | 是 | 不支持 | 是 | 是 | 不支持 | 不支持 | 不支持 |
| Exasol | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| SAP HANA | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Informix | 部分 | 部分 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| Firebird | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| H2 | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| HSQLDB | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Derby | 是（部分） | 是（部分） | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| Amazon Athena | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Azure Synapse | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Google Spanner | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Materialize | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| RisingWave | 是 | 是 | 部分 | 是 | 是 | 不支持 | 不支持 | 不支持 |
| InfluxDB (SQL) | 部分 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| DatabendDB | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Yellowbrick | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Firebolt | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |

### 维度 3：FILTER 子句对窗口聚合的支持

SQL:2003 引入 `agg_func(...) FILTER (WHERE cond)`（feature T611），SQL:2011 扩展到窗口聚合 `agg_func(...) FILTER (WHERE cond) OVER (...)`。

| 引擎 | FILTER on aggregate | FILTER on windowed aggregate | 引入版本 |
|------|:---:|:---:|------|
| PostgreSQL | 9.4+ | 12+ | 12 (2019) |
| MySQL | 不支持 | 不支持 | -- |
| MariaDB | 不支持 | 不支持 | -- |
| SQLite | 3.30+ | 3.30+ | 3.30 (2019) |
| Oracle | 不支持 (用 CASE WHEN) | 不支持 | -- |
| SQL Server | 不支持 (用 CASE WHEN) | 不支持 | -- |
| DB2 | 不支持 | 不支持 | -- |
| Snowflake | 不支持 (用 CASE WHEN) | 不支持 | -- |
| BigQuery | 不支持 | 不支持 | -- |
| Redshift | 不支持 | 不支持 | -- |
| DuckDB | 是 | 是 | 0.3+ |
| ClickHouse | 不支持 | 不支持 | -- |
| Trino | 是 | 是 | 早期 |
| Presto | 是 | 是 | 早期 |
| Spark SQL | 3.0+ | 不支持 (聚合可，窗口不可) | 3.0 (2020) |
| Hive | 不支持 | 不支持 | -- |
| Flink SQL | 部分 | 不支持 | -- |
| Databricks | 是 | 部分 | 同 Spark SQL |
| Teradata | 不支持 | 不支持 | -- |
| Greenplum | 是 | 12+ 兼容 | 继承 PG |
| CockroachDB | 是 | 是 | 20.1+ |
| TiDB | 不支持 | 不支持 | -- |
| OceanBase | 不支持 | 不支持 | -- |
| YugabyteDB | 是 | 是 | 继承 PG 12+ |
| SingleStore | 不支持 | 不支持 | -- |
| Vertica | 不支持 | 不支持 | -- |
| Impala | 不支持 | 不支持 | -- |
| StarRocks | 不支持 | 不支持 | -- |
| Doris | 不支持 | 不支持 | -- |
| MonetDB | 是 | 是 | Jul2015+ |
| CrateDB | 是 | 部分 | 4.0+ |
| TimescaleDB | 是 | 是 | 继承 PG |
| QuestDB | 不支持 | 不支持 | -- |
| Exasol | 不支持 | 不支持 | -- |
| SAP HANA | 不支持 | 不支持 | -- |
| Informix | 不支持 | 不支持 | -- |
| Firebird | 是 | 部分 | 3.0+ |
| H2 | 是 | 是 | 2.0+ |
| HSQLDB | 是 | 是 | 2.5+ |
| Derby | 不支持 | 不支持 | -- |
| Amazon Athena | 是 | 是 | 继承 Trino |
| Azure Synapse | 不支持 | 不支持 | -- |
| Google Spanner | 不支持 | 不支持 | -- |
| Materialize | 是 | 是 | 继承 PG |
| RisingWave | 是 | 部分 | GA |
| InfluxDB (SQL) | 不支持 | 不支持 | -- |
| DatabendDB | 是 | 部分 | GA |
| Yellowbrick | 是 | 是 | 继承 PG |
| Firebolt | 不支持 | 不支持 | -- |

### 维度 4：累计聚合 / Running Total（窗口聚合的最大用例）

`SUM(...) OVER (ORDER BY ... ROWS UNBOUNDED PRECEDING)` —— 几乎所有支持窗口的引擎都支持，差异在于默认帧。

| 引擎 | UNBOUNDED PRECEDING | RANGE 默认帧 | ROWS 默认帧 | 备注 |
|------|:---:|:---:|:---:|------|
| PostgreSQL | 是 | RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW | 同 | 标准默认 |
| MySQL 8.0+ | 是 | 同上 | 同 | 标准默认 |
| Oracle | 是 | 同上 | 同 | 标准默认 |
| SQL Server | 是 | 同上 | 同 | 标准默认 |
| DB2 | 是 | 同上 | 同 | 标准默认 |
| Snowflake | 是 | 同上 | 同 | 标准默认 |
| BigQuery | 是 | 同上 | 同 | 标准默认 |
| Redshift | 是 | 无 ORDER BY 时窗口为整个分区 | 同 | 标准默认 |
| ClickHouse | 是 | 同上 | 同 | -- |
| Trino/Presto | 是 | 同上 | 同 | -- |
| Spark SQL | 是 | 同上 | 同 | -- |
| Flink SQL | 是 | 同上 | 同（仅 ROWS） | RANGE 限制：仅时间窗口 |

### 维度 5：RATIO_TO_REPORT（占比函数）

`RATIO_TO_REPORT(expr)` 是 Oracle 8i 引入的非标准函数，等价于 `expr / SUM(expr) OVER (PARTITION BY ...)`。

| 引擎 | RATIO_TO_REPORT | 等价 SUM/SUM 写法 | 引入版本 |
|------|:---:|:---:|------|
| Oracle | 是 | 是 | 8i (1999) |
| PostgreSQL | 不支持 | 是（手写 SUM/SUM） | -- |
| MySQL | 不支持 | 是 | -- |
| SQL Server | 不支持 | 是 | -- |
| DB2 | 不支持 | 是 | -- |
| Snowflake | 是（兼容 Oracle） | 是 | GA |
| BigQuery | 不支持 | 是 | -- |
| Redshift | 是（兼容 PostgreSQL/Oracle 部分） | 是 | GA |
| Teradata | 是 | 是 | V2R5 |
| Vertica | 是 | 是 | 早期 |
| SAP HANA | 是 | 是 | 1.0+ |
| Greenplum | 是 | 是 | 早期 |
| Impala | 不支持 | 是 | -- |
| ClickHouse | 不支持 | 是 | -- |
| 其他多数引擎 | 不支持 | 是 | -- |

> RATIO_TO_REPORT 至今未被任何 SQL 标准收录，但 Oracle、Teradata、Snowflake、Redshift、Vertica、SAP HANA 等"传统数仓"出于兼容性收纳了它。在不支持的引擎中，写 `expr * 1.0 / SUM(expr) OVER (PARTITION BY ...)` 即可。

### 维度 6：分布函数（CUME_DIST / PERCENT_RANK）

| 引擎 | PERCENT_RANK | CUME_DIST | 备注 |
|------|:---:|:---:|------|
| PostgreSQL | 是 | 是 | 8.4+ |
| MySQL 8.0+ | 是 | 是 | 8.0 |
| Oracle | 是 | 是 | 8i |
| SQL Server | 是 | 是 | 2012 |
| DB2 | 是 | 是 | 8.0 |
| Snowflake | 是 | 是 | GA |
| BigQuery | 是 | 是 | GA |
| Redshift | 是 | 是 | GA |
| DuckDB | 是 | 是 | 0.3+ |
| ClickHouse | 不支持 | 不支持 | 用 row_number/count() 模拟 |
| Trino | 是 | 是 | 早期 |
| Spark SQL | 是 | 是 | 1.6+ |
| Hive | 是 | 是 | 0.13+ |
| Flink SQL | 是 | 是 | 1.7+ |
| Teradata | 是 | 是 | V2R5 |
| Vertica | 是 | 是 | 早期 |
| Greenplum | 是 | 是 | 继承 PG |
| Impala | 不支持 | 不支持 | -- |
| StarRocks | 是 | 是 | 2.0+ |
| 其他主要引擎 | 是 | 是 | 大多数支持 |

## 执行模型对比

### 聚合（GROUP BY）：折叠

```
SELECT department, SUM(salary)
FROM employees
GROUP BY department;

执行管道:
  Scan(employees)
    -> HashAggregate / SortAggregate
       hash key: department
       agg: SUM(salary)
    -> Output: 每组 1 行 (department, sum_salary)

特点:
  - 输入: N 行
  - 输出: G 行 (G = 不同组数)
  - 内存: O(G) 维护哈希表
  - 时间: O(N) (HashAggregate) 或 O(N log N) (SortAggregate)
```

### 分析（OVER）：保留

```
SELECT employee_id, salary,
       SUM(salary) OVER (PARTITION BY department) AS dept_total
FROM employees;

执行管道:
  Scan(employees)
    -> Sort by department (或 Hash partition)
    -> WindowAgg
       partition key: department
       agg: SUM(salary) per partition
    -> Output: 每行 1 行 (employee_id, salary, dept_total)

特点:
  - 输入: N 行
  - 输出: N 行 (不折叠)
  - 内存: O(分区大小) 维护当前分区状态
  - 时间: O(N log N) 排序 + O(N) 聚合
```

### 三阶段窗口执行

详见 [window-function-execution.md](window-function-execution.md)，简述：

1. **排序阶段**：按 `PARTITION BY + ORDER BY` 排序（或哈希分区）
2. **分区扫描**：识别每个分区边界
3. **帧计算**：在每行的窗口帧内计算聚合

聚合（GROUP BY）只有阶段 1+2 的简化版（哈希聚合可直接跳过排序）。

### 二者协作的典型查询

```sql
-- 同一查询里聚合 + 分析共存（执行顺序：先 GROUP BY，后窗口）
SELECT department,
       AVG(salary) AS dept_avg,
       AVG(salary) / SUM(AVG(salary)) OVER () AS dept_avg_share
FROM employees
GROUP BY department;

-- 执行步骤:
--   1. GROUP BY department，每组算 AVG(salary)（聚合）
--   2. 对结果集运行窗口函数 SUM(AVG(salary)) OVER ()（分析）
--   3. 计算占比 dept_avg / total

-- 关键认知:
--   分析函数永远在 GROUP BY 之后执行
--   分析函数的输入是 GROUP BY 的输出（已折叠的行）
```

## RATIO_TO_REPORT vs PERCENT_RANK：两个看似相近的占比函数

容易混淆，但语义完全不同。

### RATIO_TO_REPORT —— 数值占比

```sql
-- Oracle / Snowflake / Redshift / Teradata
SELECT employee_id, salary,
       RATIO_TO_REPORT(salary) OVER (PARTITION BY department_id) AS salary_share
FROM employees;

-- 等价 ANSI 写法
SELECT employee_id, salary,
       salary * 1.0 / SUM(salary) OVER (PARTITION BY department_id) AS salary_share
FROM employees;

-- 典型输出（部门 10）:
--   emp 1: salary 10000, share 0.40
--   emp 2: salary 8000,  share 0.32
--   emp 3: salary 7000,  share 0.28
--   合计 share = 1.00
```

语义：当前行的值 / 整个分区的总和。**值的相对大小**，对正负、零值敏感。

### PERCENT_RANK —— 排名百分位

```sql
-- 几乎所有支持窗口的引擎
SELECT employee_id, salary,
       PERCENT_RANK() OVER (PARTITION BY department_id ORDER BY salary) AS pct_rank
FROM employees;

-- 公式: (rank - 1) / (N - 1)，N 为分区行数
-- 第一名: 0.0
-- 最后一名: 1.0
-- 中间按线性插值

-- 典型输出（部门有 5 人）:
--   salary 5000  -> pct_rank 0.00
--   salary 6000  -> pct_rank 0.25
--   salary 7000  -> pct_rank 0.50
--   salary 8000  -> pct_rank 0.75
--   salary 10000 -> pct_rank 1.00
```

语义：当前行的**排名位置**百分位。和原值大小无关，只看顺序。

### 对比表

| 维度 | RATIO_TO_REPORT | PERCENT_RANK |
|------|----------------|--------------|
| 标准 | 非标准（Oracle 起源） | SQL:2003 |
| 含义 | 数值占总和比例 | 排名相对位置 |
| 是否需要 ORDER BY | 否 | 是（必须） |
| 输出范围 | [0, 1]（同号情况） | [0, 1] |
| 总和 | 同一分区合计 = 1.0 | 不为 1（除非 N=2） |
| 对负数 | 受影响（可能为负或大于 1） | 不受影响（只看顺序） |
| 等价聚合写法 | `expr / SUM(expr) OVER ()` | 不存在简洁的聚合写法 |

## FILTER (WHERE ...) 在窗口聚合上的应用

`FILTER (WHERE cond)` 由 SQL:2003 引入（普通聚合），SQL:2011 扩展到窗口聚合，PostgreSQL 12+ 是第一个完整实现。

### 基础用法

```sql
-- PostgreSQL 12+, DuckDB, Trino, SQLite 3.30+
SELECT order_date,
       SUM(amount) FILTER (WHERE status = 'paid') OVER (
           ORDER BY order_date
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ) AS rolling_paid_7d,
       SUM(amount) FILTER (WHERE status = 'refunded') OVER (
           ORDER BY order_date
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ) AS rolling_refund_7d
FROM orders;

-- 一次扫描得到 7 日滑动窗口内"已支付"和"已退款"两个聚合
-- 没有 FILTER 时需要写 SUM(CASE WHEN status = 'paid' THEN amount END) OVER (...)
```

### CASE WHEN 替代方案（适用于不支持 FILTER 的引擎）

```sql
-- Oracle / SQL Server / MySQL / BigQuery / Snowflake 等通用写法
SELECT order_date,
       SUM(CASE WHEN status = 'paid' THEN amount ELSE 0 END) OVER (
           ORDER BY order_date
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ) AS rolling_paid_7d
FROM orders;

-- 注意 NULL 处理差异:
--   FILTER:    NULL 行直接被过滤掉（不参与聚合）
--   CASE ELSE 0: NULL 行参与聚合（贡献 0），COUNT 会失真
--   CASE ELSE NULL: NULL 行参与（贡献 NULL）然后被聚合函数自然忽略，COUNT 正确
```

### COUNT FILTER 的特殊性

```sql
-- COUNT 配合 FILTER 是最常见的模式
SELECT user_id,
       COUNT(*) FILTER (WHERE event_type = 'login') OVER (
           PARTITION BY user_id
           ORDER BY ts
           RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW
       ) AS logins_7d,
       COUNT(*) FILTER (WHERE event_type = 'purchase') OVER (
           PARTITION BY user_id
           ORDER BY ts
           RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW
       ) AS purchases_7d
FROM events;

-- 替代写法（CASE WHEN）：
COUNT(CASE WHEN event_type = 'login' THEN 1 END) OVER (...)
-- 注意：必须省略 ELSE 或用 NULL，否则 COUNT 也会计入 0 值
```

### 引擎特定写法

```sql
-- DuckDB 简洁
SELECT region,
       COUNT(*) FILTER (status = 'success') AS success_count,  -- WHERE 可省略
       COUNT(*) FILTER (status = 'fail') AS fail_count
FROM logs GROUP BY region;

-- Spark SQL: FILTER 在 3.0 起支持聚合，但窗口上的 FILTER 至今部分受限
-- ClickHouse: 用 -If 后缀
SELECT user_id,
       sumIf(amount, status = 'paid') OVER (PARTITION BY user_id) AS paid_total
FROM orders;
```

## 各引擎实现细节

### PostgreSQL（参考实现）

PostgreSQL 是 SQL:2003 窗口函数最完整的开源实现：

```sql
-- 所有内建聚合函数都可加 OVER 变成窗口聚合
SELECT employee_id, salary, hire_date,
       SUM(salary) OVER w AS dept_total,
       AVG(salary) OVER w AS dept_avg,
       COUNT(*) OVER w AS dept_count,
       MIN(salary) OVER w AS dept_min,
       MAX(salary) OVER w AS dept_max,
       STDDEV(salary) OVER w AS dept_stddev,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) OVER (PARTITION BY department_id) AS dept_median
FROM employees
WINDOW w AS (PARTITION BY department_id);

-- 用户自定义聚合也自动可作窗口（除非声明为 hypothetical-set）
CREATE AGGREGATE my_agg(...) (...);
SELECT my_agg(x) OVER (PARTITION BY ...) FROM t;  -- 直接可用

-- FILTER 子句（聚合 9.4+，窗口聚合 12+）
SELECT region,
       SUM(amount) FILTER (WHERE status = 'paid') OVER (PARTITION BY region) AS paid_total
FROM orders;
```

执行计划标记：
- `Aggregate` / `HashAggregate` / `GroupAggregate` —— 聚合（折叠）
- `WindowAgg` —— 分析（不折叠）

### Oracle（分析函数的鼻祖）

Oracle 8i（1999 年）发布了完整的分析函数，**比 SQL:2003 标准早了 4 年**。其设计很大程度上影响了后续标准：

```sql
-- 经典 Oracle 分析函数语法（早于标准）
SELECT employee_id, last_name, salary, department_id,
       RANK() OVER (PARTITION BY department_id ORDER BY salary DESC) AS dept_rank,
       LAG(salary, 1, 0) OVER (PARTITION BY department_id ORDER BY hire_date) AS prev_salary,
       RATIO_TO_REPORT(salary) OVER (PARTITION BY department_id) AS salary_share,
       FIRST_VALUE(salary) OVER (PARTITION BY department_id ORDER BY salary DESC) AS dept_top_salary
FROM employees;

-- Oracle 独有的"假设性"分析函数
SELECT RANK(50000) WITHIN GROUP (ORDER BY salary) AS rank_of_50k
FROM employees;
-- "如果加入一个 salary=50000 的员工，他会排第几名？"

-- KEEP DENSE_RANK FIRST/LAST: 类似 ARG_MIN/ARG_MAX
SELECT department_id,
       MAX(hire_date) KEEP (DENSE_RANK FIRST ORDER BY salary DESC) AS earliest_top_paid_hire
FROM employees
GROUP BY department_id;
-- 每个部门工资最高员工的入职日期
```

### SQL Server（分两阶段引入）

SQL Server 的窗口支持分两个里程碑：

| 版本 | 年份 | 支持的窗口能力 |
|------|------|---------------|
| 2005 | 2005 | 排名函数（ROW_NUMBER/RANK/DENSE_RANK/NTILE） |
| 2012 | 2012 | 窗口聚合 + LAG/LEAD/FIRST_VALUE/LAST_VALUE + 帧（ROWS/RANGE） |
| 2016+ | 2016+ | 性能优化（adaptive memory grants、batch mode 加速） |

```sql
-- SQL Server 2005: 仅排名（无聚合 OVER）
SELECT employee_id, ROW_NUMBER() OVER (ORDER BY hire_date) AS rn
FROM employees;
-- 这条在 2005 就能跑

-- SQL Server 2012+: 加上窗口聚合
SELECT employee_id, salary,
       SUM(salary) OVER (PARTITION BY department_id) AS dept_total,
       LAG(salary) OVER (PARTITION BY department_id ORDER BY hire_date) AS prev_salary
FROM employees;
-- 2012 起合法

-- 注意: SQL Server 不支持 FILTER 子句，需要用 CASE WHEN
SELECT region,
       SUM(CASE WHEN status = 'paid' THEN amount END) OVER (PARTITION BY region) AS paid_total
FROM orders;
```

### MySQL 8.0（迟到 6 年的标准实现）

MySQL 5.7 完全没有窗口函数，是主流引擎里最晚补齐的。8.0（2018）一次性补全：

```sql
-- MySQL 8.0+
SELECT employee_id, salary,
       SUM(salary) OVER (PARTITION BY department_id) AS dept_total,
       ROW_NUMBER() OVER (PARTITION BY department_id ORDER BY salary DESC) AS rn
FROM employees;

-- 5.7 及以下的替代方案 (变量黑魔法)
SET @rn := 0, @prev_dept := NULL;
SELECT employee_id, salary, department_id,
       @rn := IF(@prev_dept = department_id, @rn + 1, 1) AS rn,
       @prev_dept := department_id
FROM employees
ORDER BY department_id, salary DESC;
-- 不可移植、有竞态、官方文档明确说不要依赖
```

8.0 重要限制：
- 不支持 `FILTER` 子句（用 CASE WHEN）
- 默认帧 = `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`
- 用户自定义聚合函数（UDA）不可作窗口

### MariaDB 10.2（早于 MySQL）

MariaDB 在 10.2（2017）就提供了窗口函数，比 MySQL 8.0 早一年。语法兼容标准。

### SQLite 3.25+（轻量但完整）

SQLite 3.25（2018）补齐窗口函数，3.30 加上 `FILTER`：

```sql
-- SQLite 3.25+
SELECT id, score,
       SUM(score) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative
FROM games;

-- SQLite 3.30+ (FILTER)
SELECT user_id,
       COUNT(*) FILTER (WHERE event_type = 'login') OVER (PARTITION BY user_id) AS logins
FROM events;
```

### Snowflake / BigQuery（云数仓的窗口）

```sql
-- Snowflake: 完整支持，含 RATIO_TO_REPORT
SELECT region, product, sales,
       SUM(sales) OVER (PARTITION BY region) AS region_total,
       RATIO_TO_REPORT(sales) OVER (PARTITION BY region) AS region_share,
       PERCENT_RANK() OVER (PARTITION BY region ORDER BY sales) AS pct_rank
FROM sales_data;

-- Snowflake 独有: QUALIFY 子句（在窗口结果上过滤）
SELECT *
FROM employees
QUALIFY ROW_NUMBER() OVER (PARTITION BY department_id ORDER BY salary DESC) <= 3;
-- 取每个部门工资前 3 名

-- BigQuery: 标准实现，无 RATIO_TO_REPORT，无 QUALIFY (2.0 起也支持 QUALIFY)
SELECT region, product, sales,
       SUM(sales) OVER (PARTITION BY region) AS region_total,
       sales / SUM(sales) OVER (PARTITION BY region) AS region_share  -- 手写
FROM sales_data;
```

### ClickHouse（独特的两套窗口实现）

ClickHouse 早期完全没有 SQL 标准窗口函数，21.0 起才正式支持：

```sql
-- ClickHouse 21+: 标准 OVER 语法
SELECT user_id, ts, amount,
       sum(amount) OVER (PARTITION BY user_id ORDER BY ts) AS cumsum
FROM events;

-- ClickHouse 独有: -If 后缀实现 FILTER
SELECT user_id,
       sumIf(amount, status = 'paid') AS paid_total,
       countIf(event_type = 'login') AS logins
FROM events
GROUP BY user_id;
-- sumIf/countIf 等价于 SUM(amount) FILTER (WHERE status = 'paid')

-- ClickHouse 独有: lagInFrame / leadInFrame
SELECT user_id, ts,
       lagInFrame(amount) OVER (PARTITION BY user_id ORDER BY ts) AS prev_amount
FROM events;
-- 注意: 标准的 LAG 在 ClickHouse 中表现略有不同，需用 lagInFrame 才接近 ANSI 语义

-- ClickHouse 不支持 PERCENT_RANK / CUME_DIST，需手写
SELECT user_id, ts, amount,
       (row_number() OVER w - 1) * 1.0 /
           (count() OVER (PARTITION BY user_id) - 1) AS pct_rank
FROM events
WINDOW w AS (PARTITION BY user_id ORDER BY amount);
```

### Spark SQL / Databricks

```sql
-- Spark SQL: 完整窗口 + FILTER 限制
SELECT user_id, ts, amount,
       SUM(amount) OVER (PARTITION BY user_id ORDER BY ts
                          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumsum
FROM events;

-- Spark SQL 3.0+: 聚合上的 FILTER
SELECT region, COUNT(*) FILTER (WHERE status = 'paid') AS paid_count
FROM orders GROUP BY region;

-- 窗口聚合上的 FILTER 在 Spark 中至今受限，建议用 CASE WHEN
```

### Trino / Presto

```sql
-- Trino: 完整 ANSI 窗口 + FILTER
SELECT region,
       SUM(amount) FILTER (WHERE status = 'paid') OVER (PARTITION BY region) AS paid,
       SUM(amount) OVER (PARTITION BY region) AS total
FROM orders;
```

### Teradata（最早的商用窗口实现）

Teradata V2R5（2002 年）就提供了完整的窗口函数支持，与 Oracle 8i 同时代是早期分析数据库的两大代表：

```sql
-- Teradata: 兼容 Oracle 风格
SELECT employee_id, salary,
       SUM(salary) OVER (PARTITION BY department_id ROWS UNBOUNDED PRECEDING) AS cumsum,
       RATIO_TO_REPORT(salary) OVER (PARTITION BY department_id) AS share,
       PERCENT_RANK() OVER (PARTITION BY department_id ORDER BY salary) AS pct_rank
FROM employees;

-- QUALIFY: Teradata 发明的子句（后被 Snowflake/BigQuery 采纳）
SELECT * FROM employees
QUALIFY RANK() OVER (PARTITION BY department_id ORDER BY salary DESC) = 1;
```

### DuckDB（实现最完整的现代引擎）

```sql
-- DuckDB: 标准 + 扩展
SELECT region, product, sales,
       SUM(sales) OVER (PARTITION BY region) AS total,
       SUM(sales) FILTER (WHERE sales > 100) OVER (PARTITION BY region) AS large_total,
       sales / SUM(sales) OVER (PARTITION BY region) AS share
FROM sales_data;

-- DuckDB QUALIFY
SELECT * FROM employees
QUALIFY ROW_NUMBER() OVER (PARTITION BY department_id ORDER BY salary DESC) <= 3;

-- DuckDB 独有: list aggregations 与窗口结合
SELECT user_id, ts,
       LIST(amount) OVER (PARTITION BY user_id ORDER BY ts
                           ROWS BETWEEN 4 PRECEDING AND CURRENT ROW) AS recent_5
FROM events;
```

### 流处理引擎的特殊性（Flink / RisingWave）

流式 OVER 与批处理语义不同：

```sql
-- Flink SQL 流模式: 仅支持 ROWS 帧（不支持 RANGE 数值帧），且 ORDER BY 必须是事件时间
SELECT user_id, ts, amount,
       SUM(amount) OVER (PARTITION BY user_id
                          ORDER BY ts
                          ROWS BETWEEN 9 PRECEDING AND CURRENT ROW) AS rolling_10
FROM order_stream;

-- RisingWave: 增量物化视图风格的窗口
CREATE MATERIALIZED VIEW user_stats AS
SELECT user_id,
       SUM(amount) OVER (PARTITION BY user_id ORDER BY ts) AS cumulative
FROM orders;
-- 流入新数据时，仅增量更新受影响的行
```

## 引擎实现的关键设计点

### 1. 算子分离

主流引擎都将聚合与窗口实现为不同的算子：

```
聚合算子族:
  HashAggregate    -- 哈希分组 (无序输出)
  SortAggregate    -- 已排序输入的流式聚合
  StreamingAggregate -- 流式部分聚合 (用于优化器的 partial agg)

窗口算子族:
  WindowAgg        -- 标准窗口算子
  StreamingWindow  -- 流处理 over watermark
  IndexWindow      -- 利用索引顺序跳过排序
```

### 2. 部分聚合（Partial Aggregation）

聚合可分两阶段：本地部分聚合 + 全局合并。

```sql
-- 单节点
SELECT department, SUM(salary) FROM employees GROUP BY department;
  HashAggregate(department, sum(salary))
    -> Scan(employees)

-- 分布式
SELECT department, SUM(salary) FROM employees GROUP BY department;
  Final HashAggregate(department, sum(partial_sum))
    -> Exchange (hash by department)
       -> Partial HashAggregate(department, sum(salary))
          -> Scan(employees) on each node
```

窗口函数**不能**做这种部分聚合（因为输出行数 = 输入），只能 partition-aware shuffle。

### 3. ORDER BY 与帧的默认行为

很多 bug 来自**不指定帧**：

```sql
-- 默认帧 = RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
SELECT employee_id, salary,
       SUM(salary) OVER (ORDER BY hire_date) AS running_total
FROM employees;
-- 这是 running total（累计和），不是全表 SUM!

-- 想要全表 SUM 必须省略 ORDER BY
SELECT employee_id, salary,
       SUM(salary) OVER () AS total
FROM employees;

-- 或显式声明帧
SELECT employee_id, salary,
       SUM(salary) OVER (ORDER BY hire_date
                          ROWS BETWEEN UNBOUNDED PRECEDING
                                   AND UNBOUNDED FOLLOWING) AS total
FROM employees;
```

### 4. NULL 处理一致性

聚合与窗口的 NULL 行为应保持一致：

| 函数 | 聚合 NULL 行为 | 窗口 NULL 行为 | 是否一致 |
|------|--------------|---------------|---------|
| SUM | 忽略 NULL | 忽略 NULL | 是 |
| AVG | 忽略 NULL | 忽略 NULL | 是 |
| COUNT(*) | 计入 NULL | 计入 NULL | 是 |
| COUNT(col) | 忽略 NULL | 忽略 NULL | 是 |
| MIN/MAX | 忽略 NULL | 忽略 NULL | 是 |
| FIRST_VALUE | 不适用 | 默认包括 NULL | 需 IGNORE NULLS |
| LAG/LEAD | 不适用 | 默认包括 NULL | 需 IGNORE NULLS |

### 5. IGNORE NULLS / RESPECT NULLS

```sql
-- Oracle / DB2 / SQL Server / Snowflake / Redshift
SELECT employee_id, salary,
       LAG(salary IGNORE NULLS, 1) OVER (PARTITION BY department_id ORDER BY hire_date) AS prev_salary
FROM employees;

-- PostgreSQL: 不支持 IGNORE NULLS, 需子查询过滤再 LAG
-- BigQuery: LAG(salary IGNORE NULLS) 支持
-- MySQL 8.0: 不支持 IGNORE NULLS
```

### 6. ROWS vs RANGE 帧的语义陷阱

```sql
-- ROWS: 物理行数
SELECT ts, val,
       SUM(val) OVER (ORDER BY ts ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
FROM events;
-- 当前行 + 前 2 行（如果存在）

-- RANGE: 值范围（必须配合数值/时间型 ORDER BY）
SELECT ts, val,
       SUM(val) OVER (ORDER BY ts RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW)
FROM events;
-- 当前 ts 往前 7 天内的所有行

-- 默认帧 RANGE: 同 ORDER BY 值的所有行视为同一行
-- 如果 ORDER BY 列有重复值，ROWS 与 RANGE 的累计结果不同！
```

## 引擎开发者实现建议

### 1. 算子注册：聚合即窗口

```
设计 1: 复用聚合实现
  - 聚合函数注册时声明: is_windowable = true
  - 窗口算子直接调用聚合的 init/accumulate/merge/finalize 接口
  - 优势: 新增聚合自动支持窗口

设计 2: 分离实现
  - 窗口算子有独立的 incremental update 接口
  - 优势: 可针对滑动窗口实现 O(1) 增量更新
  - 劣势: 重复代码

PostgreSQL 选择设计 1 + 增量优化 (incremental aggregate)
ClickHouse 选择设计 2 (windowFunctions vs aggregateFunctions 分开)
DuckDB 混合设计
```

### 2. 共享排序优化

多个窗口函数若 PARTITION BY + ORDER BY 兼容，应共用一次排序：

```sql
SELECT
    SUM(amount) OVER w1,
    AVG(amount) OVER w1,
    COUNT(*) OVER w1
FROM orders
WINDOW w1 AS (PARTITION BY region ORDER BY ts);

-- 优化: 三个聚合共用一次 (region, ts) 的排序
```

### 3. 增量聚合 vs 全量重算

```
可逆聚合 (SUM/COUNT/AVG):
  滑动窗口: 进入新行 + 离开旧行 = O(1) per row

不可逆聚合 (MIN/MAX/MEDIAN):
  方案 A: 全量重算 = O(W) per row
  方案 B: 单调队列 = O(1) 摊销 (仅固定大小窗口)
  方案 C: 段树 = O(log N) per row
```

### 4. RATIO_TO_REPORT 的实现策略

`RATIO_TO_REPORT(x) OVER (PARTITION BY p)` 等价于：

```
两阶段:
  阶段 1: 全分区扫描 + 计算 SUM(x)
  阶段 2: 再次扫描 + 输出 x / sum

或单阶段（流式）:
  缓存整个分区 -> 算 sum -> 重放分区 -> 输出比率
  内存: O(分区大小)
```

引擎选择：Oracle 用两阶段；Snowflake/Redshift 类似。这就是为什么大分区下 RATIO_TO_REPORT 比单纯的 SUM 慢一倍。

### 5. FILTER 在窗口上的实现

```
方法 A: 内联 CASE WHEN
  SUM(x) FILTER (WHERE cond) -> SUM(CASE WHEN cond THEN x END)
  优势: 复用现有窗口算子
  问题: COUNT(*) FILTER 必须特别处理 (计数 vs 求和)

方法 B: 算子级别 FILTER
  WindowAgg 增加 filter_expr 字段
  在 accumulate 之前评估 filter
  优势: 语义清晰、易优化
  PostgreSQL 12 选择此方案
```

### 6. EXPLAIN 输出建议

清晰区分聚合 vs 窗口：

```
错误示例（用户难以判断）:
  Aggregate
    -> Scan

正确示例（PostgreSQL）:
  WindowAgg                           <- 标记窗口
    Output: ..., sum(amount) OVER w1
    Window: w1 AS (PARTITION BY region ORDER BY ts ROWS UNBOUNDED PRECEDING)
    -> Sort
       Sort Key: region, ts
       -> Seq Scan
```

### 7. 流处理特殊考虑

流处理引擎（Flink/RisingWave/ksqlDB）对窗口的实现有额外约束：

```
1. ORDER BY 必须是事件时间或处理时间
2. 帧通常限制为 ROWS BETWEEN N PRECEDING AND CURRENT ROW
3. 不可乱序触发 (需 watermark)
4. 状态大小 = 分区数 × 帧大小 (内存敏感)
5. 增量计算几乎是必须的 (全量重算不可接受)
```

## 跨引擎兼容性建议

### 编写可移植的窗口查询

```sql
-- 推荐:
1. 显式写出帧 (ROWS BETWEEN ... AND ...) 而非依赖默认
2. 使用 CASE WHEN 替代 FILTER (兼容性最好)
3. 避免 RATIO_TO_REPORT, 用 SUM/SUM 显式计算
4. 不使用 IGNORE NULLS / RESPECT NULLS (PG/MySQL 不支持)
5. 不使用 NTH_VALUE (SQL Server 不支持)
6. 不使用 QUALIFY (仅 Snowflake/BigQuery/Teradata/DuckDB)

-- 通用安全写法:
SELECT
    employee_id, department_id, salary,
    -- 累计和: 跨引擎安全
    SUM(salary) OVER (PARTITION BY department_id
                      ORDER BY hire_date
                      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumsum,
    -- 占比: 用 SUM/SUM
    salary * 1.0 / SUM(salary) OVER (PARTITION BY department_id) AS share,
    -- 排名
    ROW_NUMBER() OVER (PARTITION BY department_id ORDER BY salary DESC) AS rn
FROM employees;
```

### 何时用 GROUP BY，何时用 OVER

| 需求 | 推荐 |
|------|------|
| 只关心每组汇总，不关心明细 | GROUP BY |
| 需要保留明细 + 显示组内汇总 | OVER (PARTITION BY) |
| 计算明细占组的比例 | OVER (PARTITION BY) |
| 求每组前 N 行 | ROW_NUMBER OVER + WHERE rn <= N |
| 求每组的"最后一行" | LAST_VALUE 或 ROW_NUMBER 反向 |
| 累计求和 / 移动平均 | OVER + 帧 |
| 与上一行比较（差值/增长率） | LAG/LEAD |
| 多维聚合（小计 + 总计） | GROUP BY ROLLUP / CUBE / GROUPING SETS |

### 性能直觉

```
GROUP BY (HashAggregate):
  内存: O(组数)
  时间: O(N)
  并行度: 高（按 hash key 分发）

OVER (WindowAgg):
  内存: O(分区大小) 缓冲
  时间: O(N log N) 排序为主
  并行度: 中等（仅按 partition key 分发，分区内串行）

经验法则: 当 GROUP BY 能解决问题时, 优先 GROUP BY
        OVER 总是比 GROUP BY 至少多一次排序
```

## 设计争议

### 标准 vs 历史名称

`SUM(...) OVER ()` 在标准里叫"window aggregate function"，但 Oracle 文档里叫"analytic function"，PostgreSQL 文档里叫"window function"，三者基本同义。

### "聚合包窗口" vs "窗口包聚合"

```sql
-- 不允许：聚合内包窗口
SELECT SUM(SUM(amount) OVER ()) FROM orders;  -- 报错

-- 允许：窗口内包聚合（在 GROUP BY 后）
SELECT region, SUM(amount), SUM(SUM(amount)) OVER ()
FROM orders GROUP BY region;
-- 第三列：所有 region 的 SUM 之和（即全局总和）
```

执行顺序：FROM -> WHERE -> GROUP BY -> 聚合 -> HAVING -> SELECT 中的窗口 -> ORDER BY -> LIMIT。所以窗口函数永远晚于聚合，可以"看到"聚合结果。

### 为什么 MySQL 等到 8.0 才支持？

MySQL 团队历史上对查询执行器投入有限，5.7 之前的引擎设计不支持任意行的"看见前后行"语义。8.0 的窗口实现复用了优化器重写后的迭代器框架，是 MySQL 历史上最大的一次执行器升级之一。

### Apache Derby 至今不支持窗口函数

Derby 是少数几个仍未实现 SQL:2003 窗口函数的"现代"引擎。原因：项目活跃度低、没有商业用户推动。这也使得 Derby 在数据分析场景几乎被弃用。

## 关键发现

1. **聚合函数普及率 100%，窗口函数普及率 ~98%**：48 个引擎中 47 个支持窗口（仅 Apache Derby 没有），但聚合函数（不带 OVER）所有引擎都支持。
2. **SQL:2003 是窗口函数的标准入口**，但 Oracle 8i（1999）早了 4 年，Teradata V2R5（2002）几乎同时实现。事实上是产品先行、标准跟进。
3. **SQL Server 分两步走**：2005 引入排名函数，2012 才补齐窗口聚合。这是少数有"窗口能力分两阶段"的主流引擎。
4. **MySQL 8.0（2018）是主流商用引擎中最晚补齐窗口的**，距离 SQL:2003 标准 15 年。
5. **MariaDB 比 MySQL 早一年**（10.2，2017）支持窗口，是 MariaDB 与 MySQL 分叉后第一个明显的功能领先。
6. **FILTER 子句在窗口聚合上的支持极不均衡**：仅 PG 12+、DuckDB、Trino、SQLite 3.30+、CockroachDB、H2、MonetDB 等支持；Oracle、SQL Server、MySQL、Snowflake、BigQuery 都不支持，必须用 CASE WHEN 替代。
7. **RATIO_TO_REPORT 是 Oracle 8i 留下的非标准函数**，仅 Oracle、Snowflake、Redshift、Teradata、Vertica、SAP HANA 等"传统数仓"支持。所有引擎都可以用 `expr / SUM(expr) OVER (...)` 等价替代。
8. **PERCENT_RANK 和 RATIO_TO_REPORT 只是名字像**：前者是排名占比 (rank-1)/(N-1)，后者是数值占比 expr/SUM(expr)。
9. **执行模型截然不同**：聚合走 HashAggregate（折叠），分析走 WindowAgg（不折叠）。前者支持部分聚合并行，后者只能 partition-aware shuffle。
10. **默认帧的陷阱**：`OVER (ORDER BY ts)` 不指定帧时，默认是 `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`，这是累计和而非全表和。

## 总结对比矩阵

### 关键能力速查

| 能力 | PG | MySQL 8 | Oracle | SQL Server | DB2 | Snowflake | BigQuery | DuckDB | ClickHouse | Spark |
|------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| 基础聚合 | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| 聚合 + OVER | 是 | 是 | 是 | 2012+ | 是 | 是 | 是 | 是 | 21+ | 是 |
| 排名函数 | 是 | 是 | 是 | 2005+ | 是 | 是 | 是 | 是 | 是 | 是 |
| LAG/LEAD | 是 | 是 | 是 | 2012+ | 是 | 是 | 是 | 是 | InFrame | 是 |
| FIRST/LAST_VALUE | 是 | 是 | 是 | 2012+ | 是 | 是 | 是 | 是 | 是 | 是 |
| PERCENT_RANK | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 否 | 是 |
| CUME_DIST | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 否 | 是 |
| RATIO_TO_REPORT | 否 | 否 | 是 | 否 | 否 | 是 | 否 | 否 | 否 | 否 |
| FILTER on agg | 9.4+ | 否 | 否 | 否 | 否 | 否 | 否 | 是 | -If 后缀 | 3.0+ |
| FILTER on window | 12+ | 否 | 否 | 否 | 否 | 否 | 否 | 是 | 否 | 部分 |
| QUALIFY | 否 | 否 | 否 | 否 | 否 | 是 | 是 | 是 | 否 | 否 |
| IGNORE NULLS | 否 | 否 | 是 | 是 | 是 | 是 | 是 | 是 | 否 | 否 |
| 默认帧 | 标准 | 标准 | 标准 | 标准 | 标准 | 标准 | 标准 | 标准 | 标准 | 标准 |

### 引擎选型建议

| 场景 | 推荐 | 原因 |
|------|------|------|
| 复杂窗口分析（HTAP/OLTP） | PostgreSQL / Oracle | 完整 SQL:2003+2016 支持 |
| 云数仓窗口大查询 | Snowflake / BigQuery | 性能好、QUALIFY 简洁 |
| 嵌入式 + 完整窗口 | DuckDB / SQLite 3.30+ | 单机性能、FILTER 完整 |
| 流式 OVER | Flink / RisingWave | 增量计算 + watermark |
| 大宽表 + 占比报告 | Snowflake / Oracle / Vertica | RATIO_TO_REPORT 原生 |
| 兼容老 Oracle 应用 | Oracle / Snowflake / Teradata | 分析函数语义一致 |
| 兼容传统 SQL Server | SQL Server 2012+ / Synapse | 注意 NTH_VALUE 缺失 |

## 参考资料

- SQL:1992 标准: ISO/IEC 9075:1992
- SQL:1999 标准: ISO/IEC 9075-2:1999, GROUPING SETS / CUBE / ROLLUP
- SQL:2003 标准: ISO/IEC 9075-2:2003, Section 6.10 (window function), Section 10.9 (set function), feature T611 (FILTER clause on aggregate)
- SQL:2011 标准: ISO/IEC 9075-2:2011, Window functions enhancements (RANGE/GROUPS, EXCLUDE), FILTER clause on window aggregate
- PostgreSQL: [Window Functions](https://www.postgresql.org/docs/current/tutorial-window.html)
- Oracle: [Analytic Functions](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Analytic-Functions.html)
- SQL Server: [OVER Clause](https://learn.microsoft.com/en-us/sql/t-sql/queries/select-over-clause-transact-sql)
- MySQL 8.0: [Window Functions](https://dev.mysql.com/doc/refman/8.0/en/window-functions.html)
- DB2: [OLAP Functions](https://www.ibm.com/docs/en/db2-for-zos/13?topic=expressions-olap-specification)
- Snowflake: [Window Functions](https://docs.snowflake.com/en/sql-reference/functions-analytic)
- BigQuery: [Window Functions](https://cloud.google.com/bigquery/docs/reference/standard-sql/window-function-calls)
- DuckDB: [Window Functions](https://duckdb.org/docs/sql/window_functions)
- ClickHouse: [Window Functions](https://clickhouse.com/docs/en/sql-reference/window-functions)
- Spark SQL: [Window Functions](https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-window.html)
- Trino: [Window Functions](https://trino.io/docs/current/functions/window.html)
- Teradata: [Ordered Analytical Functions](https://docs.teradata.com/r/Teradata-Database-SQL-Functions-Operators-Expressions-and-Predicates)
- 相关文章: [aggregate-functions-comparison.md](aggregate-functions-comparison.md), [window-function-execution.md](window-function-execution.md)
</content>
</invoke>