-- BigQuery: Dynamic SQL
--
-- 参考资料:
--   [1] BigQuery - EXECUTE IMMEDIATE
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/scripting#execute_immediate
--   [2] BigQuery - Scripting
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/scripting

-- ============================================================
-- EXECUTE IMMEDIATE (BigQuery Scripting)
-- ============================================================
EXECUTE IMMEDIATE 'SELECT * FROM `myproject.mydataset.users` WHERE id = 1';

-- 使用变量
DECLARE sql_text STRING;
SET sql_text = 'SELECT COUNT(*) AS cnt FROM `myproject.mydataset.users`';
EXECUTE IMMEDIATE sql_text;

-- ============================================================
-- EXECUTE IMMEDIATE ... USING (参数化)
-- ============================================================
EXECUTE IMMEDIATE
    'SELECT * FROM `myproject.mydataset.users` WHERE age > @min_age AND status = @status'
    USING 18 AS min_age, 'active' AS status;

-- ============================================================
-- EXECUTE IMMEDIATE ... INTO (结果存入变量)
-- ============================================================
DECLARE row_count INT64;
EXECUTE IMMEDIATE
    'SELECT COUNT(*) FROM `myproject.mydataset.users` WHERE age > @a'
    INTO row_count
    USING 18 AS a;
SELECT row_count;

-- ============================================================
-- 动态 DDL
-- ============================================================
DECLARE year_val INT64 DEFAULT 2024;
EXECUTE IMMEDIATE FORMAT(
    'CREATE TABLE IF NOT EXISTS `myproject.mydataset.orders_%d` AS SELECT * FROM `myproject.mydataset.orders` WHERE EXTRACT(YEAR FROM order_date) = %d',
    year_val, year_val
);

-- ============================================================
-- 存储过程中的动态 SQL
-- ============================================================
CREATE OR REPLACE PROCEDURE mydataset.dynamic_count(table_name STRING, OUT cnt INT64)
BEGIN
    EXECUTE IMMEDIATE CONCAT('SELECT COUNT(*) FROM `', table_name, '`') INTO cnt;
END;

DECLARE result INT64;
CALL mydataset.dynamic_count('myproject.mydataset.users', result);
SELECT result;

-- ============================================================
-- 循环中使用动态 SQL
-- ============================================================
FOR record IN (SELECT table_name FROM mydataset.INFORMATION_SCHEMA.TABLES)
DO
    EXECUTE IMMEDIATE FORMAT('SELECT COUNT(*) FROM `mydataset.%s`', record.table_name);
END FOR;

-- ============================================================
-- 参数化（防止 SQL 注入）
-- ============================================================
-- 使用 USING 子句的命名参数
DECLARE search_name STRING DEFAULT 'admin';
EXECUTE IMMEDIATE
    'SELECT * FROM `myproject.mydataset.users` WHERE username = @name'
    USING search_name AS name;

-- 版本说明：
--   BigQuery Scripting (2019+) : EXECUTE IMMEDIATE 支持
-- 注意：BigQuery 使用 @name 作为参数占位符
-- 注意：FORMAT() 用于动态标识符，USING 用于动态值
-- 注意：BigQuery 没有传统的 PREPARE / DEALLOCATE
-- 限制：每个脚本最多 1000 个语句
-- 限制：EXECUTE IMMEDIATE 不支持返回多行结果到变量（需要临时表）
