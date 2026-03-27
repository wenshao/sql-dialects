-- Snowflake: DELETE
--
-- 参考资料:
--   [1] Snowflake SQL Reference - DELETE
--       https://docs.snowflake.com/en/sql-reference/sql/delete
--   [2] Snowflake SQL Reference - TRUNCATE TABLE
--       https://docs.snowflake.com/en/sql-reference/sql/truncate-table

-- 基本删除
DELETE FROM users WHERE username = 'alice';

-- 子查询删除
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- USING 子句（多表删除，类似 FROM）
DELETE FROM users
USING blacklist
WHERE users.email = blacklist.email;

-- 多表 USING
DELETE FROM users
USING blacklist b, suspension s
WHERE users.email = b.email OR users.id = s.user_id;

-- EXISTS 子查询
DELETE FROM users u
WHERE EXISTS (SELECT 1 FROM blacklist b WHERE b.email = u.email);

-- CTE + DELETE
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);

-- 删除所有行
DELETE FROM users;

-- TRUNCATE（更快，重置表，不可回滚但支持 Time Travel）
TRUNCATE TABLE users;

-- 删除后可通过 Time Travel 恢复
-- SELECT * FROM users AT(OFFSET => -60*5);  -- 查看 5 分钟前的数据
-- 或使用 UNDROP TABLE 恢复整个表

-- CASE 条件删除
DELETE FROM users
WHERE CASE
    WHEN status = 0 AND last_login < '2023-01-01' THEN TRUE
    WHEN status = -1 THEN TRUE
    ELSE FALSE
END;
