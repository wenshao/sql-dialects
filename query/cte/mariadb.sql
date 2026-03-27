-- MariaDB: CTE (Common Table Expressions, 10.2.1+)
-- MariaDB is a MySQL fork; only differences from MySQL are shown here.
-- MariaDB added CTEs in 10.2.1, earlier than MySQL 8.0.
--
-- 参考资料:
--   [1] MariaDB Knowledge Base
--       https://mariadb.com/kb/en/documentation/
--   [2] MariaDB vs MySQL Compatibility
--       https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/

-- Basic CTE (same as MySQL 8.0)
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users WHERE age > 25;

-- Multiple CTEs (same as MySQL 8.0)
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

-- Recursive CTE (10.2.2+)
WITH RECURSIVE nums AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 10
)
SELECT n FROM nums;

-- Recursive hierarchy (same as MySQL 8.0)
WITH RECURSIVE org_tree AS (
    SELECT id, username, manager_id, 0 AS level,
           CAST(username AS CHAR(500)) AS path
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, t.level + 1,
           CONCAT(t.path, ' > ', u.username)
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SELECT * FROM org_tree ORDER BY path;

-- CTE with DML (10.2.1+)
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);

-- CTE with UPDATE
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users SET status = 2 WHERE id IN (SELECT user_id FROM vip);

-- CTE with INSERT
WITH new_data AS (
    SELECT username, email, age FROM temp_import WHERE valid = 1
)
INSERT INTO users (username, email, age)
SELECT * FROM new_data;

-- Recursion depth limit
SET max_recursive_iterations = 1000;  -- MariaDB-specific variable name
-- MySQL uses cte_max_recursion_depth; MariaDB uses max_recursive_iterations

-- CTE optimization: MariaDB may materialize or merge CTEs
-- Non-recursive CTEs referenced once are typically merged (inlined)
-- Non-recursive CTEs referenced multiple times are materialized

-- Recursive CTE with CYCLE detection (10.5.2+)
-- MariaDB added CYCLE clause to detect infinite recursion
WITH RECURSIVE org_tree AS (
    SELECT id, username, manager_id, 0 AS level
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, t.level + 1
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
CYCLE id RESTRICT
SELECT * FROM org_tree;
-- CYCLE id RESTRICT prevents infinite loops by tracking visited id values

-- Differences from MySQL 8.0:
-- CTEs available since 10.2.1 (earlier than MySQL 8.0)
-- max_recursive_iterations instead of cte_max_recursion_depth
-- CYCLE ... RESTRICT clause for recursion cycle detection (10.5.2+)
-- Generally same CTE semantics and capabilities
-- CTE merge/materialize decisions may differ from MySQL
