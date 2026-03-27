-- MySQL: INSERT
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - INSERT
--       https://dev.mysql.com/doc/refman/8.0/en/insert.html
--   [2] MySQL 8.0 Reference Manual - INSERT ... SELECT
--       https://dev.mysql.com/doc/refman/8.0/en/insert-select.html

-- 单行插入
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- 多行插入
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);

-- 插入并忽略重复
INSERT IGNORE INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- 从查询结果插入
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;

-- 8.0.19+: VALUES 行别名
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25) AS new
ON DUPLICATE KEY UPDATE email = new.email;

-- 8.0.19+: TABLE 语句（插入整个表）
INSERT INTO users_backup TABLE users;

-- 获取自增 ID
INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com');
SELECT LAST_INSERT_ID();

-- 指定列默认值
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', DEFAULT);

-- SET 语法（MySQL 特有）
INSERT INTO users SET username = 'alice', email = 'alice@example.com', age = 25;
