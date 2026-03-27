-- Apache Doris: UPDATE
--
-- 参考资料:
--   [1] Doris SQL Manual
--       https://doris.apache.org/docs/sql-manual/sql-statements/
--   [2] Doris Data Types
--       https://doris.apache.org/docs/sql-manual/data-types/
--   [3] Doris Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/

-- 注意: Doris UPDATE 仅支持 Unique Key 模型表
-- 其他模型（明细模型、聚合模型）不支持直接 UPDATE

-- 基本更新
UPDATE users SET age = 26 WHERE username = 'alice';

-- 多列更新
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- 子查询更新
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;

-- 多表 JOIN 更新（2.0+）
UPDATE users u
JOIN orders o ON u.id = o.user_id
SET u.status = 1
WHERE o.amount > 1000;

-- CTE + UPDATE（2.1+）
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users u
JOIN vip v ON u.id = v.user_id
SET u.status = 2;

-- CASE 表达式
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- 自引用更新
UPDATE users SET age = age + 1;

-- 基于子查询的批量更新
UPDATE users SET
    email = t.new_email
FROM (SELECT 'alice' AS username, 'alice_new@example.com' AS new_email
      UNION ALL
      SELECT 'bob', 'bob_new@example.com') t
WHERE users.username = t.username;

-- 条件更新（结合 Merge-on-Write）
UPDATE users SET status = 1 WHERE last_login > '2024-01-01';

-- 限制:
-- 仅 Unique Key 模型表支持
-- 不支持更新 Key 列
-- 不支持 ORDER BY / LIMIT
-- 不支持更新分区键
