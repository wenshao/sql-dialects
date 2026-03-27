-- Trino: 字符串函数
--
-- 参考资料:
--   [1] Trino - String Functions
--       https://trino.io/docs/current/functions/string.html
--   [2] Trino - Regular Expression Functions
--       https://trino.io/docs/current/functions/regexp.html

-- 拼接
SELECT 'hello' || ' ' || 'world';                        -- 'hello world'
SELECT CONCAT('hello', ' ', 'world');                    -- 'hello world'
SELECT CONCAT_WS(',', 'a', 'b', 'c');                   -- 'a,b,c'

-- 长度
SELECT LENGTH('hello');                                  -- 5（字符数）
SELECT CHAR_LENGTH('hello');                             -- 5

-- 大小写
SELECT UPPER('hello');                                   -- 'HELLO'
SELECT LOWER('HELLO');                                   -- 'hello'

-- 截取
SELECT SUBSTR('hello world', 7, 5);                      -- 'world'
SELECT SUBSTRING('hello world', 7, 5);                   -- 'world'
SELECT SUBSTRING('hello world' FROM 7 FOR 5);            -- 'world'（SQL 标准）

-- 查找
SELECT POSITION('world' IN 'hello world');               -- 7
SELECT STRPOS('hello world', 'world');                   -- 7
SELECT STARTS_WITH('hello world', 'hello');              -- TRUE

-- 替换 / 填充 / 修剪
SELECT REPLACE('hello world', 'world', 'trino');         -- 'hello trino'
SELECT LPAD('42', 5, '0');                               -- '00042'
SELECT RPAD('hi', 5, '.');                               -- 'hi...'
SELECT TRIM('  hello  ');                                -- 'hello'
SELECT LTRIM('  hello  ');                               -- 'hello  '
SELECT RTRIM('  hello  ');                               -- '  hello'
SELECT TRIM(BOTH 'x' FROM 'xxhelloxx');                  -- 'hello'

-- 翻转 / 重复
SELECT REVERSE('hello');                                 -- 'olleh'

-- 正则（Java 正则语法）
SELECT REGEXP_LIKE('abc 123', '[0-9]+');                  -- TRUE
SELECT REGEXP_EXTRACT('abc 123 def', '[0-9]+');           -- '123'
SELECT REGEXP_EXTRACT_ALL('a1b2c3', '[0-9]+');            -- ['1', '2', '3']
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');     -- 'abc # def'
SELECT REGEXP_COUNT('a1b2c3', '[0-9]');                  -- 3
SELECT REGEXP_POSITION('abc 123', '[0-9]+');             -- 5
SELECT REGEXP_SPLIT('a,b;c', '[,;]');                    -- ['a', 'b', 'c']

-- 分割
SELECT SPLIT('a,b,c', ',');                              -- 返回 ARRAY
SELECT SPLIT_PART('a.b.c', '.', 2);                      -- 'b'
SELECT SPLIT_TO_MAP('a:1,b:2', ',', ':');                -- MAP('a','1','b','2')

-- 聚合拼接
SELECT LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;
SELECT ARRAY_JOIN(ARRAY_AGG(username), ', ') FROM users;

-- 编码
SELECT TO_BASE64(CAST('hello' AS VARBINARY));
SELECT FROM_BASE64('aGVsbG8=');
SELECT TO_HEX(CAST('hello' AS VARBINARY));
SELECT MD5(CAST('hello' AS VARBINARY));
SELECT SHA256(CAST('hello' AS VARBINARY));
SELECT XXHASH64(CAST('hello' AS VARBINARY));

-- 其他
SELECT TRANSLATE('hello', 'helo', 'HELO');               -- 'HELLO'
SELECT CHR(65);                                          -- 'A'
SELECT CODEPOINT('A');                                   -- 65
SELECT WORD_STEM('running');                             -- 'run'（词干提取）
SELECT WORD_STEM('running', 'en');                       -- 指定语言
SELECT SOUNDEX('hello');                                 -- Soundex 编码
SELECT LEVENSHTEIN_DISTANCE('kitten', 'sitting');        -- 3（编辑距离）
SELECT HAMMING_DISTANCE('karolin', 'kathrin');           -- 3

-- 注意：正则使用 Java 正则语法
-- 注意：LENGTH 返回字符数（非字节数）
-- 注意：函数命名遵循 SQL 标准
