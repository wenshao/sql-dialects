-- DuckDB: Sequences & Auto-Increment
--
-- 参考资料:
--   [1] DuckDB Documentation - CREATE SEQUENCE
--       https://duckdb.org/docs/sql/statements/create_sequence
--   [2] DuckDB Documentation - Data Types
--       https://duckdb.org/docs/sql/data_types/overview

-- ============================================
-- SEQUENCE
-- ============================================
CREATE SEQUENCE user_id_seq;

CREATE SEQUENCE order_id_seq
    START 1
    INCREMENT BY 1
    MINVALUE 1
    MAXVALUE 9223372036854775807
    NO CYCLE;

-- 使用序列
INSERT INTO users (id, username) VALUES (nextval('user_id_seq'), 'alice');
SELECT nextval('user_id_seq');
SELECT currval('user_id_seq');

-- 修改序列
ALTER SEQUENCE user_id_seq RESTART;
ALTER SEQUENCE user_id_seq RESTART WITH 1000;

-- 删除序列
DROP SEQUENCE user_id_seq;
DROP SEQUENCE IF EXISTS user_id_seq;

-- ============================================
-- 自增列
-- ============================================
-- 使用序列实现自增
CREATE SEQUENCE users_id_seq START 1;
CREATE TABLE users (
    id       BIGINT DEFAULT nextval('users_id_seq'),
    username VARCHAR NOT NULL,
    email    VARCHAR NOT NULL
);

-- 使用 rowid（隐式行标识符）
-- DuckDB 为每张表自动维护 rowid

-- ============================================
-- UUID 生成
-- ============================================
SELECT uuid();
-- 结果示例：'7f1b7e42-3a1c-4b5d-8f2e-9c0d1e2f3a4b'

CREATE TABLE sessions (
    id         UUID DEFAULT uuid(),
    user_id    BIGINT,
    created_at TIMESTAMP DEFAULT current_timestamp
);

-- ============================================
-- 序列 vs 自增 权衡
-- ============================================
-- 1. SEQUENCE：标准方式，灵活
-- 2. uuid()：全局唯一，无需协调
-- 3. DuckDB 作为嵌入式 OLAP，通常不需要复杂的 ID 策略
-- 4. 分析场景下，数据通常已有业务键

-- 限制：
-- 不支持 SERIAL / BIGSERIAL 类型（使用 SEQUENCE + DEFAULT）
-- 不支持 IDENTITY 列
-- 不支持 AUTO_INCREMENT
-- 不支持 GENERATED AS IDENTITY
