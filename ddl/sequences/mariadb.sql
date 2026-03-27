-- MariaDB: Sequences & Auto-Increment
--
-- 参考资料:
--   [1] MariaDB Documentation - CREATE SEQUENCE
--       https://mariadb.com/kb/en/create-sequence/
--   [2] MariaDB Documentation - AUTO_INCREMENT
--       https://mariadb.com/kb/en/auto_increment/
--   [3] MariaDB Documentation - Sequence Functions
--       https://mariadb.com/kb/en/sequence-functions/

-- ============================================
-- SEQUENCE（MariaDB 10.3+）
-- ============================================
CREATE SEQUENCE user_id_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    MAXVALUE 9999999999
    CACHE 20
    NO CYCLE;

-- 使用序列（两种语法）
SELECT NEXT VALUE FOR user_id_seq;           -- SQL 标准语法
SELECT NEXTVAL(user_id_seq);                 -- MariaDB 简写
SELECT PREVIOUS VALUE FOR user_id_seq;
SELECT LASTVAL(user_id_seq);

INSERT INTO users (id, username) VALUES (NEXT VALUE FOR user_id_seq, 'alice');

-- 修改序列
ALTER SEQUENCE user_id_seq RESTART WITH 1000;
ALTER SEQUENCE user_id_seq INCREMENT BY 2;

-- 删除序列
DROP SEQUENCE user_id_seq;
DROP SEQUENCE IF EXISTS user_id_seq;

-- CREATE OR REPLACE SEQUENCE
CREATE OR REPLACE SEQUENCE order_id_seq START WITH 1;

-- ============================================
-- AUTO_INCREMENT
-- ============================================
CREATE TABLE users (
    id       BIGINT NOT NULL AUTO_INCREMENT,
    username VARCHAR(64) NOT NULL,
    email    VARCHAR(255) NOT NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB;

-- 获取最后生成的 AUTO_INCREMENT 值
SELECT LAST_INSERT_ID();

-- 设置表的 AUTO_INCREMENT 起始值
ALTER TABLE users AUTO_INCREMENT = 1000;

-- ============================================
-- UUID 生成
-- ============================================
SELECT UUID();
-- 结果示例：'7f1b7e42-3a1c-4b5d-8f2e-9c0d1e2f3a4b'

-- UUID 转为二进制（更高效的存储）
SELECT UUID_SHORT();                         -- 返回 64 位整数 UUID

CREATE TABLE sessions (
    id         BINARY(16) DEFAULT (UUID_TO_BIN(UUID())),   -- MariaDB 10.7+
    user_id    BIGINT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- 序列 vs 自增 权衡
-- ============================================
-- 1. AUTO_INCREMENT：最简单，MySQL 兼容，一张表只能有一个
-- 2. SEQUENCE（10.3+）：灵活，可跨表共享，支持 CYCLE/CACHE
-- 3. UUID()：全局唯一，不依赖数据库
-- 4. UUID_SHORT()：64 位整数，适合主键
-- 5. SEQUENCE 在主从复制中行为与 AUTO_INCREMENT 不同，需注意
