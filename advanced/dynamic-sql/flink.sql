-- Apache Flink SQL: Dynamic SQL
--
-- 参考资料:
--   [1] Apache Flink Documentation - SQL
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/

-- ============================================================
-- Flink SQL 不支持服务端动态 SQL
-- ============================================================
-- Flink SQL 是流处理 SQL 引擎，不支持存储过程或动态 SQL

-- ============================================================
-- 应用层替代方案: Table API (Java/Scala)
-- ============================================================
-- TableEnvironment tEnv = ...;
--
-- // 动态执行 SQL
-- String sql = "SELECT * FROM users WHERE age > " + minAge;
-- Table result = tEnv.sqlQuery(sql);
--
-- // 动态 DDL
-- tEnv.executeSql("CREATE TABLE " + tableName + " (id INT, name STRING) WITH (...)");

-- ============================================================
-- 应用层替代方案: Python (PyFlink)
-- ============================================================
-- from pyflink.table import TableEnvironment
-- t_env = TableEnvironment.create(...)
--
-- # 动态 SQL
-- table_name = "users"
-- result = t_env.sql_query(f"SELECT * FROM {table_name} WHERE age > 18")

-- ============================================================
-- SQL Client 中的变量替代                             -- 1.15+
-- ============================================================
-- SET 'table.name' = 'users';
-- Flink SQL Client 支持有限的变量替换

-- 注意：Flink SQL 面向流处理，不支持传统动态 SQL
-- 注意：通过 Table API 在应用层实现动态 SQL
-- 限制：无 PREPARE / EXECUTE / EXECUTE IMMEDIATE
-- 限制：无存储过程
