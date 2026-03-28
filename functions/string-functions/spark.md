# Spark SQL: 字符串函数 (String Functions)

> 参考资料:
> - [1] Spark SQL - Built-in String Functions
>   https://spark.apache.org/docs/latest/sql-ref-functions-builtin.html#string-functions


## 1. 拼接

```sql
SELECT CONCAT('hello', ' ', 'world');                    -- 'hello world' (NULL-safe)
SELECT CONCAT_WS(',', 'a', 'b', 'c');                   -- 'a,b,c' (跳过 NULL)
SELECT 'hello' || ' ' || 'world';                        -- Spark 2.4+

```

 CONCAT 的 NULL 处理:
   Spark:      CONCAT('a', NULL, 'b') = 'ab'（跳过 NULL）
   MySQL:      CONCAT('a', NULL, 'b') = NULL（任何 NULL 导致结果 NULL）
PostgreSQL: 'a' || NULL || 'b' = NULL（与 MySQL 一致）
 这是重要的行为差异——从 MySQL 迁移到 Spark 时，CONCAT 的 NULL 处理不同

## 2. 长度

```sql
SELECT LENGTH('hello');                                  -- 5 (字符数)
SELECT CHAR_LENGTH('hello');                             -- 5
SELECT OCTET_LENGTH('你好');                              -- 6 (UTF-8 字节数)
SELECT BIT_LENGTH('hello');                              -- 40

```

## 3. 大小写

```sql
SELECT UPPER('hello');                                   -- 'HELLO'
SELECT LOWER('HELLO');                                   -- 'hello'
SELECT INITCAP('hello world');                           -- 'Hello World'

```

## 4. 子串

```sql
SELECT SUBSTRING('hello world', 7, 5);                   -- 'world'
SELECT SUBSTRING('hello world' FROM 7 FOR 5);            -- SQL 标准语法
SELECT SUBSTR('hello world', 7, 5);                      -- 别名
SELECT LEFT('hello', 3);                                 -- 'hel'
SELECT RIGHT('hello', 3);                                -- 'llo'

```

## 5. 搜索

```sql
SELECT POSITION('world' IN 'hello world');               -- 7 (SQL 标准)
SELECT INSTR('hello world', 'world');                    -- 7
SELECT LOCATE('world', 'hello world');                   -- 7
SELECT LOCATE('world', 'hello world', 8);                -- 0 (从位置 8 开始搜索)

```

## 6. 替换 / 填充 / 修剪

```sql
SELECT REPLACE('hello world', 'world', 'spark');         -- 'hello spark'
SELECT LPAD('42', 5, '0');                               -- '00042'
SELECT RPAD('hi', 5, '.');                               -- 'hi...'
SELECT TRIM('  hello  ');                                -- 'hello'
SELECT LTRIM('  hello  ');                               -- 'hello  '
SELECT RTRIM('  hello  ');                               -- '  hello'
SELECT TRIM(BOTH 'x' FROM 'xxhelloxx');                  -- 'hello' (SQL 标准)
SELECT BTRIM('xxhelloxx', 'x');                          -- 'hello' (Spark 3.0+)
SELECT OVERLAY('hello world' PLACING 'spark' FROM 7 FOR 5); -- 'hello spark'
SELECT REVERSE('hello');                                 -- 'olleh'
SELECT REPEAT('ab', 3);                                  -- 'ababab'

```

## 7. 正则表达式

```sql
SELECT 'abc 123' RLIKE '[0-9]+';                         -- true
SELECT REGEXP_EXTRACT('abc 123 def', '(\\d+)', 1);       -- '123'
SELECT REGEXP_REPLACE('abc 123 def', '\\d+', '#');       -- 'abc # def'
SELECT REGEXP_LIKE('abc 123', '\\d+');                   -- true (3.2+)
SELECT REGEXP_COUNT('a1b2c3', '\\d');                    -- 3 (3.4+)
SELECT REGEXP_SUBSTR('abc 123 def', '\\d+');             -- '123' (3.4+)
SELECT REGEXP_INSTR('abc 123 def', '\\d+');              -- 5 (3.4+)

```

 Spark 使用 Java 正则语法（需要双反斜杠转义）:
   \\d  = 数字
   \\s  = 空白字符
   \\b  = 单词边界
 对比 PostgreSQL: 使用 POSIX 正则（~ 操作符，单反斜杠）

