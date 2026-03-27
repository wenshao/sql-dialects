-- DamengDB (达梦): UPSERT
-- Oracle compatible syntax.
--
-- 参考资料:
--   [1] DamengDB SQL Reference
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html
--   [2] DamengDB System Admin Manual
--       https://eco.dameng.com/document/dm/zh-cn/pm/index.html

-- MERGE（主要方式）
MERGE INTO users t
USING (SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age FROM DUAL) s
ON (t.username = s.username)
WHEN MATCHED THEN
    UPDATE SET t.email = s.email, t.age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- MERGE 支持 DELETE 子句
MERGE INTO users t
USING (SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age FROM DUAL) s
ON (t.username = s.username)
WHEN MATCHED THEN
    UPDATE SET t.email = s.email, t.age = s.age
    DELETE WHERE t.age < 0
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- MERGE 带 WHERE 条件
MERGE INTO users t
USING (SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age FROM DUAL) s
ON (t.username = s.username)
WHEN MATCHED THEN
    UPDATE SET t.email = s.email, t.age = s.age
    WHERE t.age < s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- PL/SQL 方式
BEGIN
    INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);
EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        UPDATE users SET email = 'alice@example.com', age = 25 WHERE username = 'alice';
END;
/

-- 注意事项：
-- 语法与 Oracle 兼容
-- MERGE 是推荐的 UPSERT 方式
-- 支持 MERGE 的 DELETE 子句
-- DUAL 表可以使用
