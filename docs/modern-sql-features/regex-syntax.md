# 正则表达式

SQL 中的正则表达式——从 LIKE 的通配符到 POSIX、PCRE、RE2 四大流派，横跨 45+ 方言的语法、函数与实现差异全景。

## LIKE 不是正则表达式

| 特性 | LIKE | 正则表达式 |
|------|------|-----------|
| 标准来源 | SQL-86 (SQL1) | 各引擎自行扩展 / SQL:2008 引入 `LIKE_REGEX` |
| 通配符 | `%`（任意字符串）、`_`（单个字符） | `.`、`*`、`+`、`?`、`[]`、`()` 等 |
| 锚定行为 | **隐式全匹配**（等同于 `^...$`） | 多数引擎做**子串匹配** |
| 表达能力 | 极其有限，无量词、无分组 | 带反向引用的 PCRE 实现在理论上图灵等价，但 RE2 等线性时间引擎有意限制了表达能力 |
| 索引利用 | 前缀 LIKE `'abc%'` 可利用 B-tree | 极少数情况可利用索引 |
| 可移植性 | **所有引擎一致** | 语法和语义差异极大 |

```sql
-- LIKE：所有引擎完全一致
SELECT * FROM users WHERE name LIKE 'A%';
-- 正则：同一需求，语法五花八门
SELECT * FROM users WHERE name REGEXP '^A';       -- MySQL / MariaDB / TiDB
SELECT * FROM users WHERE name ~ '^A';            -- PostgreSQL / Greenplum
SELECT * FROM users WHERE REGEXP_LIKE(name, '^A'); -- Oracle / DB2
```

## 四大正则家族总览

| 家族 | 代表语法 | 来源 | 语义 |
|------|---------|------|------|
| **REGEXP / RLIKE** | `col REGEXP pattern` | MySQL 原创，广泛借鉴 | 子串匹配 |
| **SIMILAR TO** | `col SIMILAR TO pattern` | SQL:1999 标准 | 全匹配（类 LIKE + 正则） |
| **POSIX 运算符** | `col ~ pattern` | PostgreSQL 原创 | 子串匹配 |
| **REGEXP_LIKE()** | `REGEXP_LIKE(col, pattern)` | Oracle 10g 原创，SQL:2008 标准化 | 子串匹配 |

## 支持矩阵：匹配运算符

