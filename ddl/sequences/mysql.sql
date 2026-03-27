-- MySQL: Sequences & Auto-Increment
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - AUTO_INCREMENT
--       https://dev.mysql.com/doc/refman/8.0/en/example-auto-increment.html
--   [2] MySQL 8.0 Reference Manual - UUID Functions
--       https://dev.mysql.com/doc/refman/8.0/en/miscellaneous-functions.html#function_uuid
--   [3] MySQL 8.0 Reference Manual - LAST_INSERT_ID()
--       https://dev.mysql.com/doc/refman/8.0/en/information-functions.html#function_last-insert-id

-- ============================================
-- AUTO_INCREMENT
-- ============================================
CREATE TABLE users (
    id       BIGINT NOT NULL AUTO_INCREMENT,
    username VARCHAR(64) NOT NULL,
    email    VARCHAR(255) NOT NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB;

-- 获取最后生成的值
SELECT LAST_INSERT_ID();

-- 设置起始值
ALTER TABLE users AUTO_INCREMENT = 1000;

-- 全局设置自增步长（主从复制场景）
SET @@auto_increment_increment = 2;          -- 步长
SET @@auto_increment_offset = 1;             -- 起始偏移

-- AUTO_INCREMENT 行为（MySQL 8.0 变更）
-- InnoDB 8.0+: AUTO_INCREMENT 计数器持久化到磁盘
-- 之前版本: 重启后计数器可能回退到 MAX(id)+1

-- ============================================
-- MySQL 不支持 CREATE SEQUENCE
-- 模拟序列的方法
-- ============================================

-- 方法 1：使用单行表模拟序列
CREATE TABLE my_sequence (
    seq_name VARCHAR(64) PRIMARY KEY,
    current_value BIGINT NOT NULL DEFAULT 0
) ENGINE=InnoDB;

INSERT INTO my_sequence VALUES ('order_id', 0);

-- 获取下一个值（原子操作）
UPDATE my_sequence SET current_value = LAST_INSERT_ID(current_value + 1) WHERE seq_name = 'order_id';
SELECT LAST_INSERT_ID();

-- 方法 2：使用函数模拟（MySQL 8.0+）
-- CREATE FUNCTION next_val(p_name VARCHAR(64)) RETURNS BIGINT ...

-- ============================================
-- UUID 生成
-- ============================================
SELECT UUID();
-- 结果示例：'7f1b7e42-3a1c-4b5d-8f2e-9c0d1e2f3a4b'

-- UUID 转二进制存储（推荐，更高效）
SELECT UUID_TO_BIN(UUID());                  -- MySQL 8.0+
SELECT UUID_TO_BIN(UUID(), 1);               -- 时间有序的 UUID（swap time-low/time-high）
SELECT BIN_TO_UUID(id) FROM sessions;        -- 读取时转回字符串

CREATE TABLE sessions (
    id         BINARY(16) DEFAULT (UUID_TO_BIN(UUID(), 1)),  -- 8.0.13+
    user_id    BIGINT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- 序列 vs 自增 权衡
-- ============================================
-- 1. AUTO_INCREMENT（推荐）：简单高效，InnoDB 原生支持
-- 2. 模拟序列：灵活但复杂，有锁竞争
-- 3. UUID()：全局唯一，但索引效率低（随机写入）
-- 4. UUID_TO_BIN(UUID(), 1)（推荐 UUID 方案）：时间有序，索引友好
-- 5. 一张表只能有一个 AUTO_INCREMENT 列
-- 6. AUTO_INCREMENT 列必须有索引（通常是主键）
