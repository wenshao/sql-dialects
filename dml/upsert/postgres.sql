-- PostgreSQL: UPSERT
--
-- 参考资料:
--   [1] PostgreSQL Documentation - INSERT ... ON CONFLICT
--       https://www.postgresql.org/docs/current/sql-insert.html
--   [2] PostgreSQL Documentation - MERGE (v15+)
--       https://www.postgresql.org/docs/current/sql-merge.html

-- ON CONFLICT (9.5+)
-- 需要指定冲突目标（列名或约束名）
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

-- 指定约束名
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON CONFLICT ON CONSTRAINT uk_username
DO UPDATE SET
    email = EXCLUDED.email,
    age = EXCLUDED.age;

-- 带 WHERE 条件的 UPSERT（只在满足条件时才更新）
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON CONFLICT (username)
DO UPDATE SET
    email = EXCLUDED.email,
    age = EXCLUDED.age
WHERE users.age < EXCLUDED.age;

-- 带 RETURNING（返回操作后的行）
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON CONFLICT (username)
DO UPDATE SET email = EXCLUDED.email
RETURNING id, username, email;

-- 15+: MERGE 语法（与 SQL 标准一致）
MERGE INTO users AS t
USING (VALUES ('alice', 'alice@example.com', 25)) AS s(username, email, age)
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);
