# 字符串填充行为 (String Padding Behavior)

`CHAR(10)` 列存入 `'abc'` 后到底变成什么？读出来是 `'abc'` 还是 `'abc       '`？`'abc' = 'abc   '` 究竟是 TRUE 还是 FALSE？这些看似无害的问题，构成了 SQL 引擎跨方言迁移最高频的"看不见的坑"——同一条 `WHERE name = 'John'` 在 MySQL 上能匹配 `'John   '`，在 PostgreSQL 上不行；同一份 CSV 导入 Oracle 的 `CHAR(20)` 列，再倒回 PostgreSQL 时索引会突然不命中；SQL Server 的 `ANSI_PADDING` 设置如果在建表前后切换，同一张表的两列可能采用截然相反的策略。本文系统对比 45+ 数据库在 CHAR 填充、PAD SPACE / NO PAD 比较、LIKE 模式匹配、SELECT 时的尾空格修剪以及 TRIM 系列函数语义上的差异，是引擎开发者、数据迁移工程师和数据建模师的必备参考。

相关文章：[`char-vs-varchar.md`](./char-vs-varchar.md) 系统对比字符类型本身；[`string-comparison-collation.md`](./string-comparison-collation.md) 聚焦排序规则与大小写敏感。本文专注填充与修剪语义。

## SQL:1992 标准定义

SQL:1992 (ISO/IEC 9075-2) 在第 4.2 节首次形式化定义了字符类型的填充与比较规则，在第 8.2 节 (`<comparison predicate>`) 中规定了字符串比较时的填充语义。

### 标准核心条款

```sql
-- 标准要求 (SQL:1992 §4.2.1):
-- 1) CHARACTER(n) (即 CHAR(n)) 是定长类型
-- 2) 实际值长度 < n 时, 必须右补空格 (right-pad with <space>) 至 n
-- 3) CHARACTER VARYING(n) (即 VARCHAR(n)) 是变长类型, 不补空格
-- 4) 长度 > n 时, 标准要求报错 (而非截断), 除非环境允许 ALTER

-- 标准要求 (SQL:1992 §8.2 比较谓词):
-- 1) 比较两个字符串时, 较短者必须先填充到与较长者相同长度
-- 2) 默认填充字符是 <space> (U+0020)
-- 3) 这条规则被称为 "PAD SPACE" 比较语义
-- 4) 因此 'abc' = 'abc   ' 在标准上为 TRUE
```

```
CHAR(5) 存 'abc'  -> 物理存储 'abc  ' (固定 5 字符)
VARCHAR(5) 存 'abc' -> 物理存储 'abc' (实际 3 字符 + 长度元数据)

比较 'abc' = 'abc   ':
  填充较短者: 'abc   ' = 'abc   '
  按字符比较: 全相等
  结果: TRUE
```

### SQL:1992 已有的 NO PAD 选项

SQL:1992 在 §4.2.4 与 §11.32 的 `<collation definition>` 中已经定义了排序规则 (collation) 的 `PAD SPACE` / `NO PAD` 属性，允许引擎覆盖默认的 PAD SPACE 比较语义；后续版本仅在细节上做了微调：

```sql
-- SQL:1992 已定义的属性:
CREATE COLLATION my_no_pad_collation
    FROM "ucs_basic"
    NO PAD;     -- 比较时不再填充, 'abc' != 'abc   '

CREATE COLLATION my_pad_collation
    FROM "ucs_basic"
    PAD SPACE;  -- 比较时填充, 'abc' = 'abc   '
```

`PAD SPACE` 是 SQL:1992 字符比较的默认；`NO PAD` 同样在 SQL:1992 中作为 collation 可选属性已被定义，让 VARCHAR 比较"所见即所得"。这一属性解决了一个长期争议：标准默认让 `'abc' = 'abc   '` 在所有字符串比较中为 TRUE，许多用户认为反直觉。NO PAD 让 VARCHAR 的语义更接近大多数程序员的心理模型。

### 三个独立维度

填充行为可拆分为三个独立维度，常被混淆：

```
维度 1: 存储时 (on store) - 写入 CHAR(n) 时是否右补空格
维度 2: 检索时 (on retrieve) - SELECT 出来时是否包含填充空格
维度 3: 比较时 (on compare) - 两值比较是否忽略尾部空格 (PAD SPACE)
```

例如 PostgreSQL 的 CHAR(n)：维度 1 = 是 (存储补空格)；维度 2 = 是 (返回带空格)；维度 3 = 是 (比较时忽略)。MySQL 的 CHAR(n)：维度 1 = 是；维度 2 = 否 (尾空格被剥离)；维度 3 = 是。Snowflake 的 CHAR：三者皆否 (CHAR 退化为 VARCHAR 别名)。

## 总体支持矩阵 (45+ 引擎)

### CHAR 存储与比较行为

| 引擎 | CHAR(n) 存储补空格 | SELECT 返回带填充 | 比较 PAD SPACE (CHAR) | 比较 PAD SPACE (VARCHAR) | LIKE 模式右侧 PAD |
|------|------------------|-----------------|---------------------|--------------------------|----------------|
| PostgreSQL | 是 | 是 | 是 | 否 (NO PAD) | 否 (LIKE 严格匹配) |
| MySQL | 是 | 否 (剥离) | 是 (PAD SPACE) | 取决于 collation | 否 |
| MariaDB | 是 | 否 (剥离) | 是 (PAD SPACE) | 取决于 collation | 否 |
| SQLite | 否 (TEXT 亲和) | -- | 否 | 否 | 否 |
| Oracle | 是 | 是 | 是 (blank-padded) | 否 (NO PAD VARCHAR2) | 否 |
| SQL Server | 是 (ANSI_PADDING ON) | 是 | 是 | 是 (非标准) | 否 |
| DB2 | 是 | 是 | 是 (PAD SPACE) | 否 | 否 |
| Snowflake | 否 (CHAR≡VARCHAR) | 否 | 否 | 否 | 否 |
| BigQuery | -- (无 CHAR) | -- | -- | 否 | 否 |
| Redshift | 是 | 是 | 是 (PAD SPACE) | 否 | 否 |
| DuckDB | 否 (CHAR≡VARCHAR) | 否 | 否 | 否 | 否 |
| ClickHouse | -- (无 CHAR；FixedString \0) | -- | 否 (FixedString 字节比较) | 否 | 否 |
| Trino | 是 | 是 | 是 (PAD SPACE) | 否 | 否 |
| Presto | 是 | 是 | 是 (PAD SPACE) | 否 | 否 |
| Spark SQL | 是 (3.0+) | 否 (3.0+ 默认剥离) | 是 (PAD SPACE) | 否 | 否 |
| Hive | 是 | 否 | 是 | 否 | 否 |
| Flink SQL | 是 | 是 | 是 (PAD SPACE) | 否 | 否 |
| Databricks | 是 | 否 (默认剥离) | 是 | 否 | 否 |
| Teradata | 是 | 是 | 是 (PAD SPACE) | 否 | 否 |
| Greenplum | 是 (继承 PG) | 是 | 是 | 否 | 否 |
| CockroachDB | 是 (兼容 PG) | 是 | 是 | 否 (NO PAD) | 否 |
| TiDB | 是 (兼容 MySQL) | 否 | 是 | 取决于 collation | 否 |
| OceanBase (MySQL 模式) | 是 | 否 | 是 | 取决于 collation | 否 |
| OceanBase (Oracle 模式) | 是 | 是 | 是 | 否 | 否 |
| YugabyteDB | 是 (兼容 PG) | 是 | 是 | 否 | 否 |
| SingleStore | 是 | 否 | 是 | 取决于 collation | 否 |
| Vertica | 是 | 是 | 是 (PAD SPACE) | 否 | 否 |
| Impala | 是 | 是 | 是 | 否 | 否 |
| StarRocks | 是 | 是 | 是 | 否 (NO PAD) | 否 |
| Doris | 是 | 是 | 是 | 否 (NO PAD) | 否 |
| MonetDB | 是 | 是 | 是 (PAD SPACE) | 否 | 否 |
| CrateDB | -- (无 CHAR) | -- | -- | 否 | 否 |
| TimescaleDB | 是 (继承 PG) | 是 | 是 | 否 | 否 |
| QuestDB | -- (无 CHAR) | -- | -- | 否 | 否 |
| Exasol | 是 | 是 | 是 (PAD SPACE) | 否 | 否 |
| SAP HANA | 是 | 是 | 是 (PAD SPACE) | 否 | 否 |
| Informix | 是 | 是 | 是 (PAD SPACE) | 否 | 否 |
| Firebird | 是 | 是 | 是 (PAD SPACE) | 否 | 否 |
| H2 | 是 | 是 | 是 | 否 | 否 |
| HSQLDB | 是 | 是 | 是 | 否 | 否 |
| Derby | 是 | 是 | 是 (PAD SPACE) | 否 | 否 |
| Amazon Athena | 是 (继承 Trino) | 是 | 是 | 否 | 否 |
| Azure Synapse | 是 (ANSI_PADDING ON) | 是 | 是 | 是 (非标准) | 否 |
| Google Spanner | -- (无 CHAR) | -- | -- | 否 | 否 |
| Materialize | 是 (兼容 PG) | 是 | 是 | 否 | 否 |
| RisingWave | 是 (兼容 PG) | 是 | 是 | 否 | 否 |
| InfluxDB (SQL) | -- | -- | -- | 否 | 否 |
| DatabendDB | -- (无 CHAR) | -- | -- | 否 | 否 |
| Yellowbrick | 是 | 是 | 是 | 否 | 否 |
| Firebolt | -- (无 CHAR) | -- | -- | 否 | 否 |

> 注：本表分别列出 CHAR 和 VARCHAR 的比较语义，因为标准只要求 CHAR 使用 PAD SPACE，VARCHAR 在 SQL:1992 中也是 PAD SPACE 但 SQL:2003 后多数引擎改为 NO PAD。SQL Server 是少数 VARCHAR 仍 PAD SPACE 的引擎之一（基于 ANSI 标准早期版本）。

