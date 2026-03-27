-- TDSQL: 字符串函数 (String Functions)
--
-- 参考资料:
--   [1] TDSQL-C MySQL Documentation
--       https://cloud.tencent.com/document/product/1003
--   [2] TDSQL MySQL Documentation
--       https://cloud.tencent.com/document/product/557
--   [3] MySQL 8.0 Reference Manual - String Functions
--       https://dev.mysql.com/doc/refman/8.0/en/string-functions.html
--
-- 说明: TDSQL 是腾讯云分布式数据库，语法与 MySQL 高度兼容。
--       字符串函数行为与 MySQL 完全一致，分布式场景有额外注意事项。

-- ============================================================
-- 1. 字符串拼接
-- ============================================================

-- CONCAT: 拼接字符串，任一参数为 NULL 则结果为 NULL
SELECT CONCAT('hello', ' ', 'world');                  -- 'hello world'
SELECT CONCAT('user', '_', 42);                        -- 'user_42'（数值自动转字符串）
SELECT CONCAT('hello', NULL, 'world');                 -- NULL（NULL 传播!）

-- CONCAT_WS: 带分隔符拼接，跳过 NULL
SELECT CONCAT_WS(',', 'a', 'b', 'c');                 -- 'a,b,c'
SELECT CONCAT_WS(',', 'a', NULL, 'c');                -- 'a,c'（跳过 NULL）
SELECT CONCAT_WS('-', '2024', '01', '15');            -- '2024-01-15'

-- 实践建议: 涉及可能为 NULL 的列时，优先使用 CONCAT_WS

-- ============================================================
-- 2. 长度函数: 字节数 vs 字符数
-- ============================================================

SELECT LENGTH('hello');                                -- 5 (字节数)
SELECT LENGTH('你好');                                 -- 6 (UTF-8 下每个汉字 3 字节)
SELECT CHAR_LENGTH('你好');                            -- 2 (字符数)
SELECT BIT_LENGTH('hello');                           -- 40 (5 字节 × 8 位)
SELECT OCTET_LENGTH('hello');                         -- 5 (同 LENGTH)

-- 注意: LENGTH 返回字节数（MySQL 语义），与 PostgreSQL 的 LENGTH=字符数不同!
-- 跨数据库迁移时建议用 CHAR_LENGTH 统一语义。

-- ============================================================
-- 3. 大小写转换
-- ============================================================

SELECT UPPER('hello');                                -- 'HELLO'
SELECT LOWER('HELLO');                                -- 'hello'
-- 注意: UPPER/LOWER 受 COLLATION 影响，某些字符集下行为可能不同

-- ============================================================
-- 4. 截取函数
-- ============================================================

SELECT SUBSTRING('hello world', 7, 5);                -- 'world'（从第 7 个字符取 5 个）
SELECT SUBSTRING('hello world', -5, 3);               -- 'wor'（负数从末尾计数）
SELECT LEFT('hello', 3);                              -- 'hel'
SELECT RIGHT('hello', 3);                             -- 'llo'
SELECT MID('hello world', 7, 5);                      -- 'world'（MID = SUBSTRING 别名）

-- ============================================================
-- 5. 查找与定位
-- ============================================================

SELECT INSTR('hello world', 'world');                 -- 7（返回起始位置，从 1 开始）
SELECT LOCATE('world', 'hello world');                -- 7（注意参数顺序与 INSTR 相反!）
SELECT LOCATE('l', 'hello world', 4);                 -- 4（从第 4 个字符开始搜索）
SELECT POSITION('world' IN 'hello world');            -- 7（SQL 标准语法）
SELECT FIELD('b', 'a', 'b', 'c');                     -- 2（返回在列表中的位置）

-- ============================================================
-- 6. 替换与填充
-- ============================================================

SELECT REPLACE('hello world', 'world', 'tdsql');      -- 'hello tdsql'
SELECT INSERT('hello world', 7, 5, 'tdsql');          -- 'hello tdsql'（位置替换）
SELECT LPAD('42', 5, '0');                            -- '00042'（左填充）
SELECT RPAD('hi', 5, '.');                            -- 'hi...'（右填充）

