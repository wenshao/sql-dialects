-- Snowflake: 子查询
--
-- 参考资料:
--   [1] Snowflake SQL Reference - Subqueries
--       https://docs.snowflake.com/en/sql-reference/operators-subquery
--   [2] Snowflake SQL Reference - SELECT
--       https://docs.snowflake.com/en/sql-reference/sql/select

-- 标量子查询
SELECT username, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;

-- WHERE 子查询
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blacklist);

-- EXISTS
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- 比较运算符 + 子查询
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);
SELECT * FROM users WHERE age >= ALL (SELECT age FROM users WHERE city = 'Beijing');
SELECT * FROM users WHERE age > ANY (SELECT age FROM users WHERE city = 'Beijing');

-- FROM 子查询
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- LATERAL 子查询（子查询可以引用外部表的列）
SELECT u.username, t.total
FROM users u,
LATERAL (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;

-- 行子查询
SELECT * FROM users WHERE (city, age) IN (SELECT city, MIN(age) FROM users GROUP BY city);

-- FLATTEN 子查询（展开半结构化数据）
SELECT u.username, f.value::STRING AS tag
FROM users u,
LATERAL FLATTEN(input => u.tags) f
WHERE f.value::STRING IN (SELECT tag_name FROM popular_tags);

-- 关联子查询
SELECT u.username,
    (SELECT MAX(amount) FROM orders o WHERE o.user_id = u.id) AS max_order
FROM users u;

-- 子查询 + QUALIFY（Snowflake 特有过滤窗口函数结果）
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age) AS rn
    FROM users
) WHERE rn = 1;
-- 等价简写（使用 QUALIFY）:
SELECT * FROM users
QUALIFY ROW_NUMBER() OVER (PARTITION BY city ORDER BY age) = 1;

-- 嵌套子查询
SELECT * FROM users
WHERE city IN (
    SELECT city FROM (
        SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
    ) WHERE cnt > 100
);
