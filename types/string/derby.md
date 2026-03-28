# Derby: 字符串类型

> 参考资料:
> - [Derby SQL Reference](https://db.apache.org/derby/docs/10.16/ref/)
> - [Derby Developer Guide](https://db.apache.org/derby/docs/10.16/devguide/)


VARCHAR(n): 变长字符串，最大 32672 字节
CHAR(n): 定长字符串，最大 254 字节
LONG VARCHAR: 长变长字符串，最大 32700 字节
CLOB: 大文本对象，最大 2GB

```sql
CREATE TABLE users (
    id       INT NOT NULL GENERATED ALWAYS AS IDENTITY,
    username VARCHAR(64) NOT NULL,
    email    VARCHAR(128),
    code     CHAR(10),
    bio      CLOB,
    notes    LONG VARCHAR,
    PRIMARY KEY (id)
);
```

VARCHAR 最大长度：32672 字节
CHAR 最大长度：254 字节
LONG VARCHAR 最大长度：32700 字节
CLOB 最大大小：2GB

## 类型特性


CHAR 会自动补空格
VARCHAR 不补空格
CLOB 不能用于索引和排序
类型转换

```sql
SELECT CAST(123 AS VARCHAR(10));
SELECT CAST('2024-01-15' AS DATE);
```

## 字符串字面量

```sql
SELECT 'hello world';
SELECT 'it''s a test';                        -- 转义单引号
```

## 字符串拼接

```sql
SELECT username || ' <' || email || '>' FROM users;
```

## 二进制类型


CHAR FOR BIT DATA(n): 定长二进制
VARCHAR FOR BIT DATA(n): 变长二进制，最大 32672
LONG VARCHAR FOR BIT DATA: 长二进制，最大 32700
BLOB: 大二进制对象，最大 2GB

```sql
CREATE TABLE files (
    id   INT NOT NULL GENERATED ALWAYS AS IDENTITY,
    name VARCHAR(100),
    data BLOB,
    PRIMARY KEY (id)
);
```

## 字符串函数


## UPPER / LOWER

```sql
SELECT UPPER('hello');
SELECT LOWER('HELLO');
```

## LENGTH / CHAR_LENGTH

```sql
SELECT LENGTH('hello');                        -- 5
```

## SUBSTR

```sql
SELECT SUBSTR('hello world', 7, 5);           -- 'world'
```

## LOCATE

```sql
SELECT LOCATE('world', 'hello world');         -- 7
```

## TRIM / LTRIM / RTRIM

```sql
SELECT TRIM('  hello  ');
SELECT LTRIM('  hello');
SELECT RTRIM('hello  ');
```

## REPLACE

```sql
SELECT REPLACE('hello world', 'world', 'derby');
```

注意：VARCHAR 最大 32672 字节
注意：CHAR 最大 254 字节
注意：没有 TEXT 类型（使用 CLOB）
注意：没有 ENUM 类型
注意：不支持 NVARCHAR 等 Unicode 类型（默认 UTF-8）
注意：支持 || 拼接运算符