> 统计：约 36 个引擎实现了某种形式的 CHAR 类型并支持 PAD SPACE 比较；约 9 个引擎将 CHAR 退化为 VARCHAR 或完全没有 CHAR 类型；只有 2 个主流引擎 (SQL Server、Sybase 系) 让 VARCHAR 也 PAD SPACE。

### 字符串等值与 LIKE 比较行为对比

| 表达式 | PostgreSQL | MySQL (5.7) | MySQL (8.0 utf8mb4_0900) | SQL Server | Oracle | Snowflake | DuckDB |
|-------|------------|-------------|--------------------------|------------|--------|-----------|--------|
| `'abc' = 'abc'` (VARCHAR) | TRUE | TRUE | TRUE | TRUE | TRUE | TRUE | TRUE |
| `'abc' = 'abc   '` (VARCHAR) | FALSE | TRUE | FALSE | TRUE | FALSE | FALSE | FALSE |
| `'abc' = 'abc   '` (CHAR(6)) | TRUE | TRUE | TRUE | TRUE | TRUE | N/A (CHAR≡VARCHAR) | N/A |
| `'abc' LIKE 'abc'` | TRUE | TRUE | TRUE | TRUE | TRUE | TRUE | TRUE |
| `'abc' LIKE 'abc   '` | FALSE | FALSE | FALSE | FALSE | FALSE | FALSE | FALSE |
| `'abc   ' LIKE 'abc'` | FALSE | FALSE | FALSE | FALSE | FALSE | FALSE | FALSE |
| `'abc   ' LIKE 'abc%'` | TRUE | TRUE | TRUE | TRUE | TRUE | TRUE | TRUE |
| `LENGTH('abc')` (CHAR(5) 列值) | 5 | 3 | 3 | 5 | 5 | 3 | 3 |

> 关键观察：(1) MySQL 5.7 默认 collation 让 VARCHAR 也 PAD SPACE；MySQL 8.0 默认 utf8mb4_0900_ai_ci 改为 NO PAD，行为更接近标准。(2) LIKE 不做 PAD SPACE，无论引擎和类型——尾空格在 LIKE 中是字面字符。(3) PostgreSQL 的 CHAR(5) 列读取时返回带空格的值，因此 `LENGTH()` 返回 5；MySQL 默认剥离尾空格，返回 3。

### TRIM / LTRIM / RTRIM 函数支持

| 引擎 | TRIM (SQL 标准) | LTRIM | RTRIM | TRIM 自定义字符 | TRIM BOTH/LEADING/TRAILING | 多字符集 |
|------|----------------|-------|-------|---------------|---------------------------|---------|
| PostgreSQL | 是 | 是 | 是 | 是 | 是 | 是 |
| MySQL | 是 | 是 | 是 | 是 (8.0+) | 是 | 是 |
| MariaDB | 是 | 是 | 是 | 是 (10.4+) | 是 | 是 |
| SQLite | 是 | 是 | 是 | 是 | 否 (无 BOTH/LEADING/TRAILING) | 是 |
| Oracle | 是 | 是 | 是 | 是 (单字符) | 是 | 是 |
| SQL Server | 是 (2017+) | 是 | 是 | 是 (2022+) | 是 (2022+) | 是 |
| DB2 | 是 | 是 | 是 | 是 | 是 | 是 |
| Snowflake | 是 | 是 | 是 | 是 | 是 | 是 |
| BigQuery | 是 | 是 | 是 | 是 | 否 (用参数代替) | 是 |
| Redshift | 是 | 是 | 是 | 是 | 是 | 是 |
| DuckDB | 是 | 是 | 是 | 是 | 是 | 是 |
| ClickHouse | 是 | 是 | 是 | 否 (TRIM BOTH/LEADING/TRAILING 只剥空格) | 是 | 是 |
| Trino | 是 | 是 | 是 | 是 (3.x+) | 是 | 是 |
| Presto | 是 | 是 | 是 | 是 | 是 | 是 |
| Spark SQL | 是 | 是 | 是 | 是 | 是 | 是 |
| Hive | 是 | 是 | 是 | 否 (仅空格) | 否 | 是 |
| Flink SQL | 是 | -- (用 TRIM LEADING) | -- (用 TRIM TRAILING) | 是 | 是 | 是 |
| Databricks | 是 | 是 | 是 | 是 | 是 | 是 |
| Teradata | 是 | 是 | 是 | 是 | 是 | 是 |
| Greenplum | 是 | 是 | 是 | 是 | 是 | 是 |
| CockroachDB | 是 | 是 | 是 | 是 | 是 | 是 |
| TiDB | 是 | 是 | 是 | 是 | 是 | 是 |
| OceanBase | 是 | 是 | 是 | 是 | 是 | 是 |
| YugabyteDB | 是 | 是 | 是 | 是 | 是 | 是 |
| SingleStore | 是 | 是 | 是 | 是 | 是 | 是 |
| Vertica | 是 | 是 | 是 | 是 | 是 | 是 |
| Impala | 是 | 是 | 是 | 否 | 否 | 是 |
| StarRocks | 是 | 是 | 是 | 是 (3.0+) | 是 | 是 |
| Doris | 是 | 是 | 是 | 是 | 是 | 是 |
| MonetDB | 是 | 是 | 是 | 是 | 是 | 是 |
| CrateDB | 是 | 是 | 是 | 是 | 是 | 是 |
| TimescaleDB | 是 (继承 PG) | 是 | 是 | 是 | 是 | 是 |
| Exasol | 是 | 是 | 是 | 是 | 是 | 是 |
| SAP HANA | 是 | 是 | 是 | 是 | 是 | 是 |
| Informix | 是 | 是 | 是 | 是 | 是 | 是 |
| Firebird | 是 | 否 (用 TRIM LEADING) | 否 (用 TRIM TRAILING) | 是 | 是 | 是 |
| H2 | 是 | 是 | 是 | 是 | 是 | 是 |
| HSQLDB | 是 | 是 | 是 | 是 | 是 | 是 |
| Derby | 是 | 是 | 是 | 是 | 是 | 是 |
| Amazon Athena | 是 (继承 Trino) | 是 | 是 | 是 | 是 | 是 |
| Azure Synapse | 是 | 是 | 是 | 是 | 是 | 是 |
| Google Spanner | 是 | 是 | 是 | 是 | 是 | 是 |
| Materialize | 是 (PG 兼容) | 是 | 是 | 是 | 是 | 是 |
| RisingWave | 是 (PG 兼容) | 是 | 是 | 是 | 是 | 是 |
| Yellowbrick | 是 | 是 | 是 | 是 | 是 | 是 |

> 关键观察：(1) Firebird 和 Flink SQL 不提供 LTRIM/RTRIM 简写，必须使用 SQL 标准的 `TRIM(LEADING/TRAILING ...)`。(2) SQL Server 2017 才引入 SQL 标准 `TRIM`；2022 才支持自定义字符。(3) ClickHouse 的 `TRIM` 只能去除空格，无法指定其他字符（要用 `replaceRegexpAll` 替代）。(4) Hive 的 `TRIM/LTRIM/RTRIM` 只能去除 ASCII 空格。

### 引擎特定的填充配置开关

| 引擎 | 配置项 | 默认值 | 影响 |
|------|--------|-------|------|
| SQL Server | `SET ANSI_PADDING ON/OFF` | ON (2000+) | OFF 时 CHAR/BINARY 不补空格、VARCHAR 剥尾空格 |
| MySQL | `sql_mode = PAD_CHAR_TO_FULL_LENGTH` | 不启用 | 启用时 SELECT 返回 CHAR 列时保留尾空格 |
| MySQL | collation `_pad` 后缀 (8.0+) | 取决于 collation | `_0900_ai_ci` 隐含 NO PAD；`_general_ci` 隐含 PAD SPACE |
| Oracle | `NLS_COMP` / `BLANK_TRIMMED_COMPARISON` | 取决于会话 | 控制 VARCHAR2 与 CHAR 之间的比较模式 |
| PostgreSQL | 无开关 | 标准固定 | CHAR PAD SPACE / VARCHAR NO PAD 不可改 |
| Spark SQL | `spark.sql.legacy.charVarcharAsString` | false (3.1+) | true 时 CHAR/VARCHAR 退化为 STRING (无填充) |
| Snowflake | 无 | 固定 | CHAR≡VARCHAR, 永远不填充 |
| DB2 | 数据库 codeset / locale | -- | 影响多字节填充字符 |
| Sybase ASE | `set string_rtruncation on` | off | 控制赋值时是否报错 / 截断 |
| Informix | `IFX_PAD_VARCHAR` | -- | 影响 VARCHAR 输出补空格 (历史选项) |
| Firebird | `LEGACY_PAD_BLANK_BYTE` | -- | 多字节字符集下控制是否填充字节级空格 |
| Teradata | `LegacyMode` 设置 | -- | 部分版本控制 CHAR 比较模式 |

## SQL 标准的完整规则: PAD SPACE 与 NO PAD

### SQL:1992 默认行为

```
SQL:1992 §8.2 比较谓词:
  "如果两个字符串长度不同, 较短者必须右补 <space> 使长度相等, 然后逐字符比较"

这意味着:
  'abc' = 'abc   '  -> TRUE  (短串补 3 空格)
  'abc' < 'abd'     -> TRUE  (字典序)
  'abc' < 'abc!'    -> TRUE  (短串补 1 空格 vs 长串末尾 '!')
                       注: 假设 ' ' 的 codepoint < '!'

LIKE 不受 PAD SPACE 影响 (SQL:1992 §8.5):
  'abc   ' LIKE 'abc'   -> FALSE  (尾空格是字面字符)
  'abc   ' LIKE 'abc%'  -> TRUE   (% 匹配空格)
```

### SQL:1992 已定义的 NO PAD 属性

