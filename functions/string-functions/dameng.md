# DamengDB (达梦): 字符串函数

Oracle compatible syntax.

> 参考资料:
> - [DamengDB SQL Reference](https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html)
> - [DamengDB System Admin Manual](https://eco.dameng.com/document/dm/zh-cn/pm/index.html)


## 拼接

```sql
SELECT 'hello' || ' ' || 'world' FROM DUAL;          -- 'hello world'
SELECT CONCAT('hello', ' world') FROM DUAL;           -- 'hello world'（只接受 2 个参数）
```

## 长度

```sql
SELECT LENGTH('hello') FROM DUAL;                     -- 5
SELECT LENGTHB('你好') FROM DUAL;                      -- 6（字节数）
SELECT CHAR_LENGTH('hello') FROM DUAL;                -- 5
```

## 大小写

```sql
SELECT UPPER('hello') FROM DUAL;                      -- 'HELLO'
SELECT LOWER('HELLO') FROM DUAL;                      -- 'hello'
SELECT INITCAP('hello world') FROM DUAL;              -- 'Hello World'
```

## 截取

```sql
SELECT SUBSTR('hello world', 7, 5) FROM DUAL;         -- 'world'
SELECT SUBSTRB('hello world', 7, 5) FROM DUAL;        -- 字节截取
```

## 查找

```sql
SELECT INSTR('hello world', 'world') FROM DUAL;       -- 7
SELECT INSTR('hello world hello', 'hello', 1, 2) FROM DUAL; -- 第 2 次出现
```

## 替换 / 填充 / 修剪

```sql
SELECT REPLACE('hello world', 'world', 'dameng') FROM DUAL;
SELECT LPAD('42', 5, '0') FROM DUAL;                  -- '00042'
SELECT RPAD('hi', 5, '.') FROM DUAL;                  -- 'hi...'
SELECT TRIM('  hello  ') FROM DUAL;                   -- 'hello'
SELECT LTRIM('  hello') FROM DUAL;
SELECT RTRIM('hello  ') FROM DUAL;
```

## 翻转

```sql
SELECT REVERSE('hello') FROM DUAL;                    -- 'olleh'
```

## TRANSLATE

```sql
SELECT TRANSLATE('hello', 'helo', 'HELO') FROM DUAL;  -- 'HELLO'
```

## 正则

```sql
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#') FROM DUAL;
SELECT REGEXP_SUBSTR('abc 123 def', '[0-9]+') FROM DUAL;
SELECT REGEXP_INSTR('abc 123 def', '[0-9]+') FROM DUAL;
SELECT REGEXP_COUNT('a1b2c3', '[0-9]') FROM DUAL;
```

## LISTAGG（字符串聚合）

```sql
SELECT LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;
```

## NVL / NVL2（Oracle 兼容）

```sql
SELECT NVL(phone, 'N/A') FROM users;
SELECT NVL2(phone, phone, 'N/A') FROM users;
```

注意事项：
函数与 Oracle 兼容
CONCAT 只接受 2 个参数（使用 || 拼接多个）
支持 REGEXP_COUNT、REGEXP_INSTR 等 Oracle 正则函数
LISTAGG 是 Oracle 风格的字符串聚合
