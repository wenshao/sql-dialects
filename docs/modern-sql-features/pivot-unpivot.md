# PIVOT/UNPIVOT 行列转换

行列转换（Row-to-Column / Column-to-Row Transformation）是 SQL 中最常见的数据重塑操作之一。
本文系统对比 45+ 方言在原生 PIVOT/UNPIVOT、手动模拟、动态列扩展等方面的实现差异，面向引擎开发者。

---

## 目录

1. [核心概念](#核心概念)
2. [方言支持总矩阵](#方言支持总矩阵)
3. [PIVOT 语法对比](#pivot-语法对比)
4. [UNPIVOT 语法对比](#unpivot-语法对比)
5. [CASE WHEN + GROUP BY 手动 PIVOT（万能回退方案）](#case-when--group-by-手动-pivot万能回退方案)
6. [PostgreSQL CROSSTAB 扩展](#postgresql-crosstab-扩展)
7. [动态 PIVOT（列数未知）](#动态-pivot列数未知)
8. [多聚合 PIVOT](#多聚合-pivot)
9. [LATERAL + VALUES 实现 UNPIVOT](#lateral--values-实现-unpivot)
10. [Spark/Hive STACK() 实现 UNPIVOT](#sparkhive-stack-实现-unpivot)
11. [CROSS JOIN + UNNEST 作为 UNPIVOT 替代](#cross-join--unnest-作为-unpivot-替代)
12. [PIVOT 子查询动态列](#pivot-子查询动态列)
13. [对引擎开发者的实现建议](#对引擎开发者的实现建议)
14. [参考资料](#参考资料)

---

## 核心概念

### PIVOT: 行转列

将窄表（many rows, few columns）转为宽表（few rows, many columns），通常伴随聚合。

```
-- 原始数据（窄 / 行格式）
| year | quarter | revenue |
|------|---------|---------|
| 2024 | Q1      | 100     |
| 2024 | Q2      | 150     |
| 2024 | Q3      | 200     |
| 2024 | Q4      | 180     |
| 2025 | Q1      | 120     |

-- 期望结果（宽 / 列格式）
| year | Q1  | Q2  | Q3  | Q4  |
|------|-----|-----|-----|-----|
| 2024 | 100 | 150 | 200 | 180 |
| 2025 | 120 | NULL| NULL| NULL|
```

### UNPIVOT: 列转行

将宽表恢复为窄表——多列"融化"（melt）为行。是 PIVOT 的逆操作。

```
-- 输入（宽表）
| year | Q1  | Q2  | Q3  | Q4  |
|------|-----|-----|-----|-----|
| 2024 | 100 | 150 | 200 | 180 |

-- 输出（窄表）
| year | quarter | revenue |
|------|---------|---------|
| 2024 | Q1      | 100     |
| 2024 | Q2      | 150     |
| 2024 | Q3      | 200     |
| 2024 | Q4      | 180     |
```

---

## 方言支持总矩阵

### PIVOT 支持

| 引擎 | 原生 PIVOT | 动态 PIVOT | 多聚合 PIVOT | 首次支持版本 |
|------|-----------|-----------|-------------|------------|
| SQL Server | 支持 | 不支持（需动态 SQL） | 不支持（单聚合） | 2005 |
| Oracle | 支持 | 不支持（需动态 SQL） | **支持** | 11g (2007) |
| Snowflake | 支持 | **支持 (PIVOT ANY)** | 不支持 | GA |
| BigQuery | 支持 | 不支持 | **支持** | GA |
| DuckDB | 支持 | **支持（自动检测）** | **支持** | 0.8.0+ |
| Databricks | 支持 | 部分支持 | 不支持 | Runtime 11.0+ |
| Spark SQL | 支持 | 不支持 | 不支持 | 2.4+ |
| PostgreSQL | 不支持 | - | - | 用 crosstab / FILTER |
| MySQL | 不支持 | - | - | 用 CASE WHEN |
| MariaDB | 不支持 | - | - | 用 CASE WHEN |
| TiDB | 不支持 | - | - | 用 CASE WHEN |
| OceanBase (MySQL) | 不支持 | - | - | 用 CASE WHEN |
| OceanBase (Oracle) | 支持 | 不支持 | 支持 | Oracle 兼容模式 |
| Trino | 不支持 | - | - | 用 CASE WHEN |
| Presto | 不支持 | - | - | 用 CASE WHEN |
| ClickHouse | 不支持 | - | - | 用 CASE WHEN / 数组函数 |
| SQLite | 不支持 | - | - | 用 CASE WHEN |
| CockroachDB | 不支持 | - | - | 用 CASE WHEN |
| YugabyteDB | 不支持 | - | - | 用 crosstab（兼容 PG） |
| Redshift | 不支持 | - | - | 用 CASE WHEN（无 crosstab） |
| Hive | 不支持 | - | - | 用 CASE WHEN |
| Greenplum | 不支持 | - | - | 用 crosstab（兼容 PG） |
| SingleStore (MemSQL) | 不支持 | - | - | 用 CASE WHEN |
| Vertica | 不支持 | - | - | 用 CASE WHEN |
| Teradata | 不支持 | - | - | 用 CASE WHEN |
| Exasol | 不支持 | - | - | 用 CASE WHEN |
| SAP HANA | 不支持 | - | - | 用 CASE WHEN / MAP() |
| Informix | 不支持 | - | - | 用 CASE WHEN |
| DB2 | 不支持 | - | - | 用 CASE WHEN / DECODE |
| Firebird | 不支持 | - | - | 用 CASE WHEN |
| H2 | 不支持 | - | - | 用 CASE WHEN |
| HSQLDB | 不支持 | - | - | 用 CASE WHEN |
| Derby | 不支持 | - | - | 用 CASE WHEN |
| MonetDB | 不支持 | - | - | 用 CASE WHEN |
| QuestDB | 不支持 | - | - | 用 CASE WHEN |
| TimescaleDB | 不支持 | - | - | 用 crosstab（兼容 PG） |
| CrateDB | 不支持 | - | - | 用 CASE WHEN |
| StarRocks | 不支持 | - | - | 用 CASE WHEN |
| Doris | 不支持 | - | - | 用 CASE WHEN |
| MatrixOne | 不支持 | - | - | 用 CASE WHEN |
| Firebolt | 不支持 | - | - | 用 CASE WHEN |
| Yellowbrick | 不支持 | - | - | 用 CASE WHEN |
| HEAVY.AI (OmniSci) | 不支持 | - | - | 用 CASE WHEN |
| DuckDB (旧版 <0.8) | 不支持 | - | - | 用 CASE WHEN |

### UNPIVOT 支持

| 引擎 | 原生 UNPIVOT | INCLUDE NULLS | 多列 UNPIVOT | 替代方案 |
|------|-------------|---------------|-------------|---------|
| SQL Server | 支持 (2005+) | 不支持 | 不支持 | CROSS APPLY + VALUES |
| Oracle | 支持 (11g+) | **支持** | **支持** | - |
| Snowflake | 支持 | **支持** | 不支持 | LATERAL FLATTEN |
| BigQuery | 支持 | **支持** | **支持** | CROSS JOIN + UNNEST |
| DuckDB | 支持 (0.8+) | 不支持 | 支持 | COLUMNS(*) 语法 |
| Databricks | 支持 (11.0+) | 不支持 | 支持 | LATERAL VIEW + STACK |
| Spark SQL | 支持 (3.4+) | 不支持 | 支持 | STACK() |
| PostgreSQL | 不支持 | - | - | LATERAL + VALUES |
| MySQL | 不支持 | - | - | UNION ALL |
| Trino | 不支持 | - | - | CROSS JOIN + UNNEST |
| ClickHouse | 不支持 | - | - | arrayJoin + 数组 |
| Hive | 不支持 | - | - | LATERAL VIEW + STACK |
| Redshift | 不支持 | - | - | UNION ALL |
| SQLite | 不支持 | - | - | UNION ALL |
| MariaDB | 不支持 | - | - | UNION ALL |
| CockroachDB | 不支持 | - | - | LATERAL + VALUES |
| TiDB | 不支持 | - | - | UNION ALL |
| Greenplum | 不支持 | - | - | LATERAL + VALUES |
| Vertica | 不支持 | - | - | UNION ALL |
| Teradata | 不支持 | - | - | UNION ALL |
| StarRocks | 不支持 | - | - | UNION ALL |
| Doris | 不支持 | - | - | UNION ALL |

---

## PIVOT 语法对比

### SQL Server

SQL Server 2005 首次引入 PIVOT，语法置于 FROM 子句中：

```sql
-- 基本 PIVOT
SELECT year, [Q1], [Q2], [Q3], [Q4]
FROM sales
PIVOT (
    SUM(revenue)
    FOR quarter IN ([Q1], [Q2], [Q3], [Q4])
) AS pvt;
```

**关键特征**:
- 值列表必须用方括号 `[]` 引用（T-SQL 标识符引用风格）
- 只允许 **一个聚合函数**，不支持多聚合
- 隐式 GROUP BY：所有未出现在 PIVOT 定义中的列自动成为分组列
- 必须提供别名（`AS pvt`）

**隐式 GROUP BY 的陷阱**: 如果原表有多余列，PIVOT 会按所有非 PIVOT 列分组，导致结果不符预期。最佳实践是先用子查询/CTE 筛选需要的列：

```sql
-- 推荐写法: 先限定列
SELECT year, [Q1], [Q2], [Q3], [Q4]
FROM (
    SELECT year, quarter, revenue FROM sales  -- 只取需要的列
) AS src
PIVOT (
    SUM(revenue)
    FOR quarter IN ([Q1], [Q2], [Q3], [Q4])
) AS pvt;
```

### Oracle

Oracle 11g (2007) 引入 PIVOT，支持多聚合和 XML PIVOT：

```sql
-- 基本 PIVOT
SELECT *
FROM (SELECT year, quarter, revenue FROM sales)
PIVOT (
    SUM(revenue)
    FOR quarter IN ('Q1' AS Q1, 'Q2' AS Q2, 'Q3' AS Q3, 'Q4' AS Q4)
);

-- 多聚合 PIVOT
SELECT *
FROM (SELECT year, quarter, revenue FROM sales)
PIVOT (
    SUM(revenue) AS total_rev,
    COUNT(*) AS cnt
    FOR quarter IN ('Q1' AS Q1, 'Q2' AS Q2)
);
-- 产出列: Q1_TOTAL_REV, Q1_CNT, Q2_TOTAL_REV, Q2_CNT

-- XML PIVOT（动态列变体，返回 XML 而非关系列）
SELECT *
FROM sales
PIVOT XML (
    SUM(revenue)
    FOR quarter IN (ANY)
);
-- FOR ... IN (ANY) 仅在 XML PIVOT 中有效
-- 返回一列 XML，包含所有不同值的聚合结果
```

**Oracle 特有**:
- IN 子句中的值使用字符串字面量 `'Q1'`，可通过 `AS` 指定列别名
- 支持 `PIVOT XML` 实现半动态 PIVOT
- 多聚合输出列名格式: `<pivot_value>_<agg_alias>`

### Snowflake (PIVOT ANY)

Snowflake 实现了目前最先进的动态 PIVOT：

```sql
-- 基本 PIVOT
SELECT *
FROM sales
PIVOT (
    SUM(revenue)
    FOR quarter IN ('Q1', 'Q2', 'Q3', 'Q4')
) AS pvt;

-- PIVOT ANY: 自动发现所有不同值（Snowflake 独有关键字）
SELECT *
FROM sales
PIVOT (
    SUM(revenue)
    FOR quarter IN (ANY)
) AS pvt;

-- PIVOT ANY + ORDER BY: 控制列顺序
SELECT *
FROM sales
PIVOT (
    SUM(revenue)
    FOR quarter IN (ANY ORDER BY quarter)
) AS pvt;

-- PIVOT ANY + 子查询过滤值
SELECT *
FROM sales
PIVOT (
    SUM(revenue)
    FOR quarter IN (SELECT DISTINCT quarter FROM sales WHERE year = 2024)
) AS pvt;
```

`PIVOT ANY` 的意义: 解决了动态 PIVOT 的核心痛点——不需要提前知道有哪些值。引擎在编译阶段自动执行值发现查询。

### DuckDB

DuckDB 提供了最简洁的 PIVOT 语法，同时兼容标准写法：

```sql
-- DuckDB 简洁语法（推荐）
PIVOT sales ON quarter USING SUM(revenue) GROUP BY year;
-- 自动检测 quarter 的所有不同值

-- 等效标准兼容语法
SELECT * FROM sales
PIVOT (SUM(revenue) FOR quarter IN ('Q1', 'Q2', 'Q3', 'Q4'));

-- 多聚合
PIVOT sales ON quarter USING SUM(revenue) AS total, COUNT(*) AS cnt GROUP BY year;
-- 产出: Q1_total, Q1_cnt, Q2_total, Q2_cnt, ...

-- PIVOT 作为独立语句（非子句）
PIVOT sales ON quarter USING SUM(revenue);
-- DuckDB 允许 PIVOT 作为顶层语句，不需要 SELECT * FROM ... PIVOT ...
```

**DuckDB 特色**:
- `PIVOT ... ON col` 语法天然支持自动值发现，无需 IN 列表
- 支持 `COLUMNS(*)` 表达式进行批量列操作
- PIVOT 可作为独立 DML 语句使用

### BigQuery

```sql
-- 基本 PIVOT
SELECT *
FROM sales
PIVOT (
    SUM(revenue)
    FOR quarter IN ('Q1', 'Q2', 'Q3', 'Q4')
);

-- 多聚合
SELECT *
FROM sales
PIVOT (
    SUM(revenue) AS total,
    AVG(revenue) AS avg_rev
    FOR quarter IN ('Q1' AS q1, 'Q2' AS q2)
);

-- 不支持动态 PIVOT，需在客户端拼 SQL 或用脚本
```

### Spark SQL

```sql
-- 基本 PIVOT
SELECT *
FROM sales
PIVOT (
    SUM(revenue)
    FOR quarter IN ('Q1', 'Q2', 'Q3', 'Q4')
);

-- 注意: Spark SQL 语法要求显式 IN 列表，不能省略
-- 省略 IN 列表仅在 DataFrame API 中可用:
--   df.groupBy("year").pivot("quarter").agg(sum("revenue"))
-- DataFrame API 会自动发现不同值（额外 job，受 spark.sql.pivotMaxValues 限制，默认 10000）
```

**注意**: Spark SQL 的 PIVOT 语法**必须提供显式 IN 列表**。自动值发现（省略 IN 列表）仅在 DataFrame API 中可用，不适用于纯 SQL 语法。

### Databricks

Databricks 在 Spark SQL 基础上扩展：

```sql
-- 基本 PIVOT（同 Spark SQL）
SELECT *
FROM sales
PIVOT (
    SUM(revenue)
    FOR quarter IN ('Q1', 'Q2', 'Q3', 'Q4')
);

-- Databricks 还支持 UNPIVOT（Spark 3.4+ / DBR 11.0+）
SELECT *
FROM sales_wide
UNPIVOT (
    revenue FOR quarter IN (Q1, Q2, Q3, Q4)
);
```

---

## UNPIVOT 语法对比

### SQL Server

```sql
-- 基本 UNPIVOT
SELECT year, quarter, revenue
FROM sales_wide
UNPIVOT (
    revenue                                    -- 值列名
    FOR quarter IN ([Q1], [Q2], [Q3], [Q4])    -- 名称列 + 源列
) AS unpvt;
```

**限制**:
- 默认排除 NULL 值（值列为 NULL 的行被过滤掉）
- 不支持 `INCLUDE NULLS` 选项（需用 `WHERE` 过滤或 `CROSS APPLY + VALUES` 保留 NULL）
- 所有源列必须是相同类型（或可隐式转换）
- 不支持多列 UNPIVOT（同时拆分多对列）

### Oracle

Oracle 的 UNPIVOT 功能最完整：

```sql
-- 基本 UNPIVOT（默认 EXCLUDE NULLS）
SELECT year, quarter, revenue
FROM sales_wide
UNPIVOT (
    revenue
    FOR quarter IN (Q1 AS 'Q1', Q2 AS 'Q2', Q3 AS 'Q3', Q4 AS 'Q4')
);

-- INCLUDE NULLS（保留 NULL 行）
SELECT year, quarter, revenue
FROM sales_wide
UNPIVOT INCLUDE NULLS (
    revenue
    FOR quarter IN (Q1 AS 'Q1', Q2 AS 'Q2', Q3 AS 'Q3', Q4 AS 'Q4')
);

-- 多列 UNPIVOT（同时拆分多对列）
SELECT year, period, revenue, cost
FROM financial_wide
UNPIVOT (
    (revenue, cost)
    FOR period IN (
        (Q1_rev, Q1_cost) AS 'Q1',
        (Q2_rev, Q2_cost) AS 'Q2',
        (Q3_rev, Q3_cost) AS 'Q3',
        (Q4_rev, Q4_cost) AS 'Q4'
    )
);
```

**Oracle 特有**:
- `INCLUDE NULLS` / `EXCLUDE NULLS` 显式控制空值行为
- 多列 UNPIVOT 允许一次将多对列拆为多行
- IN 列表中可为每个值指定别名 `AS`

### BigQuery

```sql
-- 基本 UNPIVOT
SELECT *
FROM sales_wide
UNPIVOT (
    revenue FOR quarter IN (Q1, Q2, Q3, Q4)
);

-- 多值 UNPIVOT（BigQuery 支持）
SELECT *
FROM financial_wide
UNPIVOT (
    (revenue, cost)
    FOR period IN (
        (Q1_rev, Q1_cost) AS 'Q1',
        (Q2_rev, Q2_cost) AS 'Q2'
    )
);
```

### DuckDB

```sql
-- 基本 UNPIVOT 简洁语法
UNPIVOT sales_wide ON Q1, Q2, Q3, Q4 INTO NAME quarter VALUE revenue;

-- 使用 COLUMNS(*) 自动选择列
UNPIVOT sales_wide
    ON COLUMNS(* EXCLUDE (year))
    INTO NAME quarter VALUE revenue;
-- 将除 year 外的所有列都 UNPIVOT

-- 标准兼容写法
SELECT * FROM sales_wide
UNPIVOT (revenue FOR quarter IN (Q1, Q2, Q3, Q4));
```

`COLUMNS(*)` 表达式让 UNPIVOT 无需显式列出每一列，特别适合列数很多的场景。

### Snowflake

```sql
-- UNPIVOT
SELECT year, quarter, revenue
FROM sales_wide
UNPIVOT (
    revenue FOR quarter IN (Q1, Q2, Q3, Q4)
);
-- Snowflake 的 UNPIVOT 默认排除 NULL 行
-- 支持 INCLUDE NULLS: UNPIVOT INCLUDE NULLS (revenue FOR quarter IN (Q1, Q2, Q3, Q4))
```

### Spark SQL (3.4+)

```sql
-- 原生 UNPIVOT（Spark 3.4 新增）
SELECT *
FROM sales_wide
UNPIVOT (
    revenue FOR quarter IN (Q1, Q2, Q3, Q4)
);

-- 多列 UNPIVOT
SELECT *
FROM financial_wide
UNPIVOT (
    (revenue, cost)
    FOR period IN (
        (Q1_rev, Q1_cost) AS Q1,
        (Q2_rev, Q2_cost) AS Q2
    )
);
```

---

## CASE WHEN + GROUP BY 手动 PIVOT（万能回退方案）

对不支持原生 PIVOT 的引擎（MySQL、PostgreSQL、MariaDB、SQLite、ClickHouse、Trino 等），
`CASE WHEN + 聚合 + GROUP BY` 是通用的 PIVOT 模拟方式。

### 标准写法

```sql
SELECT
    year,
    SUM(CASE WHEN quarter = 'Q1' THEN revenue END) AS Q1,
    SUM(CASE WHEN quarter = 'Q2' THEN revenue END) AS Q2,
    SUM(CASE WHEN quarter = 'Q3' THEN revenue END) AS Q3,
    SUM(CASE WHEN quarter = 'Q4' THEN revenue END) AS Q4
FROM sales
GROUP BY year;
```

### 各引擎的微小差异

| 引擎 | CASE 语法 | NULL 处理 | 更优雅的替代 |
|------|----------|----------|------------|
| MySQL | 标准 CASE WHEN | ELSE NULL（默认） | IF(quarter='Q1', revenue, NULL) |
| MariaDB | 标准 CASE WHEN | 同 MySQL | IF() 函数 |
| PostgreSQL | 标准 CASE WHEN | 同上 | **FILTER (WHERE ...)** 子句 |
| SQLite | 标准 CASE WHEN | 同上 | 无 |
| ClickHouse | 标准 CASE WHEN | 同上 | **sumIf(), countIf()** 等条件聚合 |
| Trino | 标准 CASE WHEN | 同上 | **FILTER (WHERE ...)** 子句 |
| Presto | 标准 CASE WHEN | 同上 | FILTER (WHERE ...) |
| Redshift | 标准 CASE WHEN | 同上 | 无（不支持 FILTER） |
| CockroachDB | 标准 CASE WHEN | 同上 | FILTER (WHERE ...) |
| Vertica | 标准 CASE WHEN | 同上 | 无 |
| Teradata | 标准 CASE WHEN | 同上 | 无 |
| DB2 | 标准 CASE WHEN | 同上 | DECODE() |
| Hive | 标准 CASE WHEN | 同上 | IF() 函数 |
| StarRocks | 标准 CASE WHEN | 同上 | IF() 函数 |
| Doris | 标准 CASE WHEN | 同上 | IF() 函数 |

### PostgreSQL FILTER 子句（更优雅的条件聚合）

```sql
-- 比 CASE WHEN 更简洁
SELECT
    year,
    SUM(revenue) FILTER (WHERE quarter = 'Q1') AS Q1,
    SUM(revenue) FILTER (WHERE quarter = 'Q2') AS Q2,
    SUM(revenue) FILTER (WHERE quarter = 'Q3') AS Q3,
    SUM(revenue) FILTER (WHERE quarter = 'Q4') AS Q4
FROM sales
GROUP BY year;
```

`FILTER` 是 SQL:2003 标准特性，语义等价于 `SUM(CASE WHEN ... THEN ... END)`，但可读性更好。
支持 FILTER 的引擎: PostgreSQL 9.4+, DuckDB, Trino, Presto, CockroachDB, SQLite 3.30+。

### ClickHouse 条件聚合函数

```sql
-- ClickHouse 独有的 -If 后缀聚合函数
SELECT
    year,
    sumIf(revenue, quarter = 'Q1') AS Q1,
    sumIf(revenue, quarter = 'Q2') AS Q2,
    sumIf(revenue, quarter = 'Q3') AS Q3,
    sumIf(revenue, quarter = 'Q4') AS Q4
FROM sales
GROUP BY year;
```

ClickHouse 的 `sumIf`, `countIf`, `avgIf` 等条件聚合函数比 CASE WHEN 性能更好，因为引擎可以在执行层面优化条件判断。

---

## PostgreSQL CROSSTAB 扩展

PostgreSQL 通过 `tablefunc` 扩展提供 `crosstab()` 函数实现 PIVOT：

```sql
-- 1. 启用扩展
CREATE EXTENSION IF NOT EXISTS tablefunc;

-- 2. 基本 crosstab（单参数形式）
SELECT * FROM crosstab(
    'SELECT year, quarter, SUM(revenue)
     FROM sales
     GROUP BY year, quarter
     ORDER BY 1, 2'
) AS ct(year INT, Q1 NUMERIC, Q2 NUMERIC, Q3 NUMERIC, Q4 NUMERIC);

-- 3. 双参数 crosstab（更安全，显式指定类别）
SELECT * FROM crosstab(
    'SELECT year, quarter, SUM(revenue)
     FROM sales
     GROUP BY year, quarter
     ORDER BY 1, 2',
    'SELECT DISTINCT quarter FROM sales ORDER BY 1'  -- 类别查询
) AS ct(year INT, Q1 NUMERIC, Q2 NUMERIC, Q3 NUMERIC, Q4 NUMERIC);
```

**单参数 vs 双参数**:
- 单参数: 按出现顺序填充列，如果某个 year 缺少某个 quarter，值会错位
- 双参数: 显式匹配类别与列，缺失值正确填 NULL

**crosstab 的局限**:
- 结果类型必须在函数调用外通过 `AS ct(...)` 显式定义——无法动态确定列
- 源查询必须恰好返回 3 列（行标识, 类别, 值）
- 性能不如原生 PIVOT（涉及函数调用和字符串 SQL）
- 兼容 PostgreSQL 的引擎（YugabyteDB, Greenplum, TimescaleDB）也可使用（CockroachDB 不支持 tablefunc 扩展，无法使用 crosstab）

---

## 动态 PIVOT（列数未知）

动态 PIVOT 是 PIVOT 的"圣杯问题"：当不知道有多少个不同值（即不知道要生成多少列）时如何处理？

### 方案对比矩阵

| 引擎 | 方案 | 复杂度 | 安全性 |
|------|------|--------|-------|
| Snowflake | `PIVOT ... IN (ANY)` | 极简 | 安全 |
| DuckDB | `PIVOT table ON col USING agg()` | 极简 | 安全 |
| Snowflake | `PIVOT ... IN (SELECT ...)` | 简单 | 安全 |
| Spark SQL | DataFrame API 自动发现（SQL 语法需显式 IN 列表） | 简单 | 有限制 (pivotMaxValues) |
| Oracle | `PIVOT XML ... IN (ANY)` | 中等 | 安全（但输出为 XML） |
| SQL Server | 动态 SQL + sp_executesql | 复杂 | SQL 注入风险 |
| Oracle | 动态 SQL + EXECUTE IMMEDIATE | 复杂 | SQL 注入风险 |
| PostgreSQL | 动态 SQL + crosstab | 复杂 | SQL 注入风险 |
| MySQL | PREPARE + EXECUTE | 复杂 | SQL 注入风险 |
| MariaDB | PREPARE + EXECUTE | 复杂 | SQL 注入风险 |
| Trino | 客户端拼 SQL | 复杂 | 取决于实现 |
| ClickHouse | 客户端拼 SQL | 复杂 | 取决于实现 |

### SQL Server 动态 PIVOT

```sql
DECLARE @columns NVARCHAR(MAX), @sql NVARCHAR(MAX);

-- 收集所有不同值
SELECT @columns = STRING_AGG(QUOTENAME(quarter), ', ')
FROM (SELECT DISTINCT quarter FROM sales) AS q;

-- 拼接完整 SQL
SET @sql = N'
SELECT year, ' + @columns + '
FROM (SELECT year, quarter, revenue FROM sales) AS src
PIVOT (
    SUM(revenue)
    FOR quarter IN (' + @columns + ')
) AS pvt';

EXEC sp_executesql @sql;
```

**注意**: `QUOTENAME()` 用于防止 SQL 注入——将值用方括号包裹并转义。

### Oracle 动态 PIVOT

```sql
DECLARE
    v_columns VARCHAR2(4000);
    v_sql     VARCHAR2(4000);
BEGIN
    -- 收集类别值
    SELECT LISTAGG('''' || quarter || ''' AS ' || quarter, ', ')
           WITHIN GROUP (ORDER BY quarter)
    INTO v_columns
    FROM (SELECT DISTINCT quarter FROM sales);

    -- 拼 SQL
    v_sql := 'SELECT * FROM sales
              PIVOT (SUM(revenue) FOR quarter IN (' || v_columns || '))';

    -- 作为游标返回或执行
    EXECUTE IMMEDIATE v_sql;
END;
```

### MySQL 动态 PIVOT

```sql
-- 在存储过程或会话中
SET @sql = NULL;
SELECT GROUP_CONCAT(
    DISTINCT CONCAT(
        'SUM(CASE WHEN quarter = ''', quarter,
        ''' THEN revenue END) AS `', quarter, '`'
    )
) INTO @sql FROM sales;

SET @sql = CONCAT('SELECT year, ', @sql, ' FROM sales GROUP BY year');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
```

### PostgreSQL 动态 PIVOT

```sql
-- 使用 PL/pgSQL
DO $$
DECLARE
    cols TEXT;
    query TEXT;
BEGIN
    SELECT string_agg(DISTINCT
        format('SUM(CASE WHEN quarter = %L THEN revenue END) AS %I', quarter, quarter),
        ', '
    ) INTO cols
    FROM sales;

    query := format('SELECT year, %s FROM sales GROUP BY year', cols);
    -- 使用 EXECUTE 执行或返回
    RAISE NOTICE '%', query;
END $$;

-- 或使用 crosstab 的动态版本
-- 但仍需动态定义返回类型，极其不便
```

### 动态 PIVOT 的根本困难

SQL 是强类型语言，查询的输出 schema（列数和类型）必须在编译/规划阶段确定。
动态 PIVOT 违反了这一原则——列数取决于数据内容，只有执行后才能知道。

各引擎的解决思路:

| 思路 | 代表引擎 | 实现方式 |
|------|---------|---------|
| 编译时预执行 | Snowflake, DuckDB | 在优化前先跑一个子查询收集值 |
| 生成非关系输出 | Oracle (XML PIVOT) | 输出 XML/JSON，绕过固定 schema |
| 推迟到运行时 | Spark SQL | 允许 schema 在运行时确定 |
| 放弃 | 传统 RDBMS | 要求用户自己拼动态 SQL |

---

## 多聚合 PIVOT

一些引擎允许在一个 PIVOT 中同时计算多个聚合函数。

### 支持矩阵

| 引擎 | 多聚合 | 列名格式 |
|------|--------|---------|
| Oracle | 支持 | `<value>_<agg_alias>` |
| BigQuery | 支持 | `<agg_alias>_<value>` |
| DuckDB | 支持 | `<value>_<agg_alias>` |
| SQL Server | **不支持** | - |
| Snowflake | **不支持** | - |
| Spark SQL | **不支持** | - |

### Oracle 多聚合示例

```sql
SELECT *
FROM (SELECT year, quarter, revenue FROM sales)
PIVOT (
    SUM(revenue) AS sum_rev,
    AVG(revenue) AS avg_rev,
    COUNT(*) AS cnt
    FOR quarter IN ('Q1' AS Q1, 'Q2' AS Q2)
);
-- 产出列: YEAR, Q1_SUM_REV, Q1_AVG_REV, Q1_CNT, Q2_SUM_REV, Q2_AVG_REV, Q2_CNT
```

### DuckDB 多聚合示例

```sql
PIVOT sales ON quarter
USING SUM(revenue) AS total, AVG(revenue) AS avg_val, COUNT(*) AS cnt
GROUP BY year;
```

### 不支持多聚合时的变通

对于 SQL Server / Snowflake 等不支持多聚合的引擎，可分别 PIVOT 后 JOIN：

```sql
-- SQL Server: 两次 PIVOT 后 JOIN
WITH pivot_sum AS (
    SELECT year, [Q1] AS Q1_sum, [Q2] AS Q2_sum
    FROM (SELECT year, quarter, revenue FROM sales) src
    PIVOT (SUM(revenue) FOR quarter IN ([Q1], [Q2])) pvt
),
pivot_cnt AS (
    SELECT year, [Q1] AS Q1_cnt, [Q2] AS Q2_cnt
    FROM (SELECT year, quarter, revenue FROM sales) src
    PIVOT (COUNT(revenue) FOR quarter IN ([Q1], [Q2])) pvt
)
SELECT s.year, s.Q1_sum, c.Q1_cnt, s.Q2_sum, c.Q2_cnt
FROM pivot_sum s JOIN pivot_cnt c ON s.year = c.year;
```

---

## LATERAL + VALUES 实现 UNPIVOT

对不支持原生 UNPIVOT 的引擎，`LATERAL + VALUES` 是最灵活的替代方案。

### PostgreSQL / CockroachDB / DuckDB

```sql
SELECT w.year, u.quarter, u.revenue
FROM sales_wide w
CROSS JOIN LATERAL (
    VALUES
        ('Q1', w.Q1),
        ('Q2', w.Q2),
        ('Q3', w.Q3),
        ('Q4', w.Q4)
) AS u(quarter, revenue)
WHERE u.revenue IS NOT NULL;  -- 模拟 EXCLUDE NULLS
```

### SQL Server (CROSS APPLY + VALUES)

```sql
SELECT w.year, u.quarter, u.revenue
FROM sales_wide w
CROSS APPLY (
    VALUES
        ('Q1', w.Q1),
        ('Q2', w.Q2),
        ('Q3', w.Q3),
        ('Q4', w.Q4)
) AS u(quarter, revenue)
WHERE u.revenue IS NOT NULL;
```

### Oracle (LATERAL + 表构造)

```sql
-- Oracle 12c+
SELECT w.year, u.quarter, u.revenue
FROM sales_wide w
CROSS JOIN LATERAL (
    SELECT 'Q1' AS quarter, w.Q1 AS revenue FROM DUAL UNION ALL
    SELECT 'Q2', w.Q2 FROM DUAL UNION ALL
    SELECT 'Q3', w.Q3 FROM DUAL UNION ALL
    SELECT 'Q4', w.Q4 FROM DUAL
) u
WHERE u.revenue IS NOT NULL;
```

### MySQL (UNION ALL 回退)

MySQL 不支持 LATERAL + VALUES 组合，只能用 UNION ALL:

```sql
SELECT year, 'Q1' AS quarter, Q1 AS revenue FROM sales_wide WHERE Q1 IS NOT NULL
UNION ALL
SELECT year, 'Q2', Q2 FROM sales_wide WHERE Q2 IS NOT NULL
UNION ALL
SELECT year, 'Q3', Q3 FROM sales_wide WHERE Q3 IS NOT NULL
UNION ALL
SELECT year, 'Q4', Q4 FROM sales_wide WHERE Q4 IS NOT NULL;
```

**UNION ALL 与 LATERAL + VALUES 的对比**:

| 维度 | LATERAL + VALUES | UNION ALL |
|------|-----------------|-----------|
| 表扫描次数 | 1 次 | N 次（每列一次） |
| 可维护性 | 好（一处修改） | 差（每段都要改） |
| 性能 | 好 | 差（大表时） |
| 兼容性 | 需 LATERAL 支持 | 所有引擎 |

---

## Spark/Hive STACK() 实现 UNPIVOT

Spark SQL (< 3.4) 和 Hive 没有原生 UNPIVOT，使用 `STACK()` 生成器函数配合 `LATERAL VIEW`:

### Hive

```sql
SELECT year, quarter, revenue
FROM sales_wide
LATERAL VIEW STACK(4,
    'Q1', Q1,
    'Q2', Q2,
    'Q3', Q3,
    'Q4', Q4
) t AS quarter, revenue;
```

**STACK(n, ...)**: 接受 n 行的扁平参数列表，每行的列数由参数总数/n 决定。
`STACK(4, 'Q1', Q1, 'Q2', Q2, 'Q3', Q3, 'Q4', Q4)` 生成 4 行 x 2 列。

### Spark SQL (< 3.4)

```sql
-- 与 Hive 语法相同
SELECT year, quarter, revenue
FROM sales_wide
LATERAL VIEW STACK(4,
    'Q1', Q1,
    'Q2', Q2,
    'Q3', Q3,
    'Q4', Q4
) t AS quarter, revenue
WHERE revenue IS NOT NULL;
```

### Spark SQL (3.4+)

从 Spark 3.4 开始可以直接使用原生 UNPIVOT，不再需要 STACK:

```sql
SELECT *
FROM sales_wide
UNPIVOT (
    revenue FOR quarter IN (Q1, Q2, Q3, Q4)
);
```

### Databricks STACK 与 UNPIVOT

```sql
-- 旧写法 (STACK)
SELECT year, quarter, revenue
FROM sales_wide
LATERAL VIEW STACK(4, 'Q1', Q1, 'Q2', Q2, 'Q3', Q3, 'Q4', Q4)
    t AS quarter, revenue;

-- 新写法 (UNPIVOT, DBR 11.0+)
SELECT *
FROM sales_wide
UNPIVOT (revenue FOR quarter IN (Q1, Q2, Q3, Q4));
```

### STACK 与原生 UNPIVOT 的对比

| 维度 | STACK() | 原生 UNPIVOT |
|------|---------|-------------|
| 可读性 | 差（参数顺序易错） | 好（声明式） |
| 多列支持 | 支持（增加每行列数） | 引擎相关 |
| 类型检查 | 运行时 | 编译时 |
| NULL 处理 | 需手动 WHERE | EXCLUDE NULLS 默认 |

---

## CROSS JOIN + UNNEST 作为 UNPIVOT 替代

一些引擎（Trino, Presto, BigQuery）中，`CROSS JOIN UNNEST` 是实现 UNPIVOT 的惯用方式。

### Trino / Presto

```sql
SELECT w.year, u.quarter, u.revenue
FROM sales_wide w
CROSS JOIN UNNEST(
    ARRAY['Q1', 'Q2', 'Q3', 'Q4'],
    ARRAY[w.Q1, w.Q2, w.Q3, w.Q4]
) AS u(quarter, revenue)
WHERE u.revenue IS NOT NULL;
```

**原理**: 构造两个平行数组——一个是名称，一个是值——然后 UNNEST 同时展开。

### BigQuery

```sql
-- 方法 1: 原生 UNPIVOT（推荐）
SELECT * FROM sales_wide
UNPIVOT (revenue FOR quarter IN (Q1, Q2, Q3, Q4));

-- 方法 2: CROSS JOIN + UNNEST（旧写法 / 更灵活场景）
SELECT w.year, quarter, revenue
FROM sales_wide w
CROSS JOIN UNNEST([
    STRUCT('Q1' AS quarter, w.Q1 AS revenue),
    STRUCT('Q2' AS quarter, w.Q2 AS revenue),
    STRUCT('Q3' AS quarter, w.Q3 AS revenue),
    STRUCT('Q4' AS quarter, w.Q4 AS revenue)
]) AS t
WHERE revenue IS NOT NULL;
```

BigQuery 的 UNNEST 接受 STRUCT 数组，可以同时展开多列。

### ClickHouse

```sql
-- ClickHouse 使用 arrayJoin
SELECT
    year,
    arrayJoin(['Q1', 'Q2', 'Q3', 'Q4']) AS quarter,
    arrayJoin([Q1, Q2, Q3, Q4]) AS revenue  -- 注意: 这样写有笛卡尔积问题
FROM sales_wide;

-- 正确写法: 使用 tuple 展开
SELECT
    year,
    tupleElement(t, 1) AS quarter,
    tupleElement(t, 2) AS revenue
FROM sales_wide
ARRAY JOIN
    [('Q1', Q1), ('Q2', Q2), ('Q3', Q3), ('Q4', Q4)] AS t;

-- 或使用 ARRAY JOIN 配合并行数组
SELECT year, quarter, revenue
FROM sales_wide
ARRAY JOIN
    ['Q1', 'Q2', 'Q3', 'Q4'] AS quarter,
    [Q1, Q2, Q3, Q4] AS revenue;
```

ClickHouse 的 `ARRAY JOIN` 等价于其他引擎的 `CROSS JOIN UNNEST`，且支持同时展开多个平行数组。

### 各引擎 UNNEST 风格对比

| 引擎 | UNPIVOT 惯用写法 | 备注 |
|------|-----------------|------|
| PostgreSQL | `LATERAL + VALUES` | 最直观 |
| SQL Server | `CROSS APPLY + VALUES` | T-SQL 风格 |
| Trino / Presto | `CROSS JOIN UNNEST(ARRAY[], ARRAY[])` | 数组并行展开 |
| BigQuery | `CROSS JOIN UNNEST([STRUCT(...)])` | STRUCT 数组 |
| ClickHouse | `ARRAY JOIN [...] AS name, [...] AS val` | 并行数组 |
| Hive / Spark | `LATERAL VIEW STACK(n, ...)` | 生成器函数 |
| Snowflake | `LATERAL FLATTEN(...)` | 配合 OBJECT/ARRAY |
| MySQL | `UNION ALL` | 无更好选择 |
| SQLite | `UNION ALL` | 无更好选择 |
| MariaDB | `UNION ALL` | 无更好选择 |
| Redshift | `UNION ALL` | 无更好选择 |
| DB2 | `LATERAL + VALUES` | 支持 LATERAL |
| Teradata | `UNION ALL` | 无更好选择 |
| Vertica | `UNION ALL` | 无更好选择 |
| StarRocks | `UNION ALL` | 无更好选择 |
| Doris | `UNION ALL` | 无更好选择 |
| TiDB | `UNION ALL` | 无更好选择 |
| CockroachDB | `LATERAL + VALUES` | 兼容 PG |
| YugabyteDB | `LATERAL + VALUES` | 兼容 PG |
| Greenplum | `LATERAL + VALUES` | 兼容 PG |
| TimescaleDB | `LATERAL + VALUES` | 兼容 PG |
| SingleStore | `UNION ALL` | 无更好选择 |
| Firebird | `UNION ALL` | 无更好选择 |
| H2 | `UNION ALL` | 无更好选择 |
| Exasol | `UNION ALL` | 无更好选择 |
| SAP HANA | `UNION ALL` | 无更好选择 |
| Informix | `UNION ALL` | 无更好选择 |
| MonetDB | `UNION ALL` | 无更好选择 |
| CrateDB | `CROSS JOIN UNNEST` | 类似 Trino |
| Firebolt | `CROSS JOIN UNNEST` | 类似 Trino |
| QuestDB | `UNION ALL` | 无更好选择 |
| HEAVY.AI | `UNION ALL` | 无更好选择 |

---

## PIVOT 子查询动态列

部分引擎允许在 PIVOT 的 IN 子句中使用子查询来动态确定列值。

### Snowflake

```sql
-- IN 子查询（Snowflake 独有）
SELECT *
FROM sales
PIVOT (
    SUM(revenue)
    FOR quarter IN (
        SELECT DISTINCT quarter FROM sales WHERE year >= 2024 ORDER BY quarter
    )
) AS pvt;
```

这比 `ANY` 更精确——可以通过子查询过滤要转为列的值。

### Oracle XML PIVOT

```sql
-- Oracle 的 PIVOT XML 允许 IN (ANY) 或 IN (子查询)
SELECT *
FROM sales
PIVOT XML (
    SUM(revenue)
    FOR quarter IN (SELECT DISTINCT quarter FROM sales)
);
-- 注意: 输出不是关系列，而是 XML 列
```

### 其他引擎

大多数引擎不支持在 PIVOT IN 中使用子查询。对于 SQL Server、BigQuery、Spark 等，
必须通过动态 SQL 或客户端代码先查询不同值，再拼接 PIVOT 语句。

---

## 对引擎开发者的实现建议

### 1. 语法设计: PIVOT/UNPIVOT 在 FROM 子句中的位置

PIVOT/UNPIVOT 作为表引用（table_ref）的后缀操作，与 JOIN 平级:

```
from_clause:
    table_ref { ',' table_ref }

table_ref:
    base_table
  | '(' select_stmt ')' [ AS alias ]
  | table_ref join_type JOIN table_ref ON condition
  | table_ref PIVOT '(' pivot_spec ')' [ AS alias ]
  | table_ref UNPIVOT [ INCLUDE NULLS | EXCLUDE NULLS ]
        '(' unpivot_spec ')' [ AS alias ]

pivot_spec:
    agg_func '(' expr ')' [ AS alias ]
    { ',' agg_func '(' expr ')' [ AS alias ] }
    FOR column IN '(' value_list ')'

unpivot_spec:
    value_column FOR name_column IN '(' column_list ')'
  | '(' value_columns ')' FOR name_column IN '(' multi_column_list ')'
```

**设计要点**:
- PIVOT/UNPIVOT 出现在 table_ref 产生式中，解析器在处理 FROM 子句时识别关键字
- PIVOT 中的 IN 列表在解析阶段只是表达式列表，不需要立即求值
- 如果要支持 `IN (ANY)` 或 `IN (SELECT ...)`，需要在 AST 中区分三种 IN 类型

### 2. PIVOT 语义转换（Planner 阶段）

PIVOT 本质上是语法糖，推荐在 planner/rewriter 阶段转换为等价的 GROUP BY + CASE WHEN:

```
-- 输入 AST
SELECT * FROM t PIVOT (SUM(val) FOR cat IN ('A', 'B', 'C'))

-- 转换后
SELECT
    <implicit_group_cols>,
    SUM(CASE WHEN cat = 'A' THEN val END) AS "A",
    SUM(CASE WHEN cat = 'B' THEN val END) AS "B",
    SUM(CASE WHEN cat = 'C' THEN val END) AS "C"
FROM t
GROUP BY <implicit_group_cols>
```

**隐式 GROUP BY 列的计算**: `implicit_group_cols = all_columns(t) - {val} - {cat}`
即原表所有列减去值列和 FOR 列。这意味着 PIVOT 转换依赖于输入表的 schema 信息。

**多聚合处理**:

```
-- 输入
PIVOT (SUM(val) AS s, COUNT(*) AS c FOR cat IN ('A', 'B'))

-- 转换
SELECT
    <implicit_group_cols>,
    SUM(CASE WHEN cat = 'A' THEN val END) AS "A_s",
    COUNT(CASE WHEN cat = 'A' THEN 1 END) AS "A_c",
    SUM(CASE WHEN cat = 'B' THEN val END) AS "B_s",
    COUNT(CASE WHEN cat = 'B' THEN 1 END) AS "B_c"
FROM t
GROUP BY <implicit_group_cols>
```

列名生成规则: `<pivot_value>_<agg_alias>`，需要处理特殊字符和命名冲突。

> **注意**: BigQuery 的多聚合列名格式为 `<agg_alias>_<value>`，与上述通用规则相反，详见"多聚合 PIVOT"章节的支持矩阵。

### 3. UNPIVOT 语义转换

UNPIVOT 可转换为 CROSS JOIN LATERAL + VALUES + 可选 WHERE:

```
-- 输入
SELECT * FROM t UNPIVOT (val FOR name IN (a, b, c))

-- 转换为
SELECT t.other_cols, u.name, u.val
FROM t
CROSS JOIN LATERAL (
    VALUES ('a', t.a), ('b', t.b), ('c', t.c)
) AS u(name, val)
WHERE u.val IS NOT NULL          -- EXCLUDE NULLS (默认)
```

如果引擎不支持 LATERAL，可进一步转换为 UNION ALL:

```
SELECT other_cols, 'a' AS name, a AS val FROM t WHERE a IS NOT NULL
UNION ALL
SELECT other_cols, 'b' AS name, b AS val FROM t WHERE b IS NOT NULL
UNION ALL
SELECT other_cols, 'c' AS name, c AS val FROM t WHERE c IS NOT NULL
```

**INCLUDE NULLS 处理**: 移除 WHERE 过滤条件即可。

**多列 UNPIVOT**:

```
-- 输入
UNPIVOT ((v1, v2) FOR name IN ((a1, a2) AS 'A', (b1, b2) AS 'B'))

-- 转换
CROSS JOIN LATERAL (
    VALUES ('A', t.a1, t.a2), ('B', t.b1, t.b2)
) AS u(name, v1, v2)
```

### 4. 动态 PIVOT (IN ANY) 的实现

如果要实现 Snowflake 风格的 `PIVOT ... IN (ANY)`，需要打破编译与执行的边界:

**实现步骤**:

1. **解析阶段**: 识别 `IN (ANY)` 并在 AST 中标记为"待决定"
2. **Binding/Analysis 阶段**: 检测到 ANY，生成一个内部查询 `SELECT DISTINCT pivot_col FROM source`
3. **预执行**: 在完成 PIVOT 的 binding 之前，先执行上述查询获取所有不同值
4. **重写**: 用获取的值列表替换 ANY，回到标准 PIVOT 处理流程
5. **类型推导**: 所有动态列的类型 = 聚合函数的返回类型

**架构挑战**:
- 打破了"规划阶段不执行"的传统架构假设
- 如果源表是复杂查询/视图，预执行的代价可能很高
- 需要考虑缓存策略——同一查询多次执行时是否每次都重新发现值
- 并发场景下，值发现查询和主查询之间数据可能变化

**替代实现**:
- **Lazy schema**: 延迟确定输出 schema 到执行阶段（Spark 的做法）
- **返回 MAP/JSON**: 不生成关系列，而是返回一个 MAP<string, value> 类型的列（绕过固定 schema 限制）

### 5. 类型系统考虑

**PIVOT**:
- 输出列类型 = 聚合函数的返回类型（如 SUM(INT) -> BIGINT）
- 如果值列表包含不同类型的值（如混合 INT 和 STRING），需要类型推导规则
- NULL 类型: PIVOT 结果中不存在的交叉单元格应为 NULL

**UNPIVOT**:
- 所有源列必须类型兼容（或可隐式转换为公共类型）
- 名称列的类型: 通常为 VARCHAR
- 值列的类型: 所有源列的最小公共超类型（least common supertype）
- 类型不兼容时应报编译期错误而非运行时错误

### 6. 性能优化

**PIVOT 优化**:
- **单次扫描**: N 个条件聚合应在一次表扫描中同时计算，而非 N 次独立扫描
- **Hash 聚合**: PIVOT 的 GROUP BY 天然适合 hash 聚合
- **列裁剪**: 如果外部只引用了部分 PIVOT 列，可以裁剪掉不需要的条件聚合
- **稀疏优化**: 如果大部分单元格为 NULL（稀疏矩阵），可考虑压缩存储
- **列数限制**: PIVOT 结果宽度 = |值列表| x |聚合数|，建议设置上限（如 DuckDB 的 pivot_limit 参数）

**UNPIVOT 优化**:
- **避免 UNION ALL 展开**: 如果底层使用 UNION ALL 实现，优化器应合并为单次扫描 + 行复制
- **延迟物化**: UNPIVOT 后如果接 WHERE 过滤，可将条件下推到源表
- **并行化**: UNPIVOT 是 embarrassingly parallel 的——每行独立处理

**动态 PIVOT 优化**:
- 缓存值发现查询的结果
- 如果源表有索引/统计信息，利用 metadata 而非全表扫描来获取不同值
- 设置最大列数硬限制，防止内存溢出

### 7. 错误处理

需要处理的边界情况:

| 场景 | 建议行为 |
|------|---------|
| PIVOT IN 列表为空 | 编译期报错 |
| PIVOT IN 值有重复 | 编译期报错（列名冲突） |
| UNPIVOT 源列类型不兼容 | 编译期报错 |
| 动态 PIVOT 值过多（超过限制） | 运行时报错，提示设置限制 |
| UNPIVOT 源列不存在 | 编译期报错（binding 阶段） |
| PIVOT FOR 列有 NULL 值 | 忽略（NULL 不生成列） |
| PIVOT 值列表中含特殊字符 | 自动转义为合法列名 |

### 8. PIVOT XML: 动态列的替代方案 (Oracle 风格)

硬编码 `IN ('A', 'B', 'C')` 的根本问题在于列名在编译期必须确定。Oracle 提供了 `PIVOT XML` 语法绕过这一限制:

```sql
-- Oracle PIVOT XML: 将动态列编码为 XML 而非关系列
SELECT * FROM sales
PIVOT XML (SUM(amount) FOR region IN (ANY));
-- 返回单个 XML 列, 包含所有 region 值及其聚合结果
```

**引擎实现要点**:
- `PIVOT XML` 不改变输出列数量——始终返回一个 XML/JSON 类型的列，从而避免编译期确定列名的难题
- 这是"返回 MAP/JSON"策略的工业实现，比 `IN (ANY)` 更容易实现，因为不需要打破规划与执行的边界
- 缺点: 下游消费者需要解析 XML/JSON，性能和易用性不如关系列
- **建议**: 如果引擎已支持 JSON/MAP 类型，优先考虑 `PIVOT ... RETURNING MAP<VARCHAR, agg_type>` 语法而非 XML，更符合现代引擎的类型系统

### 9. UNPIVOT 类型同质性强制

UNPIVOT 将多列合并为单个值列，这要求所有源列具有兼容类型。引擎必须在编译期严格检查:

```
-- 类型检查流程
UNPIVOT (val FOR name IN (col_int, col_varchar, col_date))
  → 尝试寻找 least common supertype(INT, VARCHAR, DATE)
  → 如果不存在公共超类型 → 编译期报错 (不应静默转换)

-- 正确的实现行为:
UNPIVOT (val FOR name IN (price, discount, tax))
  → 类型: DECIMAL(10,2), DECIMAL(8,2), DECIMAL(6,2)
  → 公共类型: DECIMAL(10,2) ← 取最大精度
```

**常见陷阱**:
- 隐式转换可能丢失精度或产生意外结果 (如 INT → FLOAT 的浮点精度损失)
- 某些引擎 (SQL Server) 对类型不兼容仅发出警告而非错误，导致运行时数据问题
- **建议**: 默认行为为严格模式 (不兼容即报错)，可选提供 `UNPIVOT ... WITH TYPE COERCION` 允许隐式转换

### 10. 动态 PIVOT SQL 的注入风险审计

当使用动态 SQL 构建 PIVOT 查询时 (尤其是在不支持 `IN (ANY)` 的引擎上)，SQL 注入风险极高:

```sql
-- 危险模式: 值直接拼接进 SQL
EXECUTE IMMEDIATE
  'SELECT * FROM t PIVOT (SUM(val) FOR cat IN ('
  || v_dynamic_list   -- 如果 v_dynamic_list 来自用户输入或数据表，存在注入风险
  || '))';

-- v_dynamic_list 可能包含: 'A'')) ; DROP TABLE t; --
```

**引擎开发者的防护建议**:
1. **引擎层防护**: 如果提供 `IN (ANY)` 或 `IN (SELECT ...)` 语法，动态列发现在引擎内部完成，天然避免注入
2. **参数化支持**: 考虑支持 `IN (:param_list)` 绑定变量形式，由引擎负责转义
3. **安全审计点**: 如果引擎提供 `EXECUTE IMMEDIATE` / `sp_executesql`，应在文档和审计日志中明确标记动态 PIVOT 为高风险模式
4. **引用标识符强制**: 动态生成的列名必须通过引擎的标识符引用函数处理 (如 `QUOTENAME()` / `quote_ident()`)，防止列名中的特殊字符被解释为 SQL 语法

### 11. 元数据与 INFORMATION_SCHEMA

PIVOT 查询的输出列名是动态生成的，在以下场景需要注意:
- 视图定义: `CREATE VIEW v AS SELECT * FROM t PIVOT (...)` 需要在视图创建时固定 schema
- 预编译语句: 返回的列元数据需要包含正确的列名和类型
- 客户端驱动: JDBC/ODBC 驱动需要正确报告 ResultSetMetaData

---

## 参考资料

- SQL Server: [PIVOT and UNPIVOT](https://learn.microsoft.com/en-us/sql/t-sql/queries/from-using-pivot-and-unpivot)
- Oracle: [PIVOT and UNPIVOT](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/SELECT.html)
- Snowflake: [PIVOT](https://docs.snowflake.com/en/sql-reference/constructs/pivot) / [UNPIVOT](https://docs.snowflake.com/en/sql-reference/constructs/unpivot)
- DuckDB: [PIVOT Statement](https://duckdb.org/docs/sql/statements/pivot)
- BigQuery: [PIVOT operator](https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#pivot_operator)
- Spark SQL: [PIVOT Clause](https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-pivot.html) / [UNPIVOT](https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-unpivot.html)
- PostgreSQL: [tablefunc — crosstab](https://www.postgresql.org/docs/current/tablefunc.html)
- ClickHouse: [ARRAY JOIN](https://clickhouse.com/docs/en/sql-reference/statements/select/array-join)
- Hive: [Lateral View](https://cwiki.apache.org/confluence/display/Hive/LanguageManual+LateralView)
