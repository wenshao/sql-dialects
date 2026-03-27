-- SQLite: 字符串函数
--
-- 参考资料:
--   [1] SQLite Documentation - Core Functions
--       https://www.sqlite.org/lang_corefunc.html
--   [2] SQLite Documentation - Expression
--       https://www.sqlite.org/lang_expr.html

-- 拼接
SELECT 'hello' || ' ' || 'world';                    -- 'hello world'
-- 注意：SQLite 没有 CONCAT() 函数（3.44.0+ 才加入）

-- 3.44.0+: CONCAT / CONCAT_WS
SELECT CONCAT('hello', ' ', 'world');                 -- 'hello world'
SELECT CONCAT_WS(',', 'a', 'b', 'c');                -- 'a,b,c'

-- 长度
SELECT LENGTH('hello');                               -- 5（字符数）
SELECT LENGTH(X'68656C6C6F');                         -- 5（BLOB 的字节数）

-- 大小写（仅对 ASCII 有效，不支持 Unicode 大小写转换）
SELECT UPPER('hello');                                -- 'HELLO'
SELECT LOWER('HELLO');                                -- 'hello'

-- 截取
SELECT SUBSTR('hello world', 7, 5);                   -- 'world'
SELECT SUBSTRING('hello world', 7, 5);                -- 'world'（别名）
-- 注意：没有 LEFT() / RIGHT()
SELECT SUBSTR('hello', 1, 3);                         -- 'hel'（替代 LEFT）
SELECT SUBSTR('hello', -3);                           -- 'llo'（替代 RIGHT）

-- 查找
SELECT INSTR('hello world', 'world');                 -- 7

-- 替换 / 修剪
SELECT REPLACE('hello world', 'world', 'sqlite');     -- 'hello sqlite'
SELECT TRIM('  hello  ');                             -- 'hello'
SELECT LTRIM('  hello');                              -- 'hello'
SELECT RTRIM('hello  ');                              -- 'hello'
SELECT TRIM('xxhelloxx', 'x');                        -- 'hello'

-- 注意：没有 LPAD/RPAD、REVERSE、REPEAT 等函数
-- 需要自行用 || 和 SUBSTR 实现，或使用扩展

-- GROUP_CONCAT（聚合拼接）
SELECT GROUP_CONCAT(username, ', ') FROM users;

-- 3.38.0+: 内置数学函数和一些新字符串函数
