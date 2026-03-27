-- SQLite: 临时表与临时存储
--
-- 参考资料:
--   [1] SQLite Documentation - CREATE TABLE
--       https://www.sqlite.org/lang_createtable.html
--   [2] SQLite Documentation - Temporary Files
--       https://www.sqlite.org/tempfiles.html

-- ============================================================
-- CREATE TEMPORARY TABLE
-- ============================================================

-- 创建临时表
CREATE TEMPORARY TABLE temp_active_users (
    id INTEGER PRIMARY KEY,
    username TEXT,
    email TEXT
);

-- 简写
CREATE TEMP TABLE temp_results (
    id INTEGER,
    value REAL
);

-- 从查询创建
CREATE TEMP TABLE temp_orders AS
SELECT user_id, SUM(amount) AS total, COUNT(*) AS cnt
FROM orders GROUP BY user_id;

-- ============================================================
-- 临时表特性
-- ============================================================

-- 1. 存储在临时数据库（temp schema）中
-- 2. 连接关闭时自动删除
-- 3. 默认存储在内存中（可溢出到磁盘）

-- 通过 temp schema 访问
SELECT * FROM temp.temp_active_users;

-- 创建索引
CREATE INDEX temp.idx_temp_users ON temp_active_users(username);

-- ============================================================
-- 临时视图
-- ============================================================

CREATE TEMP VIEW temp_user_summary AS
SELECT username, COUNT(*) AS order_count
FROM users u JOIN orders o ON u.id = o.user_id
GROUP BY username;

SELECT * FROM temp_user_summary;

-- ============================================================
-- 临时触发器
-- ============================================================

CREATE TEMP TRIGGER temp_audit_insert
AFTER INSERT ON users
BEGIN
    INSERT INTO audit_log (action, table_name, record_id)
    VALUES ('INSERT', 'users', NEW.id);
END;

-- ============================================================
-- CTE（3.8.3+）
-- ============================================================

WITH active_users AS (
    SELECT * FROM users WHERE status = 1
),
user_orders AS (
    SELECT u.id, u.username, COUNT(o.id) AS order_count
    FROM active_users u
    LEFT JOIN orders o ON u.id = o.user_id
    GROUP BY u.id, u.username
)
SELECT * FROM user_orders WHERE order_count > 5;

-- 递归 CTE
WITH RECURSIVE cnt(x) AS (
    SELECT 1
    UNION ALL
    SELECT x + 1 FROM cnt WHERE x < 100
)
SELECT x FROM cnt;

-- ============================================================
-- CTE 物化控制（3.35.0+）
-- ============================================================

-- 强制物化
WITH active AS MATERIALIZED (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active WHERE age > 25;

-- 禁止物化
WITH active AS NOT MATERIALIZED (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active WHERE age > 25;

-- ============================================================
-- 临时存储配置
-- ============================================================

-- 控制临时文件存储位置
-- PRAGMA temp_store = 0;   -- 默认（通常是文件）
-- PRAGMA temp_store = 1;   -- 文件
-- PRAGMA temp_store = 2;   -- 内存

-- 临时文件目录
-- PRAGMA temp_store_directory = '/tmp';  -- 已废弃

-- ============================================================
-- 内存数据库（替代临时表）
-- ============================================================

-- 附加内存数据库
ATTACH DATABASE ':memory:' AS memdb;

CREATE TABLE memdb.fast_cache (
    key TEXT PRIMARY KEY,
    value TEXT
);

INSERT INTO memdb.fast_cache VALUES ('k1', 'v1');
SELECT * FROM memdb.fast_cache;

DETACH DATABASE memdb;

-- 注意：SQLite 临时表存储在 temp schema 中
-- 注意：PRAGMA temp_store = 2 将临时表存储在内存中
-- 注意：3.8.3+ 支持 CTE，3.35.0+ 支持 CTE 物化控制
-- 注意：可以附加 :memory: 数据库作为快速临时存储
-- 注意：连接关闭时所有临时对象自动删除
