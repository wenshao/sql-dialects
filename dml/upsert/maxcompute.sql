-- MaxCompute (ODPS): UPSERT
--
-- 参考资料:
--   [1] MaxCompute SQL - MERGE INTO
--       https://help.aliyun.com/zh/maxcompute/user-guide/merge-into
--   [2] MaxCompute SQL Overview
--       https://help.aliyun.com/zh/maxcompute/user-guide/sql-overview

-- 注意: MaxCompute 事务表支持 MERGE 语句
-- 非事务表需要用 INSERT OVERWRITE 模拟 UPSERT

-- === 事务表 MERGE ===

-- 基本 MERGE（UPSERT）
MERGE INTO users AS t
USING (SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age) AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- 从暂存表 MERGE
MERGE INTO users AS t
USING staging_users AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- 带条件的 MERGE
MERGE INTO users AS t
USING staging_users AS s
ON t.username = s.username
WHEN MATCHED AND s.age > t.age THEN
    UPDATE SET age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- === 非事务表替代方案: INSERT OVERWRITE ===

-- 用 FULL OUTER JOIN + INSERT OVERWRITE 模拟 UPSERT
INSERT OVERWRITE TABLE users
SELECT
    COALESCE(s.username, t.username) AS username,
    COALESCE(s.email, t.email) AS email,
    COALESCE(s.age, t.age) AS age
FROM users t
FULL OUTER JOIN staging_users s ON t.username = s.username;

-- 用 LEFT ANTI JOIN + UNION ALL + INSERT OVERWRITE 模拟
INSERT OVERWRITE TABLE users
SELECT s.username, s.email, s.age FROM staging_users s
UNION ALL
SELECT t.username, t.email, t.age FROM users t
LEFT ANTI JOIN staging_users s ON t.username = s.username;

-- 分区表的 UPSERT（只重写受影响分区）
INSERT OVERWRITE TABLE events PARTITION (dt = '2024-01-15')
SELECT COALESCE(s.user_id, t.user_id),
       COALESCE(s.event_name, t.event_name),
       COALESCE(s.event_time, t.event_time)
FROM events t
FULL OUTER JOIN staging_events s
    ON t.user_id = s.user_id AND t.event_time = s.event_time
WHERE t.dt = '2024-01-15' OR s.dt = '2024-01-15';
