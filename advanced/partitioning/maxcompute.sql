-- MaxCompute (ODPS): 表分区策略
--
-- 参考资料:
--   [1] MaxCompute Documentation - Partitioned Tables
--       https://help.aliyun.com/document_detail/73768.html

-- ============================================================
-- 分区表
-- ============================================================

CREATE TABLE orders (
    id BIGINT, user_id BIGINT, amount DECIMAL(10,2)
) PARTITIONED BY (dt STRING, region STRING);

-- ============================================================
-- 分区操作
-- ============================================================

-- 添加分区
ALTER TABLE orders ADD PARTITION (dt='2024-06-15', region='East');
ALTER TABLE orders ADD IF NOT EXISTS PARTITION (dt='2024-06-15', region='West');

-- 删除分区
ALTER TABLE orders DROP PARTITION (dt='2024-01-01', region='East');

-- 写入分区数据
INSERT OVERWRITE TABLE orders PARTITION (dt='2024-06-15', region='East')
SELECT id, user_id, amount FROM raw_orders
WHERE order_date = '2024-06-15' AND region = 'East';

-- 动态分区
INSERT OVERWRITE TABLE orders PARTITION (dt, region)
SELECT id, user_id, amount, order_date AS dt, region FROM raw_orders;

-- ============================================================
-- 查看分区
-- ============================================================

SHOW PARTITIONS orders;

-- ============================================================
-- 生命周期
-- ============================================================

-- 设置分区过期时间
ALTER TABLE orders SET LIFECYCLE 90;  -- 90 天

-- 注意：MaxCompute 分区对应 ODPS 的数据分区
-- 注意：分区是数据管理和查询优化的基本单元
-- 注意：INSERT OVERWRITE 覆盖指定分区数据
-- 注意：动态分区自动根据数据值创建分区
-- 注意：LIFECYCLE 设置分区自动过期删除
