# CockroachDB: 行列转换

> 参考资料:
> - [CockroachDB Documentation - SELECT](https://www.cockroachlabs.com/docs/stable/select-clause)
> - [CockroachDB Documentation - Aggregate Functions](https://www.cockroachlabs.com/docs/stable/functions-and-operators#aggregate-functions)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning。

## 注意：CockroachDB 没有原生 PIVOT / UNPIVOT 语法

使用 CASE WHEN + GROUP BY / FILTER 实现 PIVOT
使用 LATERAL + VALUES / UNION ALL 实现 UNPIVOT
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

## UNPIVOT: LATERAL + VALUES（推荐）

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

CockroachDB 兼容 PostgreSQL，但没有 crosstab（不支持 tablefunc 扩展）
FILTER 子句比 CASE WHEN 更简洁
LATERAL + VALUES 是最优雅的 UNPIVOT 方式
动态 PIVOT 需要在应用层构建 SQL
