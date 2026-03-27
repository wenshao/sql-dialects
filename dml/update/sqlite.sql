-- SQLite: UPDATE
--
-- 参考资料:
--   [1] SQLite Documentation - UPDATE
--       https://www.sqlite.org/lang_update.html

-- 基本更新
UPDATE users SET age = 26 WHERE username = 'alice';

-- 多列更新
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- UPDATE OR REPLACE（冲突时替换）
UPDATE OR REPLACE users SET username = 'bob' WHERE username = 'alice';

-- UPDATE OR IGNORE（冲突时跳过）
UPDATE OR IGNORE users SET username = 'bob' WHERE username = 'alice';

-- 带 LIMIT / ORDER BY（需要 SQLITE_ENABLE_UPDATE_DELETE_LIMIT 编译选项）
UPDATE users SET status = 0 WHERE status = 1 ORDER BY created_at LIMIT 100;

-- 子查询更新
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;

-- CASE 表达式
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- 3.33.0+: FROM 子句
UPDATE users SET status = 1
FROM orders
WHERE users.id = orders.user_id AND orders.amount > 1000;

-- 3.35.0+: RETURNING
UPDATE users SET age = 26 WHERE username = 'alice' RETURNING id, username, age;
