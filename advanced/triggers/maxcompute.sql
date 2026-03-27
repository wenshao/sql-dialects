-- MaxCompute (ODPS): 触发器
--
-- 参考资料:
--   [1] MaxCompute SQL Overview
--       https://help.aliyun.com/zh/maxcompute/user-guide/sql-overview
--   [2] MaxCompute Documentation
--       https://help.aliyun.com/zh/maxcompute/

-- MaxCompute 不支持触发器
-- 使用以下替代方案实现类似功能

-- ============================================================
-- 替代方案 1: DataWorks 调度（最常用）
-- ============================================================

-- DataWorks 是 MaxCompute 的调度和编排平台
-- 通过定时任务和依赖关系实现类似触发器的效果

-- 数据依赖：当上游表（orders）有新分区时，自动触发下游任务
-- 配置方式：在 DataWorks 中设置节点依赖

-- 示例调度任务（在 DataWorks 中配置）：
-- 任务1: 每天凌晨处理前一天的订单数据
-- INSERT OVERWRITE TABLE daily_summary PARTITION (dt = '${bizdate}')
-- SELECT
--     user_id,
--     COUNT(*) AS order_count,
--     SUM(amount) AS total_amount
-- FROM orders
-- WHERE dt = '${bizdate}'
-- GROUP BY user_id;

-- ============================================================
-- 替代方案 2: MaxCompute 分区事件监听
-- ============================================================

-- 通过事件驱动模型，监听分区提交事件
-- 当新分区写入时，自动触发下游处理

-- 在 DataWorks 中配置事件触发器：
-- 事件类型: PARTITION_COMMIT
-- 触发条件: 指定表的分区提交

-- ============================================================
-- 替代方案 3: 数据质量监控
-- ============================================================

-- DataWorks 数据质量模块可以在数据变更后自动检查
-- 类似 BEFORE INSERT 触发器的验证功能

-- 规则示例：
-- 1. 表行数波动不超过 20%
-- 2. 关键列空值率不超过 1%
-- 3. 唯一性检查

-- ============================================================
-- 替代方案 4: ETL 管道中嵌入逻辑
-- ============================================================

-- 在 INSERT 操作前后添加验证和审计逻辑
-- 步骤 1: 验证源数据
-- SELECT COUNT(*) FROM staging_data WHERE amount < 0;

-- 步骤 2: 插入数据
INSERT OVERWRITE TABLE orders PARTITION (dt = '20240115')
SELECT id, user_id, amount, order_time
FROM staging_data
WHERE amount >= 0;     -- 过滤无效数据（类似 BEFORE INSERT 触发器）

-- 步骤 3: 记录审计信息
INSERT INTO audit_log PARTITION (dt = '20240115')
SELECT 'orders', 'INSERT', COUNT(*), GETDATE()
FROM orders WHERE dt = '20240115';

-- ============================================================
-- 替代方案 5: 实时计算（Flink on MaxCompute）
-- ============================================================

-- 使用 Flink 实时处理数据流
-- 通过 CDC（Change Data Capture）捕获变更
-- 实现实时的触发器效果

-- ============================================================
-- 替代方案 6: 物化视图
-- ============================================================

-- 物化视图可以自动维护汇总数据
CREATE MATERIALIZED VIEW mv_order_summary
LIFECYCLE 365
AS
SELECT user_id, COUNT(*) AS cnt, SUM(amount) AS total
FROM orders
GROUP BY user_id;

-- 注意：MaxCompute 是批处理引擎，不支持行级触发器
-- 注意：DataWorks 调度是最主要的自动化方式
-- 注意：分区事件监听可以实现"数据到达即处理"
-- 注意：实时场景使用 Flink 替代
-- 注意：数据质量监控替代了验证类触发器
