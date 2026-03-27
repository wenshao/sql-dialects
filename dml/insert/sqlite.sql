-- SQLite: INSERT
--
-- 参考资料:
--   [1] SQLite Documentation - INSERT
--       https://www.sqlite.org/lang_insert.html
--   [2] SQLite Documentation - REPLACE
--       https://www.sqlite.org/lang_replace.html

-- 单行插入
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- 多行插入（3.7.11+）
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);

-- 从查询结果插入
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;

-- INSERT OR REPLACE（冲突时替换整行）
INSERT OR REPLACE INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- INSERT OR IGNORE（冲突时跳过）
INSERT OR IGNORE INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- INSERT OR ABORT / ROLLBACK / FAIL
INSERT OR ABORT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- 指定默认值
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', NULL);
INSERT INTO users DEFAULT VALUES;

-- 3.35.0+: RETURNING
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
RETURNING id, username;

-- 获取自增 ID
INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com');
SELECT last_insert_rowid();
