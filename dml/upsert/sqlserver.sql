-- SQL Server: UPSERT
--
-- 参考资料:
--   [1] SQL Server T-SQL - MERGE
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/merge-transact-sql
--   [2] SQL Server T-SQL - INSERT
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/insert-transact-sql

-- MERGE（2008+，SQL 标准语法）
MERGE INTO users AS t
USING (VALUES ('alice', 'alice@example.com', 25)) AS s(username, email, age)
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET t.email = s.email, t.age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);
-- 注意：MERGE 语句必须以分号结尾

-- MERGE 支持 OUTPUT（返回操作结果）
MERGE INTO users AS t
USING (VALUES ('alice', 'alice@example.com', 25)) AS s(username, email, age)
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET t.email = s.email, t.age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age)
OUTPUT $action, inserted.id, inserted.username;

-- 传统方式：IF EXISTS（所有版本）
IF EXISTS (SELECT 1 FROM users WHERE username = 'alice')
    UPDATE users SET email = 'alice@example.com', age = 25 WHERE username = 'alice';
ELSE
    INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- 并发安全方式：带锁提示
BEGIN TRAN;
    UPDATE users WITH (UPDLOCK, SERIALIZABLE)
    SET email = 'alice@example.com', age = 25
    WHERE username = 'alice';

    IF @@ROWCOUNT = 0
    BEGIN
        INSERT INTO users (username, email, age)
        VALUES ('alice', 'alice@example.com', 25);
    END
COMMIT;
