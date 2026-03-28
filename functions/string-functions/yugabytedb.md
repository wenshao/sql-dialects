# YugabyteDB: 字符串函数

> 参考资料:
> - [YugabyteDB YSQL Reference](https://docs.yugabyte.com/stable/api/ysql/)
> - [YugabyteDB PostgreSQL Compatibility](https://docs.yugabyte.com/stable/explore/ysql-language-features/)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识。

```sql
SELECT 'hello' || ' ' || 'world';                    -- 'hello world'
SELECT CONCAT('hello', ' ', 'world');                 -- NULL-safe
SELECT CONCAT_WS(',', 'a', 'b', 'c');                -- 'a,b,c'

```

Length
```sql
SELECT LENGTH('hello');                               -- 5 (characters)
SELECT OCTET_LENGTH('hello');                         -- 5 (bytes)
SELECT CHAR_LENGTH('hello');                          -- 5
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
SELECT SUBSTRING('hello world' FROM 7 FOR 5);         -- 'world'
SELECT SUBSTR('hello world', 7, 5);                   -- 'world'
SELECT LEFT('hello', 3);                              -- 'hel'
SELECT RIGHT('hello', 3);                             -- 'llo'

```

Search
```sql
SELECT POSITION('world' IN 'hello world');            -- 7
SELECT STRPOS('hello world', 'world');                -- 7

```

Replace / Pad / Trim
```sql
SELECT REPLACE('hello world', 'world', 'yb');         -- 'hello yb'
SELECT LPAD('42', 5, '0');                            -- '00042'
SELECT RPAD('hi', 5, '.');                            -- 'hi...'
SELECT TRIM('  hello  ');                             -- 'hello'
SELECT TRIM(BOTH 'x' FROM 'xxhelloxx');               -- 'hello'
SELECT BTRIM('xxhelloxx', 'x');                       -- 'hello'
SELECT LTRIM('  hello');                              -- 'hello'
SELECT RTRIM('hello  ');                              -- 'hello'

```

Reverse / Repeat
```sql
SELECT REVERSE('hello');                              -- 'olleh'
SELECT REPEAT('ab', 3);                               -- 'ababab'

```

Regular expressions (same as PostgreSQL)
```sql
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');  -- 'abc # def'
SELECT SUBSTRING('abc 123 def' FROM '[0-9]+');        -- '123'

```

String aggregation
```sql
SELECT STRING_AGG(username, ', ' ORDER BY username) FROM users;

```

Split
```sql
SELECT SPLIT_PART('a.b.c', '.', 2);                  -- 'b'
SELECT STRING_TO_ARRAY('a,b,c', ',');                 -- {a,b,c}

```

Encoding
```sql
SELECT MD5('hello');
SELECT ENCODE('hello'::BYTEA, 'base64');
SELECT DECODE('aGVsbG8=', 'base64');
SELECT ENCODE('hello'::BYTEA, 'hex');

```

Other
```sql
SELECT TRANSLATE('hello', 'helo', 'HELO');            -- 'HELLO'
SELECT OVERLAY('hello world' PLACING 'YB' FROM 7 FOR 5);  -- 'hello YB'
SELECT ASCII('A');                                    -- 65
SELECT CHR(65);                                       -- 'A'
SELECT QUOTE_LITERAL('hello');                        -- '''hello'''
SELECT QUOTE_IDENT('my column');                      -- '"my column"'

```

Note: All PostgreSQL string functions supported
Note: || is the standard concatenation operator
Note: CONCAT handles NULL gracefully
Note: Based on PostgreSQL 11.2 string function set
Note: REGEXP_SUBSTR/REGEXP_COUNT not available (PG 15+ features)
