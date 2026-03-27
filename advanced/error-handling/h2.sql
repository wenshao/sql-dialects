-- H2 Database: Error Handling
--
-- 参考资料:
--   [1] H2 Database Documentation
--       https://h2database.com/html/grammar.html

-- ============================================================
-- H2 没有服务端异常处理语法
-- ============================================================
-- H2 的存储过程使用 Java，通过 try/catch 处理错误

-- JDBC 替代方案 (Java):
-- try {
--     stmt.execute("INSERT INTO users VALUES(1, 'test')");
-- } catch (SQLException e) {
--     System.out.println("Error: " + e.getSQLState() + " - " + e.getMessage());
-- }

-- ============================================================
-- SQL 层面的错误避免
-- ============================================================
CREATE TABLE IF NOT EXISTS users (id INT PRIMARY KEY, name VARCHAR(100));

-- 注意：H2 的错误处理在 Java 应用层实现
-- 限制：无 TRY/CATCH, EXCEPTION WHEN, DECLARE HANDLER
