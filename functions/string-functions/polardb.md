# PolarDB: 字符串函数

PolarDB-X (distributed, MySQL compatible).

> 参考资料:
> - [PolarDB-X SQL Reference](https://help.aliyun.com/zh/polardb/polardb-for-xscale/sql-reference/)
> - [PolarDB MySQL Documentation](https://help.aliyun.com/zh/polardb/polardb-for-mysql/)
> - 拼接

```sql
SELECT CONCAT('hello', ' ', 'world');                -- 'hello world'
SELECT CONCAT_WS(',', 'a', 'b', 'c');               -- 'a,b,c'
```

## 长度

```sql
SELECT LENGTH('hello');                               -- 5（字节数）
SELECT CHAR_LENGTH('你好');                            -- 2（字符数）
```

## 大小写

```sql
SELECT UPPER('hello');                                -- 'HELLO'
SELECT LOWER('HELLO');                                -- 'hello'
```

## 截取

```sql
SELECT SUBSTRING('hello world', 7, 5);                -- 'world'
SELECT LEFT('hello', 3);                              -- 'hel'
SELECT RIGHT('hello', 3);                             -- 'llo'
```

## 查找

```sql
SELECT INSTR('hello world', 'world');                 -- 7
SELECT LOCATE('world', 'hello world');                -- 7
SELECT POSITION('world' IN 'hello world');            -- 7
```

## 替换 / 填充 / 修剪

```sql
SELECT REPLACE('hello world', 'world', 'mysql');      -- 'hello mysql'
SELECT LPAD('42', 5, '0');                            -- '00042'
SELECT RPAD('hi', 5, '.');                            -- 'hi...'
SELECT TRIM('  hello  ');                             -- 'hello'
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
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');  -- 'abc # def'
SELECT REGEXP_SUBSTR('abc 123 def', '[0-9]+');        -- '123'
```

## GROUP_CONCAT

```sql
SELECT GROUP_CONCAT(username SEPARATOR ', ') FROM users;
```

注意事项：
字符串函数与 MySQL 完全兼容
GROUP_CONCAT 在分布式环境下需要合并各分片结果
