# 字符串比较与排序规则：各 SQL 方言全对比

字符串比较看似简单，实则暗藏无数跨方言陷阱。`'abc' = 'ABC'` 在 MySQL 中为 TRUE，在 PostgreSQL 中却为 FALSE；`'a' = 'a  '` 在 SQL Server 中为 TRUE，在 Oracle 中为 FALSE。本文系统梳理 20 个 SQL 方言在大小写敏感、尾部空格、模式匹配、字符串拼接、正则表达式和排序规则六个维度上的行为差异。

## 大小写敏感默认值

**核心问题**: `'abc' = 'ABC'` 的结果在不同方言下完全不同，这是跨数据库迁移中最高频的 Bug 来源之一。

| 方言 | `'abc' = 'ABC'` | 默认行为 | 默认排序规则 | 说明 |
|------|:---:|------|------|------|
| MySQL | **TRUE** | 大小写不敏感 | `utf8mb4_0900_ai_ci` (8.0+) | `_ci` = case-insensitive；5.7 默认 `utf8_general_ci` |
| MariaDB | **TRUE** | 大小写不敏感 | `utf8mb4_general_ci` | 与 MySQL 一致 |
| SQL Server | **TRUE** | 大小写不敏感 | `SQL_Latin1_General_CP1_CI_AS` | `CI` = case-insensitive |
| PostgreSQL | FALSE | 大小写敏感 | 取决于操作系统 locale | 使用 `ILIKE` 或 `LOWER()` 实现不敏感匹配 |
| Oracle | FALSE | 大小写敏感 | `BINARY` 排序 | 可通过 `NLS_COMP` + `NLS_SORT` 修改 |
| SQLite | FALSE | 大小写敏感 | `BINARY` | ASCII 范围内 `NOCASE` 可用 |
| DB2 | FALSE | 大小写敏感 | 取决于数据库创建时的 locale | - |
| Snowflake | FALSE | 大小写敏感 | 默认 locale-independent | 支持 `COLLATE` 修改 |
| BigQuery | FALSE | 大小写敏感 | 无排序规则系统 | 使用 `LOWER()` / `UPPER()` |
| ClickHouse | FALSE | 大小写敏感 | 无排序规则系统 | 提供 `*CaseInsensitive` 函数族 |
| Trino | FALSE | 大小写敏感 | 无排序规则系统 | - |
| Spark SQL | FALSE | 大小写敏感 | 无排序规则系统 | 3.4+ 引入 `COLLATION` 支持 |
| Hive | FALSE | 大小写敏感 | 无排序规则系统 | - |
| Flink SQL | FALSE | 大小写敏感 | 无排序规则系统 | - |
| DuckDB | FALSE | 大小写敏感 | 无排序规则系统 | `ILIKE` 可实现不敏感匹配 |
| TiDB | **TRUE** | 大小写不敏感 | `utf8mb4_bin` (早期) / `utf8mb4_general_ci` | 与 MySQL 兼容 |
| OceanBase (MySQL) | **TRUE** | 大小写不敏感 | 同 MySQL | MySQL 兼容模式 |
| StarRocks | FALSE | 大小写敏感 | 无排序规则系统 | - |
| Doris | FALSE | 大小写敏感 | 无排序规则系统 | - |
| MaxCompute | FALSE | 大小写敏感 | 无排序规则系统 | - |

**关键发现**: 只有 MySQL/MariaDB/TiDB/OceanBase（MySQL 模式）和 SQL Server 默认大小写不敏感。所有其他方言默认大小写敏感。从 MySQL 迁移到 PostgreSQL 时，这是最容易忽视的行为差异。

### 显式控制大小写

```sql
-- PostgreSQL: 大小写不敏感比较
SELECT * FROM users WHERE name ILIKE 'john';
SELECT * FROM users WHERE LOWER(name) = LOWER('John');

-- MySQL: 强制大小写敏感比较
SELECT * FROM users WHERE name = BINARY 'abc';            -- 5.7
SELECT * FROM users WHERE name COLLATE utf8mb4_bin = 'abc'; -- 8.0+

-- SQL Server: 强制大小写敏感比较
SELECT * FROM users WHERE name COLLATE Latin1_General_BIN = 'abc';

-- Oracle: 会话级别切换
ALTER SESSION SET NLS_COMP = 'LINGUISTIC';
ALTER SESSION SET NLS_SORT = 'BINARY_CI';  -- CI = case-insensitive
```

