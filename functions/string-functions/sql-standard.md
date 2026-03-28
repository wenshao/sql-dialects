# SQL 标准: 字符串函数

> 参考资料:
> - [ISO/IEC 9075 SQL Standard](https://www.iso.org/standard/76583.html)
> - [Modern SQL - by Markus Winand](https://modern-sql.com/)
> - [Modern SQL - String Functions](https://modern-sql.com/feature/string-functions)

SQL-86 (SQL1):
无字符串函数（仅有比较和 LIKE）

SQL-92 (SQL2):
|| (拼接)
SUBSTRING(s FROM start FOR len)
UPPER / LOWER
TRIM
POSITION
CHAR_LENGTH / CHARACTER_LENGTH
OCTET_LENGTH
BIT_LENGTH

```sql
SELECT 'hello' || ' ' || 'world';                        -- 拼接
SELECT SUBSTRING('hello world' FROM 7 FOR 5);            -- 'world'
SELECT UPPER('hello');                                   -- 'HELLO'
SELECT LOWER('HELLO');                                   -- 'hello'
SELECT TRIM(BOTH ' ' FROM '  hello  ');                  -- 'hello'
SELECT TRIM(LEADING ' ' FROM '  hello');                 -- 'hello'
SELECT TRIM(TRAILING ' ' FROM 'hello  ');                -- 'hello'
SELECT POSITION('world' IN 'hello world');               -- 7
SELECT CHAR_LENGTH('hello');                             -- 5
SELECT OCTET_LENGTH('hello');                            -- 5
SELECT BIT_LENGTH('hello');                              -- 40
```

SQL:1999 (SQL3):
OVERLAY (替换子串)
SIMILAR TO (正则 LIKE)
CONVERT / TRANSLATE

```sql
SELECT OVERLAY('hello world' PLACING 'SQL' FROM 7 FOR 5); -- 'hello SQL'
SELECT 'abc 123' SIMILAR TO '%[0-9]+%';                   -- TRUE
```

SQL:2003:
无字符串函数重大变化

SQL:2008:
无字符串函数重大变化

SQL:2011:
LISTAGG (聚合拼接)
```sql
SELECT LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;
```

SQL:2016:
TRIM_ARRAY (截断数组，非字符串)
JSON 相关字符串函数（见 JSON 类型）

SQL:2023:
无字符串函数重大变化

标准类型转换
```sql
SELECT CAST(123 AS CHARACTER VARYING(10));
```

标准 LIKE
```sql
SELECT * FROM users WHERE username LIKE 'a%';             -- 前缀匹配
SELECT * FROM users WHERE username LIKE '_bc';             -- 单字符通配
SELECT * FROM users WHERE username LIKE '%\%%' ESCAPE '\'; -- 转义
```

- **注意：标准中没有 CONCAT 函数（使用 || 运算符）**
- **注意：标准中没有 LEFT / RIGHT / REVERSE / REPEAT 函数**
- **注意：标准中没有 REPLACE 函数（使用 OVERLAY）**
- **注意：标准中没有 LPAD / RPAD 函数**
- **注意：标准中没有正则函数（REGEXP_*），只有 SIMILAR TO**
- **注意：标准中没有 SPLIT 函数**
- **注意：大多数常用字符串函数都是各厂商扩展**
