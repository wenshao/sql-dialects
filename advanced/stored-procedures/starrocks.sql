-- StarRocks: 存储过程和函数
--
-- 参考资料:
--   [1] StarRocks SQL Reference
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/
--   [2] StarRocks Documentation
--       https://docs.starrocks.io/docs/

-- StarRocks 不支持存储过程
-- 使用 UDF 和 SQL 管道替代

-- ============================================================
-- Java UDF（2.2+）
-- ============================================================

-- 标量函数（Scalar UDF）
-- 1. 编写 Java 类实现 UDF 接口
-- 2. 打包为 JAR
-- 3. 注册函数

CREATE FUNCTION my_lower(STRING)
RETURNS STRING
PROPERTIES (
    "symbol" = "com.example.udf.Lower",
    "type" = "StarrocksJar",
    "file" = "http://host:port/my_udf.jar"
);

SELECT my_lower(username) FROM users;

-- ============================================================
-- Global UDF（3.0+）
-- ============================================================

CREATE GLOBAL FUNCTION my_upper(STRING)
RETURNS STRING
PROPERTIES (
    "symbol" = "com.example.udf.Upper",
    "type" = "StarrocksJar",
    "file" = "http://host:port/my_udf.jar"
);

-- 所有数据库都可以使用

-- ============================================================
-- Java UDAF（用户定义聚合函数）
-- ============================================================

CREATE AGGREGATE FUNCTION my_median(DOUBLE)
RETURNS DOUBLE
PROPERTIES (
    "symbol" = "com.example.udaf.Median",
    "type" = "StarrocksJar",
    "file" = "http://host:port/my_udaf.jar"
);

SELECT my_median(age) FROM users;

-- ============================================================
-- Java UDTF（用户定义表生成函数，3.2+）
-- ============================================================

CREATE TABLE FUNCTION my_explode(STRING)
RETURNS (word STRING)
PROPERTIES (
    "symbol" = "com.example.udtf.Explode",
    "type" = "StarrocksJar",
    "file" = "http://host:port/my_udtf.jar"
);

SELECT u.id, t.word
FROM users u, my_explode(u.bio) t;

-- ============================================================
-- 物化视图（替代存储过程逻辑）
-- ============================================================

-- 同步物化视图
CREATE MATERIALIZED VIEW mv_user_stats AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- 异步物化视图（2.4+）
CREATE MATERIALIZED VIEW mv_daily_report
REFRESH ASYNC EVERY (INTERVAL 1 HOUR)
AS
SELECT
    order_date,
    COUNT(*) AS order_count,
    SUM(amount) AS total_amount,
    AVG(amount) AS avg_amount
FROM orders
GROUP BY order_date;

-- 手动刷新
REFRESH MATERIALIZED VIEW mv_daily_report;

-- ============================================================
-- INSERT INTO ... SELECT（ETL 替代方案）
-- ============================================================

-- 使用 SQL 管道替代存储过程
INSERT INTO user_summary
SELECT
    user_id,
    COUNT(*) AS order_count,
    SUM(amount) AS total_amount,
    MAX(order_date) AS last_order_date
FROM orders
GROUP BY user_id;

-- ============================================================
-- 删除函数
-- ============================================================

DROP FUNCTION my_lower(STRING);
DROP GLOBAL FUNCTION my_upper(STRING);
DROP AGGREGATE FUNCTION my_median(DOUBLE);
DROP TABLE FUNCTION my_explode(STRING);

-- 查看函数
SHOW FUNCTIONS;
SHOW GLOBAL FUNCTIONS;

-- 注意：StarRocks 不支持存储过程
-- 注意：UDF 只支持 Java（不支持 Python/JavaScript）
-- 注意：Global UDF 在所有数据库中可用
-- 注意：物化视图是实现自动数据处理的主要方式
-- 注意：复杂 ETL 逻辑通过外部调度工具编排
