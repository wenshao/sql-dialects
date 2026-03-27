-- SQL Server: Views
--
-- 参考资料:
--   [1] Microsoft Documentation - CREATE VIEW
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/create-view-transact-sql
--   [2] Microsoft Documentation - CREATE INDEXED VIEW
--       https://learn.microsoft.com/en-us/sql/relational-databases/views/create-indexed-views
--   [3] Microsoft Documentation - Updatable Views
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/create-view-transact-sql#updatable-views

-- ============================================
-- 基本视图
-- ============================================
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- CREATE OR ALTER VIEW（SQL Server 2016 SP1+）
CREATE OR ALTER VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- 带 SCHEMABINDING（绑定到基表结构）
CREATE VIEW dbo.active_users
WITH SCHEMABINDING                          -- 防止修改/删除基表结构
AS
SELECT id, username, email, created_at
FROM dbo.users
WHERE age >= 18;

-- 加密视图定义
CREATE VIEW secret_view
WITH ENCRYPTION                             -- 加密视图定义
AS
SELECT id, username FROM users;

-- ============================================
-- 可更新视图 + WITH CHECK OPTION
-- ============================================
CREATE VIEW adult_users AS
SELECT id, username, email, age
FROM users
WHERE age >= 18
WITH CHECK OPTION;

-- 通过视图 DML
INSERT INTO adult_users (username, email, age) VALUES ('alice', 'alice@b.com', 25);
UPDATE adult_users SET email = 'new@b.com' WHERE id = 1;
DELETE FROM adult_users WHERE id = 1;

-- INSTEAD OF 触发器（使任意视图可更新）
CREATE VIEW order_detail AS
SELECT o.id, o.amount, u.username
FROM orders o JOIN users u ON o.user_id = u.id;

CREATE TRIGGER trg_order_detail_insert
ON order_detail INSTEAD OF INSERT
AS
BEGIN
    INSERT INTO orders (id, amount)
    SELECT id, amount FROM inserted;
END;

-- ============================================
-- 索引视图 (Indexed View / Materialized View)
-- SQL Server 版本的物化视图
-- ============================================
-- 1. 必须使用 WITH SCHEMABINDING
-- 2. 必须用两部分表名 (schema.table)
-- 3. 第一个索引必须是唯一聚集索引
CREATE VIEW dbo.mv_order_summary
WITH SCHEMABINDING
AS
SELECT
    user_id,
    COUNT_BIG(*) AS order_count,            -- 必须用 COUNT_BIG
    SUM(amount) AS total_amount
FROM dbo.orders
GROUP BY user_id;
GO

-- 创建唯一聚集索引（使视图"物化"）
CREATE UNIQUE CLUSTERED INDEX idx_mv_order
ON dbo.mv_order_summary (user_id);

-- 创建非聚集索引
CREATE NONCLUSTERED INDEX idx_mv_total
ON dbo.mv_order_summary (total_amount);

-- 索引视图特性：
-- 1. 数据自动维护（DML 时自动更新）
-- 2. Enterprise Edition：优化器自动使用（即使查询不引用视图）
-- 3. Standard Edition：需要 WITH (NOEXPAND) 提示

-- 使用 NOEXPAND 提示（Standard Edition）
SELECT * FROM mv_order_summary WITH (NOEXPAND) WHERE user_id = 42;

-- ============================================
-- 删除视图
-- ============================================
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;               -- SQL Server 2016+

-- 限制：
-- 索引视图有较多限制（不支持 OUTER JOIN、UNION、子查询等）
-- 索引视图必须使用 SCHEMABINDING
-- WITH CHECK OPTION 不适用于通过 INSTEAD OF 触发器修改的视图
-- 不支持 CREATE OR REPLACE（使用 CREATE OR ALTER，2016 SP1+）
