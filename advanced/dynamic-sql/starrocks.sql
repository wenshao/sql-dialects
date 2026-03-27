-- StarRocks: 动态 SQL (Dynamic SQL)
--
-- 参考资料:
--   [1] StarRocks Documentation - SQL Reference
--       https://docs.starrocks.io/docs/sql-reference/
--   [2] StarRocks Documentation - PREPARE Statement
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/prepared-statement/PREPARE/
--   [3] StarRocks Documentation - EXECUTE Statement
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/prepared-statement/EXECUTE/
--   [4] StarRocks Documentation - DEALLOCATE Statement
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/prepared-statement/DEALLOCATE-PREPARE/

-- ============================================================
-- 1. PREPARE / EXECUTE / DEALLOCATE PREPARE (MySQL 协议兼容)
-- ============================================================

-- 基本用法: 单参数
PREPARE stmt FROM 'SELECT * FROM users WHERE id = ?';
SET @id = 42;
EXECUTE stmt USING @id;
DEALLOCATE PREPARE stmt;

-- 多参数查询
PREPARE stmt FROM 'SELECT * FROM users WHERE age > ? AND status = ?';
SET @min_age = 18;
SET @status = 'active';
EXECUTE stmt USING @min_age, @status;
DEALLOCATE PREPARE stmt;

-- StarRocks 的 PREPARE 继承自 MySQL 协议语义:
--   PREPARE 将语句文本发送至服务端，解析并缓存。
--   EXECUTE USING 按位置传递参数（? 占位符）。
--   DEALLOCATE 释放服务端缓存的预处理语句。
--
-- 差异:
--   MySQL:      PREPARE 支持 SQL 层 + COM_STMT_PREPARE 协议命令
--   StarRocks:  通过 MySQL 协议兼容层支持，行为基本一致
--   PostgreSQL: 使用 $1, $2 位置参数（非 ? 占位符）

-- ============================================================
-- 2. 动态查询构建: 字符串拼接
-- ============================================================

-- StarRocks 支持 CONCAT 函数构建动态 SQL 字符串
-- 注意: StarRocks 不支持存储过程，无法在服务端实现完整的动态 SQL 逻辑
-- 以下展示通过 MySQL 客户端变量实现的有限动态查询

SET @table_name = 'users';
SET @sql_text = CONCAT('SELECT COUNT(*) FROM ', @table_name);
PREPARE stmt FROM @sql_text;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 动态列名与条件组合
SET @col = 'age';
SET @sql_text = CONCAT('SELECT ', @col, ' FROM users ORDER BY ', @col, ' DESC LIMIT 10');
PREPARE stmt FROM @sql_text;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 重要限制:
--   PREPARE 的语句源可以是字符串字面量或用户变量（@var），不能是表达式。
--   StarRocks 不支持存储过程，无法封装动态 SQL 逻辑。

-- ============================================================
-- 3. SQL 注入防护
-- ============================================================

-- 正确: 使用参数占位符传递值参数
PREPARE safe_stmt FROM 'SELECT * FROM users WHERE username = ?';
SET @uname = 'admin';
EXECUTE safe_stmt USING @uname;
DEALLOCATE PREPARE safe_stmt;

