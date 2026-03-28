# MaxCompute (ODPS): 字符串类型

> 参考资料:
> - [1] MaxCompute SQL - Data Types
>   https://help.aliyun.com/zh/maxcompute/user-guide/data-types-1
> - [2] MaxCompute - String Functions
>   https://help.aliyun.com/zh/maxcompute/user-guide/string-functions


## 1. 字符串类型总览


STRING:      变长字符串，最大 8MB（1.0 默认, 核心类型）
VARCHAR(n):  变长字符串，1~65535 字符（2.0+, 需开启 odps2 类型系统）
CHAR(n):     定长字符串，1~255 字符（2.0+, 需开启 odps2 类型系统）
BINARY:      二进制数据，最大 8MB（2.0+）


```sql
SET odps.sql.type.system.odps2 = true;      -- 启用 2.0 类型系统

CREATE TABLE examples (
    code       CHAR(10),                    -- 定长，不足右补空格
    name       VARCHAR(255),                -- 变长，有长度限制
    content    STRING,                      -- 变长，无长度限制（推荐）
    raw_data   BINARY                       -- 二进制数据
);

```

## 2. 设计决策: STRING 为什么是核心类型?


### 1.0 类型系统只有 STRING —— 所有字符串都是 STRING

   设计哲学: 极简类型系统减少认知负担
   分区列几乎都是 STRING（目录路径中的值）
   JSON 数据用 STRING 存储（2024 年之前没有 JSON 类型）
   日期用 STRING 存储（1.0 只有 DATETIME，很多用户用 '20240115' 格式）

 为什么后来引入 VARCHAR/CHAR?
   从 MySQL/PostgreSQL 迁移时: VARCHAR(255) 是常见的列定义
   存储优化: VARCHAR(10) 可以使用更紧凑的编码
   数据质量: VARCHAR(10) 在写入时检查长度，比 STRING 更安全
   但实际使用: 大多数 MaxCompute 用户仍然使用 STRING

 对比:
   MaxCompute: STRING 为主，VARCHAR/CHAR 可选
   Hive:       STRING 为主（相同设计，MaxCompute 继承）
   BigQuery:   STRING（无长度限制，唯一的字符串类型）
   Snowflake:  VARCHAR/STRING/TEXT（三个别名，都是同一种类型）
   PostgreSQL: TEXT 推荐（VARCHAR 有长度检查但无性能差异）
   MySQL:      VARCHAR(n) 为主（n 影响索引和临时表）
   ClickHouse: String（无长度限制）+ FixedString(N)

## 3. 编码与大小写


 内部编码: UTF-8
 对比:
   MaxCompute: UTF-8（固定，不可配置）
   MySQL:      utf8mb4 才是真 UTF-8（utf8 是 3 字节假 UTF-8）
   PostgreSQL: 建库时指定编码
   Oracle:     AL32UTF8（真 UTF-8）
   SQL Server: NVARCHAR 用 UTF-16，VARCHAR 可用 UTF-8 排序规则（2019+）

 大小写敏感: MaxCompute 字符串比较默认大小写敏感
   这与 MySQL 相反! MySQL 默认大小写不敏感（utf8mb4_general_ci）
   迁移陷阱: 从 MySQL 迁移到 MaxCompute 后，WHERE name = 'Alice' 不匹配 'alice'
   解决: 使用 UPPER/LOWER 函数或 RLIKE '(?i)pattern'

 不支持字符集和排序规则设置（COLLATE）
 对比: MySQL 的 4 级字符集层次（Server→Database→Table→Column）

## 4. 字符串字面量


```sql
SELECT 'hello world';                       -- 单引号
SELECT "hello world";                       -- 双引号也可以（Hive 兼容）
```

对比: 标准 SQL 只允许单引号，双引号用于标识符

转义字符

```sql
SELECT 'it\'s';                             -- 单引号转义
SELECT 'line1\nline2';                      -- \n 换行

```

## 5. LENGTH 的字节/字符陷阱


LENGTH 返回字节数（不是字符数!）

```sql
SELECT LENGTH('hello');                     -- 5 字节
SELECT LENGTH('你好');                       -- 6 字节（UTF-8 每个汉字 3 字节）

```

CHAR_LENGTH / CHARACTER_LENGTH 返回字符数（2.0+）

```sql
SELECT CHAR_LENGTH('hello');                -- 5 字符
SELECT CHAR_LENGTH('你好');                  -- 2 字符

```

LENGTHB: 显式字节长度

```sql
SELECT LENGTHB('你好');                      -- 6 字节

```

 这是从 Hive 继承的设计:
   Hive 的 LENGTH 也返回字节数（不是字符数）
   迁移陷阱: MySQL/PostgreSQL 的 LENGTH 返回字符数
   对引擎开发者: LENGTH 的语义（字节 vs 字符）应在文档中明确说明

## 6. STRING 作为分区键的限制


 分区键值最大 256 字节（编码在目录路径中）
 分区键不能存储超长字符串
 分区键通常是短标识符: '20240115', 'cn', 'web'

## 7. 类型转换


```sql
SELECT CAST('123' AS BIGINT);               -- 字符串→整数
SELECT CAST(123 AS STRING);                 -- 整数→字符串
SELECT CAST('2024-01-15' AS DATE);          -- 字符串→日期

```

隐式转换: MaxCompute 支持部分隐式转换

```sql
SELECT '42' + 0;                            -- STRING → DOUBLE → 42.0
SELECT CONCAT('value: ', 42);               -- 42 隐式转为 STRING

```

 对比:
   MaxCompute: 较宽松的隐式转换（类似 Hive）
   PostgreSQL: 严格（需显式 CAST）
   MySQL:      极宽松（'123abc' + 0 = 123，截断警告）

## 8. 横向对比: 字符串类型


 主要字符串类型:
   MaxCompute: STRING（无限制）+ VARCHAR(n)/CHAR(n)（2.0+）
   Hive:       STRING（无限制）+ VARCHAR/CHAR（2.0+）
   BigQuery:   STRING（无限制）
   Snowflake:  VARCHAR/STRING/TEXT（别名，无限制）
   PostgreSQL: TEXT（推荐）+ VARCHAR(n)（有检查）
   MySQL:      VARCHAR(n)（主要）+ TEXT 分级（TINY/TEXT/MEDIUM/LONG）
   ClickHouse: String（无限制）+ FixedString(N)

 大文本:
   MaxCompute: STRING 最大 8MB（旧版 2MB）
   BigQuery:   STRING 无限制
   PostgreSQL: TEXT 最大 1GB
   MySQL:      LONGTEXT 最大 4GB
   ClickHouse: String 无限制

 ENUM/SET:
   MaxCompute: 不支持（用 STRING + 约定值）
   MySQL:      支持 ENUM/SET
   PostgreSQL: 支持 CREATE TYPE ... AS ENUM

## 9. 对引擎开发者的启示


### 1. 大数据引擎用单一 STRING 类型更简洁（BigQuery/ClickHouse 的做法）

### 2. VARCHAR(n) 在 OLAP 场景中价值有限（没有索引长度限制的问题）

### 3. LENGTH 的字节/字符语义必须在 API 设计时明确决定

### 4. 大小写敏感性应该与目标用户群的迁移来源一致

### 5. UTF-8 作为唯一编码是现代引擎的最佳实践（避免 MySQL utf8 的教训）

### 6. 分区键的长度限制应在 DDL 编译期检查（而非运行时报错）

