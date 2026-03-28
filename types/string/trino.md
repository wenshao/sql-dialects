# Trino: 字符串类型

> 参考资料:
> - [Trino - Data Types](https://trino.io/docs/current/language/types.html)
> - [Trino - String Functions](https://trino.io/docs/current/functions/string.html)

**引擎定位**: 分布式查询引擎（前身 Presto），不存储数据。通过 Connector 查询异构数据源（Hive/Iceberg/RDBMS）。

```sql
CREATE TABLE examples (
    code       CHAR(10),                  -- 定长
    name       VARCHAR(255),              -- 变长有限制
    content    VARCHAR                    -- 变长无限制（推荐）
);

```

**注意:** 不支持 TEXT / STRING 类型名（使用 VARCHAR）
CHAR 比较时尾部空格参与比较
VARCHAR 比较时尾部空格也参与比较

VARBINARY（二进制数据）
```sql
CREATE TABLE files (data VARBINARY);

```

类型转换
```sql
SELECT CAST('hello' AS VARCHAR(10));
SELECT CAST(123 AS VARCHAR);
SELECT TRY_CAST('abc' AS INTEGER);        -- 转换失败返回 NULL

```

字符串字面量
```sql
SELECT 'hello world';                     -- 单引号
SELECT U&'\0041\0042';                    -- Unicode 转义
SELECT X'48454C4C4F';                     -- 十六进制（VARBINARY）

```

排序规则
Trino 不支持列级 COLLATION，但有排序函数
比较时大小写敏感

**注意:** 没有 ENUM 类型
**注意:** 没有 BLOB/CLOB 类型
**注意:** 底层存储取决于 Connector（Hive、Iceberg 等）
**注意:** VARCHAR 无限制时等同于最大长度
