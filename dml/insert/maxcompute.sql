-- MaxCompute (ODPS): INSERT
--
-- 参考资料:
--   [1] MaxCompute SQL - INSERT
--       https://help.aliyun.com/zh/maxcompute/user-guide/insert-overwrite-into
--   [2] MaxCompute SQL Overview
--       https://help.aliyun.com/zh/maxcompute/user-guide/sql-overview

-- 注意: MaxCompute 使用离线批处理模型，INSERT 是提交作业执行

-- 单行插入（VALUES）
INSERT INTO TABLE users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- 多行插入
INSERT INTO TABLE users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);

-- INSERT INTO（追加数据）
INSERT INTO TABLE users_archive
SELECT username, email, age FROM users WHERE age > 60;

-- INSERT OVERWRITE（覆盖写入，MaxCompute 核心操作）
INSERT OVERWRITE TABLE users_archive
SELECT username, email, age FROM users WHERE age > 60;

-- 写入分区表（必须指定分区）
INSERT INTO TABLE events PARTITION (dt = '2024-01-15')
SELECT user_id, event_name, event_time FROM staging_events;

-- INSERT OVERWRITE 分区
INSERT OVERWRITE TABLE events PARTITION (dt = '2024-01-15')
SELECT user_id, event_name, event_time FROM staging_events;

-- 动态分区（根据数据自动确定分区值）
INSERT OVERWRITE TABLE events PARTITION (dt)
SELECT user_id, event_name, event_time, dt FROM staging_events;

-- 多路输出（一次读取写入多个表/分区）
FROM staging_events
INSERT OVERWRITE TABLE events_web PARTITION (dt = '2024-01-15')
    SELECT user_id, event_name WHERE source = 'web'
INSERT OVERWRITE TABLE events_app PARTITION (dt = '2024-01-15')
    SELECT user_id, event_name WHERE source = 'app';

-- CTE + INSERT
WITH new_users AS (
    SELECT 'alice' AS username, 'alice@example.com' AS email
)
INSERT INTO TABLE users (username, email)
SELECT username, email FROM new_users;

-- TUNNEL UPLOAD 命令行工具（大批量数据导入，非 SQL）
-- tunnel upload data.txt users -fd ',' -h true;
