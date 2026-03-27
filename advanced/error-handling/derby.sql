-- Apache Derby: Error Handling
--
-- 参考资料:
--   [1] Apache Derby Reference Manual
--       https://db.apache.org/derby/docs/10.16/ref/

-- ============================================================
-- Derby 没有服务端错误处理
-- ============================================================
-- Derby 不支持存储过程中的异常处理语法
-- 错误处理通过 Java JDBC 实现

-- ============================================================
-- JDBC 替代方案 (Java)
-- ============================================================
-- try {
--     stmt.execute("INSERT INTO users VALUES(1, 'test')");
-- } catch (SQLException e) {
--     System.out.println("SQLState: " + e.getSQLState());
--     System.out.println("Error Code: " + e.getErrorCode());
--     System.out.println("Message: " + e.getMessage());
-- }

-- ============================================================
-- Derby 错误码
-- ============================================================
-- SQLState 23505 = 重复键
-- SQLState 42X05 = 表不存在
-- SQLState 42X14 = 列不存在
-- SQLState 22003 = 数值越界

-- ============================================================
-- SQL 层面的错误避免
-- ============================================================
CREATE TABLE IF NOT EXISTS users(id INT PRIMARY KEY, name VARCHAR(100));

-- 注意：Derby 的错误处理完全在 Java 应用层实现
-- 注意：Derby 的存储过程用 Java 编写，使用 try/catch
-- 限制：无服务端异常处理语法
