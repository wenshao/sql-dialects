-- Apache Doris: Error Handling
--
-- 参考资料:
--   [1] Apache Doris Documentation
--       https://doris.apache.org/docs/sql-manual/sql-statements/

-- ============================================================
-- Doris 不支持服务端错误处理
-- ============================================================
-- Doris 是 OLAP 引擎，不支持存储过程或异常处理

-- ============================================================
-- 应用层替代方案: Python
-- ============================================================
-- import pymysql
-- try:
--     cursor.execute('INSERT INTO users VALUES (1, "test")')
-- except pymysql.IntegrityError as e:
--     print(f'Constraint error: {e}')
-- except pymysql.Error as e:
--     print(f'Doris error: {e}')

-- ============================================================
-- SQL 层面的错误避免
-- ============================================================
CREATE TABLE IF NOT EXISTS users (id INT, name VARCHAR(100))
DISTRIBUTED BY HASH(id) BUCKETS 8;

-- 注意：Doris 面向 OLAP 场景，不支持服务端错误处理
-- 注意：错误处理在应用层通过 MySQL 协议驱动实现
-- 限制：无 TRY/CATCH, EXCEPTION WHEN, DECLARE HANDLER, SIGNAL