## 尾部空格处理

**核心问题**: `'a' = 'a  '`（带尾部空格）的结果取决于方言和数据类型，这是另一个隐蔽的迁移陷阱。

SQL 标准定义了两种比较模式：

```
PAD SPACE:  比较时忽略尾部空格  →  'a' = 'a  '  为 TRUE
NO PAD:     比较时保留尾部空格  →  'a' = 'a  '  为 FALSE
```

| 方言 | `'a' = 'a  '` (VARCHAR) | `'a' = 'a  '` (CHAR) | 模式 | 说明 |
|------|:---:|:---:|------|------|
| MySQL | 取决于 collation | **TRUE** | 8.0 `_0900` 系列: NO PAD（FALSE）；`_general_ci` 等: PAD SPACE（TRUE） | 8.0 默认 `utf8mb4_0900_ai_ci` = NO PAD |
| SQL Server | **TRUE** | **TRUE** | PAD SPACE (VARCHAR + CHAR) | ANSI_PADDING ON 存储时保留，但比较时忽略 |
| PostgreSQL | FALSE | **TRUE** | NO PAD (VARCHAR) / PAD SPACE (CHAR) | 符合 SQL 标准 |
| Oracle | FALSE | **TRUE** | NO PAD (VARCHAR2) / PAD SPACE (CHAR) | 使用 `RPAD` 处理对齐 |
| SQLite | FALSE | N/A | NO PAD | 无 CHAR 类型，全部为 TEXT |
| DB2 | FALSE | **TRUE** | NO PAD (VARCHAR) / PAD SPACE (CHAR) | 符合 SQL 标准 |
| Snowflake | FALSE | FALSE | NO PAD | CHAR 不补齐，VARCHAR 和 CHAR 行为一致 |
| BigQuery | FALSE | N/A | NO PAD | 只有 STRING 类型 |
| ClickHouse | FALSE | N/A | NO PAD | 只有 String / FixedString |
| Trino | FALSE | FALSE | NO PAD | CHAR 不补齐 |
| Spark SQL | FALSE | N/A | NO PAD | 只有 STRING 类型 |
| Hive | FALSE | N/A | NO PAD | 只有 STRING 类型 |
| Flink SQL | FALSE | FALSE | NO PAD | - |
| DuckDB | FALSE | N/A | NO PAD | 只有 VARCHAR 类型 |
| TiDB | **TRUE** | **TRUE** | PAD SPACE | 与 MySQL 兼容 |
| OceanBase (MySQL) | **TRUE** | **TRUE** | PAD SPACE | MySQL 兼容模式 |
| StarRocks | FALSE | N/A | NO PAD | 只有 VARCHAR / CHAR，比较为 NO PAD |
| Doris | FALSE | N/A | NO PAD | 只有 VARCHAR / CHAR，比较为 NO PAD |

**关键发现**: MySQL 和 SQL Server 对 VARCHAR 也使用 PAD SPACE，这是**非标准行为**。SQL 标准仅要求 CHAR 类型使用 PAD SPACE。从 MySQL 迁移到 PostgreSQL 时，如果数据中有尾部空格差异，WHERE 条件和 JOIN 结果可能悄悄变化。

### 尾部空格的陷阱

```sql
-- MySQL: 这两条都能匹配到 name = 'John' 的行
SELECT * FROM users WHERE name = 'John';
SELECT * FROM users WHERE name = 'John   ';  -- 也能匹配!

-- PostgreSQL: 只有第一条能匹配
SELECT * FROM users WHERE name = 'John';
SELECT * FROM users WHERE name = 'John   ';  -- 不匹配!

-- MySQL 8.0 注意: utf8mb4_0900_ai_ci 对 VARCHAR 使用 NO PAD
-- 但旧的 utf8mb4_general_ci 仍然使用 PAD SPACE
SELECT 'a' = 'a  ' COLLATE utf8mb4_0900_ai_ci;  -- 结果取决于版本和列类型
```

