# SQL Server: 排名与 Top-N

> 参考资料:
> - [SQL Server - TOP / CROSS APPLY](https://learn.microsoft.com/en-us/sql/t-sql/queries/top-transact-sql)

## 全局 Top-N

```sql
SELECT TOP 10 order_id, customer_id, amount FROM orders ORDER BY amount DESC;
```

TOP WITH TIES（包含并列行）
```sql
SELECT TOP 10 WITH TIES order_id, amount FROM orders ORDER BY amount DESC;
```

TOP PERCENT
```sql
SELECT TOP 10 PERCENT order_id, amount FROM orders ORDER BY amount DESC;
```

OFFSET-FETCH（2012+ 标准语法）
```sql
SELECT order_id, amount FROM orders ORDER BY amount DESC
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;
```

## 分组 Top-N: ROW_NUMBER 方法

```sql
SELECT * FROM (
    SELECT order_id, customer_id, amount,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY amount DESC) AS rn
    FROM orders
) ranked WHERE rn <= 3;
```

RANK（含并列）vs DENSE_RANK
```sql
SELECT * FROM (
    SELECT *, RANK() OVER (PARTITION BY customer_id ORDER BY amount DESC) AS rnk
    FROM orders
) ranked WHERE rnk <= 3;
```

## CROSS APPLY: SQL Server 最高效的分组 Top-N

每个客户的前 3 笔最大订单
```sql
SELECT c.customer_id, t.order_id, t.amount
FROM (SELECT DISTINCT customer_id FROM orders) c
CROSS APPLY (
    SELECT TOP 3 order_id, amount
    FROM orders o WHERE o.customer_id = c.customer_id
    ORDER BY amount DESC
) t;
```

设计分析（对引擎开发者）:
  CROSS APPLY + TOP 是 SQL Server 分组 Top-N 的最优方案:
  如果 (customer_id, amount DESC) 上有索引，每组只需 3 次 Index Seek。
  总代价 = 客户数 × 3 次 Seek（远优于 ROW_NUMBER 的全表扫描 + 排序）。

  ROW_NUMBER 方法: 需要全表扫描 → 排序 → 过滤（O(n log n)）
  CROSS APPLY 方法: 每组 Index Seek（O(m × log n)，m = 组数）

横向对比:
  PostgreSQL: LATERAL JOIN + LIMIT（语义等价）
  MySQL:      8.0.14+ LATERAL JOIN + LIMIT
  Oracle:     12c+ CROSS APPLY 或 LATERAL

对引擎开发者的启示:
  分组 Top-N 是一个频率极高的查询模式。
  引擎优化器应该能自动将 ROW_NUMBER + filter 转换为 per-group index seek。
  SQL Server 的优化器有时会做这个转换（Top N Sort），但不总是。

OUTER APPLY（包含没有订单的客户）
```sql
SELECT c.customer_id, c.name, t.order_id, t.amount
FROM customers c
OUTER APPLY (
    SELECT TOP 3 order_id, amount FROM orders o
    WHERE o.customer_id = c.customer_id ORDER BY amount DESC
) t;
```

## CTE + 窗口函数（最常见的写法）

```sql
;WITH ranked_orders AS (
    SELECT order_id, customer_id, amount,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY amount DESC) AS rn
    FROM orders
)
SELECT order_id, customer_id, amount FROM ranked_orders WHERE rn <= 3;
```

## 关联子查询方式（兼容旧版本）

```sql
SELECT o.* FROM orders o
WHERE (SELECT COUNT(*) FROM orders o2
       WHERE o2.customer_id = o.customer_id AND o2.amount > o.amount) < 3
ORDER BY o.customer_id, o.amount DESC;
```

## 性能优化

推荐索引（覆盖分组 Top-N 查询）
```sql
CREATE INDEX ix_orders_customer_amount
ON orders (customer_id, amount DESC) INCLUDE (order_id);
```

CROSS APPLY + TOP + 上述索引 = 最优方案
ROW_NUMBER 在无索引时需要全表排序
TOP WITH TIES 适用于全局排名（不适用于分组）
