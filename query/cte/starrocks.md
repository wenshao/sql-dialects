# StarRocks: CTE

> 参考资料:
> - [1] StarRocks Documentation - WITH
>   https://docs.starrocks.io/docs/sql-reference/sql-statements/


## 1. 基本 CTE (与 Doris 相同)

```sql
WITH active_users AS (SELECT * FROM users WHERE status = 1)
SELECT * FROM active_users WHERE age > 25;

WITH active AS (SELECT * FROM users WHERE status = 1),
user_orders AS (SELECT user_id, COUNT(*) AS cnt FROM orders GROUP BY user_id)
SELECT u.username, o.cnt FROM active u JOIN user_orders o ON u.id = o.user_id;

```

## 2. 递归 CTE

```sql
WITH RECURSIVE nums AS (
    SELECT 1 AS n UNION ALL SELECT n + 1 FROM nums WHERE n < 10
)
SELECT n FROM nums;

WITH RECURSIVE org_tree AS (
    SELECT id, username, manager_id, 0 AS level FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, t.level + 1
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SELECT * FROM org_tree;

```

## 3. CTE + DML / 窗口函数

```sql
INSERT INTO users_archive
WITH inactive AS (SELECT * FROM users WHERE last_login < '2023-01-01')
SELECT * FROM inactive;

```

CTE 在 CBO 优化器中的处理:
StarRocks CBO 可以将 CTE 内联或物化，根据引用次数和成本决定。
多次引用的 CTE → 物化(避免重复计算)
单次引用的 CTE → 内联(减少中间结果开销)

