# 原生 PIVOT / UNPIVOT

行列转换的原生语法支持——从手写 CASE WHEN 到声明式转换。

## 支持矩阵

| 引擎 | PIVOT | UNPIVOT | 动态 PIVOT | 版本 |
|------|-------|---------|-----------|------|
| SQL Server | 支持 | 支持 | 不支持（需动态 SQL） | 2005+ |
| Oracle | 支持 | 支持 | 不支持（需动态 SQL） | 11g+ (2007) |
| Snowflake | 支持 | 支持 | **支持 (PIVOT ANY)** | GA |
| BigQuery | 支持 | 支持 | 不支持 | GA |
| DuckDB | 支持 | 支持 | **支持（自动检测值）** | 0.8.0+ |
| Databricks | 支持 | 支持 | 部分支持 | Runtime 11.0+ |
| Spark SQL | 支持 | 支持 | 不支持 | 3.4+ (UNPIVOT) |
| Trino | 不支持 | 不支持 | - | - |
| PostgreSQL | 不支持 | 不支持 | - | 用 crosstab 扩展或 FILTER |
| MySQL | 不支持 | 不支持 | - | 用 CASE WHEN + GROUP BY |
| ClickHouse | 不支持 | 不支持 | - | 用 CASE WHEN / 数组函数 |
| SQLite | 不支持 | 不支持 | - | 用 CASE WHEN |

## 设计动机

### PIVOT: 行转列

```
-- 原始数据（行格式）
| year | quarter | revenue |
|------|---------|---------|
| 2024 | Q1      | 100     |
| 2024 | Q2      | 150     |
| 2024 | Q3      | 200     |
| 2024 | Q4      | 180     |

-- 期望结果（列格式）
| year | Q1  | Q2  | Q3  | Q4  |
|------|-----|-----|-----|-----|
| 2024 | 100 | 150 | 200 | 180 |
```

没有原生 PIVOT 时的写法极其冗长：

```sql
-- 传统写法: CASE WHEN + GROUP BY
SELECT
    year,
    SUM(CASE WHEN quarter = 'Q1' THEN revenue END) AS Q1,
    SUM(CASE WHEN quarter = 'Q2' THEN revenue END) AS Q2,
    SUM(CASE WHEN quarter = 'Q3' THEN revenue END) AS Q3,
    SUM(CASE WHEN quarter = 'Q4' THEN revenue END) AS Q4
FROM sales
GROUP BY year;
```

列数多时（如按月份、按产品），手写 CASE WHEN 极为痛苦且容易出错。

### UNPIVOT: 列转行

与 PIVOT 相反——将多列合并为行。常用于将宽表转为窄表以便分析。

## 语法对比

### SQL Server

```sql
-- PIVOT
SELECT year, [Q1], [Q2], [Q3], [Q4]
FROM sales
PIVOT (
    SUM(revenue)
    FOR quarter IN ([Q1], [Q2], [Q3], [Q4])
) AS pvt;

-- UNPIVOT
SELECT year, quarter, revenue
FROM sales_wide
UNPIVOT (
    revenue
    FOR quarter IN ([Q1], [Q2], [Q3], [Q4])
) AS unpvt;

-- 动态 PIVOT（需要动态 SQL）
DECLARE @columns NVARCHAR(MAX), @sql NVARCHAR(MAX);
SELECT @columns = STRING_AGG(QUOTENAME(quarter), ',')
FROM (SELECT DISTINCT quarter FROM sales) AS q;

SET @sql = N'SELECT year, ' + @columns + '
FROM sales PIVOT (SUM(revenue) FOR quarter IN (' + @columns + ')) AS pvt';
EXEC sp_executesql @sql;
```

### Oracle

```sql
-- PIVOT
SELECT *
FROM sales
PIVOT (
    SUM(revenue)
    FOR quarter IN ('Q1' AS Q1, 'Q2' AS Q2, 'Q3' AS Q3, 'Q4' AS Q4)
);

-- UNPIVOT（支持 INCLUDE/EXCLUDE NULLS）
SELECT year, quarter, revenue
FROM sales_wide
UNPIVOT INCLUDE NULLS (
    revenue
    FOR quarter IN (Q1 AS 'Q1', Q2 AS 'Q2', Q3 AS 'Q3', Q4 AS 'Q4')
);

-- 多列 PIVOT
SELECT *
FROM sales
PIVOT (
    SUM(revenue) AS rev,
    COUNT(*) AS cnt
    FOR quarter IN ('Q1' AS Q1, 'Q2' AS Q2)
);
-- 产出列: Q1_REV, Q1_CNT, Q2_REV, Q2_CNT
```

