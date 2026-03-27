-- Apache Spark SQL: Dynamic SQL
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html
--   [2] Spark SQL Programming Guide
--       https://spark.apache.org/docs/latest/sql-programming-guide.html

-- ============================================================
-- Spark SQL 不支持服务端动态 SQL
-- ============================================================
-- Spark SQL 没有存储过程（Spark 3.x 有初步支持但功能有限）

-- ============================================================
-- 应用层替代方案: PySpark
-- ============================================================
-- # 动态 SQL
-- table_name = "users"
-- df = spark.sql(f"SELECT * FROM {table_name} WHERE age > 18")
--
-- # 参数化 (Spark 3.4+)
-- spark.sql("SELECT * FROM users WHERE age > :min_age", args={"min_age": 18})
--
-- # 使用 DataFrame API 替代动态 SQL
-- df = spark.table("users").filter(col("age") > 18)

-- ============================================================
-- Spark SQL 变量替换
-- ============================================================
-- SET spark.sql.variable.substitute=true;
-- SET hivevar:table_name=users;
-- SELECT * FROM ${hivevar:table_name} LIMIT 10;

-- ============================================================
-- Spark 3.4+ 参数化查询
-- ============================================================
-- SELECT * FROM users WHERE age > :min_age;
-- 通过 spark.sql() 的 args 参数传入值

-- 版本说明：
--   Spark 3.4+ : 参数化查询 (:param 语法)
-- 注意：推荐使用 DataFrame API 替代动态 SQL
-- 注意：Spark SQL 主要面向批处理和交互式分析
-- 限制：无 PREPARE / EXECUTE / EXECUTE IMMEDIATE
-- 限制：存储过程支持非常有限
