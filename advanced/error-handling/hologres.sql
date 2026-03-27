-- Hologres: Error Handling
--
-- 参考资料:
--   [1] Hologres Documentation
--       https://www.alibabacloud.com/help/en/hologres/

-- ============================================================
-- PostgreSQL 兼容的错误处理（有限支持）
-- ============================================================
-- Hologres 兼容 PostgreSQL 协议，但存储过程支持有限

-- 应用层替代方案 (psycopg2):
-- try:
--     cursor.execute('INSERT INTO users VALUES(1, \'test\')')
-- except psycopg2.IntegrityError as e:
--     print(f'Constraint error: {e}')
-- except psycopg2.Error as e:
--     print(f'Database error: {e}')

-- SQL 层面的错误避免
CREATE TABLE IF NOT EXISTS users (id INT, name TEXT);
INSERT INTO users SELECT 1, 'test' WHERE NOT EXISTS (SELECT 1 FROM users WHERE id = 1);

-- 注意：Hologres 兼容 PostgreSQL 错误码
-- 限制：存储过程和 PL/pgSQL 支持有限
