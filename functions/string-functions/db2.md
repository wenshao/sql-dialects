# IBM Db2: String Functions

> 参考资料:
> - [Db2 SQL Reference](https://www.ibm.com/docs/en/db2/11.5?topic=sql)
> - [Db2 Built-in Functions](https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in)
> - Concatenation

```sql
SELECT 'hello' || ' ' || 'world';                         -- 'hello world'
SELECT CONCAT('hello', ' world');                          -- 'hello world' (two args only)
```

## Length

```sql
SELECT LENGTH('hello');                                    -- 5
SELECT CHARACTER_LENGTH('hello');                          -- 5
SELECT OCTET_LENGTH('hello');                              -- 5 (bytes)
```

## Case

```sql
SELECT UPPER('hello');                                     -- 'HELLO'
SELECT LOWER('HELLO');                                     -- 'hello'
SELECT INITCAP('hello world');                             -- 'Hello World' (Db2 11.1+)
```

## Substring

```sql
SELECT SUBSTRING('hello world', 7, 5);                     -- 'world'
SELECT SUBSTR('hello world', 7, 5);                        -- 'world'
SELECT LEFT('hello', 3);                                   -- 'hel'
SELECT RIGHT('hello', 3);                                  -- 'llo'
```

## Position

```sql
SELECT POSITION('world' IN 'hello world');                 -- 7
SELECT LOCATE('world', 'hello world');                     -- 7
SELECT LOCATE('l', 'hello world', 5);                      -- 11 (start from position 5)
```

## Trim

```sql
SELECT TRIM('  hello  ');                                  -- 'hello'
SELECT TRIM(LEADING ' ' FROM '  hello  ');                 -- 'hello  '
SELECT TRIM(TRAILING ' ' FROM '  hello  ');                -- '  hello'
SELECT TRIM(BOTH 'x' FROM 'xxhelloxx');                    -- 'hello'
SELECT LTRIM('  hello');                                   -- 'hello'
SELECT RTRIM('hello  ');                                   -- 'hello'
SELECT STRIP('  hello  ');                                 -- 'hello' (synonym for TRIM)
```

## Padding

```sql
SELECT LPAD('42', 5, '0');                                 -- '00042'
SELECT RPAD('hi', 5, '.');                                 -- 'hi...'
```

## Replace

```sql
SELECT REPLACE('hello world', 'world', 'db2');             -- 'hello db2'
```

## Translate (character-by-character replacement)

```sql
SELECT TRANSLATE('hello', 'HELO', 'helo');                 -- 'HELLO'
```

## Regular expressions (Db2 11.1+)

```sql
SELECT REGEXP_SUBSTR('abc 123 def', '[0-9]+');             -- '123'
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');       -- 'abc # def'
SELECT REGEXP_INSTR('abc 123 def', '[0-9]+');              -- 5
SELECT REGEXP_COUNT('a1b2c3', '[0-9]');                    -- 3
SELECT REGEXP_LIKE('abc 123', '[0-9]+');                   -- 1
```

## String aggregation (Db2 11.1+)

```sql
SELECT LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;
```

## LISTAGG with DISTINCT (Db2 11.5+)

```sql
SELECT LISTAGG(DISTINCT city, ', ') WITHIN GROUP (ORDER BY city) FROM users;
```

## Repeat / Reverse

```sql
SELECT REPEAT('ab', 3);                                    -- 'ababab'
SELECT REVERSE('hello');                                   -- 'olleh' (Db2 11.1+)
```

## Other functions

```sql
SELECT ASCII('A');                                         -- 65
SELECT CHR(65);                                            -- 'A'
SELECT INSERT('hello world', 7, 5, 'db2');                 -- 'hello db2'
SELECT SPACE(5);                                           -- '     '
```

## SOUNDEX (phonetic matching)

```sql
SELECT SOUNDEX('Smith');                                   -- 'S530'
SELECT DIFFERENCE('Smith', 'Smythe');                      -- 4 (0-4 scale)
```

Note: CONCAT takes only 2 arguments; use || for multi-part
Note: LISTAGG is the standard string aggregation (Db2 11.1+)
Note: REGEXP functions available from Db2 11.1+
