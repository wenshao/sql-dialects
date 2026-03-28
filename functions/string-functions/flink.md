# Flink SQL: 字符串函数

> 参考资料:
> - [Flink SQL Documentation](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/)
> - [Flink SQL - Built-in Functions](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/)
> - [Flink SQL - Data Types](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

```sql
SELECT 'hello' || ' ' || 'world';                    -- 'hello world'
SELECT CONCAT('hello', ' ', 'world');                 -- 'hello world'
SELECT CONCAT_WS(',', 'a', 'b', 'c');                -- 'a,b,c'

```

Length
```sql
SELECT CHAR_LENGTH('hello');                          -- 5 (characters)
SELECT CHARACTER_LENGTH('hello');                     -- 5
SELECT OCTET_LENGTH('你好');                           -- 6 (bytes, UTF-8)
SELECT BIT_LENGTH('hello');                           -- 40

```

Case
```sql
SELECT UPPER('hello');                                -- 'HELLO'
SELECT LOWER('HELLO');                                -- 'hello'
SELECT INITCAP('hello world');                        -- 'Hello World'

```

Substring
```sql
SELECT SUBSTRING('hello world' FROM 7 FOR 5);         -- 'world' (SQL standard)
SELECT SUBSTRING('hello world', 7, 5);                -- 'world'
SELECT SUBSTR('hello world', 7, 5);                   -- 'world' (Flink 1.15+)
SELECT LEFT('hello', 3);                              -- 'hel' (Flink 1.15+)
SELECT RIGHT('hello', 3);                             -- 'llo' (Flink 1.15+)

```

Search
```sql
SELECT POSITION('world' IN 'hello world');            -- 7
SELECT LOCATE('world', 'hello world');                -- 7
SELECT LOCATE('world', 'hello world', 8);             -- 0 (start from position 8)

```

Replace / Pad / Trim
```sql
SELECT REPLACE('hello world', 'world', 'flink');     -- 'hello flink'
SELECT LPAD('42', 5, '0');                            -- '00042'
SELECT RPAD('hi', 5, '.');                            -- 'hi...'
SELECT TRIM('  hello  ');                             -- 'hello'
SELECT LTRIM('  hello  ');                            -- 'hello  '
SELECT RTRIM('  hello  ');                            -- '  hello'
SELECT TRIM(BOTH ' ' FROM '  hello  ');               -- 'hello'
SELECT TRIM(LEADING 'x' FROM 'xxhello');              -- 'hello'
SELECT TRIM(TRAILING 'x' FROM 'helloxx');             -- 'hello'

```

OVERLAY (replace substring at position)
```sql
SELECT OVERLAY('hello world' PLACING 'flink' FROM 7 FOR 5);  -- 'hello flink'

```

Reverse / Repeat
```sql
SELECT REVERSE('hello');                              -- 'olleh' (Flink 1.15+)
SELECT REPEAT('ab', 3);                               -- 'ababab' (Flink 1.15+)

```

Regular expressions
```sql
SELECT REGEXP('abc 123', '[0-9]+');                   -- true (Flink 1.15+)
SELECT REGEXP_EXTRACT('abc 123 def', '(\d+)', 1);    -- '123'
SELECT REGEXP_REPLACE('abc 123 def', '\d+', '#');     -- 'abc # def'

```

String aggregation
```sql
SELECT LISTAGG(username, ', ') FROM users;
SELECT LISTAGG(username) FROM users;                  -- Default: no separator

```

LIKE / SIMILAR TO
```sql
SELECT 'Hello' LIKE 'H%';                            -- true
SELECT 'Hello' LIKE 'h%';                            -- false (case-sensitive)
SELECT 'Hello' SIMILAR TO 'H(e|a)llo';               -- true (SQL regex)
```

Case-insensitive: use LOWER
```sql
SELECT LOWER('Hello') LIKE 'h%';                     -- true

```

Encoding
```sql
SELECT FROM_BASE64('aGVsbG8=');                       -- binary
SELECT TO_BASE64(CAST('hello' AS BYTES));             -- 'aGVsbG8='
SELECT MD5('hello');                                  -- MD5 hash
SELECT SHA1('hello');                                 -- SHA-1 hash
SELECT SHA2('hello', 256);                            -- SHA-256 hash (Flink 1.15+)
SELECT SHA256('hello');                               -- SHA-256 hash (alias)

```

Type conversion
```sql
SELECT CAST(123 AS STRING);                           -- '123'
SELECT CAST('123' AS INT);                            -- 123

```

ASCII / CHR
```sql
SELECT ASCII('A');                                    -- 65
SELECT CHR(65);                                       -- 'A'

```

SPLIT_INDEX (Flink-specific, extract element after splitting)
```sql
SELECT SPLIT_INDEX('a,b,c', ',', 0);                 -- 'a' (0-based)
SELECT SPLIT_INDEX('a,b,c', ',', 1);                 -- 'b'

```

JSON string functions (used with STRING type JSON)
```sql
SELECT JSON_VALUE('{"name":"alice"}', '$.name');      -- 'alice' (Flink 1.15+)

```

Note: No ILIKE; use LOWER() + LIKE for case-insensitive matching
Note: LISTAGG is the string aggregation function (not STRING_AGG)
Note: SPLIT_INDEX is Flink-specific (0-based index)
Note: Regular expressions use Java regex syntax
Note: Some functions added in Flink 1.15+ (LEFT, RIGHT, REVERSE, REPEAT, etc.)
Note: No built-in fuzzy matching (Levenshtein, Soundex)
Note: Use UDFs for advanced string processing not covered by built-ins