## LIKE 通配符与转义

### 基础支持矩阵

| 方言 | 通配符 | 默认转义字符 | ESCAPE 子句 | ILIKE (不敏感) | 说明 |
|------|------|:---:|:---:|:---:|------|
| MySQL | `%` `_` | `\` | 支持 | 不支持 | `\` 转义在 `NO_BACKSLASH_ESCAPES` 模式下禁用 |
| MariaDB | `%` `_` | `\` | 支持 | 不支持 | 同 MySQL |
| PostgreSQL | `%` `_` | 无默认 | 支持 | **支持** | 9.1 前默认 `\` 转义，之后禁用 |
| Oracle | `%` `_` | 无默认 | 支持 | 不支持 | 必须用 ESCAPE 子句声明 |
| SQL Server | `%` `_` `[]` `[^]` | 无默认 | 支持 | 不支持 | 额外支持字符类 `[a-z]` |
| SQLite | `%` `_` | 无默认 | 支持 | 不支持 | 默认只支持 ASCII 的 LIKE |
| DB2 | `%` `_` | 无默认 | 支持 | 不支持 | - |
| Snowflake | `%` `_` | `\` | 支持 | **支持** | ILIKE 是官方推荐的不敏感匹配方式 |
| BigQuery | `%` `_` | `\` | 支持 | 不支持 | 使用 `LOWER()` + `LIKE` 实现不敏感匹配 |
| ClickHouse | `%` `_` | `\` | 支持 | **支持** | 支持 `ILIKE`（早期版本即有） |
| Trino | `%` `_` | 无默认 | 支持 | 不支持 | - |
| Spark SQL | `%` `_` | `\` | 支持 | **支持** | 3.3+ 支持 `ILIKE` |
| Hive | `%` `_` | `\` | 支持 | 不支持 | `RLIKE` 用于正则 |
| Flink SQL | `%` `_` | 无默认 | 支持 | 不支持 | - |
| DuckDB | `%` `_` | 无默认 | 支持 | **支持** | 与 PostgreSQL 兼容 |
| StarRocks | `%` `_` | `\` | 支持 | 不支持 | - |
| Doris | `%` `_` | `\` | 支持 | 不支持 | - |

**关键发现**: `ILIKE` 支持仅限 PostgreSQL、Snowflake、ClickHouse、Spark SQL（3.3+）和 DuckDB。其他方言需要 `LOWER(col) LIKE LOWER(pattern)` 或使用排序规则来实现大小写不敏感匹配。

### LIKE 与 ESCAPE 用法

```sql
-- 标准: 查找包含 % 字面量的字符串
SELECT * FROM t WHERE col LIKE '%10\%%' ESCAPE '\';

-- PostgreSQL (9.1+): 无默认转义字符，必须显式声明
SELECT * FROM t WHERE col LIKE '%10!%%' ESCAPE '!';

-- SQL Server: 额外的字符类语法
SELECT * FROM t WHERE col LIKE '[A-Z]%';      -- 以大写字母开头
SELECT * FROM t WHERE col LIKE '[^0-9]%';     -- 不以数字开头

