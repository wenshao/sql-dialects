-- SQL Server: INSERT
--
-- 参考资料:
--   [1] SQL Server T-SQL - INSERT
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/insert-transact-sql
--   [2] SQL Server T-SQL - BULK INSERT
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/bulk-insert-transact-sql

-- 单行插入
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- 多行插入（2008+，最多 1000 行）
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);

-- 从查询结果插入
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;

-- OUTPUT（返回插入的行，类似 RETURNING）
INSERT INTO users (username, email, age)
OUTPUT inserted.id, inserted.username
VALUES ('alice', 'alice@example.com', 25);

-- OUTPUT INTO（结果插入到另一个表）
DECLARE @ids TABLE (id BIGINT);
INSERT INTO users (username, email, age)
OUTPUT inserted.id INTO @ids
VALUES ('alice', 'alice@example.com', 25);

-- 获取自增 ID
INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com');
SELECT SCOPE_IDENTITY();     -- 当前作用域（推荐）
SELECT @@IDENTITY;           -- 全局（可能受触发器影响）
SELECT IDENT_CURRENT('users'); -- 指定表（可能受其他会话影响）

-- 插入 IDENTITY 列
SET IDENTITY_INSERT users ON;
INSERT INTO users (id, username, email) VALUES (100, 'alice', 'alice@example.com');
SET IDENTITY_INSERT users OFF;

-- 指定默认值
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', DEFAULT);
INSERT INTO users DEFAULT VALUES;

-- SELECT INTO（创建新表并插入）
SELECT username, email, age
INTO users_backup
FROM users
WHERE age > 60;

-- TOP（只插入前 N 行）
INSERT TOP (10) INTO users_archive (username, email)
SELECT username, email FROM users ORDER BY created_at;
