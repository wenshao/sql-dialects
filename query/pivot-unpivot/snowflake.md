# Snowflake: PIVOT / UNPIVOT

> 参考资料:
> - [1] Snowflake SQL Reference - PIVOT
>   https://docs.snowflake.com/en/sql-reference/constructs/pivot
> - [2] Snowflake SQL Reference - UNPIVOT
>   https://docs.snowflake.com/en/sql-reference/constructs/unpivot


## 1. PIVOT 基本语法


```sql
SELECT * FROM (
    SELECT product, quarter, amount FROM sales
)
PIVOT (SUM(amount) FOR quarter IN ('Q1', 'Q2', 'Q3', 'Q4')) AS pvt;

```

指定列别名

```sql
SELECT * FROM (
    SELECT product, quarter, amount FROM sales
)
PIVOT (SUM(amount) FOR quarter IN ('Q1', 'Q2', 'Q3', 'Q4'))
    AS pvt (product, Q1, Q2, Q3, Q4);

```

## 2. 语法设计分析（对 SQL 引擎开发者）


### 2.1 动态 PIVOT: Snowflake 的独有特性

传统 PIVOT 需要预先列举所有值（静态）:
FOR quarter IN ('Q1', 'Q2', 'Q3', 'Q4')  -- 必须硬编码
Snowflake 支持动态 PIVOT:

```sql
SELECT * FROM (
    SELECT product, quarter, amount FROM sales
)
PIVOT (SUM(amount) FOR quarter IN (ANY ORDER BY quarter)) AS pvt;

```

使用子查询指定 IN 值:

```sql
SELECT * FROM (
    SELECT product, quarter, amount FROM sales
)
PIVOT (SUM(amount) FOR quarter IN (
    SELECT DISTINCT quarter FROM sales ORDER BY quarter
)) AS pvt;

```

 动态 PIVOT 的设计意义:
   传统 PIVOT（MySQL/PG 不支持原生 PIVOT，Oracle/SQL Server 需硬编码值）
   是数据分析中的主要痛点: 值集合未知时必须用动态 SQL 生成。
   Snowflake 的 ANY 和子查询方式解决了这个问题。

 对比:
   Oracle:     PIVOT（需硬编码 IN 列表，动态需 PL/SQL）
   SQL Server: PIVOT（需硬编码，动态需 sp_executesql）
   PostgreSQL: 不支持原生 PIVOT（用 crosstab 或 CASE WHEN）
   MySQL:      不支持原生 PIVOT（只能用 CASE WHEN）
   BigQuery:   PIVOT（需硬编码值）

 对引擎开发者的启示:
   动态 PIVOT 需要在执行时确定输出列数和列名，
   这对查询编译器是挑战（输出 schema 不是编译时确定的）。
   Snowflake 的实现可能是: 先执行子查询获取值集 → 编译 PIVOT → 执行。

## 3. CASE WHEN / IFF 替代方案


通用替代（所有数据库都支持）:

```sql
SELECT product,
    SUM(IFF(quarter = 'Q1', amount, 0)) AS Q1,
    SUM(IFF(quarter = 'Q2', amount, 0)) AS Q2,
    SUM(IFF(quarter = 'Q3', amount, 0)) AS Q3,
    SUM(IFF(quarter = 'Q4', amount, 0)) AS Q4
FROM sales GROUP BY product;

```

## 4. UNPIVOT


```sql
SELECT * FROM quarterly_sales
UNPIVOT (amount FOR quarter IN (Q1, Q2, Q3, Q4));

```

自定义列值名称:

```sql
SELECT * FROM quarterly_sales
UNPIVOT (amount FOR quarter IN (
    Q1 AS 'First Quarter', Q2 AS 'Second Quarter',
    Q3 AS 'Third Quarter', Q4 AS 'Fourth Quarter'));

```

UNION ALL 替代方案:

```sql
SELECT product, 'Q1' AS quarter, Q1 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q2', Q2 FROM quarterly_sales
UNION ALL
SELECT product, 'Q3', Q3 FROM quarterly_sales
UNION ALL
SELECT product, 'Q4', Q4 FROM quarterly_sales;

```

FLATTEN 替代方案（Snowflake 特有，适合半结构化数据）:

```sql
SELECT s.product, f.value:quarter::VARCHAR AS quarter, f.value:amount::NUMBER AS amount
FROM quarterly_sales s,
    LATERAL FLATTEN(input => ARRAY_CONSTRUCT(
        OBJECT_CONSTRUCT('quarter', 'Q1', 'amount', s.Q1),
        OBJECT_CONSTRUCT('quarter', 'Q2', 'amount', s.Q2),
        OBJECT_CONSTRUCT('quarter', 'Q3', 'amount', s.Q3),
        OBJECT_CONSTRUCT('quarter', 'Q4', 'amount', s.Q4)
    )) f;

```

## 横向对比: PIVOT 能力矩阵

| 能力            | Snowflake    | BigQuery  | PostgreSQL | MySQL  | Oracle |
|------|------|------|------|------|------|
| PIVOT 原生      | 支持         | 支持      | 不支持     | 不支持 | 支持 |
| 动态 PIVOT(ANY) | 独有         | 不支持    | N/A        | N/A    | 不支持 |
| UNPIVOT 原生    | 支持         | 支持      | 不支持     | 不支持 | 支持 |
| 多聚合 PIVOT    | 不支持       | 不支持    | N/A        | N/A    | 不支持 |
| FLATTEN UNPIVOT | 独有         | UNNEST    | unnest     | 不支持 | 不支持 |

