-- SQL Standard: 数据去重策略（Deduplication）
--
-- 参考资料:
--   [1] ISO/IEC 9075 SQL Standard - DISTINCT / GROUP BY
--       https://www.iso.org/standard/76583.html
--   [2] SQL Standard - Window Functions
--       https://modern-sql.com/feature/over

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   users(user_id INT, email VARCHAR(255), username VARCHAR(64), created_at TIMESTAMP)
--   events(event_id INT, user_id INT, event_type VARCHAR(50), event_time TIMESTAMP, payload VARCHAR)

-- ============================================================
-- 1. 查找重复数据（GROUP BY HAVING）
-- ============================================================

-- 查找重复的 email
SELECT email, COUNT(*) AS cnt
FROM users
GROUP BY email
HAVING COUNT(*) > 1;

-- 查找重复并显示具体行
SELECT u.*
FROM users u
JOIN (
    SELECT email
    FROM users
    GROUP BY email
    HAVING COUNT(*) > 1
) dup ON u.email = dup.email
ORDER BY u.email, u.created_at;

-- 查找多列组合重复
SELECT username, email, COUNT(*) AS cnt
FROM users
GROUP BY username, email
HAVING COUNT(*) > 1;

-- ============================================================
-- 2. 保留每组一行（ROW_NUMBER 方式）
-- ============================================================

-- 保留每个 email 最新的一条记录
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

-- 保留每个 email 最早的一条记录
SELECT *
FROM (
    SELECT user_id, email, username, created_at,
           ROW_NUMBER() OVER (
               PARTITION BY email
               ORDER BY created_at ASC
           ) AS rn
    FROM users
) ranked
WHERE rn = 1;

-- 保留 user_id 最大的（最后插入的）
SELECT *
FROM (
    SELECT user_id, email, username, created_at,
           ROW_NUMBER() OVER (
               PARTITION BY email
               ORDER BY user_id DESC
           ) AS rn
    FROM users
) ranked
WHERE rn = 1;

-- ============================================================
-- 3. 删除重复数据（保留最新/最早）
-- ============================================================

-- 删除重复，保留最新记录
DELETE FROM users
WHERE user_id NOT IN (
    SELECT keep_id FROM (
        SELECT MAX(user_id) AS keep_id
        FROM users
        GROUP BY email
    ) keepers
);

-- 使用 CTE + ROW_NUMBER 删除（标准 SQL 不直接支持 DELETE + CTE，
-- 但许多数据库支持此扩展语法）
-- 各数据库的具体语法见对应方言文件

-- ============================================================
-- 4. DISTINCT vs GROUP BY
-- ============================================================

-- DISTINCT：去除完全相同的行
SELECT DISTINCT email FROM users;

-- SELECT DISTINCT 多列：所有列组合唯一
SELECT DISTINCT email, username FROM users;

-- GROUP BY：按列分组，可配合聚合函数
SELECT email, COUNT(*) AS cnt, MAX(created_at) AS latest
FROM users
GROUP BY email;

-- 注意：
-- DISTINCT 是对整行去重（所有 SELECT 列的组合）
-- GROUP BY 可以配合聚合函数获取分组信息
-- 仅做去重时，两者等价：
--   SELECT DISTINCT email FROM users;
--   等价于
--   SELECT email FROM users GROUP BY email;

-- ============================================================
-- 5. 关联子查询去重（无窗口函数场景）
-- ============================================================

-- 保留每个 email 最新的记录
SELECT u.*
FROM users u
WHERE u.created_at = (
    SELECT MAX(u2.created_at)
    FROM users u2
    WHERE u2.email = u.email
);

-- 保留每个 email 的 user_id 最大的记录
SELECT u.*
FROM users u
WHERE u.user_id = (
    SELECT MAX(u2.user_id)
    FROM users u2
    WHERE u2.email = u.email
);

-- ============================================================
-- 6. 去重后插入新表
-- ============================================================

-- 将去重结果插入新表
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

-- ROW_NUMBER 方式最灵活（可以指定保留哪条）
-- 关联子查询方式 O(n^2)，仅适合小数据集
-- DELETE 去重前建议先备份
-- DISTINCT 和 GROUP BY 在大数据集上都可能需要排序/哈希
-- 建议在去重键上建索引
