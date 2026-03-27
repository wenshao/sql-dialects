-- StarRocks: DELETE
--
-- 参考资料:
--   [1] StarRocks - DELETE
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/loading_unloading/DELETE/
--   [2] StarRocks SQL Reference
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/

-- 注意: StarRocks DELETE 支持取决于表模型
-- 主键模型（Primary Key）: 支持标准 DELETE
-- 其他模型: 仅支持按分区条件删除

-- === 主键模型表 DELETE ===

-- 基本删除
DELETE FROM users WHERE username = 'alice';

-- 子查询删除
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- EXISTS 子查询
DELETE FROM users
WHERE EXISTS (SELECT 1 FROM blacklist WHERE blacklist.email = users.email);

-- 多表 JOIN 删除（3.0+）
DELETE FROM users
USING blacklist
WHERE users.email = blacklist.email;

-- CTE + DELETE（3.0+）
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);

-- 条件删除
DELETE FROM users WHERE status = 0 AND last_login < '2023-01-01';

-- 删除所有行
DELETE FROM users;

-- === 非主键模型表（按分区条件删除） ===

-- 按分区键值删除（明细模型、聚合模型、更新模型）
DELETE FROM events PARTITION (p20240115)
WHERE event_name = 'spam';

-- 限制:
-- 非主键模型表的 DELETE 条件必须包含分区列
-- 不支持 ORDER BY / LIMIT
-- 不支持更新主键列

-- TRUNCATE（清空表数据）
TRUNCATE TABLE users;
