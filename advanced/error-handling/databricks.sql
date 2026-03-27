-- Databricks: Error Handling
--
-- 参考资料:
--   [1] Databricks SQL Reference - Error Handling
--       https://docs.databricks.com/en/sql/language-manual/sql-ref-error-handling.html

-- ============================================================
-- Databricks SQL 错误处理 (有限支持)
-- ============================================================
-- Databricks SQL 支持基本的脚本级错误处理

-- ============================================================
-- PySpark / Python 替代方案
-- ============================================================
-- try:
--     spark.sql("INSERT INTO users VALUES (1, 'test')")
-- except AnalysisException as e:
--     print(f"SQL Error: {e}")
-- except Exception as e:
--     print(f"Unexpected error: {e}")

-- ============================================================
-- SQL 层面的错误避免
-- ============================================================
-- 使用 IF EXISTS / IF NOT EXISTS
CREATE TABLE IF NOT EXISTS users (id INT, name STRING);

-- 使用 TRY_CAST 避免类型转换错误
SELECT TRY_CAST('abc' AS INT);  -- 返回 NULL 而非错误

-- 使用 try_* 函数
SELECT try_divide(10, 0);       -- 返回 NULL 而非错误
SELECT try_add(2147483647, 1);  -- 返回 NULL 而非溢出错误

-- 注意：Databricks SQL 错误处理功能有限
-- 注意：推荐在 Python/Scala 应用层实现错误处理
-- 注意：使用 TRY_CAST / try_* 函数避免运行时错误
-- 限制：无 TRY/CATCH, EXCEPTION WHEN, DECLARE HANDLER
