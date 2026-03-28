# Hologres: CTE（公共表表达式，兼容 PostgreSQL 语法）

> 参考资料:
> - [Hologres SQL - SELECT (CTE)](https://help.aliyun.com/zh/hologres/user-guide/select)
> - [Hologres SQL Reference](https://help.aliyun.com/zh/hologres/user-guide/overview-27)


## 基本 CTE

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
enriched AS (
    SELECT b.*, COUNT(o.id) AS order_count
    FROM base b LEFT JOIN orders o ON b.id = o.user_id
    GROUP BY b.id, b.username, b.status, b.age, b.city
)
SELECT * FROM enriched WHERE order_count > 5;
```

## CTE + INSERT

```sql
INSERT INTO users_archive
WITH inactive AS (
    SELECT * FROM users WHERE last_login < '2023-01-01'
)
SELECT * FROM inactive;
```

## CTE + 联邦查询（内部表 + MaxCompute 外部表）

```sql
WITH mc_orders AS (
    SELECT user_id, SUM(amount) AS total
    FROM maxcompute_orders
    GROUP BY user_id
)
SELECT u.username, o.total
FROM hologres_users u
JOIN mc_orders o ON u.id = o.user_id;
```

注意：Hologres 兼容 PostgreSQL CTE 语法
注意：Hologres 不支持递归 CTE（WITH RECURSIVE）
注意：Hologres 不支持 MATERIALIZED / NOT MATERIALIZED 提示
注意：CTE 在 Hologres 中会被优化器内联处理
