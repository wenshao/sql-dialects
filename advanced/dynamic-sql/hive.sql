-- Apache Hive: Dynamic SQL
--
-- 参考资料:
--   [1] Apache Hive Language Manual
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual
--   [2] HiveQL Reference
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DML

-- ============================================================
-- Hive 不支持服务端动态 SQL
-- ============================================================
-- Hive 不支持存储过程、PREPARE/EXECUTE 或 EXECUTE IMMEDIATE

-- ============================================================
-- 应用层替代方案: HiveQL 变量替换
-- ============================================================
-- hive -e "SELECT * FROM users WHERE age > ${hiveconf:min_age}"
-- hive --hiveconf min_age=18 -e "SELECT * FROM users WHERE age > ${hiveconf:min_age}"
SET hivevar:table_name=users;
SELECT * FROM ${hivevar:table_name} LIMIT 10;

-- ============================================================
-- 应用层替代方案: Beeline 参数化
-- ============================================================
-- beeline -u "jdbc:hive2://host:10000" \
--   --hivevar table_name=users \
--   -e "SELECT COUNT(*) FROM \${hivevar:table_name}"

-- ============================================================
-- 应用层替代方案: Python (PyHive)
-- ============================================================
-- from pyhive import hive
-- conn = hive.connect('localhost')
-- cursor = conn.cursor()
--
-- # 参数化查询
-- cursor.execute('SELECT * FROM users WHERE age > %s', (18,))

-- 注意：Hive 面向批处理分析，不支持传统动态 SQL
-- 注意：使用 SET hivevar / hiveconf 实现有限的变量替换
-- 注意：复杂动态 SQL 在应用层（Python/Java/Spark）实现
-- 限制：无 PREPARE / EXECUTE / EXECUTE IMMEDIATE
-- 限制：无存储过程
