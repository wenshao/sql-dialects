-- MaxCompute (ODPS): UPDATE
--
-- 参考资料:
--   [1] MaxCompute SQL - UPDATE
--       https://help.aliyun.com/zh/maxcompute/user-guide/update
--   [2] MaxCompute SQL Overview
--       https://help.aliyun.com/zh/maxcompute/user-guide/sql-overview

-- 注意: MaxCompute 普通表不支持 UPDATE，必须使用 事务表（Transactional Table）
-- 创建事务表: CREATE TABLE t (...) TBLPROPERTIES ('transactional' = 'true');
-- 非事务表只能通过 INSERT OVERWRITE 实现更新效果

-- === 事务表 UPDATE ===

-- 基本更新
UPDATE users SET age = 26 WHERE username = 'alice';

-- 多列更新
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- 子查询更新
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;

-- CASE 表达式
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- 自引用更新
UPDATE users SET age = age + 1;

-- === 非事务表替代方案: INSERT OVERWRITE ===

-- 用 INSERT OVERWRITE 模拟更新（重写整个表/分区）
INSERT OVERWRITE TABLE users
SELECT
    username,
    CASE WHEN username = 'alice' THEN 'new@example.com' ELSE email END AS email,
    CASE WHEN username = 'alice' THEN 26 ELSE age END AS age
FROM users;

-- 用 INSERT OVERWRITE 模拟分区级更新（只重写受影响分区）
INSERT OVERWRITE TABLE events PARTITION (dt = '2024-01-15')
SELECT
    user_id,
    CASE WHEN event_name = 'login' THEN 'user_login' ELSE event_name END AS event_name,
    event_time
FROM events
WHERE dt = '2024-01-15';
