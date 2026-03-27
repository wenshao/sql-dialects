-- Trino (formerly Presto SQL): Sequences & Auto-Increment
--
-- 参考资料:
--   [1] Trino Documentation - CREATE TABLE
--       https://trino.io/docs/current/sql/create-table.html
--   [2] Trino Documentation - Functions and Operators
--       https://trino.io/docs/current/functions.html
--   [3] Trino Documentation - UUID Functions
--       https://trino.io/docs/current/functions/uuid.html

-- ============================================
-- Trino 不支持 SEQUENCE、AUTO_INCREMENT、IDENTITY
-- 以下是替代方案
-- ============================================

-- 方法 1：使用 UUID 函数
SELECT
    uuid() AS id,
    username,
    email
FROM users;

-- 在 CTAS 中使用
CREATE TABLE users_with_uuid AS
SELECT
    uuid() AS id,
    username,
    email,
    created_at
FROM staging_users;

-- 方法 2：使用 ROW_NUMBER() 窗口函数
SELECT
    ROW_NUMBER() OVER (ORDER BY created_at) AS row_id,
    username,
    email
FROM users;

-- 方法 3：使用 from_unixtime + 随机数组合
SELECT
    CAST(to_unixtime(now()) * 1000000 + (random() * 999999) AS BIGINT) AS pseudo_id,
    username
FROM users;

-- ============================================
-- UUID 生成
-- ============================================
SELECT uuid();
-- 返回 UUID 类型值

-- UUID 类型操作
SELECT CAST(uuid() AS VARCHAR);             -- 转为字符串
SELECT CAST('7f1b7e42-3a1c-4b5d-8f2e-9c0d1e2f3a4b' AS UUID);  -- 字符串转 UUID

-- ============================================
-- 序列 vs 自增 权衡
-- ============================================
-- Trino 是联邦查询引擎，设计用于分析而非 OLTP：
-- 1. uuid()：最常用的唯一标识方案
-- 2. ROW_NUMBER()：为结果集编号
-- 3. 数据通常在源系统中已有 ID
-- 4. Trino 不存储数据（写入取决于 Connector）
-- 5. 如果 Connector 支持（如 Iceberg），可使用底层存储的 ID 机制

-- 限制：
-- 不支持 CREATE SEQUENCE
-- 不支持 AUTO_INCREMENT / IDENTITY / SERIAL
-- 不支持 GENERATED AS IDENTITY
-- ID 生成依赖于底层 Connector 的能力
