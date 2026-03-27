-- Azure Synapse: UPSERT
--
-- 参考资料:
--   [1] Synapse SQL Features
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features
--   [2] Synapse T-SQL Differences
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features

-- Synapse 专用 SQL 池支持 MERGE（2022+ 新增）
-- 也可以使用 CTAS 模式或 UPDATE + INSERT 模式

-- ============================================================
-- 方式一: MERGE（推荐，2022+ 支持）
-- ============================================================

MERGE INTO users AS t
USING staging_users AS s
ON t.id = s.id
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age, updated_at = GETDATE()
WHEN NOT MATCHED THEN
    INSERT (id, username, email, age, created_at)
    VALUES (s.id, s.username, s.email, s.age, GETDATE());

-- MERGE 带条件
MERGE INTO users AS t
USING staging_users AS s
ON t.id = s.id
WHEN MATCHED AND s.status = 'delete' THEN
    DELETE
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (id, username, email, age) VALUES (s.id, s.username, s.email, s.age);

-- ============================================================
-- 方式二: CTAS 模式（大批量替换场景）
-- ============================================================

-- 加载新数据到暂存表
CREATE TABLE #staging
WITH (DISTRIBUTION = ROUND_ROBIN, HEAP)
AS SELECT * FROM external_source;

-- 使用 CTAS 合并
CREATE TABLE users_merged
WITH (DISTRIBUTION = HASH(id), CLUSTERED COLUMNSTORE INDEX)
AS
-- 已存在且需要更新的行（用暂存数据覆盖）
SELECT s.id, s.username, s.email, s.age, s.created_at, GETDATE() AS updated_at
FROM #staging s
INNER JOIN users u ON s.id = u.id
UNION ALL
-- 已存在但暂存中没有的行（保留原始数据）
SELECT u.id, u.username, u.email, u.age, u.created_at, u.updated_at
FROM users u
WHERE NOT EXISTS (SELECT 1 FROM #staging s WHERE s.id = u.id)
UNION ALL
-- 新行（暂存中有但表中没有）
SELECT s.id, s.username, s.email, s.age, s.created_at, GETDATE()
FROM #staging s
WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.id = s.id);

RENAME OBJECT users TO users_old;
RENAME OBJECT users_merged TO users;
DROP TABLE users_old;

-- ============================================================
-- 方式二: UPDATE + INSERT（适合小批量）
-- ============================================================

-- 先更新已存在的行
UPDATE u
SET u.email = s.email, u.age = s.age, u.updated_at = GETDATE()
FROM users u
INNER JOIN staging_users s ON u.username = s.username;

-- 再插入新行
INSERT INTO users (username, email, age, created_at)
SELECT s.username, s.email, s.age, GETDATE()
FROM staging_users s
WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.username = s.username);

-- ============================================================
-- 方式三: DELETE + INSERT（适合中等批量）
-- ============================================================

BEGIN TRANSACTION;

DELETE FROM users
WHERE id IN (SELECT id FROM staging_users);

INSERT INTO users (id, username, email, age)
SELECT id, username, email, age FROM staging_users;

COMMIT;

-- ============================================================
-- 方式四: 存储过程封装
-- ============================================================

CREATE PROCEDURE upsert_users
AS
BEGIN
    -- 1. 更新已存在的行
    UPDATE u
    SET u.email = s.email, u.age = s.age
    FROM users u
    INNER JOIN staging_users s ON u.id = s.id;

    -- 2. 插入新行
    INSERT INTO users (id, username, email, age)
    SELECT s.id, s.username, s.email, s.age
    FROM staging_users s
    LEFT JOIN users u ON s.id = u.id
    WHERE u.id IS NULL;
END;

EXEC upsert_users;

-- ============================================================
-- Serverless 池中的 MERGE
-- ============================================================
-- Serverless 池不支持 DML 操作
-- 数据更新需要在数据湖层面处理（如 Delta Lake on Synapse）

-- 注意：Synapse 专用池从 2022 年起支持 MERGE 语句
-- 注意：MERGE 是推荐的 UPSERT 方式；CTAS 模式适合全量刷新
-- 注意：UPDATE + INSERT 适合小批量但需要注意并发
-- 注意：暂存表用堆表 + ROUND_ROBIN 分布（加载最快）
-- 注意：合并后需要 RENAME + DROP 替换原表
-- 注意：IDENTITY 列在 CTAS 中可能不保留原始值
