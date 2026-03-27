-- BigQuery: 触发器
--
-- 参考资料:
--   [1] BigQuery - Scheduled Queries
--       https://cloud.google.com/bigquery/docs/scheduling-queries
--   [2] BigQuery - Pub/Sub to BigQuery Streaming
--       https://cloud.google.com/pubsub/docs/bigquery

-- ============================================================
-- 1. BigQuery 没有触发器（为什么）
-- ============================================================

-- BigQuery 不支持 CREATE TRIGGER。原因:
--
-- (a) 无服务器架构:
--     触发器需要常驻进程监听数据变更。
--     BigQuery 没有常驻服务器（计算资源按需分配）。
--     没有进程 = 没有办法"监听" INSERT/UPDATE/DELETE。
--
-- (b) 批量写入模型:
--     BigQuery 的数据加载是批量的（LOAD 作业、Streaming API）。
--     传统触发器是逐行触发的（FOR EACH ROW）。
--     在 PB 级表上逐行触发 = 不可接受的延迟和成本。
--
-- (c) DML 配额:
--     每个表每天 1500 次 DML。
--     触发器内部的 DML 也消耗配额。
--     触发器会迅速耗尽配额。
--
-- (d) 成本模型:
--     触发器隐藏了查询成本（用户不知道每次 INSERT 会触发多少计算）。
--     BigQuery 按扫描量计费，隐藏的触发器查询会导致意外的高额账单。

-- ============================================================
-- 2. 替代方案
-- ============================================================

-- 2.1 计划查询（Scheduled Queries）: 定时触发
-- 通过 BigQuery 内置的计划查询功能，定时执行 SQL:
-- 设置: BigQuery Console → Scheduled Queries → Create
-- 支持 cron 表达式，每 N 分钟/小时/天执行

-- 示例: 每小时聚合数据
-- Schedule: every 1 hours
-- Query:
MERGE INTO myproject.mydataset.hourly_stats AS t
USING (
    SELECT DATE_TRUNC(created_at, HOUR) AS hour, COUNT(*) AS cnt
    FROM myproject.mydataset.events
    WHERE created_at > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 HOUR)
    GROUP BY hour
) AS s
ON t.hour = s.hour
WHEN MATCHED THEN UPDATE SET cnt = s.cnt
WHEN NOT MATCHED THEN INSERT (hour, cnt) VALUES (s.hour, s.cnt);

-- 2.2 物化视图（自动刷新）: 最接近触发器的功能
-- BigQuery 物化视图自动检测基表变更并刷新（默认 30 分钟）。
-- 智能查询重写使用户无感知地利用物化视图结果。
CREATE MATERIALIZED VIEW myproject.mydataset.mv_user_stats AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total
FROM myproject.mydataset.orders GROUP BY user_id;

-- 2.3 Cloud Functions + Pub/Sub: 实时事件触发
-- BigQuery → Pub/Sub → Cloud Function → BigQuery
-- 通过 BigQuery Logs → Cloud Audit Logs → Pub/Sub 订阅
-- Cloud Function 接收事件后执行自定义逻辑

-- 2.4 Dataflow / Dataproc: 流式处理管道
-- 实时数据 → Pub/Sub → Dataflow（Apache Beam）→ BigQuery
-- 在 Dataflow 中实现"触发器逻辑"

-- ============================================================
-- 3. 对比与引擎开发者启示
-- ============================================================
-- BigQuery 不支持触发器，替代方案:
--   计划查询 → 定时触发（最简单）
--   物化视图 → 自动刷新聚合（最接近触发器）
--   Cloud Functions → 实时事件响应（最灵活）
--   Dataflow → 流式处理管道（最强大）
--
-- 对比:
--   MySQL/PostgreSQL: 完整的 BEFORE/AFTER 触发器
--   SQLite:           BEFORE/AFTER + INSTEAD OF
--   ClickHouse:       物化视图替代（INSERT 触发的数据管道）
--   BigQuery:         外部服务替代（Scheduled Query / Cloud Function）
--
-- 对引擎开发者的启示:
--   无服务器引擎天然不适合传统触发器。
--   物化视图（自动刷新）是更好的抽象:
--   声明式（用户定义"要什么"）vs 命令式（触发器定义"做什么"）。
--   计划查询是触发器的"最小可用替代"，实现成本极低。
