-- SQL Standard: DELETE
--
-- 参考资料:
--   [1] ISO/IEC 9075 SQL Standard
--       https://www.iso.org/standard/76583.html
--   [2] Modern SQL - by Markus Winand
--       https://modern-sql.com/
--   [3] Modern SQL - DELETE
--       https://modern-sql.com/feature/delete

-- === SQL-89 (SQL1) ===
-- 基本删除（搜索式 DELETE）
DELETE FROM users WHERE username = 'alice';

-- 删除所有行
DELETE FROM users;

-- === SQL-92 (SQL2) ===
-- 子查询删除
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- EXISTS 子查询
DELETE FROM users
WHERE EXISTS (SELECT 1 FROM blacklist WHERE blacklist.email = users.email);

-- 相关子查询
DELETE FROM users u
WHERE (SELECT COUNT(*) FROM orders o WHERE o.user_id = u.id) = 0;

-- === SQL:1999 (SQL3) ===
-- 更复杂的子查询支持
DELETE FROM users
WHERE age < ALL (SELECT min_age FROM policies WHERE policy_type = 'active');

-- === SQL:2003 ===
-- MERGE 语句中的 DELETE（见 upsert）
-- MERGE ... WHEN MATCHED THEN DELETE

-- === SQL:2011 ===
-- 时态表删除
-- DELETE 系统版本化表时自动记录删除时间
-- 系统时间维度的行不会物理删除，而是标记结束时间

-- === 各版本差异总结 ===
-- SQL-89:  基本 DELETE FROM ... WHERE
-- SQL-92:  子查询 (IN, EXISTS, 相关子查询)
-- SQL:1999: 更丰富的子查询能力
-- SQL:2003: MERGE 中的条件删除
-- SQL:2011: 时态表支持
-- 注意: TRUNCATE TABLE 不在 SQL 标准中（各数据库自行实现）
-- 注意: 多表 JOIN 删除不在 SQL 标准中
-- 注意: ORDER BY / LIMIT 不在 SQL 标准中
