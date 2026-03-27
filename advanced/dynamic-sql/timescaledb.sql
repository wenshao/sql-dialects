-- TimescaleDB: Dynamic SQL
--
-- 参考资料:
--   [1] TimescaleDB Documentation
--       https://docs.timescale.com/
--   [2] PostgreSQL PL/pgSQL - Dynamic Commands
--       https://www.postgresql.org/docs/current/plpgsql-statements.html

-- ============================================================
-- TimescaleDB 基于 PostgreSQL，完全兼容其动态 SQL
-- ============================================================

-- PREPARE / EXECUTE / DEALLOCATE
PREPARE ts_query(TIMESTAMPTZ) AS
    SELECT * FROM sensor_data WHERE time > $1;
EXECUTE ts_query('2024-01-01');
DEALLOCATE ts_query;

-- ============================================================
-- PL/pgSQL EXECUTE (动态 SQL)
-- ============================================================
CREATE OR REPLACE FUNCTION query_hypertable(p_table TEXT, p_interval INTERVAL)
RETURNS SETOF RECORD AS $$
BEGIN
    RETURN QUERY EXECUTE format(
        'SELECT * FROM %I WHERE time > NOW() - $1',
        p_table
    ) USING p_interval;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 动态创建超表
-- ============================================================
CREATE OR REPLACE FUNCTION create_hypertable_dynamic(
    p_table TEXT,
    p_time_col TEXT DEFAULT 'time'
)
RETURNS VOID AS $$
BEGIN
    EXECUTE format(
        'CREATE TABLE IF NOT EXISTS %I (
            time TIMESTAMPTZ NOT NULL,
            device_id TEXT,
            value DOUBLE PRECISION
        )', p_table
    );
    PERFORM create_hypertable(p_table, p_time_col, if_not_exists => TRUE);
END;
$$ LANGUAGE plpgsql;

-- 注意：TimescaleDB 完全兼容 PostgreSQL 动态 SQL
-- 注意：使用 format(%I, %L) 防止 SQL 注入
-- 注意：可以动态创建和管理超表 (hypertable)
-- 限制：与 PostgreSQL 相同
