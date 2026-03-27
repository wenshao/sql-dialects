-- Vertica: Dynamic SQL
--
-- 参考资料:
--   [1] Vertica Documentation - PL/vSQL
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/ProgrammersGuide/StoredProcedures/PLvSQL.htm
--   [2] Vertica Documentation - EXECUTE
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Statements/EXECUTE.htm

-- ============================================================
-- PREPARE / EXECUTE / DEALLOCATE (vsql)
-- ============================================================
PREPARE user_query AS SELECT * FROM users WHERE age > $1;
EXECUTE user_query(25);
DEALLOCATE user_query;

-- ============================================================
-- PL/vSQL EXECUTE (存储过程中的动态 SQL)               -- 11.0+
-- ============================================================
CREATE OR REPLACE PROCEDURE count_table(p_table VARCHAR)
LANGUAGE PLvSQL
AS $$
DECLARE
    row_count INT;
BEGIN
    EXECUTE 'SELECT COUNT(*) FROM ' || p_table INTO row_count;
    RAISE NOTICE 'Table % has % rows', p_table, row_count;
END;
$$;

-- ============================================================
-- EXECUTE ... USING (参数化动态 SQL)
-- ============================================================
CREATE OR REPLACE PROCEDURE find_users(p_status VARCHAR, p_age INT)
LANGUAGE PLvSQL
AS $$
BEGIN
    EXECUTE 'SELECT * FROM users WHERE status = $1 AND age >= $2'
        USING p_status, p_age;
END;
$$;

-- ============================================================
-- 动态 DDL
-- ============================================================
CREATE OR REPLACE PROCEDURE create_projection(p_table VARCHAR)
LANGUAGE PLvSQL
AS $$
BEGIN
    EXECUTE 'CREATE PROJECTION ' || p_table || '_proj AS SELECT * FROM ' || p_table
         || ' ORDER BY id SEGMENTED BY HASH(id) ALL NODES';
END;
$$;

-- 版本说明：
--   Vertica 9.x+   : PREPARE / EXECUTE
--   Vertica 11.0+  : PL/vSQL 存储过程
-- 注意：PL/vSQL 语法类似 PostgreSQL PL/pgSQL
-- 注意：使用参数化查询防止 SQL 注入
-- 限制：PL/vSQL 功能比 PostgreSQL PL/pgSQL 更有限
