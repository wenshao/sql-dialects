-- Apache Hive: Error Handling
--
-- 参考资料:
--   [1] Apache Hive Language Manual
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual

-- ============================================================
-- Hive 不支持服务端错误处理
-- ============================================================
-- Hive 不支持存储过程或异常处理

-- ============================================================
-- 应用层替代方案 (Python/PyHive)
-- ============================================================
-- from pyhive import hive
--
-- conn = hive.Connection(host='localhost', port=10000, database='default')
-- cursor = conn.cursor()
--
-- try:
--     cursor.execute('SELECT * FROM nonexistent_table')
-- except Exception as e:
--     print(f'Hive error: {e}')
-- finally:
--     cursor.close()
--     conn.close()

-- ============================================================
-- 应用层替代方案 (Java/JDBC)
-- ============================================================
-- try {
--     Statement stmt = conn.createStatement();
--     stmt.execute("SELECT * FROM nonexistent_table");
-- } catch (SQLException e) {
--     System.err.println("SQLState: " + e.getSQLState());
--     System.err.println("Error code: " + e.getErrorCode());
--     System.err.println("Message: " + e.getMessage());
-- }

-- ============================================================
-- SQL 层面的错误避免
-- ============================================================
-- IF NOT EXISTS / IF EXISTS 防止常见 DDL 错误
CREATE TABLE IF NOT EXISTS users (id INT, name STRING);
DROP TABLE IF EXISTS temp_table;
CREATE DATABASE IF NOT EXISTS analytics;
DROP DATABASE IF EXISTS temp_db;

-- 安全的分区操作
ALTER TABLE users ADD IF NOT EXISTS PARTITION (dt='2025-01-01');
ALTER TABLE users DROP IF EXISTS PARTITION (dt='2025-01-01');

-- ============================================================
-- Hive 配置控制错误行为
-- ============================================================
-- 跳过有问题的输入行（而非整个查询失败）
-- SET hive.exec.max.dynamic.partitions=1000;
-- SET hive.exec.max.dynamic.partitions.pernode=100;
-- SET hive.exec.max.created.files=100000;

-- 设置查询超时
-- SET hive.server2.idle.operation.timeout=3600000;
-- SET hive.server2.idle.session.timeout=7200000;

-- ============================================================
-- 常见错误场景
-- ============================================================
-- 1. 表不存在: Table not found
-- 2. 分区不存在: Partition not found
-- 3. 权限不足: Permission denied
-- 4. 资源不足: Container killed by YARN
-- 5. 数据格式错误: Failed with exception java.io.IOException

-- 注意：Hive 面向批处理，不支持服务端错误处理
-- 注意：使用 IF EXISTS / IF NOT EXISTS 避免常见 DDL 错误
-- 注意：Hive 配置参数可控制错误容忍度
-- 限制：无 TRY/CATCH, EXCEPTION WHEN, DECLARE HANDLER, SIGNAL
-- 限制：无存储过程或 PL/SQL 块
