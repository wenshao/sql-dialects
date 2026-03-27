-- ClickHouse: UPSERT
--
-- 参考资料:
--   [1] ClickHouse SQL Reference - INSERT INTO
--       https://clickhouse.com/docs/en/sql-reference/statements/insert-into
--   [2] ClickHouse - ReplacingMergeTree
--       https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replacingmergetree

-- 注意: ClickHouse 没有标准 UPSERT / MERGE 语法
-- 通过表引擎特性和 INSERT 实现"更新或插入"语义

-- === 方式一: ReplacingMergeTree（推荐） ===
-- 通过插入新版本行，后台合并时自动去重保留最新版本

-- 建表时指定版本列
-- CREATE TABLE users (
--     username String,
--     email String,
--     age UInt8,
--     version UInt64
-- ) ENGINE = ReplacingMergeTree(version)
-- ORDER BY username;

-- UPSERT = 直接 INSERT 新版本
INSERT INTO users (username, email, age, version)
VALUES ('alice', 'new@example.com', 26, 2);
-- 后台合并后，同一 ORDER BY 键只保留 version 最大的行

-- 查询时强制去重（合并前可能看到多个版本）
SELECT * FROM users FINAL WHERE username = 'alice';

-- 批量 UPSERT
INSERT INTO users (username, email, age, version)
VALUES
    ('alice', 'alice_new@example.com', 26, 2),
    ('bob', 'bob_new@example.com', 31, 2);

-- === 方式二: CollapsingMergeTree ===
-- 通过 sign 列 (+1 / -1) 实现行级更新

-- 插入取消行 + 新行
INSERT INTO users (username, email, age, sign)
VALUES ('alice', 'alice@example.com', 25, -1);  -- 取消旧行
INSERT INTO users (username, email, age, sign)
VALUES ('alice', 'new@example.com', 26, 1);     -- 插入新行

-- === 方式三: AggregatingMergeTree + argMax ===
-- 用聚合函数保留最新值（适合宽表场景）

-- === 方式四: ALTER TABLE UPDATE + INSERT（不推荐） ===
-- 先尝试更新，如果影响 0 行则插入（需要应用层处理）
-- ALTER TABLE users UPDATE email = 'new@example.com' WHERE username = 'alice';
-- 然后检查是否有行被更新，如果没有则 INSERT

-- === 方式五: INSERT ... ON DUPLICATE KEY（不支持） ===
-- ClickHouse 不支持 MySQL 风格的 ON DUPLICATE KEY

-- 23.3+: 实验性 DELETE + INSERT 组合
-- DELETE FROM users WHERE username = 'alice';
-- INSERT INTO users VALUES ('alice', 'new@example.com', 26);

-- 最佳实践:
-- 1. 使用 ReplacingMergeTree 引擎处理 UPSERT 场景
-- 2. 查询时使用 FINAL 关键字确保去重
-- 3. 或在应用层使用 argMax 聚合去重
-- 4. 批量操作优于逐行操作
