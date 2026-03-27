-- Hive: UPDATE
--
-- 参考资料:
--   [1] Apache Hive Language Manual - DML
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DML
--   [2] Apache Hive - Hive Transactions
--       https://cwiki.apache.org/confluence/display/Hive/Hive+Transactions

-- 注意: Hive UPDATE 仅支持 ACID 事务表
-- 需要配置:
--   SET hive.support.concurrency = true;
--   SET hive.txn.manager = org.apache.hadoop.hive.ql.lockmgr.DbTxnManager;
-- 表必须为 ORC 格式且开启事务:
--   CREATE TABLE t (...) STORED AS ORC TBLPROPERTIES ('transactional' = 'true');

-- === ACID 事务表 UPDATE（0.14+） ===

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

-- 限制: 不支持多表 JOIN 更新
-- 限制: 不支持 ORDER BY / LIMIT
-- 限制: 分区列和分桶列不能更新

-- === 非 ACID 表替代方案: INSERT OVERWRITE ===

-- 用 INSERT OVERWRITE 模拟更新（重写整个表/分区）
INSERT OVERWRITE TABLE users
SELECT
    username,
    CASE WHEN username = 'alice' THEN 'new@example.com' ELSE email END AS email,
    CASE WHEN username = 'alice' THEN 26 ELSE age END AS age
FROM users;

-- 用 INSERT OVERWRITE 模拟分区级更新
INSERT OVERWRITE TABLE events PARTITION (dt = '2024-01-15')
SELECT
    user_id,
    CASE WHEN event_name = 'login' THEN 'user_login' ELSE event_name END AS event_name,
    event_time
FROM events
WHERE dt = '2024-01-15';
