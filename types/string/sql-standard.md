# SQL 标准: 字符串类型

> 参考资料:
> - [ISO/IEC 9075 SQL Standard](https://www.iso.org/standard/76583.html)
> - [Modern SQL - by Markus Winand](https://modern-sql.com/)
> - [SQL Standard Features Comparison (jOOQ)](https://www.jooq.org/diff)

SQL-86 (SQL1):
CHARACTER(n): 定长字符串

SQL-92 (SQL2):
CHARACTER(n) / CHAR(n): 定长，尾部补空格
CHARACTER VARYING(n) / VARCHAR(n): 变长，最大 n 字符
BIT(n): 定长位串
BIT VARYING(n): 变长位串

```sql
CREATE TABLE examples (
    code       CHARACTER(10),             -- 定长
    name       CHARACTER VARYING(255)     -- 变长
);
```

SQL:1999 (SQL3):
CHARACTER LARGE OBJECT / CLOB: 大字符对象
BINARY LARGE OBJECT / BLOB: 大二进制对象
```sql
CREATE TABLE documents (
    content    CLOB,
    data       BLOB
);
```

SQL:2003:
无字符串类型重大变化

SQL:2008:
无字符串类型重大变化

SQL:2011:
无字符串类型重大变化

SQL:2016:
无字符串类型重大变化

SQL:2023:
无字符串类型重大变化

标准排序规则
```sql
SELECT * FROM t ORDER BY name COLLATE "en_US";
```

标准类型转换
```sql
SELECT CAST('123' AS INTEGER);
```

- **注意：标准中没有 TEXT 类型（各厂商扩展）**
- **注意：标准中没有 ENUM 类型**
- **注意：标准中没有 STRING 类型（BigQuery/Hive 扩展）**
- **注意：BIT / BIT VARYING 在 SQL:2003 中标记为可选特性**
- **注意：大多数数据库都在标准基础上做了大量扩展**
