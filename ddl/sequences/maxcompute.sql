-- MaxCompute (ODPS): Sequences & Auto-Increment
--
-- 参考资料:
--   [1] MaxCompute Documentation - Data Types
--       https://www.alibabacloud.com/help/en/maxcompute/user-guide/data-type-editions
--   [2] MaxCompute Documentation - Built-in Functions
--       https://www.alibabacloud.com/help/en/maxcompute/user-guide/built-in-functions
--   [3] MaxCompute Documentation - SEQUENCE
--       https://www.alibabacloud.com/help/en/maxcompute/user-guide/sequence

-- ============================================
-- MaxCompute 不支持传统的 SEQUENCE 和 AUTO_INCREMENT
-- ============================================

-- 方法 1：使用 ROW_NUMBER() 窗口函数
SELECT
    ROW_NUMBER() OVER (ORDER BY created_at) AS row_id,
    username,
    email
FROM users;

-- 方法 2：使用 UUID 生成唯一标识
SELECT
    UUID() AS id,
    username,
    email
FROM staging_users;

-- 方法 3：使用 SEQUENCE（MaxCompute 2.0+）
-- 注意：MaxCompute 的 SEQUENCE 是表级别的自增列，非独立对象
CREATE TABLE users (
    id       BIGINT DEFAULT SEQUENCE(1, 1),  -- 起始值 1，步长 1
    username STRING,
    email    STRING
);

-- 方法 4：使用 CTAS + ROW_NUMBER
CREATE TABLE users_with_id AS
SELECT
    ROW_NUMBER() OVER (ORDER BY created_at) AS id,
    username,
    email,
    created_at
FROM users;

-- ============================================
-- UUID 生成
-- ============================================
SELECT UUID();
-- 返回标准 UUID 字符串

-- ============================================
-- 序列 vs 自增 权衡
-- ============================================
-- MaxCompute 是离线批处理数仓引擎：
-- 1. 数据通常批量导入，不需要实时自增
-- 2. UUID() 适合全局唯一标识
-- 3. ROW_NUMBER() 适合为结果集编号
-- 4. 如需持久化自增 ID，在数据管道中生成

-- 限制：
-- 不支持 CREATE SEQUENCE（独立序列对象）
-- 不支持 AUTO_INCREMENT / IDENTITY / SERIAL
-- 不支持 GENERATED AS IDENTITY
-- SEQUENCE 作为列默认值的语法有限
