# Spark SQL: 字符串类型 (String Types)

> 参考资料:
> - [1] Spark SQL - Data Types
>   https://spark.apache.org/docs/latest/sql-ref-datatypes.html


## 1. 类型概览

STRING:     变长字符串，无长度限制，UTF-8 编码（推荐使用）
VARCHAR(n): 变长字符串，限定最大长度 n（Spark 3.1+ 强制）
CHAR(n):    定长字符串，固定长度 n，空格填充（Spark 3.1+ 强制）
BINARY:     二进制数据


```sql
CREATE TABLE examples (
    code    CHAR(10),                            -- 定长 10 字符（3.1+ 填充+截断）
    name    VARCHAR(255),                        -- 最大 255 字符（3.1+ 强制）
    content STRING                               -- 无限制（推荐）
) USING PARQUET;

```

## 2. STRING: Spark 的统一字符串类型


 Spark 推荐: 总是使用 STRING
 VARCHAR(n) 在 3.1 之前被静默忽略（当作 STRING 处理!）
 CHAR(n)    在 3.1 之前也被静默忽略

 设计理由:
   在列式存储（Parquet/ORC）中，VARCHAR(n) 的长度限制没有存储优化价值。
   传统数据库的 VARCHAR(n) 限制主要服务于:
1. 内存分配优化（行存储引擎预分配 n 字节）

2. 索引长度限制（B+Tree 索引键有最大长度）

在列式存储中，这两个需求都不存在——列独立存储，自动压缩。

对比:
MySQL:      VARCHAR(255) vs VARCHAR(256) 影响行格式（1 字节 vs 2 字节长度前缀）
PostgreSQL: VARCHAR(n) 有限制但推荐用 TEXT（无限制）
BigQuery:   STRING（无长度限制）
ClickHouse: String（无长度限制）
Hive:       STRING（与 Spark 一致，无长度限制）
Flink SQL:  VARCHAR(n) / STRING

对引擎开发者的启示:
如果你的引擎使用列式存储，VARCHAR(n) 的长度限制是可选的。
BigQuery/ClickHouse/Spark 都选择了无长度限制的 STRING——这是列式引擎的共识。
但保留 VARCHAR(n) 语法对迁移兼容性有价值。

BINARY: 二进制数据

```sql
CREATE TABLE files (data BINARY) USING PARQUET;

```

## 3. 字符串字面量

```sql
SELECT 'hello world';                                    -- 单引号（标准）
SELECT "hello world";                                    -- 双引号（Spark 特色!）
SELECT 'it''s a test';                                   -- 转义单引号
SELECT 'line1\nline2';                                   -- 转义序列

```

 双引号字符串是 Spark/Hive 特色:
   SQL 标准: 双引号用于标识符（"table_name"）
   Spark:    双引号也可以用于字符串字面量
   PostgreSQL: 双引号仅用于标识符，字符串必须用单引号
 迁移时这是常见的语法差异

## 4. Unicode / UTF-8

```sql
SELECT '你好世界';                                        -- UTF-8 原生支持
SELECT LENGTH('你好');                                    -- 2 (字符数)
SELECT OCTET_LENGTH('你好');                              -- 6 (UTF-8 字节数)

```

 Spark 内部统一使用 UTF-8（不像 MySQL 有 utf8/utf8mb4 的历史问题）
 对比:
   MySQL:      utf8 != UTF-8！utf8 只支持 3 字节，必须用 utf8mb4
   PostgreSQL: UTF-8 是真正的 UTF-8
   SQL Server: NVARCHAR 用 UTF-16; 2019+ VARCHAR 可用 UTF-8 排序规则
   Spark:      UTF-8（真正的 UTF-8，无 MySQL 的历史问题）

## 5. 编码与转换

```sql
SELECT ENCODE('hello', 'UTF-8');                         -- STRING -> BINARY
SELECT DECODE(ENCODE('hello', 'UTF-8'), 'UTF-8');        -- BINARY -> STRING
SELECT BASE64(CAST('hello' AS BINARY));                  -- Base64 编码
SELECT UNBASE64('aGVsbG8=');                             -- Base64 解码

```

类型转换

```sql
SELECT CAST(123 AS STRING);                              -- 数字 -> 字符串
SELECT CAST('123' AS INT);                               -- 字符串 -> 数字
SELECT STRING(123);                                      -- 函数式转换

```

## 6. Collation（排序规则，Spark 4.0+）


 Spark 4.0 引入 Collation 支持:
   默认: 二进制比较（逐字节比较，大小写敏感）
   Spark 4.0+: 支持指定排序规则（如 UTF8_BINARY, UTF8_LCASE）

 对比:
   MySQL:      多级排序规则（数据库/表/列），utf8mb4_unicode_ci 等
   PostgreSQL: ICU 排序规则（12+），CREATE COLLATION 自定义
   Oracle:     NLS_SORT, NLS_COMP 参数控制
   Spark 3.x:  仅二进制比较——不区分大小写需要手动 LOWER()
   Spark 4.0:  开始支持 Collation（CREATE TABLE t (name STRING COLLATE UTF8_LCASE)）

## 7. 字符串类型的局限性


 无 ENUM 类型: 使用 STRING + CHECK 约束（Delta Lake）
 无 SET 类型: 使用 ARRAY<STRING>
 无 TEXT/CLOB 分级: STRING 统一处理所有长度
 最大字符串长度受 JVM 内存和 Spark 配置限制（非固定上限）

## 8. 版本演进

Spark 2.0: STRING, BINARY
Spark 3.1: VARCHAR(n) 强制长度限制, CHAR(n) 强制定长
Spark 3.4: :: 运算符（字符串转换）
Spark 4.0: Collation 支持, Variant 类型（半结构化字符串替代）

限制:
VARCHAR(n) 在 3.1 之前不强制（静默忽略长度限制）
CHAR(n) 使用空格填充和比较时修剪（注意行为差异）
双引号可用于字符串（非标准，迁移到其他引擎可能报错）
无 ENUM/SET 类型
默认仅二进制比较（4.0 之前不支持 Collation）
无 ILIKE（大小写不敏感比较需手动 LOWER()）

