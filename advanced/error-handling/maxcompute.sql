-- MaxCompute (ODPS): Error Handling
--
-- 参考资料:
--   [1] MaxCompute Documentation
--       https://www.alibabacloud.com/help/en/maxcompute/

-- ============================================================
-- MaxCompute 不支持服务端错误处理
-- ============================================================

-- 应用层替代方案 (PyODPS):
-- from odps import errors
-- try:
--     o.execute_sql('SELECT * FROM nonexistent_table')
-- except errors.ODPSError as e:
--     print(f'MaxCompute error: {e}')

-- SQL 层面的错误避免
CREATE TABLE IF NOT EXISTS users (id BIGINT, name STRING);

-- 注意：MaxCompute 面向大数据批处理，不支持服务端错误处理
-- 限制：无 TRY/CATCH, EXCEPTION WHEN, DECLARE HANDLER