| 引擎 | REGEXP/RLIKE | SIMILAR TO | POSIX (~) | REGEXP_LIKE() | 正则引擎 |
|------|:-:|:-:|:-:|:-:|------|
| MySQL 8.0+ | ✓ | ✗ | ✗ | ✓ | ICU |
| MySQL 5.x | ✓ | ✗ | ✗ | ✗ | Henry Spencer |
| MariaDB | ✓ | ✗ | ✗ | ✓ (10.0.5+) | PCRE / PCRE2 (10.5+) |
| PostgreSQL | ✗ | ✓ | ✓ | ✗ | POSIX ARE |
| Oracle | ✓ (23c+) | ✗ | ✗ | ✓ (10g+) | POSIX ERE + Perl 扩展 |
| SQL Server | ✗ | ✗ | ✗ | ✗ | **无原生支持** |
| SQLite | ✓ (需扩展) | ✗ | ✗ | ✗ | 用户自定义 |
| DB2 | ✗ | ✓ | ✗ | ✓ (9.7+) | ICU (XQuery) |
| Snowflake | ✓ | ✗ | ✗ | ✓ | POSIX ERE (内部 PCRE2 实现) |
| BigQuery | ✓ | ✗ | ✗ | ✓ | RE2 |
| DuckDB | ✓ | ✓ | ✓ | ✓ | RE2 |
| Spark SQL | ✓ | ✗ | ✗ | ✗ | Java regex |
| Hive | ✓ | ✗ | ✗ | ✗ | Java regex |
| Trino | ✓ | ✗ | ✗ | ✓ | Java regex (RE2J 可选) |
| Presto | ✓ | ✗ | ✗ | ✓ | Java regex |
| ClickHouse | ✓ (`match`) | ✗ | ✗ | ✗ | RE2 / Hyperscan |
| TiDB | ✓ | ✗ | ✗ | ✓ (6.x+) | Go regexp (RE2) |
| OceanBase (MySQL) | ✓ | ✗ | ✗ | ✓ | 兼容 MySQL |
| OceanBase (Oracle) | ✗ | ✗ | ✗ | ✓ | 兼容 Oracle |
| CockroachDB | ✗ | ✓ | ✓ | ✗ | RE2 (Go) |
| YugabyteDB | ✗ | ✓ | ✓ | ✗ | POSIX ARE |
| Redshift | ✓ | ✓ | ✓ | ✓ | POSIX ERE |
| Greenplum | ✗ | ✓ | ✓ | ✗ | POSIX ARE |
| SingleStore | ✓ | ✗ | ✗ | ✓ | PCRE2 |
| Databricks | ✓ | ✗ | ✗ | ✗ | Java regex |
| Doris | ✓ | ✗ | ✗ | ✓ | RE2 |
| StarRocks | ✓ | ✗ | ✗ | ✓ | RE2 |
| Vertica | ✗ | ✗ | ✗ | ✓ | PCRE |
| Teradata | ✗ | ✗ | ✗ | ✓ (14+) | ICU |
| SAP HANA | ✗ | ✗ | ✗ | ✓ | POSIX ERE |
| Informix | ✗ | ✗ | ✗ | ✓ (14.10+) | POSIX ERE |
| MonetDB | ✓ | ✓ | ✗ | ✗ | PCRE |
| H2 | ✓ | ✗ | ✗ | ✓ | Java regex |
| HSQLDB | ✗ | ✓ | ✗ | ✗ | Java regex |
| Derby | ✗ | ✗ | ✗ | ✗ | 无原生支持 |
| Firebird | ✗ | ✓ | ✗ | ✗ | SQL 标准语义 |
| Exasol | ✓ | ✗ | ✗ | ✓ | PCRE |
| TimescaleDB | ✗ | ✓ | ✓ | ✗ | POSIX ARE |
| QuestDB | ✓ | ✗ | ✗ | ✗ | Java regex |
| CrateDB | ✓ | ✗ | ✓ | ✗ | Java / Lucene |
| Materialize | ✗ | ✓ | ✓ | ✗ | RE2 (Rust) |
| RisingWave | ✗ | ✓ | ✓ | ✗ | Rust regex |
| Flink SQL | ✓ | ✓ | ✗ | ✗ | Java regex |
| Calcite | ✓ | ✓ | ✗ | ✗ | Java regex |
| PolarDB (MySQL) | ✓ | ✗ | ✗ | ✓ | 兼容 MySQL 8.0 |
| PolarDB (PG) | ✗ | ✓ | ✓ | ✗ | 兼容 PostgreSQL |
| GaussDB | ✗ | ✓ | ✓ | ✓ | 兼容 PG / Oracle |
| Yellowbrick | ✗ | ✓ | ✓ | ✗ | POSIX ERE |

## REGEXP / RLIKE 语法

```sql
-- MySQL / MariaDB / TiDB
SELECT * FROM t WHERE col REGEXP 'pattern';
SELECT * FROM t WHERE col RLIKE 'pattern';     -- 同义词
SELECT * FROM t WHERE col NOT REGEXP 'pattern'; -- 取反

-- Spark SQL / Hive / Databricks
SELECT * FROM t WHERE col RLIKE 'pattern';

-- ClickHouse（函数形式）
SELECT * FROM t WHERE match(col, 'pattern');

-- BigQuery（函数形式，名称不同）
SELECT * FROM t WHERE REGEXP_CONTAINS(col, r'pattern');
```

### 子串匹配 vs 全匹配

| 引擎 | 默认语义 | `'abc' REGEXP 'b'` |
|------|---------|---------------------|
| MySQL / MariaDB / TiDB | **子串匹配** | TRUE |
| PostgreSQL (~) | **子串匹配** | TRUE |
| Oracle (REGEXP_LIKE) | **子串匹配** | TRUE |
| Snowflake (RLIKE) | **全匹配** | FALSE |
| Spark SQL (RLIKE) | **全匹配** (3.4+)，子串 (3.3-) | 版本相关 |
| BigQuery (REGEXP_CONTAINS) | **子串匹配** | TRUE |
| ClickHouse (match) | **子串匹配** | TRUE |

> **注意**：Spark SQL 3.4 将 RLIKE 从子串匹配改为全匹配，是**破坏性变更**。

## SIMILAR TO

SQL:1999 标准的 SIMILAR TO 是 LIKE 与正则的混合体——全匹配语义、支持正则量词、保留 `%` `_` 通配符：

