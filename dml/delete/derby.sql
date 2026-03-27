-- Derby: DELETE
--
-- 参考资料:
--   [1] Derby SQL Reference
--       https://db.apache.org/derby/docs/10.16/ref/
--   [2] Derby Developer Guide
--       https://db.apache.org/derby/docs/10.16/devguide/

-- 基本删除
DELETE FROM users WHERE username = 'alice';

-- 删除所有行
DELETE FROM users;

-- 子查询删除
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- EXISTS 子查询
DELETE FROM users
WHERE EXISTS (SELECT 1 FROM blacklist b WHERE b.email = users.email);

-- 关联子查询
DELETE FROM users WHERE id NOT IN (
    SELECT DISTINCT user_id FROM orders
);

-- WHERE CURRENT OF（游标定位删除）
-- 在存储过程中使用
-- DECLARE cur CURSOR FOR SELECT * FROM users FOR UPDATE;
-- FETCH NEXT FROM cur;
-- DELETE FROM users WHERE CURRENT OF cur;

-- TRUNCATE（10.11+）
TRUNCATE TABLE users;

-- 删除表
DROP TABLE users;

-- 注意：不支持 LIMIT 子句
-- 注意：不支持多表 JOIN 删除
-- 注意：不支持 RETURNING 子句
-- 注意：不支持 CTE + DELETE
-- 注意：TRUNCATE 在较新版本（10.11+）才支持
-- 注意：支持 WHERE CURRENT OF 游标定位删除
-- 注意：DELETE 受事务控制，可以 ROLLBACK