-- ILIKE 示例 (PostgreSQL / Snowflake / DuckDB)
SELECT * FROM users WHERE name ILIKE '%john%'; -- 不敏感匹配
```

## 字符串拼接

**核心问题**: `||` 运算符在 MySQL 中默认是逻辑 OR，不是字符串拼接。

| 方言 | `\|\|` 拼接 | `+` 拼接 | `CONCAT()` | NULL 处理 (`'a' \|\| NULL`) | 说明 |
|------|:---:|:---:|:---:|------|------|
| MySQL | 不支持 | 不支持 | **CONCAT()** | CONCAT: NULL 传播 | `\|\|` 默认是 `OR`；开启 `PIPES_AS_CONCAT` 可改变 |
| MariaDB | 不支持 | 不支持 | **CONCAT()** | CONCAT: NULL 传播 | 同 MySQL |
| PostgreSQL | **支持** | 不支持 | CONCAT() | `\|\|`: NULL 传播; CONCAT: 跳过 NULL | `CONCAT()` 是 9.1+ 补充的 |
| Oracle | **支持** | 不支持 | CONCAT(a,b) | `\|\|` 和 CONCAT: **NULL 均视为空字符串（不传播）** | CONCAT 只接受 2 参数，行为同 `\|\|`；`''=NULL` |
| SQL Server | 不支持 | **支持** | CONCAT() | `+`: NULL 传播; CONCAT: 跳过 NULL | `CONCAT()` 是 2012+ 引入 |
| SQLite | **支持** | 不支持 | concat() (3.44.0+) | `\|\|`: NULL 传播; concat(): **跳过 NULL** | concat 和 `\|\|` NULL 行为不同（同 Spark） |
| DB2 | **支持** | 不支持 | CONCAT(a,b) | `\|\|`: NULL 传播 | CONCAT 只接受 2 个参数 |
| Snowflake | **支持** | 不支持 | CONCAT() | `\|\|`: NULL 传播; CONCAT: 跳过 NULL | CONCAT 可变参数 |
| BigQuery | **支持** | 不支持 | CONCAT() | 均 NULL 传播 | - |
| ClickHouse | **支持** | 不支持 | concat() | concat: **NULL 传播** | `\|\|` 是 concat 别名；`concatAssumeNotNull()` 跳过 NULL |
| Trino | **支持** | 不支持 | CONCAT() | 均 NULL 传播 | CONCAT 可变参数 |
| Spark SQL | **支持** | 不支持 | CONCAT() | `\|\|` 和 CONCAT: **均 NULL 传播** | `concat_ws()` 才跳过 NULL |
| Hive | **支持 (2.2.0+)** | 不支持 | CONCAT() | `\|\|` 和 CONCAT: NULL 传播 | `\|\|` 是 CONCAT 简写 (2.2.0+) |
| Flink SQL | **支持** | 不支持 | CONCAT() | `\|\|`: NULL 传播; CONCAT: **NULL 传播** | CONCAT_WS 才跳过 NULL |
| DuckDB | **支持** | 不支持 | CONCAT() | `\|\|`: NULL 传播; CONCAT: 跳过 NULL | 与 PostgreSQL 兼容 |
| TiDB | 不支持 | 不支持 | **CONCAT()** | CONCAT: NULL 传播 | MySQL 兼容 |
| StarRocks | **不支持** | 不支持 | CONCAT() | CONCAT: NULL 传播 | `\|\|` 是逻辑 OR（MySQL 兼容） |
| Doris | **不支持** | 不支持 | CONCAT() | CONCAT: NULL 传播 | `\|\|` 是逻辑 OR（MySQL 兼容） |

**关键发现**:
- MySQL/MariaDB/TiDB/StarRocks/Doris 中 `||` 默认是逻辑 OR，**不是**字符串拼接，这是最常见的迁移陷阱
- SQL Server 是唯一使用 `+` 做拼接的方言
- `CONCAT()` 的 NULL 处理分三派：**跳过 NULL**: PostgreSQL/SQL Server/Snowflake/DuckDB/SQLite(3.44+)；**不传播（视为空字符串）**: Oracle（`||` 和 CONCAT 均不传播）；**传播 NULL**: MySQL/MariaDB/DB2/BigQuery/ClickHouse/Trino/Spark/Flink/Hive/TiDB/StarRocks/Doris

### NULL 处理对比

```sql
-- NULL 传播 (大多数方言的 || 行为):
SELECT 'Hello' || NULL || ' World';      -- 结果: NULL

-- PostgreSQL CONCAT: 跳过 NULL
SELECT CONCAT('Hello', NULL, ' World');  -- 结果: 'Hello World'

-- MySQL: 必须用 CONCAT
SELECT CONCAT('Hello', ' ', 'World');    -- 结果: 'Hello World'
SELECT CONCAT('Hello', NULL, ' World');  -- 结果: NULL (MySQL CONCAT 传播 NULL!)

-- MySQL: 如果要跳过 NULL，用 CONCAT_WS
SELECT CONCAT_WS('', 'Hello', NULL, ' World'); -- 结果: 'Hello World'

