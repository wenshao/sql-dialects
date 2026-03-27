-- MaxCompute: JOIN
--
-- 参考资料:
--   [1] MaxCompute SQL - JOIN
--       https://help.aliyun.com/zh/maxcompute/user-guide/join
--   [2] MaxCompute SQL - SELECT
--       https://help.aliyun.com/zh/maxcompute/user-guide/select

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

-- LATERAL VIEW：展开数组（类似 Hive 语法）
SELECT u.username, tag
FROM users u
LATERAL VIEW EXPLODE(u.tags) t AS tag;

-- LATERAL VIEW OUTER（保留无数据的行）
SELECT u.username, tag
FROM users u
LATERAL VIEW OUTER EXPLODE(u.tags) t AS tag;

-- LATERAL VIEW + POSEXPLODE（带位置信息）
SELECT u.username, pos, tag
FROM users u
LATERAL VIEW POSEXPLODE(u.tags) t AS pos, tag;

-- MAP 展开
SELECT u.username, k, v
FROM users u
LATERAL VIEW EXPLODE(u.properties) t AS k, v;

-- MAPJOIN（小表广播 JOIN 优化）
SELECT /*+ MAPJOIN(r) */ u.username, r.role_name
FROM users u
JOIN roles r ON u.role_id = r.id;

-- 多表 JOIN
SELECT u.username, o.amount, p.product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id;

-- 注意：MaxCompute JOIN 条件必须包含等值条件
-- 注意：MaxCompute 不支持 USING 和 NATURAL JOIN
-- 注意：MaxCompute 不支持 LATERAL（标准 SQL 侧向连接）
-- 注意：笛卡尔积需要显式使用 CROSS JOIN 或设置 set odps.sql.allow.cartesian=true
