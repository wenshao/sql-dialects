-- Databricks SQL: 子查询
--
-- 参考资料:
--   [1] Databricks SQL Language Reference
--       https://docs.databricks.com/en/sql/language-manual/index.html
--   [2] Databricks SQL - Built-in Functions
--       https://docs.databricks.com/en/sql/language-manual/sql-ref-functions-builtin.html
--   [3] Delta Lake Documentation
--       https://docs.delta.io/latest/index.html

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

-- FROM 子查询
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- LATERAL 子查询（Databricks 2023+）
SELECT u.username, t.total
FROM users u,
LATERAL (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;

-- 关联子查询
SELECT u.username,
    (SELECT MAX(amount) FROM orders o WHERE o.user_id = u.id) AS max_order
FROM users u;

-- 行子查询
SELECT * FROM users WHERE (city, age) IN (SELECT city, MIN(age) FROM users GROUP BY city);

-- 嵌套子查询
SELECT * FROM users
WHERE city IN (
    SELECT city FROM (
        SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
    ) WHERE cnt > 100
);

-- 数组展开子查询
SELECT u.username, tag
FROM users u
LATERAL VIEW EXPLODE(u.tags) t AS tag
WHERE tag IN (SELECT tag_name FROM popular_tags);

-- QUALIFY（Databricks 2023+，过滤窗口函数结果）
SELECT * FROM users
QUALIFY ROW_NUMBER() OVER (PARTITION BY city ORDER BY age) = 1;

-- 等价子查询写法
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age) AS rn
    FROM users
) WHERE rn = 1;

-- WITH 子句 + 子查询
WITH top_users AS (
    SELECT user_id, SUM(amount) AS total
    FROM orders GROUP BY user_id
)
SELECT * FROM users WHERE id IN (SELECT user_id FROM top_users WHERE total > 10000);

-- Time Travel 子查询
SELECT * FROM users
WHERE id NOT IN (
    SELECT id FROM users VERSION AS OF 5
);
-- 找出自版本 5 以来新增的行

-- 注意：Databricks 支持 LATERAL 子查询和 LATERAL VIEW
-- 注意：QUALIFY 子句可以直接过滤窗口函数结果
-- 注意：NOT IN 在有 NULL 时行为不同，推荐用 NOT EXISTS
-- 注意：Photon 引擎优化了子查询的执行
-- 注意：Time Travel 子查询可以比较不同版本的数据
