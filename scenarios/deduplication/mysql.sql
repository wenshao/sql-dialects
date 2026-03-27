-- MySQL: 数据去重策略（Deduplication）
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - DELETE
--       https://dev.mysql.com/doc/refman/8.0/en/delete.html
--   [2] MySQL 8.0 Reference Manual - Window Functions
--       https://dev.mysql.com/doc/refman/8.0/en/window-functions.html
--   [3] MySQL 8.0 Reference Manual - INSERT ... ON DUPLICATE KEY
--       https://dev.mysql.com/doc/refman/8.0/en/insert-on-duplicate.html

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   users(user_id INT AUTO_INCREMENT PRIMARY KEY, email VARCHAR(255), username VARCHAR(64), created_at DATETIME)

-- ============================================================
-- 1. 查找重复数据
-- ============================================================

SELECT email, COUNT(*) AS cnt
FROM users
GROUP BY email
HAVING COUNT(*) > 1;

SELECT u.*
FROM users u
JOIN (
    SELECT email FROM users GROUP BY email HAVING COUNT(*) > 1
) dup ON u.email = dup.email
ORDER BY u.email, u.created_at;

-- ============================================================
-- 2. 保留每组一行（ROW_NUMBER，MySQL 8.0+）
-- ============================================================

SELECT *
FROM (
    SELECT user_id, email, username, created_at,
           ROW_NUMBER() OVER (
               PARTITION BY email
               ORDER BY created_at DESC
           ) AS rn
    FROM users
) ranked
WHERE rn = 1;

-- ============================================================
-- 3. 删除重复数据
-- ============================================================

-- 方法一：保留 user_id 最大的（MySQL 不能在子查询中引用被删除的表，需要包一层）
DELETE FROM users
WHERE user_id NOT IN (
    SELECT keep_id FROM (
        SELECT MAX(user_id) AS keep_id
        FROM users
        GROUP BY email
    ) tmp
);

-- 方法二：DELETE JOIN（MySQL 特有语法）
DELETE u1
FROM users u1
JOIN users u2
  ON u1.email = u2.email
  AND u1.user_id < u2.user_id;

-- 方法三：CTE + ROW_NUMBER（MySQL 8.0+）
WITH duplicates AS (
    SELECT user_id,
           ROW_NUMBER() OVER (
               PARTITION BY email
               ORDER BY created_at DESC
           ) AS rn
    FROM users
)
DELETE FROM users
WHERE user_id IN (
    SELECT user_id FROM duplicates WHERE rn > 1
);

-- 方法四：MySQL 5.7（无窗口函数）
DELETE u1
FROM users u1
LEFT JOIN (
    SELECT MIN(user_id) AS keep_id
    FROM users
    GROUP BY email
) u2 ON u1.user_id = u2.keep_id
WHERE u2.keep_id IS NULL;

-- ============================================================
-- 4. 防止重复插入
-- ============================================================

-- INSERT IGNORE（静默忽略重复）
INSERT IGNORE INTO users (email, username) VALUES ('a@b.com', 'alice');

-- ON DUPLICATE KEY UPDATE（更新已有记录）
INSERT INTO users (email, username, created_at)
VALUES ('a@b.com', 'alice', NOW())
ON DUPLICATE KEY UPDATE
    username = VALUES(username),
    created_at = VALUES(created_at);

-- REPLACE INTO（删除旧记录再插入新记录）
REPLACE INTO users (email, username, created_at)
VALUES ('a@b.com', 'alice', NOW());

-- ============================================================
-- 5. DISTINCT vs GROUP BY
-- ============================================================

SELECT DISTINCT email FROM users;
SELECT email FROM users GROUP BY email;

-- GROUP BY + 聚合
SELECT email, COUNT(*) AS cnt, MAX(created_at) AS latest
FROM users
GROUP BY email;

-- ============================================================
-- 6. 去重后创建新表
-- ============================================================

CREATE TABLE users_clean AS
SELECT *
FROM (
    SELECT user_id, email, username, created_at,
           ROW_NUMBER() OVER (
               PARTITION BY email
               ORDER BY created_at DESC
           ) AS rn
    FROM users
) ranked
WHERE rn = 1;

-- ============================================================
-- 7. 性能考量
-- ============================================================

CREATE INDEX idx_users_email ON users (email);

-- DELETE JOIN 是 MySQL 最高效的去重删除方式
-- MySQL 8.0+ 推荐 CTE + ROW_NUMBER
-- INSERT IGNORE / ON DUPLICATE KEY 预防重复
-- REPLACE INTO 会删除旧行再插入，可能导致自增 ID 变化
-- 大表去重建议分批 DELETE（LIMIT + 循环）
