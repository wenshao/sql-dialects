-- TDengine: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] TDengine Documentation
--       https://docs.tdengine.com/reference/sql/

-- ============================================================
-- 注意: TDengine 是时序数据库，不适用于传统 SCD 模式
-- ============================================================
-- TDengine 数据模型以时间序列为核心:
-- - 超级表 (STABLE) 定义 schema
-- - 子表 (TABLE) 每个采集设备一个
-- - 标签 (TAG) 类似维度属性，可更新

-- 更新标签（类似 SCD Type 1）
ALTER TABLE sensor_001 SET TAG location = 'new_location';
ALTER TABLE sensor_001 SET TAG status = 'active';

-- 标签变化不保留历史（TDengine 不支持 SCD Type 2）
-- 如需跟踪标签变化历史，建议:
-- 1. 在应用层记录变更日志
-- 2. 使用外部数据库存储维度表