## 8. 字符串聚合（替代 STRING_AGG / GROUP_CONCAT）

```sql
SELECT CONCAT_WS(', ', COLLECT_LIST(username)) FROM users;
```

排序后拼接:

```sql
SELECT CONCAT_WS(', ', SORT_ARRAY(COLLECT_LIST(username))) FROM users;

```

 对比:
   MySQL:      GROUP_CONCAT(username ORDER BY username SEPARATOR ', ')
   PostgreSQL: STRING_AGG(username, ', ' ORDER BY username)
   BigQuery:   STRING_AGG(username, ', ' ORDER BY username)
   Spark:      CONCAT_WS + COLLECT_LIST + SORT_ARRAY（三步组合）

## 9. 分割

```sql
SELECT SPLIT('a.b.c', '\\.');                            -- ['a', 'b', 'c'] (正则)
SELECT SPLIT('a,b,c', ',');                              -- ['a', 'b', 'c']
SELECT SENTENCES('Hello World. How are you?');           -- [['Hello','World'],...]

```

## 10. 编码与哈希

```sql
SELECT BASE64(CAST('hello' AS BINARY));                  -- 'aGVsbG8='
SELECT UNBASE64('aGVsbG8=');
SELECT HEX('hello');                                     -- '68656C6C6F'
SELECT MD5('hello');
SELECT SHA1('hello');
SELECT SHA2('hello', 256);                               -- SHA-256
SELECT SOUNDEX('hello');                                 -- 语音哈希
SELECT LEVENSHTEIN('kitten', 'sitting');                  -- 3 (编辑距离)
SELECT ASCII('A');                                       -- 65
SELECT CHR(65);                                          -- 'A'

```

## 11. 格式化与 URL

```sql
SELECT FORMAT_STRING('%s is %d years old', 'Alice', 25);
SELECT PRINTF('%s is %d years old', 'Alice', 25);        -- Spark 3.5+
SELECT TRANSLATE('hello', 'helo', 'HELO');               -- 'HELLO'
SELECT PARSE_URL('http://example.com/path?q=1', 'HOST');  -- 'example.com'
SELECT URL_ENCODE('hello world');                        -- Spark 3.4+
SELECT URL_DECODE('hello+world');                        -- Spark 3.4+

```

## 12. LIKE / RLIKE

```sql
SELECT 'Hello' LIKE 'H%';                               -- true
SELECT 'Hello' LIKE 'h%';                               -- false (大小写敏感)
SELECT LOWER('Hello') LIKE 'h%';                         -- true (手动不敏感)
SELECT 'Hello' RLIKE '(?i)h.*';                          -- true (正则不敏感)

```

 无 ILIKE（大小写不敏感 LIKE）:
 对比 PostgreSQL: ILIKE 是内置关键字
 Spark 必须用 LOWER(col) LIKE pattern 或 RLIKE '(?i)pattern'

## 13. 版本演进

Spark 2.0: 基本字符串函数（继承 Hive）
| Spark 2.4: || 运算符 |
|------|------|------|
Spark 3.0: BTRIM
Spark 3.2: REGEXP_LIKE
Spark 3.4: REGEXP_COUNT/SUBSTR/INSTR, URL_ENCODE/DECODE
Spark 3.5: PRINTF

限制:
无 ILIKE（大小写不敏感 LIKE）
正则使用 Java 语法（双反斜杠）
SPLIT 使用正则（特殊字符需转义: '\\.' 而非 '.'）
CONCAT 的 NULL 处理与 MySQL 不同（Spark 跳过 NULL）
无 STRING_AGG（使用 COLLECT_LIST + CONCAT_WS 组合）
SENTENCES 是 Spark/Hive 独有的自然语言分词函数