-- SQL Server: CONCAT 跳过 NULL (2012+)
SELECT CONCAT('Hello', NULL, ' World');  -- 结果: 'Hello World'
SELECT 'Hello' + NULL + ' World';        -- 结果: NULL

-- Oracle 特殊: || 和 CONCAT 都不传播 NULL (视 NULL 为空字符串)
SELECT 'Hello' || NULL || ' World' FROM DUAL;  -- 结果: 'Hello World' (非 NULL!)
SELECT CONCAT('Hello', NULL) FROM DUAL;         -- 结果: 'Hello'

-- Spark SQL: concat() 传播 NULL, concat_ws() 跳过 NULL
SELECT concat('Hello', NULL, ' World');          -- 结果: NULL
SELECT concat_ws('', 'Hello', NULL, ' World');   -- 结果: 'Hello World'
```

## 正则表达式支持

### 支持矩阵

| 方言 | 匹配语法 | REGEXP_REPLACE | REGEXP_SUBSTR | 正则风格 | 说明 |
|------|------|:---:|:---:|------|------|
| MySQL | `REGEXP` / `RLIKE` | 8.0+ | 8.0+ | ICU (8.0+) | 5.7 只支持匹配，不支持提取/替换 |
| MariaDB | `REGEXP` / `RLIKE` | 10.0.5+ | 10.0.5+ | PCRE2 | 比 MySQL 早支持 REGEXP_REPLACE |
| PostgreSQL | `~` `~*` `!~` `!~*` | 支持 | `substring()` | POSIX (ARE) | `~*` = 不敏感匹配 |
| Oracle | `REGEXP_LIKE()` | 支持 | 支持 | POSIX (ERE) | 10g+ 引入 |
| SQL Server | **不支持** | **不支持** | **不支持** | N/A | 只有 `PATINDEX` + `LIKE [a-z]`，无真正正则 |
| SQLite | 不内置 | 不内置 | 不内置 | 需扩展 | 可通过 `REGEXP` 扩展加载 |
| DB2 | `REGEXP_LIKE()` | 支持 | 支持 | ICU | 11.1+ |
| Snowflake | `REGEXP` / `RLIKE` | REGEXP_REPLACE | REGEXP_SUBSTR | POSIX (ERE) | 支持 POSIX 字符类 |
| BigQuery | `REGEXP_CONTAINS()` | 支持 | REGEXP_EXTRACT | **RE2** | 不支持 backreference |
| ClickHouse | `match()` / `REGEXP` | replaceRegexpAll | extractAll | **RE2** | 高性能向量化 |
| Trino | `REGEXP_LIKE()` | 支持 | REGEXP_EXTRACT | **Java** (java.util.regex) | - |
| Spark SQL | `REGEXP` / `RLIKE` | REGEXP_REPLACE | REGEXP_EXTRACT | **Java** (java.util.regex) | - |
| Hive | `REGEXP` / `RLIKE` | REGEXP_REPLACE | REGEXP_EXTRACT | **Java** (java.util.regex) | - |
| Flink SQL | `REGEXP` / `RLIKE` | REGEXP_REPLACE | REGEXP_EXTRACT | **Java** (java.util.regex) | - |
| DuckDB | `REGEXP_MATCHES()` / `~` | REGEXP_REPLACE | REGEXP_EXTRACT | **RE2** | 也支持 POSIX `~` 运算符 |
| StarRocks | `REGEXP` / `RLIKE` | REGEXP_REPLACE | REGEXP_EXTRACT | **RE2** | - |
| Doris | `REGEXP` / `RLIKE` | REGEXP_REPLACE | REGEXP_EXTRACT | **RE2** | - |

### 正则风格对比

```
RE2 (BigQuery, ClickHouse, StarRocks, Doris, DuckDB):
  - 保证线性时间复杂度，不会 ReDoS
  - 不支持 backreference (\1)、lookahead (?=)、lookbehind (?<=)
  - 适合大规模数据处理

Java / java.util.regex (Hive, Spark, Trino, Flink):
  - 支持 backreference、lookahead、lookbehind
  - 可能存在 ReDoS 风险（指数级回溯）
  - 功能最丰富

