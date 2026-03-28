# Databricks SQL: 字符串函数

> 参考资料:
> - [Databricks SQL Language Reference](https://docs.databricks.com/en/sql/language-manual/index.html)
> - [Databricks SQL - Built-in Functions](https://docs.databricks.com/en/sql/language-manual/sql-ref-functions-builtin.html)
> - [Delta Lake Documentation](https://docs.delta.io/latest/index.html)


拼接
```sql
SELECT 'hello' || ' ' || 'world';                    -- 'hello world'
SELECT CONCAT('hello', ' ', 'world');                 -- 'hello world'（NULL 安全）
SELECT CONCAT_WS(',', 'a', 'b', 'c');                -- 'a,b,c'（带分隔符，跳过 NULL）
```


长度
```sql
SELECT LENGTH('hello');                               -- 5
SELECT CHAR_LENGTH('hello');                          -- 5
SELECT CHARACTER_LENGTH('hello');                     -- 5
SELECT OCTET_LENGTH('你好');                           -- 6（UTF-8 字节数）
SELECT BIT_LENGTH('hello');                           -- 40
```


大小写
```sql
SELECT UPPER('hello');                                -- 'HELLO'
SELECT LOWER('HELLO');                                -- 'hello'
SELECT INITCAP('hello world');                        -- 'Hello World'
```


截取
```sql
SELECT SUBSTRING('hello world', 7, 5);                -- 'world'
SELECT SUBSTR('hello world', 7, 5);                   -- 'world'
SELECT LEFT('hello', 3);                              -- 'hel'
SELECT RIGHT('hello', 3);                             -- 'llo'
```


查找
```sql
SELECT POSITION('world' IN 'hello world');            -- 7
SELECT INSTR('hello world', 'world');                 -- 7
SELECT LOCATE('world', 'hello world');                -- 7
SELECT LOCATE('o', 'hello world', 6);                 -- 8（从位置 6 开始）
```


替换 / 填充 / 修剪
```sql
SELECT REPLACE('hello world', 'world', 'databricks'); -- 'hello databricks'
SELECT LPAD('42', 5, '0');                            -- '00042'
SELECT RPAD('hi', 5, '.');                            -- 'hi...'
SELECT TRIM('  hello  ');                             -- 'hello'
SELECT LTRIM('  hello');                              -- 'hello'
SELECT RTRIM('hello  ');                              -- 'hello'
SELECT TRIM(BOTH 'x' FROM 'xxhelloxx');               -- 'hello'
SELECT BTRIM('xxhelloxx', 'x');                       -- 'hello'
```


翻转 / 重复
```sql
SELECT REVERSE('hello');                              -- 'olleh'
SELECT REPEAT('ab', 3);                               -- 'ababab'
```


正则表达式
```sql
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');  -- 'abc # def'
SELECT REGEXP_EXTRACT('abc 123 def', '([0-9]+)', 1);  -- '123'
SELECT REGEXP_EXTRACT_ALL('a1b2c3', '([0-9])', 1);    -- ['1','2','3']
SELECT REGEXP_COUNT('a1b2c3', '[0-9]');               -- 3
SELECT REGEXP_LIKE('abc123', '[a-z]+[0-9]+');         -- true
SELECT REGEXP_INSTR('abc 123', '[0-9]+');             -- 5
```


分割
```sql
SELECT SPLIT('a,b,c', ',');                           -- ['a','b','c']（返回 ARRAY）
SELECT SPLIT('a,b,c', ',')[0];                        -- 'a'
SELECT SPLIT_PART('a.b.c', '.', 2);                   -- 'b'
```


字符串聚合
```sql
SELECT CONCAT_WS(', ', COLLECT_LIST(username)) FROM users;
-- 或
SELECT ARRAY_JOIN(COLLECT_LIST(username), ', ') FROM users;
```


分组聚合
```sql
SELECT city, ARRAY_JOIN(COLLECT_LIST(username), ', ') AS user_list
FROM users GROUP BY city;
```


Base64 编码
```sql
SELECT BASE64(CAST('hello' AS BINARY));               -- 编码
SELECT CAST(UNBASE64('aGVsbG8=') AS STRING);          -- 解码
```


哈希
```sql
SELECT MD5('hello');
SELECT SHA1('hello');
SELECT SHA2('hello', 256);
```


其他
```sql
SELECT TRANSLATE('hello', 'helo', 'HELO');            -- 'HELLO'
SELECT SOUNDEX('hello');                              -- 语音编码
SELECT LEVENSHTEIN('hello', 'hallo');                 -- 1（编辑距离）
SELECT OVERLAY('hello world' PLACING 'databricks' FROM 7); -- 'hello databricks'
SELECT FORMAT_STRING('Name: %s, Age: %d', 'alice', 25); -- 格式化字符串
```


URL 函数
```sql
SELECT URL_ENCODE('hello world');                     -- 'hello+world'
SELECT URL_DECODE('hello+world');                     -- 'hello world'
SELECT PARSE_URL('https://example.com/path?q=1', 'HOST');  -- 'example.com'
```


注意：Databricks 支持非常丰富的字符串函数
注意：REGEXP_EXTRACT_ALL 返回数组
注意：SPLIT 返回数组类型
注意：LEVENSHTEIN 用于模糊匹配（编辑距离）
注意：COLLECT_LIST + ARRAY_JOIN 用于字符串聚合
注意：正则使用 Java 正则语法
