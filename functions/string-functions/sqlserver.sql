-- SQL Server: 字符串函数
--
-- 参考资料:
--   [1] SQL Server T-SQL - String Functions
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/string-functions-transact-sql
--   [2] SQL Server T-SQL - LIKE
--       https://learn.microsoft.com/en-us/sql/t-sql/language-elements/like-transact-sql

-- 拼接
SELECT 'hello' + ' ' + 'world';                      -- 'hello world'
SELECT CONCAT('hello', ' ', 'world');                 -- 'hello world'（2012+，NULL 安全）
SELECT CONCAT_WS(',', 'a', 'b', 'c');                -- 'a,b,c'（2017+）
-- 注意：+ 拼接时，任一参数为 NULL 则结果为 NULL

-- 长度
SELECT LEN('hello');                                  -- 5（不含尾部空格）
SELECT DATALENGTH('hello');                           -- 5（字节数）
SELECT DATALENGTH(N'你好');                            -- 4（NVARCHAR 每字符 2 字节）

-- 大小写
SELECT UPPER('hello');                                -- 'HELLO'
SELECT LOWER('HELLO');                                -- 'hello'

-- 截取
SELECT SUBSTRING('hello world', 7, 5);                -- 'world'
SELECT LEFT('hello', 3);                              -- 'hel'
SELECT RIGHT('hello', 3);                             -- 'llo'

-- 查找
SELECT CHARINDEX('world', 'hello world');              -- 7
SELECT PATINDEX('%[0-9]%', 'abc123');                  -- 4（模式匹配位置）

-- 替换 / 填充 / 修剪
SELECT REPLACE('hello world', 'world', 'sql');        -- 'hello sql'
SELECT STUFF('hello world', 7, 5, 'sql');             -- 'hello sql'（按位置替换）
-- 注意：没有 LPAD/RPAD，需要手动实现
SELECT RIGHT('00000' + '42', 5);                      -- '00042'（模拟 LPAD）
SELECT TRIM('  hello  ');                             -- 'hello'（2017+）
SELECT LTRIM('  hello');                              -- 'hello'
SELECT RTRIM('hello  ');                              -- 'hello'

-- 翻转 / 重复
SELECT REVERSE('hello');                              -- 'olleh'
SELECT REPLICATE('ab', 3);                            -- 'ababab'

-- 2017+: TRANSLATE（逐字符替换）
SELECT TRANSLATE('hello', 'helo', 'HELO');            -- 'HELLO'

-- 2017+: STRING_AGG（聚合拼接）
SELECT STRING_AGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;

-- 2016+: STRING_SPLIT（拆分字符串）
SELECT value FROM STRING_SPLIT('a,b,c', ',');

-- 格式化
SELECT FORMAT(123456.789, 'N2');                       -- '123,456.79'（2012+）
SELECT QUOTENAME('table name');                        -- '[table name]'
