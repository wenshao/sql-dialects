# Teradata: String Functions

> 参考资料:
> - [Teradata SQL Reference](https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates)
> - [Teradata Database Documentation](https://docs.teradata.com/)


Concatenation
```sql
SELECT 'hello' || ' ' || 'world';                         -- 'hello world'
-- Note: || is the standard concatenation operator
```


Length
```sql
SELECT CHARACTER_LENGTH('hello');                          -- 5 (characters)
SELECT CHAR_LENGTH('hello');                               -- 5
SELECT OCTET_LENGTH('hello');                              -- 5 (bytes)
```


Case
```sql
SELECT UPPER('hello');                                     -- 'HELLO'
SELECT LOWER('HELLO');                                     -- 'hello'
-- No INITCAP; use CASE or UDF
```


Substring
```sql
SELECT SUBSTRING('hello world' FROM 7 FOR 5);              -- 'world' (SQL standard)
SELECT SUBSTR('hello world', 7, 5);                        -- 'world'
```


Position / Index
```sql
SELECT POSITION('world' IN 'hello world');                 -- 7
SELECT INDEX('hello world', 'world');                      -- 7 (Teradata-specific)
```


Trim
```sql
SELECT TRIM('  hello  ');                                  -- 'hello'
SELECT TRIM(LEADING ' ' FROM '  hello  ');                 -- 'hello  '
SELECT TRIM(TRAILING ' ' FROM '  hello  ');                -- '  hello'
SELECT TRIM(BOTH 'x' FROM 'xxhelloxx');                    -- 'hello'
```


Padding
```sql
SELECT LPAD('42', 5, '0');                                 -- '00042'
SELECT RPAD('hi', 5, '.');                                 -- 'hi...'
```


Replace
```sql
SELECT OREPLACE('hello world', 'world', 'td');             -- 'hello td' (Teradata-specific)
-- Note: OREPLACE, not REPLACE
```


Translate
```sql
SELECT OTRANSLATE('hello', 'helo', 'HELO');                -- 'HELLO' (Teradata-specific)
```


Regular expressions (14.10+)
```sql
SELECT REGEXP_SUBSTR('abc 123 def', '[0-9]+');             -- '123'
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');       -- 'abc # def'
SELECT REGEXP_INSTR('abc 123 def', '[0-9]+');              -- 5
```


REGEXP_SIMILAR (returns 1 if matches, 0 otherwise)
```sql
SELECT CASE WHEN REGEXP_SIMILAR('abc 123', '.*[0-9]+.*', 'i') = 1
       THEN 'match' ELSE 'no match' END;
```


String aggregation
No STRING_AGG; use recursive or XML approach
Alternative: use ordered analytics
```sql
SELECT city,
    TRIM(TRAILING ',' FROM
        (XMLAGG(TRIM(username) || ',' ORDER BY username) (VARCHAR(10000)))
    ) AS usernames
FROM users
GROUP BY city;
```


Other functions
```sql
SELECT REVERSE('hello');                                   -- 'olleh'
SELECT CHAR(65);                                           -- 'A' (ASCII to char)
SELECT ASCII('A');                                         -- 65
```


STRTOK (tokenize string, Teradata-specific)
```sql
SELECT STRTOK('a.b.c', '.', 1);                           -- 'a'
SELECT STRTOK('a.b.c', '.', 2);                           -- 'b'
SELECT STRTOK('a.b.c', '.', 3);                           -- 'c'
```


NGRAM (generate n-grams, Teradata-specific)
```sql
SELECT NGRAM('hello', 2);  -- returns bigrams
```


Note: Teradata uses OREPLACE/OTRANSLATE (not REPLACE/TRANSLATE)
Note: STRTOK is Teradata's split function
Note: no CONCAT() function; use || operator
