-- Hive: 子查询
--
-- 参考资料:
--   [1] Apache Hive Language Manual - SubQueries
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+SubQueries
--   [2] Apache Hive Language Manual - SELECT
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Select

-- 标量子查询（关联标量子查询 2.0+，非关联标量子查询 0.13+）
SELECT username, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;

-- WHERE IN 子查询（0.13+）
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blacklist);

-- EXISTS（0.13+）
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- FROM 子查询（所有版本支持）
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- 关联子查询（2.0+，之前版本不支持）
SELECT u.username,
    (SELECT MAX(amount) FROM orders o WHERE o.user_id = u.id) AS max_order
FROM users u;

-- SEMI JOIN（左半连接，替代 IN 子查询的高效写法，0.13+）
SELECT u.*
FROM users u
LEFT SEMI JOIN orders o ON u.id = o.user_id;

-- 子查询 + LATERAL VIEW
SELECT u.username, tag
FROM (
    SELECT * FROM users WHERE status = 1
) u
LATERAL VIEW EXPLODE(u.tags) t AS tag;

-- 嵌套子查询
SELECT * FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- 注意：Hive 0.12 及之前不支持 WHERE 子句中的子查询
-- 注意：Hive 不支持 ALL / ANY / SOME 运算符
-- 注意：Hive 不支持 LATERAL 子查询（标准 SQL 侧向子查询）
-- 注意：早期版本只支持 FROM 子查询，WHERE 子句中的 IN/EXISTS 需要改写为 JOIN
-- 建议：性能敏感场景下将子查询改写为 JOIN 或 SEMI JOIN
