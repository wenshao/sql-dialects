-- SQL 标准: 分页演进
--
-- 参考资料:
--   [1] ISO/IEC 9075 SQL Standard
--       https://www.iso.org/standard/76583.html
--   [2] Modern SQL - by Markus Winand
--       https://modern-sql.com/
--   [3] Modern SQL - FETCH FIRST / OFFSET
--       https://modern-sql.com/feature/fetch-first

-- ========== SQL-92 (SQL2) ==========
-- 无标准分页语法
-- 各数据库使用私有语法：LIMIT/OFFSET (MySQL), ROWNUM (Oracle) 等

-- ========== SQL:2003 ==========
-- 引入窗口函数，可用于分页
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- ========== SQL:2008 ==========
-- 正式引入 OFFSET / FETCH 标准分页语法

-- FETCH FIRST（取前 N 行）
SELECT * FROM users ORDER BY id FETCH FIRST 10 ROWS ONLY;

-- OFFSET + FETCH（跳过后取 N 行）
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;

-- FETCH NEXT（等价于 FETCH FIRST）
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- ROW / ROWS（单数和复数均可）
SELECT * FROM users ORDER BY id FETCH FIRST 1 ROW ONLY;
SELECT * FROM users ORDER BY id FETCH FIRST 10 ROWS ONLY;

-- OFFSET 不带 FETCH（跳过前 N 行，返回其余所有行）
SELECT * FROM users ORDER BY id OFFSET 20 ROWS;

-- ========== SQL:2008 扩展 ==========
-- PERCENT（百分比）
SELECT * FROM users ORDER BY id FETCH FIRST 10 PERCENT ROWS ONLY;

-- WITH TIES（包含同值行）
SELECT * FROM users ORDER BY age FETCH FIRST 10 ROWS WITH TIES;

-- ========== 各标准版本分页特性总结 ==========
-- SQL:2003 之前: 无标准分页语法
-- SQL:2003: ROW_NUMBER() 窗口函数可间接实现
-- SQL:2008: OFFSET / FETCH FIRST ... ROWS ONLY 标准语法
--           PERCENT, WITH TIES
-- 注意：LIMIT / OFFSET 不是 SQL 标准语法，但被大多数数据库支持
-- 注意：游标分页（WHERE id > ? ORDER BY id LIMIT n）也不是标准语法，但是最佳实践
