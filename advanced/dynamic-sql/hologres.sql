-- Hologres: Dynamic SQL
--
-- 参考资料:
--   [1] Hologres Documentation
--       https://www.alibabacloud.com/help/en/hologres/

-- ============================================================
-- Hologres 兼容 PostgreSQL 协议
-- ============================================================
-- PREPARE / EXECUTE / DEALLOCATE
PREPARE user_query(INT) AS SELECT * FROM users WHERE age > $1;
EXECUTE user_query(25);
DEALLOCATE user_query;

-- ============================================================
-- PL/pgSQL 动态 SQL (有限支持)
-- ============================================================
-- Hologres 兼容部分 PostgreSQL PL/pgSQL 语法
-- 但主要面向 OLAP 场景，存储过程支持有限

-- ============================================================
-- 应用层替代方案
-- ============================================================
-- 使用 PostgreSQL 驱动连接 Hologres
-- import psycopg2
-- conn = psycopg2.connect(host='hologres-endpoint', port=80, dbname='mydb')
-- cursor = conn.cursor()
-- cursor.execute('SELECT * FROM users WHERE age > %s', (18,))

-- 注意：Hologres 兼容 PostgreSQL 协议和 SQL 语法
-- 注意：PREPARE / EXECUTE 可用
-- 限制：存储过程/PL/pgSQL 支持可能不完整
-- 限制：面向 OLAP，不建议在动态 SQL 中执行复杂事务