```sql
-- PostgreSQL / DuckDB / CockroachDB / DB2
SELECT * FROM t WHERE col SIMILAR TO '(A|B)[0-9]+';
SELECT * FROM t WHERE col SIMILAR TO '%[0-9]{3}%';  -- 包含三个连续数字
```

SIMILAR TO 被广泛认为是标准中的失败设计：表达能力不如真正的正则（无反向引用、无环视），却比 LIKE 复杂。MySQL、Oracle、SQL Server 均未实现。**新引擎建议跳过 SIMILAR TO，直接实现 REGEXP_LIKE 函数族**。

## POSIX 运算符 (~)

PostgreSQL 独创，被所有 PG 兼容引擎继承：

```sql
col ~   pattern   -- 区分大小写匹配
col ~*  pattern   -- 不区分大小写匹配
col !~  pattern   -- 区分大小写不匹配
col !~* pattern   -- 不区分大小写不匹配
```

支持引擎：PostgreSQL、CockroachDB、YugabyteDB、Greenplum、Redshift、TimescaleDB、DuckDB、Materialize、RisingWave、CrateDB、PolarDB (PG)、GaussDB、Yellowbrick。

```sql
SELECT * FROM users WHERE email ~ '^[a-z]+@example\.com$';
SELECT * FROM users WHERE name ~* 'mcdonald|macdonald';  -- 不区分大小写
```

## REGEXP_LIKE() 函数

Oracle 10g 引入、SQL:2008 标准化，**可移植性最好**的正则匹配方式：

```sql
REGEXP_LIKE(col, 'pat', 'i')           -- Oracle / MySQL 8.0+ / DB2 / Snowflake / Redshift
REGEXP_CONTAINS(col, r'(?i)pat')       -- BigQuery（函数名不同！）
REGEXP_LIKE(col, '(?i)pat')            -- Trino（不支持 flags 参数，需嵌入标志）
col LIKE_REGEXPR 'pat' FLAG 'i'        -- SAP HANA（独特语法）
```

## 正则函数族

### 支持矩阵

| 引擎 | REGEXP_SUBSTR | REGEXP_REPLACE | REGEXP_INSTR | REGEXP_COUNT |
|------|:-:|:-:|:-:|:-:|
| Oracle | ✓ (10g+) | ✓ (10g+) | ✓ (10g+) | ✓ (11g+) |
| MySQL 8.0+ | ✓ | ✓ | ✓ | ✗ |
| MariaDB 10.0.5+ | ✓ | ✓ | ✓ | ✗ |
| PostgreSQL | ✓ (`substring`; `regexp_substr` 15+) | ✓ | ✗ | ✓ (`regexp_count` 15+) |
| DB2 9.7+ | ✓ | ✓ | ✓ | ✓ (11.1+) |
| Snowflake | ✓ | ✓ | ✓ | ✓ |
| BigQuery | ✓ (`REGEXP_EXTRACT`) | ✓ | ✗ | ✗ |
| DuckDB | ✓ (`regexp_extract`) | ✓ | ✗ | ✗ |
| Spark SQL | ✓ (`regexp_extract`) | ✓ | ✗ | ✗ |
| Trino | ✓ (`regexp_extract`) | ✓ | ✗ | ✓ |
| ClickHouse | ✓ (`extract`) | ✓ (`replaceRegexpOne/All`) | ✗ | ✓ (`countMatches`) |
| Redshift | ✓ | ✓ | ✓ | ✓ |
| TiDB 6.x+ | ✓ | ✓ | ✓ | ✗ |
| Vertica | ✓ | ✓ | ✓ | ✓ |
| Teradata | ✓ | ✓ | ✓ | ✗ |
| SAP HANA | ✓ (`SUBSTR_REGEXPR`) | ✓ (`REPLACE_REGEXPR`) | ✓ (`LOCATE_REGEXPR`) | ✓ (`OCCURRENCES_REGEXPR`) |
| Exasol | ✓ | ✓ | ✓ | ✗ |
| SingleStore | ✓ | ✓ | ✓ | ✗ |
| Doris / StarRocks | ✓ | ✓ | ✗ | ✓ |
| SQL Server | ✗ | ✗ | ✗ | ✗ |

### REGEXP_SUBSTR

