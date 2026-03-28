-- StarRocks: 子查询
--
-- 参考资料:
--   [1] StarRocks Documentation - Subquery
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/

SELECT username, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS cnt FROM users;
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
SELECT * FROM users u WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);

SELECT t.city, t.cnt FROM (SELECT city, COUNT(*) AS cnt FROM users GROUP BY city) t WHERE t.cnt > 10;

SELECT u.* FROM users u LEFT SEMI JOIN orders o ON u.id = o.user_id;
SELECT u.* FROM users u LEFT ANTI JOIN orders o ON u.id = o.user_id;

-- StarRocks CBO 的子查询优化:
--   自动将 IN/EXISTS 改写为 SEMI JOIN
--   自动将关联子查询去关联(Decorrelation)
--   支持多层嵌套子查询的平坦化
--   CBO 更成熟(Cascades 框架)——比 Doris Nereids 更早实现。
