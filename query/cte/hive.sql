-- Hive: CTE（公共表表达式，0.13+）
--
-- 参考资料:
--   [1] Apache Hive Language Manual - CTE
--       https://cwiki.apache.org/confluence/display/Hive/Common+Table+Expression
--   [2] Apache Hive Language Manual - SELECT
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Select

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

-- CTE + LATERAL VIEW
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT u.username, tag
FROM active_users u
LATERAL VIEW EXPLODE(u.tags) t AS tag;

-- CTE + INSERT（Hive 特有的多路插入）
WITH source AS (
    SELECT * FROM users WHERE status = 1
)
INSERT INTO TABLE active_users_backup
SELECT * FROM source;

-- CTE + MAPJOIN hint
WITH small_table AS (
    SELECT * FROM roles WHERE active = 1
)
SELECT /*+ MAPJOIN(s) */ u.username, s.role_name
FROM users u
JOIN small_table s ON u.role_id = s.id;

-- 注意：Hive 0.13 引入 CTE，之前版本需使用子查询代替
-- 注意：Hive 不支持递归 CTE（WITH RECURSIVE）
-- 注意：Hive CTE 在每次引用时会被展开（非物化），多次引用可能导致重复计算
-- 注意：Hive CTE 不支持用于 UPDATE / DELETE 语句
