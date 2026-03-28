# Trino: 行列转换

> 参考资料:
> - [Trino Documentation - SELECT](https://trino.io/docs/current/sql/select.html)
> - [Trino Documentation - Aggregate Functions](https://trino.io/docs/current/functions/aggregate.html)
> - [Trino Documentation - Conditional Expressions](https://trino.io/docs/current/functions/conditional.html)

**引擎定位**: 分布式查询引擎（前身 Presto），不存储数据。通过 Connector 查询异构数据源（Hive/Iceberg/RDBMS）。

## 注意：Trino 没有原生 PIVOT / UNPIVOT 语法

使用 CASE WHEN + GROUP BY / FILTER 实现 PIVOT
使用 CROSS JOIN UNNEST / UNION ALL 实现 UNPIVOT
PIVOT: CASE WHEN + GROUP BY
```sql
    product,
    SUM(CASE WHEN quarter = 'Q1' THEN amount ELSE 0 END) AS Q1,
    SUM(CASE WHEN quarter = 'Q2' THEN amount ELSE 0 END) AS Q2,
    SUM(CASE WHEN quarter = 'Q3' THEN amount ELSE 0 END) AS Q3,
    SUM(CASE WHEN quarter = 'Q4' THEN amount ELSE 0 END) AS Q4
FROM sales
GROUP BY product;

```

FILTER 子句（更简洁）
```sql
SELECT
    product,
    SUM(amount) FILTER (WHERE quarter = 'Q1') AS Q1,
    SUM(amount) FILTER (WHERE quarter = 'Q2') AS Q2,
    SUM(amount) FILTER (WHERE quarter = 'Q3') AS Q3,
    SUM(amount) FILTER (WHERE quarter = 'Q4') AS Q4
FROM sales
GROUP BY product;

```

IF 函数
```sql
SELECT
    product,
    SUM(IF(quarter = 'Q1', amount, 0)) AS Q1,
    SUM(IF(quarter = 'Q2', amount, 0)) AS Q2,
    SUM(IF(quarter = 'Q3', amount, 0)) AS Q3,
    SUM(IF(quarter = 'Q4', amount, 0)) AS Q4
FROM sales
GROUP BY product;

```

## PIVOT: map_agg（Trino 特有，动态场景）

```sql
SELECT
    product,
    map_agg(quarter, total) AS quarter_totals
FROM (
    SELECT product, quarter, SUM(amount) AS total
    FROM sales
    GROUP BY product, quarter
) t
GROUP BY product;
```

结果：{Q1=100, Q2=200, ...}

## UNPIVOT: CROSS JOIN UNNEST

```sql
SELECT
    s.product,
    t.quarter,
    t.amount
FROM quarterly_sales s
CROSS JOIN UNNEST(
    ARRAY['Q1', 'Q2', 'Q3', 'Q4'],
    ARRAY[s.Q1, s.Q2, s.Q3, s.Q4]
) AS t(quarter, amount);

```

过滤 NULL
```sql
SELECT
    s.product,
    t.quarter,
    t.amount
FROM quarterly_sales s
CROSS JOIN UNNEST(
    ARRAY['Q1', 'Q2', 'Q3', 'Q4'],
    ARRAY[s.Q1, s.Q2, s.Q3, s.Q4]
) AS t(quarter, amount)
WHERE t.amount IS NOT NULL;

```

## UNPIVOT: UNION ALL

```sql
SELECT product, 'Q1' AS quarter, Q1 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q2' AS quarter, Q2 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q3' AS quarter, Q3 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q4' AS quarter, Q4 AS amount FROM quarterly_sales;

```

## 注意事项

Trino 没有原生 PIVOT/UNPIVOT 语法
FILTER 子句比 CASE WHEN 更简洁
CROSS JOIN UNNEST 是最佳的 UNPIVOT 方式
map_agg 适合动态 PIVOT 场景
支持跨数据源的 PIVOT/UNPIVOT 操作
