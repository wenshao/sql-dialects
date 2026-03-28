# Materialize: CTE（公共表表达式）

> 参考资料:
> - [Materialize SQL Reference](https://materialize.com/docs/sql/)
> - [Materialize SQL Functions](https://materialize.com/docs/sql/functions/)
> - Materialize 支持 CTE（兼容 PostgreSQL）
> - 基本 CTE

```sql
WITH active_users AS (
    SELECT * FROM users WHERE status = 'active'
)
SELECT * FROM active_users WHERE age > 25;
```

## 多个 CTE

```sql
WITH
active_users AS (
    SELECT * FROM users WHERE status = 'active'
),
user_orders AS (
    SELECT user_id, COUNT(*) AS cnt, SUM(amount) AS total
    FROM orders GROUP BY user_id
)
SELECT u.username, o.cnt, o.total
FROM active_users u
JOIN user_orders o ON u.id = o.user_id;
```

## CTE 引用前面的 CTE

```sql
WITH
base AS (SELECT * FROM users WHERE status = 'active'),
enriched AS (
    SELECT b.*, COUNT(o.id) AS order_count
    FROM base b LEFT JOIN orders o ON b.id = o.user_id
    GROUP BY b.id, b.username, b.status, b.age, b.city
)
SELECT * FROM enriched WHERE order_count > 5;
```

## 递归 CTE

```sql
WITH RECURSIVE nums AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 10
)
SELECT n FROM nums;
```

## 递归：层级结构

```sql
WITH RECURSIVE org_tree AS (
    SELECT id, username, manager_id, 0 AS level
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, t.level + 1
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SELECT * FROM org_tree;
```

## 物化视图中的 CTE


## CTE 可以在 CREATE MATERIALIZED VIEW 中使用

```sql
CREATE MATERIALIZED VIEW top_customers AS
WITH customer_totals AS (
    SELECT user_id, SUM(amount) AS total
    FROM orders GROUP BY user_id
)
SELECT u.username, c.total
FROM customer_totals c
JOIN users u ON c.user_id = u.id
WHERE c.total > 1000;
```

## CTE + 窗口函数

```sql
CREATE MATERIALIZED VIEW ranked_customers AS
WITH customer_stats AS (
    SELECT user_id, COUNT(*) AS cnt, SUM(amount) AS total
    FROM orders GROUP BY user_id
)
SELECT u.username, cs.total,
    RANK() OVER (ORDER BY cs.total DESC) AS rank
FROM customer_stats cs
JOIN users u ON cs.user_id = u.id;
```

注意：Materialize 支持标准 CTE 和递归 CTE
注意：CTE 可以在物化视图定义中使用
注意：CTE 在物化视图中会被增量维护
注意：兼容 PostgreSQL 的 CTE 语法
