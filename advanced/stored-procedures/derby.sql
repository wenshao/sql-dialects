-- Derby: 存储过程

-- Derby 通过 Java 方法实现存储过程和函数

-- ============================================================
-- 创建存储过程（Java 方法）
-- ============================================================

-- 步骤 1：编写 Java 类
-- public class MyProcedures {
--     public static void getUser(String username, ResultSet[] rs)
--             throws SQLException {
--         Connection conn = DriverManager.getConnection("jdbc:default:connection");
--         PreparedStatement ps = conn.prepareStatement(
--             "SELECT * FROM users WHERE username = ?");
--         ps.setString(1, username);
--         rs[0] = ps.executeQuery();
--     }
-- }

-- 步骤 2：注册存储过程
CREATE PROCEDURE GET_USER(IN p_username VARCHAR(64))
LANGUAGE JAVA PARAMETER STYLE JAVA
READS SQL DATA
DYNAMIC RESULT SETS 1
EXTERNAL NAME 'MyProcedures.getUser';

-- 步骤 3：调用
CALL GET_USER('alice');

-- ============================================================
-- 创建函数
-- ============================================================

-- public class MyFunctions {
--     public static String fullName(String first, String last) {
--         return first + " " + last;
--     }
-- }

CREATE FUNCTION FULL_NAME(first_name VARCHAR(50), last_name VARCHAR(50))
RETURNS VARCHAR(101)
LANGUAGE JAVA PARAMETER STYLE JAVA
NO SQL
EXTERNAL NAME 'MyFunctions.fullName';

SELECT FULL_NAME('Alice', 'Smith') FROM SYSIBM.SYSDUMMY1;

-- ============================================================
-- 系统存储过程（SYSCS_UTIL）
-- ============================================================

-- 导入数据
CALL SYSCS_UTIL.SYSCS_IMPORT_TABLE('APP', 'USERS', '/path/to/data.csv', ',', '"', 'UTF-8', 0);

-- 导出数据
CALL SYSCS_UTIL.SYSCS_EXPORT_TABLE('APP', 'USERS', '/path/to/export.csv', ',', '"', 'UTF-8');

-- 更新统计信息
CALL SYSCS_UTIL.SYSCS_UPDATE_STATISTICS('APP', 'USERS', NULL);

-- 压缩表
CALL SYSCS_UTIL.SYSCS_COMPRESS_TABLE('APP', 'USERS', 0);

-- 设置数据库属性
CALL SYSCS_UTIL.SYSCS_SET_DATABASE_PROPERTY('derby.storage.pageSize', '32768');

-- 备份
CALL SYSCS_UTIL.SYSCS_BACKUP_DATABASE('/path/to/backup');

-- ============================================================
-- 删除
-- ============================================================

DROP PROCEDURE GET_USER;
DROP FUNCTION FULL_NAME;

-- 注意：Derby 存储过程必须用 Java 编写
-- 注意：需要先编译 Java 类并放入 classpath
-- 注意：SYSCS_UTIL 提供系统管理过程
-- 注意：PARAMETER STYLE JAVA 是唯一支持的参数风格
-- 注意：不支持 PL/SQL 或 T-SQL 过程式语言
