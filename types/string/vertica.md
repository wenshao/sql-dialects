# Vertica: 字符串类型

> 参考资料:
> - [Vertica SQL Reference](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/SQLReferenceManual.htm)
> - [Vertica Functions](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Functions.htm)


CHAR(n) / CHARACTER(n): 定长，最大 65000 字节，尾部补空格
VARCHAR(n) / CHARACTER VARYING(n): 变长，最大 65000 字节
LONG VARCHAR: 变长，最大 32000000 字节（32MB）
BINARY(n) / VARBINARY(n): 二进制，最大 65000 字节
LONG VARBINARY: 二进制，最大 32000000 字节

```sql
CREATE TABLE examples (
    code       CHAR(10),                  -- 定长
    name       VARCHAR(255),              -- 变长（推荐）
    content    LONG VARCHAR,              -- 大文本
    data       VARBINARY(1000),           -- 二进制数据
    large_data LONG VARBINARY             -- 大二进制数据
);
```


VARCHAR 默认长度为 80
```sql
CREATE TABLE t (name VARCHAR);            -- 等同于 VARCHAR(80)
```


UUID 类型
```sql
CREATE TABLE t (
    id UUID DEFAULT UUID_GENERATE()
);
```


类型转换
```sql
SELECT CAST('123' AS INT);
SELECT '123'::INT;                        -- 简写
SELECT TO_CHAR(123, '999');
SELECT TO_CHAR(CURRENT_TIMESTAMP, 'YYYY-MM-DD');
```


字符串字面量
```sql
SELECT 'hello world';                     -- 单引号
SELECT E'hello\nworld';                   -- 转义字符串
```


字符串运算符
```sql
SELECT 'hello' || ' ' || 'world';        -- 拼接
SELECT 'hello' LIKE 'hel%';              -- 模式匹配
SELECT 'hello' ILIKE 'HEL%';            -- 不区分大小写
SELECT REGEXP_LIKE('hello', 'h.*o');     -- 正则
```


编码
```sql
CREATE TABLE encoded_strings (
    name VARCHAR(255) ENCODING RLE,       -- 适合低基数
    code VARCHAR(32) ENCODING BLOCKDICT_COMP
);
```


Flex 表中的字符串
```sql
CREATE FLEX TABLE flex_data ();
-- Flex 表中所有值存储为 LONG VARBINARY
```


注意：VARCHAR 默认长度 80（不指定时）
注意：LONG VARCHAR 最大 32MB
注意：支持 ILIKE（大小写不敏感 LIKE）
注意：支持 UUID 类型
注意：|| 运算符用于字符串拼接
注意：列编码选择影响存储效率
