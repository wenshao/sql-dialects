-- Oracle: 子查询
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - Subqueries
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Using-Subqueries.html
--   [2] Oracle SQL Language Reference - SELECT
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/SELECT.html

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
SELECT * FROM users WHERE age >= ALL (SELECT age FROM users WHERE city = 'Beijing');
SELECT * FROM users WHERE age > ANY (SELECT age FROM users WHERE city = 'Beijing');

-- FROM 子查询（内联视图）
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- 行子查询
SELECT * FROM users WHERE (city, age) IN (SELECT city, MIN(age) FROM users GROUP BY city);

-- 多列子查询
SELECT * FROM users WHERE (city, age) = (SELECT 'Beijing', MAX(age) FROM users WHERE city = 'Beijing');

-- 12c+: LATERAL
SELECT u.username, t.total
FROM users u,
LATERAL (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;

-- 标量子查询缓存：Oracle 会自动缓存标量子查询的结果（按输入值），性能优于其他数据库

-- WITH CHECK OPTION（用于视图或 DML 中的子查询，确保数据满足条件）
-- 在 INSERT/UPDATE 通过子查询操作时有效，纯 SELECT 中无意义
-- 示例：通过视图更新时确保数据满足视图条件
-- CREATE VIEW adult_users AS SELECT * FROM users WHERE age > 18 WITH CHECK OPTION;
