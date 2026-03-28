-- Snowflake: 触发器（Streams + Tasks 替代方案）
--
-- 参考资料:
--   [1] Snowflake SQL Reference - CREATE STREAM
--       https://docs.snowflake.com/en/sql-reference/sql/create-stream
--   [2] Snowflake SQL Reference - CREATE TASK
--       https://docs.snowflake.com/en/sql-reference/sql/create-task

-- ============================================================
-- 1. 核心概念: Snowflake 不支持传统触发器
-- ============================================================

-- Snowflake 没有 BEFORE/AFTER INSERT/UPDATE/DELETE 触发器。
-- 使用 Streams + Tasks 组合实现类似功能（CDC + 调度执行）。

-- ============================================================
-- 2. 语法设计分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 为什么不支持触发器
-- 传统触发器的问题在云数仓场景中被放大:
--   (a) 行级触发器与批量加载冲突: COPY INTO 加载百万行时，
--       每行触发一次 → 性能灾难
--   (b) 触发器在事务内同步执行: 增加事务持有锁的时间
--   (c) 触发器级联: 触发器 A 触发触发器 B → 调试噩梦
--   (d) 分布式执行: 触发器需要在写入节点上同步执行 →
--       多 Warehouse 并发写入时，触发器在哪个 Warehouse 执行？
--
-- Snowflake 的替代方案 Streams + Tasks 解决了这些问题:
--   Streams: 异步捕获变更（不在写入路径上执行）
--   Tasks:   按调度执行（1 分钟最小间隔，非实时）
--   分离了"变更捕获"和"响应执行"两个关注点
--
-- 对比:
--   MySQL:      BEFORE/AFTER 行级触发器（性能影响大）
--   PostgreSQL: 行级/语句级 + INSTEAD OF + Event Triggers（功能最丰富）
--   Oracle:     行级/语句级 + COMPOUND 触发器（性能优化）
--   SQL Server: AFTER/INSTEAD OF 触发器 + DDL 触发器
--   BigQuery:   无触发器（也无 Stream + Task 替代）
--   Redshift:   无触发器
--   Databricks: Delta Lake Change Data Feed（类似 Stream）+ 作业调度
--
-- 对引擎开发者的启示:
--   触发器是 OLTP 的核心功能但与 OLAP 模式冲突。
--   异步变更捕获 (CDC) + 调度执行是云数仓的标准替代方案。
--   Debezium (MySQL/PG CDC) + Kafka + 流处理是开源世界的等价方案。

-- ============================================================
-- 3. Streams: 变更数据捕获 (CDC)
-- ============================================================

-- 在表上创建 Stream 来捕获变更:
CREATE STREAM users_stream ON TABLE users;

-- 查看变更:
SELECT * FROM users_stream;

-- Stream 中的元数据列:
-- METADATA$ACTION:    'INSERT' 或 'DELETE'
-- METADATA$ISUPDATE:  TRUE 表示是 UPDATE（UPDATE = DELETE + INSERT 组合）
-- METADATA$ROW_ID:    行的唯一标识

-- 消费 Stream 中的变更（INSERT/UPDATE/DELETE 分别处理）:
INSERT INTO audit_log (table_name, action, record_id, new_data, changed_at)
SELECT
    'users',
    CASE WHEN METADATA$ISUPDATE THEN 'UPDATE'
         ELSE METADATA$ACTION END,
    id,
    OBJECT_CONSTRUCT(*),
    CURRENT_TIMESTAMP()
FROM users_stream
WHERE METADATA$ACTION = 'INSERT';

-- Stream 的关键行为:
--   (a) 增量的: 消费后（SELECT 在 DML 事务中引用），数据不再出现
--   (b) 事务性: 只有在消费事务提交后才标记为已消费
--   (c) 位移追踪: Stream 内部维护一个偏移量（类似 Kafka consumer offset）

-- Stream 类型:
CREATE STREAM std_stream ON TABLE users;                -- 标准 (默认)
CREATE STREAM append_stream ON TABLE users APPEND_ONLY = TRUE;  -- 仅追加（仅捕获 INSERT）
CREATE STREAM ins_only ON TABLE users INSERT_ONLY = TRUE;       -- INSERT_ONLY（External Table）

