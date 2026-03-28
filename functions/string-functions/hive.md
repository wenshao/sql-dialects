# Hive: 字符串函数

> 参考资料:
> - [1] Apache Hive - String Functions
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF#LanguageManualUDF-StringFunctions
> - [2] Apache Hive Language Manual - UDF
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF


## 1. 拼接

```sql
SELECT CONCAT('hello', ' ', 'world');                   -- 'hello world'
SELECT CONCAT_WS(',', 'a', 'b', 'c');                  -- 'a,b,c'
SELECT CONCAT_WS(',', ARRAY('a', 'b', 'c'));           -- 'a,b,c' (数组版)

```

注意: Hive 不支持 || 拼接运算符
对比: PostgreSQL 使用 'a' || 'b'; Oracle 也用 ||
 Hive 必须使用 CONCAT() 函数

## 2. 长度

```sql
SELECT LENGTH('hello');                                 -- 5 (字符数)
SELECT OCTET_LENGTH('hello');                          -- 5 (字节数, 2.2+)
SELECT CHAR_LENGTH('hello');                           -- 5 (2.2+)

```

 LENGTH('你好') → 2 (字符数)
 OCTET_LENGTH('你好') → 6 (UTF-8 编码字节数)

## 3. 大小写转换

```sql
SELECT UPPER('hello');                                  -- 'HELLO'
SELECT LOWER('HELLO');                                  -- 'hello'
SELECT INITCAP('hello world');                         -- 'Hello World' (1.1+)

```

## 4. 截取与查找

```sql
SELECT SUBSTR('hello world', 7, 5);                    -- 'world'
SELECT SUBSTRING('hello world', 7, 5);                 -- 'world' (别名)

SELECT INSTR('hello world', 'world');                  -- 7 (1.2+)
SELECT LOCATE('world', 'hello world');                 -- 7
SELECT LOCATE('world', 'hello world world', 8);        -- 13 (从第8位开始)

```

 索引从 1 开始（与 SQL 标准一致）
 但 ARRAY 索引从 0 开始（与 Java 一致）——这是常见的混淆点

## 5. 替换、填充、修剪

```sql
SELECT REPLACE('hello world', 'world', 'hive');        -- 'hello hive' (1.3+)
SELECT LPAD('42', 5, '0');                             -- '00042'
SELECT RPAD('hi', 5, '.');                             -- 'hi...'
SELECT TRIM('  hello  ');                              -- 'hello'
SELECT LTRIM('  hello  ');                             -- 'hello  '
SELECT RTRIM('  hello  ');                             -- '  hello'
SELECT REVERSE('hello');                               -- 'olleh'
SELECT REPEAT('ab', 3);                                -- 'ababab'
SELECT TRANSLATE('hello', 'helo', 'HELO');             -- 'HELLO'

```

## 6. 正则表达式 (Java 正则语法)

```sql
SELECT REGEXP_EXTRACT('abc 123 def', '[0-9]+', 0);     -- '123'
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');   -- 'abc # def'
SELECT 'abc 123' RLIKE '[0-9]+';                       -- TRUE
SELECT 'abc 123' REGEXP '[0-9]+';                      -- TRUE (别名)

```

 设计分析: Java 正则 vs POSIX 正则
 Hive 使用 Java 正则语法（java.util.regex），不是 POSIX 正则。
 差异: Java 的 \d 等价于 [0-9]; POSIX 的 [:digit:] 不被 Hive 识别
 对比: PostgreSQL 使用 POSIX 正则; MySQL 8.0 也使用 ICU 正则

## 7. SPLIT: 返回 ARRAY（Hive 特色）

```sql
SELECT SPLIT('a,b,c', ',');                            -- ARRAY['a','b','c']
SELECT SPLIT('a,b,c', ',')[0];                         -- 'a' (0-based)

```

 SPLIT 返回 ARRAY 是 Hive 的特色——与 LATERAL VIEW EXPLODE 配合使用:
 SELECT tag FROM (SELECT SPLIT(tags_str, ',') AS tags FROM t) t
 LATERAL VIEW EXPLODE(tags) v AS tag;

 对比: PostgreSQL 的 STRING_TO_ARRAY() + UNNEST()
 对比: MySQL 没有 SPLIT（需要递归 CTE 或 JSON_TABLE）

## 8. 编码与哈希

```sql
SELECT MD5('hello');                                   -- MD5 哈希 (1.3+)
SELECT SHA1('hello');                                  -- SHA-1 (1.3+)
SELECT SHA2('hello', 256);                             -- SHA-256 (1.3+)
SELECT BASE64(CAST('hello' AS BINARY));               -- Base64 编码
SELECT UNBASE64('aGVsbG8=');                           -- Base64 解码

```

## 9. URL 与文本分析

```sql
SELECT PARSE_URL('http://example.com/path?k=v', 'HOST');      -- 'example.com'
SELECT PARSE_URL('http://example.com/path?k=v', 'PATH');      -- '/path'
SELECT PARSE_URL('http://example.com/path?k=v', 'QUERY', 'k'); -- 'v'
SELECT SENTENCES('Hello world. How are you?');                  -- 分句分词
SELECT SOUNDEX('hello');                               -- Soundex 编码
SELECT LEVENSHTEIN('kitten', 'sitting');               -- 编辑距离: 3

```

## 10. 跨引擎对比

 函数          Hive            MySQL            PostgreSQL      BigQuery
拼接          CONCAT          CONCAT/||        ||/CONCAT       CONCAT/||
 分割          SPLIT→ARRAY     无               STRING_TO_ARRAY SPLIT
 正则提取      REGEXP_EXTRACT  REGEXP_SUBSTR    SUBSTRING(POSIX) REGEXP_EXTRACT
 编辑距离      LEVENSHTEIN     无               LEVENSHTEIN     无
 URL解析       PARSE_URL       无               无              无
 分句分词      SENTENCES       无               无              无
 字符串聚合    COLLECT_LIST    GROUP_CONCAT     STRING_AGG      STRING_AGG

## 11. 已知限制

1. 不支持 || 运算符: 必须用 CONCAT

2. 正则使用 Java 语法: 与 PostgreSQL POSIX 正则不兼容

3. ARRAY 索引 0-based 但字符串位置 1-based: 容易混淆

4. 无 LIKE_REGEX: Hive 的 LIKE 只支持 % 和 _ 通配符

5. REPLACE 函数 1.3 才引入: 旧版用 REGEXP_REPLACE 替代


## 12. 对引擎开发者的启示

1. SPLIT 返回 ARRAY 是好的设计: 与嵌套类型系统集成，而非返回虚拟表

2. PARSE_URL 和 SENTENCES 是大数据场景的实用函数:

    RDBMS 很少内置这些，但大数据引擎的文本分析需求更多
3. || 运算符 vs CONCAT 函数: 支持两者是最好的，Hive 只支持后者是不便之处

4. 正则引擎的选择: Java 正则 vs POSIX 正则 vs ICU 正则

影响跨引擎迁移，应该在文档中明确说明语法差异