### Snowflake（PIVOT ANY —— 最先进的实现）

```sql
-- 基本 PIVOT
SELECT *
FROM sales
PIVOT (
    SUM(revenue)
    FOR quarter IN ('Q1', 'Q2', 'Q3', 'Q4')
) AS pvt;

-- PIVOT ANY: 自动检测所有不同值！（Snowflake 独有）
SELECT *
FROM sales
PIVOT (
    SUM(revenue)
    FOR quarter IN (ANY)              -- 不需要列出具体值
) AS pvt;
-- 引擎自动扫描 quarter 的所有不同值，为每个值创建一列
-- 这解决了动态 PIVOT 的核心痛点

-- PIVOT ANY + ORDER BY
SELECT *
FROM sales
PIVOT (
    SUM(revenue)
    FOR quarter IN (ANY ORDER BY quarter)
) AS pvt;

-- UNPIVOT
SELECT year, quarter, revenue
FROM sales_wide
UNPIVOT (
    revenue
    FOR quarter IN (Q1, Q2, Q3, Q4)
);
```

### DuckDB（自动检测值）

```sql
-- 基本 PIVOT
PIVOT sales ON quarter USING SUM(revenue);
-- 等效于 SQL 标准风格:
SELECT * FROM sales
PIVOT (SUM(revenue) FOR quarter IN ('Q1', 'Q2', 'Q3', 'Q4'));

-- DuckDB 简洁语法（自动检测值）
PIVOT sales ON quarter USING SUM(revenue) GROUP BY year;
-- 自动检测 quarter 的所有不同值，无需列出

-- UNPIVOT
UNPIVOT sales_wide ON Q1, Q2, Q3, Q4 INTO NAME quarter VALUE revenue;
-- 或自动:
UNPIVOT sales_wide ON COLUMNS(* EXCLUDE year) INTO NAME quarter VALUE revenue;

-- PIVOT + 多聚合
PIVOT sales ON quarter USING SUM(revenue) AS total, COUNT(*) AS cnt GROUP BY year;
```

### BigQuery

```sql
-- PIVOT
SELECT *
FROM sales
PIVOT (
    SUM(revenue)
    FOR quarter IN ('Q1', 'Q2', 'Q3', 'Q4')
);

-- UNPIVOT
SELECT *
FROM sales_wide
UNPIVOT (
    revenue
    FOR quarter IN (Q1, Q2, Q3, Q4)
);

-- 多值 UNPIVOT
SELECT *
FROM wide_table
UNPIVOT (
    (value1, value2)
    FOR category IN ((a1, a2) AS 'A', (b1, b2) AS 'B')
);
```

### PostgreSQL（替代方案）

```sql
-- 方案 1: CASE WHEN + GROUP BY（最通用）
SELECT
    year,
    SUM(revenue) FILTER (WHERE quarter = 'Q1') AS Q1,
    SUM(revenue) FILTER (WHERE quarter = 'Q2') AS Q2,
    SUM(revenue) FILTER (WHERE quarter = 'Q3') AS Q3,
    SUM(revenue) FILTER (WHERE quarter = 'Q4') AS Q4
FROM sales
GROUP BY year;
-- PostgreSQL 的 FILTER 子句比 CASE WHEN 更优雅

-- 方案 2: crosstab 扩展
CREATE EXTENSION IF NOT EXISTS tablefunc;
SELECT * FROM crosstab(
    'SELECT year, quarter, SUM(revenue)
     FROM sales GROUP BY year, quarter ORDER BY 1, 2',
    'SELECT DISTINCT quarter FROM sales ORDER BY 1'
) AS ct(year INT, Q1 NUMERIC, Q2 NUMERIC, Q3 NUMERIC, Q4 NUMERIC);

-- UNPIVOT 替代: UNNEST + VALUES
SELECT year, quarter, revenue
FROM sales_wide
CROSS JOIN LATERAL (
    VALUES ('Q1', Q1), ('Q2', Q2), ('Q3', Q3), ('Q4', Q4)
) AS t(quarter, revenue);
```

### MySQL（替代方案）

```sql
-- PIVOT 替代: CASE WHEN + GROUP BY
SELECT
    year,
    SUM(CASE WHEN quarter = 'Q1' THEN revenue ELSE 0 END) AS Q1,
    SUM(CASE WHEN quarter = 'Q2' THEN revenue ELSE 0 END) AS Q2,
    SUM(CASE WHEN quarter = 'Q3' THEN revenue ELSE 0 END) AS Q3,
    SUM(CASE WHEN quarter = 'Q4' THEN revenue ELSE 0 END) AS Q4
FROM sales
GROUP BY year;

-- UNPIVOT 替代: UNION ALL
SELECT year, 'Q1' AS quarter, Q1 AS revenue FROM sales_wide
UNION ALL
SELECT year, 'Q2', Q2 FROM sales_wide
UNION ALL
SELECT year, 'Q3', Q3 FROM sales_wide
UNION ALL
SELECT year, 'Q4', Q4 FROM sales_wide;
```

