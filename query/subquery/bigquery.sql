-- BigQuery: 子查询
--
-- 参考资料:
--   [1] BigQuery SQL Reference - Subqueries
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/subqueries
--   [2] BigQuery SQL Reference - Query Syntax
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax

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

-- FROM 子查询
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- WITH（CTE 代替复杂嵌套子查询，BigQuery 推荐方式）
WITH high_value_orders AS (
    SELECT user_id, SUM(amount) AS total
    FROM orders GROUP BY user_id HAVING SUM(amount) > 1000
)
SELECT u.username, h.total
FROM users u JOIN high_value_orders h ON u.id = h.user_id;

-- 数组子查询（ARRAY 构造）
SELECT username,
    ARRAY(SELECT amount FROM UNNEST(order_amounts) AS amount WHERE amount > 100) AS high_amounts
FROM users;

-- IN + UNNEST（在数组中查找）
SELECT * FROM users
WHERE 'admin' IN UNNEST(tags);

-- STRUCT 子查询
SELECT username,
    (SELECT AS STRUCT COUNT(*) AS cnt, SUM(amount) AS total
     FROM orders WHERE user_id = users.id) AS order_info
FROM users;

-- IN 子查询 + UNNEST 数组
SELECT * FROM users
WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);

-- 关联子查询
SELECT u.username,
    (SELECT MAX(amount) FROM orders o WHERE o.user_id = u.id) AS max_order
FROM users u;

-- 注意：BigQuery 关联子查询有一些限制（例如不能在 ARRAY 子查询中引用外部关联列的某些操作）