```sql
-- Oracle（最完整签名）
REGEXP_SUBSTR(source, pattern, position, occurrence, flags, group)
SELECT REGEXP_SUBSTR('hello 123 world 456', '\d+', 1, 2) FROM dual;  -- '456'

-- PostgreSQL
SELECT substring('hello 123' FROM '\d+');                 -- '123'
SELECT (regexp_match('2024-01-15', '(\d{4})'))[1];        -- '2024'

-- BigQuery（名称不同）
SELECT REGEXP_EXTRACT('hello 123', r'\d+');               -- '123'
SELECT REGEXP_EXTRACT_ALL('hello 123 world 456', r'\d+'); -- ['123','456']

-- Spark SQL
SELECT regexp_extract('hello 123', '(\\d+)', 1);         -- '123'

-- ClickHouse
SELECT extractAll('hello 123 world 456', '\\d+');         -- ['123','456']
```

### REGEXP_REPLACE

```sql
-- Oracle / MySQL 8.0+ / Snowflake / BigQuery / Spark SQL
SELECT REGEXP_REPLACE('a1b2c3', '[0-9]', 'X');  -- 'aXbXcX'

-- PostgreSQL：默认只替换第一个！需 'g' 标志
SELECT regexp_replace('a1b2c3', '\d', 'X');        -- 'aXb2c3'
SELECT regexp_replace('a1b2c3', '\d', 'X', 'g');   -- 'aXbXcX'

-- ClickHouse：显式区分单次/全部
SELECT replaceRegexpOne('a1b2c3', '\\d', 'X');  -- 'aXb2c3'
SELECT replaceRegexpAll('a1b2c3', '\\d', 'X');  -- 'aXbXcX'
```

> **默认替换行为差异**：PostgreSQL 默认**只替换第一个**，Oracle / MySQL / Snowflake / BigQuery / Spark 默认**全部替换**。这是迁移中最常见的 bug 来源。

### REGEXP_INSTR / REGEXP_COUNT

```sql
-- REGEXP_INSTR：返回匹配位置（1-based）
SELECT REGEXP_INSTR('hello 123', '\d+') FROM dual;  -- 7 (Oracle / MySQL / Snowflake)

-- REGEXP_COUNT：统计匹配次数
SELECT REGEXP_COUNT('aaa bbb aaa', 'aaa') FROM dual;  -- 2 (Oracle / Snowflake / PG 15+)
-- ClickHouse: countMatches()    SAP HANA: OCCURRENCES_REGEXPR()
```

## 正则引擎风格对比

| 风格 | 回溯 | 时间保证 | 反向引用 | 环视 | Unicode `\p{L}` | 代表引擎 |
|------|:---:|:---:|:---:|:---:|:---:|------|
| **PCRE2** | ✓ | ✗ | ✓ | ✓ | ✓ | MariaDB, Snowflake, Exasol, Vertica |
| **POSIX ERE/ARE** | ✓ | ✗ | ✗/有限 | ✗ | ✗ | PostgreSQL, Oracle, Redshift |
| **RE2** | ✗ | **O(mn)** | **✗** | **✗** | ✓ | BigQuery, ClickHouse, DuckDB, CockroachDB |
| **Java regex** | ✓ | ✗ | ✓ | ✓ (定长后瞻) | ✓ | Spark, Hive, Trino, Flink |
| **ICU** | ✓ | ✗ | ✓ | ✓ | ✓ | MySQL 8.0+, DB2, Teradata |

RE2 不支持反向引用——因为反向引用使匹配成为 NP 完全问题。对多租户云数据库，这是安全选择。

### 反向引用在替换中的引用语法

| 语法 | 引擎 |
|------|------|
| `\1`, `\2` | Oracle, PostgreSQL, ClickHouse, Snowflake |
| `$1`, `$2` | MySQL (8.0.17+), Spark SQL, Trino, Presto |

```sql
-- 交换名和姓
SELECT REGEXP_REPLACE('John Smith', '(\w+) (\w+)', '\2, \1');  -- Oracle/PG
SELECT REGEXP_REPLACE('John Smith', '(\\w+) (\\w+)', '$2, $1'); -- Spark/Trino
```

## 大小写敏感性