```sql
-- SQL:1992 §4.2.4 / §11.32 排序规则定义即包含:
CREATE COLLATION my_no_pad
    FROM "ucs_basic"
    NO PAD;     -- 比较时不填充

-- 使用 NO PAD 排序规则后:
'abc' COLLATE my_no_pad = 'abc   '  -> FALSE  (长度不等直接不同)
```

NO PAD 让 VARCHAR 比较"所见即所得"，更符合现代程序员的心理预期。一些数据库（如 MySQL 8.0 的 `utf8mb4_0900` 系列）将 NO PAD 设为新默认。

### 标准时间线与各版本调整

```
时间线:
  SQL:1992  -> 字符比较默认 PAD SPACE; collation 定义已包含 PAD SPACE / NO PAD 属性
  SQL:1999  -> 引入 CLOB, 不在 PAD SPACE 范围
  SQL:2003  -> 排序规则与 Unicode 进一步整合
  SQL:2008  -> Unicode 排序规则进一步规范
  SQL:2016  -> 多字节字符的 NO PAD 行为细化
```

各引擎采纳标准的速度不同：PostgreSQL 长期遵循 SQL:1992 默认 (CHAR PAD SPACE，VARCHAR 实际是 NO PAD)；MySQL 8.0 完成了向 NO PAD VARCHAR 的迁移；SQL Server 至今（2025）仍让 VARCHAR PAD SPACE（出于历史兼容）。

## 各引擎详解

### PostgreSQL: 严格的 PAD SPACE (CHAR) / NO PAD (VARCHAR)

PostgreSQL 是 SQL:1992 / SQL:2003 双语义混合的"教科书实现"。

```sql
-- 1) CHAR(n) 存储与检索均带空格
CREATE TABLE t (c CHAR(10), v VARCHAR(10));
INSERT INTO t VALUES ('abc', 'abc');

SELECT length(c), length(v) FROM t;
-- length=10, length=3   -- CHAR 返回填充值, VARCHAR 不填充

SELECT '|' || c || '|' AS char_val,
       '|' || v || '|' AS varchar_val FROM t;
-- |abc       |   |abc|   -- CHAR 列右补 7 空格

-- 2) CHAR 比较: PAD SPACE 强制启用
SELECT c = 'abc' FROM t;          -- TRUE  (短串补空格后相等)
SELECT c = 'abc   ' FROM t;       -- TRUE
SELECT c = 'abc       ' FROM t;   -- TRUE  (10 空格)
SELECT c LIKE 'abc' FROM t;       -- FALSE (LIKE 不 PAD)
SELECT c LIKE 'abc%' FROM t;      -- TRUE  (% 匹配空格)

-- 3) VARCHAR 比较: NO PAD 严格匹配
SELECT v = 'abc' FROM t;          -- TRUE
SELECT v = 'abc ' FROM t;         -- FALSE (NO PAD)
SELECT v = 'abc   ' FROM t;       -- FALSE

-- 4) CHAR 与 VARCHAR 跨类型比较: 隐式转 TEXT, 实际行为接近 NO PAD
-- 注意: 跨类型比较时 PG 会做类型提升, 通常不再 PAD
SELECT t.c::TEXT = 'abc' FROM t;  -- FALSE!  (CHAR 转 TEXT 后保留空格)

-- 5) CHAR 列上 GROUP BY / DISTINCT
SELECT c, COUNT(*) FROM (
    VALUES ('abc'::CHAR(10)), ('abc   '::CHAR(10)), ('abc       '::CHAR(10))
) AS x(c) GROUP BY c;
-- 一组: c='abc       ' count=3   -- 视为同一值

-- 6) 索引行为: CHAR 索引存储填充值, 但比较时按 PAD SPACE
CREATE INDEX idx_c ON t (c);
SELECT * FROM t WHERE c = 'abc';  -- 命中索引
```

PostgreSQL 的 CHAR 总被官方文档不推荐使用 ("There is no performance advantage to using CHAR(n)... in fact CHAR(n) is usually the slowest of the three")。原因之一就是这种"存储和返回都带空格、比较又忽略空格"的二重性容易让应用代码出错。

### MySQL: 5.0.3 是分水岭

MySQL 在 5.0.3 之前，VARCHAR 列也会剥离尾部空格存储，与标准不符。5.0.3 后改为严格存储用户输入。

```sql
-- MySQL 5.0.3 前的非标准行为:
INSERT INTO t (v) VALUES ('abc   ');  -- 存为 'abc' (尾空格被剥)

-- MySQL 5.0.3 起 (2005-03-23 发布):
INSERT INTO t (v) VALUES ('abc   ');  -- 存为 'abc   ' (3 尾空格保留)

-- 但 CHAR 列仍然剥离 SELECT 时的尾空格 (维度 2):
CREATE TABLE t (c CHAR(10), v VARCHAR(10));
INSERT INTO t VALUES ('abc', 'abc   ');
SELECT length(c), length(v) FROM t;  -- 3, 6  (CHAR 剥离, VARCHAR 保留)

-- 启用 PAD_CHAR_TO_FULL_LENGTH 改变 CHAR SELECT 行为
SET sql_mode = 'PAD_CHAR_TO_FULL_LENGTH';
SELECT length(c) FROM t;             -- 10 (现在 CHAR 也返回填充值)
```

#### MySQL collation 与 PAD 行为

```sql
-- MySQL 8.0 引入了 collation 的 PAD 属性:
SHOW COLLATION WHERE Collation IN ('utf8mb4_0900_ai_ci', 'utf8mb4_general_ci');
-- utf8mb4_0900_ai_ci  Pad_attribute=NO PAD
-- utf8mb4_general_ci  Pad_attribute=PAD SPACE

-- 因此在 8.0 默认 collation 下 VARCHAR 比较是 NO PAD:
SET NAMES utf8mb4 COLLATE utf8mb4_0900_ai_ci;
SELECT 'abc' = 'abc   ';   -- 0 (FALSE, NO PAD)

-- 切回旧 collation 即恢复 PAD SPACE:
SET NAMES utf8mb4 COLLATE utf8mb4_general_ci;
SELECT 'abc' = 'abc   ';   -- 1 (TRUE, PAD SPACE)

-- 但 CHAR 类型不受影响, 永远 PAD SPACE:
CREATE TABLE c10 (c CHAR(10));
INSERT INTO c10 VALUES ('abc');
SELECT * FROM c10 WHERE c = 'abc       ';   -- 命中 (CHAR PAD SPACE)
```

#### MySQL 5.0.3 变更的历史背景

```
MySQL 4.x / 5.0.0 - 5.0.2 行为 (非标准):
  INSERT INTO t (varchar_col) VALUES ('abc   ');
  -- 实际存储: 'abc'  (尾空格被剥离)
  -- SELECT 返回: 'abc'

MySQL 5.0.3+ 标准化后:
  INSERT INTO t (varchar_col) VALUES ('abc   ');
  -- 实际存储: 'abc   '
  -- SELECT 返回: 'abc   '

迁移影响:
  从 4.x 升级到 5.0.3+ 后, 现有数据不变, 但新插入的行可能保留尾空格
  应用层若依赖"VARCHAR 总是不带尾空格"的假设, 行为会变化
```

### SQL Server: ANSI_PADDING 控制全局行为

SQL Server 的填充行为由 `SET ANSI_PADDING ON/OFF` 控制，但这个开关只在**建表时**生效，列的填充策略一旦写入 catalog 就固定。

```sql
-- SQL Server 2000+ 默认 ANSI_PADDING ON
SET ANSI_PADDING ON;

CREATE TABLE t (
    c   CHAR(10),
    v   VARCHAR(10),
    b   BINARY(10),
    vb  VARBINARY(10)
);

INSERT INTO t VALUES ('abc', 'abc   ', 0x00FF, 0x00FF);

SELECT LEN(c), LEN(v), DATALENGTH(b), DATALENGTH(vb) FROM t;
-- ANSI_PADDING ON:
--   c: 3 (LEN 不计尾空格), DATALENGTH(c)=10
--   v: 6 (尾空格保留)
--   b: 10 (二进制全长)
--   vb: 2 (实际长度)

-- 切换到 OFF 重建表:
SET ANSI_PADDING OFF;
DROP TABLE t;
CREATE TABLE t (c CHAR(10), v VARCHAR(10));
INSERT INTO t VALUES ('abc', 'abc   ');

SELECT LEN(c), LEN(v) FROM t;
-- ANSI_PADDING OFF:
--   c: 3 (CHAR 不再补空格存储)
--   v: 3 (尾空格被剥)

-- 比较行为不受 ANSI_PADDING 影响:
SELECT 'abc' = 'abc   ';   -- 1 (PAD SPACE, 永远如此)
SELECT '|' + 'abc' + '|' WHERE 'abc' = 'abc   ';   -- 显示 |abc|
```

ANSI_PADDING OFF 已被微软标记为废弃 (deprecated)，现代代码应保持 ON。但旧表可能携带 OFF 历史，导出时需小心。

#### SQL Server 的 VARCHAR PAD SPACE 例外

```sql
-- SQL Server 是少数让 VARCHAR 也 PAD SPACE 的引擎:
DECLARE @a VARCHAR(10) = 'abc';
DECLARE @b VARCHAR(10) = 'abc   ';
SELECT CASE WHEN @a = @b THEN 'EQUAL' ELSE 'NOT EQUAL' END;
-- 输出: EQUAL

-- 这与 SQL Server 早期的 ANSI 兼容承诺有关
-- 微软文档 (SQL Server 2022) 仍然保持此行为以兼容历史代码
```

### Oracle: CHAR blank-padded, VARCHAR2 NO PAD

Oracle 强烈推荐使用 `VARCHAR2` 而非标准的 `VARCHAR`（VARCHAR 在 Oracle 中保留供未来语义变化使用）。

