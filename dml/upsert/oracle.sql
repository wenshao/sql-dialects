-- Oracle: UPSERT
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - MERGE
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/MERGE.html
--   [2] Oracle SQL Language Reference - INSERT
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/INSERT.html

-- MERGE（9i+，最常用的方式）
MERGE INTO users t
USING (SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age FROM dual) s
ON (t.username = s.username)
WHEN MATCHED THEN
    UPDATE SET t.email = s.email, t.age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- 10g+: MERGE 支持 DELETE 子句（在 MATCHED 更新后还能删除）
MERGE INTO users t
USING (SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age FROM dual) s
ON (t.username = s.username)
WHEN MATCHED THEN
    UPDATE SET t.email = s.email, t.age = s.age
    DELETE WHERE t.age < 0
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- 10g+: MERGE 支持 WHERE 条件
MERGE INTO users t
USING (SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age FROM dual) s
ON (t.username = s.username)
WHEN MATCHED THEN
    UPDATE SET t.email = s.email, t.age = s.age
    WHERE t.age < s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- 传统方式：PL/SQL 块（所有版本）
BEGIN
    INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);
EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        UPDATE users SET email = 'alice@example.com', age = 25 WHERE username = 'alice';
END;
/
