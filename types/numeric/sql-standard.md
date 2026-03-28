# SQL 标准: 数值类型

> 参考资料:
> - [ISO/IEC 9075 SQL Standard](https://www.iso.org/standard/76583.html)
> - [Modern SQL - by Markus Winand](https://modern-sql.com/)
> - [SQL Standard Features Comparison (jOOQ)](https://www.jooq.org/diff)

SQL-86 (SQL1):
INTEGER / INT: 整数
SMALLINT: 小整数
NUMERIC(p, s): 定点数
DECIMAL(p, s) / DEC(p, s): 定点数
FLOAT(p): 浮点数
REAL: 单精度浮点
DOUBLE PRECISION: 双精度浮点

```sql
CREATE TABLE examples (
    id         INTEGER,
    small_val  SMALLINT,
    price      NUMERIC(10, 2),
    rate       DECIMAL(5, 4),
    value      DOUBLE PRECISION
);
```

SQL-92 (SQL2):
增加了精度规范的细化
BIT / BIT VARYING: 位串类型
```sql
CREATE TABLE t (flags BIT(8));
```

SQL:1999 (SQL3):
BOOLEAN: 布尔类型（TRUE / FALSE / UNKNOWN）
```sql
CREATE TABLE t (active BOOLEAN DEFAULT TRUE);
```

BIGINT: 大整数（部分文档归于此版本）

SQL:2003:
BIGINT: 大整数（正式标准化）
```sql
CREATE TABLE t (big_val BIGINT);
```

SQL:2008:
无数值类型重大变化

SQL:2011:
无数值类型重大变化

SQL:2016:
DECFLOAT: 十进制浮点数（IEEE 754-2008）
DECFLOAT(16): 16 位十进制精度
DECFLOAT(34): 34 位十进制精度
```sql
SELECT CAST(3.14 AS DECFLOAT(16));
```

SQL:2023:
无数值类型重大变化

标准类型转换
```sql
SELECT CAST('123' AS INTEGER);
SELECT CAST(3.14 AS NUMERIC(10, 2));
```

- **注意：标准中没有 UNSIGNED（MySQL 扩展）**
- **注意：标准中没有 TINYINT / MEDIUMINT（各厂商扩展）**
- **注意：标准中没有 AUTO_INCREMENT / SERIAL / IDENTITY（各厂商扩展）**
- **注意：SQL:2003 引入 GENERATED ALWAYS AS IDENTITY 作为自增标准**
- **注意：BIT 类型在 SQL:2003 标记为可选特性，很少使用**
