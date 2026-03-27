-- Oracle: UPDATE
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - UPDATE
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/UPDATE.html

-- 基本更新
UPDATE users SET age = 26 WHERE username = 'alice';

-- 多列更新
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- 子查询更新（标量子查询）
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;

-- 关联子查询更新
UPDATE users u SET status = 1
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id AND o.amount > 1000);

-- 多列子查询更新
UPDATE users SET (email, age) = (
    SELECT email, age FROM temp_users t WHERE t.username = users.username
)
WHERE username IN (SELECT username FROM temp_users);

-- CASE 表达式
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- RETURNING（PL/SQL 中使用）
-- UPDATE users SET age = 26 WHERE username = 'alice' RETURNING id INTO v_id;

-- 更新视图（通过可更新视图间接更新）
UPDATE (
    SELECT u.status, o.amount
    FROM users u JOIN orders o ON u.id = o.user_id
) SET status = 1 WHERE amount > 1000;
-- 注意：需要有键保留表

-- ROWNUM 限制更新行数
UPDATE users SET status = 0 WHERE status = 1 AND ROWNUM <= 100;
