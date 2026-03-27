-- SQLite: JOIN
--
-- 参考资料:
--   [1] SQLite Documentation - SELECT (JOIN)
--       https://www.sqlite.org/lang_select.html
--   [2] SQLite Documentation - Query Planning
--       https://www.sqlite.org/queryplanner.html

-- INNER JOIN
SELECT u.username, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id;

-- LEFT JOIN
SELECT u.username, o.amount
FROM users u
LEFT JOIN orders o ON u.id = o.user_id;

-- CROSS JOIN
SELECT u.username, r.role_name
FROM users u
CROSS JOIN roles r;

-- 自连接
SELECT e.username AS employee, m.username AS manager
FROM users e
LEFT JOIN users m ON e.manager_id = m.id;

-- USING
SELECT * FROM users JOIN orders USING (user_id);

-- NATURAL JOIN
SELECT * FROM users NATURAL JOIN orders;

-- 注意：SQLite 不支持 RIGHT JOIN 和 FULL OUTER JOIN（3.39.0 之前）

-- 3.39.0+: RIGHT JOIN 和 FULL OUTER JOIN
SELECT u.username, o.amount
FROM users u
RIGHT JOIN orders o ON u.id = o.user_id;

SELECT u.username, o.amount
FROM users u
FULL OUTER JOIN orders o ON u.id = o.user_id;

-- 注意：SQLite 不支持 LATERAL JOIN
