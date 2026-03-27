-- H2 Database: 错误处理 (Error Handling)
--
-- 参考资料:
--   [1] H2 Database Documentation - SQL Grammar
--       https://h2database.com/html/grammar.html
--   [2] H2 Database Documentation - Error Codes
--       https://h2database.com/javadoc/org/h2/api/ErrorCode.html
--   [3] H2 Database Documentation - Stored Procedures
--       https://h2database.com/html/features.html#stored_procedures

-- ============================================================
-- 1. H2 错误处理概述
-- ============================================================
-- H2 是嵌入式/内存 Java 数据库，没有服务端存储过程语言（如 PL/pgSQL）。
-- 错误处理完全依赖 Java 应用层或 SQL 防御性写法。
-- H2 兼容多种模式: PostgreSQL, MySQL, Oracle, SQL Server 等。

-- ============================================================
-- 2. 应用层错误捕获: JDBC
-- ============================================================

-- Java 示例: 基本 try/catch 错误处理
-- try (Connection conn = DriverManager.getConnection(url, user, pass)) {
--     Statement stmt = conn.createStatement();
--     stmt.execute("INSERT INTO users VALUES(1, 'test')");
-- } catch (SQLException e) {
--     String sqlState = e.getSQLState();       // e.g. "23000" (约束违反)
--     int errorCode = e.getErrorCode();         // H2 特定错误码 e.g. 23505
--     String message = e.getMessage();          // 人类可读的错误描述
--     System.err.println("Error [" + sqlState + "] " + message);
-- }

-- Java 示例: 按错误类型分别处理
-- try {
--     stmt.executeUpdate("INSERT INTO users(id, name) VALUES(1, 'alice')");
-- } catch (java.sql.SQLIntegrityConstraintViolationException e) {
--     // 约束违反: 唯一键、外键、NOT NULL 等
--     System.out.println("Constraint violation: " + e.getMessage());
-- } catch (java.sql.SQLSyntaxErrorException e) {
--     // SQL 语法错误
--     System.out.println("Syntax error: " + e.getMessage());
-- } catch (java.sql.SQLDataException e) {
--     // 数据异常: 溢出、类型不匹配等
--     System.out.println("Data exception: " + e.getMessage());
-- } catch (SQLException e) {
--     // 其他所有 SQL 错误
--     System.out.println("General error: " + e.getMessage());
-- }

-- ============================================================
-- 3. H2 常见错误码
-- ============================================================

-- H2 遵循 SQL 标准 SQLSTATE 编码:
--   23000 / 23505 = 唯一约束违反 (Unique Constraint Violation)
--   23000 / 23502 = NULL 约束违反 (Not Null Violation)
--   23000 / 23503 = 外键约束违反 (Foreign Key Violation)
--   23000 / 23513 = CHECK 约束违反 (Check Constraint Violation)
--   42000          = 语法错误或访问违规 (Syntax Error)
--   22003          = 数值超范围 (Numeric Value Out of Range)
--   22018          = 字符转换错误 (Invalid Character Value)
--   08003          = 连接不存在 (Connection Does Not Exist)
--   42502          = 权限不足 (Insufficient Privilege)
--   42S02          = 表或视图不存在 (Table Not Found)
--   42S11          = 索引已存在 (Index Already Exists)
--   42S22          = 列未找到 (Column Not Found)

-- Java 代码查看所有 H2 错误码:
-- for (org.h2.api.ErrorCode ec : org.h2.api.ErrorCode.class.getEnumConstants()) {
--     System.out.println(ec.name() + " = " + ec.getIntValue());
-- }

-- ============================================================
-- 4. SQL 层面的错误避免: 防御性写法
-- ============================================================

-- 使用 IF NOT EXISTS 避免对象已存在错误
CREATE TABLE IF NOT EXISTS users (
    id    INT PRIMARY KEY,
    name  VARCHAR(100),
    email VARCHAR(255)
);

-- 使用 IF EXISTS 避免对象不存在错误
DROP TABLE IF EXISTS temp_data;

-- 安全插入: 仅在键不存在时插入
INSERT INTO users(id, name, email)
SELECT 1, 'alice', 'alice@example.com'
WHERE NOT EXISTS (SELECT 1 FROM users WHERE id = 1);

