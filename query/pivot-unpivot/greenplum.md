# Greenplum: PIVOT / UNPIVOT

> 参考资料:
> - [Greenplum Documentation - tablefunc](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-modules-tablefunc.html)
> - [Greenplum Documentation - Aggregate Functions](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-function-summary.html)


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


FILTER 子句（6.0+）
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


## PIVOT: crosstab（需要 tablefunc 扩展）

```sql
CREATE EXTENSION IF NOT EXISTS tablefunc;

SELECT * FROM crosstab(
    'SELECT product, quarter, SUM(amount)
     FROM sales
     GROUP BY product, quarter
     ORDER BY product, quarter',
    'SELECT DISTINCT quarter FROM sales ORDER BY quarter'
) AS ct(product text, Q1 numeric, Q2 numeric, Q3 numeric, Q4 numeric);
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


## UNPIVOT: LATERAL + VALUES（6.0+）

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


## UNPIVOT: unnest + array

```sql
SELECT
    product,
    unnest(ARRAY['Q1', 'Q2', 'Q3', 'Q4']) AS quarter,
    unnest(ARRAY[Q1, Q2, Q3, Q4]) AS amount
FROM quarterly_sales;
```


## 注意事项

Greenplum 兼容 PostgreSQL，支持 crosstab 和 FILTER 子句
MPP 架构下 PIVOT 操作可能触发数据重分布
crosstab 需要 tablefunc 扩展
LATERAL 从 6.0 开始支持
大数据量下建议用 CASE WHEN 方式（避免多次扫描）
