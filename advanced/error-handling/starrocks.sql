-- StarRocks: Error Handling
--
-- 参考资料:
--   [1] StarRocks Documentation
--       https://docs.starrocks.io/docs/sql-reference/

-- ============================================================
-- StarRocks 不支持服务端错误处理
-- ============================================================
-- StarRocks 不支持存储过程或异常处理

-- 应用层替代方案 (Python/pymysql):
-- try:
--     cursor.execute('INSERT INTO users VALUES(1, "test")')
-- except pymysql.IntegrityError:
--     print('Constraint violation')

-- SQL 层面的错误避免
CREATE TABLE IF NOT EXISTS users (id INT, name VARCHAR(100))
DISTRIBUTED BY HASH(id) BUCKETS 8;

-- 注意：StarRocks 兼容 MySQL 协议
-- 限制：无存储过程或异常处理语法
