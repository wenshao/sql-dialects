-- Hive: JOIN
--
-- 参考资料:
--   [1] Apache Hive Language Manual - Joins
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Joins
--   [2] Apache Hive Language Manual - SELECT
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Select

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

-- FULL OUTER JOIN（0.7+）
SELECT u.username, o.amount
FROM users u
FULL OUTER JOIN orders o ON u.id = o.user_id;

-- CROSS JOIN（0.10+）
SELECT u.username, r.role_name
FROM users u
CROSS JOIN roles r;

-- 自连接
SELECT e.username AS employee, m.username AS manager
FROM users e
LEFT JOIN users m ON e.manager_id = m.id;

-- 隐式连接（逗号连接，早期版本）
SELECT u.username, o.amount
FROM users u, orders o
WHERE u.id = o.user_id;

-- LATERAL VIEW：展开数组列（Hive 特有）
SELECT u.username, tag
FROM users u
LATERAL VIEW EXPLODE(u.tags) t AS tag;

-- LATERAL VIEW OUTER（0.12+，保留无数据的行，输出 NULL）
SELECT u.username, tag
FROM users u
LATERAL VIEW OUTER EXPLODE(u.tags) t AS tag;

-- LATERAL VIEW + POSEXPLODE（0.13+，带位置信息）
SELECT u.username, pos, tag
FROM users u
LATERAL VIEW POSEXPLODE(u.tags) t AS pos, tag;

-- MAP 类型展开
SELECT u.username, k, v
FROM users u
LATERAL VIEW EXPLODE(u.properties) t AS k, v;

-- 多重 LATERAL VIEW
SELECT u.username, tag, skill
FROM users u
LATERAL VIEW EXPLODE(u.tags) t1 AS tag
LATERAL VIEW EXPLODE(u.skills) t2 AS skill;

-- MAPJOIN hint（广播小表优化）
SELECT /*+ MAPJOIN(r) */ u.username, r.role_name
FROM users u
JOIN roles r ON u.role_id = r.id;

-- STREAMTABLE hint（指定大表流式处理）
SELECT /*+ STREAMTABLE(o) */ u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id;

-- SEMI JOIN（左半连接，Hive 早期版本即支持）
SELECT u.*
FROM users u
LEFT SEMI JOIN orders o ON u.id = o.user_id;

-- BUCKET MAP JOIN（分桶表优化 JOIN）
SELECT /*+ MAPJOIN(o) */ u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id;
-- 前提：两表都按 JOIN 列分桶

-- 注意：Hive 不支持 USING 和 NATURAL JOIN
-- 注意：早期版本 JOIN 条件必须是等值连接（不支持不等值 JOIN）
-- 注意：0.13 之前不支持 WHERE 子句中的隐式连接（逗号分隔）
