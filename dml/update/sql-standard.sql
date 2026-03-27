-- SQL Standard: UPDATE
--
-- 参考资料:
--   [1] ISO/IEC 9075 SQL Standard
--       https://www.iso.org/standard/76583.html
--   [2] Modern SQL - by Markus Winand
--       https://modern-sql.com/
--   [3] Modern SQL - UPDATE
--       https://modern-sql.com/feature/update

-- === SQL-89 (SQL1) ===
-- 基本更新（搜索式 UPDATE）
UPDATE users SET age = 26 WHERE username = 'alice';

-- 多列更新
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- 无条件更新（作用于所有行）
UPDATE users SET status = 0;

-- === SQL-92 (SQL2) ===
-- 子查询更新
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;

-- 带子查询的 WHERE 条件
UPDATE users SET status = 1
WHERE id IN (SELECT user_id FROM orders WHERE amount > 1000);

-- 标量子查询赋值
UPDATE users SET
    email = (SELECT email FROM temp_users WHERE temp_users.id = users.id)
WHERE id IN (SELECT id FROM temp_users);

-- DEFAULT 关键字（重置为默认值）
UPDATE users SET age = DEFAULT WHERE username = 'alice';

-- === SQL:1999 (SQL3) ===
-- CASE 表达式
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- 行值构造器赋值
UPDATE users SET (email, age) = ('new@example.com', 26) WHERE username = 'alice';

-- === SQL:2003 ===
-- 标准化的多列赋值
UPDATE users SET (email, age) = (SELECT email, age FROM temp WHERE temp.id = users.id);

-- === SQL:2011 ===
-- 时态表更新
-- UPDATE 系统版本化表时自动记录修改时间
-- 系统时间列不可手动更新

-- === 各版本差异总结 ===
-- SQL-89:  基本 UPDATE SET ... WHERE
-- SQL-92:  子查询赋值, DEFAULT 关键字
-- SQL:1999: CASE 表达式, 行值构造器赋值
-- SQL:2003: 多列子查询赋值
-- SQL:2011: 时态表支持
-- 注意: FROM 子句多表更新不在 SQL 标准中（各数据库自行扩展）
-- 注意: ORDER BY / LIMIT 不在 SQL 标准中
