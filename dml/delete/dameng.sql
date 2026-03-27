-- DamengDB (达梦): DELETE
-- Oracle compatible syntax.
--
-- 参考资料:
--   [1] DamengDB SQL Reference
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html
--   [2] DamengDB System Admin Manual
--       https://eco.dameng.com/document/dm/zh-cn/pm/index.html

-- 基本删除
DELETE FROM users WHERE username = 'alice';

-- 子查询删除
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- EXISTS 删除
DELETE FROM users u
WHERE EXISTS (SELECT 1 FROM blacklist b WHERE b.email = u.email);

-- 关联删除（使用子查询）
DELETE FROM users
WHERE id IN (
    SELECT u.id FROM users u
    JOIN blacklist b ON u.email = b.email
);

-- 删除所有行
DELETE FROM users;
TRUNCATE TABLE users;

-- RETURNING（PL/SQL 中使用）
-- DELETE FROM users WHERE status = 0 RETURNING id BULK COLLECT INTO v_ids;

-- 注意事项：
-- 语法与 Oracle 兼容
-- 没有 MySQL 风格的 JOIN DELETE 语法
-- TRUNCATE 不可回滚，不触发触发器
-- 使用子查询或 EXISTS 实现多表删除
-- 支持分区表上的 DELETE（可以指定分区）
-- DELETE FROM users PARTITION (p2023) WHERE ...;