```sql
-- Oracle: CHAR 与 VARCHAR2 比较语义对比
CREATE TABLE t (c CHAR(10), v VARCHAR2(10));
INSERT INTO t VALUES ('abc', 'abc');

SELECT LENGTH(c), LENGTH(v) FROM t;
-- 10, 3   -- CHAR 返回带填充值

-- CHAR 比较: blank-padded (Oracle 用语, 等价于 PAD SPACE)
SELECT * FROM t WHERE c = 'abc';            -- 命中
SELECT * FROM t WHERE c = 'abc       ';     -- 命中

-- VARCHAR2 比较: non-padded (NO PAD)
SELECT * FROM t WHERE v = 'abc';            -- 命中
SELECT * FROM t WHERE v = 'abc   ';         -- 不命中

-- CHAR 与 VARCHAR2 的混合比较: Oracle 文档明确规则
-- 当 CHAR 与 VARCHAR2 比较时, 整体使用 non-padded 模式
SELECT * FROM t WHERE c = v;
-- 此时 c 实际值 'abc       ' 与 v='abc' 比较 -> FALSE
-- 因为混合比较退化为 non-padded
```

#### Oracle 的字符串语义 (PL/SQL 文档明确总结)

```
Oracle 字符串比较的 4 种语义:
  1. blank-padded:    CHAR vs CHAR, CHAR vs CHAR 字面量
  2. non-padded:      VARCHAR2 vs VARCHAR2, VARCHAR2 vs VARCHAR2 字面量
  3. non-padded:      CHAR vs VARCHAR2 (混合时退化为 non-padded)
  4. non-padded:      字符串字面量被视为 VARCHAR2

会话级别开关:
  ALTER SESSION SET NLS_COMP = 'LINGUISTIC';
  ALTER SESSION SET NLS_SORT = 'BINARY_CI';
```

#### Oracle BLANK_PAD 函数与 RPAD 模拟

```sql
-- 没有内置的 BLANK_PAD, 但可以用 RPAD/LPAD 模拟
SELECT RPAD('abc', 10) FROM dual;         -- 'abc       ' (右补空格至 10)
SELECT LPAD('abc', 10) FROM dual;         -- '       abc' (左补空格至 10)
SELECT RPAD('abc', 10, '*') FROM dual;    -- 'abc*******'

-- TRIM 与 RPAD 配对
SELECT TRIM(RPAD('abc', 10)) FROM dual;   -- 'abc' (修剪后)
```

### DB2: 标准的标杆

DB2 严格遵循 SQL:1992 / SQL:2003 标准，是 PAD SPACE / NO PAD 行为最"教科书"的引擎之一。

```sql
-- DB2: CHAR 与 VARCHAR 行为
CREATE TABLE t (c CHAR(10), v VARCHAR(10));
INSERT INTO t VALUES ('abc', 'abc');

SELECT LENGTH(c), LENGTH(v) FROM t;
-- 10, 3

-- CHAR 比较: PAD SPACE
SELECT * FROM t WHERE c = 'abc';            -- 命中
SELECT * FROM t WHERE c = 'abc       ';     -- 命中

-- VARCHAR 比较: NO PAD (实际行为)
-- 但 DB2 文档定义 VARCHAR 比较语义为 SQL:1992 PAD SPACE, 然而实现中 VARCHAR
-- 末尾空格不被存储时已剥离的话可能差异
INSERT INTO t (v) VALUES ('abc   ');
-- DB2 实际存储 'abc   ' (从 V8.1 起严格保留)

-- LIKE 同样不 PAD:
SELECT * FROM t WHERE c LIKE 'abc';         -- 不命中 (LIKE 严格)
SELECT * FROM t WHERE c LIKE 'abc%';        -- 命中
```

### SQLite: TEXT 亲和性，无 CHAR 强制

SQLite 是动态类型系统，CHAR(n) 实际等同于 TEXT，不强制长度，不补空格。

```sql
-- SQLite 的类型亲和性 (type affinity):
CREATE TABLE t (c CHAR(10), v VARCHAR(10), n NCHAR(20));

INSERT INTO t VALUES ('abc', 'abc   ', 'hello');
SELECT length(c), length(v), length(n) FROM t;
-- 3, 6, 5   -- 均按实际长度, 不填充

-- CHAR(10) 在 SQLite 仅是"建议", 不强制截断
INSERT INTO t (c) VALUES ('this is a very long string');
-- 成功插入, length(c) = 26

-- 比较: NO PAD, 严格按字符
SELECT 'abc' = 'abc   ';   -- 0 (FALSE)
SELECT 'abc' = 'abc';      -- 1 (TRUE)

-- 但 SQLite 文档允许通过自定义 collation 实现 PAD SPACE 模拟:
-- 默认 collation 是 BINARY, 不 PAD;
-- NOCASE 也不 PAD; 仅大小写不敏感.
```

SQLite 的设计哲学是"约束最小、行为透明"，因此完全没有标准 PAD SPACE 概念。这对从其他数据库迁移的代码可能是一个隐蔽的语义变化。

### ClickHouse: FixedString 用 NUL 填充

ClickHouse 没有 CHAR 类型，只有可变长度的 `String` 和定长的 `FixedString(N)`。FixedString 用 `\0` (字节 0x00) 而非空格填充。

```sql
-- ClickHouse: FixedString 行为
CREATE TABLE t (
    s String,
    f FixedString(10)
) ENGINE = Memory;

INSERT INTO t VALUES ('abc', 'abc');
SELECT length(s), length(f), hex(f) FROM t;
-- 3, 10, '6162630000000000000000'   -- f 用 \0 补到 10 字节

-- FixedString 比较: 字节级精确匹配, 包含 \0
SELECT s = f FROM t;
-- 0 (FALSE)   -- 因为 f 是 'abc\0\0\0\0\0\0\0', s 是 'abc'

-- 显式转换才相等:
SELECT s = trim(TRAILING '\0' FROM f) FROM t;   -- 1 (TRUE)
SELECT toString(f) = s;                          -- 取决于版本

-- LIKE 在 FixedString 上同样按字节比较, \0 是字面字节
SELECT f LIKE 'abc' FROM t;            -- 0 (FALSE, 因为 f 包含 \0)
SELECT f LIKE 'abc%' FROM t;           -- 0 (FALSE? 取决于是否将 \0 视作字符)
```

ClickHouse 文档明确说 FixedString 设计用于"已知固定字节长度的数据，如 IP 地址、UUID、哈希值"，不应作为 CHAR 替代品。

### Snowflake: CHAR ≡ VARCHAR

Snowflake 文档明确说明 CHAR 是 VARCHAR 的别名，没有任何填充行为。

```sql
-- Snowflake: CHAR 完全退化为 VARCHAR
CREATE TABLE t (c CHAR(10), v VARCHAR(10));
INSERT INTO t VALUES ('abc', 'abc');

SELECT LENGTH(c), LENGTH(v) FROM t;
-- 3, 3

SELECT * FROM t WHERE c = 'abc';            -- 命中
SELECT * FROM t WHERE c = 'abc       ';     -- 不命中! (Snowflake CHAR 不 PAD)

-- 这是与传统数据库的最大语义差异之一
-- 从 Oracle / SQL Server / PostgreSQL 迁移到 Snowflake 时
-- CHAR 列上的尾空格匹配查询会大量失效
```

Snowflake 的设计逻辑是"VARCHAR 永远够用，定长存储无现代意义"。但这导致从传统 OLTP 数据库迁移时，CHAR 类型的语义假设全部失效。

### DuckDB: 同样 CHAR ≡ VARCHAR

DuckDB 与 Snowflake 类似，所有 CHAR / VARCHAR / TEXT 都映射为 VARCHAR (无长度限制)。

```sql
-- DuckDB: 类型统一为 VARCHAR
CREATE TABLE t (c CHAR(10), v VARCHAR(10), s TEXT);
INSERT INTO t VALUES ('abc', 'abc   ', 'abc');

SELECT length(c), length(v), length(s) FROM t;
-- 3, 6, 3   -- 全部按实际长度

SELECT typeof(c), typeof(v), typeof(s) FROM t;
-- VARCHAR, VARCHAR, VARCHAR

-- 比较: NO PAD (严格)
SELECT 'abc' = 'abc   ';   -- false
```

### Spark SQL / Databricks

Spark SQL 在 3.0 之前完全没有 CHAR / VARCHAR 概念，CHAR(n) 被映射为 STRING。3.0 起引入了 CHAR / VARCHAR 类型并支持 PAD SPACE 比较，但默认 SELECT 时仍剥离尾空格。

```sql
-- Spark SQL 3.0+ 的 CHAR 行为
CREATE TABLE t (c CHAR(10), v VARCHAR(10), s STRING) USING parquet;
INSERT INTO t VALUES ('abc', 'abc', 'abc');

SELECT length(c), length(v), length(s) FROM t;
-- 取决于 spark.sql.legacy.charVarcharAsString:
-- false (默认 3.1+): 10, 3, 3   -- CHAR 补全
-- true (legacy): 3, 3, 3        -- CHAR 退化为 STRING

-- CHAR 比较启用 PAD SPACE
SELECT * FROM t WHERE c = 'abc';            -- 命中

-- Spark 3.0+ 支持 NO PAD VARCHAR 比较
SELECT * FROM t WHERE v = 'abc   ';         -- 不命中

-- Compare 时尾空格修剪 (旧版本通用行为):
-- Spark / Hive / Databricks 在 STRING 类型间比较时通常严格匹配
SELECT 'abc' = 'abc   ';   -- false

-- 但 CHAR 列读出时去除空格的设计与 PostgreSQL 行为相反
SELECT c FROM t;            -- 返回 'abc' (无空格)
SELECT c, length(c) FROM t; -- 'abc', 但 length=10? 取决于配置
```

### Hive: STRING 主导，CHAR 受限

Hive 的主要字符串类型是 `STRING` (无长度上限)，CHAR(n) 是较晚 (0.13+) 引入的。

