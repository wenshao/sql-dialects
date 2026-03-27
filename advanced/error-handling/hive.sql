-- Apache Hive: Error Handling
--
-- 参考资料:
--   [1] Apache Hive Language Manual
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual

-- ============================================================
-- Hive 不支持服务端错误处理
-- ============================================================
-- Hive 不支持存储过程或异常处理

-- 应用层替代方案 (Python/PyHive):
-- try:
--     cursor.execute('SELECT * FROM nonexistent_table')
-- except Exception as e:
--     print(f'Hive error: {e}')

-- SQL 层面的错误避免
CREATE TABLE IF NOT EXISTS users (id INT, name STRING);
DROP TABLE IF EXISTS temp_table;

-- 注意：Hive 面向批处理，不支持服务端错误处理
-- 限制：无 TRY/CATCH, EXCEPTION WHEN, DECLARE HANDLER, SIGNAL
