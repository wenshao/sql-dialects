-- Hologres: Sequences & Auto-Increment
--
-- 参考资料:
--   [1] Hologres Documentation - CREATE TABLE
--       https://www.alibabacloud.com/help/en/hologres/developer-reference/create-table
--   [2] Hologres Documentation - Serial Types
--       https://www.alibabacloud.com/help/en/hologres/developer-reference/serial

-- ============================================
-- SERIAL / BIGSERIAL（兼容 PostgreSQL）
-- ============================================
CREATE TABLE users (
    id       BIGSERIAL PRIMARY KEY,
    username TEXT NOT NULL,
    email    TEXT NOT NULL
);

-- SERIAL 等价于创建序列 + DEFAULT nextval
-- 注意：Hologres 中 SERIAL 的值在分布式环境下不保证连续

-- ============================================
-- SEQUENCE（Hologres 部分支持 PostgreSQL 序列语法）
-- ============================================
CREATE SEQUENCE user_id_seq START WITH 1 INCREMENT BY 1;
SELECT nextval('user_id_seq');

-- 使用序列
CREATE TABLE orders (
    id       BIGINT DEFAULT nextval('user_id_seq'),
    amount   DECIMAL(10,2)
);

-- 删除序列
DROP SEQUENCE user_id_seq;

-- ============================================
-- DEFAULT 表达式
-- ============================================
CREATE TABLE events (
    id         BIGSERIAL,
    event_type TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================
-- UUID 生成
-- ============================================
-- 需要安装 uuid-ossp 扩展（部分 Hologres 版本支持）
-- CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
-- SELECT uuid_generate_v4();

-- 使用内置随机函数模拟
-- SELECT md5(random()::text || clock_timestamp()::text);

-- ============================================
-- 序列 vs 自增 权衡
-- ============================================
-- 1. SERIAL/BIGSERIAL：简单易用，兼容 PostgreSQL
-- 2. SEQUENCE：灵活，可自定义起始值和步长
-- 3. Hologres 是分布式引擎，自增值可能不连续
-- 4. 建议对高并发场景使用 UUID 或业务键

-- 限制：
-- 不支持 GENERATED AS IDENTITY
-- 序列值在分布式环境下不保证连续和有序
-- 部分 PostgreSQL 序列功能可能不完全支持