## 动态 PIVOT 的演进

动态 PIVOT（不需要预先列出所有值）是 PIVOT 的"圣杯"：

| 引擎 | 方案 | 评价 |
|------|------|------|
| Snowflake | `PIVOT ... IN (ANY)` | 最优雅: 原生语法级支持 |
| DuckDB | `PIVOT table ON col USING agg()` | 很好: 自动检测值 |
| SQL Server | 动态 SQL + sp_executesql | 差: 需要字符串拼接 |
| Oracle | 动态 SQL + EXECUTE IMMEDIATE | 差: 需要 PL/SQL |
| PostgreSQL | 动态 SQL + crosstab | 差: 需要额外扩展 |
| MySQL | 动态 SQL + PREPARE/EXECUTE | 差: 需要存储过程 |

Snowflake 的 `PIVOT ANY` 和 DuckDB 的自动 PIVOT 代表了现代 SQL 在行列转换上的方向。

## 对引擎开发者的实现建议

1. 语法解析

PIVOT 子句在 FROM 子句中，语法位置与 JOIN 平级：

```
table_ref:
    table_name
  | table_ref PIVOT '(' agg_func FOR column IN '(' value_list ')' ')' [AS alias]
  | table_ref UNPIVOT '(' value_column FOR name_column IN '(' column_list ')' ')' [AS alias]
```

2. PIVOT 的语义转换

PIVOT 本质上是语法糖，可以在 planner 阶段转换为等价的 GROUP BY + CASE WHEN：

```sql
-- 输入
SELECT * FROM t PIVOT (SUM(val) FOR cat IN ('A', 'B', 'C'));

-- 转换为
SELECT
    <implicit GROUP BY columns>,
    SUM(CASE WHEN cat = 'A' THEN val END) AS A,
    SUM(CASE WHEN cat = 'B' THEN val END) AS B,
    SUM(CASE WHEN cat = 'C' THEN val END) AS C
FROM t
GROUP BY <implicit GROUP BY columns>;
```

隐式 GROUP BY 列 = 原表的所有列 - PIVOT 值列 - PIVOT FOR 列。

3. UNPIVOT 的语义转换

UNPIVOT 可以转换为 CROSS JOIN LATERAL + VALUES：

```sql
-- 输入
SELECT * FROM t UNPIVOT (val FOR name IN (a, b, c));

-- 转换为
SELECT t.other_cols, u.name, u.val
FROM t CROSS JOIN LATERAL (
    VALUES ('a', t.a), ('b', t.b), ('c', t.c)
) AS u(name, val)
WHERE u.val IS NOT NULL;  -- 默认 EXCLUDE NULLS
```

4. 动态 PIVOT 的实现

如果要实现 Snowflake 的 `PIVOT ANY`：

1. **编译阶段**: 在优化前先执行一个 `SELECT DISTINCT pivot_column FROM source` 获取所有不同值
2. **动态生成**: 用这些值构建完整的 PIVOT 表达式
3. **类型系统**: 输出 schema 在编译时确定（所有动态列的类型 = 聚合函数的返回类型）

挑战: 这要求编译器在规划阶段执行一个子查询，打破了"规划不执行"的传统架构。

5. 性能优化

- **单次扫描**: PIVOT 的多个聚合应该在一次表扫描中完成（与分别执行多个查询相比）
- **稀疏优化**: 如果大部分单元格为 NULL（稀疏 PIVOT），考虑跳过空值的输出
- **内存**: PIVOT 结果集的宽度与不同值的数量成正比，需要限制最大列数

## 参考资料

- SQL Server: [PIVOT and UNPIVOT](https://learn.microsoft.com/en-us/sql/t-sql/queries/from-using-pivot-and-unpivot)
- Oracle: [PIVOT and UNPIVOT](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/SELECT.html#GUID-CFA006CA-6FF1-4972-821E-6996142A51C6)
- Snowflake: [PIVOT](https://docs.snowflake.com/en/sql-reference/constructs/pivot)
- DuckDB: [PIVOT](https://duckdb.org/docs/sql/statements/pivot)
- BigQuery: [PIVOT operator](https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#pivot_operator)
