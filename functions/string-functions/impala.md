# Apache Impala: 字符串函数

> 参考资料:
> - [Impala SQL Reference](https://impala.apache.org/docs/build/html/topics/impala_langref.html)
> - [Impala Built-in Functions](https://impala.apache.org/docs/build/html/topics/impala_functions.html)


拼接
```sql
SELECT CONCAT('hello', ' ', 'world');                -- 'hello world'
SELECT CONCAT_WS(',', 'a', 'b', 'c');               -- 'a,b,c'
-- 注意：|| 不用于拼接
```


长度
```sql
SELECT LENGTH('hello');                               -- 5（字符数）
SELECT CHAR_LENGTH('hello');                          -- 5
```


大小写
```sql
SELECT UPPER('hello');                                -- 'HELLO'
SELECT LOWER('HELLO');                                -- 'hello'
SELECT INITCAP('hello world');                       -- 'Hello World'
```


截取
```sql
SELECT SUBSTRING('hello world', 7, 5);                -- 'world'
SELECT SUBSTR('hello world', 7, 5);                   -- 'world'
SELECT LEFT('hello', 3);                              -- 'hel'
SELECT RIGHT('hello', 3);                             -- 'llo'
SELECT STRLEFT('hello', 3);                          -- 'hel'（别名）
SELECT STRRIGHT('hello', 3);                         -- 'llo'（别名）
```


查找
```sql
SELECT INSTR('hello world', 'world');                 -- 7
SELECT LOCATE('world', 'hello world');                -- 7
SELECT FIND_IN_SET('b', 'a,b,c');                    -- 2
```


替换 / 填充 / 修剪
```sql
SELECT REPLACE('hello world', 'world', 'impala');     -- 'hello impala'
SELECT TRANSLATE('hello', 'el', 'EL');               -- 'hELLo'
SELECT LPAD('42', 5, '0');                            -- '00042'
SELECT RPAD('hi', 5, '.');                            -- 'hi...'
SELECT TRIM('  hello  ');                             -- 'hello'
SELECT LTRIM('  hello');                              -- 'hello'
SELECT RTRIM('hello  ');                              -- 'hello'
SELECT BTRIM('xxhelloxx', 'x');                      -- 'hello'
```


翻转 / 重复
```sql
SELECT REVERSE('hello');                              -- 'olleh'
SELECT REPEAT('ab', 3);                               -- 'ababab'
```


正则
```sql
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');  -- 'abc # def'
SELECT REGEXP_EXTRACT('abc 123 def', '([0-9]+)', 1); -- '123'
SELECT 'abc' REGEXP '[a-z]+';                        -- TRUE
SELECT 'abc' RLIKE '[a-z]+';                         -- TRUE（别名）
```


分割
```sql
SELECT SPLIT_PART('a,b,c', ',', 2);                  -- 'b'
```


编码
```sql
SELECT BASE64ENCODE('hello');
SELECT BASE64DECODE('aGVsbG8=');
```


ASCII
```sql
SELECT ASCII('A');                                    -- 65
SELECT CHR(65);                                       -- 'A'
```


空格
```sql
SELECT SPACE(5);                                      -- '     '
```


GROUP_CONCAT（聚合拼接）
```sql
SELECT GROUP_CONCAT(username, ', ') FROM users;
```


注意：Impala 字符串函数与 Hive 兼容
注意：支持 INITCAP, BTRIM 等扩展函数
注意：REGEXP_EXTRACT 使用 Java 正则语法
注意：GROUP_CONCAT 是 Impala 特有的聚合函数