```sql
-- Hive 的 CHAR 与 VARCHAR
CREATE TABLE t (c CHAR(10), v VARCHAR(10), s STRING);
INSERT INTO t VALUES ('abc', 'abc   ', 'abc   ');

SELECT length(c), length(v), length(s) FROM t;
-- 取决于版本: 通常 10, 6, 6

-- CHAR 比较: PAD SPACE
SELECT * FROM t WHERE c = 'abc';            -- 命中

-- STRING 与 VARCHAR 比较: NO PAD
SELECT * FROM t WHERE s = 'abc';            -- 不命中! (s='abc   ')
SELECT * FROM t WHERE s = 'abc   ';         -- 命中
```

#### Hive / Spark 在 JOIN 时的尾空格陷阱

```sql
-- 经典 JOIN 陷阱: 两表 CHAR(10) 列上的 JOIN
-- 表 A: a 列 CHAR(10), 值 'abc'  -> 实际存储 'abc       '
-- 表 B: b 列 CHAR(10), 值 'abc'  -> 实际存储 'abc       '
SELECT * FROM A JOIN B ON A.a = B.b;
-- 命中, PAD SPACE

-- 但若 A 列改为 STRING 后导入:
-- 表 A: a 列 STRING, 值 'abc'   -> 'abc' (无空格)
-- 表 B: b 列 CHAR(10), 值 'abc' -> 'abc       '
SELECT * FROM A JOIN B ON A.a = B.b;
-- 不命中! (类型混合导致语义退化)

-- 解决: 显式 trim 或类型对齐
SELECT * FROM A JOIN B ON RTRIM(A.a) = RTRIM(B.b);
```

### Trino / Presto: 严格 PAD SPACE CHAR

Trino 在 CHAR 上严格实现 PAD SPACE，但 VARCHAR 是 NO PAD。

```sql
-- Trino: CHAR 与 VARCHAR
SELECT length(CAST('abc' AS CHAR(10)));    -- 10
SELECT length(CAST('abc' AS VARCHAR(10))); -- 3

SELECT CAST('abc' AS CHAR(10)) = 'abc';        -- TRUE
SELECT CAST('abc' AS CHAR(10)) = CAST('abc   ' AS CHAR(10));  -- TRUE

-- VARCHAR 严格
SELECT 'abc' = 'abc   ';   -- FALSE
```

### MariaDB: 与 MySQL 一致, 部分版本细节差异

MariaDB 自分叉以来基本与 MySQL 行为一致，但在 collation 方面差异较大：MariaDB 至 10.x 仍以 `utf8mb4_general_ci` (PAD SPACE) 为默认；MySQL 8.0 已经切到 `utf8mb4_0900_ai_ci` (NO PAD)。

```sql
-- MariaDB 10.4+ 默认行为
CREATE TABLE t (c CHAR(10), v VARCHAR(10));
INSERT INTO t VALUES ('abc', 'abc   ');

SELECT length(c), length(v) FROM t;
-- 3, 6

SELECT * FROM t WHERE v = 'abc';   -- 命中 (PAD SPACE 默认 collation)
-- 这与 MySQL 8.0 默认行为不同!

-- 显式切到 NO PAD collation:
SELECT * FROM t WHERE v COLLATE utf8mb4_0900_ai_ci = 'abc';
-- 但 MariaDB 10.x 不支持 utf8mb4_0900_ai_ci
-- 用 utf8mb4_uca1400 系列代替 (10.10+)
```

### Vertica: 严格 PAD SPACE

```sql
-- Vertica: 标准 CHAR(n) 行为
CREATE TABLE t (c CHAR(10), v VARCHAR(10));
INSERT INTO t VALUES ('abc', 'abc');
SELECT length(c), length(v) FROM t;   -- 10, 3
SELECT * FROM t WHERE c = 'abc';      -- 命中 (PAD SPACE)
SELECT * FROM t WHERE v = 'abc   ';   -- 不命中 (NO PAD)
```

### Teradata: 标准 PAD SPACE, 含 BLOB 例外

```sql
-- Teradata: CHAR 与 VARCHAR
CREATE TABLE t (c CHAR(10), v VARCHAR(10));
INSERT INTO t VALUES ('abc', 'abc');
SELECT char_length(c), char_length(v) FROM t;   -- 10, 3

-- PAD SPACE 比较
SELECT * FROM t WHERE c = 'abc       ';   -- 命中

-- TRIM 系列函数齐全, 支持 LEADING/TRAILING/BOTH
SELECT TRIM(BOTH ' ' FROM '  abc  ');    -- 'abc'
SELECT TRIM(TRAILING '0' FROM '12300');  -- '123'
```

### Redshift: PostgreSQL-like 但有差异

Redshift fork 自 PostgreSQL 8.0.2，CHAR 的填充与比较行为继承 PG，但 VARCHAR 的存储有 1MB / 65535 字节限制。

```sql
-- Redshift CHAR 与 VARCHAR
CREATE TABLE t (c CHAR(10), v VARCHAR(10));
INSERT INTO t VALUES ('abc', 'abc');
SELECT length(c), length(v) FROM t;   -- 10, 3

SELECT * FROM t WHERE c = 'abc';      -- 命中 (PAD SPACE)
SELECT * FROM t WHERE v = 'abc   ';   -- 不命中 (NO PAD)
```

### CockroachDB: 兼容 PG 严格模式

```sql
-- CockroachDB: 完全兼容 PostgreSQL 语义
CREATE TABLE t (c CHAR(10), v VARCHAR(10));
INSERT INTO t VALUES ('abc', 'abc');
SELECT length(c), length(v) FROM t;   -- 10, 3

SELECT * FROM t WHERE c = 'abc';      -- 命中 (CHAR PAD SPACE)
SELECT * FROM t WHERE v = 'abc   ';   -- 不命中 (NO PAD)
```

### TiDB: 兼容 MySQL

```sql
-- TiDB: 与 MySQL 5.7 兼容, CHAR 类似 PG, VARCHAR 取决于 collation
CREATE TABLE t (c CHAR(10), v VARCHAR(10));
INSERT INTO t VALUES ('abc', 'abc   ');

SELECT length(c), length(v) FROM t;
-- 3, 6   -- TiDB 对 CHAR SELECT 默认剥空格 (兼容 MySQL)

-- TiDB 支持 PAD_CHAR_TO_FULL_LENGTH sql_mode
SET sql_mode = 'PAD_CHAR_TO_FULL_LENGTH';
SELECT length(c) FROM t;   -- 10
```

### SAP HANA: 已废弃 CHAR

```sql
-- SAP HANA 推荐使用 NVARCHAR / VARCHAR / NCHAR
-- CHAR 类型已被标记为废弃, 但仍工作
CREATE TABLE t (c CHAR(10), nv NVARCHAR(10), v VARCHAR(10));
INSERT INTO t VALUES ('abc', 'abc', 'abc');
SELECT length(c), length(nv), length(v) FROM t;   -- 10, 3, 3

SELECT * FROM t WHERE c = 'abc       ';   -- 命中 (PAD SPACE)
```

### Other dialects 简评

- **Materialize / RisingWave**：基本继承 PostgreSQL 语义，CHAR PAD SPACE / VARCHAR NO PAD。
- **Greenplum / TimescaleDB / YugabyteDB**：均继承 PG，行为一致。
- **OceanBase**：MySQL 模式与 MySQL 5.7 兼容；Oracle 模式与 Oracle 兼容。
- **SingleStore (MemSQL)**：与 MySQL 兼容，但 collation 选择稍少。
- **Impala / StarRocks / Doris**：CHAR 实现 PAD SPACE 存储；VARCHAR 默认 NO PAD 比较。
- **MonetDB**：标准 PAD SPACE CHAR / NO PAD VARCHAR。
- **Exasol / Firebird / Informix / H2 / HSQLDB / Derby**：均严格遵循 SQL:1992 标准。
- **Yellowbrick**：兼容 PostgreSQL 大部分语义。
- **DatabendDB / Firebolt / BigQuery / Spanner / CrateDB / QuestDB**：无独立 CHAR 类型；STRING / VARCHAR 均为 NO PAD。

## TRIM / LTRIM / RTRIM 语义详解

### SQL 标准 TRIM 语法

```sql
-- SQL:1992 §6.7 引入了 TRIM 函数
TRIM([ [LEADING | TRAILING | BOTH] [trim_char] FROM ] string)

-- 4 种用法:
TRIM(string)                              -- 默认 BOTH ' '
TRIM(LEADING FROM string)                 -- 仅左侧空格
TRIM(TRAILING FROM string)                -- 仅右侧空格
TRIM(BOTH 'x' FROM string)                -- 两侧 'x'
TRIM(LEADING 'x' FROM string)             -- 左侧 'x'
TRIM(TRAILING 'x' FROM string)            -- 右侧 'x'

-- LTRIM / RTRIM 是简写, 但**不在 SQL 标准中**:
LTRIM(string)        -- = TRIM(LEADING FROM string)
RTRIM(string)        -- = TRIM(TRAILING FROM string)
LTRIM(string, chars) -- 各引擎扩展
RTRIM(string, chars) -- 各引擎扩展
```

### 跨引擎 TRIM 行为对比

