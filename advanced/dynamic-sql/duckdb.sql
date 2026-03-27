-- DuckDB: Dynamic SQL
--
-- 参考资料:
--   [1] DuckDB Documentation - Prepared Statements
--       https://duckdb.org/docs/sql/query_syntax/prepared_statements
--   [2] DuckDB Documentation - Python API
--       https://duckdb.org/docs/api/python/overview

-- ============================================================
-- PREPARE / EXECUTE / DEALLOCATE
-- ============================================================
PREPARE user_query AS SELECT * FROM users WHERE age > $1;
EXECUTE user_query(25);
DEALLOCATE user_query;

-- 多个参数
PREPARE search AS SELECT * FROM users WHERE status = $1 AND age > $2;
EXECUTE search('active', 18);
DEALLOCATE search;

-- ============================================================
-- 应用层动态 SQL: Python
-- ============================================================
-- import duckdb
-- conn = duckdb.connect('mydb.duckdb')
--
-- # 参数化查询
-- conn.execute('SELECT * FROM users WHERE age > ? AND status = ?', [18, 'active'])
--
-- # 动态 SQL
-- table = 'users'
-- conn.execute(f'SELECT COUNT(*) FROM {table}')
--
-- # 使用 pandas 交互
-- df = conn.execute('SELECT * FROM users WHERE age > ?', [18]).fetchdf()

-- ============================================================
-- 应用层动态 SQL: CLI
-- ============================================================
-- duckdb mydb.duckdb -c "SELECT * FROM users WHERE age > 18"
-- echo "SELECT COUNT(*) FROM users" | duckdb mydb.duckdb

-- 注意：DuckDB 支持 PostgreSQL 风格的 PREPARE / EXECUTE
-- 注意：嵌入式使用时，通过 API 实现动态 SQL 更自然
-- 注意：使用 $1, $2 等位置参数进行参数化
-- 限制：无存储过程
-- 限制：无 EXECUTE IMMEDIATE
-- 限制：无 PL/pgSQL
