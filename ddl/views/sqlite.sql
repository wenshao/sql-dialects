-- SQLite: 视图（Views）
--
-- 参考资料:
--   [1] SQLite Documentation - CREATE VIEW
--       https://www.sqlite.org/lang_createview.html
--   [2] SQLite Documentation - INSTEAD OF Triggers
--       https://www.sqlite.org/lang_createtrigger.html

-- ============================================================
-- 1. 基本语法
-- ============================================================

CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- IF NOT EXISTS
CREATE VIEW IF NOT EXISTS active_users AS
SELECT id, username, email FROM users WHERE age >= 18;

-- 临时视图（仅在当前连接中可见）
CREATE TEMPORARY VIEW temp_active AS
SELECT id, username FROM users WHERE status = 1;

-- 删除视图
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;

-- ============================================================
-- 2. 不支持 CREATE OR REPLACE VIEW（设计分析）
-- ============================================================

-- SQLite 不支持 CREATE OR REPLACE VIEW，必须 DROP + CREATE。
-- 原因: 视图的 SQL 文本存储在 sqlite_master 表中，
-- "REPLACE" 需要原子地修改 sqlite_master 中的 SQL 文本。
-- SQLite 选择不实现这个功能（保持实现简单）。
--
-- 安全做法:
DROP VIEW IF EXISTS active_users;
CREATE VIEW active_users AS
SELECT id, username, email FROM users WHERE age >= 18;
--
-- 对比:
--   MySQL:      CREATE OR REPLACE VIEW（支持）
--   PostgreSQL: CREATE OR REPLACE VIEW（支持）
--   ClickHouse: CREATE OR REPLACE VIEW（支持）
--   BigQuery:   CREATE OR REPLACE VIEW（支持）
--   只有 SQLite 不支持，这是其极简设计的代价之一。

-- ============================================================
-- 3. 可更新视图: INSTEAD OF 触发器（对引擎开发者）
-- ============================================================

-- SQLite 的视图不可直接更新（不能对视图 INSERT/UPDATE/DELETE）。
-- 但可以通过 INSTEAD OF 触发器使视图"看起来"可更新。
-- 这是 SQLite 独特的设计: 用触发器替代内置的视图更新逻辑。

CREATE VIEW order_detail AS
SELECT o.id, o.amount, o.user_id, u.username
FROM orders o JOIN users u ON o.user_id = u.id;

-- INSERT 触发器
CREATE TRIGGER trg_order_detail_insert
INSTEAD OF INSERT ON order_detail
BEGIN
    INSERT INTO orders (id, amount, user_id) VALUES (NEW.id, NEW.amount, NEW.user_id);
END;

-- UPDATE 触发器
CREATE TRIGGER trg_order_detail_update
INSTEAD OF UPDATE ON order_detail
BEGIN
    UPDATE orders SET amount = NEW.amount WHERE id = OLD.id;
END;

-- DELETE 触发器
CREATE TRIGGER trg_order_detail_delete
INSTEAD OF DELETE ON order_detail
BEGIN
    DELETE FROM orders WHERE id = OLD.id;
END;

-- 设计 trade-off:
--   优点: 开发者完全控制视图的写入逻辑（比自动可更新视图更灵活）
--   缺点: 样板代码多，每个视图需要 3 个触发器
--   优点: 不需要引擎判断哪些视图"可以安全更新"（复杂的规则）
--
-- 对比:
--   MySQL:      简单视图自动可更新（单表、无 GROUP BY/DISTINCT/UNION）
--   PostgreSQL: 简单视图自动可更新 + RULE 或 INSTEAD OF TRIGGER
--   SQL Server: INSTEAD OF TRIGGER（与 SQLite 最接近）
--   BigQuery:   视图不可更新（无替代方案）
--   ClickHouse: 视图不可更新

-- ============================================================
-- 4. 没有物化视图（为什么以及替代方案）
-- ============================================================

-- SQLite 不支持 CREATE MATERIALIZED VIEW。
-- 原因:
-- (a) 物化视图需要后台进程刷新数据 → SQLite 是嵌入式，没有后台进程
-- (b) 物化视图需要跟踪基表变更 → 增加写入开销
-- (c) 嵌入式场景数据量通常不大 → 普通视图的实时计算已经够快

-- 手动模拟物化视图:
CREATE TABLE mv_order_summary (
    user_id      INTEGER PRIMARY KEY,
    order_count  INTEGER,
    total_amount REAL
);

-- 刷新（应用层定时调用）
DELETE FROM mv_order_summary;
INSERT INTO mv_order_summary
SELECT user_id, COUNT(*), SUM(amount)
FROM orders GROUP BY user_id;

-- 或者使用触发器实现增量更新:
CREATE TRIGGER trg_orders_insert_mv
AFTER INSERT ON orders
BEGIN
    INSERT INTO mv_order_summary (user_id, order_count, total_amount)
    VALUES (NEW.user_id, 1, NEW.amount)
    ON CONFLICT(user_id) DO UPDATE SET
        order_count = order_count + 1,
        total_amount = total_amount + NEW.amount;
END;

-- 设计对比:
--   PostgreSQL: CREATE MATERIALIZED VIEW + REFRESH MATERIALIZED VIEW
--   BigQuery:   CREATE MATERIALIZED VIEW（自动刷新）
--   ClickHouse: CREATE MATERIALIZED VIEW（INSERT 时增量更新，最独特）
--   SQLite:     手动表 + 触发器增量更新（最原始但完全可控）

-- ============================================================
-- 5. 视图存储与性能
-- ============================================================

-- 视图定义存储在 sqlite_master 中:
-- SELECT sql FROM sqlite_master WHERE type = 'view' AND name = 'active_users';

-- 视图是查询替换（query rewriting），不缓存结果。
-- 每次 SELECT * FROM active_users 都会展开为底层 SQL 执行。
-- 嵌套视图（视图引用视图）会层层展开，可能导致复杂的执行计划。

-- 不支持 WITH CHECK OPTION:
-- SQLite 不强制视图的 WHERE 条件在 INSERT/UPDATE 时生效。
-- 通过 INSTEAD OF 触发器可以手动实现类似检查。

-- ============================================================
-- 6. 对比与引擎开发者启示
-- ============================================================
-- SQLite 视图的设计特征:
--   (1) 只读视图 + INSTEAD OF 触发器 → 简单实现，灵活控制
--   (2) 无物化视图 → 嵌入式无后台进程，用触发器增量更新替代
--   (3) 无 CREATE OR REPLACE → schema 以 SQL 文本存储的限制
--   (4) 临时视图 → 连接级可见性，适合动态查询
--
-- 对引擎开发者的启示:
--   视图的可更新性判断是引擎中最复杂的规则之一。
--   SQLite 的做法（完全不自动判断，交给 INSTEAD OF 触发器）
--   对嵌入式引擎是合理的: 减少引擎复杂度，用户按需实现。
