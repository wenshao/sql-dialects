-- DuckDB: Error Handling
--
-- 参考资料:
--   [1] DuckDB Documentation
--       https://duckdb.org/docs/

-- ============================================================
-- DuckDB 没有服务端错误处理
-- ============================================================
-- DuckDB 是嵌入式 OLAP 数据库，不支持存储过程或异常处理

-- ============================================================
-- 应用层替代方案: Python
-- ============================================================
-- import duckdb
-- try:
--     conn.execute('INSERT INTO users VALUES (1, \'test\')')
-- except duckdb.ConstraintException as e:
--     print(f'Constraint error: {e}')
-- except duckdb.CatalogException as e:
--     print(f'Catalog error: {e}')
-- except duckdb.Error as e:
--     print(f'DuckDB error: {e}')

-- ============================================================
-- SQL 层面的错误避免
-- ============================================================
CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name VARCHAR);
INSERT OR IGNORE INTO users VALUES (1, 'test');

-- TRY_CAST 安全类型转换
SELECT TRY_CAST('abc' AS INTEGER);  -- 返回 NULL

-- 注意：DuckDB 不支持服务端错误处理
-- 注意：使用 TRY_CAST / INSERT OR IGNORE 避免常见错误
-- 限制：无存储过程或异常处理语法
