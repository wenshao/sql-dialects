-- Vertica: JOIN
--
-- 参考资料:
--   [1] Vertica SQL Reference
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/SQLReferenceManual.htm
--   [2] Vertica Functions
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Functions.htm

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

-- NATURAL JOIN
SELECT * FROM users NATURAL JOIN user_profiles;

-- 自连接
SELECT e.username AS employee, m.username AS manager
FROM users e
LEFT JOIN users m ON e.manager_id = m.id;

-- USING
SELECT * FROM users JOIN orders USING (user_id);

-- LATERAL JOIN
SELECT u.username, recent.*
FROM users u
CROSS JOIN LATERAL (
    SELECT amount, order_date
    FROM orders
    WHERE user_id = u.id
    ORDER BY order_date DESC
    LIMIT 3
) recent;

-- 多表 JOIN
SELECT u.username, o.amount, p.product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id;

-- SEMI JOIN（通过 EXISTS 实现，优化器自动选择）
SELECT u.*
FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- ANTI JOIN（通过 NOT EXISTS 实现）
SELECT u.*
FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- JOIN hint: SYNTACTIC（按语法顺序 JOIN）
SELECT /*+SYNTACTIC_JOIN*/ u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id;

-- Event Series JOIN（时间序列数据特有）
SELECT t.ts, d.sensor_id, d.value
FROM timestamps t
INNER JOIN sensor_data d
ON t.ts = d.event_time
    AND d.sensor_id = 1;

-- Interpolation JOIN（插值连接）
SELECT t.ts, d.value
FROM (SELECT ts FROM timestamps) t
LEFT JOIN sensor_data d
ON t.ts INTERPOLATE PREVIOUS VALUE d.event_time;

-- 查看查询计划
EXPLAIN SELECT u.username, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;

-- 注意：Vertica 支持标准 SQL JOIN 语法
-- 注意：支持 LATERAL JOIN
-- 注意：Interpolation JOIN 适合时间序列数据填充缺失值
-- 注意：Projections 的排序顺序影响 Merge JOIN 效率
-- 注意：SEGMENTED BY 相同列的表 JOIN 可利用本地数据
