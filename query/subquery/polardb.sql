-- PolarDB: 子查询
-- PolarDB-X (distributed, MySQL compatible).
--
-- 参考资料:
--   [1] PolarDB-X SQL Reference
--       https://help.aliyun.com/zh/polardb/polardb-for-xscale/sql-reference/
--   [2] PolarDB MySQL Documentation
--       https://help.aliyun.com/zh/polardb/polardb-for-mysql/

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

-- FROM 子查询（派生表）
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- LATERAL 派生表
SELECT u.username, t.total
FROM users u,
LATERAL (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;

-- 注意事项：
-- 子查询可能涉及跨分片查询，性能与分区键相关
-- IN 子查询和 EXISTS 子查询在分布式环境下由优化器选择执行计划
-- 标量子查询如果涉及不同分片会在代理层合并
-- 建议用 JOIN 替代子查询以提高分布式环境下的性能
