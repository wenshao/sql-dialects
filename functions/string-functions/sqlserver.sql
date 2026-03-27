-- SQL Server: 字符串函数
--
-- 参考资料:
--   [1] SQL Server T-SQL - String Functions
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/string-functions-transact-sql

-- ============================================================
-- 1. 字符串拼接: + vs CONCAT
-- ============================================================

SELECT 'hello' + ' ' + 'world';                  -- + 运算符
SELECT CONCAT('hello', ' ', 'world');              -- CONCAT（2012+, NULL 安全）
SELECT CONCAT_WS(',', 'a', 'b', 'c');             -- 带分隔符（2017+）

-- 关键差异（对引擎开发者）:
--   + 运算符: 任一参数为 NULL 则结果为 NULL
--   CONCAT:   NULL 被视为空字符串（不影响结果）
-- 这是 SQL Server 中最常见的 NULL 相关 bug 来源。
-- 示例: first_name + ' ' + last_name → 如果 last_name 为 NULL，整个表达式为 NULL
--
-- 横向对比:
--   PostgreSQL: || 运算符（NULL 传播），CONCAT（NULL 安全）
--   MySQL:      CONCAT（NULL 传播！与 SQL Server 的 CONCAT 行为相反）
--   Oracle:     || 运算符（NULL 被视为空字符串——Oracle 独有行为）

-- ============================================================
-- 2. 长度函数
-- ============================================================

SELECT LEN('hello');                     -- 5（字符数，不含尾部空格）
SELECT DATALENGTH('hello');              -- 5（字节数，VARCHAR）
SELECT DATALENGTH(N'hello');             -- 10（字节数，NVARCHAR = UTF-16，每字符 2 字节）
SELECT DATALENGTH(N'你好');               -- 4（NVARCHAR, 2 个字符 × 2 字节）

-- LEN 的尾部空格行为:
SELECT LEN('hello   ');                  -- 5（自动忽略尾部空格）
SELECT DATALENGTH('hello   ');           -- 8（包含尾部空格）
-- 这是 SQL Server 独有行为——大多数数据库的长度函数计算尾部空格

-- 横向对比:
--   PostgreSQL: LENGTH('hello   ') = 8（计算尾部空格）
--   MySQL:      CHAR_LENGTH('hello   ') = 8（计算尾部空格）

-- ============================================================
-- 3. 截取与查找
-- ============================================================

SELECT SUBSTRING('hello world', 7, 5);   -- 'world'
SELECT LEFT('hello', 3);                 -- 'hel'
SELECT RIGHT('hello', 3);               -- 'llo'
SELECT CHARINDEX('world', 'hello world');-- 7（位置，从 1 开始）
SELECT PATINDEX('%[0-9]%', 'abc123');    -- 4（正则模式匹配位置）

-- ============================================================
-- 4. 替换与填充
-- ============================================================

SELECT REPLACE('hello world', 'world', 'sql');      -- 'hello sql'
SELECT STUFF('hello world', 7, 5, 'sql');            -- 'hello sql'（按位置替换）

-- SQL Server 没有 LPAD/RPAD 函数（几乎所有其他数据库都有）
-- 必须手动模拟:
SELECT RIGHT('00000' + '42', 5);                     -- '00042'（模拟 LPAD）
SELECT LEFT('42' + '00000', 5);                      -- '42000'（模拟 RPAD）
-- 横向对比:
--   PostgreSQL: LPAD('42', 5, '0') → '00042'
--   MySQL:      LPAD('42', 5, '0') → '00042'
--   Oracle:     LPAD('42', 5, '0') → '00042'
-- SQL Server 是唯一没有 LPAD/RPAD 的主流数据库

-- ============================================================
-- 5. 修剪
-- ============================================================

SELECT TRIM('  hello  ');                -- 'hello'（2017+）
SELECT LTRIM('  hello');                 -- 'hello'
SELECT RTRIM('hello  ');                 -- 'hello'

-- 2017+ TRIM 支持指定字符:
SELECT TRIM('xy' FROM 'xyhelloxy');      -- 'hello'

-- ============================================================
-- 6. 其他字符串函数
-- ============================================================

SELECT UPPER('hello');                   -- 'HELLO'
SELECT LOWER('HELLO');                   -- 'hello'
SELECT REVERSE('hello');                 -- 'olleh'
SELECT REPLICATE('ab', 3);              -- 'ababab'（等价于 REPEAT）
SELECT TRANSLATE('hello', 'helo', 'HELO'); -- 'HELLO'（2017+, 逐字符替换）

-- ============================================================
-- 7. STRING_SPLIT: 拆分字符串为行（2016+）
-- ============================================================

SELECT value FROM STRING_SPLIT('a,b,c', ',');

-- 2022+: 带序号（ordinal 参数）
SELECT value, ordinal FROM STRING_SPLIT('a,b,c', ',', 1) ORDER BY ordinal;

-- 设计分析（对引擎开发者）:
--   STRING_SPLIT 是表值函数——返回表而非标量值。
--   这在 SQL Server 中通过 CROSS APPLY 使用:
--   SELECT t.id, s.value FROM tags t CROSS APPLY STRING_SPLIT(t.tags, ',') s;
--
--   2016 版本的 STRING_SPLIT 不保证顺序——这是一个设计缺陷，2022 修复了。
--
-- 横向对比:
--   PostgreSQL: string_to_array() + unnest()（或 regexp_split_to_table()）
--   MySQL:      无内置函数（需要递归 CTE 或存储过程）
--   Oracle:     无内置函数（需要 REGEXP_SUBSTR + CONNECT BY LEVEL）

-- ============================================================
-- 8. STRING_AGG: 行聚合为字符串（2017+）
-- ============================================================

SELECT STRING_AGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;

-- 分组聚合:
SELECT city, STRING_AGG(username, ', ') WITHIN GROUP (ORDER BY username) AS members
FROM users GROUP BY city;

-- ============================================================
-- 9. FORMAT: 通用格式化（2012+, CLR 实现）
-- ============================================================

SELECT FORMAT(123456.789, 'N2');          -- '123,456.79'
SELECT QUOTENAME('table name');          -- '[table name]'
SELECT QUOTENAME('table name', '"');     -- '"table name"'

-- FORMAT 性能警告: 基于 .NET CLR，逐行调用非常慢。
-- 对大数据集避免使用 FORMAT，改用 CONVERT 或 STR。

-- 版本演进:
-- 2005+ : CHARINDEX, PATINDEX, STUFF, REPLACE, LEN
-- 2012+ : CONCAT, FORMAT
-- 2016+ : STRING_SPLIT
-- 2017+ : STRING_AGG, CONCAT_WS, TRIM, TRANSLATE
-- 2022+ : STRING_SPLIT 带 ordinal
