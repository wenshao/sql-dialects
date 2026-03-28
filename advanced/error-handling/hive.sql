-- Hive: 错误处理 (无服务端支持)
--
-- 参考资料:
--   [1] Apache Hive Language Manual
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual
--   [2] Apache Hive - Configuration Properties
--       https://cwiki.apache.org/confluence/display/Hive/Configuration+Properties

-- ============================================================
-- 1. Hive 不支持服务端错误处理
-- ============================================================
-- Hive 没有 TRY/CATCH、EXCEPTION WHEN、DECLARE HANDLER 或 SIGNAL。
-- 这是 Hive 作为批处理引擎的设计选择:
--
-- 为什么没有错误处理?
-- 1. 无存储过程: 没有过程式代码，就没有需要捕获异常的执行上下文
-- 2. 作业级粒度: Hive 的执行单位是 MapReduce/Tez 作业，作业失败 = 整体重试
-- 3. 幂等写入: INSERT OVERWRITE 天然幂等，重试不会产生副作用
-- 4. 错误处理在调度层: Airflow/Oozie 负责失败重试和告警

-- ============================================================
-- 2. SQL 层面的错误预防
-- ============================================================
-- IF NOT EXISTS / IF EXISTS 防止常见 DDL 错误
CREATE TABLE IF NOT EXISTS users (id BIGINT, name STRING) STORED AS ORC;
CREATE DATABASE IF NOT EXISTS analytics;
DROP TABLE IF EXISTS temp_table;
DROP DATABASE IF EXISTS temp_db;

-- 安全的分区操作
ALTER TABLE orders ADD IF NOT EXISTS PARTITION (dt='2024-01-15');
ALTER TABLE orders DROP IF EXISTS PARTITION (dt='2024-01-15');

-- 设计分析: 为什么 IF NOT EXISTS 在 Hive 中特别重要？
-- Hive ETL 作业通常由调度工具反复执行，幂等性是核心需求。
-- 如果建表不加 IF NOT EXISTS，第二次执行就会失败。
-- MySQL/PostgreSQL 也支持 IF NOT EXISTS，但 OLTP 场景中手动执行居多，
-- 不如 Hive 中这么关键。

-- ============================================================
-- 3. ASSERT_TRUE: 数据质量检查 (Hive 特有)
-- ============================================================
-- Hive 提供 assert_true() 函数在查询中做断言
SELECT assert_true(COUNT(*) > 0) FROM orders WHERE dt = '2024-01-15';
-- 如果断言失败，查询报错终止

-- 在 INSERT 前验证数据质量
INSERT OVERWRITE TABLE clean_orders PARTITION (dt = '2024-01-15')
SELECT id, user_id, amount, order_time
FROM staging_orders
WHERE amount >= 0 AND user_id IS NOT NULL;

-- 将无效数据路由到拒绝表
INSERT OVERWRITE TABLE rejected_orders PARTITION (dt = '2024-01-15')
SELECT *, 'validation_failed' AS reason
FROM staging_orders
WHERE amount < 0 OR user_id IS NULL;

-- ============================================================
-- 4. 配置级别的错误控制
-- ============================================================
-- 动态分区限制（防止意外创建过多分区）
SET hive.exec.max.dynamic.partitions = 1000;           -- 总分区数上限
SET hive.exec.max.dynamic.partitions.pernode = 100;    -- 每节点分区数上限
SET hive.exec.max.created.files = 100000;              -- 最大创建文件数

-- 查询超时
SET hive.server2.idle.operation.timeout = 3600000;     -- 空闲操作超时 (1小时)
SET hive.server2.idle.session.timeout = 7200000;       -- 空闲会话超时 (2小时)
SET hive.query.timeout.seconds = 600;                  -- 查询超时 (10分钟)

-- MapReduce/Tez 资源限制
SET mapreduce.map.memory.mb = 4096;
SET mapreduce.reduce.memory.mb = 8192;
SET hive.tez.container.size = 4096;

-- 跳过损坏的输入数据
SET hive.exec.orc.tolerant.reader = true;              -- ORC 容错读取
SET mapreduce.map.skip.maxrecords = 100;               -- 跳过损坏记录

-- ============================================================
-- 5. 应用层错误处理
-- ============================================================
-- Python (PyHive)
-- try:
--     cursor.execute('INSERT OVERWRITE TABLE results PARTITION (dt="2024-01-15") ...')
-- except hive.OperationalError as e:
--     if 'Table not found' in str(e):
--         create_table()
--         cursor.execute(...)
--     else:
--         raise
-- finally:
--     cursor.close()

-- Java (JDBC)
-- try {
--     stmt.execute("INSERT OVERWRITE TABLE results PARTITION ...");
-- } catch (SQLException e) {
--     logger.error("SQLState: " + e.getSQLState());
--     logger.error("ErrorCode: " + e.getErrorCode());
--     // 重试逻辑
-- }

-- ============================================================
-- 6. 常见错误场景与处理策略
-- ============================================================
-- 错误场景                    处理策略
-- 表不存在                    IF NOT EXISTS / 前置检查
-- 分区不存在                  IF EXISTS / MSCK REPAIR TABLE
-- 权限不足                    Ranger 策略 / GRANT
-- YARN 资源不足               调整 container 大小 / 队列
-- 数据格式错误                hive.exec.orc.tolerant.reader
-- 数据倾斜(OOM)              MAPJOIN / skew join 优化
-- 小文件过多                  CONCATENATE / INSERT OVERWRITE 合并
-- Metastore 连接超时          HMS HA / 重试策略

-- ============================================================
-- 7. 跨引擎对比: 错误处理能力
-- ============================================================
-- 引擎          错误处理方式                   设计理由
-- MySQL         DECLARE HANDLER / SIGNAL       存储过程中的结构化异常处理
-- PostgreSQL    EXCEPTION WHEN (PL/pgSQL)      完整的异常捕获和处理
-- Oracle        EXCEPTION WHEN (PL/SQL)        最成熟的过程式异常处理
-- SQL Server    TRY/CATCH                      T-SQL 的结构化异常处理
-- Hive          无（外部编排 + 配置控制）      批处理: 作业级重试
-- Spark SQL     try/catch (Scala/Python)        编程语言级别的错误处理
-- BigQuery      无（Scripting 有限支持）        云托管: 自动重试
-- Flink SQL     框架级重试（checkpoint）        流处理: 自动故障恢复

-- ============================================================
-- 8. 对引擎开发者的启示
-- ============================================================
-- 1. 批处理引擎的错误处理在作业级别而非语句级别:
--    Hive 证明了"整体重试"比"语句级异常处理"更适合批处理场景
-- 2. 幂等写入是错误恢复的基础:
--    INSERT OVERWRITE 使得重试不会产生重复数据，这比 try/catch 更重要
-- 3. 配置驱动的错误容忍度: 通过参数控制（最大分区数、超时、跳过损坏记录）
--    比在 SQL 中写 try/catch 更适合批处理
-- 4. IF NOT EXISTS 应该是所有 DDL 的默认行为:
--    在可重复执行的环境中，DDL 幂等性比抛异常更有用
-- 5. assert_true() 是数据质量检查的好模式:
--    在 SQL 中嵌入断言，比 try/catch 更直观
