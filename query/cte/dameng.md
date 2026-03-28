# DamengDB (达梦): CTE（公共表表达式）

Oracle compatible syntax.

> 参考资料:
> - [DamengDB SQL Reference](https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html)
> - [DamengDB System Admin Manual](https://eco.dameng.com/document/dm/zh-cn/pm/index.html)


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
enriched AS (SELECT b.*, COUNT(o.id) AS order_count FROM base b LEFT JOIN orders o ON b.id = o.user_id GROUP BY b.id)
SELECT * FROM enriched WHERE order_count > 5;
```

## 递归 CTE

```sql
WITH RECURSIVE nums AS (
    SELECT 1 AS n FROM DUAL
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

## Oracle 风格的层级查询（CONNECT BY）

```sql
SELECT id, username, manager_id, LEVEL
FROM users
START WITH manager_id IS NULL
CONNECT BY PRIOR id = manager_id
ORDER SIBLINGS BY username;
```

## CONNECT BY 相关伪列

```sql
SELECT id, username,
    LEVEL,
    SYS_CONNECT_BY_PATH(username, '/') AS path,
    CONNECT_BY_ROOT username AS root_user,
    CONNECT_BY_ISLEAF AS is_leaf
FROM users
START WITH manager_id IS NULL
CONNECT BY PRIOR id = manager_id;
```

## CTE 用于 DML

```sql
WITH inactive AS (
    SELECT id FROM users WHERE last_login < DATE '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);
```

注意事项：
支持 Oracle 的 CONNECT BY 层级查询语法
支持 SQL 标准的递归 CTE
SYS_CONNECT_BY_PATH、CONNECT_BY_ROOT 等伪列可用
ORDER SIBLINGS BY 控制同级排序
