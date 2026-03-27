-- SQLite: 数据去重策略（Deduplication）
--
-- 参考资料:
--   [1] SQLite Documentation - Window Functions
--       https://www.sqlite.org/windowfunctions.html
--   [2] SQLite Documentation - DELETE
--       https://www.sqlite.org/lang_delete.html

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   users(user_id INTEGER PRIMARY KEY, email TEXT, username TEXT, created_at TEXT)

-- ============================================================
-- 1. 查找重复数据
-- ============================================================

SELECT email, COUNT(*) AS cnt
FROM users
GROUP BY email
HAVING COUNT(*) > 1;

-- ============================================================
-- 2. 保留每组一行（ROW_NUMBER，SQLite 3.25.0+）
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

-- 方法一：使用 rowid（SQLite 物理行 ID）
DELETE FROM users
WHERE rowid NOT IN (
    SELECT MIN(rowid)
    FROM users
    GROUP BY email
);

-- 方法二：保留最新记录
DELETE FROM users
WHERE rowid NOT IN (
    SELECT rowid FROM (
        SELECT rowid,
               ROW_NUMBER() OVER (
                   PARTITION BY email
                   ORDER BY created_at DESC
               ) AS rn
        FROM users
    ) WHERE rn = 1
);

-- 方法三：无窗口函数（SQLite 3.24 及以下）
DELETE FROM users
WHERE user_id NOT IN (
    SELECT MAX(user_id)
    FROM users
    GROUP BY email
);

-- ============================================================
-- 4. 防止重复（INSERT OR 语法）
-- ============================================================

-- INSERT OR IGNORE
INSERT OR IGNORE INTO users (email, username) VALUES ('a@b.com', 'alice');

-- INSERT OR REPLACE（等价于 REPLACE INTO）
INSERT OR REPLACE INTO users (email, username, created_at)
VALUES ('a@b.com', 'alice', datetime('now'));

-- UPSERT（SQLite 3.24+）
INSERT INTO users (email, username, created_at)
VALUES ('a@b.com', 'alice', datetime('now'))
ON CONFLICT(email) DO UPDATE SET
    username = excluded.username,
    created_at = excluded.created_at;

-- ============================================================
-- 5. DISTINCT vs GROUP BY
-- ============================================================

SELECT DISTINCT email FROM users;
SELECT email FROM users GROUP BY email;

-- ============================================================
-- 6. 关联子查询去重（无窗口函数场景）
-- ============================================================

SELECT u.*
FROM users u
WHERE u.user_id = (
    SELECT MAX(u2.user_id)
    FROM users u2
    WHERE u2.email = u.email
);

-- ============================================================
-- 7. 性能考量
-- ============================================================

CREATE INDEX idx_users_email ON users (email);

-- rowid 方式在 SQLite 中最高效
-- INSERT OR IGNORE / ON CONFLICT 预防重复
-- 窗口函数需要 SQLite 3.25.0+
-- UPSERT (ON CONFLICT) 需要 SQLite 3.24+
-- SQLite 适合小数据集的去重
