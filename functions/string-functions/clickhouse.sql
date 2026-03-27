-- ClickHouse: 字符串函数
--
-- 参考资料:
--   [1] ClickHouse SQL Reference - String Functions
--       https://clickhouse.com/docs/en/sql-reference/functions/string-functions
--   [2] ClickHouse - String Search Functions
--       https://clickhouse.com/docs/en/sql-reference/functions/string-search-functions

-- 拼接
SELECT concat('hello', ' ', 'world');                    -- 'hello world'
SELECT 'hello' || ' ' || 'world';                        -- 'hello world'
-- 注意：concat 是小写（ClickHouse 函数名区分大小写）

-- 长度
SELECT length('hello');                                  -- 5（字节数！）
SELECT lengthUTF8('你好');                                -- 2（字符数）
SELECT char_length('hello');                             -- 5（字符数，别名）

-- 大小写
SELECT upper('hello');                                   -- 'HELLO'
SELECT lower('HELLO');                                   -- 'hello'
SELECT upperUTF8('hello');                               -- 'HELLO'（UTF-8 安全）
SELECT lowerUTF8('HELLO');                               -- 'hello'（UTF-8 安全）
-- 注意：upper/lower 只处理 ASCII，非 ASCII 用 UTF8 版本

-- 截取
SELECT substring('hello world', 7, 5);                   -- 'world'
SELECT substringUTF8('hello world', 7, 5);               -- 'world'（UTF-8 安全）

-- 查找
SELECT position('hello world', 'world');                 -- 7（字节位置）
SELECT positionUTF8('hello world', 'world');             -- 7（字符位置）
SELECT positionCaseInsensitive('Hello World', 'world');  -- 7
SELECT multiSearchAllPositions('hello', ['he', 'lo']);   -- [1, 4]（多模式搜索）

-- 替换 / 填充 / 修剪
SELECT replace('hello world', 'world', 'ch');            -- 'hello ch'
SELECT replaceAll('aaa', 'a', 'b');                      -- 'bbb'
SELECT replaceOne('aaa', 'a', 'b');                      -- 'baa'（只替换第一个）
SELECT leftPad('42', 5, '0');                            -- '00042'
SELECT rightPad('hi', 5, '.');                           -- 'hi...'
SELECT trimBoth('  hello  ');                             -- 'hello'
SELECT trimLeft('  hello  ');                             -- 'hello  '
SELECT trimRight('  hello  ');                            -- '  hello'

-- 翻转 / 重复
SELECT reverse('hello');                                 -- 'olleh'
SELECT reverseUTF8('hello');                              -- 'olleh'（UTF-8 安全）
SELECT repeat('ab', 3);                                  -- 'ababab'

-- 正则（re2 语法）
SELECT match('abc 123', '[0-9]+');                       -- 1（布尔）
SELECT extract('abc 123 def', '[0-9]+');                  -- '123'
SELECT replaceRegexpAll('abc 123 def', '[0-9]+', '#');   -- 'abc # def'
SELECT replaceRegexpOne('a1b2', '[0-9]', '#');           -- 'a#b2'
SELECT extractAll('a1b2c3', '[0-9]+');                    -- ['1', '2', '3']

-- 分割
SELECT splitByChar(',', 'a,b,c');                        -- ['a', 'b', 'c']
SELECT splitByString(', ', 'a, b, c');                   -- ['a', 'b', 'c']
SELECT splitByRegexp('[,;]', 'a,b;c');                   -- ['a', 'b', 'c']
SELECT arrayStringConcat(['a', 'b', 'c'], ',');          -- 'a,b,c'

-- 编码
SELECT hex(MD5('hello'));                                -- 十六进制字符串（MD5 返回 FixedString(16)）
SELECT sipHash64('hello');                               -- SipHash（快速哈希）
SELECT cityHash64('hello');                              -- CityHash
SELECT base64Encode('hello');
SELECT base64Decode(base64Encode('hello'));
SELECT hex('hello');                                     -- 十六进制
SELECT unhex('68656C6C6F');                              -- 从十六进制

-- 其他
SELECT format('{} has {} items', 'cart', 5);             -- 'cart has 5 items'
SELECT leftPadUTF8('42', 5, '0');                        -- '00042'（UTF-8 安全）
SELECT char(65);                                         -- 'A'
SELECT ASCII('A');                                       -- 65

-- 注意：函数名区分大小写（全部小写开头，驼峰命名）
-- 注意：length 返回字节数，需要字符数用 lengthUTF8
-- 注意：很多函数有 UTF8 后缀的变体
-- 注意：正则使用 re2 语法（不支持反向引用）
