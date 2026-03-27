-- PostgreSQL: Dynamic SQL
--
-- 参考资料:
--   [1] PostgreSQL Documentation - PREPARE
--       https://www.postgresql.org/docs/current/sql-prepare.html
--   [2] PostgreSQL Documentation - EXECUTE
--       https://www.postgresql.org/docs/current/sql-execute.html
--   [3] PostgreSQL Documentation - PL/pgSQL - Dynamic Commands
--       https://www.postgresql.org/docs/current/plpgsql-statements.html#PLPGSQL-STATEMENTS-EXECUTING-DYN

-- ============================================================
-- PREPARE / EXECUTE / DEALLOCATE (会话级预编译)
-- ============================================================
-- 准备参数化语句
PREPARE user_by_age(INT) AS
    SELECT * FROM users WHERE age > $1;

-- 执行
EXECUTE user_by_age(25);

-- 释放
DEALLOCATE user_by_age;

-- DEALLOCATE ALL 释放所有
DEALLOCATE ALL;

-- ============================================================
-- PL/pgSQL 中的 EXECUTE (动态 SQL 核心)
-- ============================================================
-- EXECUTE 可执行任意动态 SQL 字符串
CREATE OR REPLACE FUNCTION run_dynamic_query(p_table TEXT)
RETURNS SETOF RECORD AS $$
BEGIN
    RETURN QUERY EXECUTE 'SELECT * FROM ' || quote_ident(p_table);
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- EXECUTE ... USING (参数化动态 SQL，防止 SQL 注入)   -- 8.1+
-- ============================================================
CREATE OR REPLACE FUNCTION find_users_by_status(p_status TEXT, p_min_age INT)
RETURNS SETOF users AS $$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT * FROM users WHERE status = $1 AND age >= $2'
        USING p_status, p_min_age;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- EXECUTE ... INTO (将结果存入变量)
-- ============================================================
CREATE OR REPLACE FUNCTION count_rows(p_table TEXT)
RETURNS BIGINT AS $$
DECLARE
    row_count BIGINT;
BEGIN
    EXECUTE 'SELECT COUNT(*) FROM ' || quote_ident(p_table) INTO row_count;
    RETURN row_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- format() 构建安全的动态 SQL                        -- 9.1+
-- ============================================================
CREATE OR REPLACE FUNCTION dynamic_insert(p_table TEXT, p_name TEXT, p_value INT)
RETURNS VOID AS $$
BEGIN
    -- %I = 标识符 (自动加引号), %L = 字面量 (自动转义)
    EXECUTE format('INSERT INTO %I (name, value) VALUES (%L, %L)', p_table, p_name, p_value);
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 动态 DDL
-- ============================================================
CREATE OR REPLACE FUNCTION create_partition(p_year INT)
RETURNS VOID AS $$
BEGIN
    EXECUTE format(
        'CREATE TABLE IF NOT EXISTS orders_%s PARTITION OF orders
         FOR VALUES FROM (%L) TO (%L)',
        p_year,
        p_year || '-01-01',
        (p_year + 1) || '-01-01'
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- DO 块 (匿名代码块执行动态 SQL)                     -- 9.0+
-- ============================================================
DO $$
DECLARE
    tbl RECORD;
BEGIN
    FOR tbl IN SELECT tablename FROM pg_tables WHERE schemaname = 'public'
    LOOP
        EXECUTE 'ANALYZE ' || quote_ident(tbl.tablename);
    END LOOP;
END;
$$;

-- ============================================================
-- 动态游标
-- ============================================================
CREATE OR REPLACE FUNCTION process_table(p_table TEXT)
RETURNS VOID AS $$
DECLARE
    cur REFCURSOR;
    rec RECORD;
BEGIN
    OPEN cur FOR EXECUTE 'SELECT * FROM ' || quote_ident(p_table);
    LOOP
        FETCH cur INTO rec;
        EXIT WHEN NOT FOUND;
        -- 处理记录
    END LOOP;
    CLOSE cur;
END;
$$ LANGUAGE plpgsql;

-- 版本说明：
--   PostgreSQL 8.1+  : EXECUTE ... USING 支持
--   PostgreSQL 9.0+  : DO 匿名块
--   PostgreSQL 9.1+  : format() 函数
-- 注意：始终使用 quote_ident() / quote_literal() / format(%I, %L) 防止 SQL 注入
-- 注意：PREPARE 是会话级的，不跨连接共享
-- 注意：PL/pgSQL EXECUTE 与 SQL EXECUTE 是不同的语句
-- 限制：EXECUTE 不支持直接返回多行结果集，需 RETURN QUERY EXECUTE
