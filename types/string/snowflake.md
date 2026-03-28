# Snowflake: 字符串类型

> 参考资料:
> - [1] Snowflake SQL Reference - String Data Types
>   https://docs.snowflake.com/en/sql-reference/data-types-text


## 1. 类型概述


VARCHAR(n): 变长字符串，n 可选（默认 16,777,216 = 16MB）
CHAR(n):    别名，与 VARCHAR 行为完全相同（无尾部填充）
STRING:     VARCHAR 的别名（推荐使用）
TEXT:       VARCHAR 的别名
BINARY(n):  二进制数据，最大 8MB
VARBINARY:  BINARY 的别名


```sql
CREATE TABLE examples (
    code    CHAR(10),           -- 实际等同 VARCHAR(10)（无填充!）
    name    VARCHAR(255),
    content STRING,             -- VARCHAR 的别名，推荐
    data    BINARY
);

```

## 2. 语法设计分析（对 SQL 引擎开发者）


### 2.1 CHAR = VARCHAR（无定长语义）

 Snowflake 的 CHAR(n) 不做尾部空格填充:
   INSERT INTO t VALUES ('ab');
   SELECT LENGTH(code) FROM t;  -- 2（不是 10）
 对比:
   PostgreSQL: CHAR(10) 会填充到 10 字符（但比较时忽略尾部空格）
   MySQL:      CHAR(10) 会填充到 10 字符，存储固定长度
   Oracle:     CHAR(10) 会填充到 10 字符
 Snowflake 的设计: CHAR 只是 VARCHAR 的别名，简化了实现

### 2.2 默认 16MB

 不指定长度时 VARCHAR 默认最大 16,777,216 字节。
 指定长度对存储无影响（内部始终按实际长度存储），仅影响输入校验。
 对比:
   PostgreSQL: TEXT 无大小限制（推荐代替 VARCHAR）
   MySQL:      VARCHAR(n) 的 n 影响内存分配和索引长度
   BigQuery:   STRING（无长度限制）
 对引擎开发者的启示:
   列存引擎中字符串长度对存储无影响（按实际长度编码），
   长度限制只是逻辑约束。这与行存的定长 CHAR 有本质区别。

### 2.3 UTF-8 默认

 Snowflake 默认使用 UTF-8 编码，一个字符最多 4 字节。
 没有 MySQL 的 utf8 vs utf8mb4 问题。
 没有字符集选择（只有 UTF-8）。

## 3. 排序规则 (COLLATION)


默认: 大小写敏感，重音敏感
指定大小写不敏感:

```sql
SELECT COLLATE('hello', 'en-ci');

```

列级排序规则

```sql
CREATE TABLE t (name VARCHAR(100) COLLATE 'en-ci');

```

 对比:
   MySQL:      在表/列/数据库级别设置 COLLATE（复杂的 4 级层次）
   PostgreSQL: CREATE DATABASE ... LC_COLLATE = 'en_US.UTF-8'
   Snowflake:  COLLATE 函数或列级属性（更简单）

## 4. 字符串字面量


```sql
SELECT 'hello world';                    -- 单引号
SELECT $$hello world$$;                  -- 美元引号（避免转义）
SELECT 'it''s escaped';                  -- 单引号转义
```

 美元引号在存储过程中特别有用（避免嵌套引号转义）:
 CREATE PROCEDURE p() ... AS $$ BEGIN ... END; $$;

## 5. VARIANT 中的字符串


```sql
SELECT PARSE_JSON('{"name": "alice"}'):name::STRING;
```

 VARIANT 内部的字符串需要 ::STRING 显式转换为 SQL 字符串

## 6. 没有的类型

 无 ENUM 类型（使用 VARCHAR + CHECK 模拟，但 CHECK 不执行）
 无 TINYTEXT/TEXT/MEDIUMTEXT/LONGTEXT 分级（统一 VARCHAR）
 无 CLOB/BLOB 区分（VARCHAR = 文本, BINARY = 二进制）

## 横向对比: 字符串类型

| 特性           | Snowflake      | BigQuery  | PostgreSQL    | MySQL |
|------|------|------|------|------|
| 变长类型       | VARCHAR/STRING | STRING    | VARCHAR/TEXT  | VARCHAR/TEXT |
| 定长类型       | 无(CHAR=VARCHAR)| 无       | CHAR(有填充)  | CHAR(有填充) |
| 默认最大长度   | 16MB           | 无限制    | 1GB           | 65535B |
| 编码           | UTF-8(唯一)    | UTF-8     | 多种          | 多种 |
| COLLATE        | 函数/列级      | 不支持    | 库级+ICU      | 4级层次 |
| 美元引号       | 支持           | 不支持    | 支持          | 不支持 |
| ENUM           | 不支持         | 不支持    | 不支持        | 支持 |
| 二进制类型     | BINARY(8MB)    | BYTES     | BYTEA         | BLOB |

