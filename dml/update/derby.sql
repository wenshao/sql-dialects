-- Derby: UPDATE
--
-- 参考资料:
--   [1] Derby SQL Reference
--       https://db.apache.org/derby/docs/10.16/ref/
--   [2] Derby Developer Guide
--       https://db.apache.org/derby/docs/10.16/devguide/

-- 基本更新
UPDATE users SET age = 26 WHERE username = 'alice';

-- 多列更新
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- 更新所有行
UPDATE users SET status = 0;

-- 子查询更新
UPDATE users SET age = (SELECT CAST(AVG(age) AS INT) FROM users) WHERE age IS NULL;

-- CASE 表达式
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- 算术运算
UPDATE orders SET amount = amount * 1.1 WHERE status = 'pending';

-- IN 子查询
UPDATE users SET status = 1
WHERE id IN (SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 1000);

-- EXISTS 子查询
UPDATE users SET status = 1
WHERE EXISTS (SELECT 1 FROM orders WHERE orders.user_id = users.id);

-- 关联子查询
UPDATE users u SET status = (
    SELECT CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END
    FROM orders o WHERE o.user_id = u.id
);

-- WHERE CURRENT OF（游标更新）
-- 在存储过程中使用
-- DECLARE cur CURSOR FOR SELECT * FROM users FOR UPDATE;
-- FETCH NEXT FROM cur;
-- UPDATE users SET status = 1 WHERE CURRENT OF cur;

-- 注意：Derby 不支持 FROM 子句的多表更新
-- 注意：不支持 LIMIT 子句
-- 注意：不支持 RETURNING 子句
-- 注意：不支持 CTE + UPDATE
-- 注意：支持 WHERE CURRENT OF（游标定位更新）
-- 注意：UPDATE 受事务控制