| 引擎 | 默认 | 切换方式 |
|------|:---:|------|
| MySQL 8.0+ | 取决于 collation | `REGEXP_LIKE(col, 'pat', 'c'/'i')` |
| MariaDB | 不敏感 (非 binary) | `BINARY col REGEXP` 或 collation |
| PostgreSQL | **敏感** | `~*` 运算符或 `(?i)` 嵌入 |
| Oracle | **敏感** | flags 参数 `'i'` |
| Snowflake | **敏感** | flags 参数 `'i'` 或 `(?i)` |
| BigQuery | **敏感** | `(?i)` 嵌入 |
| Spark SQL | **敏感** | `(?i)` 嵌入 |
| ClickHouse | **敏感** | `match(col, '(?i)pattern')`（部分版本亦有 `matchi()`） |
| Trino | **敏感** | `(?i)` 嵌入 |
| DuckDB | **敏感** | `(?i)` 嵌入 |

## 正则标志 / 修饰符

| 标志 | 含义 | Oracle | MySQL | PostgreSQL | Snowflake | BigQuery |
|------|------|:---:|:---:|:---:|:---:|:---:|
| `i` | 不区分大小写 | ✓ | ✓ | ✓ | ✓ | ✓ (嵌入) |
| `c` | 区分大小写 | ✓ | ✓ | ✗ | ✓ | ✗ |
| `m` | 多行 (`^$` 匹配行首尾) | ✓ | ✓ | ✓ (`n`) | ✓ | ✓ (嵌入) |
| `n`/`s` | dotall (`.` 匹配换行) | ✓ (`n`) | ✗ | ✓ | ✓ (`s`) | ✓ (`(?s)`) |
| `x` | 扩展模式 (忽略空格和注释) | ✓ | ✗ | ✓ | ✓ | ✓ (嵌入) |
| `g` | 全局 (regexp_replace) | ✗ | ✗ | ✓ | ✗ | ✗ |

> **警告**：Oracle 用 `n` 表示 dotall，PCRE/Java/RE2 用 `s`。PostgreSQL 的 `n` 等于其他引擎的 `m`（多行）。标志字母含义在引擎间不一致。

## 捕获组

```sql
-- Oracle：REGEXP_SUBSTR 的 group 参数
SELECT REGEXP_SUBSTR('2024-01-15', '(\d{4})-(\d{2})-(\d{2})', 1, 1, NULL, 2) FROM dual;
-- 结果: '01'

-- PostgreSQL：regexp_match 返回数组
SELECT (regexp_match('2024-01-15', '(\d{4})-(\d{2})-(\d{2})'))[2];  -- '01'

-- BigQuery（不支持 group 参数，需调整正则使目标成为唯一捕获组）
SELECT REGEXP_EXTRACT('2024-01-15', r'\d{4}-(\d{2})-\d{2}');  -- '01'

-- Spark SQL
SELECT regexp_extract('2024-01-15', '(\\d{4})-(\\d{2})-(\\d{2})', 2);  -- '01'

-- DuckDB：命名捕获组
SELECT regexp_extract('2024-01-15', '(?P<year>\d{4})-(?P<month>\d{2})', ['year','month']);
-- {'year':'2024','month':'01'}

-- Snowflake：'e' 标志启用捕获组提取
SELECT REGEXP_SUBSTR('2024-01-15', '(\\d{4})-(\\d{2})', 1, 1, 'e', 2);  -- '01'

-- ClickHouse
SELECT extractGroups('2024-01-15', '(\\d{4})-(\\d{2})-(\\d{2})');  -- ['2024','01','15']
```

## Unicode 支持

| 引擎 | `\p{L}` | `\p{Lu}` | `\p{Han}` | 备注 |
|------|:---:|:---:|:---:|------|
| MySQL 8.0+ (ICU) | ✓ | ✓ | ✓ | 最完整 |
| MariaDB (PCRE2) | ✓ | ✓ | ✓ | 含图形族簇 `\X` |
| BigQuery / ClickHouse / DuckDB (RE2) | ✓ | ✓ | ✓ | |
| Spark / Trino (Java) | ✓ | ✓ | ✓ | Java 需 `\p{IsHan}` 前缀 |
| DB2 / Teradata (ICU) | ✓ | ✓ | ✓ | |
| Snowflake (PCRE) | ✓ | ✓ | ✓ | |
| PostgreSQL (POSIX ARE) | ✗ | ✗ | ✗ | 有限支持 |
| Oracle (POSIX ERE) | ✗ | ✗ | ✗ | 需用字符范围变通 |

