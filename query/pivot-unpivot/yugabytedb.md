# YugabyteDB: 行列转换

> 参考资料:
> - [YugabyteDB Documentation - SELECT](https://docs.yugabyte.com/preview/api/ysql/the-sql-language/statements/dml_select/)
> - [YugabyteDB Documentation - Aggregate Functions](https://docs.yugabyte.com/preview/api/ysql/exprs/aggregate_functions/)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识。

## 注意：YugabyteDB 没有原生 PIVOT / UNPIVOT 语法

兼容 PostgreSQL，使用 CASE WHEN + GROUP BY / LATERAL 实现
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

FILTER 子句
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

## 注意事项

YugabyteDB YSQL 兼容 PostgreSQL，支持 crosstab 和 FILTER
分布式环境下 PIVOT 聚合可能涉及跨节点数据传输
tablefunc 扩展需要单独安装
FILTER 子句比 CASE WHEN 更简洁高效
