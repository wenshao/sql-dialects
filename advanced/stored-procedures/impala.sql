-- Apache Impala: 存储过程
--
-- 参考资料:
--   [1] Impala SQL Reference
--       https://impala.apache.org/docs/build/html/topics/impala_langref.html
--   [2] Impala Built-in Functions
--       https://impala.apache.org/docs/build/html/topics/impala_functions.html

-- Impala 不支持存储过程
-- 但支持 UDF（用户自定义函数）

-- ============================================================
-- UDF（用户自定义函数）
-- ============================================================

-- Impala 支持 C++ 和 Java 编写的 UDF

-- 创建 UDF（C++ 编译为 .so 文件）
-- CREATE FUNCTION my_upper(STRING) RETURNS STRING
-- LOCATION '/user/impala/udfs/libudf_samples.so'
-- SYMBOL='UpperUDF';

-- 创建 UDF（Java .jar 文件）
-- CREATE FUNCTION my_add(INT, INT) RETURNS INT
-- LOCATION '/user/impala/udfs/my_udfs.jar'
-- SYMBOL='com.example.AddUDF';

-- 调用 UDF
-- SELECT my_upper(username) FROM users;
-- SELECT my_add(age, 1) FROM users;

-- 删除 UDF
-- DROP FUNCTION my_upper(STRING);
-- DROP FUNCTION IF EXISTS my_add(INT, INT);

-- ============================================================
-- UDA（用户自定义聚合函数）
-- ============================================================

-- 创建 UDA（C++ 编译为 .so 文件）
-- CREATE AGGREGATE FUNCTION my_count(INT) RETURNS BIGINT
-- LOCATION '/user/impala/udfs/libudf_samples.so'
-- INIT_FN='CountInit'
-- UPDATE_FN='CountUpdate'
-- MERGE_FN='CountMerge'
-- SERIALIZE_FN='CountSerialize'
-- FINALIZE_FN='CountFinalize';

-- ============================================================
-- 替代方案一：视图
-- ============================================================

-- 用视图封装复杂查询
CREATE VIEW active_users_view AS
SELECT * FROM users WHERE status = 1;

CREATE VIEW user_summary_view AS
SELECT u.id, u.username,
    COUNT(o.id) AS order_count,
    SUM(o.amount) AS total_spend
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.id, u.username;

-- ============================================================
-- 替代方案二：客户端脚本
-- ============================================================

-- 使用 Python / Java / Shell 编写逻辑
-- 通过 JDBC/ODBC/HiveServer2 协议连接 Impala

-- ============================================================
-- 替代方案三：外部调度工具
-- ============================================================

-- Apache Airflow / Oozie / Azkaban
-- 编排多个 SQL 任务

-- ============================================================
-- Hive UDF 兼容
-- ============================================================

-- Impala 可以使用 Hive 中注册的 UDF
-- 需要先在 Hive 中注册，然后在 Impala 中刷新元数据
-- INVALIDATE METADATA;

-- 注意：Impala 不支持存储过程
-- 注意：支持 C++ UDF（性能最好）和 Java UDF
-- 注意：UDF 需要部署到 HDFS 上
-- 注意：UDA 是用户自定义聚合函数（C++ 实现）
-- 注意：可以使用 Hive 中注册的 UDF
