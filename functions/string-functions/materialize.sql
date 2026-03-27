-- Materialize: 字符串函数

-- Materialize 兼容 PostgreSQL 字符串函数

-- 拼接
SELECT 'hello' || ' ' || 'world';
SELECT CONCAT('hello', ' ', 'world');

-- 长度
SELECT LENGTH('hello');
SELECT CHAR_LENGTH('hello');
SELECT OCTET_LENGTH('hello');

-- 大小写
SELECT UPPER('hello');
SELECT LOWER('HELLO');
SELECT INITCAP('hello world');

-- 截取
SELECT SUBSTRING('hello world' FROM 7 FOR 5);
SELECT LEFT('hello', 3);
SELECT RIGHT('hello', 3);

-- 查找
SELECT POSITION('world' IN 'hello world');

-- 替换 / 填充 / 修剪
SELECT REPLACE('hello world', 'world', 'mz');
SELECT LPAD('42', 5, '0');
SELECT RPAD('hi', 5, '.');
SELECT TRIM('  hello  ');
SELECT LTRIM('  hello');
SELECT RTRIM('hello  ');

-- 翻转 / 重复
SELECT REVERSE('hello');
SELECT REPEAT('ab', 3);

-- 正则
SELECT REGEXP_MATCH('abc 123', '\d+');

-- ASCII / CHR
SELECT ASCII('A');
SELECT CHR(65);

-- SPLIT_PART
SELECT SPLIT_PART('a,b,c', ',', 2);

-- 编码
SELECT ENCODE(E'\\xDEAD'::BYTEA, 'hex');
SELECT DECODE('68656C6C6F', 'hex');

-- 聚合拼接
SELECT STRING_AGG(username, ', ') FROM users;

-- 注意：兼容 PostgreSQL 的字符串函数
-- 注意：支持 || 拼接运算符
-- 注意：支持正则表达式函数
