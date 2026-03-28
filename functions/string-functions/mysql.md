# MySQL: 字符串函数

> 参考资料:
> - [MySQL 8.0 Reference Manual - String Functions and Operators](https://dev.mysql.com/doc/refman/8.0/en/string-functions.html)
> - [MySQL 8.0 Reference Manual - Regular Expressions](https://dev.mysql.com/doc/refman/8.0/en/regexp.html)
> - [MySQL 8.0 Reference Manual - PIPES_AS_CONCAT SQL Mode](https://dev.mysql.com/doc/refman/8.0/en/sql-mode.html#sqlmode_pipes_as_concat)

## 字符串拼接

```sql
SELECT CONCAT('hello', ' ', 'world');                  -- 'hello world'
SELECT CONCAT_WS(',', 'a', 'b', 'c');                 -- 'a,b,c' (With Separator)
SELECT CONCAT_WS(',', 'a', NULL, 'c');                -- 'a,c'   (跳过 NULL!)
```

## CONCAT 的 NULL 处理（对引擎开发者: 重要的语义差异）

### MySQL 的 CONCAT: 任一参数 NULL → 结果 NULL

```sql
SELECT CONCAT('hello', NULL, 'world');                 -- NULL（不是 'helloworld'!）
-- 这符合 SQL 标准: NULL 参与运算则结果为 NULL
-- 但在实际应用中极其容易出错:
--   SELECT CONCAT(first_name, ' ', last_name) FROM users;
--   如果 last_name 为 NULL → 整个结果为 NULL（而非只显示 first_name）

-- 2.2 CONCAT_WS 的 NULL 处理: 跳过 NULL（更安全）
SELECT CONCAT_WS(' ', 'hello', NULL, 'world');         -- 'hello world'
-- CONCAT_WS = "CONCAT With Separator"
-- 设计逻辑: 分隔符拼接时，NULL 值应被忽略（否则会产生多余的分隔符）
-- 实践建议: 涉及可能为 NULL 的列时，优先使用 CONCAT_WS

-- 2.3 IFNULL / COALESCE 防御
SELECT CONCAT(IFNULL(first_name, ''), ' ', IFNULL(last_name, '')) FROM users;
-- 或用标准的 COALESCE:
SELECT CONCAT(COALESCE(first_name, ''), ' ', COALESCE(last_name, '')) FROM users;
```

### 横向对比: CONCAT 的 NULL 处理

  MySQL:      CONCAT(a, NULL) = NULL          ← SQL 标准
  PostgreSQL: CONCAT(a, NULL) = a             ← 非标准但更实用!
              PG 的 CONCAT 自动跳过 NULL，是 MySQL 的 CONCAT_WS 语义
              PG 的 || 操作符则遵循标准: 'a' || NULL = NULL
  Oracle:     CONCAT(a, NULL) = a             ← 因为 '' = NULL (Oracle 独有行为)
              'hello' || NULL = 'hello'       ← 同理
  SQL Server: CONCAT(a, NULL) = a             ← 非标准但更实用（同 PG）
              'hello' + NULL = NULL           ← + 操作符遵循标准
  ClickHouse: concat(a, NULL) = a             ← 跳过 NULL

对引擎开发者的启示:
  SQL 标准的 NULL 传播在 CONCAT 场景中反直觉。
  PG/SQL Server/ClickHouse 选择了 "实用优于标准" -- CONCAT 函数跳过 NULL，
  但保留 || 操作符的标准 NULL 传播行为。这是一个合理的折中。
  如果设计新引擎，建议: CONCAT 函数跳过 NULL，|| 遵循标准。

## || 在 MySQL 中是逻辑 OR（最大的方言陷阱之一）

### MySQL 默认: || 是 OR 操作符

```sql
SELECT 'hello' || 'world';      -- 0 （字符串转数值 0，0 OR 0 = 0）
SELECT 1 || 0;                  -- 1 （1 OR 0 = 1，逻辑运算）
-- 这与 SQL 标准完全矛盾!

-- 3.2 SQL 标准和其他数据库: || 是字符串拼接
-- PostgreSQL: SELECT 'hello' || 'world';   → 'helloworld'
-- Oracle:     SELECT 'hello' || 'world' FROM dual;  → 'helloworld'
-- SQLite:     SELECT 'hello' || 'world';   → 'helloworld'
-- SQL Server: 使用 + 拼接（也不是 ||，但至少不是逻辑 OR）

-- 3.3 PIPES_AS_CONCAT 模式: 让 || 变成拼接
SET sql_mode = 'PIPES_AS_CONCAT';  -- 或追加到现有 sql_mode
SELECT 'hello' || ' ' || 'world'; -- 'hello world'（与 PG/Oracle 行为一致）
-- 注意: 开启后 || 不再是逻辑 OR，需要用 OR 关键字

-- 3.4 为什么 MySQL 选择 || 作为 OR?
-- 历史原因: MySQL 最初的设计受 C 语言影响:
--   C 语言: || 是逻辑或，&& 是逻辑与
--   MySQL:  || 是 OR，&& 是 AND（C 程序员"友好"）
-- 这导致 MySQL 是唯一将 || 作为逻辑 OR 的主流数据库
--
-- 3.5 从 Oracle/PG 迁移到 MySQL 的经典事故
--   原始 SQL:  WHERE status || type = 'ACTIVEVIP'
--   Oracle 语义: status 和 type 拼接后与 'ACTIVEVIP' 比较
--   MySQL 语义: status OR type = 'ACTIVEVIP'（完全不同的逻辑!）
-- 迁移工具必须将 || 替换为 CONCAT()

-- 横向对比: 字符串拼接操作符
--   MySQL:      CONCAT() 函数（|| 默认是 OR）
--   PostgreSQL: || 操作符 + CONCAT() 函数（推荐 ||）
--   Oracle:     || 操作符 + CONCAT() 函数（CONCAT 只接受 2 个参数!）
--   SQL Server: + 操作符 + CONCAT() 函数（2012+）
--   SQLite:     || 操作符 + CONCAT 不支持
--   ClickHouse: concat() 函数 + || 操作符 (21.8+)
--   BigQuery:   || 操作符 + CONCAT() 函数
--   Snowflake:  || 操作符 + CONCAT() 函数
--
-- 对引擎开发者的启示:
--   || 作为字符串拼接是 SQL 标准 (SQL:1992)，没有理由偏离。
--   MySQL 的 || = OR 是最被诟病的非标准行为之一。
--   如果设计新引擎: || 必须是字符串拼接，逻辑或只用 OR 关键字。
```

## 长度函数: 字节数 vs 字符数

```sql
SELECT LENGTH('你好');          -- 6 (字节数, utf8mb4 下每个汉字 3 字节)
SELECT CHAR_LENGTH('你好');     -- 2 (字符数)
SELECT BIT_LENGTH('hello');    -- 40 (位数, 5 字节 * 8)
SELECT OCTET_LENGTH('你好');   -- 6 (同 LENGTH，SQL 标准名)

-- 横向对比:
--   MySQL:      LENGTH = 字节数, CHAR_LENGTH = 字符数
--   PostgreSQL: LENGTH = 字符数! (与 MySQL 语义不同!)
--               OCTET_LENGTH = 字节数
--   Oracle:     LENGTH = 字符数, LENGTHB = 字节数
--   SQL Server: LEN = 字符数(去尾部空格!), DATALENGTH = 字节数
--
-- 迁移陷阱: LENGTH('你好')
--   MySQL → 6 (字节)   PG → 2 (字符)   Oracle → 2 (字符)
--   同一函数名，不同语义! 这是跨数据库迁移中最常见的 bug 来源之一。
--
-- 对引擎开发者的启示:
--   LENGTH 应返回字符数（SQL 标准语义），字节数用 OCTET_LENGTH。
--   MySQL 的 LENGTH=字节数 是非标准行为，但因用户量太大无法修正。
```

## 截取、查找、替换

截取
```sql
SELECT SUBSTRING('hello world', 7, 5);          -- 'world' (从第7个字符取5个)
SELECT LEFT('hello', 3);                         -- 'hel'
SELECT RIGHT('hello', 3);                        -- 'llo'

-- 查找
SELECT INSTR('hello world', 'world');            -- 7 (返回起始位置)
SELECT LOCATE('world', 'hello world');           -- 7 (参数顺序与 INSTR 相反!)
SELECT POSITION('world' IN 'hello world');       -- 7 (SQL 标准语法)
-- LOCATE 独有: 支持第三个参数指定搜索起始位置
SELECT LOCATE('l', 'hello world', 4);            -- 4 (从第4个字符开始搜索)

-- 替换
SELECT REPLACE('hello world', 'world', 'mysql'); -- 'hello mysql'
SELECT INSERT('hello world', 7, 5, 'mysql');     -- 'hello mysql' (位置替换)
```

## 填充、修剪、格式化

```sql
SELECT LPAD('42', 5, '0');             -- '00042' (左填充)
SELECT RPAD('hi', 5, '.');            -- 'hi...' (右填充)

SELECT TRIM('  hello  ');              -- 'hello'
SELECT TRIM(LEADING '0' FROM '00042'); -- '42' (去前导零)
SELECT LTRIM('  hello');               -- 'hello'
SELECT RTRIM('hello  ');               -- 'hello'
SELECT REVERSE('hello');               -- 'olleh'
SELECT REPEAT('ab', 3);                -- 'ababab'
SELECT UPPER('hello');                 -- 'HELLO' (受 COLLATION 影响)
SELECT LOWER('HELLO');                 -- 'hello'
```

## 正则表达式 (8.0+: ICU 正则引擎)

### 之前: Henry Spencer 正则库（功能有限）

8.0+: 替换为 ICU 正则引擎（完整 Unicode 支持）
```sql
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');   -- 'abc # def'
SELECT REGEXP_SUBSTR('abc 123 def', '[0-9]+');         -- '123'
SELECT REGEXP_INSTR('abc 123 def', '[0-9]+');          -- 5 (位置)
SELECT 'hello123' REGEXP '^[a-z]+[0-9]+$';             -- 1 (true)
SELECT REGEXP_LIKE('hello123', '^[a-z]+[0-9]+$');      -- 1 (8.0+ 函数形式)

-- 横向对比:
--   MySQL 8.0:  REGEXP_REPLACE/REGEXP_SUBSTR (ICU 引擎)
--   PostgreSQL: regexp_replace/regexp_matches (POSIX)，~ 操作符
--   Oracle:     REGEXP_REPLACE/REGEXP_SUBSTR/REGEXP_COUNT
--   SQL Server: 无内置正则! 需要 CLR 函数或 LIKE 模拟
--   ClickHouse: match()/extract()/replaceRegexpAll() (RE2 引擎)
```

## FORMAT 和编码函数

```sql
SELECT FORMAT(1234567.89, 2);         -- '1,234,567.89' (千分位)
SELECT FORMAT(1234567.89, 2, 'de_DE'); -- '1.234.567,89' (德语)
SELECT HEX('abc');                     -- '616263'
SELECT UNHEX('616263');                -- 'abc'
SELECT ASCII('A');                     -- 65
SELECT CHAR(65);                       -- 'A'
```

## 版本演进与最佳实践

MySQL 5.7:  字符串函数基本完备
MySQL 8.0:  REGEXP_REPLACE/REGEXP_SUBSTR (ICU 正则引擎)
            REGEXP_LIKE (RLIKE 的函数形式)

实践建议:
  1. 用 CONCAT_WS 而非 CONCAT 拼接可能为 NULL 的列
  2. 不要依赖 || 做拼接 -- 用 CONCAT()（跨方言安全）
  3. 用 CHAR_LENGTH 而非 LENGTH 获取字符数（多字节安全）
  4. 从 PG/Oracle 迁移时注意: LENGTH 语义不同、|| 语义不同
  5. 正则功能在 8.0+ 才完整可用（之前的 REGEXP 只支持匹配，不支持替换）
  6. COLLATION 影响 UPPER/LOWER/比较行为，选择 COLLATION 时需考虑函数行为
