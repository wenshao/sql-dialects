-- SQLite: 表分区策略
--
-- 参考资料:
--   [1] SQLite Documentation - ATTACH DATABASE
--       https://www.sqlite.org/lang_attach.html
--   [2] SQLite Best Practices - Large Databases
--       https://www.sqlite.org/np1queryprob.html

-- ============================================================
-- 1. SQLite 不支持表分区（为什么）
-- ============================================================

-- SQLite 没有 PARTITION BY 语法。原因:
--
-- (a) 单文件架构: 分区需要将数据分散到不同的物理位置。
--     SQLite 的整个数据库是一个文件，没有"不同物理位置"的概念。
--
-- (b) 无查询优化器的分区裁剪:
--     分区的核心价值是 partition pruning（跳过不相关分区）。
--     SQLite 的查询优化器为单文件设计，没有分区裁剪逻辑。
--
-- (c) 嵌入式定位: 分区是大规模数据管理的特性。
--     SQLite 的典型数据量是 MB-GB 级别，索引已经足够。
--
-- 对比:
--   MySQL:      PARTITION BY RANGE/LIST/HASH/KEY
--   PostgreSQL: PARTITION BY RANGE/LIST/HASH（10+）
--   ClickHouse: PARTITION BY（任意表达式，核心特性）
--   BigQuery:   PARTITION BY（DATE/TIMESTAMP/INT64）

-- ============================================================
-- 2. 替代方案 1: 手动分表（应用层分区）
-- ============================================================

-- 按时间创建多个表
CREATE TABLE orders_2023 (
    id INTEGER PRIMARY KEY, user_id INTEGER,
    amount REAL, order_date TEXT
);
CREATE TABLE orders_2024 (
    id INTEGER PRIMARY KEY, user_id INTEGER,
    amount REAL, order_date TEXT
);
CREATE TABLE orders_2025 (
    id INTEGER PRIMARY KEY, user_id INTEGER,
    amount REAL, order_date TEXT
);

-- 插入时路由到正确的表（应用层逻辑）
-- if year == 2024: conn.execute("INSERT INTO orders_2024 ...")

-- 查询时 UNION ALL
SELECT * FROM orders_2024 WHERE order_date >= '2024-06-01'
UNION ALL
SELECT * FROM orders_2025;

-- ============================================================
-- 3. 替代方案 2: 视图统一分表
-- ============================================================

CREATE VIEW orders_all AS
SELECT * FROM orders_2023
UNION ALL
SELECT * FROM orders_2024
UNION ALL
SELECT * FROM orders_2025;

-- 通过视图透明查询:
SELECT * FROM orders_all WHERE order_date >= '2024-01-01';
-- 注意: SQLite 不会做分区裁剪! 上面的查询仍然扫描所有 3 个表。

-- 配合 INSTEAD OF 触发器使视图可写:
-- CREATE TRIGGER trg_orders_all_insert
-- INSTEAD OF INSERT ON orders_all
-- BEGIN
--     INSERT INTO orders_2024 ... (根据 NEW.order_date 路由)
-- END;

-- ============================================================
-- 4. 替代方案 3: ATTACH DATABASE（文件级分区）
-- ============================================================

-- 每个"分区"是独立的数据库文件
ATTACH DATABASE 'orders_2024.db' AS db2024;
ATTACH DATABASE 'orders_2025.db' AS db2025;

-- 跨文件查询
SELECT * FROM db2024.orders WHERE order_date >= '2024-06-01'
UNION ALL
SELECT * FROM db2025.orders;

-- 文件级分区的优势:
--   (a) 每个文件可以独立备份/迁移/删除
--   (b) 删除旧分区 = 删除文件（rm orders_2020.db），比 DELETE 快得多
--   (c) 每个文件可以独立 VACUUM
--
-- 文件级分区的限制:
--   (a) 所有 ATTACH 的文件共享同一个写锁
--   (b) 最多 ATTACH 10 个数据库（SQLITE_MAX_ATTACHED = 10，可编译时调整）
--   (c) 跨文件事务使用两阶段提交（性能略有开销）

-- ============================================================
-- 5. 替代方案 4: 索引替代分区裁剪
-- ============================================================

-- 对于不分表的场景，复合索引可以实现类似分区裁剪的效果:
CREATE INDEX idx_orders_date ON orders(order_date);
-- WHERE order_date = '2024-01-15' → 使用索引快速定位

CREATE INDEX idx_orders_date_user ON orders(order_date, user_id);
-- 复合索引 → 先按日期过滤，再按用户过滤

-- 部分索引（3.8.0+）:
CREATE INDEX idx_recent_orders ON orders(order_date) WHERE order_date >= '2024-01-01';
-- 只索引近期数据，减少索引大小

-- ============================================================
-- 6. 对比与引擎开发者启示
-- ============================================================
-- SQLite 的分区替代方案:
--   手动分表 → 最灵活但最多应用层代码
--   视图统一 → 透明但无分区裁剪
--   ATTACH DATABASE → 文件级分区（最推荐）
--   索引 → 适合不分区的场景
--
-- 对引擎开发者的启示:
--   嵌入式数据库的"分区"最自然的实现是文件级分离（ATTACH）。
--   这比在单文件中实现分区裁剪简单得多，
--   且有额外优势（独立备份/删除/VACUUM）。
--   如果设计嵌入式数据库，ATTACH 机制比 PARTITION BY 更适合。