| 引擎 | `TRIM('abc')` | `TRIM(' abc ')` | `TRIM('x' FROM 'xxabcxx')` | `LTRIM('  abc')` | `RTRIM('abc  ')` | 多字符修剪 |
|------|--------------|-----------------|---------------------------|------------------|------------------|----------|
| PostgreSQL | 'abc' | 'abc' | 'abc' | 'abc' | 'abc' | `TRIM('xy' FROM 'xyabcxy')` |
| MySQL | 'abc' | 'abc' | 'abc' (8.0+) | 'abc' | 'abc' | `LTRIM('xy', 'abc')` 不支持单字符外的多字符 |
| MariaDB | 'abc' | 'abc' | 'abc' | 'abc' | 'abc' | 类似 MySQL |
| Oracle | 'abc' | 'abc' | 'abc' | 'abc' | 'abc' | TRIM 仅单字符；LTRIM/RTRIM 支持多字符集 |
| SQL Server | 'abc' (2017+) | 'abc' (2017+) | 'abc' (2022+) | 'abc' | 'abc' | TRIM 多字符 (2022+) |
| SQLite | 'abc' | 'abc' | 'abc' | 'abc' | 'abc' | LTRIM/RTRIM 第二参数为字符集 |
| DB2 | 'abc' | 'abc' | 'abc' | 'abc' | 'abc' | 单字符 |
| Snowflake | 'abc' | 'abc' | 'abc' | 'abc' | 'abc' | LTRIM/RTRIM 字符集 |
| BigQuery | 'abc' | 'abc' | 'abc' | 'abc' | 'abc' | TRIM(string, chars) 字符集 |
| Redshift | 'abc' | 'abc' | 'abc' | 'abc' | 'abc' | 字符集 |
| ClickHouse | 'abc' | 'abc' | -- (TRIM 仅剥空格) | 'abc' | 'abc' | 用 replaceRegexpAll |
| Trino | 'abc' | 'abc' | 'abc' | 'abc' | 'abc' | 字符集 (Trino 333+) |
| Spark SQL | 'abc' | 'abc' | 'abc' | 'abc' | 'abc' | 字符集 |

#### TRIM 函数差异点

```sql
-- 1) TRIM 修剪字符: 单字符 vs 字符集
-- PostgreSQL: TRIM 接受字符集 (字符串中任一字符都被修剪)
SELECT TRIM('xy' FROM 'xyzabcxyz');   -- 'zabcxyz' 不对!
-- 实际 PG: 修剪所有出现在 'xy' 中的字符
SELECT TRIM('xy' FROM 'xxyyabcxyx');  -- 'abc'

-- Oracle: TRIM 只接受单字符 (字符串字面量长度必须为 1)
SELECT TRIM('x' FROM 'xxabcxx') FROM dual;  -- 'abc'
SELECT TRIM('xy' FROM 'xxabcxx') FROM dual;  -- ORA-30001

-- 2) LTRIM / RTRIM 第二参数语义
-- PostgreSQL / Oracle: 字符集
SELECT LTRIM('xyzabc', 'xyz');   -- 'abc'  (剥离任一 x/y/z)
SELECT RTRIM('abcxyz', 'xyz');   -- 'abc'

-- MySQL 8.0+ TRIM: 字符串而非字符集 (与 PG 不同!)
-- 但 LTRIM / RTRIM 仅修剪空格 (无第二参数)
SELECT LTRIM('  abc');           -- 'abc'
SELECT LTRIM('abc', 'x');        -- 错误 (MySQL LTRIM 无第二参数)

-- 3) ClickHouse TRIM 限制
-- TRIM(BOTH/LEADING/TRAILING ...) 仅去除空格
SELECT TRIM(BOTH FROM '  abc  ');                -- 'abc'
SELECT TRIM(LEADING 'x' FROM 'xxabc');           -- 错误! ClickHouse 不支持自定义字符
SELECT trimLeft('xxabc');                         -- 用 trimLeft 函数
SELECT replaceRegexpAll('xxabc', '^x+', '');     -- 通用方法
```

### TRIM 与 PAD SPACE 的微妙交互

```sql
-- PostgreSQL: CHAR 列上 TRIM 是否影响比较?
CREATE TABLE t (c CHAR(10));
INSERT INTO t VALUES ('abc');

SELECT c, length(c), length(TRIM(c)), length(RTRIM(c)) FROM t;
-- 'abc       ', 10, 3, 3

-- 但比较: 因为 PAD SPACE, TRIM 与否结果一样
SELECT * FROM t WHERE c = 'abc';           -- 命中 (PAD SPACE)
SELECT * FROM t WHERE TRIM(c) = 'abc';     -- 命中 (TRIM 后 NO PAD 也成立)
SELECT * FROM t WHERE c = TRIM(c);         -- 命中? 取决于跨类型比较

-- 实际 PG 实现: c (CHAR) 与 TRIM(c) (TEXT) 比较时, c 先转 TEXT 保留空格
-- 因此 'abc       ' = 'abc' -> FALSE!
SELECT 'abc       '::TEXT = 'abc';   -- FALSE
SELECT 'abc       '::CHAR(10) = 'abc';   -- TRUE (CHAR PAD SPACE)
```

### 为什么 TRIM 是 SQL 标准而 LTRIM / RTRIM 不是？

SQL:1992 决定将 TRIM 设计为函数（带语法关键字 LEADING/TRAILING/BOTH/FROM），是因为：
1. 简化标准：一个函数处理所有用例
2. 自然语言：`TRIM(LEADING ' ' FROM x)` 比 `LTRIM(x)` 更自描述
3. 避免函数命名冲突：LTRIM/RTRIM 名字与某些方言冲突

但实际工程中 LTRIM / RTRIM 短小好记，几乎所有引擎都同时支持。SQL Server 在 2017 才补全 SQL 标准 TRIM 函数（之前只有 LTRIM / RTRIM）。

## PAD SPACE / NO PAD 排序规则属性 (SQL:1992)

### 标准定义

```sql
-- SQL:1992 §4.2.4 / §11.32 排序规则定义即包含:
CREATE COLLATION my_collation
    FROM "ucs_basic"
    [ PAD SPACE | NO PAD ]
    [ NO CASE_SENSITIVITY | CASE_SENSITIVITY ]
    [ NO ACCENT_SENSITIVITY | ACCENT_SENSITIVITY ];

-- 默认: PAD SPACE (SQL:1992 字符比较默认)
-- NO PAD: 比较时不填充 (SQL:1992 起即可在 collation 中显式声明)
```

### 主要引擎对 SQL:1992 排序规则属性的支持

| 引擎 | 排序规则系统 | NO PAD 支持 | 默认 PAD 行为 | 设置方式 |
|------|------------|------------|--------------|---------|
| PostgreSQL | ICU + libc | 是 (16+) | 取决于 collation | `CREATE COLLATION ... DETERMINISTIC` |
| MySQL | 内置完整系统 | 是 (8.0+) | NO PAD (utf8mb4_0900_ai_ci) | `_pad` / `_nopad` 后缀 |
| MariaDB | 内置 | 是 | 默认 PAD SPACE | `utf8mb4_uca1400` 系列 NO PAD |
| Oracle | NLS | 是 | NLS_COMP/NLS_SORT | NLS_COMP=LINGUISTIC |
| SQL Server | 系统 collation | 是 (BINARY 隐含 NO PAD) | PAD SPACE | `Latin1_General_BIN` |
| DB2 | locale + collation | 是 | PAD SPACE | UCA collation |
| Snowflake | 简化 collation | -- (CHAR≡VARCHAR) | NO PAD | `COLLATE 'en-ci'` |
| BigQuery | -- | -- | NO PAD | 无 collation 系统 |
| ClickHouse | -- | -- | 字节比较 | `String` 默认字节, `lowerUTF8` 函数 |
| Spark SQL | 3.4+ 引入 | 是 | NO PAD | `COLLATE` 关键字 |
| DuckDB | 简化 | -- | NO PAD | `COLLATE` 仅大小写 |

### MySQL 8.0 排序规则 PAD 属性详解

```sql
-- 查询 collation 的 PAD 属性
SELECT collation_name, pad_attribute
FROM information_schema.collations
WHERE character_set_name = 'utf8mb4'
ORDER BY collation_name
LIMIT 10;

-- 关键发现:
-- utf8mb4_0900_ai_ci    NO PAD     (8.0 默认, ai = accent-insensitive, ci = case-insensitive)
-- utf8mb4_0900_as_cs    NO PAD     (as = accent-sensitive, cs = case-sensitive)
-- utf8mb4_general_ci    PAD SPACE  (5.7 老默认, 兼容性保留)
-- utf8mb4_unicode_ci    PAD SPACE  (UCA-4.0)
-- utf8mb4_unicode_520_ci PAD SPACE (UCA-5.2)
-- utf8mb4_bin           PAD SPACE  (字节级)

-- 实战影响:
SET NAMES utf8mb4 COLLATE utf8mb4_0900_ai_ci;
SELECT 'abc' = 'abc   ';   -- 0 (FALSE, NO PAD)

SET NAMES utf8mb4 COLLATE utf8mb4_general_ci;
SELECT 'abc' = 'abc   ';   -- 1 (TRUE, PAD SPACE)

-- 8.4+ 新增:
-- utf8mb4_0900_bin       NO PAD (二进制 + NO PAD)
```

### PostgreSQL 16+ 的 NO PAD 支持

```sql
-- PostgreSQL 16+ 引入 deterministic NO PAD collation
CREATE COLLATION my_no_pad (
    provider = icu,
    locale = 'en-US',
    deterministic = false   -- 启用 NO PAD 等高级特性
);

-- 旧版 PG (< 16): CHAR 隐含 PAD SPACE, VARCHAR 隐含 NO PAD, 不可改
-- 新版 PG (16+): 通过 collation 灵活配置
```

## MySQL 5.0.3 CHAR / VARCHAR 行为变更

MySQL 5.0.3 (2005-03-23 发布) 是字符串类型语义的分水岭。在此之前：

```
旧行为 (MySQL 4.x / 5.0.0 - 5.0.2):
  1. VARCHAR(n) 的 n 上限为 255 字符 (一字节长度前缀)
  2. VARCHAR 列存入字符串时, 末尾空格被剥离 (非标准!)
  3. CHAR(n) 行为符合标准 (右补空格存储)

新行为 (MySQL 5.0.3+):
  1. VARCHAR(n) 上限提升至 65535 字节 (两字节长度前缀, 取决于行格式)
  2. VARCHAR 列严格保留尾空格 (与 SQL 标准一致)
  3. CHAR(n) 行为继续符合标准
```

### 升级影响

