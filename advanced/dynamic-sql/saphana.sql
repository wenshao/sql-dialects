-- SAP HANA: Dynamic SQL
--
-- 参考资料:
--   [1] SAP HANA SQL Reference - EXECUTE IMMEDIATE
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/20fdf93675191014a4b1e35c756e7a15.html
--   [2] SAP HANA SQLScript Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/de2486ee947e43e684d39702027f8a94/d12d86a0d3f04ebf9ac0cb3e5a700e50.html

-- ============================================================
-- EXEC / EXECUTE IMMEDIATE (SQLScript)
-- ============================================================
DO BEGIN
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM users';
END;

-- ============================================================
-- EXEC 带 INTO
-- ============================================================
DO BEGIN
    DECLARE v_count INTEGER;
    EXEC 'SELECT COUNT(*) FROM users' INTO v_count;
END;

-- ============================================================
-- 动态 SQL 带参数绑定
-- ============================================================
DO BEGIN
    DECLARE v_sql NVARCHAR(5000);
    DECLARE v_count INTEGER;
    v_sql := 'SELECT COUNT(*) FROM users WHERE age > ?';
    EXECUTE IMMEDIATE v_sql INTO v_count USING 18;
END;

-- ============================================================
-- 存储过程中的动态 SQL
-- ============================================================
CREATE PROCEDURE dynamic_search(
    IN p_table NVARCHAR(128),
    IN p_column NVARCHAR(128),
    IN p_value NVARCHAR(255)
)
LANGUAGE SQLSCRIPT
AS
BEGIN
    DECLARE v_sql NVARCHAR(5000);
    v_sql := 'SELECT * FROM "' || :p_table || '" WHERE "' || :p_column || '" = ?';
    EXECUTE IMMEDIATE v_sql USING p_value;
END;

-- ============================================================
-- APPLY_FILTER (动态过滤，推荐)                       -- 安全
-- ============================================================
CREATE PROCEDURE filter_users(IN p_filter NVARCHAR(5000))
LANGUAGE SQLSCRIPT
AS
BEGIN
    lt_users = SELECT * FROM users;
    lt_filtered = APPLY_FILTER(:lt_users, :p_filter);
    SELECT * FROM :lt_filtered;
END;
-- CALL filter_users('age > 18 AND status = ''active''');

-- ============================================================
-- 动态 DDL
-- ============================================================
CREATE PROCEDURE create_archive(IN p_year INTEGER)
LANGUAGE SQLSCRIPT
AS
BEGIN
    DECLARE v_sql NVARCHAR(5000);
    v_sql := 'CREATE TABLE "ORDERS_' || :p_year || '" AS (SELECT * FROM "ORDERS" WHERE YEAR("ORDER_DATE") = ' || :p_year || ')';
    EXECUTE IMMEDIATE v_sql;
END;

-- 版本说明：
--   SAP HANA 1.0+ : EXECUTE IMMEDIATE / EXEC
--   SAP HANA 2.0+ : APPLY_FILTER
-- 注意：SAP HANA 使用 SQLScript 作为过程语言
-- 注意：APPLY_FILTER 是动态过滤的安全替代方案
-- 注意：使用 USING 子句进行参数绑定防止 SQL 注入
-- 限制：标识符（表名、列名）不能通过 USING 参数化
