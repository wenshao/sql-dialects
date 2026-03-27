-- DamengDB (达梦): 子查询
-- Oracle compatible syntax.
--
-- 参考资料:
--   [1] DamengDB SQL Reference
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html
--   [2] DamengDB System Admin Manual
--       https://eco.dameng.com/document/dm/zh-cn/pm/index.html

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

-- FROM 子查询（内联视图）
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- WITH 子查询分解（Oracle 风格）
WITH city_stats AS (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
)
SELECT * FROM city_stats WHERE cnt > 10;

-- 注意事项：
-- 语法与 Oracle 兼容
-- 支持子查询优化（子查询展开等）
-- 不需要给派生表别名时也可以工作（与 Oracle 兼容）
