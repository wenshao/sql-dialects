-- Snowflake: Dynamic SQL
--
-- 参考资料:
--   [1] Snowflake Documentation - EXECUTE IMMEDIATE
--       https://docs.snowflake.com/en/sql-reference/sql/execute-immediate
--   [2] Snowflake Documentation - Stored Procedures
--       https://docs.snowflake.com/en/sql-reference/stored-procedures-overview

-- ============================================================
-- EXECUTE IMMEDIATE
-- ============================================================
EXECUTE IMMEDIATE 'SELECT * FROM users WHERE id = 1';

-- 使用变量
EXECUTE IMMEDIATE 'CREATE TABLE test_tbl (id INT, name VARCHAR(100))';

-- ============================================================
-- EXECUTE IMMEDIATE ... USING (参数化)
-- ============================================================
EXECUTE IMMEDIATE 'SELECT * FROM users WHERE age > ? AND status = ?'
    USING (18, 'active');

-- ============================================================
-- Snowflake Scripting (SQL 存储过程)
-- ============================================================
CREATE OR REPLACE PROCEDURE count_table(p_table VARCHAR)
RETURNS INTEGER
LANGUAGE SQL
AS
$$
DECLARE
    row_count INTEGER;
    sql_text VARCHAR;
BEGIN
    sql_text := 'SELECT COUNT(*) FROM ' || p_table;
    EXECUTE IMMEDIATE sql_text INTO :row_count;
    RETURN row_count;
END;
$$;

CALL count_table('users');

-- ============================================================
-- EXECUTE IMMEDIATE ... INTO
-- ============================================================
CREATE OR REPLACE PROCEDURE get_user_count(p_status VARCHAR)
RETURNS INTEGER
LANGUAGE SQL
AS
$$
DECLARE
    cnt INTEGER;
BEGIN
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM users WHERE status = ?'
        INTO :cnt
        USING (p_status);
    RETURN cnt;
END;
$$;

-- ============================================================
-- JavaScript 存储过程中的动态 SQL
-- ============================================================
CREATE OR REPLACE PROCEDURE dynamic_js(TABLE_NAME VARCHAR)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
AS
$$
    var sql = "SELECT COUNT(*) AS CNT FROM " + TABLE_NAME;
    var stmt = snowflake.createStatement({sqlText: sql});
    var rs = stmt.execute();
    rs.next();
    return rs.getColumnValue(1);
$$;

-- ============================================================
-- RESULTSET 和游标
-- ============================================================
CREATE OR REPLACE PROCEDURE process_dynamic(p_table VARCHAR)
RETURNS TABLE()
LANGUAGE SQL
AS
$$
DECLARE
    res RESULTSET;
    sql_text VARCHAR;
BEGIN
    sql_text := 'SELECT * FROM ' || p_table || ' LIMIT 100';
    res := (EXECUTE IMMEDIATE :sql_text);
    RETURN TABLE(res);
END;
$$;

-- 版本说明：
--   Snowflake : EXECUTE IMMEDIATE (全版本)
--   Snowflake : Snowflake Scripting (2021+)
-- 注意：使用 USING 子句参数化值，防止 SQL 注入
-- 注意：Snowflake Scripting 使用 :variable 引用变量
-- 注意：也支持 JavaScript/Python/Java 存储过程
-- 限制：无 PREPARE / DEALLOCATE