POSIX / ERE (PostgreSQL, Oracle, Snowflake):
  - 支持 POSIX 字符类 [[:alpha:]]、[[:digit:]]
  - PostgreSQL 使用 Advanced Regular Expressions (ARE)，支持 lookahead
  - Oracle 使用 Extended Regular Expressions (ERE)

ICU (MySQL 8.0+, DB2):
  - Unicode-aware
  - 功能介于 POSIX 和 Java 之间
```

### SQL Server 的替代方案

```sql
-- SQL Server 没有正则支持，常用替代:

-- PATINDEX: 有限的模式匹配
SELECT PATINDEX('%[0-9][0-9][0-9]%', '订单号ABC123DEF'); -- 找三连数字

-- LIKE 的字符类:
SELECT * FROM t WHERE col LIKE '%[A-Z]%';   -- 包含大写字母
SELECT * FROM t WHERE col LIKE '%[^0-9]%';  -- 包含非数字字符

-- CLR 集成 (终极方案):
-- 通过 .NET CLR 注册自定义正则函数，但需要 sysadmin 权限
```

## Collation 支持

排序规则（Collation）决定字符串的比较、排序和大小写转换行为。

### 支持矩阵

| 方言 | 列级 COLLATE | 表达式级 COLLATE | Unicode 支持 | Collation 体系 | 说明 |
|------|:---:|:---:|------|------|------|
| MySQL | 支持 | 支持 | utf8mb4 完整 Unicode | 完整 | 200+ 排序规则可选 |
| MariaDB | 支持 | 支持 | utf8mb4 完整 Unicode | 完整 | 与 MySQL 兼容 |
| PostgreSQL | 支持 | 支持 | ICU (15+) | 完整 | 12+ 支持 ICU collation provider |
| Oracle | 支持 | 支持 | 完整 Unicode | 完整 | NLS_SORT / NLS_COMP 系统 |
| SQL Server | 支持 | 支持 | 完整 Unicode | 完整 | 数据库/列/表达式三级 |
| SQLite | 支持 | 支持 | 有限 | 基础 | 内置 BINARY / NOCASE / RTRIM |
| DB2 | 支持 | 支持 | 完整 Unicode | 完整 | 依赖数据库创建时的设置 |
| Snowflake | 支持 | 支持 | 完整 Unicode | 完整 | 支持丰富的 locale-aware collation |
| Trino | 不支持 | 有限 | 无 | **无** | - |
| DuckDB | 支持 | 支持 | ICU 扩展 | 基础 | 需要加载 ICU 扩展 |
| TiDB | 支持 | 支持 | utf8mb4 完整 Unicode | 完整 | 与 MySQL 兼容 |
| BigQuery | 不支持 | 不支持 | N/A | **无** | 使用函数处理大小写 |
| ClickHouse | 不支持 | 不支持 | N/A | **无** | 使用 `*CaseInsensitive` 函数 |
| Hive | 不支持 | 不支持 | N/A | **无** | - |
| Spark SQL | 不支持 | 有限 (3.4+) | 3.4+ 引入 | **基本无** | 3.4 开始实验性支持 |
| Flink SQL | 不支持 | 不支持 | N/A | **无** | - |
| StarRocks | 不支持 | 不支持 | N/A | **无** | - |
| Doris | 不支持 | 不支持 | N/A | **无** | - |
| MaxCompute | 不支持 | 不支持 | N/A | **无** | - |

**关键发现**: 分析型引擎（BigQuery、ClickHouse、Hive、Spark、Flink、StarRocks、Doris、MaxCompute）普遍没有排序规则系统。这些引擎优先考虑计算吞吐而非字符串语义精度，字符串比较统一为二进制比较。

### Collation 使用示例

```sql
-- MySQL: 列级定义
CREATE TABLE users (
    name VARCHAR(100) COLLATE utf8mb4_unicode_ci, -- 大小写不敏感
    code VARCHAR(50)  COLLATE utf8mb4_bin          -- 大小写敏感 (二进制)
);

-- MySQL: 查询时临时指定
SELECT * FROM users WHERE name = 'John' COLLATE utf8mb4_bin;