```sql
SELECT * FROM t WHERE REGEXP_LIKE(col, '\\p{Han}');             -- MySQL 8.0+
SELECT * FROM t WHERE REGEXP_CONTAINS(col, r'\p{Han}');         -- BigQuery
SELECT * FROM t WHERE col RLIKE '\\p{IsHan}';                   -- Spark SQL
SELECT * FROM t WHERE REGEXP_LIKE(col, '[\u4e00-\u9fff]');      -- Oracle (变通)
```

## 性能：正则 vs LIKE

| 场景 | LIKE | REGEXP | 差距 |
|------|------|--------|-----|
| 前缀匹配 `'abc%'` vs `'^abc'` | 索引 O(log n) | 全表扫描 O(n) | 100-10000x |
| 后缀/中间匹配 | 全表扫描 | 全表扫描 | 1-3x (LIKE 略快) |

**索引例外**：PostgreSQL 的 `pg_trgm` GIN 索引可加速正则查询。

### 正则引擎性能与 ReDoS

| 引擎 | 最坏复杂度 | ReDoS 风险 | 适合多租户 |
|------|----------|:---:|:---:|
| RE2 | **O(mn)** 线性 | ✗ | ✓ |
| PCRE / Java / ICU | **O(2^n)** 指数 | ✓ | ✗ |

```sql
-- 各引擎的 ReDoS 防护
SET GLOBAL pcre_backtrack_limit = 1000000;  -- MariaDB (PCRE2)
SET GLOBAL regexp_time_limit = 32;          -- MySQL 8.0+ (ICU)
-- BigQuery / ClickHouse (RE2)：天然免疫
```

## REGEXP 在 CHECK 约束中

```sql
-- PostgreSQL
CREATE TABLE users (
    email TEXT CHECK (email ~ '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
);
-- MySQL 8.0.16+
CREATE TABLE users (
    email VARCHAR(255) CHECK (REGEXP_LIKE(email, '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$'))
);
-- Oracle
CREATE TABLE users (
    email VARCHAR2(255) CHECK (REGEXP_LIKE(email, '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'))
);
```

| 引擎 | CHECK 中可用正则 | 强制执行 |
|------|:---:|:---:|
| PostgreSQL / CockroachDB / DuckDB | ✓ | ✓ |
| MySQL 8.0.16+ / MariaDB 10.2.1+ | ✓ | ✓ |
| Oracle | ✓ | ✓ |
| Snowflake | ✓ | **✗** (仅声明) |
| TiDB | ✓ | ✗ (5.x-) / ✓ (7.x+) |
| SQL Server / DB2 | ✗ (无正则) | ✓ |

## 转义字符处理

