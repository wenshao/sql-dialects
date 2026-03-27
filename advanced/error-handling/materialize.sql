-- Materialize: Error Handling
--
-- 参考资料:
--   [1] Materialize Documentation
--       https://materialize.com/docs/sql/

-- ============================================================
-- Materialize 不支持服务端错误处理
-- ============================================================
-- Materialize 没有存储过程或异常处理语法

-- 应用层替代方案 (psycopg2):
-- try:
--     cursor.execute('CREATE SOURCE ...')
-- except psycopg2.Error as e:
--     print(f'Materialize error: {e.pgcode} - {e.pgerror}')

-- SQL 层面的错误避免
CREATE TABLE IF NOT EXISTS users (id INT, name TEXT);

-- 注意：Materialize 兼容 PostgreSQL 协议和错误码
-- 限制：无存储过程或异常处理语法
