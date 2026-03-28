# MaxCompute (ODPS): 字符串函数

> 参考资料:
> - [1] MaxCompute SQL - String Functions
>   https://help.aliyun.com/zh/maxcompute/user-guide/string-functions
> - [2] MaxCompute Built-in Functions
>   https://help.aliyun.com/zh/maxcompute/user-guide/built-in-functions-overview


## 1. 拼接


```sql
SELECT CONCAT('hello', ' ', 'world');       -- 'hello world'
SELECT CONCAT_WS(',', 'a', 'b', 'c');      -- 'a,b,c'（带分隔符）
SELECT CONCAT_WS(',', tags) FROM users;     -- 数组→字符串（ARRAY 版本）

```

注意: 不支持 || 拼接运算符（PostgreSQL/Oracle 标准）
 对比:
   MaxCompute: CONCAT(a, b)（函数式）
PostgreSQL: a || b（运算符，标准 SQL）
   MySQL:      CONCAT(a, b)（函数式）
BigQuery:   CONCAT(a, b) 或 a || b（两者都支持）

## 2. 长度（字节 vs 字符陷阱!）


```sql
SELECT LENGTH('hello');                     -- 5（字节数!）
SELECT LENGTH('你好');                       -- 6（3 字节/字符 x 2）
SELECT CHAR_LENGTH('hello');                -- 5（字符数，2.0+）
SELECT CHAR_LENGTH('你好');                  -- 2（字符数）
SELECT LENGTHB('你好');                      -- 6（显式字节长度）

```

 迁移陷阱: MySQL/PostgreSQL 的 LENGTH 返回字符数
   MaxCompute LENGTH = MySQL OCTET_LENGTH = PostgreSQL LENGTH 的字节语义
   用 CHAR_LENGTH 代替 LENGTH 获取字符数

## 3. 大小写转换


```sql
SELECT UPPER('hello');                      -- 'HELLO'
SELECT LOWER('HELLO');                      -- 'hello'
SELECT INITCAP('hello world');              -- 'Hello World'

```

 MaxCompute 字符串比较默认大小写敏感
 对比 MySQL: 默认大小写不敏感（utf8mb4_general_ci）

## 4. 截取


```sql
SELECT SUBSTR('hello world', 7, 5);         -- 'world'（位置从 1 开始）
SELECT SUBSTRING('hello world', 7, 5);      -- 'world'（2.0+ 别名）
SELECT SUBSTR('hello world', 7);            -- 'world'（到末尾）
SELECT SUBSTR('hello world', -5);           -- 'world'（负数=从末尾）

```

 对比: 位置从 0 还是 1 开始?
   MaxCompute SUBSTR: 从 1 开始（Oracle/SQL 标准）
   MaxCompute ARRAY: 从 0 开始（Java/Hive 风格）
   不一致 — 用户需要注意

## 5. 查找


```sql
SELECT INSTR('hello world', 'world');       -- 7（位置从 1 开始）
SELECT LOCATE('world', 'hello world');      -- 7（参数顺序相反!）

```

 INSTR vs LOCATE 参数顺序:
   INSTR(haystack, needle) — Oracle 风格
   LOCATE(needle, haystack) — MySQL/SQL 标准风格
   MaxCompute 同时支持两者

## 6. 替换 / 填充 / 修剪


```sql
SELECT REPLACE('hello world', 'world', 'mc');  -- 'hello mc'
SELECT LPAD('42', 5, '0');                     -- '00042'（左填充）
SELECT RPAD('hi', 5, '.');                     -- 'hi...'（右填充）
SELECT TRIM('  hello  ');                      -- 'hello'
SELECT LTRIM('  hello  ');                     -- 'hello  '
SELECT RTRIM('  hello  ');                     -- '  hello'
SELECT REVERSE('hello');                       -- 'olleh'
SELECT REPEAT('ab', 3);                        -- 'ababab'

```

## 7. 正则表达式（Java 正则语法）


