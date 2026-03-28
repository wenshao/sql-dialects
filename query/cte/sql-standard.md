# SQL 标准: CTE 公共表表达式

> 参考资料:
> - [ISO/IEC 9075 SQL Standard](https://www.iso.org/standard/76583.html)
> - [Modern SQL - by Markus Winand](https://modern-sql.com/)
> - [Modern SQL - WITH Clause (CTE)](https://modern-sql.com/feature/with)

## SQL:1999 (SQL3)

首次引入 WITH 子句和递归查询

基本 CTE
```sql
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users WHERE age > 25;
```

多个 CTE
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

CTE 引用前面的 CTE
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

递归 CTE（WITH RECURSIVE）
```sql
WITH RECURSIVE nums(n) AS (
    VALUES (1)
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 10
)
SELECT n FROM nums;
```

递归：层级结构
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

## SQL:1999 递归语义

UNION ALL: 允许重复行（常用）
UNION: 不允许重复行（也可用于递归，但少见）

## SQL:2011

SEARCH 子句（控制递归遍历顺序）
```sql
WITH RECURSIVE org_tree AS (
    SELECT id, username, manager_id
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SEARCH DEPTH FIRST BY id SET ordercol
SELECT * FROM org_tree ORDER BY ordercol;
```

CYCLE 子句（检测循环）
```sql
WITH RECURSIVE org_tree AS (
    SELECT id, username, manager_id
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
CYCLE id SET is_cycle USING path
SELECT * FROM org_tree WHERE NOT is_cycle;
```

搜索模式：
SEARCH DEPTH FIRST BY col SET ordercol: 深度优先
SEARCH BREADTH FIRST BY col SET ordercol: 广度优先

## 各标准版本 CTE 特性总结

SQL:1999: WITH, WITH RECURSIVE, UNION/UNION ALL
SQL:2011: SEARCH (DEPTH/BREADTH FIRST), CYCLE
- **注意：MATERIALIZED / NOT MATERIALIZED 不在 SQL 标准中，是 PostgreSQL 扩展**
- **注意：可写 CTE（WITH ... DELETE/UPDATE/INSERT ... RETURNING）也不在标准中**
