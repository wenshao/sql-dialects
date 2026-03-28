# TimescaleDB: 字符串函数

## TimescaleDB 继承 PostgreSQL 全部字符串函数

拼接

```sql
SELECT 'hello' || ' ' || 'world';                   -- 'hello world'
SELECT CONCAT('hello', ' ', 'world');                -- 'hello world'
SELECT CONCAT_WS(',', 'a', 'b', 'c');               -- 'a,b,c'
```

## 长度

```sql
SELECT LENGTH('hello');                               -- 5
SELECT CHAR_LENGTH('hello');                          -- 5
SELECT OCTET_LENGTH('hello');                         -- 5（字节数）
```

## 大小写

```sql
SELECT UPPER('hello');                                -- 'HELLO'
SELECT LOWER('HELLO');                                -- 'hello'
SELECT INITCAP('hello world');                        -- 'Hello World'
```

## 截取

```sql
SELECT SUBSTRING('hello world' FROM 7 FOR 5);         -- 'world'
SELECT LEFT('hello', 3);                              -- 'hel'
SELECT RIGHT('hello', 3);                             -- 'llo'
```

## 查找

```sql
SELECT POSITION('world' IN 'hello world');            -- 7
SELECT STRPOS('hello world', 'world');                -- 7
```

## 替换 / 填充 / 修剪

```sql
SELECT REPLACE('hello world', 'world', 'pg');         -- 'hello pg'
SELECT LPAD('42', 5, '0');                            -- '00042'
SELECT RPAD('hi', 5, '.');                            -- 'hi...'
SELECT TRIM('  hello  ');                             -- 'hello'
SELECT TRIM(BOTH 'x' FROM 'xxhelloxx');              -- 'hello'
SELECT LTRIM('  hello');                              -- 'hello'
SELECT RTRIM('hello  ');                              -- 'hello'
```

## 翻转 / 重复

```sql
SELECT REVERSE('hello');                              -- 'olleh'
SELECT REPEAT('ab', 3);                               -- 'ababab'
```

## 正则

```sql
SELECT REGEXP_REPLACE('abc 123 def', '\d+', '#');     -- 'abc # def'
SELECT REGEXP_MATCH('abc 123', '\d+');                -- {123}
SELECT REGEXP_MATCHES('a1b2c3', '\d+', 'g');          -- 多行匹配
SELECT REGEXP_SPLIT_TO_TABLE('a,b,c', ',');           -- 拆分为行
```

## 聚合拼接

```sql
SELECT STRING_AGG(username, ', ' ORDER BY username) FROM users;
```

## 编码

```sql
SELECT ENCODE(E'\\xDEAD', 'hex');
SELECT DECODE('68656C6C6F', 'hex');
```

注意：完全兼容 PostgreSQL 的字符串函数
注意：|| 是标准拼接运算符
注意：STRING_AGG 是聚合拼接函数
