-- openGauss/GaussDB: INSERT
-- PostgreSQL compatible syntax.
--
-- 参考资料:
--   [1] openGauss SQL Reference
--       https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/SQL-reference.html
--   [2] GaussDB Documentation
--       https://support.huaweicloud.com/gaussdb/index.html

-- 单行插入
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- 多行插入
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);

-- 从查询结果插入
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;

-- RETURNING（返回插入的行）
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
RETURNING id, username;

-- RETURNING *
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
RETURNING *;

-- 指定默认值
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', DEFAULT);

-- DEFAULT VALUES（所有列使用默认值）
INSERT INTO logs DEFAULT VALUES RETURNING id;

-- CTE + INSERT
WITH new_users AS (
    SELECT 'alice' AS username, 'alice@example.com' AS email
)
INSERT INTO users (username, email)
SELECT username, email FROM new_users;

-- OVERRIDING（覆盖 IDENTITY 列）
INSERT INTO users (id, username, email)
OVERRIDING SYSTEM VALUE
VALUES (100, 'alice', 'alice@example.com');

-- 注意事项：
-- 支持 RETURNING 子句（比 MySQL 更方便获取插入后的值）
-- GaussDB 分布式版本的插入会根据 DISTRIBUTE BY 路由到对应 DN
-- MOT 内存表的插入性能更高
-- 列存储表的插入建议使用批量方式
