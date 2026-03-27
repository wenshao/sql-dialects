-- Azure Synapse: 约束
--
-- 参考资料:
--   [1] Synapse SQL Features
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features
--   [2] Synapse T-SQL Differences
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features

-- Synapse 专用 SQL 池的约束支持非常有限
-- 只有 NOT NULL 被强制执行

-- ============================================================
-- NOT NULL（唯一强制执行的约束）
-- ============================================================

CREATE TABLE users (
    id       BIGINT NOT NULL IDENTITY(1, 1),
    username NVARCHAR(64) NOT NULL,
    email    NVARCHAR(255)                   -- 默认允许 NULL
)
WITH (DISTRIBUTION = HASH(id));

-- 修改 NOT NULL 需要通过 CTAS 重建表
CREATE TABLE users_new
WITH (DISTRIBUTION = HASH(id), CLUSTERED COLUMNSTORE INDEX)
AS
SELECT
    id,
    username,
    ISNULL(email, '') AS email               -- 填充 NULL 值
FROM users;
-- 然后 RENAME + DROP 原表

-- ============================================================
-- DEFAULT
-- ============================================================

CREATE TABLE users (
    id         BIGINT IDENTITY(1, 1),
    status     INT DEFAULT 1,
    created_at DATETIME2 DEFAULT GETDATE()
);

-- 注意：IDENTITY 列在 CTAS 操作中不保证原始值

-- ============================================================
-- PRIMARY KEY（不支持）
-- ============================================================
-- Synapse 专用池不支持 PRIMARY KEY 约束
-- 可以声明 NOT ENFORCED 的主键（仅信息性）

-- 某些版本支持信息性约束：
-- ALTER TABLE users ADD CONSTRAINT pk_users PRIMARY KEY NONCLUSTERED (id) NOT ENFORCED;
-- 但行为和支持范围因版本而异

-- ============================================================
-- UNIQUE（不支持）
-- ============================================================
-- Synapse 专用池不支持 UNIQUE 约束

-- ============================================================
-- FOREIGN KEY（不支持）
-- ============================================================
-- Synapse 专用池不支持 FOREIGN KEY 约束

-- ============================================================
-- CHECK（不支持）
-- ============================================================
-- Synapse 专用池不支持 CHECK 约束

-- ============================================================
-- 数据完整性保障策略
-- ============================================================

-- 方案一：在 ETL 管道中验证
-- 检查主键唯一性
SELECT id, COUNT(*) AS cnt
FROM users
GROUP BY id
HAVING COUNT(*) > 1;

-- 检查外键完整性
SELECT o.user_id
FROM orders o
LEFT JOIN users u ON o.user_id = u.id
WHERE u.id IS NULL;

-- 检查非空约束
SELECT COUNT(*) AS null_count
FROM users
WHERE username IS NULL;

-- 方案二：使用 CTAS 过滤无效数据
CREATE TABLE orders_clean
WITH (DISTRIBUTION = HASH(user_id), CLUSTERED COLUMNSTORE INDEX)
AS
SELECT o.*
FROM orders o
INNER JOIN users u ON o.user_id = u.id     -- 只保留有效外键
WHERE o.amount IS NOT NULL;                 -- 只保留非空金额

-- 方案三：使用视图层做验证
CREATE VIEW v_valid_orders AS
SELECT o.*
FROM orders o
WHERE EXISTS (SELECT 1 FROM users u WHERE u.id = o.user_id);

-- ============================================================
-- 统计信息（帮助查询优化器）
-- ============================================================

-- 手动创建统计信息（替代约束对优化器的提示）
CREATE STATISTICS stat_users_id ON users (id);
CREATE STATISTICS stat_orders_user_id ON orders (user_id);
CREATE STATISTICS stat_multi ON orders (order_date, user_id) WITH FULLSCAN;

UPDATE STATISTICS users;

-- 自动统计
-- 默认开启 AUTO_CREATE_STATISTICS

-- ============================================================
-- Serverless 池的约束
-- ============================================================
-- Serverless 池通过 OPENROWSET 查询外部数据
-- 不创建表，因此没有约束概念
-- 数据质量在数据湖层面保证

-- 注意：Synapse 专用池只有 NOT NULL 被强制执行
-- 注意：不支持 PRIMARY KEY、UNIQUE、FOREIGN KEY、CHECK
-- 注意：IDENTITY 列不保证值唯一（特别是 CTAS 操作后）
-- 注意：数据完整性需要在 ETL/ELT 管道中保证
-- 注意：正确创建统计信息对查询性能至关重要
-- 注意：CTAS 是执行数据清洗和验证的主要模式
