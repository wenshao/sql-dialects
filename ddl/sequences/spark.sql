-- Spark SQL: Sequences & Auto-Increment
--
-- 参考资料:
--   [1] Spark SQL Documentation - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions-builtin.html
--   [2] Spark SQL Documentation - CREATE TABLE
--       https://spark.apache.org/docs/latest/sql-ref-syntax-ddl-create-table.html

-- ============================================
-- Spark SQL 不支持 SEQUENCE、AUTO_INCREMENT、IDENTITY
-- 以下是替代方案
-- ============================================

-- 方法 1：使用 monotonically_increasing_id()
SELECT
    monotonically_increasing_id() AS id,
    username,
    email
FROM users;
-- 注意：不保证连续，每个分区有独立计数器
-- 返回值 = partition_id * 8589934592 + partition内序号

-- 方法 2：使用 ROW_NUMBER() 窗口函数
SELECT
    ROW_NUMBER() OVER (ORDER BY created_at) AS row_id,
    username,
    email
FROM users;

-- 方法 3：使用 UUID 函数
SELECT
    uuid() AS id,
    username,
    email
FROM users;

-- 方法 4：CTAS + monotonically_increasing_id
CREATE TABLE users_with_id USING DELTA AS
SELECT
    monotonically_increasing_id() AS id,
    username,
    email,
    created_at
FROM staging_users;

-- 方法 5：使用 ZIPWITHINDEX（需要 DataFrame API）
-- 在 Spark Scala/Python API 中:
-- df.rdd.zipWithIndex().map(...)

-- ============================================
-- UUID 生成
-- ============================================
SELECT uuid();
-- 返回标准 UUID 字符串

-- ============================================
-- 序列 vs 自增 权衡
-- ============================================
-- Spark 是分布式批处理引擎：
-- 1. monotonically_increasing_id()：最简单但不连续
-- 2. ROW_NUMBER()：连续但需要全局排序（可能很慢）
-- 3. uuid()：分布式安全，无性能损耗
-- 4. zipWithIndex（API）：严格连续但需要额外 shuffle
-- 5. 数据通常已有业务键

-- 限制：
-- 不支持 CREATE SEQUENCE
-- 不支持 AUTO_INCREMENT / IDENTITY / SERIAL
-- 不支持 GENERATED AS IDENTITY
-- monotonically_increasing_id() 的值在重新计算时可能变化