| 引擎 | 匹配 `\d+` 需写 | 匹配字面 `\` 需写 |
|------|----------------|-----------------|
| Oracle / PostgreSQL / DuckDB | `'\d+'` | `'\\\\'` |
| MySQL / MariaDB / Snowflake / Spark | `'\\d+'` | `'\\\\\\\\'` |
| BigQuery | `r'\d+'` | `r'\\'` |

## SQL Server 变通方案

SQL Server 是主流引擎中唯一无原生正则的：

```sql
-- PATINDEX: 有限的 [] 字符类
SELECT * FROM t WHERE PATINDEX('%[0-9][0-9][0-9]%', col) > 0;
-- CLR 集成: 编写 C# 正则函数
-- Python 扩展 (2017+): sp_execute_external_script
```

## SQL 标准中的正则

- **SQL:1999**：引入 SIMILAR TO（全匹配 + 正则量词 + LIKE 通配符）
- **SQL:2008**：引入 `LIKE_REGEX`、`OCCURRENCES_REGEX`、`POSITION_REGEX`、`SUBSTRING_REGEX`、`TRANSLATE_REGEX`（基于 XQuery 正则语法）

实际上只有 DB2 和 SAP HANA 接近实现了 SQL:2008 正则标准。Oracle 的 REGEXP_LIKE 系列更早且被更广泛采纳。

## 对引擎开发者的实现建议

### 1. 正则引擎选型

| 场景 | 推荐 | 理由 |
|------|------|------|
| 多租户 SaaS / 云数据库 | **RE2** | 线性时间保证，免疫 ReDoS |
| 单租户 OLTP | **PCRE2** (带回溯限制) | 功能最完整 |
| JVM 生态 | **RE2J** | RE2 的 Java 实现 |
| Rust 生态 | **regex crate** | RE2 语义 |
| 完整 Unicode 支持 | **ICU** | 最完整的 Unicode 属性 |

### 2. API 设计

推荐实现的最小函数集（按优先级）：

1. `REGEXP` / `RLIKE` 运算符 — 匹配判断（必须）
2. `REGEXP_REPLACE` — 替换（必须）
3. `REGEXP_SUBSTR` / `REGEXP_EXTRACT` — 提取（必须）
4. `REGEXP_LIKE()` — 函数形式匹配（Oracle 兼容必须）
5. `REGEXP_COUNT` — 计数（高优先级）
6. `REGEXP_INSTR` — 定位（中优先级）

建议采用 Oracle 风格签名（参数最完整）：

```sql
REGEXP_SUBSTR(source, pattern [, position [, occurrence [, flags [, group]]]])
REGEXP_REPLACE(source, pattern, replacement [, position [, occurrence [, flags]]])
REGEXP_INSTR(source, pattern [, position [, occurrence [, return_opt [, flags]]]])
REGEXP_COUNT(source, pattern [, position [, flags]])
```

### 3. 语义决策

- **匹配语义**：建议默认**子串匹配**（符合 POSIX 标准和主流引擎行为）
- **大小写**：建议默认**敏感**（符合 Oracle/PG/BigQuery），通过 `'i'` 标志切换
- **替换行为**：建议默认**全部替换**（符合多数引擎），PostgreSQL 的"默认只替换第一个"是常见陷阱

### 4. 正则编译缓存

正则编译开销远大于匹配。必须缓存已编译的正则：

- 常量正则：查询规划阶段编译，执行计划节点中复用
- 参数化正则：LRU 缓存（建议 256-4096 条目），key = (pattern, flags)
- RE2 编译后对象线程安全，PCRE2 不是

### 5. 安全性清单

- 设置回溯步数上限（PCRE2: match_limit）
- 设置匹配超时（或直接用 RE2 免疫 ReDoS）
- 限制正则长度（建议 ≤ 32KB）和捕获组数量（建议 ≤ 99）
- CHECK 约束中的正则：编译期验证语法

### 6. NULL 处理与错误处理

所有正则函数在任一参数为 NULL 时应返回 NULL（符合 SQL NULL 传播语义）。

无效正则应在常量场景于规划阶段报错，非常量于执行阶段报错。错误消息应包含原始正则、出错位置和原因。

### 7. 与 collation 的交互

如果引擎有 collation 系统，正则的大小写行为应默认遵循列的 collation，但允许通过 `'i'`/`'c'` 标志覆盖——这是最不让用户惊讶的设计。

### 8. ReDoS 防御：RE2 优先原则

对于接受用户输入正则的场景（Web 应用搜索框、API 过滤参数、多租户 SaaS），正则引擎的选型直接决定了系统安全性：

```
PCRE / Java regex / ICU（回溯引擎）:
├── 支持反向引用、环视等高级特性
├── 最坏情况: O(2^n) 指数时间复杂度
├── 攻击模式: (a+)+$ 对输入 "aaaaaaaaaaaaaaaaX" 可触发灾难性回溯
├── 即使设置 backtrack_limit, 攻击者仍可消耗大量 CPU
└── 仅适合: 单租户、受信正则来源（DBA 编写的 CHECK 约束等）

RE2 / RE2J / Rust regex（非回溯引擎）:
├── 基于 NFA/DFA 自动机, 保证 O(mn) 线性时间
├── 代价: 不支持反向引用 (\1)、不支持环视 (?=...)
├── 实际影响: 95%+ 的业务正则不需要反向引用
├── BigQuery / ClickHouse / DuckDB / CockroachDB / TiDB 均选择 RE2
└── 推荐: 所有面向用户输入的正则场景必须使用 RE2 系列

混合方案:
├── 用 RE2 处理用户输入的正则（WHERE col REGEXP user_input）
├── 用 PCRE2 处理系统定义的正则（CHECK 约束、内部校验）
├── 通过编译期检测正则来源决定使用哪个引擎
└── Trino 已采用此方案: 默认 Java regex, 可配置切换到 RE2J
```

### 9. Collation 对正则匹配的隐藏影响

Collation 不仅影响大小写敏感性，还会影响字符类匹配和排序范围：

```
大小写行为:
├── MySQL: 正则的大小写敏感性默认跟随列的 collation
│   col VARCHAR(100) COLLATE utf8mb4_general_ci → REGEXP 不区分大小写
│   col VARCHAR(100) COLLATE utf8mb4_bin → REGEXP 区分大小写
├── PostgreSQL: 正则运算符 (~) 始终区分大小写, 无论 collation 设置
│   需要不区分大小写时必须显式使用 ~* 运算符
├── Oracle: REGEXP_LIKE 默认区分大小写, 需通过 'i' 标志切换
└── 陷阱: 同一条 SQL, 在 MySQL 和 PostgreSQL 中因 collation 语义不同结果可能相反