-- ============================================================
-- 4. Tasks: 调度执行
-- ============================================================

-- 基于 Stream 的 Task（当 Stream 有变更时执行）:
CREATE TASK process_user_changes
    WAREHOUSE = compute_wh
    SCHEDULE = '1 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA('users_stream')
AS
    INSERT INTO audit_log (table_name, action, record_id, changed_at)
    SELECT 'users', METADATA$ACTION, id, CURRENT_TIMESTAMP()
    FROM users_stream;

-- 启动/暂停 Task:
ALTER TASK process_user_changes RESUME;
ALTER TASK process_user_changes SUSPEND;

-- Task 需要显式 RESUME 才会开始执行（创建后默认 SUSPENDED）

-- ============================================================
-- 5. Task DAG: 多步骤处理链
-- ============================================================

-- 根 Task（有 SCHEDULE）
CREATE TASK step1
    WAREHOUSE = compute_wh
    SCHEDULE = '1 HOUR'
AS INSERT INTO staging FROM raw_data;

-- 子 Task（依赖根 Task）
CREATE TASK step2
    WAREHOUSE = compute_wh
    AFTER step1
AS INSERT INTO cleaned FROM staging;

CREATE TASK step3
    WAREHOUSE = compute_wh
    AFTER step2
AS INSERT INTO final FROM cleaned;

-- 启动: 必须从叶节点向根节点启动
ALTER TASK step3 RESUME;
ALTER TASK step2 RESUME;
ALTER TASK step1 RESUME;    -- 根 Task 最后启动

-- Task DAG 设计:
--   这是一个简化的 DAG 调度器（类似 Airflow 的子集）。
--   AFTER 子句定义依赖关系，Snowflake 保证执行顺序。
--   对比 Airflow/dbt: 功能更简单，但无需额外基础设施。

-- ============================================================
-- 6. 存储过程 + Task
-- ============================================================

CREATE PROCEDURE handle_changes()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    MERGE INTO users_summary AS target
    USING (SELECT user_id, SUM(amount) AS total
           FROM orders_stream GROUP BY user_id) AS source
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
-- 7. Snowpipe: 文件到达触发的自动加载
-- ============================================================

CREATE PIPE my_pipe
    AUTO_INGEST = TRUE
AS COPY INTO users FROM @my_stage FILE_FORMAT = (TYPE = 'CSV');

-- AUTO_INGEST: 当新文件到达 Stage 时自动加载
-- 触发机制: S3 Event Notification / Azure Event Grid / GCS Pub/Sub
-- 这是最接近"INSERT 触发器"的功能

-- ============================================================
-- 8. 管理与监控
-- ============================================================

SHOW STREAMS;
SHOW TASKS;
DESCRIBE STREAM users_stream;

-- 查看 Task 执行历史:
SELECT * FROM TABLE(information_schema.task_history(
    scheduled_time_range_start => DATEADD('hour', -1, CURRENT_TIMESTAMP())
));

DROP STREAM IF EXISTS users_stream;
DROP TASK IF EXISTS process_user_changes;

-- ============================================================
-- 横向对比: 触发器与替代方案
-- ============================================================
-- 能力            | Snowflake        | MySQL/PG/Oracle | BigQuery  | Databricks
-- 行级触发器      | 不支持           | 支持            | 不支持    | 不支持
-- 语句级触发器    | 不支持           | 支持(PG/Oracle) | 不支持    | 不支持
-- CDC 变更捕获    | Streams          | Binlog/WAL/Redo | 不支持    | CDF
-- 调度执行        | Tasks            | 外部调度(cron)  | 外部调度  | Jobs
-- DAG 编排        | Task DAG         | 无原生          | 无原生    | Workflows
-- 文件触发        | Snowpipe         | 无              | 无        | Auto Loader
-- 最小延迟        | 1 分钟           | 实时(行级)      | N/A       | 秒级
--
-- 关键限制: Stream + Task 最小延迟 1 分钟，不是实时的。
-- 对于需要亚秒级响应的场景（如库存扣减），Snowflake 不适合。
-- Hybrid Tables (2024) 可能未来支持更接近实时的触发能力。
