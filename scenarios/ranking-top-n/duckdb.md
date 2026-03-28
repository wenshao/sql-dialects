# DuckDB: TopN 排名查询

> 参考资料:
> - [DuckDB Documentation - Window Functions](https://duckdb.org/docs/sql/window_functions)
> - [DuckDB Documentation - QUALIFY](https://duckdb.org/docs/sql/query_syntax/qualify)
> - [DuckDB Documentation - LIMIT](https://duckdb.org/docs/sql/query_syntax/limit)

**引擎定位**: 嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法。

## 示例数据上下文

假设表结构:
  orders(order_id INTEGER, customer_id INTEGER, amount DECIMAL(10,2), order_date DATE)

## Top-N 整体


```sql
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
LIMIT 10;

SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
LIMIT 10 OFFSET 20;

```

FETCH FIRST（SQL 标准语法）
```sql
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
FETCH FIRST 10 ROWS ONLY;

```

## Top-N 分组 + QUALIFY（DuckDB 支持）


QUALIFY 直接过滤窗口函数结果
```sql
SELECT order_id, customer_id, amount, order_date
FROM orders
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY customer_id
    ORDER BY amount DESC
) <= 3;

```

QUALIFY + RANK
```sql
SELECT order_id, customer_id, amount, order_date
FROM orders
QUALIFY RANK() OVER (
    PARTITION BY customer_id
    ORDER BY amount DESC
) <= 3;

```

QUALIFY + DENSE_RANK
```sql
SELECT order_id, customer_id, amount, order_date
FROM orders
QUALIFY DENSE_RANK() OVER (
    PARTITION BY customer_id
    ORDER BY amount DESC
) <= 3;

```

## 传统子查询方式


```sql
SELECT *
FROM (
    SELECT order_id, customer_id, amount, order_date,
           ROW_NUMBER() OVER (
               PARTITION BY customer_id
               ORDER BY amount DESC
           ) AS rn
    FROM orders
) ranked
WHERE rn <= 3;

```

## LATERAL 子查询


```sql
SELECT c.customer_id, t.order_id, t.amount
FROM (SELECT DISTINCT customer_id FROM orders) c,
LATERAL (
    SELECT order_id, amount
    FROM orders o
    WHERE o.customer_id = c.customer_id
    ORDER BY amount DESC
    LIMIT 3
) t;

```

## DuckDB 特色：直接从文件查询 Top-N


从 Parquet 文件直接查询
```sql
SELECT *
FROM read_parquet('orders.parquet')
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY customer_id
    ORDER BY amount DESC
) <= 3;

```

从 CSV 文件直接查询
```sql
SELECT *
FROM read_csv_auto('orders.csv')
ORDER BY amount DESC
LIMIT 10;

```

## 关联子查询方式


```sql
SELECT o.*
FROM orders o
WHERE (
    SELECT COUNT(*)
    FROM orders o2
    WHERE o2.customer_id = o.customer_id
      AND o2.amount > o.amount
) < 3
ORDER BY o.customer_id, o.amount DESC;

```

## 性能考量


DuckDB 是列式内存数据库，自动向量化执行
QUALIFY 是推荐的方式，语法简洁
DuckDB 支持 LATERAL 子查询
无需手动创建索引（自动 ART 索引和 min/max 索引）
直接从 Parquet 文件 Top-N 查询效率极高（列裁剪）
