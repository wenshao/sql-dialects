-- Snowflake: UPDATE
--
-- 参考资料:
--   [1] Snowflake SQL Reference - UPDATE
--       https://docs.snowflake.com/en/sql-reference/sql/update

-- 基本更新
UPDATE users SET age = 26 WHERE username = 'alice';

-- 多列更新
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- 子查询更新
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;

-- FROM 子句（多表更新）
UPDATE users u
SET u.status = 1
FROM orders o
WHERE u.id = o.user_id AND o.amount > 1000;

-- 多表 JOIN 更新
UPDATE users u
SET u.status = 1
FROM orders o, payments p
WHERE u.id = o.user_id AND o.id = p.order_id AND p.amount > 1000;

-- CTE + UPDATE
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users u
SET u.status = 2
FROM vip v
WHERE u.id = v.user_id;

-- CASE 表达式
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- 自引用更新
UPDATE users SET age = age + 1;

-- 更新半结构化数据（VARIANT / OBJECT）
UPDATE events SET data = OBJECT_INSERT(data, 'source', 'web', TRUE)
WHERE event_name = 'login';

-- 更新 ARRAY 元素（需整体替换或使用 ARRAY 函数）
UPDATE users SET tags = ARRAY_APPEND(tags, 'premium') WHERE username = 'alice';

-- 基于子查询的批量更新
UPDATE users u SET
    email = t.new_email
FROM (SELECT 'alice' AS username, 'alice_new@example.com' AS new_email
      UNION ALL
      SELECT 'bob', 'bob_new@example.com') t
WHERE u.username = t.username;
