# 窗口函数高级语法：各 SQL 方言全对比

> 参考资料:
> - [SQL:2003 Window Functions](https://modern-sql.com/feature/over)
> - [PostgreSQL - Window Functions](https://www.postgresql.org/docs/current/functions-window.html)
> - [MySQL 8.0 - Window Functions](https://dev.mysql.com/doc/refman/8.0/en/window-functions.html)
> - [BigQuery - QUALIFY](https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#qualify_clause)

窗口函数是 SQL 中最强大也最复杂的特性之一。SQL:2003 引入基本窗口函数，SQL:2011 增加了 GROUPS 帧模式、FILTER 子句和 EXCLUDE 选项。但各引擎的实现进度差异巨大——有的引擎已经支持 QUALIFY 等非标准扩展，有的连 GROUPS 都尚未实现。本文对 40+ 引擎的窗口函数高级语法做全面横向对比。

---

## 1. QUALIFY 支持矩阵

QUALIFY 是窗口函数结果的专用过滤子句，在 SQL 执行顺序中位于 HAVING 之后、ORDER BY 之前。它不是 SQL 标准的一部分，但因为 ROI 极高（实现简单、用户价值大）而被越来越多引擎采纳。

### 语法

```sql
-- QUALIFY: 直接过滤窗口函数结果，无需子查询包装
SELECT emp_id, dept_id, salary
FROM employees
QUALIFY ROW_NUMBER() OVER (PARTITION BY dept_id ORDER BY salary DESC) = 1;

-- 等价的传统写法: 必须嵌套子查询
SELECT * FROM (
    SELECT emp_id, dept_id, salary,
        ROW_NUMBER() OVER (PARTITION BY dept_id ORDER BY salary DESC) AS rn
    FROM employees
) t
WHERE rn = 1;
```

### 支持矩阵

| 引擎 | QUALIFY | 版本 | 备注 |
|------|---------|------|------|
| Teradata | ✅ | 早期版本 | **首创者** |
| Snowflake | ✅ | GA | 完整支持 |
| BigQuery | ✅ | GA | 完整支持 |
| DuckDB | ✅ | 0.3.0+ | 完整支持 |
| Databricks | ✅ | Runtime 11.0+ | Databricks 扩展（早于 Spark 3.4 原生支持） |
| StarRocks | ✅ | 2.5+ | 完整支持 |
| ClickHouse | ✅ | 22.7+ | 完整支持 |
| H2 | ✅ | 2.0+ | 完整支持 |
| Spark SQL | ✅ | 3.4+ | 原生支持 |
| MySQL | ❌ | - | 需子查询改写 |
| PostgreSQL | ❌ | - | 需子查询改写 |
| Oracle | ❌ | - | 需子查询改写 |
| SQL Server | ❌ | - | 需子查询改写 |
| SQLite | ❌ | - | 需子查询改写 |
| MariaDB | ❌ | - | 需子查询改写 |
| Trino | ✅ (411+) |
| Db2 | ❌ | - | 需子查询改写 |
| Redshift | ❌ | - | 需子查询改写 |
| SAP HANA | ❌ | - | 需子查询改写 |
| Greenplum | ❌ | - | 需子查询改写 |
| Hive | ❌ | - | 需子查询改写 |
| Flink | ❌ | - | 需子查询改写 |
| CockroachDB | ❌ | - | 需子查询改写 |
| TiDB | ❌ | - | 需子查询改写 |
| OceanBase | ❌ | - | 需子查询改写 |

**趋势**: QUALIFY 的采纳在加速。支持 QUALIFY 的引擎数量已从 2020 年的 3 个（Teradata、Snowflake、BigQuery）增长到 2025 年的 9 个。不支持的引擎需要通过子查询或 CTE 包装来实现等价逻辑。

---

## 2. 命名窗口 WINDOW 子句

WINDOW 子句允许在 SELECT 语句末尾定义命名窗口，多个窗口函数可以复用同一个窗口定义，减少重复并帮助优化器合并排序操作。这是 SQL:2003 标准的一部分。

### 语法

```sql
-- 命名窗口: 定义一次，复用多次
SELECT username, age,
    ROW_NUMBER() OVER w AS rn,
    RANK()       OVER w AS rnk,
    LAG(age)     OVER w AS prev_age,
    SUM(age)     OVER w AS running_sum
FROM users
WINDOW w AS (ORDER BY age);

-- 命名窗口 + 内联扩展: 在引用时追加帧子句
SELECT username, age,
    SUM(age) OVER (w ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum,
    AVG(age) OVER (w ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_avg
FROM users
WINDOW w AS (ORDER BY age);
```

### 支持矩阵

| 引擎 | WINDOW 子句 | 内联扩展 | 版本 |
|------|------------|---------|------|
| PostgreSQL | ✅ | ✅ | 8.4+ |
| MySQL | ✅ | ✅ | 8.0+ |
| MariaDB | ✅ | ✅ | 10.2+ |
| SQLite | ✅ | ✅ | 3.28+ |
| DuckDB | ✅ | ✅ | 0.3.0+ |
| Snowflake | ✅ | ✅ | GA |
| BigQuery | ✅ | ✅ | GA |
| Trino | ✅ | ✅ | 早期版本 |
| Spark SQL | ✅ | ✅ | 3.0+ |
| Databricks | ✅ | ✅ | Runtime 7.0+ |
| Flink | ✅ | ✅ | 1.13+ |
| StarRocks | ✅ | ✅ | GA |
| Hologres | ✅ | ✅ | GA |
| Db2 | ✅ | ✅ | GA |
| CockroachDB | ✅ | ✅ | 20.1+ |
| YugabyteDB | ✅ | ✅ | GA |
| openGauss | ✅ | ✅ | GA |
| KingbaseES | ✅ | ✅ | GA |
| Teradata | ✅ | ✅ | GA |
| Greenplum | ✅ | ✅ | GA |
| Oracle | ❌ | - | - |
| SQL Server | ❌ | - | - |
| Redshift | ❌ | - | - |
| ClickHouse | ❌ | - | - |
| Hive | ❌ | - | - |
| SAP HANA | ❌ | - | - |
| Doris | ❌ | - | - |
| TiDB | ❌ | - | - |
| OceanBase | ✅ | ✅ | GA |
| Impala | ❌ | - | - |

**关键发现**: Oracle 和 SQL Server 作为两大传统 RDBMS 不支持 WINDOW 子句，这意味着面向这些引擎的 SQL 无法使用命名窗口语法。PostgreSQL 系（包括 CockroachDB、YugabyteDB 等衍生引擎）天然支持。

---

## 3. 帧类型: ROWS vs RANGE vs GROUPS

SQL 标准定义了三种窗口帧模式，用于控制"当前行参与计算时，哪些行应该被包含"：

| 帧类型 | 语义 | 引入标准 |
|--------|------|---------|
| ROWS | 按物理行偏移计数 | SQL:2003 |
| RANGE | 按 ORDER BY 列的值范围 | SQL:2003 |
| GROUPS | 按对等组（peer group）计数 | SQL:2011 |

### 三种模式的区别示例

```
数据: score = 80, 80, 85, 85, 85, 90, 95

ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING:
  第1个85 → {80, 85, 85}      -- 物理行: 前1行 + 自己 + 后1行
  第3个85 → {85, 85, 90}      -- 同值行看到不同帧!

RANGE BETWEEN 5 PRECEDING AND 5 FOLLOWING:
  所有85  → {80, 80, 85, 85, 85, 90}  -- 值在 [80, 90] 范围内

GROUPS BETWEEN 1 PRECEDING AND 1 FOLLOWING:
  所有85  → {80, 80, 85, 85, 85, 90}  -- 前1组 + 当前组 + 后1组
```

### 支持矩阵

| 引擎 | ROWS | RANGE | GROUPS | 版本说明 |
|------|------|-------|--------|---------|
| PostgreSQL | ✅ | ✅ | ✅ | GROUPS: 11+ (2018) |
| SQLite | ✅ | ✅ | ✅ | GROUPS: 3.28+ (2019) |
| DuckDB | ✅ | ✅ | ✅ | 0.3.0+ |
| MariaDB | ✅ | ✅ | ✅ | GROUPS: 10.9+ |
| Trino | ✅ | ✅ | ✅ | 最新版本 |
| MySQL | ✅ | ✅ | ❌ | 8.0+ |
| Oracle | ✅ | ✅ | ❌ | 8i+ |
| SQL Server | ✅ | ✅ | ❌ | 2012+ |
| Db2 | ✅ | ✅ | ❌ | GA |
| SAP HANA | ✅ | ✅ | ❌ | GA |
| BigQuery | ✅ | ✅ | ❌ | GA |
| Snowflake | ✅ | 部分 | ❌ | RANGE 限制较多 |
| Redshift | ✅ | ✅ | ❌ | GA |
| Databricks | ✅ | ✅ | ❌ | GA |
| Spark SQL | ✅ | ✅ | ❌ | GA |
| Hive | ✅ | ✅ | ❌ | GA |
| Flink | ✅ | ✅ | ❌ | GA |
| ClickHouse | ✅ | ❌ | ❌ | 21.1+ 仅 ROWS |
| StarRocks | ✅ | ✅ | ❌ | GA |
| Doris | ✅ | ✅ | ❌ | GA |
| TiDB | ✅ | ✅ | ❌ | GA |
| OceanBase | ✅ | ✅ | ❌ | GA |
| CockroachDB | ✅ | ✅ | ❌ | GA |
| Greenplum | ✅ | ✅ | ❌ | GA |
| Teradata | ✅ | ✅ | ❌ | GA |
| Vertica | ✅ | ✅ | ❌ | GA |

**关键发现**: GROUPS 帧模式仅 5 个引擎支持（PostgreSQL、SQLite、DuckDB、MariaDB、Trino）。即便是 Oracle、SQL Server、BigQuery 等主流引擎也未实现。不支持 GROUPS 的引擎可以通过 `DENSE_RANK() + 自连接` 模拟等价语义。

---

## 4. 帧边界

帧边界定义了窗口帧的起止位置。SQL 标准定义了 5 种边界：

```sql
window_function OVER (
    ORDER BY expr
    {ROWS | RANGE | GROUPS} BETWEEN
        {UNBOUNDED PRECEDING | n PRECEDING | CURRENT ROW}
    AND
        {n FOLLOWING | UNBOUNDED FOLLOWING | CURRENT ROW}
)
```

### 各边界类型的语义

| 边界 | 语义 |
|------|------|
| `UNBOUNDED PRECEDING` | 分区的第一行 |
| `n PRECEDING` | 当前行/值/组之前的第 n 个 |
| `CURRENT ROW` | 当前行（ROWS）或当前对等组（RANGE/GROUPS） |
| `n FOLLOWING` | 当前行/值/组之后的第 n 个 |
| `UNBOUNDED FOLLOWING` | 分区的最后一行 |

### 默认帧行为

当指定了 ORDER BY 但未指定帧子句时，默认帧为：

```sql
RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
```

这是 LAST_VALUE 经典陷阱的根源——`LAST_VALUE(x) OVER (ORDER BY y)` 返回的是"当前行的值"而不是"分区最后一行的值"。

### 支持差异

| 引擎 | UNBOUNDED PRECEDING/FOLLOWING | n PRECEDING/FOLLOWING | CURRENT ROW | RANGE + INTERVAL |
|------|------|------|------|------|
| PostgreSQL | ✅ | ✅ | ✅ | ✅ |
| MySQL | ✅ | ✅ | ✅ | ❌ |
| Oracle | ✅ | ✅ | ✅ | ✅ |
| SQL Server | ✅ | ✅ | ✅ | ⚠️ 2022+ |
| SQLite | ✅ | ✅ | ✅ | ❌ |
| MariaDB | ✅ | ✅ | ✅ | ❌ |
| BigQuery | ✅ | ✅ | ✅ | ⚠️ 需类型转换 |
| Snowflake | ✅ | ✅ | ✅ | ⚠️ 需类型转换 |
| DuckDB | ✅ | ✅ | ✅ | ✅ |
| Db2 | ✅ | ✅ | ✅ | ✅ |
| SAP HANA | ✅ | ✅ | ✅ | ✅ |
| ClickHouse | ✅ | ✅ | ✅ | ❌ |
| Trino | ✅ | ✅ | ✅ | ❌ |
| Spark SQL | ✅ | ✅ | ✅ | ❌ |
| Hive | ✅ | ✅ | ✅ | ❌ |
| Redshift | ✅ | ✅ | ✅ | ❌ |
| Teradata | ✅ | ✅ | ✅ | ✅ |
| Vertica | ✅ | ✅ | ✅ | ✅ |

基本帧边界（UNBOUNDED、n PRECEDING/FOLLOWING、CURRENT ROW）各引擎一致支持。主要差异在 **RANGE + INTERVAL** 语法（如 `RANGE BETWEEN INTERVAL '7' DAY PRECEDING AND CURRENT ROW`），仅 PostgreSQL、Oracle、Db2、DuckDB、SAP HANA、Teradata、Vertica 原生支持。

---

## 5. 窗口函数完整列表对比

### 排名与分布函数

| 函数 | SQL 标准 | MySQL | PostgreSQL | Oracle | SQL Server | SQLite | BigQuery | Snowflake | DuckDB |
|------|---------|-------|-----------|--------|-----------|--------|---------|-----------|--------|
| ROW_NUMBER | SQL:2003 | ✅ 8.0+ | ✅ | ✅ 8i+ | ✅ 2005+ | ✅ 3.25+ | ✅ | ✅ | ✅ |
| RANK | SQL:2003 | ✅ 8.0+ | ✅ | ✅ | ✅ | ✅ 3.25+ | ✅ | ✅ | ✅ |
| DENSE_RANK | SQL:2003 | ✅ 8.0+ | ✅ | ✅ | ✅ | ✅ 3.25+ | ✅ | ✅ | ✅ |
| NTILE | SQL:2003 | ✅ 8.0+ | ✅ | ✅ | ✅ | ✅ 3.25+ | ✅ | ✅ | ✅ |
| PERCENT_RANK | SQL:2003 | ✅ 8.0+ | ✅ | ✅ | ✅ | ✅ 3.25+ | ✅ | ✅ | ✅ |
| CUME_DIST | SQL:2003 | ✅ 8.0+ | ✅ | ✅ | ✅ | ✅ 3.25+ | ✅ | ✅ | ✅ |

排名函数是窗口函数中支持最广泛的类别，上述 6 个函数在所有支持窗口函数的主流引擎中均可用。

### 偏移函数

| 函数 | SQL 标准 | MySQL | PostgreSQL | Oracle | SQL Server | SQLite | BigQuery | Snowflake | DuckDB |
|------|---------|-------|-----------|--------|-----------|--------|---------|-----------|--------|
| LAG | SQL:2003 | ✅ 8.0+ | ✅ | ✅ | ✅ 2012+ | ✅ 3.25+ | ✅ | ✅ | ✅ |
| LEAD | SQL:2003 | ✅ 8.0+ | ✅ | ✅ | ✅ 2012+ | ✅ 3.25+ | ✅ | ✅ | ✅ |
| FIRST_VALUE | SQL:2003 | ✅ 8.0+ | ✅ | ✅ | ✅ 2012+ | ✅ 3.25+ | ✅ | ✅ | ✅ |
| LAST_VALUE | SQL:2003 | ✅ 8.0+ | ✅ | ✅ | ✅ 2012+ | ✅ 3.25+ | ✅ | ✅ | ✅ |
| NTH_VALUE | SQL:2003 | ✅ 8.0+ | ✅ | ✅ | ❌ | ✅ 3.25+ | ✅ | ✅ | ✅ |

NTH_VALUE 的兼容性差异最大：

| 引擎 | NTH_VALUE |
|------|-----------|
| SQL Server | ❌ 不支持（需用 ROW_NUMBER 子查询模拟） |
| Firebird | ❌ |
| Hive | ❌ |
| ClickHouse | ❌ |
| StarRocks | ❌ |
| Doris | ❌ |
| Derby | ❌ |

### 大数据引擎补充对比

| 函数 | Hive | ClickHouse | Spark | Flink | Trino | StarRocks | Doris |
|------|------|-----------|-------|-------|-------|-----------|-------|
| ROW_NUMBER | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| RANK / DENSE_RANK | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| NTILE | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| LAG / LEAD | ✅ | ⚠️ | ✅ | ✅ | ✅ | ✅ | ✅ |
| FIRST_VALUE / LAST_VALUE | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| NTH_VALUE | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ |

ClickHouse 的 LAG/LEAD 使用 `lagInFrame`/`leadInFrame` 替代名称，语义与标准略有不同（基于帧而非分区）。

### IGNORE NULLS 支持

`IGNORE NULLS` 修饰符可用于 FIRST_VALUE、LAST_VALUE、LAG、LEAD，跳过 NULL 值：

```sql
-- 取每个分区中第一个非 NULL 的值
FIRST_VALUE(col IGNORE NULLS) OVER (PARTITION BY grp ORDER BY id)
```

| 引擎 | IGNORE NULLS |
|------|-------------|
| Oracle | ✅ |
| SQL Server | ✅ 2012+ |
| BigQuery | ✅ |
| Snowflake | ✅ |
| Db2 | ✅ |
| Teradata | ✅ |
| DuckDB | ✅ |
| Trino | ✅ |
| Databricks | ✅ |
| Redshift | ✅ |
| MySQL | ❌ |
| PostgreSQL | ❌ |
| SQLite | ❌ |
| MariaDB | ❌ |
| Hive | ❌ |
| ClickHouse | ❌ |
| Flink | ❌ |

---

## 6. EXCLUDE 子句

SQL:2011 引入了帧排除选项，在帧计算后从结果中排除特定行。

### 语法

```sql
window_function OVER (
    ORDER BY expr
    ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING
    EXCLUDE { CURRENT ROW | GROUP | TIES | NO OTHERS }
)
```

| 排除选项 | 语义 |
|---------|------|
| `EXCLUDE NO OTHERS` | 不排除任何行（默认） |
| `EXCLUDE CURRENT ROW` | 排除当前行 |
| `EXCLUDE GROUP` | 排除当前行及所有与当前行 ORDER BY 值相等的行 |
| `EXCLUDE TIES` | 排除与当前行同值的其他行，但保留当前行本身 |

### 示例

```sql
-- 计算"排除自己之后的组内平均值"
SELECT student, score,
    AVG(score) OVER (
        ORDER BY score
        ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING
        EXCLUDE CURRENT ROW
    ) AS avg_without_self
FROM scores;
```

### 支持矩阵

| 引擎 | EXCLUDE CURRENT ROW | EXCLUDE GROUP | EXCLUDE TIES | 版本 |
|------|-------------------|--------------|-------------|------|
| PostgreSQL | ✅ | ✅ | ✅ | 11+ |
| SQLite | ✅ | ✅ | ✅ | 3.28+ |
| DuckDB | ✅ | ✅ | ✅ | 0.3.0+ |
| MySQL | ❌ | ❌ | ❌ | - |
| MariaDB | ❌ | ❌ | ❌ | - |
| Oracle | ❌ | ❌ | ❌ | - |
| SQL Server | ❌ | ❌ | ❌ | - |
| BigQuery | ❌ | ❌ | ❌ | - |
| Snowflake | ❌ | ❌ | ❌ | - |
| ClickHouse | ❌ | ❌ | ❌ | - |
| Trino | ✅ (411+) | ❌ | ❌ | - |
| Spark SQL | ❌ | ❌ | ❌ | - |
| Databricks | ❌ | ❌ | ❌ | - |
| Hive | ❌ | ❌ | ❌ | - |
| Db2 | ❌ | ❌ | ❌ | - |
| Redshift | ❌ | ❌ | ❌ | - |
| Teradata | ❌ | ❌ | ❌ | - |

**关键发现**: EXCLUDE 子句是窗口函数中支持率最低的特性，全行业仅 3 个引擎支持（PostgreSQL、SQLite、DuckDB）。不支持的引擎需要通过自连接或子查询手动排除行。

### 不支持引擎的替代方案

```sql
-- 模拟 EXCLUDE CURRENT ROW:
-- 用 SUM 减去当前行的值
SELECT student, score,
    (SUM(score) OVER w - score) / NULLIF(COUNT(*) OVER w - 1, 0) AS avg_without_self
FROM scores
WINDOW w AS (ORDER BY score ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING);

-- 如果不支持 WINDOW 子句 (Oracle/SQL Server):
SELECT student, score,
    (SUM(score) OVER (ORDER BY score ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) - score)
    / NULLIF(COUNT(*) OVER (ORDER BY score ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) - 1, 0)
    AS avg_without_self
FROM scores;
```

---

## 7. FILTER 子句

FILTER 是 SQL:2003 标准定义的聚合函数条件过滤语法。它也可以与窗口聚合函数结合使用。

### 语法

```sql
-- FILTER 与窗口函数结合
SELECT city,
    COUNT(*) FILTER (WHERE age < 30) OVER () AS young_count,
    COUNT(*) FILTER (WHERE age >= 30) OVER () AS senior_count,
    SUM(salary) FILTER (WHERE dept = 'eng') OVER (ORDER BY hire_date) AS eng_running_sum
FROM employees;

-- 等价的 CASE WHEN 写法
SELECT city,
    COUNT(CASE WHEN age < 30 THEN 1 END) OVER () AS young_count,
    COUNT(CASE WHEN age >= 30 THEN 1 END) OVER () AS senior_count,
    SUM(CASE WHEN dept = 'eng' THEN salary END) OVER (ORDER BY hire_date) AS eng_running_sum
FROM employees;
```

### 支持矩阵

| 引擎 | FILTER (聚合) | FILTER (窗口聚合) | 版本 | 替代方案 |
|------|-------------|----------------|------|---------|
| PostgreSQL | ✅ | ✅ | 9.4+ | - |
| SQLite | ✅ | ✅ | 3.30+ | - |
| DuckDB | ✅ | ✅ | 0.3.0+ | - |
| CockroachDB | ✅ | ✅ | 20.1+ | - |
| Spark SQL | ✅ | ✅ | 3.0+ | - |
| Databricks | ✅ | ✅ | Runtime 7.0+ | - |
| H2 | ✅ | ✅ | 2.0+ | - |
| Trino | ✅ | ✅ | 早期版本 | - |
| MySQL | ❌ | ❌ | - | CASE WHEN |
| MariaDB | ❌ | ❌ | - | CASE WHEN |
| Oracle | ❌ | ❌ | - | CASE WHEN |
| SQL Server | ❌ | ❌ | - | CASE WHEN |
| Snowflake | ❌ | ❌ | - | IFF / CASE WHEN |
| BigQuery | ❌ | ❌ | - | IF / COUNTIF |
| ClickHouse | ❌ | ❌ | - | `countIf`/`sumIf` 后缀函数 |
| Hive | ❌ | ❌ | - | CASE WHEN |
| Redshift | ❌ | ❌ | - | CASE WHEN |
| Db2 | ❌ | ❌ | - | CASE WHEN |
| Teradata | ❌ | ❌ | - | CASE WHEN |
| StarRocks | ❌ | ❌ | - | CASE WHEN |
| Doris | ❌ | ❌ | - | CASE WHEN |
| Flink | ❌ | ❌ | - | CASE WHEN |

**关键发现**: FILTER 子句虽然是 SQL 标准的一部分，但仅约 1/3 的主流引擎支持。ClickHouse 提供了独特的替代方案——带条件后缀的聚合函数（如 `countIf(expr, cond)`），功能等价但语法不同。BigQuery 的 `COUNTIF` 函数也是类似的思路。

---

## 8. 综合特性矩阵

将所有高级窗口函数特性汇总为一张表，方便快速查阅：

### 传统 RDBMS

| 特性 | PostgreSQL | MySQL | Oracle | SQL Server | SQLite | MariaDB | Db2 | Firebird |
|------|-----------|-------|--------|-----------|--------|---------|-----|---------|
| QUALIFY | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| WINDOW 子句 | ✅ | ✅ 8.0+ | ❌ | ❌ | ✅ 3.28+ | ✅ 10.2+ | ✅ | ❌ |
| GROUPS 帧 | ✅ 11+ | ❌ | ❌ | ❌ | ✅ 3.28+ | ✅ 10.9+ | ❌ | ❌ |
| EXCLUDE | ✅ 11+ | ❌ | ❌ | ❌ | ✅ 3.28+ | ❌ | ❌ | ❌ |
| FILTER (窗口) | ✅ 9.4+ | ❌ | ❌ | ❌ | ✅ 3.30+ | ❌ | ❌ | ❌ |
| NTH_VALUE | ✅ | ✅ 8.0+ | ✅ | ❌ | ✅ 3.25+ | ✅ 10.2+ | ✅ | ❌ |
| IGNORE NULLS | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | DuckDB | ClickHouse | Trino | Spark | Flink | Hive |
|------|---------|-----------|--------|-----------|-------|-------|-------|------|
| QUALIFY | ✅ | ✅ | ✅ | ✅ 22.7+ | ❌ | ✅ 3.4+ | ❌ | ❌ |
| WINDOW 子句 | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ |
| GROUPS 帧 | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ |
| EXCLUDE | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| FILTER (窗口) | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ | ❌ | ❌ |
| NTH_VALUE | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ |
| IGNORE NULLS | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Teradata | Vertica |
|------|---------|---------|-----------|-----------|---------|---------|
| QUALIFY | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ |
| WINDOW 子句 | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ |
| GROUPS 帧 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| EXCLUDE | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| FILTER (窗口) | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| NTH_VALUE | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ |
| IGNORE NULLS | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | YugabyteDB | Spanner | PolarDB |
|------|------|----------|------------|-----------|---------|---------|
| QUALIFY | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| WINDOW 子句 | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ |
| GROUPS 帧 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| EXCLUDE | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| FILTER (窗口) | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| NTH_VALUE | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| IGNORE NULLS | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

---

## 9. 对引擎开发者的建议

### 优先级排序

基于实现复杂度和用户价值，推荐以下实现顺序：

| 优先级 | 特性 | 实现复杂度 | 用户价值 | 理由 |
|--------|------|----------|---------|------|
| P0 | 基础窗口函数 | 中 | 极高 | ROW_NUMBER/RANK/LAG/LEAD 是必备特性 |
| P1 | QUALIFY | 低 | 高 | 在 HAVING 之后增加一个过滤步骤即可，ROI 最高的语法扩展 |
| P1 | WINDOW 子句 | 低 | 中 | 语法糖，帮助优化器合并排序 |
| P2 | FILTER 子句 | 低 | 中 | 替代 CASE WHEN，优化器更容易处理 |
| P2 | IGNORE NULLS | 中 | 高 | 偏移函数的重要修饰符，避免用户写复杂的 NULL 处理逻辑 |
| P3 | GROUPS 帧 | 中 | 低 | 使用场景较窄，可用 DENSE_RANK + 自连接替代 |
| P3 | EXCLUDE 子句 | 中 | 低 | 使用场景很窄，可用算术运算替代 |

### 实现要点

**QUALIFY 实现**:
- 在查询执行管道中，HAVING 之后增加一个过滤节点
- 语义等价于在子查询外层加 WHERE，但避免了额外的 projection 和物化
- 注意: QUALIFY 中可以引用 SELECT 列表中的别名（Snowflake/BigQuery 行为）

**WINDOW 子句实现**:
- Parser 层面: 在 SELECT 语句的 grammar 中增加可选的 WINDOW 子句
- 优化器层面: 引用同一个命名窗口的多个窗口函数可以共享排序
- 需要处理内联扩展（如 `OVER (w ROWS ...)` 在命名窗口 `w` 基础上追加帧子句）

**GROUPS 帧实现**:
- 核心是维护对等组（peer group）边界
- 推荐预计算组边界数组: 排序后扫描一遍，记录每组的起止位置
- 可与 ROWS/RANGE 共享帧计算基础设施，只在边界确定逻辑上不同

**EXCLUDE 子句实现**:
- 在帧计算之后做行过滤
- EXCLUDE GROUP 和 EXCLUDE TIES 共享组边界检测逻辑，区别仅在于是否保留当前行

### 兼容性路线选择

| 兼容目标 | 推荐实现范围 |
|---------|------------|
| PostgreSQL 兼容 | WINDOW + GROUPS + EXCLUDE + FILTER (PostgreSQL 11+ 全部支持) |
| MySQL 兼容 | WINDOW (MySQL 8.0+ 支持)，其他特性可选 |
| Snowflake/BigQuery 兼容 | QUALIFY + WINDOW + IGNORE NULLS |
| SQL 标准完整实现 | 全部特性 (SQL:2003 + SQL:2011) |

---

## 参考资料

- SQL:2003 标准: ISO/IEC 9075-2:2003 Section 7.11 `<window clause>`
- SQL:2011 标准: ISO/IEC 9075-2:2011 新增 GROUPS 帧模式和 EXCLUDE 子句
- Modern SQL: [Window Functions](https://modern-sql.com/feature/over-and-partition-by)
- 本仓库: [`query/window-functions/_comparison.md`](../../query/window-functions/_comparison.md)
- 本仓库: [`scenarios/window-analytics/_comparison.md`](../../scenarios/window-analytics/_comparison.md)
- 本仓库: [`docs/modern-sql-features/qualify.md`](qualify.md)
- 本仓库: [`docs/modern-sql-features/filter-clause.md`](filter-clause.md)
- 本仓库: [`docs/modern-sql-features/window-frame-groups.md`](window-frame-groups.md)
