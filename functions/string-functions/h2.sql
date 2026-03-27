-- H2: 字符串函数

-- 拼接
SELECT CONCAT('hello', ' ', 'world');                -- 'hello world'
SELECT 'hello' || ' ' || 'world';                   -- 'hello world'

-- 长度
SELECT LENGTH('hello');                               -- 5
SELECT CHAR_LENGTH('hello');                          -- 5

-- 大小写
SELECT UPPER('hello');                                -- 'HELLO'
SELECT LOWER('HELLO');                                -- 'hello'

-- 截取
SELECT SUBSTRING('hello world', 7, 5);                -- 'world'
SELECT SUBSTRING('hello world' FROM 7 FOR 5);         -- 'world'
SELECT LEFT('hello', 3);                              -- 'hel'
SELECT RIGHT('hello', 3);                             -- 'llo'

-- 查找
SELECT POSITION('world' IN 'hello world');            -- 7
SELECT LOCATE('world', 'hello world');                -- 7
SELECT INSTR('hello world', 'world');                 -- 7

-- 替换 / 填充 / 修剪
SELECT REPLACE('hello world', 'world', 'h2');         -- 'hello h2'
SELECT LPAD('42', 5, '0');                            -- '00042'
SELECT RPAD('hi', 5, '.');                            -- 'hi...'
SELECT TRIM('  hello  ');                             -- 'hello'
SELECT LTRIM('  hello');                              -- 'hello'
SELECT RTRIM('hello  ');                              -- 'hello'

-- 翻转 / 重复
SELECT REVERSE('hello');                              -- 'olleh'
SELECT REPEAT('ab', 3);                               -- 'ababab'
SELECT SPACE(5);                                      -- '     '

-- 正则
SELECT REGEXP_REPLACE('abc 123', '[0-9]+', '#');
SELECT REGEXP_LIKE('abc 123', '[0-9]+');
SELECT REGEXP_SUBSTR('abc 123', '[0-9]+');

-- ASCII / CHR
SELECT ASCII('A');                                    -- 65
SELECT CHAR(65);                                      -- 'A'

-- 其他
SELECT SOUNDEX('hello');
SELECT DIFFERENCE('hello', 'hallo');
SELECT HEXTORAW('48656C6C6F');
SELECT RAWTOHEX('Hello');
SELECT TRANSLATE('hello', 'elo', 'aio');

-- GROUP_CONCAT（聚合拼接）
SELECT GROUP_CONCAT(username ORDER BY username SEPARATOR ', ') FROM users;
-- 或
SELECT LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;

-- 注意：H2 支持丰富的字符串函数
-- 注意：支持 REGEXP 系列函数
-- 注意：GROUP_CONCAT 和 LISTAGG 都可用
-- 注意：SOUNDEX/DIFFERENCE 用于语音相似度
