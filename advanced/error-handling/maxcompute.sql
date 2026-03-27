-- MaxCompute (ODPS): Error Handling
--
-- 参考资料:
--   [1] MaxCompute Documentation
--       https://www.alibabacloud.com/help/en/maxcompute/

-- ============================================================
-- MaxCompute 不支持服务端错误处理
-- ============================================================
-- MaxCompute 是大数据批处理引擎，不支持存储过程或异常处理

-- ============================================================
-- 应用层替代方案 (PyODPS)
-- ============================================================
-- from odps import ODPS, errors
--
-- o = ODPS('access_id', 'access_key', 'project', 'endpoint')
--
-- try:
--     o.execute_sql('SELECT * FROM nonexistent_table')
-- except errors.ODPSError as e:
--     print(f'MaxCompute error: {e}')
-- except errors.NoSuchObject as e:
--     print(f'Table not found: {e}')

-- ============================================================
-- 应用层替代方案 (Java SDK)
-- ============================================================
-- import com.aliyun.odps.OdpsException;
--
-- try {
--     odps.instances().create(task);
-- } catch (OdpsException e) {
--     System.err.println("Error code: " + e.getErrorCode());
--     System.err.println("Message: " + e.getMessage());
-- }

-- ============================================================
-- SQL 层面的错误避免
-- ============================================================
-- IF NOT EXISTS 防止重复创建
CREATE TABLE IF NOT EXISTS users (id BIGINT, name STRING);

-- IF EXISTS 防止删除不存在的表
DROP TABLE IF EXISTS temp_table;

-- 安全的分区操作
ALTER TABLE users ADD IF NOT EXISTS PARTITION (dt='2025-01-01');
ALTER TABLE users DROP IF EXISTS PARTITION (dt='2025-01-01');

-- ============================================================
-- 常见错误码
-- ============================================================
-- ODPS-0010000: 系统内部错误
-- ODPS-0110061: 表不存在
-- ODPS-0110111: 分区不存在
-- ODPS-0120006: 语法错误
-- ODPS-0130013: 权限不足
-- ODPS-0130071: 资源不足

-- ============================================================
-- 任务状态检查
-- ============================================================
-- 使用 SHOW 命令查看任务状态:
-- SHOW INSTANCES;
-- SHOW P;           -- 查看当前正在运行的任务

-- 注意：MaxCompute 面向大数据批处理，不支持服务端错误处理
-- 注意：使用 PyODPS 或 Java SDK 在应用层捕获错误
-- 注意：SQL 层面使用 IF EXISTS / IF NOT EXISTS 避免常见错误
-- 限制：无 TRY/CATCH, EXCEPTION WHEN, DECLARE HANDLER, SIGNAL
