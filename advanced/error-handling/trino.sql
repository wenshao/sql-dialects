-- Trino: Error Handling
--
-- 参考资料:
--   [1] Trino Documentation
--       https://trino.io/docs/current/

-- ============================================================
-- Trino 不支持服务端错误处理
-- ============================================================
-- Trino 不支持存储过程或异常处理语法

-- 应用层替代方案 (Python):
-- import trino
-- try:
--     cursor.execute('SELECT * FROM nonexistent_table')
-- except trino.exceptions.TrinoQueryError as e:
--     print(f'Error code: {e.error_code}, Message: {e.message}')

-- JDBC 替代方案:
-- try {
--     stmt.execute("SELECT ...");
-- } catch (SQLException e) {
--     System.out.println("Trino error: " + e.getMessage());
-- }

-- SQL 层面的错误避免
-- 使用 TRY_CAST 避免类型转换错误
SELECT TRY_CAST('abc' AS INTEGER);    -- 返回 NULL
SELECT TRY(1/0);                      -- 返回 NULL

-- 注意：Trino 面向交互式查询，不支持存储过程
-- 注意：TRY() 函数可将错误转为 NULL
-- 限制：无 TRY/CATCH, EXCEPTION WHEN, DECLARE HANDLER
