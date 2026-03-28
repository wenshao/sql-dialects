# KingbaseES (人大金仓): 字符串函数 (String Functions)

> 参考资料:
> - [KingbaseES SQL Reference Manual](https://help.kingbase.com.cn/v8/index.html)
> - [KingbaseES Documentation - String Functions](https://help.kingbase.com.cn/v8/developer/sql-reference/functions/string.html)
> - [PostgreSQL Documentation - String Functions](https://www.postgresql.org/docs/current/functions-string.html)


## 说明: KingbaseES 兼容 PostgreSQL 和 Oracle 双语法体系。

字符串函数以 PostgreSQL 语法为基础，Oracle 模式下额外支持 Oracle 函数。

## 字符串拼接


## || 操作符: SQL 标准拼接（推荐）

```sql
SELECT 'hello' || ' ' || 'world';                     -- 'hello world'
```

## CONCAT: 函数形式，跳过 NULL（非标准但实用）

```sql
SELECT CONCAT('hello', ' ', 'world');                 -- 'hello world'
SELECT CONCAT('hello', NULL, 'world');                -- 'helloworld'（跳过 NULL）
```

## CONCAT_WS: 带分隔符拼接

```sql
SELECT CONCAT_WS(',', 'a', 'b', 'c');                -- 'a,b,c'
SELECT CONCAT_WS(',', 'a', NULL, 'c');                -- 'a,c'（跳过 NULL）
```

|| vs CONCAT 的 NULL 处理:
|| : 任一操作数为 NULL → 结果 NULL（SQL 标准）
CONCAT: 跳过 NULL → 结果非 NULL

```sql
SELECT 'hello' || NULL;                               -- NULL
```

## 长度函数: 字符数 vs 字节数


```sql
SELECT LENGTH('hello');                               -- 5（字符数! PG 语义）
SELECT CHAR_LENGTH('hello');                          -- 5（同 LENGTH，SQL 标准名）
SELECT OCTET_LENGTH('hello');                         -- 5（字节数，ASCII）
SELECT OCTET_LENGTH('你好');                           -- 6（UTF-8 字节数）
SELECT BIT_LENGTH('hello');                           -- 40（位数）
```

## 注意: LENGTH 返回字符数（PostgreSQL 语义），与 MySQL 的 LENGTH=字节数不同!

迁移建议: 统一使用 CHAR_LENGTH（字符数）或 OCTET_LENGTH（字节数）避免歧义

## 大小写转换


```sql
SELECT UPPER('hello');                                -- 'HELLO'
SELECT LOWER('HELLO');                                -- 'hello'
SELECT INITCAP('hello world');                        -- 'Hello World'（首字母大写）
```

## 截取函数


## SQL 标准语法

```sql
SELECT SUBSTRING('hello world' FROM 7 FOR 5);         -- 'world'
```

## PostgreSQL 简写

```sql
SELECT SUBSTRING('hello world', 7, 5);                -- 'world'
```

## Oracle 兼容: SUBSTR

```sql
SELECT SUBSTR('hello world', 7, 5);                   -- 'world'
```

## LEFT / RIGHT

```sql
SELECT LEFT('hello', 3);                              -- 'hel'
SELECT RIGHT('hello', 3);                             -- 'llo'
```

## 查找与定位


## SQL 标准

```sql
SELECT POSITION('world' IN 'hello world');            -- 7
```

## PostgreSQL 简写

```sql
SELECT STRPOS('hello world', 'world');                -- 7
```

## Oracle 兼容: INSTR

```sql
SELECT INSTR('hello world', 'world');                 -- 7
SELECT INSTR('hello world', 'l', 4);                  -- 4（从第 4 位开始搜索）
```

## 替换函数


```sql
SELECT REPLACE('hello world', 'world', 'kingbase');   -- 'hello kingbase'
SELECT OVERLAY('hello world' PLACING 'kb' FROM 7 FOR 5);  -- 'hello kb'（SQL 标准）
SELECT TRANSLATE('hello', 'helo', 'HELO');            -- 'HELLO'（字符映射）
```

## 填充与修剪


## 填充

```sql
SELECT LPAD('42', 5, '0');                            -- '00042'
SELECT RPAD('hi', 5, '.');                            -- 'hi...'
```

## 修剪

```sql
SELECT TRIM('  hello  ');                             -- 'hello'
SELECT LTRIM('  hello');                              -- 'hello'
SELECT RTRIM('hello  ');                              -- 'hello'
SELECT BTRIM('xxhelloxx', 'x');                       -- 'hello'（去两端指定字符）
SELECT TRIM(LEADING '0' FROM '00042');                -- '42'（去前导零）
```

## 翻转与重复


```sql
SELECT REVERSE('hello');                              -- 'olleh'
SELECT REPEAT('ab', 3);                               -- 'ababab'
```

## 正则表达式


## PostgreSQL POSIX 正则

```sql
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');  -- 'abc # def'
SELECT REGEXP_REPLACE('abc 123 def 456', '\d+', 'X', 'g');  -- 全局替换
SELECT SUBSTRING('abc 123 def' FROM '[0-9]+');         -- '123'（正则截取）
```

## 正则匹配操作符

```sql
SELECT 'hello123' ~ '^[a-z]+[0-9]+$';                -- true（匹配）
SELECT 'hello123' !~ '^[a-z]+$';                     -- true（不匹配）
SELECT 'Hello' ~* 'hello';                           -- true（大小写不敏感）
```

## 分隔与拼接 (SPLIT_PART / STRING_AGG)


## SPLIT_PART: 按分隔符分割取第 N 段

```sql
SELECT SPLIT_PART('a.b.c', '.', 2);                  -- 'b'
SELECT SPLIT_PART('2024-01-15', '-', 1);             -- '2024'
```

## STRING_AGG: 字符串聚合

```sql
SELECT STRING_AGG(username, ', ') FROM users;                         -- 基本拼接
SELECT STRING_AGG(username, ', ' ORDER BY username) FROM users;       -- 带排序
SELECT STRING_AGG(DISTINCT city, ', ') FROM users;                    -- 去重
```

## ASCII / 字符转换


```sql
SELECT ASCII('A');                                    -- 65
SELECT CHR(65);                                       -- 'A'
SELECT UNICODE('你');                                 -- 20320（Unicode 码点）
```

## 编码与解码


```sql
SELECT ENCODE('hello'::BYTEA, 'hex');                 -- '68656c6c6f'
SELECT DECODE('68656c6c6f', 'hex');                   -- 'hello' (BYTEA)
SELECT ENCODE('hello'::BYTEA, 'base64');              -- 'aGVsbG8='
SELECT CONVERT_TO('hello', 'UTF8');                   -- 字符串 → BYTEA
SELECT CONVERT_FROM('hello'::BYTEA, 'UTF8');          -- BYTEA → 字符串
```

## Oracle 兼容模式字符串函数


Oracle 模式下额外支持的函数:
INSTR(str, substr [, pos [, occurrence]])
SUBSTR(str, pos [, len])
LPAD/RPAD/TRIM (语法略有差异)
INITCAP 同名可用
REPLACE 同名可用
Oracle 模式下使用 FROM DUAL:
SELECT INSTR('hello world', 'world') FROM DUAL;
SELECT SUBSTR('hello world', 1, 5) FROM DUAL;

## 兼容模式差异总结


PostgreSQL 模式:
拼接: || 操作符 + CONCAT + CONCAT_WS
长度: LENGTH(字符数), OCTET_LENGTH(字节数)
截取: SUBSTRING(... FROM ... FOR ...)
查找: POSITION(... IN ...), STRPOS()
正则: ~ 操作符 + REGEXP_REPLACE
无 DUAL 表
Oracle 模式:
拼接: || 操作符 + CONCAT（仅 2 参数!）
长度: LENGTH(字符数), LENGTHB(字节数)
截取: SUBSTR()
查找: INSTR()
正则: REGEXP_LIKE / REGEXP_REPLACE / REGEXP_SUBSTR
使用 DUAL 虚表

## 版本演进与注意事项

KingbaseES V8R2: PostgreSQL 兼容字符串函数完备
KingbaseES V8R3: Oracle 兼容模式增强（INSTR/SUBSTR/REGEXP_*）
KingbaseES V8R6: Unicode 函数增强
注意事项:
1. 字符串函数与 PostgreSQL 高度兼容
2. Oracle 模式额外支持 INSTR/SUBSTR 等 Oracle 专有函数
3. LENGTH 返回字符数（与 MySQL 的 LENGTH=字节数不同）
4. 正则使用 POSIX 语法（非 ICU/PCRE）
5. 建议使用 SQL 标准函数以保持跨模式兼容