```sql
-- 旧表 (5.0.2 及以下) 使用 VARCHAR(10) 存 'abc   ' 实际存为 'abc'
-- 升级到 5.0.3 后, 现有数据不变, 但新插入会保留尾空格
-- 这意味着同一表内可能出现 "看起来一样但实际不一样" 的数据

-- 检查升级影响:
SELECT name, LENGTH(name) FROM old_table
WHERE LENGTH(name) != LENGTH(TRIM(TRAILING ' ' FROM name));
-- 含尾空格的行 = 升级后插入的

-- 修复 (一次性清理):
UPDATE old_table SET name = TRIM(TRAILING ' ' FROM name);
```

### 5.0.3 之后的新陷阱

```sql
-- 陷阱 1: 应用代码假设"VARCHAR 不带尾空格"失效
-- 旧代码:
INSERT INTO users (name) VALUES ('john   ');
SELECT name FROM users WHERE name = 'john';
-- MySQL 4.x: 命中 (尾空格被剥)
-- MySQL 5.0.3+: 取决于 collation
--   PAD SPACE: 命中
--   NO PAD: 不命中!

-- 陷阱 2: 索引唯一性检查变化
CREATE TABLE u (name VARCHAR(50) UNIQUE);
INSERT INTO u VALUES ('alice');
INSERT INTO u VALUES ('alice  ');
-- MySQL 4.x: 第二条因 'alice' 重复而失败 (尾空格剥离)
-- MySQL 5.0.3+ + utf8mb4_0900_ai_ci (NO PAD): 两条都成功!
--   但 5.0.3+ + utf8mb4_general_ci (PAD SPACE): 第二条失败
```

### 5.0.3 变更的官方说明

MySQL 文档 5.0.3 release note:
> "The handling of trailing spaces in VARCHAR columns has been changed to conform to SQL-standard behavior. Trailing spaces are now retained on storage and retrieval, rather than stripped."

这一变更让 MySQL 的 VARCHAR 与 SQL:1992 标准完全一致（仅在存储与检索维度），但比较语义仍取决于 collation。

## SQL Server ANSI_PADDING 历史与默认值

### ANSI_PADDING 简史

```
SQL Server 6.5 (1996): 引入 ANSI_PADDING, 默认 OFF (兼容 Sybase)
SQL Server 7.0 (1998): 默认仍 OFF
SQL Server 2000 (2000): 默认 ON (符合 ANSI 标准)
SQL Server 2005+: 默认 ON, OFF 选项被标记 deprecated
SQL Server 2022: ANSI_PADDING OFF 仍受支持但不推荐
```

### ANSI_PADDING ON / OFF 行为对比

```sql
-- ANSI_PADDING ON (现代默认):
SET ANSI_PADDING ON;
CREATE TABLE t_on (c CHAR(10), v VARCHAR(10), b BINARY(10), vb VARBINARY(10));
INSERT INTO t_on VALUES ('abc', 'abc   ', 0xFF, 0xFF);
SELECT DATALENGTH(c), DATALENGTH(v), DATALENGTH(b), DATALENGTH(vb) FROM t_on;
-- 10, 6, 10, 1

-- ANSI_PADDING OFF (历史/已废弃):
SET ANSI_PADDING OFF;
CREATE TABLE t_off (c CHAR(10), v VARCHAR(10), b BINARY(10), vb VARBINARY(10));
INSERT INTO t_off VALUES ('abc', 'abc   ', 0xFF, 0xFF);
SELECT DATALENGTH(c), DATALENGTH(v), DATALENGTH(b), DATALENGTH(vb) FROM t_off;
-- 3, 3, 1, 1   -- CHAR 不补, VARCHAR 剥, BINARY 不补
```

### ANSI_PADDING 的列级烙印

`SET ANSI_PADDING` 的关键特性是**只在 CREATE/ALTER TABLE 时生效**：列一旦创建，其填充行为就被固化在 catalog 中，后续会话切换 ANSI_PADDING 设置都不会改变现有列的行为。

```sql
-- 演示:
SET ANSI_PADDING ON;
CREATE TABLE mixed (c1 CHAR(10));   -- c1 列固化为 PAD ON

SET ANSI_PADDING OFF;
ALTER TABLE mixed ADD c2 CHAR(10);  -- c2 列固化为 PAD OFF

-- 同一表的两列行为不同!
INSERT INTO mixed VALUES ('abc', 'abc');
SELECT DATALENGTH(c1), DATALENGTH(c2) FROM mixed;
-- 10, 3   -- c1 补空格, c2 不补
```

这种"建表时锁定"的设计是 SQL Server 与其他引擎最大的区别。其他引擎要么全局固定 (PG, Oracle)，要么允许会话级覆盖 (MySQL collation)，但都不会让同一表的两列采用不同填充策略。

### ANSI_PADDING 与连接驱动的交互

各种 SQL Server 客户端驱动（ODBC, OLE DB, .NET SqlClient）默认在连接时执行 `SET ANSI_PADDING ON`：

```csharp
// .NET SqlClient: 默认 ANSI_PADDING ON
using var conn = new SqlConnection(connStr);
conn.Open();
// 已自动执行: SET ANSI_NULLS ON; SET ANSI_PADDING ON; ...
```

但如果应用直接通过 TDS 协议发送 SQL，需要手动设置。这是一个隐蔽的"客户端不同导致行为不同"的陷阱。

## LIKE 模式匹配中的填充行为

LIKE 不受 PAD SPACE 影响——这是所有引擎的共识。

```sql
-- 所有引擎一致:
SELECT 'abc' LIKE 'abc';           -- TRUE
SELECT 'abc' LIKE 'abc   ';        -- FALSE  (LIKE 严格)
SELECT 'abc   ' LIKE 'abc';        -- FALSE
SELECT 'abc   ' LIKE 'abc%';       -- TRUE   (% 匹配空格)
SELECT 'abc   ' LIKE 'abc   ';     -- TRUE
```

### CHAR 列上 LIKE 的"幽灵空格"陷阱

```sql
-- PostgreSQL CHAR(10):
CREATE TABLE t (c CHAR(10));
INSERT INTO t VALUES ('abc');     -- 实际存储 'abc       '

-- LIKE 与等号行为不一致!
SELECT * FROM t WHERE c = 'abc';        -- 命中 (PAD SPACE)
SELECT * FROM t WHERE c LIKE 'abc';     -- 不命中! (LIKE 不 PAD)
SELECT * FROM t WHERE c LIKE 'abc%';    -- 命中

-- 解决: 显式 trim
SELECT * FROM t WHERE TRIM(c) LIKE 'abc';   -- 命中
```

这是 CHAR 列上最常见的应用层 Bug：以为等号匹配就够了，结果切换到 LIKE 时全部失效。

## 字符串拼接与填充传染

### CHAR 列参与拼接的"空格污染"

```sql
-- PostgreSQL:
CREATE TABLE t (c CHAR(5), v VARCHAR(5));
INSERT INTO t VALUES ('abc', 'abc');

SELECT '|' || c || '|', '|' || v || '|' FROM t;
-- '|abc  |', '|abc|'
-- CHAR 列拼接时尾空格被一同拼入

SELECT '|' || c || '|' = '|abc|' FROM t;
-- 实际: '|abc  |' = '|abc|'
-- 取决于隐式类型: 通常 FALSE (TEXT 比较 NO PAD)

-- 但若用 CHAR 字面:
SELECT '|' || c || '|' = '|abc|'::CHAR(5);
-- 取决于具体类型推断, 一般 FALSE
```

### Oracle 的 || 与隐式类型

```sql
-- Oracle: 拼接 CHAR 时空格也会进入结果
SELECT '|' || c || '|' FROM t;
-- 'abc       ' 拼接后: '|abc       |'

-- 实际工程中常需要 RTRIM
SELECT '|' || RTRIM(c) || '|' FROM t;
-- '|abc|'
```

## 性能与索引的影响

### CHAR 索引的额外存储开销

```
CHAR(10) UTF-8 索引存储:
  每行索引键: 10 字符 * (最多 4 字节 / 字符) = 40 字节 (理论上限)
  实际 ASCII 数据: 10 字节固定

VARCHAR(10) UTF-8 索引存储:
  每行索引键: 实际长度 + 长度前缀 (1-2 字节)
  ASCII 'abc': 4 字节 (3 + 1)
  
索引大小比例 (1 亿行 ASCII 'abc'):
  CHAR(10):    10 * 100M = 1 GB (固定)
  VARCHAR(10): 4 * 100M  = 400 MB
  比例: CHAR 索引大 2.5 倍
```

### B-tree 比较函数的开销

```
PAD SPACE 比较:
  1) 比较前 min(len_a, len_b) 字符
  2) 长度不等时, 较短者隐式补空格继续比较
  3) 实际实现: 末尾空格批量跳过

NO PAD 比较:
  1) 长度不等直接返回不等
  2) 长度等才逐字符比较
  
PAD SPACE 比 NO PAD 略慢, 但在现代 CPU 上差异 < 5%
```

### 哈希分区与填充

```sql
-- PG: CHAR 与 VARCHAR 哈希值不同 (类型不同)
SELECT hashtext('abc'::CHAR(10));        -- 假设 H1
SELECT hashtext('abc       '::CHAR(10)); -- H1 (PAD SPACE 视为同值)
SELECT hashtext('abc'::VARCHAR(10));     -- H2 ≠ H1
SELECT hashtext('abc       '::VARCHAR(10)); -- H3 ≠ H1, H2 (NO PAD)

-- 这意味着将 CHAR 列改为 VARCHAR 后, 哈希分区结果完全改变
-- 数据迁移时需重新计算分区
```

## 工程实战建议

### 1) 默认避免 CHAR(n)，除非真有定长需求

```
适用 CHAR(n) 的场景:
  1. 国家代码、币种代码等真正定长 (CHAR(2), CHAR(3))
  2. 哈希值 (CHAR(64) for SHA-256 hex)
  3. UUID 字符串表示 (CHAR(36) for hyphen format)
  4. 银行账号、身份证号等业务定长

不适用 CHAR(n) 的场景:
  1. 任何长度可变的字段 (姓名, 地址, 描述, 标签)
  2. 跨数据库迁移频繁的场景 (CHAR 语义差异最大)
  3. 与应用层程序员协作的字段 (空格语义难解释)
  4. 需要 LIKE 模式匹配的字段
```

