-- Apache Spark SQL: Error Handling
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html

-- ============================================================
-- Spark SQL 不支持服务端错误处理
-- ============================================================

-- 应用层替代方案 (PySpark):
-- try:
--     spark.sql("SELECT * FROM nonexistent_table")
-- except AnalysisException as e:
--     print(f"SQL error: {e}")
-- except SparkException as e:
--     print(f"Spark error: {e}")

-- SQL 层面的错误避免
CREATE TABLE IF NOT EXISTS users (id INT, name STRING) USING DELTA;

-- 安全函数
SELECT TRY_CAST('abc' AS INT);       -- 返回 NULL
SELECT try_divide(10, 0);             -- 返回 NULL       -- 3.2+
SELECT try_add(2147483647, 1);        -- 返回 NULL       -- 3.2+

-- 注意：Spark SQL 错误处理在应用层实现
-- 注意：使用 TRY_CAST / try_* 函数避免运行时错误
-- 限制：无 TRY/CATCH, EXCEPTION WHEN, DECLARE HANDLER
