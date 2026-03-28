# Greenplum: 字符串函数

> 参考资料:
> - [Greenplum SQL Reference](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-sql_ref.html)
> - [Greenplum Admin Guide](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-intro-about_greenplum.html)


拼接
```sql
SELECT 'hello' || ' ' || 'world';                    -- 'hello world'
SELECT CONCAT('hello', ' ', 'world');                 -- 'hello world'
SELECT CONCAT_WS(',', 'a', 'b', 'c');               -- 'a,b,c'
```


长度
```sql
SELECT LENGTH('hello');                               -- 5（字符数）
SELECT OCTET_LENGTH('你好');                          -- 6（字节数，UTF-8）
SELECT CHAR_LENGTH('hello');                          -- 5
SELECT BIT_LENGTH('hello');                           -- 40
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
SELECT SUBSTRING('hello world' FROM 7 FOR 5);        -- 'world'（SQL 标准）
```


查找
```sql
SELECT POSITION('world' IN 'hello world');            -- 7
SELECT STRPOS('hello world', 'world');                -- 7
```


替换 / 填充 / 修剪
```sql
SELECT REPLACE('hello world', 'world', 'greenplum');  -- 'hello greenplum'
SELECT OVERLAY('hello world' PLACING 'GP' FROM 7 FOR 5);  -- 'hello GP'
SELECT LPAD('42', 5, '0');                            -- '00042'
SELECT RPAD('hi', 5, '.');                            -- 'hi...'
SELECT TRIM('  hello  ');                             -- 'hello'
SELECT BTRIM('xxhelloxx', 'x');                      -- 'hello'
SELECT LTRIM('  hello');                              -- 'hello'
SELECT RTRIM('hello  ');                              -- 'hello'
```


翻转 / 重复
```sql
SELECT REVERSE('hello');                              -- 'olleh'
SELECT REPEAT('ab', 3);                               -- 'ababab'
```


正则
```sql
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');  -- 'abc # def'
SELECT REGEXP_MATCHES('abc 123 def', '([0-9]+)');    -- {'123'}
SELECT SUBSTRING('abc 123 def' FROM '[0-9]+');       -- '123'
SELECT 'abc' ~ '[a-z]+';                             -- TRUE（POSIX 正则）
SELECT 'ABC' ~* '[a-z]+';                            -- TRUE（不区分大小写）
```


分割
```sql
SELECT SPLIT_PART('a,b,c', ',', 2);                  -- 'b'
SELECT string_to_array('a,b,c', ',');                -- {a,b,c}
SELECT unnest(string_to_array('a,b,c', ','));        -- 多行输出
```


编码
```sql
SELECT MD5('hello');
SELECT ENCODE('hello'::BYTEA, 'hex');
SELECT DECODE('68656c6c6f', 'hex');
```


格式化
```sql
SELECT FORMAT('Hello %s, you are %s', 'Alice', 25);
```


STRING_AGG（聚合拼接）
```sql
SELECT STRING_AGG(username, ', ' ORDER BY username) FROM users;
```


注意：Greenplum 兼容 PostgreSQL 字符串函数
注意：|| 运算符用于拼接
注意：支持 POSIX 正则运算符（~, ~*, !~, !~*）
注意：STRING_AGG 替代 MySQL 的 GROUP_CONCAT
