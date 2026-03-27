-- Apache Doris: DELETE
--
-- 参考资料:
--   [1] Doris SQL Manual
--       https://doris.apache.org/docs/sql-manual/sql-statements/
--   [2] Doris Data Types
--       https://doris.apache.org/docs/sql-manual/data-types/
--   [3] Doris Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/

-- 注意: Doris DELETE 支持取决于表模型
-- Unique Key（Merge-on-Write）: 支持标准 DELETE
-- 其他模型: 仅支持按条件删除（有限制）

-- === Unique Key 模型表 DELETE ===

-- 基本删除
DELETE FROM users WHERE username = 'alice';

-- 子查询删除
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- EXISTS 子查询
DELETE FROM users
WHERE EXISTS (SELECT 1 FROM blacklist WHERE blacklist.email = users.email);

-- 多表 JOIN 删除（2.0+）
DELETE FROM users
USING blacklist
WHERE users.email = blacklist.email;

-- CTE + DELETE（2.1+）
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);

-- 条件删除
DELETE FROM users WHERE status = 0 AND last_login < '2023-01-01';

-- 删除所有行
DELETE FROM users;

-- === 非 Unique Key 模型表 DELETE ===

-- Duplicate Key / Aggregate Key 模型的 DELETE 有条件限制
-- 条件必须是 Key 列或分区列
DELETE FROM events WHERE event_date < '2023-01-01';

-- 按分区删除
DELETE FROM events PARTITION p20240115
WHERE event_name = 'spam';

-- TRUNCATE（清空表数据）
TRUNCATE TABLE users;

-- 删除分区（DDL 操作，比 DELETE 更高效）
ALTER TABLE events DROP PARTITION p20240115;

-- 临时分区（用于原子替换数据）
-- 1. 创建临时分区
-- ALTER TABLE events ADD TEMPORARY PARTITION tp1 VALUES LESS THAN ('2024-02-01');
-- 2. 导入数据到临时分区
-- 3. 替换正式分区
-- ALTER TABLE events REPLACE PARTITION (p2024_01) WITH TEMPORARY PARTITION (tp1);

-- 限制:
-- 非 Unique Key 模型表的 DELETE 条件有限制
-- 不支持 ORDER BY / LIMIT
-- 不支持删除 Key 列条件以外的行（非 Unique Key 模型）
