-- Apache Impala: Error Handling
--
-- 参考资料:
--   [1] Apache Impala SQL Reference
--       https://impala.apache.org/docs/build/html/topics/impala_langref.html

-- ============================================================
-- Impala 不支持服务端错误处理
-- ============================================================
-- Impala 不支持存储过程或异常处理

-- 应用层替代方案 (Python/impyla):
-- from impala.error import HiveServer2Error
-- try:
--     cursor.execute('SELECT * FROM nonexistent_table')
-- except HiveServer2Error as e:
--     print(f'Impala error: {e}')

-- SQL 层面的错误避免
CREATE TABLE IF NOT EXISTS users (id INT, name STRING);
DROP TABLE IF EXISTS temp_table;

-- 注意：Impala 面向交互式 OLAP，不支持服务端错误处理
-- 限制：无 TRY/CATCH, EXCEPTION WHEN, DECLARE HANDLER
