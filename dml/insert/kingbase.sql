-- KingbaseES (人大金仓): INSERT
-- PostgreSQL compatible syntax.
--
-- 参考资料:
--   [1] KingbaseES SQL Reference
--       https://help.kingbase.com.cn/v8/index.html
--   [2] KingbaseES Documentation
--       https://help.kingbase.com.cn/v8/index.html

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
-- 语法与 PostgreSQL 完全兼容
-- 支持 RETURNING 子句
-- 支持 CTE + INSERT
-- Oracle 兼容模式下也支持 INSERT ALL 语法
