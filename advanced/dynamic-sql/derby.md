# Apache Derby: 动态 SQL (Dynamic SQL)

> 参考资料:
> - [Apache Derby Reference Manual](https://db.apache.org/derby/docs/10.16/ref/)
> - [Apache Derby Developer's Guide - Dynamic SQL](https://db.apache.org/derby/docs/10.16/devguide/)
> - [Apache Derby Tools Guide - ij Tool](https://db.apache.org/derby/docs/10.16/tools/)
> - [JDBC PreparedStatement API](https://docs.oracle.com/javase/8/docs/api/java/sql/PreparedStatement.html)
> - ============================================================
> - 1. Derby 的动态 SQL 模型
> - ============================================================
> - Derby 是纯 Java 嵌入式数据库，不支持服务端动态 SQL:
> - 无 EXECUTE IMMEDIATE 或服务端 SQL 字符串执行
> - 无存储过程语言（PL/SQL、T-SQL 等）
> - 存储过程使用 Java 类实现
> - Derby 的动态 SQL 完全通过 JDBC API 实现:
> - PreparedStatement: 参数化查询（防注入，预编译）
> - Statement: 动态 SQL 字符串执行（不安全，不推荐）
> - CallableStatement: 调用 Java 存储过程
> - ============================================================
> - 2. JDBC PreparedStatement: 参数化动态查询
> - ============================================================
> - PreparedStatement 是 Derby 动态 SQL 的核心机制
> - 基本参数化查询:
> - import java.sql.*;
> - String url = "jdbc:derby:mydb;create=true";
> - try (Connection conn = DriverManager.getConnection(url)) {
> - String sql = "SELECT * FROM users WHERE age > ? AND status = ?";
> - try (PreparedStatement ps = conn.prepareStatement(sql)) {
> - ps.setInt(1, 18);
> - ps.setString(2, "active");
> - try (ResultSet rs = ps.executeQuery()) {
> - while (rs.next()) {
> - System.out.println(rs.getString("name"));
> - }
> - }
> - }
> - }
> - PreparedStatement 内部机制:
> - SQL 在 prepareStatement() 时发送到 Derby 引擎。
> - Derby 解析 SQL、生成查询计划、缓存（同一会话内）。
> - setXxx() 设置参数值，executeQuery()/executeUpdate() 执行。
> - 参数占位符 ? 只能用于值位置，不能用于标识符（表名/列名）。
> - ============================================================
> - 3. 动态 SQL 字符串构建
> - ============================================================
> - 动态表名或列名无法使用 PreparedStatement，需要拼接 SQL 字符串
> - 动态表名:
> - String table = "users";
> - String sql = "SELECT COUNT(*) FROM " + table;
> - try (Statement stmt = conn.createStatement();
> - ResultSet rs = stmt.executeQuery(sql)) {
> - if (rs.next()) System.out.println("Count: " + rs.getInt(1));
> - }
> - 动态 WHERE 子句:
> - List<String> conditions = new ArrayList<>();
> - if (name != null) conditions.add("name = '" + escapeSql(name) + "'");
> - if (age != null)  conditions.add("age > " + age);
> - String where = conditions.isEmpty() ? "" : " WHERE " + String.join(" AND ", where);
> - String sql = "SELECT * FROM users" + where;
> - SQL 转义工具方法:
> - public static String escapeSql(String input) {
> - if (input == null) return "NULL";
> - return input.replace("'", "''").replace("\\", "\\\\");
> - }
> - ============================================================
> - 4. SQL 注入防护
> - ============================================================
> - 策略 1: PreparedStatement 参数化（最佳，用于值参数）
> - PreparedStatement ps = conn.prepareStatement(
> - "SELECT * FROM users WHERE username = ? AND password = ?"
> - );
> - ps.setString(1, username);   // 自动转义
> - ps.setString(2, password);   // 自动转义
> - // Derby 驱动确保参数值不会改变 SQL 语义
> - 策略 2: 白名单验证（用于标识符: 表名、列名）
> - import java.util.Set;
> - Set<String> validTables = Set.of("users", "orders", "products");
> - public static void validateTable(String table) {
> - if (!validTables.contains(table.toLowerCase())) {
> - throw new IllegalArgumentException("Invalid table: " + table);
> - }
> - }
> - 策略 3: 标识符引号（Derby 使用双引号引用标识符）
> - public static String quoteIdentifier(String id) {
> - return '"' + id.replace("\"", "\"\"") + '"';
> - }
> - String safeSql = "SELECT * FROM " + quoteIdentifier(tableName);
> - 错误（危险）: 直接拼接用户输入
> - String sql = "SELECT * FROM users WHERE name = '" + userInput + "'";

```sql
// 容易受到 SQL 注入攻击: userInput = "'; DROP TABLE users; --"
```

## Java 存储过程: 服务端动态 SQL 的替代


Derby 存储过程使用 Java 实现，可在 Java 代码中使用动态 SQL
定义存储过程:
CREATE PROCEDURE dynamic_query(IN sql_text VARCHAR(4000))
LANGUAGE JAVA
PARAMETER STYLE JAVA
EXTERNAL NAME 'com.example.Procedures.dynamicQuery';
Java 实现:
package com.example;
import java.sql.*;
public class Procedures {
public static void dynamicQuery(String sqlText) throws SQLException {
Connection conn = DriverManager.getConnection("jdbc:default:connection");
try (Statement stmt = conn.createStatement()) {
stmt.execute(sqlText);  // 在 Derby 引擎内部执行动态 SQL
}
}
}
带结果集的存储过程:
CREATE PROCEDURE search_users(IN p_status VARCHAR(20))
LANGUAGE JAVA
PARAMETER STYLE JAVA
READS SQL DATA
DYNAMIC RESULT SETS 1
EXTERNAL NAME 'com.example.Procedures.searchUsers';
public static void searchUsers(String status, ResultSet[] results)
throws SQLException {
Connection conn = DriverManager.getConnection("jdbc:default:connection");
PreparedStatement ps = conn.prepareStatement(
"SELECT * FROM users WHERE status = ?"
);
ps.setString(1, status);
results[0] = ps.executeQuery();
}
设计要点:
jdbc:default:connection 是 Derby 特殊 URL，获取当前连接上下文。
DYNAMIC RESULT SETS 1 声明存储过程返回 1 个结果集。
READS SQL DATA / MODIFIES SQL DATA 声明访问权限级别。

## ij 工具: 交互式 SQL 脚本


Derby 自带 ij 命令行工具，支持基本的脚本化操作
java -Dderby.system.home=/path/to/db org.apache.derby.tools.ij
CONNECT 'jdbc:derby:mydb;create=true';
使用 Prepared Statement (ij 语法)
PREPARE findUser AS 'SELECT * FROM users WHERE id = ?';
EXECUTE findUser USING 'VALUE 42';
动态 SQL (ij 中使用字符串变量)
CREATE TABLE IF NOT EXISTS users (id INT PRIMARY KEY, name VARCHAR(100), age INT);
ij 工具的 PREPARE/EXECUTE:
ij 支持 PREPARE ... AS 和 EXECUTE ... USING 语法。
这是 ij 工具层的功能，不是 Derby SQL 语法的一部分。
适合交互式测试和简单脚本。

## 横向对比: 嵌入式 Java 数据库


## 服务端动态 SQL:

Derby:       无（JDBC PreparedStatement + Java 存储过程）
H2:          EXECUTE IMMEDIATE（有限支持）+ JDBC
HSQLDB:      EXECUTE IMMEDIATE + JDBC
SQLite:      无（C API sqlite3_prepare_v2）
2. 存储过程:
Derby:       Java 语言实现（外部类）
H2:          Java 语言实现或 JavaScript (v2.+)
HSQLDB:      SQL/PSM 标准语法
PostgreSQL:  PL/pgSQL
3. 预处理语句缓存:
Derby:       同一会话内自动缓存（默认启用）
H2:          可配置缓存大小
HSQLDB:      自动缓存
MySQL:       max_prepared_stmt_count 限制

## 对引擎开发者的启示


(1) 嵌入式数据库的动态 SQL 由驱动层承担:
Derby 作为嵌入式引擎，JDBC 驱动和引擎在同一个 JVM 进程中。
PreparedStatement 的"预处理"开销极低（无网络传输）。
这是嵌入式数据库不需要服务端 EXECUTE IMMEDIATE 的原因。
(2) Java 存储过程是独特的设计选择:
Derby 让存储过程用 Java 编写，而非专有过程语言。
优点: 复用 Java 生态（类型安全、IDE 支持、调试）。
缺点: 需要编译/部署 Java 类，开发流程较重。
在 Java 存储过程中可以使用完整的 JDBC API 实现动态 SQL。
(3) PreparedStatement 参数化的安全性设计值得学习:
参数值在 SQL 解析之后绑定，从根本上防止 SQL 注入。
这是所有数据库注入防护的基石（无论服务端还是驱动层实现）。

## 版本与限制

Derby 10.x:    JDBC PreparedStatement 完整支持
Derby 10.x:    Java 存储过程（CREATE PROCEDURE ... EXTERNAL NAME）
Derby 10.12+:  标准语法增强（IF EXISTS 等）
Derby 10.15+:  Java 9+ 模块化支持
注意:          ij 工具的 PREPARE/EXECUTE 是工具层语法，非 SQL 标准语法
注意:          Derby 的 PreparedStatement 缓存在同一会话内有效
限制:          无 EXECUTE IMMEDIATE（服务端动态 SQL）
限制:          无 PL/SQL 或 T-SQL 风格的过程语言
限制:          存储过程需要外部 Java 类，不支持内联过程代码
限制:          嵌入式模式无网络协议，所有动态 SQL 在应用进程内执行
