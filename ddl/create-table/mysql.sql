-- MySQL: CREATE TABLE
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - CREATE TABLE
--       https://dev.mysql.com/doc/refman/8.0/en/create-table.html
--   [2] MySQL 8.0 Reference Manual - Data Types
--       https://dev.mysql.com/doc/refman/8.0/en/data-types.html
--   [3] MySQL 8.0 Reference Manual - AUTO_INCREMENT
--       https://dev.mysql.com/doc/refman/8.0/en/example-auto-increment.html

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
