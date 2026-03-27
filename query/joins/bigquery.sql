-- BigQuery: JOIN
--
-- 参考资料:
--   [1] BigQuery SQL Reference - JOIN
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#join_types
--   [2] BigQuery SQL Reference - Query Syntax
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax

-- INNER JOIN
SELECT u.username, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id;

-- LEFT JOIN
SELECT u.username, o.amount
FROM users u
LEFT JOIN orders o ON u.id = o.user_id;

-- RIGHT JOIN
SELECT u.username, o.amount
FROM users u
RIGHT JOIN orders o ON u.id = o.user_id;

-- FULL OUTER JOIN
SELECT u.username, o.amount
FROM users u
FULL OUTER JOIN orders o ON u.id = o.user_id;

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

-- UNNEST：展开数组列进行 JOIN（BigQuery 特有）
SELECT u.username, tag
FROM users u
CROSS JOIN UNNEST(u.tags) AS tag;

-- UNNEST + LEFT JOIN
SELECT u.username, tag
FROM users u
LEFT JOIN UNNEST(u.tags) AS tag ON TRUE;

-- UNNEST 带 OFFSET（获取数组元素的位置）
SELECT u.username, tag, pos
FROM users u
CROSS JOIN UNNEST(u.tags) AS tag WITH OFFSET AS pos;

-- TABLESAMPLE（抽样连接）
SELECT u.username, o.amount
FROM users u TABLESAMPLE SYSTEM (10 PERCENT)
JOIN orders o ON u.id = o.user_id;

-- 多表 JOIN
SELECT u.username, o.amount, p.product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id;

-- 注意：BigQuery 不支持 NATURAL JOIN
-- 注意：BigQuery JOIN 优化建议使用较小的表放在右侧
