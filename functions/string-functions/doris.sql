-- Apache Doris: 字符串函数
--
-- 参考资料:
--   [1] Doris SQL Manual
--       https://doris.apache.org/docs/sql-manual/sql-statements/
--   [2] Doris Data Types
--       https://doris.apache.org/docs/sql-manual/data-types/
--   [3] Doris Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/

-- 拼接
SELECT CONCAT('hello', ' ', 'world');                -- 'hello world'
SELECT CONCAT_WS(',', 'a', 'b', 'c');               -- 'a,b,c'（带分隔符）
-- 注意：|| 不是拼接运算符（MySQL 兼容模式）

-- 长度
SELECT LENGTH('hello');                               -- 5（字节数）
SELECT CHAR_LENGTH('你好');                            -- 2（字符数）

-- 大小写
SELECT UPPER('hello');                                -- 'HELLO'
SELECT LOWER('HELLO');                                -- 'hello'
SELECT INITCAP('hello world');                       -- 'Hello World'

-- 截取
SELECT SUBSTRING('hello world', 7, 5);                -- 'world'
SELECT SUBSTR('hello world', 7, 5);                   -- 'world'（别名）
SELECT LEFT('hello', 3);                              -- 'hel'
SELECT RIGHT('hello', 3);                             -- 'llo'

-- 查找
SELECT INSTR('hello world', 'world');                 -- 7
SELECT LOCATE('world', 'hello world');                -- 7
SELECT POSITION('world' IN 'hello world');            -- 7

-- 替换 / 填充 / 修剪
SELECT REPLACE('hello world', 'world', 'doris');      -- 'hello doris'
SELECT LPAD('42', 5, '0');                            -- '00042'
SELECT RPAD('hi', 5, '.');                            -- 'hi...'
SELECT TRIM('  hello  ');                             -- 'hello'
SELECT LTRIM('  hello');                              -- 'hello'
SELECT RTRIM('hello  ');                              -- 'hello'
SELECT TRIM(BOTH 'x' FROM 'xxhelloxx');              -- 'hello'

-- 翻转 / 重复
SELECT REVERSE('hello');                              -- 'olleh'
SELECT REPEAT('ab', 3);                               -- 'ababab'

-- 正则
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');  -- 'abc # def'
SELECT REGEXP_EXTRACT('abc 123 def', '[0-9]+', 0);   -- '123'
SELECT 'abc' REGEXP '[a-z]+';                        -- 1 (TRUE)

-- 分割
SELECT SPLIT_PART('a,b,c', ',', 2);                  -- 'b'
SELECT EXPLODE_SPLIT('a,b,c', ',');                  -- 多行输出

-- 编码
SELECT HEX('hello');                                  -- '68656C6C6F'
SELECT UNHEX('68656C6C6F');                          -- 'hello'
SELECT MD5('hello');                                  -- MD5 哈希
SELECT SM3('hello');                                  -- SM3 哈希（国密）

-- 空格填充
SELECT SPACE(5);                                      -- '     '

-- GROUP_CONCAT（聚合拼接）
SELECT GROUP_CONCAT(username SEPARATOR ', ') FROM users;
SELECT GROUP_CONCAT(DISTINCT city ORDER BY city SEPARATOR ', ') FROM users;

-- 注意：Doris 兼容 MySQL 字符串函数
-- 注意：额外支持 INITCAP, SPLIT_PART 等扩展函数
-- 注意：不支持 PIPES_AS_CONCAT 模式
