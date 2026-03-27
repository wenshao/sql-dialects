-- TDengine: Error Handling
--
-- 参考资料:
--   [1] TDengine Documentation
--       https://docs.tdengine.com/reference/sql/

-- ============================================================
-- TDengine 不支持服务端错误处理
-- ============================================================
-- TDengine 是时序数据库，不支持存储过程或异常处理

-- 应用层替代方案 (Python/taospy):
-- import taos
-- try:
--     conn.execute('INSERT INTO meters VALUES(NOW, 10.5)')
-- except taos.error.ProgrammingError as e:
--     print(f'TDengine error: {e}')

-- TDengine 错误码:
-- 0x0200 : 无效的参数
-- 0x0300 : 表不存在
-- 0x0388 : 数据库不存在

-- SQL 层面的错误避免
CREATE TABLE IF NOT EXISTS meters (ts TIMESTAMP, val FLOAT) TAGS (location NCHAR(20));
CREATE DATABASE IF NOT EXISTS mydb;

-- 注意：TDengine 面向时序数据场景
-- 限制：无 SQL 级别的错误处理语法
