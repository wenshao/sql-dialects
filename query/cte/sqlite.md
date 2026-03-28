# SQLite: CTE 公共表表达式

> 参考资料:
> - [SQLite Documentation - WITH (CTE)](https://www.sqlite.org/lang_with.html)

## 基本 CTE

```sql
WITH active_users AS (
    SELECT id, username, email FROM users WHERE status = 1
)
SELECT u.username, COUNT(o.id) AS order_count
FROM active_users u
LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.username;
```

多个 CTE
```sql
WITH
    active_users AS (SELECT * FROM users WHERE status = 1),
    recent_orders AS (SELECT * FROM orders WHERE order_date >= '2024-01-01')
SELECT u.username, SUM(o.amount) AS total
FROM active_users u
JOIN recent_orders o ON u.id = o.user_id
GROUP BY u.username;
```

## 递归 CTE（3.8.3+，SQLite 的强项）

数列生成
```sql
WITH RECURSIVE cnt(x) AS (
    SELECT 1
    UNION ALL
    SELECT x + 1 FROM cnt WHERE x < 100
)
SELECT x FROM cnt;
```

层级遍历（组织架构树）
```sql
WITH RECURSIVE org_tree AS (
    SELECT id, name, manager_id, 0 AS depth
    FROM employees WHERE manager_id IS NULL        -- 根节点
    UNION ALL
    SELECT e.id, e.name, e.manager_id, t.depth + 1
    FROM employees e
    JOIN org_tree t ON e.manager_id = t.id         -- 递归展开
)
SELECT * FROM org_tree;
```

日期序列
```sql
WITH RECURSIVE dates(d) AS (
    SELECT '2024-01-01'
    UNION ALL
    SELECT date(d, '+1 day') FROM dates WHERE d < '2024-01-31'
)
SELECT d FROM dates;
```

## CTE 的实现细节（对引擎开发者）

SQLite 的 CTE 默认是"物化的"（materialized）:
  CTE 查询结果存储在临时表中，每次引用直接读临时表。
  对比 PostgreSQL 12+: 默认内联（优化器可能合并 CTE 和外部查询）

这意味着:
  优点: 多次引用同一 CTE 不重复计算
  缺点: 优化器不能将 CTE 的 WHERE 条件下推

3.35.0+: MATERIALIZED / NOT MATERIALIZED 提示
WITH active AS MATERIALIZED (...)        -- 强制物化
WITH active AS NOT MATERIALIZED (...)    -- 强制内联

递归 CTE 的深度限制:
SQLITE_MAX_RECURSIVE_CTE_DEPTH = 1000000（默认）
可通过 sqlite3_limit() 调整

## CTE 在 INSERT/UPDATE/DELETE 中的使用

CTE + INSERT（3.8.3+）
```sql
WITH new_users AS (SELECT 'alice' AS name UNION ALL SELECT 'bob')
INSERT INTO users (username) SELECT name FROM new_users;
```

CTE + UPDATE（3.33.0+）
```sql
WITH vip AS (SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000)
UPDATE users SET status = 2 WHERE id IN (SELECT user_id FROM vip);
```

CTE + DELETE（3.35.0+）
```sql
WITH inactive AS (SELECT id FROM users WHERE last_login < '2023-01-01')
DELETE FROM users WHERE id IN (SELECT id FROM inactive);
```

## 对比与引擎开发者启示

SQLite CTE 的特点:
  (1) 默认物化 → 多次引用不重复计算但无法优化下推
  (2) 3.35.0+ MATERIALIZED 提示 → 用户控制物化策略
  (3) 递归 CTE → 日期序列、层级查询、图遍历
  (4) CTE 在 DML 中 → INSERT/UPDATE/DELETE 都支持

对引擎开发者的启示:
  CTE 物化策略（物化 vs 内联）是重要的优化器决策。
  默认物化简单安全，但牺牲了优化机会。
  现代引擎应该由优化器自动决定（如 PostgreSQL 12+）。
