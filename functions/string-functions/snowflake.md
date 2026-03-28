# Snowflake: 字符串函数

> 参考资料:
> - [1] Snowflake SQL Reference - String Functions
>   https://docs.snowflake.com/en/sql-reference/functions-string
> - [2] Snowflake SQL Reference - Regular Expressions
>   https://docs.snowflake.com/en/sql-reference/functions-regexp


## 1. 拼接


```sql
SELECT 'hello' || ' ' || 'world';           -- 'hello world'
SELECT CONCAT('hello', ' ', 'world');        -- 支持多参数
SELECT CONCAT_WS(',', 'a', 'b', 'c');       -- 'a,b,c'（分隔符拼接）

```

## 2. 语法设计分析（对 SQL 引擎开发者）


### 2.1 || 运算符 vs CONCAT 函数

 Snowflake 两者都支持，但行为有差异:
|| 遇到 NULL 结果为 NULL: 'hello' || NULL → NULL
   CONCAT 跳过 NULL:         CONCAT('hello', NULL, 'world') → 'helloworld'

 对比:
PostgreSQL: || 遇到 NULL 结果为 NULL（与 Snowflake 一致）
MySQL:      || 默认是逻辑 OR！需要 SET sql_mode = 'PIPES_AS_CONCAT'
               CONCAT 跳过 NULL: CONCAT('a', NULL, 'b') → NULL（MySQL 不跳过！）
Oracle:     || 跳过 NULL（因为 Oracle 中 '' = NULL）
BigQuery:   || 和 CONCAT 行为一致

 对引擎开发者的启示:
|| 与 NULL 的交互行为是跨数据库迁移的常见坑。
   推荐 CONCAT 函数提供 NULL 跳过的选项（或提供 CONCAT_WS 处理）。

### 2.2 SPLIT / SPLIT_PART: 字符串分割

```sql
SELECT SPLIT('a,b,c', ',');                  -- 返回 ARRAY ['a','b','c']
SELECT SPLIT_PART('a.b.c', '.', 2);          -- 'b'（取第 2 部分）
SELECT STRTOK('a,b,c', ',', 2);              -- 'b'（SPLIT_PART 的别名）

```

 SPLIT 返回 ARRAY（VARIANT 类型）是 Snowflake 特有:
   配合 FLATTEN 可以展开为行（见 json-flatten/snowflake.sql）
 对比:
   PostgreSQL: string_to_array('a,b,c', ',') + unnest()
   MySQL:      无原生 SPLIT（需要自定义函数或递归 CTE）
   BigQuery:   SPLIT('a,b,c', ',') 返回 ARRAY

## 3. 长度


```sql
SELECT LENGTH('hello');          -- 5（字符数）
SELECT LEN('hello');             -- 5（别名）
SELECT OCTET_LENGTH('你好');      -- 6（字节数，UTF-8 每汉字 3 字节）

```

## 4. 大小写与修剪


```sql
SELECT UPPER('hello');           -- 'HELLO'
SELECT LOWER('HELLO');           -- 'hello'
SELECT INITCAP('hello world');   -- 'Hello World'

SELECT TRIM('  hello  ');       -- 'hello'
SELECT LTRIM('  hello  ');      -- 'hello  '
SELECT RTRIM('  hello  ');      -- '  hello'
SELECT TRIM(BOTH 'x' FROM 'xxhelloxx'); -- 'hello'

```

## 5. 截取与查找


```sql
SELECT SUBSTR('hello world', 7, 5);           -- 'world'
SELECT LEFT('hello', 3);                       -- 'hel'
SELECT RIGHT('hello', 3);                      -- 'llo'

SELECT POSITION('world' IN 'hello world');     -- 7
SELECT CHARINDEX('world', 'hello world');      -- 7
SELECT CONTAINS('hello world', 'world');       -- TRUE
SELECT STARTSWITH('hello world', 'hello');     -- TRUE
SELECT ENDSWITH('hello world', 'world');       -- TRUE

```

 CONTAINS / STARTSWITH / ENDSWITH 返回 BOOLEAN
 对比 PostgreSQL: LIKE 'hello%' 或 position(needle in haystack) > 0

## 6. 替换与填充


```sql
SELECT REPLACE('hello world', 'world', 'sf'); -- 'hello sf'
SELECT LPAD('42', 5, '0');                     -- '00042'
SELECT RPAD('hi', 5, '.');                     -- 'hi...'
SELECT REVERSE('hello');                       -- 'olleh'
SELECT REPEAT('ab', 3);                        -- 'ababab'
SELECT TRANSLATE('hello', 'helo', 'HELO');     -- 'HELLO'
SELECT INSERT('hello world', 7, 5, 'sf');      -- 'hello sf'
SELECT SPACE(5);                               -- '     '

```

## 7. 正则表达式


```sql
SELECT REGEXP_LIKE('abc 123', '[0-9]+');                -- TRUE
SELECT RLIKE('abc 123', '[0-9]+');                      -- TRUE (别名)
SELECT REGEXP_SUBSTR('abc 123 def', '[0-9]+');          -- '123'
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');   -- 'abc # def'
SELECT REGEXP_COUNT('a1b2c3', '[0-9]');                -- 3
SELECT REGEXP_INSTR('abc 123', '[0-9]+');              -- 5

```

 正则使用 POSIX 语法（不是 PCRE）
 对比:
   PostgreSQL: ~ 运算符 + regexp_matches / regexp_replace
   MySQL:      REGEXP / REGEXP_LIKE / REGEXP_REPLACE（8.0+）
   Oracle:     REGEXP_LIKE / REGEXP_SUBSTR / REGEXP_REPLACE（与 Snowflake 最一致）

## 8. 编码与哈希


```sql
SELECT BASE64_ENCODE('hello');
SELECT BASE64_DECODE_STRING(BASE64_ENCODE('hello'));
SELECT MD5('hello');
SELECT SHA2('hello', 256);                    -- SHA-256
SELECT HEX_ENCODE('hello');
SELECT ASCII('A');                            -- 65
SELECT CHR(65);                               -- 'A'

```

## 9. 聚合拼接


```sql
SELECT LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;
SELECT ARRAY_AGG(username) FROM users;

```

 对比:
   PostgreSQL: STRING_AGG(col, sep ORDER BY ...)
   MySQL:      GROUP_CONCAT(col ORDER BY ... SEPARATOR sep)
   Oracle:     LISTAGG（与 Snowflake 语法一致）

## 横向对比: 字符串函数亮点

| 特性           | Snowflake      | BigQuery     | PostgreSQL  | MySQL |
|------|------|------|------|------|
|| NULL行为    | 结果为NULL     | 结果为NULL   | 结果为NULL  | 默认是OR! |
| SPLIT→ARRAY   | 支持           | 支持         | string_to_arr| 不支持 |
| SPLIT_PART    | 支持           | 不支持       | 支持        | 不支持(8.0) |
| CONTAINS      | 内置BOOLEAN    | CONTAINS     | LIKE/POSIT  | LOCATE |
| 正则函数      | Oracle风格     | REGEXP_*     | ~/regexp_*  | REGEXP(8.0) |
| LISTAGG       | SQL标准+Oracle | STRING_AGG   | STRING_AGG  | GROUP_CONCAT |
| BASE64        | 内置           | TO_BASE64    | encode()    | TO_BASE64 |

