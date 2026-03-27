-- BigQuery: DELETE
--
-- 参考资料:
--   [1] BigQuery SQL Reference - DELETE
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/dml-syntax#delete_statement
--   [2] BigQuery SQL Reference - DML Syntax
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/dml-syntax

-- 注意: BigQuery DML 有配额限制（每个表每秒最多 5 个并发 DML 语句）
-- DELETE 必须带 WHERE 子句（不允许无条件删除整个表）

-- 基本删除
DELETE FROM dataset.users WHERE username = 'alice';

-- 删除所有行（必须用 WHERE true）
DELETE FROM dataset.users WHERE true;

-- 子查询删除
DELETE FROM dataset.users WHERE id IN (SELECT user_id FROM dataset.blacklist);

-- EXISTS 子查询
DELETE FROM dataset.users u
WHERE EXISTS (SELECT 1 FROM dataset.blacklist b WHERE b.email = u.email);

-- CTE + DELETE
WITH inactive AS (
    SELECT id FROM dataset.users WHERE last_login < '2023-01-01'
)
DELETE FROM dataset.users WHERE id IN (SELECT id FROM inactive);

-- 按分区删除（性能更好，直接删除分区数据）
DELETE FROM dataset.events WHERE event_date = '2024-01-15';

-- 按时间范围删除
DELETE FROM dataset.events
WHERE event_date BETWEEN '2024-01-01' AND '2024-01-31';

-- 更快的方式：删除整个表或分区
-- 删除表: DROP TABLE dataset.users;
-- 删除分区: 使用分区过期 (partition_expiration_days)

-- TRUNCATE（截断表，不受 DML 配额限制）
TRUNCATE TABLE dataset.users;

-- 限制:
-- 必须有 WHERE 子句
-- 不支持多表 JOIN 删除
-- 不支持 ORDER BY / LIMIT
