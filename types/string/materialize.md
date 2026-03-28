# Materialize: 字符串类型

> 参考资料:
> - [Materialize SQL Reference](https://materialize.com/docs/sql/)
> - [Materialize SQL Functions](https://materialize.com/docs/sql/functions/)
> - Materialize 兼容 PostgreSQL 字符串类型
> - TEXT: 变长字符串，无长度限制（推荐）
> - VARCHAR(n): 变长字符串，最大 n 个字符
> - CHAR(n): 定长字符串，自动补空格
> - BYTEA: 二进制数据

```sql
CREATE TABLE users (
    id       INT,
    name     TEXT NOT NULL,                  -- 推荐使用 TEXT
    email    VARCHAR(128),
    code     CHAR(10),
    avatar   BYTEA
);
```

## TEXT 是推荐类型，无需指定长度

类型转换

```sql
SELECT CAST(123 AS TEXT);
SELECT 123::TEXT;
SELECT '123'::INT;
```

## 字符串字面量

```sql
SELECT 'hello world';
SELECT 'it''s a test';
SELECT E'hello\nworld';
```

## 字符串函数


## 拼接

```sql
SELECT 'hello' || ' ' || 'world';
SELECT CONCAT('hello', ' ', 'world');
```

## 长度

```sql
SELECT LENGTH('hello');
SELECT CHAR_LENGTH('hello');
SELECT OCTET_LENGTH('hello');
```

## 大小写

```sql
SELECT UPPER('hello');
SELECT LOWER('HELLO');
```

## 截取

```sql
SELECT SUBSTRING('hello world' FROM 7 FOR 5);
SELECT LEFT('hello', 3);
SELECT RIGHT('hello', 3);
```

## 查找

```sql
SELECT POSITION('world' IN 'hello world');
```

## 替换和修剪

```sql
SELECT REPLACE('hello world', 'world', 'materialize');
SELECT TRIM('  hello  ');
SELECT LTRIM('  hello');
SELECT RTRIM('hello  ');
```

## 填充

```sql
SELECT LPAD('42', 5, '0');
SELECT RPAD('hi', 5, '.');
```

## 正则

```sql
SELECT REGEXP_MATCH('abc 123', '[0-9]+');
```

注意：Materialize 兼容 PostgreSQL 的字符串类型和函数
注意：TEXT 是推荐的字符串类型
注意：支持 || 拼接运算符
注意：支持正则表达式函数
