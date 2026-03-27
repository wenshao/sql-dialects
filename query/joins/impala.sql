-- Apache Impala: JOIN
--
-- 参考资料:
--   [1] Impala SQL Reference
--       https://impala.apache.org/docs/build/html/topics/impala_langref.html
--   [2] Impala Built-in Functions
--       https://impala.apache.org/docs/build/html/topics/impala_functions.html

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

-- LEFT SEMI JOIN（等价于 IN / EXISTS）
SELECT u.*
FROM users u
LEFT SEMI JOIN orders o ON u.id = o.user_id;

-- LEFT ANTI JOIN（等价于 NOT IN / NOT EXISTS）
SELECT u.*
FROM users u
LEFT ANTI JOIN orders o ON u.id = o.user_id;

-- RIGHT SEMI JOIN
SELECT o.*
FROM users u
RIGHT SEMI JOIN orders o ON u.id = o.user_id;

-- RIGHT ANTI JOIN
SELECT o.*
FROM users u
RIGHT ANTI JOIN orders o ON u.id = o.user_id;

-- 多表 JOIN
SELECT u.username, o.amount, p.product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id;

-- JOIN hint: BROADCAST（广播小表）
SELECT /* +BROADCAST(orders) */ u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id;

-- JOIN hint: SHUFFLE（Hash 重分布）
SELECT /* +SHUFFLE(orders) */ u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id;

-- 查看查询计划
EXPLAIN SELECT u.username, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;

-- COMPUTE STATS 优化 JOIN（帮助优化器选择策略）
COMPUTE STATS users;
COMPUTE STATS orders;

-- 注意：Impala 支持标准 JOIN 语法
-- 注意：支持 SEMI JOIN 和 ANTI JOIN（左右两种）
-- 注意：不支持 NATURAL JOIN
-- 注意：不支持 LATERAL JOIN
-- 注意：COMPUTE STATS 对 JOIN 优化非常重要
-- 注意：JOIN hint 可以强制使用 BROADCAST 或 SHUFFLE 策略
