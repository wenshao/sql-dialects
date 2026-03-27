-- Hive: UPSERT
--
-- 参考资料:
--   [1] Apache Hive Language Manual - DML (MERGE)
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DML
--   [2] Apache Hive - Hive Transactions
--       https://cwiki.apache.org/confluence/display/Hive/Hive+Transactions

-- 注意: Hive ACID 事务表支持 MERGE 语句（2.2+）
-- 非 ACID 表需要用 INSERT OVERWRITE 模拟
-- 需要配置:
--   SET hive.support.concurrency = true;
--   SET hive.txn.manager = org.apache.hadoop.hive.ql.lockmgr.DbTxnManager;

-- === ACID 事务表 MERGE（2.2+） ===

-- 基本 MERGE（UPSERT）
MERGE INTO users AS t
USING staging_users AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT VALUES (s.username, s.email, s.age);

-- 带条件的 MERGE
MERGE INTO users AS t
USING staging_users AS s
ON t.username = s.username
WHEN MATCHED AND s.age > t.age THEN
    UPDATE SET age = s.age
WHEN MATCHED AND s.status = 'delete' THEN
    DELETE
WHEN NOT MATCHED THEN
    INSERT VALUES (s.username, s.email, s.age);

-- 仅插入不存在的行
MERGE INTO users AS t
USING staging_users AS s
ON t.username = s.username
WHEN NOT MATCHED THEN
    INSERT VALUES (s.username, s.email, s.age);

-- 从子查询 MERGE
MERGE INTO users AS t
USING (SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age) AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT VALUES (s.username, s.email, s.age);

-- === 非 ACID 表替代方案: INSERT OVERWRITE ===

-- 用 FULL OUTER JOIN + INSERT OVERWRITE 模拟 UPSERT
INSERT OVERWRITE TABLE users
SELECT
    COALESCE(s.username, t.username) AS username,
    COALESCE(s.email, t.email) AS email,
    COALESCE(s.age, t.age) AS age
FROM users t
FULL OUTER JOIN staging_users s ON t.username = s.username;

-- 用 UNION ALL + ROW_NUMBER 去重模拟（增量更新优先）
INSERT OVERWRITE TABLE users
SELECT username, email, age FROM (
    SELECT username, email, age,
           ROW_NUMBER() OVER (PARTITION BY username ORDER BY source DESC) AS rn
    FROM (
        SELECT username, email, age, 1 AS source FROM staging_users
        UNION ALL
        SELECT username, email, age, 0 AS source FROM users
    ) combined
) ranked
WHERE rn = 1;

-- 分区表的 UPSERT（只重写受影响分区）
INSERT OVERWRITE TABLE events PARTITION (dt = '2024-01-15')
SELECT COALESCE(s.user_id, t.user_id),
       COALESCE(s.event_name, t.event_name),
       COALESCE(s.event_time, t.event_time)
FROM events t
FULL OUTER JOIN staging_events s
    ON t.user_id = s.user_id AND t.event_time = s.event_time
WHERE t.dt = '2024-01-15';
