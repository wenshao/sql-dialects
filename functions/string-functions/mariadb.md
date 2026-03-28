# MariaDB: 字符串函数

与 MySQL 基本一致, 几个独有函数

参考资料:
[1] MariaDB Knowledge Base - String Functions
https://mariadb.com/kb/en/string-functions/

## 1. 标准字符串函数

```sql
SELECT CONCAT('Hello', ' ', 'World');
SELECT CONCAT_WS(', ', 'a', 'b', 'c');    -- 'a, b, c'
SELECT LENGTH('Hello');                      -- 字节长度: 5
SELECT CHAR_LENGTH('Hello');                 -- 字符长度: 5
SELECT UPPER('hello'), LOWER('HELLO');
SELECT TRIM('  hello  '), LTRIM('  hello'), RTRIM('hello  ');
SELECT SUBSTRING('Hello World', 7, 5);      -- 'World'
SELECT REPLACE('Hello World', 'World', 'MariaDB');
SELECT REVERSE('Hello');
SELECT REPEAT('ab', 3);                     -- 'ababab'
SELECT LPAD('42', 5, '0'), RPAD('42', 5, '*');
```


## 2. 正则表达式 (PCRE, 10.0.5+)

MariaDB 10.0.5+ 使用 PCRE (Perl Compatible Regular Expressions)
MySQL 8.0+ 使用 ICU 正则引擎
```sql
SELECT 'Hello123' REGEXP '^[A-Za-z]+[0-9]+$';
SELECT REGEXP_REPLACE('abc123def', '[0-9]+', '#');     -- 'abc#def'
SELECT REGEXP_SUBSTR('abc123def456', '[0-9]+');         -- '123'
SELECT REGEXP_INSTR('abc123', '[0-9]');                 -- 4
```


PCRE vs ICU 的差异:
PCRE: 更丰富的语法 (lookahead/lookbehind, 反向引用)
ICU: 更好的 Unicode 支持, 性能更稳定
迁移时: 复杂正则表达式可能不兼容

## 3. 对引擎开发者的启示

正则引擎选择: PCRE vs ICU vs RE2 (Google)
PCRE: 功能最丰富但可能有 ReDoS 风险 (指数回溯)
RE2: 线性时间保证, 但不支持反向引用
ICU: Unicode 一流支持, 适合国际化场景
MariaDB 选择 PCRE 因为功能丰富; MySQL 选择 ICU 因为 Unicode 支持