-- 错误（危险）: 直接拼接用户输入到 SQL 字符串
-- SET @unsafe_sql = CONCAT('SELECT * FROM users WHERE username = ''', user_input, '''');
-- PREPARE unsafe_stmt FROM @unsafe_sql;

-- 动态标识符（表名/列名）的安全处理:
--   1. 使用白名单验证（推荐）
--   2. 使用 REPLACE 过滤危险字符（次选）
--   3. 在应用层使用参数化查询（最佳）

-- 白名单示例（应用层）:
-- valid_tables = {'users', 'orders', 'products'}
-- if table_name not in valid_tables:
--     raise ValueError(f'Invalid table: {table_name}')

-- 设计原则:
--   值参数 → 始终使用 ? 占位符 + EXECUTE USING
--   标识符 → 白名单验证，不直接拼接

-- ============================================================
-- 4. 应用层替代方案: Python (pymysql)
-- ============================================================

-- StarRocks 兼容 MySQL 协议，可使用 MySQL 驱动
-- import pymysql
-- conn = pymysql.connect(host='localhost', port=9030, user='root', db='mydb')
-- cursor = conn.cursor()
--
-- -- 参数化查询（服务端预处理）
-- cursor.execute('SELECT * FROM users WHERE age > %s', (18,))
--
-- -- 动态表名（应用层安全拼接）
-- table = 'users'
-- cursor.execute(f'SELECT COUNT(*) FROM {pymysql.escape_string(table)}')

-- pymysql 的参数化机制:
--   cursor.execute(sql, params) → 内部使用 COM_STMT_PREPARE / COM_STMT_EXECUTE
--   %s 占位符由驱动替换为 ? 发送到服务端

-- ============================================================
-- 5. 应用层替代方案: Java (JDBC)
-- ============================================================

-- import java.sql.*;
-- String url = "jdbc:mysql://localhost:9030/mydb";
-- try (Connection conn = DriverManager.getConnection(url, "root", "")) {
--     // 参数化查询
--     PreparedStatement ps = conn.prepareStatement(
--         "SELECT * FROM users WHERE age > ? AND status = ?"
--     );
--     ps.setInt(1, 18);
--     ps.setString(2, "active");
--     ResultSet rs = ps.executeQuery();
-- }

-- ============================================================
-- 6. 动态 DDL: 分区管理场景
-- ============================================================

-- StarRocks 常见场景: 动态创建分区（OLAP 分析）
-- 通过应用层循环执行 DDL
-- for month in range(1, 13):
--     sql = f"""ALTER TABLE orders
--               ADD PARTITION IF NOT EXISTS p2026{month:02d}
--               VALUES LESS THAN ('2026-{month:02d}-01')"""
--     cursor.execute(sql)

-- StarRocks 自动分区特性 (3.1+):
--   CREATE TABLE orders (
--       order_date DATE, ...
--   ) PARTITION BY RANGE(order_date) (
--       START ('2026-01-01') END ('2027-01-01') EVERY (INTERVAL 1 MONTH)
--   );
--   自动分区减少了对动态 DDL 的需求。

-- ============================================================
-- 7. 横向对比
-- ============================================================

-- 1. 协议兼容性:
--   StarRocks:    MySQL wire protocol
--   MySQL:        原生 MySQL protocol
--   TiDB:         MySQL wire protocol
--   Doris:        MySQL wire protocol
--   Materialize:  PostgreSQL wire protocol
--
-- 2. 服务端动态 SQL:
--   StarRocks:    PREPARE/EXECUTE（MySQL 兼容）
--   MySQL:        PREPARE/EXECUTE + 存储过程
--   PostgreSQL:   PREPARE/EXECUTE + PL/pgSQL EXECUTE
--   Doris:        PREPARE/EXECUTE（MySQL 兼容）
--
-- 3. OLAP 特有模式:
--   StarRocks:  自动分区 + 物化视图（减少动态 DDL 需求）
--   Doris:      动态分区策略（自动管理分区生命周期）
--   ClickHouse: PARTITION BY + TTL（声明式而非动态）

-- ============================================================
-- 8. 对引擎开发者的启示
-- ============================================================

-- (1) MySQL 协议兼容是 OLAP 引擎的常见选择:
--     StarRocks、Doris、TiDB、ClickHouse 均支持 MySQL 协议。
--     复用 MySQL 驱动生态（JDBC、ODBC、pymysql、Go-MySQL-Driver）。
--
-- (2) OLAP 引擎中"动态 SQL"的需求特征:
--     少量 ad-hoc 查询（通过 PREPARE/EXECUTE 满足）。
--     大量 ETL 管道（通过应用层 JDBC/驱动满足）。
--     分区管理通过声明式语法（自动分区）优于动态 DDL。
--
-- (3) 存储过程缺失的权衡:
--     OLAP 引擎通常不支持存储过程（简化引擎复杂度）。
--     动态 SQL 逻辑全部移至应用层（Python/Java/Go）。
--     这是"数据库做存储+计算，应用层做逻辑"的现代架构趋势。

-- ============================================================
-- 9. 版本与限制
-- ============================================================
-- StarRocks 2.x:  PREPARE / EXECUTE / DEALLOCATE PREPARE（MySQL 兼容）
-- StarRocks 3.1+: 自动分区（PARTITION BY ... EVERY）
-- 注意:            PREPARE 只能使用用户变量 (@var)，不能使用局部变量
-- 注意:            每个会话的预处理语句数量受 max_prepared_stmt_count 控制
-- 限制:            无存储过程
-- 限制:            无 EXECUTE IMMEDIATE
-- 限制:            PREPARE 不支持所有 SQL 语句类型（如部分 DDL）
-- 限制:            面向 OLAP 分析场景，动态 SQL 场景有限
