-- Hive: INSERT
--
-- 参考资料:
--   [1] Apache Hive Language Manual - DML
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DML

-- 注意: Hive 面向批量数据处理，INSERT 提交 MapReduce / Tez / Spark 作业

-- INSERT INTO（追加数据）
INSERT INTO TABLE users
SELECT 'alice', 'alice@example.com', 25;

-- INSERT OVERWRITE（覆盖写入，Hive 核心操作）
INSERT OVERWRITE TABLE users_archive
SELECT username, email, age FROM users WHERE age > 60;

-- VALUES 子句（0.14+ ACID 表，3.0+ 默认所有托管表支持）
INSERT INTO TABLE users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30);

-- 插入分区表（静态分区）
INSERT INTO TABLE events PARTITION (dt = '2024-01-15')
SELECT user_id, event_name, event_time FROM staging_events;

-- INSERT OVERWRITE 分区
INSERT OVERWRITE TABLE events PARTITION (dt = '2024-01-15')
SELECT user_id, event_name, event_time FROM staging_events;

-- 动态分区（根据数据自动确定分区值）
SET hive.exec.dynamic.partition = true;
SET hive.exec.dynamic.partition.mode = nonstrict;
INSERT OVERWRITE TABLE events PARTITION (dt)
SELECT user_id, event_name, event_time, dt FROM staging_events;

-- 混合分区（静态 + 动态）
INSERT OVERWRITE TABLE events PARTITION (year = '2024', month)
SELECT user_id, event_name, month_col FROM staging_events;

-- 多路输出（一次读取写入多个表/分区，减少扫描次数）
FROM staging_events
INSERT OVERWRITE TABLE events_web PARTITION (dt = '2024-01-15')
    SELECT user_id, event_name WHERE source = 'web'
INSERT OVERWRITE TABLE events_app PARTITION (dt = '2024-01-15')
    SELECT user_id, event_name WHERE source = 'app';

-- 从本地文件加载
LOAD DATA LOCAL INPATH '/tmp/users.txt' INTO TABLE users;

-- 从 HDFS 加载（移动文件而非复制）
LOAD DATA INPATH '/data/users.txt' INTO TABLE users;

-- LOAD DATA OVERWRITE（覆盖原有数据）
LOAD DATA INPATH '/data/users.txt' OVERWRITE INTO TABLE users;

-- CTE + INSERT（1.1.0+）
WITH new_users AS (
    SELECT 'alice' AS username, 'alice@example.com' AS email
)
INSERT INTO TABLE users (username, email)
SELECT username, email FROM new_users;

-- 创建表并插入数据 (CTAS)
CREATE TABLE users_backup AS
SELECT * FROM users WHERE age > 18;