### 2) 始终明确 trim 策略

```sql
-- 应用层规范:
-- 1) 写入前: 应用层 trim, 而非依赖数据库
-- 2) 读取时: 显式 RTRIM, 而非假设引擎行为

-- 写入示例:
INSERT INTO users (name) VALUES (RTRIM(?));
-- 或在应用层: name = name.strip()

-- 读取示例:
SELECT RTRIM(name) AS name FROM users;
-- 或: SELECT TRIM(TRAILING FROM name) FROM users;
```

### 3) JOIN 字段类型对齐

```sql
-- 反模式: CHAR 与 VARCHAR 跨表 JOIN
SELECT * FROM orders o JOIN customers c
  ON o.customer_code = c.code;
-- 若 o.customer_code 是 CHAR(10), c.code 是 VARCHAR(10)
-- 匹配可能因 PAD 行为差异而失败

-- 推荐: 显式类型转换或 trim
SELECT * FROM orders o JOIN customers c
  ON RTRIM(o.customer_code) = RTRIM(c.code);

-- 或建表时统一为 VARCHAR
ALTER TABLE orders ALTER COLUMN customer_code TYPE VARCHAR(10);
```

### 4) 跨方言迁移前先检测尾空格

```sql
-- 检测含尾空格的行 (任意方言通用):
SELECT col, LENGTH(col), LENGTH(RTRIM(col)) AS trimmed_len
FROM tbl
WHERE LENGTH(col) > LENGTH(RTRIM(col));

-- 修复 (迁移前):
UPDATE tbl SET col = RTRIM(col) WHERE col != RTRIM(col);
```

### 5) 测试策略：包含填充边界用例

```sql
-- 单元测试必备样本:
-- 1) 空字符串
INSERT INTO t (c) VALUES ('');           -- CHAR(10) 实际存 '          '
-- 2) 只有空格
INSERT INTO t (c) VALUES ('   ');        -- 全空格
-- 3) 尾空格
INSERT INTO t (c) VALUES ('abc   ');     -- 含尾空格
-- 4) 非 ASCII 空格 (注意 NBSP \xa0 不是 ASCII 空格)
INSERT INTO t (c) VALUES ('abc' || CHR(160));   -- 含 NBSP

-- 验证:
SELECT * FROM t WHERE c = '';            -- 是否命中?
SELECT * FROM t WHERE c = '   ';
SELECT * FROM t WHERE c = 'abc';
SELECT * FROM t WHERE c LIKE 'abc';
SELECT * FROM t WHERE TRIM(c) = '';
```

## 关键发现

1. **45+ 引擎中只有 9 个完全没有 CHAR 类型或将 CHAR 退化为 VARCHAR**：Snowflake、DuckDB、BigQuery、ClickHouse (用 String/FixedString)、CrateDB、QuestDB、Spanner、DatabendDB、Firebolt。这意味着**约 80% 的引擎仍保留传统 CHAR(n) 填充语义**。

2. **VARCHAR PAD SPACE 是少数派**：只有 SQL Server / Azure Synapse / Sybase 系 / MySQL 5.7 默认 collation / TiDB/OceanBase MySQL 模式让 VARCHAR 比较时也 PAD SPACE。其他主流引擎 (PG, Oracle, DB2, Snowflake, BQ, etc.) 一致使用 NO PAD。

3. **MySQL 8.0 的 NO PAD 转向是重大变化**：从 5.7 默认 `utf8mb4_general_ci` (PAD SPACE) 改为 8.0 `utf8mb4_0900_ai_ci` (NO PAD)，这是大版本升级的隐性兼容风险。从 5.7 升 8.0 时，依赖尾空格匹配的 WHERE / JOIN / UNIQUE 约束都可能行为变化。

4. **SQL Server 的 ANSI_PADDING 是列级烙印**：SET 语句仅影响后续 CREATE/ALTER TABLE 时的列定义，已存在的列固化在 catalog。这导致同一表的两列可能采用不同填充策略，是 SQL Server 独有的复杂性。

5. **MySQL 5.0.3 是 VARCHAR 标准化的分水岭**：之前剥离尾空格 (非标准)，之后保留。20 年后的今天，仍可能在升级 4.x 数据库时遇到这个历史包袱。

6. **LIKE 不 PAD 是所有引擎的共识**：但 CHAR 列上 LIKE 的"幽灵空格"陷阱会让等号查询命中而 LIKE 失败。CHAR 列上做 LIKE 必须先 RTRIM。

7. **SQL:1992 NO PAD 选项仍是少数引擎实现**：尽管 SQL:1992 即已定义此 collation 属性，仅 PG 16+、MySQL 8.0+、MariaDB 10.10+ (uca1400)、Spark 3.4+ 等少数主流引擎完整实现。SQL Server 至今未提供原生 NO PAD VARCHAR。

8. **TRIM 标准 vs LTRIM/RTRIM 简写**：SQL 标准只定义 TRIM；LTRIM/RTRIM 是事实标准但语义在跨引擎间不完全一致 (单字符 vs 字符集)。Firebird/Flink SQL 不提供 LTRIM/RTRIM 简写。

9. **ClickHouse FixedString 用 \0 而非空格填充**：与所有 SQL 引擎不同，FixedString 设计用于固定字节长度数据 (IP/UUID/Hash)，绝非 CHAR 替代品。从传统数据库迁移到 ClickHouse 时，CHAR 类型应映射为 String 而非 FixedString。

10. **CHAR 索引存储开销显著**：UTF-8 编码下，CHAR(n) 索引占用上限是 VARCHAR(n) 的数倍（取决于实际数据长度）。对索引性能敏感的大表，CHAR 是反模式。

11. **跨类型比较通常退化为 NO PAD**：CHAR 与 VARCHAR 混合比较时，多数引擎会将 CHAR 隐式转 VARCHAR/TEXT，导致 PAD SPACE 失效。在跨表 JOIN / UNION 时尤需注意。

12. **PostgreSQL CHAR 是"不推荐使用"的官方立场**：PG 文档明确说 CHAR 没有性能优势，反而最慢，这一立场 20 年未变。新建 PG 数据库基本不应使用 CHAR(n)。

13. **Snowflake 的 CHAR ≡ VARCHAR 是云数仓共识**：BigQuery、Snowflake、DuckDB、DatabendDB、Firebolt 等云原生引擎共同选择废弃 CHAR(n) 的填充语义。从 OLTP 迁移到这些云数仓时，CHAR 列上的尾空格匹配逻辑需重写。

14. **OLAP 引擎间 PAD SPACE 实现一致性高**：Trino、Vertica、Redshift、Greenplum、Teradata、SAP HANA 等传统 MPP 数据仓库严格遵循 SQL 标准 PAD SPACE CHAR / NO PAD VARCHAR。这是它们继承自 OLTP 时代的兼容遗产。

15. **TRIM(BOTH 'x' FROM s) 在不同引擎语义不同**：PostgreSQL 中 'x' 是字符集 (任一字符都修剪)；Oracle 中 'x' 必须为单字符；SQL Server 2022+ 中 'x' 是字符串。跨引擎迁移 TRIM 表达式时需逐个核对。

## 参考资料

- SQL:1992 标准: ISO/IEC 9075:1992, §4.2 (character string types, including §4.2.4 collation pad attribute), §6.7 (TRIM function), §8.2 (comparison predicate), §11.32 (collation definition with PAD SPACE / NO PAD attribute)
- SQL:2003 标准: ISO/IEC 9075-2:2003 (refinements to collation/Unicode handling)
- PostgreSQL: [Character Types (CHARACTER, CHARACTER VARYING)](https://www.postgresql.org/docs/current/datatype-character.html)
- MySQL: [Char and Varchar Types](https://dev.mysql.com/doc/refman/8.0/en/char.html) and [Trailing Spaces in CHAR/VARCHAR](https://dev.mysql.com/doc/refman/8.0/en/charset-collation-pad-attribute.html)
- MySQL Release Notes 5.0.3: [Changes in MySQL 5.0.3](https://dev.mysql.com/doc/refman/5.0/en/news-5-0-3.html)
- MariaDB: [VARCHAR](https://mariadb.com/kb/en/varchar/) and [collations](https://mariadb.com/kb/en/data-type-character-sets-and-collations/)
- SQL Server: [SET ANSI_PADDING](https://learn.microsoft.com/en-us/sql/t-sql/statements/set-ansi-padding-transact-sql) and [char and varchar](https://learn.microsoft.com/en-us/sql/t-sql/data-types/char-and-varchar-transact-sql)
- Oracle: [Data Types - CHAR / VARCHAR2 / NCHAR](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Data-Types.html) and [Blank-Padded Comparison Semantics](https://docs.oracle.com/en/database/oracle/oracle-database/19/lnpls/static-sql.html)
- DB2: [String Comparisons](https://www.ibm.com/docs/en/db2/11.5?topic=expressions-string-comparisons)
- SQLite: [Datatypes In SQLite](https://www.sqlite.org/datatype3.html)
- Snowflake: [Data Types: String & Binary](https://docs.snowflake.com/en/sql-reference/data-types-text)
- BigQuery: [Data Types: String](https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types#string_type)
- ClickHouse: [String / FixedString](https://clickhouse.com/docs/en/sql-reference/data-types/fixedstring)
- Trino: [CHAR](https://trino.io/docs/current/language/types.html#char)
- Spark SQL: [CHAR / VARCHAR](https://spark.apache.org/docs/latest/sql-ref-datatypes.html) and [legacy.charVarcharAsString](https://spark.apache.org/docs/latest/configuration.html)
- DuckDB: [VARCHAR](https://duckdb.org/docs/sql/data_types/text)
- ISO Working Group documents: SQL/Foundation Edits to PAD SPACE / NO PAD (ISO/IEC JTC 1/SC 32/WG 3 N-series)
