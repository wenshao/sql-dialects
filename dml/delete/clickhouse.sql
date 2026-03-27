-- ClickHouse: DELETE
--
-- 参考资料:
--   [1] ClickHouse SQL Reference - ALTER DELETE
--       https://clickhouse.com/docs/en/sql-reference/statements/alter/delete
--   [2] ClickHouse - Lightweight Delete
--       https://clickhouse.com/docs/en/sql-reference/statements/delete

-- 注意: ClickHouse 没有标准 DELETE 语句
-- 使用 ALTER TABLE ... DELETE（异步 mutation，后台执行）
-- mutation 是重量级操作，不适合频繁小批量删除
-- 18.12.14+ 支持

-- === ALTER TABLE DELETE（异步 mutation） ===

-- 基本删除
ALTER TABLE users DELETE WHERE username = 'alice';

-- 条件删除
ALTER TABLE users DELETE WHERE status = 0 AND last_login < '2023-01-01';

-- 多条件删除
ALTER TABLE users DELETE WHERE age < 18 OR status = -1;

-- 子查询删除
ALTER TABLE users DELETE WHERE id IN (SELECT user_id FROM blacklist);

-- 查看 mutation 执行状态
-- SELECT * FROM system.mutations WHERE table = 'users' AND is_done = 0;

-- 同步等待 mutation 完成
-- SET mutations_sync = 1;
-- ALTER TABLE users DELETE WHERE username = 'alice';

-- === 轻量级删除（23.3+） ===
-- 使用标准 DELETE 语法，通过标记行而非物理删除实现
-- 性能远优于 mutation，适合频繁删除场景

DELETE FROM users WHERE username = 'alice';

-- 轻量级删除通过 _row_exists 虚拟列标记行为已删除
-- 查询时自动过滤已删除行
-- 后台合并时才物理删除数据

-- === 替代方案 ===

-- TRUNCATE（清空整个表，立即生效）
TRUNCATE TABLE users;

-- DROP PARTITION（删除整个分区，最快）
ALTER TABLE events DROP PARTITION '2024-01-15';

-- TTL 自动过期删除
-- CREATE TABLE events (..., event_date Date)
-- ENGINE = MergeTree ORDER BY (event_date)
-- TTL event_date + INTERVAL 90 DAY DELETE;

-- 限制:
-- ALTER TABLE DELETE 是异步的，不保证立即生效
-- WHERE 子句必须存在
-- mutation 会重写整个 data part，影响性能
-- 轻量级 DELETE 在 23.3 引入，23.8+ 已正式可用（非实验性）