-- MERGE 语句: 存在则更新，不存在则插入
MERGE INTO users u
USING (VALUES(1, 'alice', 'alice@new.com')) AS v(id, name, email)
ON u.id = v.id
WHEN MATCHED THEN UPDATE SET u.email = v.email
WHEN NOT MATCHED THEN INSERT (id, name, email) VALUES(v.id, v.name, v.email);

-- 安全删除: 先检查存在性
DELETE FROM users WHERE id = 999 AND EXISTS (SELECT 1 FROM users WHERE id = 999);

-- ============================================================
-- 5. 存储过程 (Java): 带错误处理的 UDF
-- ============================================================

-- H2 通过 CREATE ALIAS 注册 Java 方法为存储过程
-- CREATE ALIAS SAFE_DIVIDE AS $$
-- import java.sql.*;
-- public static Double safeDivide(Connection conn, double a, double b)
--     throws SQLException {
--     if (b == 0.0) {
--         return null;  // 除零返回 NULL 而非抛出异常
--     }
--     return a / b;
-- }
-- $$;

-- 带事务管理的存储过程
-- CREATE ALIAS SAFE_TRANSFER AS $$
-- import java.sql.*;
-- public static void safeTransfer(Connection conn,
--         int fromId, int toId, double amount) throws SQLException {
--     try {
--         conn.setAutoCommit(false);
--         // 扣减余额
--         try (PreparedStatement ps = conn.prepareStatement(
--                 "UPDATE accounts SET balance = balance - ? WHERE id = ? AND balance >= ?")) {
--             ps.setDouble(1, amount);
--             ps.setInt(2, fromId);
--             ps.setDouble(3, amount);
--             int rows = ps.executeUpdate();
--             if (rows == 0) throw new SQLException("Insufficient balance", "45001");
--         }
--         // 增加余额
--         try (PreparedStatement ps = conn.prepareStatement(
--                 "UPDATE accounts SET balance = balance + ? WHERE id = ?")) {
--             ps.setDouble(1, amount);
--             ps.setInt(2, toId);
--             int rows = ps.executeUpdate();
--             if (rows == 0) throw new SQLException("Target not found", "45002");
--         }
--         conn.commit();
--     } catch (SQLException e) {
--         conn.rollback();
--         throw e;  -- 重抛给调用者
--     }
-- }
-- $$;

-- ============================================================
-- 6. 诊断: 系统视图
-- ============================================================

-- 查看 H2 数据库信息
SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'PUBLIC';

-- 查看约束信息（用于排查约束违反错误）
SELECT CONSTRAINT_NAME, CONSTRAINT_TYPE, TABLE_NAME
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
WHERE TABLE_SCHEMA = 'PUBLIC';

-- 查看列的 NOT NULL 约束
SELECT TABLE_NAME, COLUMN_NAME, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'PUBLIC';

-- H2 控制台调试:
--   TRACE_LEVEL_SYSTEM_OUT = 2;  -- 开启 SQL 日志输出到控制台
--   SET TRACE_MAX_FILE_SIZE 16;  -- 限制 trace 文件大小 (MB)

-- ============================================================
-- 7. 兼容性模式的错误处理差异
-- ============================================================
-- H2 支持多种兼容模式，不同模式下错误行为可能不同:
--   PostgreSQL 模式: 错误码和消息格式接近 PostgreSQL
--   MySQL 模式: 支持 MySQL 风格的错误码
--   Oracle 模式: 模拟 Oracle 的部分行为
--   SQL Server 模式: 模拟 SQL Server 的部分行为
-- 设置模式: SET MODE PostgreSQL;

-- ============================================================
-- 8. 版本说明
-- ============================================================
-- H2 1.x:       基本错误处理，JDBC 标准异常
-- H2 2.0+:      改进的错误消息，新增 INFORMATION_SCHEMA 视图
-- 注意: H2 没有 TRY/CATCH, EXCEPTION WHEN, DECLARE HANDLER 语法
-- 注意: 所有服务端错误处理通过 Java 存储过程 (CREATE ALIAS) 实现
-- 限制: 不支持 SIGNAL / RESIGNAL
-- 限制: 嵌入式模式下，错误直接抛出到 JVM 调用线程
