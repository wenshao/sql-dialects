-- Apache Derby: 数据去重策略（Deduplication）
--
-- 参考资料:
--   [1] Apache Derby Documentation
--       https://db.apache.org/derby/docs/10.15/ref/

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   users(user_id INT, email VARCHAR(255), username VARCHAR(64), created_at DATE)

-- ============================================================
-- 1. 查找重复数据
-- ============================================================

SELECT email, COUNT(*) AS cnt
FROM users
GROUP BY email
HAVING COUNT(*) > 1;

-- ============================================================
-- 2. 保留每组一行（关联子查询方式，Derby 窗口函数有限）
-- ============================================================

SELECT u.*
FROM users u
WHERE u.user_id = (
    SELECT MAX(u2.user_id)
    FROM users u2
    WHERE u2.email = u.email
);

-- ============================================================
-- 3. 删除重复数据
-- ============================================================

DELETE FROM users
WHERE user_id NOT IN (
    SELECT MAX(user_id)
    FROM users
    GROUP BY email
);

-- ============================================================
-- 4. DISTINCT vs GROUP BY
-- ============================================================

SELECT DISTINCT email FROM users;
SELECT email FROM users GROUP BY email;

-- ============================================================
-- 5. 性能考量
-- ============================================================

CREATE INDEX idx_users_email ON users (email);

-- Derby 仅支持 ROW_NUMBER()，不支持 SUM/AVG OVER
-- 去重推荐使用关联子查询或 GROUP BY + MAX
-- Derby 是嵌入式数据库，适合小数据集
