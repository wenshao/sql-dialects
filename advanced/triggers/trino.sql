-- Trino (formerly PrestoSQL): 触发器
--
-- 参考资料:
--   [1] Trino - SQL Statement List
--       https://trino.io/docs/current/sql.html
--   [2] Trino - Connectors
--       https://trino.io/docs/current/connector.html

-- Trino 不支持触发器
-- Trino 是查询引擎，不管理数据生命周期

-- ============================================================
-- 底层系统的触发器能力
-- ============================================================

-- Trino 连接的底层系统可能支持触发器：
-- PostgreSQL Connector: PostgreSQL 支持完整的触发器
-- MySQL Connector: MySQL 支持触发器
-- Hive Connector: Hive 不支持触发器
-- Iceberg Connector: 不支持触发器

-- 通过底层系统创建的触发器会在底层数据变更时生效
-- 但这些触发器对 Trino 透明，Trino 无法管理它们

-- ============================================================
-- 替代方案 1: 底层 RDBMS 触发器
-- ============================================================

-- 如果 Trino 连接 PostgreSQL，在 PostgreSQL 中创建触发器
-- PostgreSQL 的触发器会在通过 Trino 或直接写入时生效

-- 示例（在 PostgreSQL 中执行，不是在 Trino 中）：
-- CREATE TRIGGER trg_audit AFTER INSERT ON users
-- FOR EACH ROW EXECUTE FUNCTION audit_insert();

-- ============================================================
-- 替代方案 2: Iceberg 表维护操作
-- ============================================================

-- Iceberg 支持表维护操作，类似定时触发器

-- 过期快照清理
ALTER TABLE iceberg.mydb.orders EXECUTE expire_snapshots(retention_threshold => '7d');

-- 清理孤立文件
ALTER TABLE iceberg.mydb.orders EXECUTE remove_orphan_files(retention_threshold => '7d');

-- 优化文件大小
ALTER TABLE iceberg.mydb.orders EXECUTE optimize(file_size_threshold => '10MB');

-- ============================================================
-- 替代方案 3: 外部编排工具
-- ============================================================

-- 使用 Airflow / dbt / Dagster 等工具
-- 在 Trino 查询前后执行额外的逻辑

-- Airflow DAG 示例结构：
-- task_validate >> task_insert >> task_audit >> task_notify

-- dbt 示例：
-- pre-hook: "INSERT INTO audit_log VALUES ('start', CURRENT_TIMESTAMP)"
-- post-hook: "INSERT INTO audit_log VALUES ('end', CURRENT_TIMESTAMP)"

-- ============================================================
-- 替代方案 4: 使用 INSERT ... SELECT 管道
-- ============================================================

-- 步骤 1: 验证数据（类似 BEFORE INSERT）
-- 如果查询返回结果则说明数据有问题
SELECT * FROM staging_data WHERE amount < 0;

-- 步骤 2: 插入数据
INSERT INTO orders SELECT * FROM staging_data WHERE amount >= 0;

-- 步骤 3: 更新汇总（类似 AFTER INSERT）
INSERT INTO daily_summary
SELECT DATE(order_date), COUNT(*), SUM(amount)
FROM staging_data
WHERE amount >= 0
GROUP BY DATE(order_date);

-- ============================================================
-- 替代方案 5: 物化视图（部分 Connector）
-- ============================================================

-- Iceberg Connector 不支持物化视图
-- 需要通过 Trino 的 CTAS + 定时刷新实现

-- 创建汇总表
CREATE TABLE summary AS SELECT ... FROM orders GROUP BY ...;

-- 定时重建（通过外部调度）
DROP TABLE IF EXISTS summary;
CREATE TABLE summary AS SELECT ... FROM orders GROUP BY ...;

-- 注意：Trino 是查询引擎，不支持触发器
-- 注意：数据生命周期管理由底层存储系统负责
-- 注意：RDBMS Connector 的底层触发器仍然生效
-- 注意：推荐使用外部编排工具（Airflow/dbt）实现自动化
-- 注意：Iceberg 的表维护操作可以定期清理和优化数据
