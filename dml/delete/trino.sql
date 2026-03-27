-- Trino: DELETE
--
-- 参考资料:
--   [1] Trino - DELETE
--       https://trino.io/docs/current/sql/delete.html
--   [2] Trino - TRUNCATE TABLE
--       https://trino.io/docs/current/sql/truncate.html

-- 注意: Trino DELETE 支持取决于底层 connector
-- 支持 DELETE 的 connector: Iceberg, Delta Lake, Hive (ACID), Kudu, MySQL, PostgreSQL 等
-- 不支持 DELETE 的 connector: Kafka, Elasticsearch 等

-- 基本删除
DELETE FROM users WHERE username = 'alice';

-- 子查询删除
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- EXISTS 子查询
DELETE FROM users
WHERE EXISTS (SELECT 1 FROM blacklist b WHERE b.email = users.email);

-- 条件删除
DELETE FROM users WHERE status = 0 AND last_login < DATE '2023-01-01';

-- 删除所有行
DELETE FROM users;

-- CTE + DELETE
WITH inactive AS (
    SELECT id FROM users WHERE last_login < DATE '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);

-- 跨 catalog 子查询删除
DELETE FROM iceberg.db.users
WHERE email IN (SELECT email FROM mysql.db.blacklist);

-- Iceberg connector 特性
-- DELETE 产生新 snapshot，历史数据可通过 Time Travel 查看
DELETE FROM iceberg.db.events WHERE event_date < DATE '2023-01-01';
-- 查看历史: SELECT * FROM iceberg.db.events FOR VERSION AS OF <snapshot_id>;

-- Delta Lake connector 特性
-- DELETE 产生新版本
DELETE FROM delta.db.events WHERE event_date < DATE '2023-01-01';

-- Hive ACID 表删除
DELETE FROM hive.db.users WHERE username = 'alice';

-- 限制:
-- 不支持多表 JOIN 删除
-- 不支持 ORDER BY / LIMIT
-- 性能取决于底层存储和 connector 实现
-- Hive connector 非 ACID 表不支持 DELETE
