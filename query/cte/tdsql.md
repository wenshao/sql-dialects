# TDSQL: CTE（公共表表达式）

TDSQL distributed MySQL 8.0 compatible.

> 参考资料:
> - [TDSQL-C MySQL Documentation](https://cloud.tencent.com/document/product/1003)
> - [TDSQL MySQL Documentation](https://cloud.tencent.com/document/product/557)
> - 基本 CTE

```sql
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users WHERE age > 25;
```

## 多个 CTE

```sql
WITH
active_users AS (
    SELECT * FROM users WHERE status = 1
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
base AS (SELECT * FROM users WHERE status = 1),
enriched AS (SELECT b.*, COUNT(o.id) AS order_count FROM base b LEFT JOIN orders o ON b.id = o.user_id GROUP BY b.id)
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

## CTE 用于 DML

```sql
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);
```

递归深度限制
SET cte_max_recursion_depth = 1000;
注意事项：
CTE 在分布式环境下需要跨分片合并数据
递归 CTE 的每次迭代可能涉及跨分片查询
CTE 的性能取决于涉及的分片数量