```sql
SELECT REGEXP_EXTRACT('abc 123 def', '[0-9]+', 0);   -- '123'（提取匹配）
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');  -- 'abc # def'
SELECT REGEXP_COUNT('a1b2c3', '[0-9]');               -- 3（匹配计数）
SELECT REGEXP_INSTR('abc 123', '[0-9]+');             -- 5（匹配位置，2.0+）

```

RLIKE / REGEXP: 正则匹配判断

```sql
SELECT * FROM users WHERE email RLIKE '^[a-z]+@[a-z]+\\.com$';

```

 正则语法: Java java.util.regex
   \\d: 数字（SQL 字符串中反斜杠需要转义）
   (?i): 大小写不敏感标志
   对比 PostgreSQL: POSIX 正则（~ 运算符）
   对比 MySQL: 正则语法类似但转义规则不同

## 8. 分割


```sql
SELECT SPLIT('a,b,c', ',');                 -- ARRAY<STRING>: ['a','b','c']
SELECT SPLIT_PART('a.b.c', '.', 2);        -- 'b'（取第 N 个部分）

```

SPLIT 返回 ARRAY，通常配合 EXPLODE 展开:

```sql
SELECT t.tag
FROM (SELECT 'a,b,c' AS tags) src
LATERAL VIEW EXPLODE(SPLIT(src.tags, ',')) t AS tag;

```

## 9. 编码与哈希


```sql
SELECT MD5('hello');                        -- MD5 哈希（32 位十六进制）
SELECT SHA1('hello');                       -- SHA-1 哈希
SELECT SHA2('hello', 256);                  -- SHA-256 哈希
SELECT TO_BASE64('hello');                  -- Base64 编码
SELECT FROM_BASE64(TO_BASE64('hello'));     -- Base64 解码

```

URL 处理

```sql
SELECT PARSE_URL('http://example.com/path?k=v', 'HOST');  -- 'example.com'
SELECT URL_ENCODE('hello world');           -- 'hello+world'
SELECT URL_DECODE('hello+world');           -- 'hello world'

```

## 10. 其他函数


```sql
SELECT TRANSLATE('hello', 'helo', 'HELO');  -- 'HELLO'（逐字符替换）
SELECT SPACE(5);                            -- '     '（N 个空格）
SELECT ASCII('A');                          -- 65
SELECT CHR(65);                             -- 'A'（2.0+）

```

聚合拼接

```sql
SELECT WM_CONCAT(',', username) FROM users; -- 字符串聚合（无序!）

```

## 11. 横向对比: 字符串函数


 拼接运算符:
MaxCompute: CONCAT()（无 ||）   | PostgreSQL: || 和 CONCAT()
MySQL:      CONCAT()（无 ||）   | BigQuery: || 和 CONCAT()
Oracle:     || 和 CONCAT()

 LENGTH 语义:
MaxCompute: 字节数（Hive 兼容） | PostgreSQL: 字符数
MySQL:      字符数              | BigQuery: 字符数
   Oracle:     字节数（LENGTHB）或字符数（LENGTH）

 字符串聚合:
MaxCompute: WM_CONCAT（无序）   | PostgreSQL: STRING_AGG（有序）
MySQL:      GROUP_CONCAT（有序）| BigQuery: STRING_AGG（有序）

 正则语法:
MaxCompute: Java 正则（RLIKE）  | PostgreSQL: POSIX 正则（~）
MySQL:      Java 正则（REGEXP） | BigQuery: RE2 正则

## 12. 对引擎开发者的启示


1. LENGTH 的字节/字符语义是经典的迁移陷阱 — 应明确命名（LEN vs OCTET_LENGTH）

2. || 拼接运算符是 SQL 标准 — 不支持会让用户不便

3. 正则引擎的选择（Java/POSIX/RE2/PCRE）影响功能和性能

4. SPLIT + EXPLODE 是 ETL 中的高频操作 — 性能应优先优化

5. 字符串聚合必须支持 ORDER BY — WM_CONCAT 的无序是设计缺陷

6. URL/JSON/Base64 处理函数在数据工程中使用频率越来越高

