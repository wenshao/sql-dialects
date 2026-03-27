-- Hive: 触发器
--
-- 参考资料:
--   [1] Apache Hive Language Manual
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual
--   [2] Apache Hive - Hive Transactions
--       https://cwiki.apache.org/confluence/display/Hive/Hive+Transactions

-- Hive 不支持触发器
-- 使用以下替代方案实现类似功能

-- ============================================================
-- 替代方案 1: 物化视图（Hive 3.0+）
-- ============================================================

-- 物化视图自动维护聚合结果
CREATE MATERIALIZED VIEW mv_daily_orders AS
SELECT
    dt,
    COUNT(*) AS order_count,
    SUM(amount) AS total_amount
FROM orders
GROUP BY dt;

-- 自动重写查询使用物化视图
-- 类似 AFTER INSERT 触发器的聚合更新功能

-- 手动重建物化视图
ALTER MATERIALIZED VIEW mv_daily_orders REBUILD;

-- ============================================================
-- 替代方案 2: 调度工具（最常用）
-- ============================================================

-- 使用 Oozie、Airflow、DataWorks 等调度工具
-- 在 Hive 作业执行前后插入额外的处理步骤

-- Oozie Workflow 示例结构：
-- <action name="validate">... 数据验证 ...</action>
-- <action name="load_data">... INSERT INTO ...</action>
-- <action name="audit_log">... 记录审计日志 ...</action>

-- ============================================================
-- 替代方案 3: ETL 管道中的数据验证
-- ============================================================

-- 在 INSERT 之前验证数据（类似 BEFORE INSERT 触发器）
-- 步骤 1: 检查数据质量
SELECT COUNT(*) AS invalid_count
FROM staging_orders
WHERE amount < 0 OR user_id IS NULL;

-- 步骤 2: 只加载有效数据
INSERT INTO TABLE orders PARTITION (dt = '20240115')
SELECT id, user_id, amount, order_time
FROM staging_orders
WHERE amount >= 0 AND user_id IS NOT NULL;

-- 步骤 3: 记录被拒绝的数据
INSERT INTO TABLE rejected_orders PARTITION (dt = '20240115')
SELECT *, 'validation failed' AS reason
FROM staging_orders
WHERE amount < 0 OR user_id IS NULL;

-- ============================================================
-- 替代方案 4: 事件通知（Hive Metastore 事件）
-- ============================================================

-- Hive Metastore 发出事件通知：
-- CREATE_TABLE, DROP_TABLE, ALTER_TABLE
-- ADD_PARTITION, DROP_PARTITION
-- INSERT

-- 通过监听 Metastore 事件实现触发器效果
-- 需要配置 hive.metastore.event.listeners

-- ============================================================
-- 替代方案 5: Hive Hook（元数据钩子）
-- ============================================================

-- Hive 支持 Hook 机制，在查询执行的不同阶段插入自定义逻辑
-- hive.exec.pre.hooks: 查询执行前
-- hive.exec.post.hooks: 查询执行后
-- hive.exec.failure.hooks: 查询失败时

-- 配置示例（hive-site.xml）：
-- <property>
--   <name>hive.exec.post.hooks</name>
--   <value>com.example.AuditHook</value>
-- </property>

-- ============================================================
-- 替代方案 6: HBase 触发器（Coprocessor）
-- ============================================================

-- 如果使用 HBase 作为 Hive 的存储后端
-- 可以使用 HBase Coprocessor 实现行级触发器
-- 但这不是纯 Hive 方案

-- 注意：Hive 是批处理引擎，不支持行级触发器
-- 注意：调度工具是实现自动化处理的标准方式
-- 注意：物化视图可以自动维护聚合数据
-- 注意：Hive Hook 可以在查询执行前后插入自定义逻辑
-- 注意：Metastore 事件可以通知外部系统
