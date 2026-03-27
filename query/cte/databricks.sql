-- Databricks SQL: CTE（公共表表达式）
--
-- 参考资料:
--   [1] Databricks SQL Language Reference
--       https://docs.databricks.com/en/sql/language-manual/index.html
--   [2] Databricks SQL - Built-in Functions
--       https://docs.databricks.com/en/sql/language-manual/sql-ref-functions-builtin.html
--   [3] Delta Lake Documentation
--       https://docs.delta.io/latest/index.html

-- 基本 CTE
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users WHERE age > 25;

-- 多个 CTE
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

-- CTE 引用前面的 CTE
WITH
base AS (SELECT * FROM users WHERE status = 1),
enriched AS (
    SELECT b.*, COUNT(o.id) AS order_count
    FROM base b LEFT JOIN orders o ON b.id = o.user_id
    GROUP BY b.id, b.username, b.status, b.age, b.city
)
SELECT * FROM enriched WHERE order_count > 5;

-- 递归 CTE
WITH RECURSIVE nums AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 10
)
SELECT n FROM nums;

-- 递归：层级结构
WITH RECURSIVE org_tree AS (
    SELECT id, username, manager_id, 0 AS level,
           CAST(username AS STRING) AS path
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, t.level + 1,
           CONCAT(t.path, ' > ', u.username)
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SELECT * FROM org_tree;

-- CTE + CTAS
CREATE OR REPLACE TABLE users_archive AS
WITH inactive AS (
    SELECT * FROM users WHERE last_login < '2023-01-01'
)
SELECT * FROM inactive;

-- CTE + INSERT
WITH new_data AS (
    SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age
)
INSERT INTO users (username, email, age)
SELECT username, email, age FROM new_data;

-- CTE + MERGE
WITH updates AS (
    SELECT username, email, age FROM staging_users
)
MERGE INTO users AS t
USING updates AS s
ON t.username = s.username
WHEN MATCHED THEN UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- CTE + QUALIFY
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users
QUALIFY ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) = 1;

-- CTE + 数组操作
WITH expanded AS (
    SELECT username, EXPLODE(tags) AS tag
    FROM users
)
SELECT tag, COUNT(*) AS cnt FROM expanded GROUP BY tag ORDER BY cnt DESC;

-- CTE + Time Travel
WITH current_data AS (
    SELECT * FROM users
),
old_data AS (
    SELECT * FROM users VERSION AS OF 5
)
SELECT c.username, c.email AS current_email, o.email AS old_email
FROM current_data c
JOIN old_data o ON c.id = o.id
WHERE c.email != o.email;

-- 多层 CTE 分析
WITH
daily_sales AS (
    SELECT order_date, SUM(amount) AS daily_total
    FROM orders GROUP BY order_date
),
weekly_avg AS (
    SELECT order_date, daily_total,
        AVG(daily_total) OVER (ORDER BY order_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS avg_7day
    FROM daily_sales
)
SELECT * FROM weekly_avg WHERE daily_total > avg_7day * 1.5;

-- 注意：Databricks 支持递归 CTE（需要 RECURSIVE 关键字）
-- 注意：CTE 默认内联（优化器自行决策是否物化）
-- 注意：CTE + Time Travel 可以比较不同版本的数据
-- 注意：CTE 可以与 MERGE INTO 一起使用
-- 注意：CTE 中可以使用 EXPLODE 和其他 Spark SQL 函数
