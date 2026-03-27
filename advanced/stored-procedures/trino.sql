-- Trino (formerly PrestoSQL): 存储过程和函数
--
-- 参考资料:
--   [1] Trino - SQL Routines
--       https://trino.io/docs/current/routines.html
--   [2] Trino - SQL Statement List
--       https://trino.io/docs/current/sql.html

-- Trino 不支持存储过程
-- 提供有限的函数扩展能力

-- ============================================================
-- 内置函数（丰富）
-- ============================================================

-- Trino 有大量内置函数
SELECT
    upper(username),
    length(email),
    substr(email, 1, 5),
    concat(first_name, ' ', last_name),
    coalesce(phone, 'N/A'),
    date_trunc('day', created_at),
    json_extract_scalar(data, '$.name')
FROM users;

-- 查看所有函数
SHOW FUNCTIONS;
SHOW FUNCTIONS LIKE 'date%';

-- ============================================================
-- Lambda 表达式（用于数组/MAP 操作）
-- ============================================================

-- 数组转换
SELECT transform(ARRAY[1, 2, 3], x -> x * 2);           -- [2, 4, 6]
SELECT filter(ARRAY[1, 2, 3, 4, 5], x -> x > 3);        -- [4, 5]
SELECT reduce(ARRAY[1, 2, 3], 0, (s, x) -> s + x, s -> s);  -- 6

-- MAP 操作
SELECT transform_keys(MAP(ARRAY['a'], ARRAY[1]), (k, v) -> upper(k));
SELECT transform_values(MAP(ARRAY['a'], ARRAY[1]), (k, v) -> v * 10);

-- ============================================================
-- SQL 例程（Routine，Trino 420+）
-- ============================================================

-- 内联函数定义（会话级别）
-- 注意：这是较新的功能

-- ============================================================
-- 插件 UDF（通过 SPI 扩展）
-- ============================================================

-- Trino 通过 SPI（Service Provider Interface）支持自定义函数
-- 需要编写 Java 插件

-- 1. 实现 @ScalarFunction 注解的 Java 方法
-- 2. 打包为 Trino 插件
-- 3. 部署到 Trino 集群的 plugin 目录

-- 示例 Java 代码（不是 SQL）：
-- @ScalarFunction("my_func")
-- @SqlType(StandardTypes.VARCHAR)
-- public static Slice myFunc(@SqlType(StandardTypes.VARCHAR) Slice input) {
--     return Slices.utf8Slice(input.toStringUtf8().toUpperCase());
-- }

-- ============================================================
-- Connector 特定的函数
-- ============================================================

-- 不同 Connector 提供特有函数
-- Hive Connector: 支持 Hive UDF
-- PostgreSQL Connector: 可以调用 PostgreSQL 函数

-- 通过 Hive Connector 使用 Hive UDF
-- 需要 Hive Metastore 中注册的 UDF

-- ============================================================
-- 聚合函数
-- ============================================================

-- 近似聚合（Trino 特色）
SELECT approx_distinct(user_id) FROM orders;
SELECT approx_percentile(amount, 0.95) FROM orders;
SELECT approx_most_frequent(5, city, 1000) FROM users;

-- HyperLogLog
SELECT cardinality(merge(CAST(approx_set(user_id) AS hyperloglog))) FROM orders;

-- ============================================================
-- 表函数（Table Function，Trino 381+）
-- ============================================================

-- 内置表函数
SELECT * FROM TABLE(sequence(1, 10));
SELECT * FROM TABLE(exclude_columns(
    INPUT => TABLE(users),
    COLUMNS => DESCRIPTOR(password, secret)
));

-- ============================================================
-- 替代方案：使用 WITH (CTE) 组织复杂逻辑
-- ============================================================

WITH step1 AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
),
step2 AS (
    SELECT u.*, s.total FROM users u JOIN step1 s ON u.id = s.user_id
)
SELECT * FROM step2 WHERE total > 1000;

-- 注意：Trino 不支持存储过程（CREATE PROCEDURE）
-- 注意：函数扩展通过 Java SPI 插件实现
-- 注意：Trino 是查询引擎，复杂逻辑应在应用层处理
-- 注意：Lambda 表达式提供灵活的内联数据处理能力
-- 注意：SQL Routine 是较新的功能（420+版本）
