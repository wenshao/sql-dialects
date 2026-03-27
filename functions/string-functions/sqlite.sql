-- SQLite: 字符串函数
--
-- 参考资料:
--   [1] SQLite Documentation - Core Functions
--       https://www.sqlite.org/lang_corefunc.html

-- ============================================================
-- 1. 基本字符串函数
-- ============================================================

SELECT length('hello');                -- 5（字符数，UTF-8 aware）
SELECT upper('hello');                 -- 'HELLO'（仅 ASCII）
SELECT lower('HELLO');                 -- 'hello'（仅 ASCII）
SELECT trim('  hello  ');              -- 'hello'
SELECT ltrim('  hello');               -- 'hello'
SELECT rtrim('hello  ');               -- 'hello'
SELECT trim('xxhelloxx', 'x');         -- 'hello'（指定字符）

-- 子字符串
SELECT substr('hello world', 7);       -- 'world'
SELECT substr('hello world', 1, 5);    -- 'hello'

-- 查找位置（1-based）
SELECT instr('hello world', 'world');  -- 7

-- 替换
SELECT replace('hello world', 'world', 'SQLite');  -- 'hello SQLite'

-- ============================================================
-- 2. SQLite 字符串函数的局限
-- ============================================================

-- upper()/lower() 只处理 ASCII!
-- SELECT upper('cafe');   → 'CAFE'（正确）
-- SELECT upper('cafe');   → 'cafe'（错误! 带重音的字符不转换）
-- 需要加载 ICU 扩展才能正确处理 Unicode 大小写转换
--
-- 不支持的常见函数:
--   LPAD / RPAD（左/右填充）→ 需要 printf
--   REVERSE → 不支持
--   SPLIT → 不支持（用递归 CTE 模拟）
--   REGEXP → 默认不支持（需要加载扩展）
--   CONCAT → 用 || 运算符替代

-- ============================================================
-- 3. 字符串拼接与格式化
-- ============================================================

-- 拼接用 || 运算符（不是 CONCAT 函数）
SELECT 'hello' || ' ' || 'world';     -- 'hello world'
-- 注意: NULL || 'text' = NULL（与 MySQL 的 CONCAT 不同）

-- printf 格式化（3.8.3+）
SELECT printf('%d items at $%.2f', 5, 9.99);  -- '5 items at $9.99'
SELECT printf('%05d', 42);                     -- '00042'（左填充零）
SELECT printf('%-10s|', 'hello');              -- 'hello     |'（左对齐填充）

-- 3.38.0+: CONCAT 和 CONCAT_WS 函数
-- SELECT CONCAT('hello', ' ', 'world');       -- 'hello world'

-- ============================================================
-- 4. LIKE 和 GLOB
-- ============================================================

-- LIKE（大小写不敏感，仅 ASCII）
SELECT * FROM users WHERE username LIKE '%alice%';
-- % = 任意多字符, _ = 单个字符

-- GLOB（大小写敏感，Unix 风格通配符）
SELECT * FROM users WHERE username GLOB '*[Aa]lice*';
-- * = 任意多字符, ? = 单个字符, [...] = 字符类

-- LIKE 的大小写不敏感仅限 ASCII:
-- 'CAFE' LIKE 'cafe'  → true
-- 'CAFE' LIKE 'cafe'  → true（重音字符不参与不敏感比较）

-- ============================================================
-- 5. 编码函数
-- ============================================================

SELECT hex('hello');                   -- '68656C6C6F'
SELECT unicode('A');                   -- 65（Unicode 码点）
SELECT char(65);                       -- 'A'（码点转字符）
SELECT quote('it''s');                 -- '''it''s'''（SQL 转义）
SELECT zeroblob(10);                   -- 10 字节的零填充 BLOB

-- ============================================================
-- 6. 对比与引擎开发者启示
-- ============================================================
-- SQLite 字符串函数的设计:
--   (1) ASCII-only 的 upper/lower → Unicode 需要 ICU 扩展
--   (2) || 运算符而非 CONCAT → SQL 标准但 NULL 传播
--   (3) printf → 比 LPAD/RPAD 更通用
--   (4) GLOB → Unix 风格通配符（SQLite 独有）
--
-- 对引擎开发者的启示:
--   Unicode 处理是字符串函数的最大复杂度来源。
--   SQLite 选择 ASCII-only + ICU 扩展的分层方案。
--   对嵌入式引擎: 核心只做 ASCII，Unicode 通过扩展提供，是合理的。
