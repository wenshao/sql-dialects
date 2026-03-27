-- Oracle: Dynamic SQL
--
-- 参考资料:
--   [1] Oracle PL/SQL Reference - EXECUTE IMMEDIATE
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/lnpls/EXECUTE-IMMEDIATE-statement.html
--   [2] Oracle PL/SQL Reference - DBMS_SQL Package
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/arpls/DBMS_SQL.html
--   [3] Oracle PL/SQL Reference - Dynamic SQL
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/lnpls/dynamic-sql.html

-- ============================================================
-- EXECUTE IMMEDIATE (原生动态 SQL, NDS)
-- ============================================================
-- 基本用法
BEGIN
    EXECUTE IMMEDIATE 'CREATE TABLE test_tbl (id NUMBER, name VARCHAR2(100))';
END;
/

-- 带 INTO 子句（单行查询）
DECLARE
    v_count NUMBER;
BEGIN
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM users' INTO v_count;
    DBMS_OUTPUT.PUT_LINE('Count: ' || v_count);
END;
/

-- ============================================================
-- EXECUTE IMMEDIATE ... USING (参数化，防止 SQL 注入)
-- ============================================================
DECLARE
    v_name VARCHAR2(100);
    v_age  NUMBER;
BEGIN
    EXECUTE IMMEDIATE
        'SELECT name, age FROM users WHERE id = :id'
        INTO v_name, v_age
        USING 42;
    DBMS_OUTPUT.PUT_LINE(v_name || ', ' || v_age);
END;
/

-- DML 带参数
DECLARE
    v_rows NUMBER;
BEGIN
    EXECUTE IMMEDIATE
        'UPDATE users SET status = :s WHERE age > :a'
        USING 'active', 18;
    v_rows := SQL%ROWCOUNT;
    DBMS_OUTPUT.PUT_LINE('Updated: ' || v_rows || ' rows');
END;
/

-- ============================================================
-- EXECUTE IMMEDIATE 返回结果集 (BULK COLLECT)
-- ============================================================
DECLARE
    TYPE user_tab IS TABLE OF users%ROWTYPE;
    v_users user_tab;
BEGIN
    EXECUTE IMMEDIATE
        'SELECT * FROM users WHERE status = :s'
        BULK COLLECT INTO v_users
        USING 'active';

    FOR i IN 1..v_users.COUNT LOOP
        DBMS_OUTPUT.PUT_LINE(v_users(i).username);
    END LOOP;
END;
/

-- ============================================================
-- 动态游标 (REF CURSOR)
-- ============================================================
DECLARE
    TYPE ref_cur IS REF CURSOR;
    v_cur   ref_cur;
    v_id    NUMBER;
    v_name  VARCHAR2(100);
BEGIN
    OPEN v_cur FOR
        'SELECT id, name FROM users WHERE age > :min_age'
        USING 25;
    LOOP
        FETCH v_cur INTO v_id, v_name;
        EXIT WHEN v_cur%NOTFOUND;
        DBMS_OUTPUT.PUT_LINE(v_id || ': ' || v_name);
    END LOOP;
    CLOSE v_cur;
END;
/

-- ============================================================
-- DBMS_SQL 包 (完全动态 SQL)
-- ============================================================
DECLARE
    v_cursor INTEGER;
    v_rows   INTEGER;
    v_id     NUMBER;
    v_name   VARCHAR2(100);
BEGIN
    v_cursor := DBMS_SQL.OPEN_CURSOR;
    DBMS_SQL.PARSE(v_cursor, 'SELECT id, name FROM users WHERE age > :age', DBMS_SQL.NATIVE);
    DBMS_SQL.BIND_VARIABLE(v_cursor, ':age', 25);
    DBMS_SQL.DEFINE_COLUMN(v_cursor, 1, v_id);
    DBMS_SQL.DEFINE_COLUMN(v_cursor, 2, v_name, 100);
    v_rows := DBMS_SQL.EXECUTE(v_cursor);

    WHILE DBMS_SQL.FETCH_ROWS(v_cursor) > 0 LOOP
        DBMS_SQL.COLUMN_VALUE(v_cursor, 1, v_id);
        DBMS_SQL.COLUMN_VALUE(v_cursor, 2, v_name);
        DBMS_OUTPUT.PUT_LINE(v_id || ': ' || v_name);
    END LOOP;
    DBMS_SQL.CLOSE_CURSOR(v_cursor);
END;
/

-- ============================================================
-- 存储过程中的动态 SQL
-- ============================================================
CREATE OR REPLACE PROCEDURE dynamic_search(
    p_table  IN VARCHAR2,
    p_column IN VARCHAR2,
    p_value  IN VARCHAR2,
    p_result OUT SYS_REFCURSOR
) AS
    v_sql VARCHAR2(4000);
BEGIN
    -- DBMS_ASSERT 防止 SQL 注入
    v_sql := 'SELECT * FROM '
             || DBMS_ASSERT.SQL_OBJECT_NAME(p_table)
             || ' WHERE '
             || DBMS_ASSERT.SIMPLE_SQL_NAME(p_column)
             || ' = :val';
    OPEN p_result FOR v_sql USING p_value;
END;
/

-- ============================================================
-- 动态 DDL
-- ============================================================
CREATE OR REPLACE PROCEDURE create_partition_table(p_year IN NUMBER) AS
BEGIN
    EXECUTE IMMEDIATE
        'CREATE TABLE orders_' || p_year || ' AS SELECT * FROM orders WHERE EXTRACT(YEAR FROM order_date) = :yr'
        USING p_year;
END;
/

-- 版本说明：
--   Oracle 8i+   : EXECUTE IMMEDIATE (NDS)
--   Oracle 8i+   : DBMS_SQL 包
--   Oracle 11g+  : DBMS_ASSERT 安全验证
--   Oracle 12c+  : DBMS_SQL.RETURN_RESULT
-- 注意：NDS (EXECUTE IMMEDIATE) 比 DBMS_SQL 更简洁，首选
-- 注意：DBMS_SQL 适用于列数量/类型在运行时才知道的场景
-- 注意：使用绑定变量 (:name) 防止 SQL 注入和提高性能
-- 注意：DBMS_ASSERT 可用于验证标识符（表名、列名）
-- 限制：EXECUTE IMMEDIATE 每次只能返回单行（多行需 BULK COLLECT）
-- 限制：DDL 不支持绑定变量
