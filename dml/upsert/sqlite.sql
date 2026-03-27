-- SQLite: UPSERT
--
-- 参考资料:
--   [1] SQLite Documentation - UPSERT
--       https://www.sqlite.org/lang_upsert.html
--   [2] SQLite Documentation - INSERT
--       https://www.sqlite.org/lang_insert.html

-- ON CONFLICT (3.24.0+, 2018-06-04)
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON CONFLICT (username)
DO UPDATE SET
    email = EXCLUDED.email,
    age = EXCLUDED.age;

-- 冲突时什么都不做
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON CONFLICT (username) DO NOTHING;

-- INSERT OR REPLACE（旧语法，所有版本支持）
-- 注意：冲突时先 DELETE 再 INSERT，未指定的列会被重置为默认值
INSERT OR REPLACE INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25);

-- INSERT OR IGNORE
INSERT OR IGNORE INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25);
