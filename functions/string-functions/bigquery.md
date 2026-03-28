# BigQuery: 字符串函数

> 参考资料:
> - [1] BigQuery SQL Reference - String Functions
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/string_functions
> - [2] BigQuery SQL Reference - Functions Reference
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/functions-and-operators


拼接

```sql
SELECT CONCAT('hello', ' ', 'world');                    -- 'hello world'
SELECT 'hello' || ' ' || 'world';                        -- 'hello world'（SQL 标准）
SELECT FORMAT('%s has %d items', 'cart', 5);              -- 格式化拼接

```

长度

```sql
SELECT LENGTH('hello');                                  -- 5（字符数）
SELECT CHAR_LENGTH('hello');                             -- 5
SELECT BYTE_LENGTH('你好');                               -- 6（UTF-8 字节数）

```

大小写

```sql
SELECT UPPER('hello');                                   -- 'HELLO'
SELECT LOWER('HELLO');                                   -- 'hello'
SELECT INITCAP('hello world');                           -- 'Hello World'

```

截取

```sql
SELECT SUBSTR('hello world', 7, 5);                      -- 'world'
SELECT SUBSTRING('hello world', 7, 5);                   -- 'world'
SELECT LEFT('hello', 3);                                 -- 'hel'
SELECT RIGHT('hello', 3);                                -- 'llo'

```

查找

```sql
SELECT INSTR('hello world', 'world');                    -- 7
SELECT STRPOS('hello world', 'world');                   -- 7
SELECT STARTS_WITH('hello world', 'hello');              -- TRUE
SELECT ENDS_WITH('hello world', 'world');                -- TRUE
SELECT CONTAINS_SUBSTR('hello world', 'WORLD');          -- TRUE（大小写不敏感）

```

替换 / 填充 / 修剪

```sql
SELECT REPLACE('hello world', 'world', 'bq');            -- 'hello bq'
SELECT LPAD('42', 5, '0');                               -- '00042'
SELECT RPAD('hi', 5, '.');                               -- 'hi...'
SELECT TRIM('  hello  ');                                -- 'hello'
SELECT LTRIM('  hello  ');                               -- 'hello  '
SELECT RTRIM('  hello  ');                               -- '  hello'
SELECT TRIM(BOTH 'x' FROM 'xxhelloxx');                  -- 'hello'

```

翻转 / 重复

```sql
SELECT REVERSE('hello');                                 -- 'olleh'
SELECT REPEAT('ab', 3);                                  -- 'ababab'

```

正则

```sql
SELECT REGEXP_CONTAINS('abc 123', r'[0-9]+');            -- TRUE
SELECT REGEXP_EXTRACT('abc 123 def', r'[0-9]+');         -- '123'
SELECT REGEXP_EXTRACT_ALL('a1b2c3', r'[0-9]+');          -- ['1', '2', '3']
SELECT REGEXP_REPLACE('abc 123 def', r'[0-9]+', '#');    -- 'abc # def'
SELECT REGEXP_INSTR('abc 123', r'[0-9]+');               -- 5

```

分割

```sql
SELECT SPLIT('a,b,c', ',');                              -- ['a', 'b', 'c']（返回 ARRAY）
SELECT SPLIT('a,b,c', ',')[OFFSET(0)];                  -- 'a'

```

聚合拼接

```sql
SELECT STRING_AGG(username, ', ' ORDER BY username) FROM users;
SELECT STRING_AGG(DISTINCT city, ', ') FROM users;

```

编码

```sql
SELECT TO_BASE64(b'hello');                              -- 编码
SELECT FROM_BASE64('aGVsbG8=');                          -- 解码
SELECT TO_HEX(b'hello');                                 -- 十六进制
SELECT MD5('hello');                                     -- MD5 哈希（返回 BYTES）
SELECT TO_HEX(MD5('hello'));                             -- MD5 十六进制字符串
SELECT SHA256('hello');                                  -- SHA256 哈希（返回 BYTES）
SELECT TO_HEX(SHA256('hello'));                          -- SHA256 十六进制字符串

```

Unicode

```sql
SELECT UNICODE('A');                                     -- 65
SELECT CHR(65);                                          -- 'A'
SELECT NORMALIZE('hello', NFC);                          -- Unicode 正规化

```

注意：正则使用 re2 语法（r'' 前缀表示原始字符串）
注意：SPLIT 返回 ARRAY<STRING>

