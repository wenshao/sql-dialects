# Hologres: PIVOT / UNPIVOT

> 参考资料:
> - [Hologres Documentation - SELECT](https://help.aliyun.com/zh/hologres/user-guide/select)
> - [Hologres Documentation - SQL Reference](https://help.aliyun.com/zh/hologres/user-guide/)


## PIVOT: CASE WHEN + GROUP BY（兼容 PostgreSQL 11）

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
    VALUES ('Q1', s.Q1), ('Q2', s.Q2), ('Q3', s.Q3), ('Q4', s.Q4)
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

## UNPIVOT: unnest + array

```sql
SELECT
    product,
    unnest(ARRAY['Q1', 'Q2', 'Q3', 'Q4']) AS quarter,
    unnest(ARRAY[Q1, Q2, Q3, Q4]) AS amount
FROM quarterly_sales;
```

## 注意事项

Hologres 兼容 PostgreSQL 11 语法
支持 FILTER 子句和 LATERAL + VALUES
列存表上的聚合操作性能优异
不支持 tablefunc 扩展（无 crosstab）
动态 PIVOT 需在应用层构建 SQL
