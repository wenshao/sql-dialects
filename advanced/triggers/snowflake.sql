-- Snowflake: 触发器
--
-- 参考资料:
--   [1] Snowflake SQL Reference - Streams
--       https://docs.snowflake.com/en/sql-reference/sql/create-stream
--   [2] Snowflake SQL Reference - Tasks
--       https://docs.snowflake.com/en/sql-reference/sql/create-task

-- Snowflake 不支持传统数据库触发器
-- 使用以下替代方案实现类似功能

-- ============================================================
-- 替代方案 1: Streams（变更数据捕获）
-- ============================================================

-- Stream 捕获表的变更（INSERT/UPDATE/DELETE）
CREATE STREAM users_stream ON TABLE users;

-- 查看变更
SELECT * FROM users_stream;

-- Stream 中的元数据列：
-- METADATA$ACTION: 'INSERT' 或 'DELETE'
-- METADATA$ISUPDATE: TRUE 表示是 UPDATE（UPDATE = DELETE + INSERT）
-- METADATA$ROW_ID: 行标识

-- 消费 Stream 中的变更
INSERT INTO audit_log (table_name, action, record_id, new_data, changed_at)
SELECT
    'users',
    METADATA$ACTION,
    id,
    OBJECT_CONSTRUCT(*),
    CURRENT_TIMESTAMP()
FROM users_stream
WHERE METADATA$ACTION = 'INSERT';

-- Stream + Task 组合 = 类似触发器的自动化
-- 当 Stream 有数据时，Task 自动执行

-- ============================================================
-- 替代方案 2: Tasks（自动化任务）
-- ============================================================

-- 基于 Stream 的 Task（当 Stream 有变更时执行）
CREATE TASK process_user_changes
    WAREHOUSE = compute_wh
    SCHEDULE = '1 MINUTE'                   -- 检查频率
    WHEN SYSTEM$STREAM_HAS_DATA('users_stream')
AS
    INSERT INTO audit_log (table_name, action, record_id, changed_at)
    SELECT 'users', METADATA$ACTION, id, CURRENT_TIMESTAMP()
    FROM users_stream;

-- 启动 Task
ALTER TASK process_user_changes RESUME;

-- 暂停 Task
ALTER TASK process_user_changes SUSPEND;

-- Task 链（DAG，多步骤处理）
CREATE TASK step1
    WAREHOUSE = compute_wh
    SCHEDULE = '1 HOUR'
AS INSERT INTO staging FROM raw_data;

CREATE TASK step2
    WAREHOUSE = compute_wh
    AFTER step1                             -- 在 step1 完成后执行
AS INSERT INTO final FROM staging;

ALTER TASK step2 RESUME;
ALTER TASK step1 RESUME;

-- ============================================================
-- 替代方案 3: 存储过程 + Task
-- ============================================================

CREATE PROCEDURE handle_changes()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    -- 消费 Stream 变更
    MERGE INTO users_summary AS target
    USING (SELECT user_id, SUM(amount) AS total FROM orders_stream GROUP BY user_id) AS source
    ON target.user_id = source.user_id
    WHEN MATCHED THEN UPDATE SET total_amount = target.total_amount + source.total
    WHEN NOT MATCHED THEN INSERT VALUES (source.user_id, source.total);

    RETURN 'Done';
END;
$$;

CREATE TASK run_handle_changes
    WAREHOUSE = compute_wh
    SCHEDULE = '5 MINUTES'
    WHEN SYSTEM$STREAM_HAS_DATA('orders_stream')
AS CALL handle_changes();

-- ============================================================
-- 替代方案 4: 外部函数 + 通知
-- ============================================================

-- 使用通知集成发送事件到外部系统
CREATE NOTIFICATION INTEGRATION my_notification
    ENABLED = TRUE
    TYPE = QUEUE
    NOTIFICATION_PROVIDER = AWS_SNS
    DIRECTION = OUTBOUND
    AWS_SNS_TOPIC_ARN = 'arn:aws:sns:us-east-1:123456:my-topic'
    AWS_SNS_ROLE_ARN = 'arn:aws:iam::123456:role/my-role';

-- ============================================================
-- 替代方案 5: Snowpipe（自动数据加载）
-- ============================================================

-- 新文件到达时自动加载数据（类似 INSERT 触发器）
CREATE PIPE my_pipe
    AUTO_INGEST = TRUE
AS COPY INTO users FROM @my_stage FILE_FORMAT = (TYPE = 'CSV');

-- ============================================================
-- 管理 Stream 和 Task
-- ============================================================

SHOW STREAMS;
SHOW TASKS;
DESCRIBE STREAM users_stream;

DROP STREAM IF EXISTS users_stream;
DROP TASK IF EXISTS process_user_changes;

-- 注意：Snowflake 没有行级触发器
-- 注意：Stream + Task 组合是最接近触发器的替代方案
-- 注意：Stream 是增量的，消费后数据不再出现
-- 注意：Task 最小调度间隔是 1 分钟，不是实时的
-- 注意：Snowpipe 实现了文件到达时的自动加载