-- ============================================================
-- 7. 修剪函数
-- ============================================================

SELECT TRIM('  hello  ');                             -- 'hello'
SELECT TRIM(LEADING '0' FROM '00042');                -- '42'
SELECT TRIM(TRAILING 'x' FROM 'helloxxx');            -- 'hello'
SELECT LTRIM('  hello');                              -- 'hello'
SELECT RTRIM('hello  ');                              -- 'hello'

-- ============================================================
-- 8. 翻转与重复
-- ============================================================

SELECT REVERSE('hello');                              -- 'olleh'
SELECT REPEAT('ab', 3);                               -- 'ababab'
SELECT SPACE(5);                                      -- '     '（5 个空格）

-- ============================================================
-- 9. 正则表达式 (MySQL 8.0+ 兼容)
-- ============================================================

-- TDSQL 兼容 MySQL 8.0 的 ICU 正则引擎
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');  -- 'abc # def'
SELECT REGEXP_SUBSTR('abc 123 def', '[0-9]+');        -- '123'
SELECT REGEXP_INSTR('abc 123 def', '[0-9]+');         -- 5（位置）
SELECT 'hello123' REGEXP '^[a-z]+[0-9]+$';            -- 1 (true)
SELECT REGEXP_LIKE('hello123', '^[a-z]+[0-9]+$');    -- 1 (8.0+ 函数形式)

-- ============================================================
-- 10. 编码与 ASCII 函数
-- ============================================================

SELECT HEX('abc');                                    -- '616263'
SELECT UNHEX('616263');                               -- 'abc'
SELECT ASCII('A');                                    -- 65
SELECT CHAR(65);                                      -- 'A'
SELECT ORD('A');                                      -- 65（多字节字符返回 Unicode 码点）
SELECT CONV('FF', 16, 10);                           -- '255'（进制转换）

-- ============================================================
-- 11. GROUP_CONCAT: 字符串聚合
-- ============================================================

-- 基本用法
SELECT GROUP_CONCAT(username SEPARATOR ', ') FROM users;

-- 带排序与去重
SELECT GROUP_CONCAT(DISTINCT city ORDER BY city SEPARATOR ', ') FROM users;

-- 分组聚合
SELECT department, GROUP_CONCAT(name ORDER BY name SEPARATOR '; ') FROM employees
GROUP BY department;

-- 分布式注意事项:
--   GROUP_CONCAT 在跨分片查询时由 TDSQL 代理层合并
--   默认长度限制: group_concat_max_len = 1024（需按需调大）
--   跨分片 GROUP_CONCAT 可能不保序（建议显式 ORDER BY）

-- ============================================================
-- 12. 格式化函数
-- ============================================================

SELECT FORMAT(1234567.89, 2);                        -- '1,234,567.89'（千分位）
SELECT FORMAT(1234567.89, 2, 'de_DE');               -- '1.234.567,89'（德语格式）
SELECT QUOTE("O'Reilly");                             -- "'O\\'Reilly'"（转义引号）

-- ============================================================
-- 13. 分布式环境注意事项
-- ============================================================

-- 1. 字符串函数本身在各分片独立执行，无跨分片问题
-- 2. GROUP_CONCAT 跨分片需合并，注意长度限制和排序
-- 3. REGEXP 函数在各分片独立执行，确保分片 MySQL 版本一致
-- 4. COLLATION 应在各分片保持一致，否则拼接/比较结果可能不同
-- 5. 字符集建议统一使用 utf8mb4（支持完整 Unicode）

-- ============================================================
-- 14. 版本兼容性
-- ============================================================
-- MySQL 5.7 / TDSQL: 基础字符串函数完备
-- MySQL 8.0 / TDSQL: REGEXP_REPLACE/REGEXP_SUBSTR (ICU 正则引擎)
--   如果 TDSQL 版本基于 MySQL 5.7，正则功能受限（仅 REGEXP 匹配）
-- 建议确认 TDSQL 底层 MySQL 版本以确定可用函数范围
