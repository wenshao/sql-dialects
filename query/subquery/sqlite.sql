-- SQLite: 子查询
--
-- 参考资料:
--   [1] SQLite Documentation - SELECT (Subqueries)
--       https://www.sqlite.org/lang_select.html
--   [2] SQLite Documentation - Expression (Subquery)
--       https://www.sqlite.org/lang_expr.html#subq

-- 标量子查询
SELECT username, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;

-- WHERE 子查询
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);

-- EXISTS
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- 比较运算符 + 子查询
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);

-- FROM 子查询
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- 注意：不支持 LATERAL 子查询
-- 注意：不支持行子查询比较 (a, b) IN (SELECT ...)（3.15.0+ 才支持）

-- 3.15.0+: 行值比较
SELECT * FROM users WHERE (city, age) IN (SELECT city, MIN(age) FROM users GROUP BY city);
