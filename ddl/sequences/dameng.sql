-- 达梦 (DM): Sequences & Auto-Increment
--
-- 参考资料:
--   [1] 达梦数据库 SQL 语言参考 - CREATE SEQUENCE
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/dmpl-sql-sequence.html
--   [2] 达梦数据库 SQL 语言参考 - IDENTITY 列
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/dmpl-sql-table.html

-- ============================================
-- SEQUENCE
-- ============================================
CREATE SEQUENCE user_id_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    MAXVALUE 9999999999
    CACHE 20
    NO CYCLE;

-- 使用序列
INSERT INTO users (id, username) VALUES (user_id_seq.NEXTVAL, 'alice');
SELECT user_id_seq.CURRVAL FROM DUAL;
SELECT user_id_seq.NEXTVAL FROM DUAL;

-- 修改序列
ALTER SEQUENCE user_id_seq INCREMENT BY 2;
ALTER SEQUENCE user_id_seq RESTART WITH 1000;

-- 删除序列
DROP SEQUENCE user_id_seq;
DROP SEQUENCE IF EXISTS user_id_seq;

-- ============================================
-- IDENTITY 列
-- 达梦支持 IDENTITY 自增列
-- ============================================
CREATE TABLE users (
    id       INT IDENTITY(1, 1),              -- 起始值 1，步长 1
    username VARCHAR(64) NOT NULL,
    email    VARCHAR(255) NOT NULL
);

-- IDENTITY(start, increment)
CREATE TABLE orders (
    id     INT IDENTITY(1000, 1),
    amount DECIMAL(10,2)
);

-- 插入时不指定 IDENTITY 列
INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com');

-- 获取最近生成的 IDENTITY 值
SELECT @@IDENTITY;
SELECT IDENT_CURRENT('users');

-- SET IDENTITY_INSERT 允许显式插入
SET IDENTITY_INSERT users ON;
INSERT INTO users (id, username, email) VALUES (100, 'bob', 'bob@example.com');
SET IDENTITY_INSERT users OFF;

-- ============================================
-- UUID 生成
-- ============================================
SELECT SYS_GUID() FROM DUAL;                 -- 返回 32 位十六进制字符串
SELECT NEWID();                               -- 返回标准 UUID 格式

-- ============================================
-- 序列 vs 自增 权衡
-- ============================================
-- 1. IDENTITY：简单易用，一张表一个自增列
-- 2. SEQUENCE：灵活，可跨表共享，可缓存
-- 3. SYS_GUID()/NEWID()：全局唯一，适合分布式场景
-- 达梦同时兼容 Oracle 的 SEQUENCE 语法和 SQL Server 的 IDENTITY 语法
