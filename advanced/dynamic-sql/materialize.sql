-- Materialize: Dynamic SQL
--
-- 参考资料:
--   [1] Materialize Documentation - SQL Reference
--       https://materialize.com/docs/sql/

-- ============================================================
-- PREPARE / EXECUTE / DEALLOCATE (PostgreSQL 兼容)
-- ============================================================
PREPARE user_query(INT) AS SELECT * FROM users WHERE age > $1;
EXECUTE user_query(25);
DEALLOCATE user_query;

-- ============================================================
-- 应用层动态 SQL (PostgreSQL 驱动)
-- ============================================================
-- import psycopg2
-- conn = psycopg2.connect("host=localhost port=6875 dbname=materialize user=materialize")
-- cursor = conn.cursor()
-- cursor.execute('SELECT * FROM users WHERE age > %s', (18,))

-- 注意：Materialize 兼容 PostgreSQL wire protocol
-- 注意：PREPARE / EXECUTE 可用
-- 限制：无存储过程 / PL/pgSQL
-- 限制：无 EXECUTE IMMEDIATE
-- 限制：Materialize 面向增量计算，动态 SQL 场景有限
