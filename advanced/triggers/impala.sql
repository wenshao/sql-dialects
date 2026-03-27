-- Apache Impala: 触发器
--
-- 参考资料:
--   [1] Impala SQL Reference
--       https://impala.apache.org/docs/build/html/topics/impala_langref.html
--   [2] Impala Built-in Functions
--       https://impala.apache.org/docs/build/html/topics/impala_functions.html

-- Impala 不支持触发器

-- ============================================================
-- 替代方案
-- ============================================================

-- 方案一：使用 Hive 的事件通知
-- Hive Metastore 支持事件通知
-- 可以监听表和分区的变更

-- 方案二：使用 HDFS 的 inotify 机制
-- 监听 HDFS 目录变更
-- 当新文件到达时触发处理逻辑

-- 方案三：使用 Apache Kafka + Flink
-- 上游变更发送到 Kafka
-- Flink 消费并处理变更事件

-- 方案四：使用 INVALIDATE METADATA / REFRESH
-- 当外部数据变更后刷新 Impala 元数据
-- INVALIDATE METADATA table_name;
-- REFRESH table_name;

-- 方案五：使用调度工具定期检查
-- Apache Airflow / Oozie
-- 定时检查数据变更并执行处理逻辑

-- 方案六：使用 Kudu 的回调机制
-- Kudu 支持 WAL（Write Ahead Log）
-- 可以通过 Kudu API 监听数据变更

-- 审计日志替代方案
-- Impala 自带审计日志功能（Sentry 集成）
-- 通过 Cloudera Manager 配置审计

-- 自动更新时间戳替代方案
-- 在 INSERT 语句中显式设置时间戳
INSERT INTO users (id, username, email, updated_at)
VALUES (1, 'alice', 'alice@example.com', NOW());

-- 使用视图封装
CREATE VIEW users_with_timestamp AS
SELECT *, NOW() AS query_time FROM users;

-- 注意：Impala 不支持触发器
-- 注意：Hadoop 生态系统通常使用 ETL 流程替代触发器
-- 注意：推荐使用 Kafka + Flink / Spark 实现事件驱动处理
-- 注意：INVALIDATE METADATA 用于刷新外部数据变更