字符类 [a-z] 的范围:
├── 在二进制 collation 下, [a-z] 严格匹配 ASCII 0x61-0x7A
├── 在语言感知 collation 下, [a-z] 可能包含重音字符 (如 ä, ö, ü)
├── 这导致同一正则在不同 collation 下匹配不同的字符集
└── 建议: 文档中明确标注正则中字符范围与 collation 的交互规则

引擎开发者建议:
├── 在正则编译阶段将 collation 信息传入正则引擎
├── 字符类展开应参考当前 collation 的字符映射表
├── 提供 BINARY 修饰符允许用户绕过 collation 影响 (MySQL: BINARY col REGEXP)
└── 测试矩阵中必须包含 case-insensitive collation + 正则的组合
```

### 10. 多字节编码下的正则性能

非 UTF-8 编码（如 GBK、Shift-JIS、EUC-JP）下正则匹配可能产生非线性 CPU 开销：

```
问题根源:
├── 变长多字节编码中, 正则引擎需要判断每个字节是字符边界还是后续字节
├── `.` (匹配任意字符) 在多字节编码下必须解码完整字符, 不能简单匹配单字节
├── 某些编码的字符边界判断本身就是 O(n) 回溯 (如 Shift-JIS 的歧义字节)
├── 最坏情况: O(n × m × k), k 为字符边界判断开销
└── UTF-8 设计精巧: 每个字节的前导位明确标记角色, 字符边界判断 O(1)

实际影响:
├── GBK 编码下 REGEXP_REPLACE 对 1MB 文本的耗时可能是 UTF-8 的 3-5 倍
├── Latin1 编码下单字节匹配最快 (无多字节问题)
├── 某些正则引擎 (如旧版 MySQL Henry Spencer) 对非 ASCII 字节处理不正确
└── MySQL 5.x: 非 ASCII 字符的正则匹配结果可能不正确 (已在 8.0 ICU 中修复)

引擎开发者建议:
├── 内部统一使用 UTF-8 处理正则匹配, 在接口层做编码转换
├── 如果必须支持非 UTF-8, 在正则编译阶段注入编码感知的字符解码器
├── 对 REGEXP_REPLACE 等可能产生大量中间结果的函数, 设置输出大小上限
├── 性能测试矩阵: 必须包含 UTF-8、GBK、Latin1 三种编码的基准对比
└── 文档中警告: 非 UTF-8 编码下正则操作可能显著变慢
```

## 附录：快速迁移指南

### MySQL → PostgreSQL

| MySQL | PostgreSQL |
|-------|-----------|
| `col REGEXP 'pat'` | `col ~ 'pat'` |
| `REGEXP_LIKE(col, 'pat', 'i')` | `col ~* 'pat'` |
| `REGEXP_SUBSTR(col, 'pat')` | `substring(col FROM 'pat')` / `regexp_substr` (15+) |
| `REGEXP_REPLACE(col, 'pat', 'rep')` | `regexp_replace(col, 'pat', 'rep', 'g')` (**加 'g'!**) |
| `'\\d+'` | `'\d+'` |

### Oracle → MySQL

| Oracle | MySQL 8.0+ |
|--------|-----------|
| `REGEXP_LIKE(col, 'pat')` | `REGEXP_LIKE(col, 'pat')` (相同) |
| `REGEXP_SUBSTR(col, 'p', 1, 1, NULL, 1)` | `REGEXP_SUBSTR(col, 'p', 1, 1)` (无 group 参数) |
| `REGEXP_COUNT(col, 'pat')` | 无直接等价 |
| `'\d+'` | `'\\d+'` |

### MySQL → BigQuery

| MySQL | BigQuery |
|-------|---------|
| `col REGEXP 'pat'` | `REGEXP_CONTAINS(col, r'pat')` |
| `REGEXP_SUBSTR(col, 'pat')` | `REGEXP_EXTRACT(col, r'pat')` |
| 反向引用 `\\1` | **不支持** (RE2 限制) |
| `'\\d+'` | `r'\d+'` |
