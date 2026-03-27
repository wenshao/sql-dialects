-- MaxCompute (ODPS): Dynamic SQL
--
-- 参考资料:
--   [1] MaxCompute SQL Reference
--       https://www.alibabacloud.com/help/en/maxcompute/user-guide/sql-overview

-- ============================================================
-- MaxCompute 不支持服务端动态 SQL
-- ============================================================
-- MaxCompute 不支持存储过程或 PREPARE/EXECUTE

-- ============================================================
-- MaxCompute Script Mode (脚本模式)
-- ============================================================
-- MaxCompute 支持脚本模式，可以使用变量
SET @table_name = 'users';
-- 注意：变量不能用于表名替换

-- ============================================================
-- 应用层替代方案: Python (PyODPS)
-- ============================================================
-- from odps import ODPS
-- o = ODPS(access_id, access_key, project, endpoint)
--
-- # 动态 SQL
-- table_name = 'users'
-- result = o.execute_sql(f'SELECT COUNT(*) FROM {table_name}')
--
-- # 参数化不直接支持，需在应用层拼接（注意安全）

-- ============================================================
-- DataWorks 调度中的变量替换
-- ============================================================
-- SELECT * FROM ${table_name} WHERE dt = '${bizdate}';
-- 在 DataWorks 调度中支持 ${} 变量替换

-- 注意：MaxCompute 面向大数据批处理
-- 注意：使用 PyODPS SDK 或 DataWorks 调度实现动态 SQL
-- 限制：无 PREPARE / EXECUTE / EXECUTE IMMEDIATE
-- 限制：无存储过程
