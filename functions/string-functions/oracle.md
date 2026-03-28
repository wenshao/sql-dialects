# Oracle: 字符串函数

> 参考资料:
> - [Oracle SQL Language Reference - Character Functions](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Single-Row-Functions.html)

## 拼接（|| 运算符是 Oracle 的核心字符串操作）

```sql
SELECT 'hello' || ' ' || 'world' FROM DUAL;    -- 'hello world'
SELECT CONCAT('hello', ' world') FROM DUAL;     -- CONCAT 只接受 2 个参数!

-- Oracle CONCAT 只接受 2 个参数，这是独特的限制:
-- 多个拼接只能嵌套: CONCAT(CONCAT('a', 'b'), 'c')
-- 或用 || 运算符（推荐）

-- || 与 NULL 的行为:
SELECT 'hello' || NULL FROM DUAL;               -- 'hello'（NULL 被忽略!）
-- 这是 Oracle 独有的: || 将 NULL 视为空字符串
-- 由于 '' = NULL，'hello' || '' 也返回 'hello'
--
-- 横向对比:
--   Oracle:     'hello' || NULL → 'hello'
--   PostgreSQL: 'hello' || NULL → NULL（SQL 标准行为）
--   MySQL:      CONCAT('hello', NULL) → NULL
--   SQL Server: 'hello' + NULL → NULL（需要 SET CONCAT_NULL_YIELDS_NULL OFF 改变）
```

## 长度

```sql
SELECT LENGTH('hello') FROM DUAL;               -- 5（字符数）
SELECT LENGTHB('你好') FROM DUAL;                -- 6（字节数，UTF-8 下）

-- '' = NULL 陷阱:
SELECT LENGTH('') FROM DUAL;                    -- NULL（不是 0!）
-- 因为 '' = NULL，LENGTH(NULL) = NULL

-- 横向对比:
--   Oracle:     LENGTH('') → NULL
--   PostgreSQL: LENGTH('') → 0
--   MySQL:      LENGTH('') → 0
--   SQL Server: LEN('') → 0
```

## 大小写转换

```sql
SELECT UPPER('hello') FROM DUAL;                -- 'HELLO'
SELECT LOWER('HELLO') FROM DUAL;                -- 'hello'
SELECT INITCAP('hello world') FROM DUAL;        -- 'Hello World'
```

## 截取（SUBSTR，Oracle 下标从 1 开始）

```sql
SELECT SUBSTR('hello world', 7, 5) FROM DUAL;   -- 'world'
SELECT SUBSTRB('hello world', 7, 5) FROM DUAL;  -- 按字节截取

-- Oracle 独有: 起始位置为 0 时视为 1
-- SUBSTR('hello', 0, 3) → 'hel'（与起始位置 1 相同）

-- Oracle 没有 LEFT/RIGHT 函数，用 SUBSTR 替代:
-- LEFT(s, n)  → SUBSTR(s, 1, n)
-- RIGHT(s, n) → SUBSTR(s, -n)
```

## 查找

```sql
SELECT INSTR('hello world', 'world') FROM DUAL;  -- 7
SELECT INSTR('hello world hello', 'hello', 1, 2) FROM DUAL;  -- 13（第2次出现）
-- INSTR 的 4 参数形式是 Oracle 独有的: INSTR(str, substr, start, nth)
```

## 替换 / 填充 / 修剪

```sql
SELECT REPLACE('hello world', 'world', 'oracle') FROM DUAL;
SELECT LPAD('42', 5, '0') FROM DUAL;            -- '00042'
SELECT RPAD('hi', 5, '.') FROM DUAL;            -- 'hi...'
SELECT TRIM('  hello  ') FROM DUAL;              -- 'hello'
SELECT TRIM(BOTH 'x' FROM 'xxhelloxx') FROM DUAL; -- 'hello'
SELECT LTRIM('  hello') FROM DUAL;               -- 'hello'
SELECT RTRIM('hello  ') FROM DUAL;               -- 'hello'
```

## TRANSLATE: 逐字符替换（Oracle 独有的强大函数）

```sql
SELECT TRANSLATE('hello', 'helo', 'HELO') FROM DUAL;  -- 'HELLO'
-- TRANSLATE 是逐字符映射: h→H, e→E, l→L, o→O

-- 常用技巧: 删除所有数字
SELECT TRANSLATE('abc123def', '0123456789', ' ') FROM DUAL;
```

替换为空格再 TRIM

'' = NULL 陷阱:
```sql
SELECT TRANSLATE('hello', 'helo', '') FROM DUAL; -- NULL!
-- 因为 '' = NULL，第三个参数变成 NULL，整个结果为 NULL
-- 这是 TRANSLATE 中著名的陷阱
```

## 正则表达式（10g+，Oracle 较早支持）

```sql
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#') FROM DUAL;
SELECT REGEXP_SUBSTR('abc 123 def', '[0-9]+') FROM DUAL;
SELECT REGEXP_COUNT('a1b2c3', '[0-9]') FROM DUAL;   -- 3（11g+）
SELECT REGEXP_INSTR('abc 123 def', '[0-9]+') FROM DUAL;
```

## LISTAGG（字符串聚合，11g R2+）

```sql
SELECT LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;
SELECT LISTAGG(username, ', ' ON OVERFLOW TRUNCATE '...')
    WITHIN GROUP (ORDER BY username) FROM users;  -- 12c R2+: 防溢出
```

## REVERSE（非文档化函数，10g+ 可用）

```sql
SELECT REVERSE('hello') FROM DUAL;              -- 'olleh'
-- REVERSE 是非文档化函数，但广泛使用
```

## 对引擎开发者的总结

1. || 运算符对 NULL 的处理是 Oracle 独有的（忽略 NULL），
   PostgreSQL/SQL Server 遵循标准（NULL 传染）。
2. LENGTH('') → NULL 是 '' = NULL 的直接后果，迁移时极易出错。
3. CONCAT 只接受 2 个参数是 Oracle 的历史包袱，新引擎应支持多参数。
4. TRANSLATE 在替换字符串为 '' 时返回 NULL，因为 '' = NULL。
5. INSTR 的 4 参数形式（第 N 次出现）是 Oracle 独有的实用功能。
6. LISTAGG 的 ON OVERFLOW TRUNCATE 是从实际痛点中学到的优秀设计。
