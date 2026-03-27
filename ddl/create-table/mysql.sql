-- MySQL: CREATE TABLE
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - CREATE TABLE
--       https://dev.mysql.com/doc/refman/8.0/en/create-table.html
--   [2] MySQL 8.0 Reference Manual - Data Types
--       https://dev.mysql.com/doc/refman/8.0/en/data-types.html
--   [3] MySQL 8.0 Reference Manual - AUTO_INCREMENT
--       https://dev.mysql.com/doc/refman/8.0/en/example-auto-increment.html

-- ============================================================
-- 基本建表
-- ============================================================
CREATE TABLE users (
    id         BIGINT       NOT NULL AUTO_INCREMENT,
    username   VARCHAR(64)  NOT NULL,
    email      VARCHAR(255) NOT NULL,
    age        INT,
    balance    DECIMAL(10,2) DEFAULT 0.00,
    bio        TEXT,
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_username (username),
    UNIQUE KEY uk_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================
-- 常用数据类型
-- ============================================================
-- 整数: TINYINT, SMALLINT, MEDIUMINT, INT, BIGINT
-- 浮点: FLOAT, DOUBLE, DECIMAL(M,D)
-- 字符: CHAR(n), VARCHAR(n), TEXT, MEDIUMTEXT, LONGTEXT
-- 二进制: BINARY(n), VARBINARY(n), BLOB, MEDIUMBLOB, LONGBLOB
-- 日期: DATE, TIME, DATETIME, TIMESTAMP, YEAR
-- 其他: ENUM('a','b'), SET('a','b'), JSON, BOOLEAN

-- ============================================================
-- IF NOT EXISTS（条件建表）
-- ============================================================
CREATE TABLE IF NOT EXISTS audit_log (
    id         BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    action     VARCHAR(50)  NOT NULL,
    details    JSON,
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- ============================================================
-- 索引
-- ============================================================
CREATE TABLE orders (
    id          BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    user_id     BIGINT       NOT NULL,
    status      ENUM('pending', 'paid', 'shipped', 'completed', 'cancelled') NOT NULL DEFAULT 'pending',
    total       DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id),
    INDEX idx_status_created (status, created_at),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ============================================================
-- CREATE TABLE ... SELECT（从查询结果建表）
-- ============================================================
CREATE TABLE active_users AS
SELECT id, username, email FROM users WHERE age >= 18;

-- ============================================================
-- CREATE TABLE ... LIKE（复制表结构）
-- ============================================================
CREATE TABLE users_backup LIKE users;

-- 版本说明：
--   MySQL 5.7+ : JSON 类型
--   MySQL 8.0+ : 表达式默认值, CHECK 约束, 不可见索引
-- 注意：AUTO_INCREMENT 是 MySQL 特有的自增语法
-- 注意：ON UPDATE CURRENT_TIMESTAMP 自动更新时间戳（MySQL 特有）
-- 注意：ENGINE=InnoDB 是默认存储引擎（支持事务和外键）
-- 注意：CHARSET=utf8mb4 支持完整 Unicode（包括 emoji）