-- PostgreSQL: 创建自定义 collation (12+)
CREATE COLLATION chinese_pinyin (
    provider = icu,
    locale = 'zh-u-co-pinyin'
);
CREATE TABLE contacts (
    name TEXT COLLATE "chinese_pinyin"
);

-- SQL Server: 三级 collation 层次
-- 1. 服务器级别 (安装时设定)
-- 2. 数据库级别
ALTER DATABASE mydb COLLATE Latin1_General_100_CI_AI;
-- 3. 列级 / 表达式级
SELECT * FROM t WHERE col COLLATE Latin1_General_BIN2 = 'abc';

-- Oracle: 12c+ COLLATE 表达式
SELECT * FROM t WHERE name = 'John' COLLATE BINARY_CI;

-- Snowflake: 表达式级
SELECT * FROM t WHERE COLLATE(name, 'en-ci') = 'john';
```

## 横向总结

### 迁移风险矩阵

| 维度 | MySQL -> PostgreSQL | MySQL -> BigQuery | SQL Server -> PostgreSQL | Oracle -> PostgreSQL |
|------|------|------|------|------|
| 大小写 | 高风险: CI -> CS | 高风险: CI -> CS | 高风险: CI -> CS | 低风险: 都是 CS |
| 尾部空格 | 高风险: PAD -> NO PAD | 高风险: PAD -> NO PAD | 高风险: PAD -> NO PAD | 中风险: VARCHAR 一致 |
| 拼接 | 中风险: CONCAT -> `\|\|` | 低风险: 都支持 CONCAT | 高风险: `+` -> `\|\|` | 低风险: 都支持 `\|\|` |
| 正则 | 低风险: 语法不同但能力相近 | 中风险: RE2 不支持 backreference | 高风险: 无 -> 有 | 低风险: 都是 POSIX 系 |
| Collation | 高风险: 体系完全不同 | 高风险: 无 Collation | 中风险: 体系不同 | 中风险: NLS -> ICU |

### 方言特性速查

```
特性覆盖度排名 (字符串处理能力):
1. PostgreSQL   - 全面: ILIKE、POSIX 正则、ICU collation、标准 || 拼接
2. Oracle       - 全面: REGEXP_LIKE、NLS collation、标准 || 拼接
3. MySQL 8.0+   - 较全: REGEXP 增强、200+ collation，但 || 不是拼接
4. SQL Server   - 偏科: 强 collation 系统，但无正则、无 || 拼接
5. Snowflake    - 良好: ILIKE、REGEXP、Collation 均支持
6. DuckDB       - 良好: 兼容 PostgreSQL，ILIKE + RE2 正则
7. BigQuery     - 基础: RE2 正则好用，但无 Collation、无 ILIKE
8. ClickHouse   - 基础: RE2 正则 + ILIKE，但无 Collation
9. Spark/Hive   - 基础: Java 正则，无 Collation (Spark 3.4 开始改善)
10. SQLite      - 最少: 有限 LIKE，正则需扩展，3 种内置 collation
```

### 安全迁移检查清单

```
从 MySQL/SQL Server 迁移到大小写敏感方言时:
[ ] 审计所有 WHERE col = 'value'，确认是否依赖大小写不敏感匹配
[ ] 审计所有 JOIN ON a.col = b.col，确认是否有大小写不一致的关联数据
[ ] 审计所有 UNIQUE 约束，大小写敏感后 'ABC' 和 'abc' 是两条不同记录
[ ] 审计所有 GROUP BY，大小写敏感后分组数可能增加
[ ] 检查尾部空格: SELECT COUNT(*) FROM t WHERE col != RTRIM(col)
[ ] 统一拼接方式: Oracle 迁出时用 CONCAT() 而非 ||（避免 NULL 行为变化）; Spark/SQLite 中 concat() 和 || 的 NULL 行为不同
[ ] 替换 + 拼接 (SQL Server) 为 || 或 CONCAT()
[ ] 将 REGEXP/RLIKE 转换为目标方言的正则语法
[ ] 重新评估 Collation 设置，确保排序行为一致
```
