-- SQLite: 迁移速查表 (Migration Cheatsheet)
--
-- 参考资料:
--   [1] SQLite Documentation - SQL Syntax
--       https://www.sqlite.org/lang.html
--   [2] SQLite Documentation - Datatypes
--       https://www.sqlite.org/datatype3.html

-- ============================================================
-- 一、从 MySQL/PostgreSQL 迁移到 SQLite
-- ============================================================
-- 数据类型: SQLite 使用动态类型（类型亲和性）
--   所有整数    → INTEGER
--   所有浮点    → REAL
--   所有字符串  → TEXT
--   所有二进制  → BLOB
--   布尔/日期   → INTEGER 或 TEXT（SQLite 无原生类型）
--   JSON       → TEXT（通过 JSON1 扩展处理）
--   AUTO_INCREMENT → INTEGER PRIMARY KEY（自动递增）

-- 函数等价:
--   IFNULL / NVL / ISNULL   → IFNULL(a, b) 或 COALESCE(a, b)
--   NOW() / GETDATE()       → DATETIME('now')
--   CURRENT_DATE            → DATE('now')
--   DATE_ADD                → DATE(d, '+1 day')
--   DATEDIFF                → JULIANDAY(a) - JULIANDAY(b)
--   CONCAT(a, b)            → a || b
--   GROUP_CONCAT            → GROUP_CONCAT(col, ',')
--   SUBSTRING               → SUBSTR(s, start, len)
--   LENGTH                  → LENGTH(s)

-- 常见陷阱:
--   - SQLite 不支持 ALTER TABLE DROP COLUMN（3.35.0+ 支持）
--   - SQLite 不支持 RIGHT JOIN / FULL OUTER JOIN（3.39.0+ 支持）
--   - SQLite 没有严格的数据类型检查（除非用 STRICT 表）
--   - SQLite 不支持存储过程/触发器中的复杂逻辑
--   - SQLite 的并发写入有限制（WAL 模式可改善）

-- ============================================================
-- 二、自增
-- ============================================================
CREATE TABLE t (id INTEGER PRIMARY KEY);  -- 自动递增
-- 或显式: CREATE TABLE t (id INTEGER PRIMARY KEY AUTOINCREMENT);
-- 区别: AUTOINCREMENT 保证 ID 单调递增，不复用已删除的 ID

-- ============================================================
-- 三、日期/时间函数
-- ============================================================
SELECT DATETIME('now');                       -- 当前 UTC 时间
SELECT DATETIME('now', 'localtime');          -- 当前本地时间
SELECT DATE('now');                           -- 当前日期
SELECT DATE('now', '+1 day');                 -- 加一天
SELECT DATE('now', '-1 month');               -- 减一月
SELECT JULIANDAY('2024-12-31') - JULIANDAY('2024-01-01'); -- 日期差
SELECT STRFTIME('%Y-%m-%d %H:%M:%S', 'now'); -- 格式化

-- ============================================================
-- 四、字符串函数
-- ============================================================
SELECT LENGTH('hello');              -- 字符长度
SELECT UPPER('hello');               -- 大写
SELECT LOWER('HELLO');               -- 小写
SELECT TRIM('  hello  ');            -- 去空格
SELECT SUBSTR('hello', 2, 3);       -- 子串 → 'ell'
SELECT REPLACE('hello', 'l', 'r');   -- 替换
SELECT INSTR('hello', 'lo');         -- 位置 → 4
SELECT 'hello' || ' world';         -- 连接
SELECT GROUP_CONCAT(name, ', ') FROM users; -- 聚合连接
