-- Snowflake: Sequences & Auto-Increment
--
-- 参考资料:
--   [1] Snowflake Documentation - CREATE SEQUENCE
--       https://docs.snowflake.com/en/sql-reference/sql/create-sequence
--   [2] Snowflake Documentation - AUTOINCREMENT / IDENTITY
--       https://docs.snowflake.com/en/sql-reference/sql/create-table
--   [3] Snowflake Documentation - UUID Functions
--       https://docs.snowflake.com/en/sql-reference/functions/uuid_string

-- ============================================
-- SEQUENCE
-- ============================================
CREATE SEQUENCE user_id_seq;

CREATE SEQUENCE order_id_seq
    START = 1
    INCREMENT = 1
    COMMENT = 'Order ID sequence';

-- CREATE OR REPLACE
CREATE OR REPLACE SEQUENCE user_id_seq START = 1 INCREMENT = 1;

-- 使用序列
INSERT INTO users (id, username) VALUES (user_id_seq.NEXTVAL, 'alice');
SELECT user_id_seq.NEXTVAL;

-- 修改序列
ALTER SEQUENCE user_id_seq SET INCREMENT = 2;

-- 删除序列
DROP SEQUENCE user_id_seq;
DROP SEQUENCE IF EXISTS user_id_seq;

-- ============================================
-- AUTOINCREMENT / IDENTITY
-- Snowflake 支持两种等价语法
-- ============================================
CREATE TABLE users (
    id       NUMBER AUTOINCREMENT,           -- 或 IDENTITY
    username VARCHAR(64) NOT NULL,
    email    VARCHAR(255) NOT NULL
);

-- 指定起始值和步长
CREATE TABLE orders (
    id       NUMBER AUTOINCREMENT START 1 INCREMENT 1,
    amount   NUMBER(10,2)
);

-- 等价的 IDENTITY 语法
CREATE TABLE products (
    id       NUMBER IDENTITY(1, 1),          -- IDENTITY(start, step)
    name     VARCHAR(64)
);

-- AUTOINCREMENT 的 ORDER / NOORDER
CREATE TABLE logs (
    id       NUMBER AUTOINCREMENT START 1 INCREMENT 1 ORDER,    -- 全局有序
    message  VARCHAR(1000)
);

CREATE TABLE events (
    id       NUMBER AUTOINCREMENT START 1 INCREMENT 1 NOORDER,  -- 可能不连续，性能更好
    data     VARIANT
);

-- 注意：Snowflake 的主键和唯一约束是信息性的，不强制执行！

-- ============================================
-- UUID 生成
-- ============================================
SELECT UUID_STRING();                        -- 返回 v4 UUID
-- 结果示例：'7f1b7e42-3a1c-4b5d-8f2e-9c0d1e2f3a4b'

CREATE TABLE sessions (
    id         VARCHAR(36) DEFAULT UUID_STRING(),
    user_id    NUMBER,
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================
-- 序列 vs 自增 权衡
-- ============================================
-- 1. AUTOINCREMENT/IDENTITY：简单，Snowflake 原生
-- 2. SEQUENCE：灵活，可跨表共享
-- 3. UUID_STRING()：全局唯一
-- 4. ORDER vs NOORDER：性能 vs 有序性
-- 5. Snowflake 约束是信息性的，唯一性不强制
-- 6. 数据仓库场景通常使用业务键而非自增
