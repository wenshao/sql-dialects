-- Impala: Sequences & Auto-Increment
--
-- 参考资料:
--   [1] Impala Documentation - CREATE TABLE
--       https://impala.apache.org/docs/build/html/topics/impala_create_table.html
--   [2] Impala Documentation - Built-in Functions
--       https://impala.apache.org/docs/build/html/topics/impala_functions.html

-- ============================================
-- Impala 不支持 SEQUENCE、AUTO_INCREMENT、IDENTITY
-- 以下是替代方案
-- ============================================

-- 方法 1：使用 uuid() 函数
SELECT uuid() AS id, username, email
FROM users;

-- 在 CTAS 中使用
CREATE TABLE users_with_uuid AS
SELECT uuid() AS id, username, email, created_at
FROM staging_users;

-- 方法 2：使用 ROW_NUMBER() 窗口函数
SELECT
    ROW_NUMBER() OVER (ORDER BY created_at) AS row_id,
    username,
    email
FROM users;

-- 方法 3：使用外部系统生成 ID
-- Impala 通常从 HDFS/Kudu/HBase 读取数据
-- ID 由 ETL 管道或源系统生成

-- 方法 4：使用 Kudu 表的自增功能（如果使用 Kudu 后端）
-- Kudu 表支持 auto-incrementing 列（Kudu 1.17+）
-- CREATE TABLE kudu_users (
--     id       BIGINT PRIMARY KEY AUTO_INCREMENT,
--     username STRING
-- ) STORED AS KUDU;

-- ============================================
-- UUID 生成
-- ============================================
SELECT uuid();
-- 返回类似 'a1b2c3d4e5f6:7890abcdef12:3456789abcde' 的字符串
-- 注意：Impala 的 uuid() 格式不是标准 RFC 4122 格式

-- ============================================
-- 序列 vs 自增 权衡
-- ============================================
-- Impala 是 MPP 查询引擎，设计用于分析而非 OLTP：
-- 1. 数据通常由 ETL 管道加载，ID 在上游生成
-- 2. uuid() 是查询时唯一标识的最简单方式
-- 3. ROW_NUMBER() 适合为结果集编号
-- 4. 如使用 Kudu 后端，可利用 Kudu 的自增功能
-- 5. 不需要严格递增的序列号

-- 限制：
-- 不支持 CREATE SEQUENCE
-- 不支持 AUTO_INCREMENT / IDENTITY / SERIAL
-- 不支持 GENERATED AS IDENTITY
-- uuid() 返回非标准格式
