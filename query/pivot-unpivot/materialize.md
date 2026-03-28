# Materialize: PIVOT / UNPIVOT

> 参考资料:
> - [Materialize Documentation - SELECT](https://materialize.com/docs/sql/select/)
> - [Materialize Documentation - Functions](https://materialize.com/docs/sql/functions/)


## 注意：Materialize 没有原生 PIVOT / UNPIVOT 语法

兼容 PostgreSQL，使用 CASE WHEN + GROUP BY / LATERAL 实现


## PIVOT: CASE WHEN + GROUP BY

```sql
SELECT
    product,
    SUM(CASE WHEN quarter = 'Q1' THEN amount ELSE 0 END) AS Q1,
    SUM(CASE WHEN quarter = 'Q2' THEN amount ELSE 0 END) AS Q2,
    SUM(CASE WHEN quarter = 'Q3' THEN amount ELSE 0 END) AS Q3,
    SUM(CASE WHEN quarter = 'Q4' THEN amount ELSE 0 END) AS Q4
FROM sales
GROUP BY product;
```

## FILTER 子句

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

## UNPIVOT: LATERAL + VALUES

```sql
SELECT s.product, v.quarter, v.amount
FROM quarterly_sales s
CROSS JOIN LATERAL (
    VALUES
        ('Q1', s.Q1),
        ('Q2', s.Q2),
        ('Q3', s.Q3),
        ('Q4', s.Q4)
) AS v(quarter, amount);
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

## 在物化视图中使用 PIVOT

```sql
CREATE MATERIALIZED VIEW sales_pivot AS
SELECT
    product,
    SUM(CASE WHEN quarter = 'Q1' THEN amount ELSE 0 END) AS Q1,
    SUM(CASE WHEN quarter = 'Q2' THEN amount ELSE 0 END) AS Q2,
    SUM(CASE WHEN quarter = 'Q3' THEN amount ELSE 0 END) AS Q3,
    SUM(CASE WHEN quarter = 'Q4' THEN amount ELSE 0 END) AS Q4
FROM sales
GROUP BY product;
```

## 注意事项

Materialize 兼容 PostgreSQL，但不支持 tablefunc 扩展（无 crosstab）
FILTER 子句比 CASE WHEN 更简洁
PIVOT 查询可直接用于物化视图定义
增量计算使得物化视图中的 PIVOT 高效更新
