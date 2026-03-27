-- Derby: 字符串函数

-- 拼接
SELECT username || ' <' || email || '>' FROM users;
-- 注意：Derby 使用 || 拼接，不支持 CONCAT 函数

-- 长度
SELECT LENGTH('hello') FROM SYSIBM.SYSDUMMY1;        -- 5
SELECT CHAR_LENGTH('hello') FROM SYSIBM.SYSDUMMY1;   -- 5

-- 大小写
SELECT UPPER('hello') FROM SYSIBM.SYSDUMMY1;         -- 'HELLO'
SELECT LOWER('HELLO') FROM SYSIBM.SYSDUMMY1;         -- 'hello'

-- 截取
SELECT SUBSTR('hello world', 7, 5) FROM SYSIBM.SYSDUMMY1;  -- 'world'
SELECT SUBSTR('hello world', 7) FROM SYSIBM.SYSDUMMY1;     -- 'world'

-- 查找
SELECT LOCATE('world', 'hello world') FROM SYSIBM.SYSDUMMY1; -- 7
SELECT LOCATE('world', 'hello world', 3) FROM SYSIBM.SYSDUMMY1; -- 从位置 3 开始

-- 修剪
SELECT TRIM('  hello  ') FROM SYSIBM.SYSDUMMY1;
SELECT TRIM(LEADING ' ' FROM '  hello') FROM SYSIBM.SYSDUMMY1;
SELECT TRIM(TRAILING ' ' FROM 'hello  ') FROM SYSIBM.SYSDUMMY1;
SELECT LTRIM('  hello') FROM SYSIBM.SYSDUMMY1;
SELECT RTRIM('hello  ') FROM SYSIBM.SYSDUMMY1;

-- 替换
SELECT REPLACE('hello world', 'world', 'derby') FROM SYSIBM.SYSDUMMY1;

-- 类型转换
SELECT CHAR(123) FROM SYSIBM.SYSDUMMY1;
SELECT VARCHAR(CURRENT_TIMESTAMP) FROM SYSIBM.SYSDUMMY1;
SELECT CAST(123 AS VARCHAR(10)) FROM SYSIBM.SYSDUMMY1;

-- ============================================================
-- 不支持的字符串函数
-- ============================================================

-- 不支持 CONCAT 函数（使用 ||）
-- 不支持 REVERSE
-- 不支持 REPEAT
-- 不支持 LPAD / RPAD
-- 不支持 INITCAP
-- 不支持正则函数
-- 不支持 GROUP_CONCAT / STRING_AGG

-- 注意：Derby 字符串函数比较有限
-- 注意：使用 || 拼接而非 CONCAT
-- 注意：SYSIBM.SYSDUMMY1 是单行虚拟表
-- 注意：不支持正则表达式
-- 注意：复杂字符串处理建议通过 Java 存储过程
