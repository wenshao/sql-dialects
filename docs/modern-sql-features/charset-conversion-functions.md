# 字符集转换函数 (Character Set Conversion Functions)

把 GBK 的订单数据迁移到 UTF-8 仓库，把 Latin1 的历史日志合并进 utf8mb4 的现代表，把 Shift_JIS 的供应商接口转成 UTF-16——字符集转换是数据集成、跨境业务和遗留系统改造中绕不开的硬骨头。本文聚焦**显式字符集转换函数**（`CONVERT` / `CAST AS CHARACTER SET` / `CONVERT_FROM` / `ENCODE` 等），与侧重排序规则的 [charset-collation.md](./charset-collation.md) 和侧重比较语义的 [string-comparison-collation.md](./string-comparison-collation.md) 互为补充。

## 为什么显式字符集转换很重要

字符集（character set / encoding）决定了字节序列如何解释为字符；排序规则（collation）决定了字符如何比较。当两个系统使用不同字符集时，"直接拷贝字节" 的结果是乱码（mojibake），而 "依赖隐式转换" 的结果取决于客户端、连接、服务器三层的默认值，几乎不可预测。显式转换函数让开发者**精确控制**字节到字符的映射，是以下场景的必备工具：

1. **数据迁移**：从 Oracle WE8MSWIN1252 迁到 PostgreSQL UTF8，或从 MySQL latin1 升级到 utf8mb4
2. **混合本地化**：同一张表里既有简体中文（GB18030）又有日文（Shift_JIS）来源
3. **二进制数据互操作**：把 BLOB 中存储的 UTF-16 字节解码为可读字符串
4. **协议适配**：HTTP 表单、邮件 MIME、CSV 文件常自带编码声明
5. **乱码修复**：把"被双重编码"的字符串还原（latin1→utf8→latin1 解释为 utf8）
6. **Unicode 转义**：从 `\u00e9` 这种 ASCII 安全的转义序列还原为真实字符
7. **加密 / 哈希前的标准化**：保证不同系统计算同一字符串得到同一摘要

## SQL 标准定义

SQL:1999（ISO/IEC 9075-2, Section 6.22 ⟨cast specification⟩）首次为字符集转换提供了语法基础：

```sql
CAST ( <value_expression> AS <character_string_type>
       [ CHARACTER SET <character_set_specification> ]
       [ COLLATE <collation_name> ] )
```

`INFORMATION_SCHEMA.CHARACTER_SETS` 视图（SQL:1999 Schemata，Section 5.10）暴露引擎支持的字符集列表，列包括 `CHARACTER_SET_CATALOG`、`CHARACTER_SET_SCHEMA`、`CHARACTER_SET_NAME`、`CHARACTER_REPERTOIRE`、`FORM_OF_USE`、`DEFAULT_COLLATE_*`。

SQL:2003 进一步细化：

- 字符串字面量可前缀字符集名：`_UTF8'résumé'` 或 `N'résumé'`（`N` 表示 NATIONAL CHARACTER SET）
- `CONVERT` 在 SQL/MED 与 SQL/PSM 中作为可选词出现，但 SQL:1999 定义的 `CONVERT` 实际指的是**字符串到字符串的转换函数**（与下面的方言函数同名但语义不同）
- `TRANSLATE` 子句（不是 Oracle 的字符替换函数）原本就用于字符集转换：`TRANSLATE(<string> USING <transliteration_name>)`

标准的关键概念：**form-of-use conversion** 把字符从一种编码（form）转到另一种，**字符仓库（repertoire）**保持不变；**transliteration** 则可以改变字符仓库（例如把希腊字母转写成拉丁字母）。绝大多数引擎只实现了 form-of-use（编码转换），transliteration 几乎没有实现。

实际遵守 SQL:1999 `CAST ... AS CHARACTER SET` 语法的引擎屈指可数：MySQL/MariaDB 部分实现，DB2 LUW 实现完整，其他都依赖方言函数。

## 支持矩阵

### 1. CONVERT() 函数（字符集形式）

注意 `CONVERT` 是 SQL 中最歧义的函数名之一：MySQL 用它做字符集转换，SQL Server 用它做类型转换 + 格式化，PostgreSQL 用它在 bytea 与 text 之间转换编码，Oracle 用它做字符集转换。下表只统计**字符集 / 编码转换**用法。

| 引擎 | 关键字 | 语法形式 | 输入类型 | 版本 |
|------|--------|---------|---------|------|
| PostgreSQL | `convert` | `convert(bytea, src, dest)` | bytea→bytea | 7.2+ |
| MySQL | `CONVERT` | `CONVERT(str USING charset)` | char→char | 4.1+ |
| MariaDB | `CONVERT` | `CONVERT(str USING charset)` | char→char | 5.1+ |
| SQLite | -- | -- | -- | 不支持（始终 UTF-8） |
| Oracle | `CONVERT` | `CONVERT(char, dest, src)` | char→char | 8i+ |
| SQL Server | `CONVERT` | `CONVERT(varchar, expr)` + COLLATE | 类型转换 | 早期 |
| DB2 | `VARCHAR` / `GRAPHIC` | `VARCHAR(expr, n, codeunits16)` | 类型 + 编码 | 9.5+ |
| Snowflake | -- | 无字符集概念，统一 UTF-8 | -- | -- |
| BigQuery | -- | 统一 UTF-8 | -- | -- |
| Redshift | -- | 统一 UTF-8（VARCHAR 按字节计） | -- | -- |
| DuckDB | -- | 统一 UTF-8 | -- | -- |
| ClickHouse | `convertCharset` | `convertCharset(s, from, to)` | str→str | 20.1+ |
| Trino | `from_utf8` / `to_utf8` | `from_utf8(varbinary)` | bin↔str | 早期 |
| Presto | `from_utf8` / `to_utf8` | 同 Trino | bin↔str | 早期 |
| Spark SQL | `decode` / `encode` | `decode(binary, charset)` | bin↔str | 1.5+ |
| Hive | `decode` / `encode` | `decode(binary, charset)` | bin↔str | 0.12+ |
| Flink SQL | `DECODE` / `ENCODE` | 同 Spark | bin↔str | 1.10+ |
| Databricks | `decode` / `encode` | 继承 Spark | bin↔str | GA |
| Teradata | `TRANSLATE` | `TRANSLATE(str USING xxx_TO_yyy)` | char→char | V2R5+ |
| Greenplum | `convert` | 继承 PG | bytea→bytea | 继承 PG |
| CockroachDB | `convert_from`/`convert_to` | 兼容 PG | bytea↔text | 22.1+ |
| TiDB | `CONVERT` | 兼容 MySQL | char→char | 继承 MySQL |
| OceanBase | `CONVERT` | 兼容 MySQL | char→char | 早期 |
| YugabyteDB | `convert` | 继承 PG | bytea→bytea | 继承 PG |
| SingleStore | `CONVERT` | 兼容 MySQL | char→char | GA |
| Vertica | -- | UTF-8 单一字符集 | -- | -- |
| Impala | -- | UTF-8 单一字符集 | -- | -- |
| StarRocks | `convert` | `convert(s USING gbk)` | char→char | 2.5+ |
| Doris | `convert` | 同 StarRocks | char→char | 1.2+ |
| MonetDB | -- | UTF-8 单一字符集 | -- | -- |
| CrateDB | -- | UTF-8 单一字符集 | -- | -- |
| TimescaleDB | `convert` | 继承 PG | bytea→bytea | 继承 PG |
| QuestDB | -- | UTF-8 单一字符集 | -- | -- |
| Exasol | -- | UTF-8 单一字符集（V6+） | -- | -- |
| SAP HANA | -- | 内部统一 CESU-8 | -- | -- |
| Informix | `TO_CHAR` | NLS 转换通过会话变量 | -- | 11.7+ |
| Firebird | `_charset` 引介词 | `_WIN1252 'abc'` | 字面量 | 1.0+ |
| H2 | -- | -- | -- | 不支持 |
| HSQLDB | -- | -- | -- | 不支持 |
| Derby | -- | -- | -- | 不支持 |
| Amazon Athena | `from_utf8`/`to_utf8` | 继承 Trino | bin↔str | GA |
| Azure Synapse | `CONVERT` | 同 SQL Server | 类型 | GA |
| Google Spanner | -- | 统一 UTF-8 | -- | -- |
| Materialize | `convert_from` | 继承 PG | bytea→text | GA |
| RisingWave | `convert_from` | 继承 PG | bytea→text | GA |
| InfluxDB (SQL) | -- | 统一 UTF-8 | -- | -- |
| DatabendDB | `from_utf8`/`to_utf8` | 类似 Trino | bin↔str | GA |
| Yellowbrick | `convert_from`/`convert_to` | 继承 PG | bytea↔text | GA |
| Firebolt | -- | 统一 UTF-8 | -- | -- |

> 统计：约 18 个引擎支持某种形式的显式字符集转换；约 19 个引擎采用"内部统一 UTF-8"策略，根本不需要转换函数；其余少数（H2/HSQLDB/Derby/SQLite）既无字符集概念也无转换函数。

### 2. CONVERT(expr USING charset_name) — MySQL 风格

这是 SQL:2003 `CONVERT(<string> USING <transcoding_name>)` 的方言实现。

| 引擎 | 支持 | 备注 |
|------|------|------|
| MySQL | 是 | `CONVERT('abc' USING utf8mb4)` |
| MariaDB | 是 | 同 MySQL |
| TiDB | 是 | 兼容 MySQL |
| OceanBase | 是 | 兼容 MySQL |
| SingleStore | 是 | 兼容 MySQL |
| StarRocks | 是 | 2.5+ 加入 |
| Doris | 是 | 1.2+ 加入 |
| 其他 | -- | 多数不识别 USING 子句 |

### 3. CAST(expr AS <type>) 携带字符集

| 引擎 | 支持 | 语法 |
|------|------|------|
| MySQL | 是 | `CAST(s AS CHAR CHARACTER SET utf8mb4)` |
| MariaDB | 是 | 同 MySQL |
| DB2 LUW | 是 | `CAST(s AS VARCHAR(10) CCSID 1208)` |
| TiDB | 部分 | 兼容 MySQL 子集 |
| OceanBase | 是 | 兼容 MySQL |
| SingleStore | 是 | 兼容 MySQL |
| Firebird | 是 | `CAST(s AS VARCHAR(10) CHARACTER SET WIN1252)` |
| PostgreSQL | -- | 不支持 CAST 携带字符集 |
| SQL Server | -- | 通过 `COLLATE` 子句 |
| Oracle | -- | NCHAR 类型隐含 NLS_NCHAR_CHARACTERSET |

### 4. CONVERT_FROM / CONVERT_TO（PostgreSQL 对偶）

`convert_from(bytes bytea, src_encoding text) → text`：把字节按 src 编码解码为数据库内部 UTF-8 字符串。
`convert_to(string text, dest_encoding text) → bytea`：把字符串按 dest 编码序列化为字节。

| 引擎 | convert_from | convert_to | convert (3-arg) |
|------|--------------|------------|-----------------|
| PostgreSQL | 是 | 是 | 是 |
| Greenplum | 是 | 是 | 是 |
| CockroachDB | 是 | 是 | -- |
| YugabyteDB | 是 | 是 | 是 |
| TimescaleDB | 是 | 是 | 是 |
| Materialize | 是 | 是 | -- |
| RisingWave | 是 | 是 | -- |
| Yellowbrick | 是 | 是 | 是 |
| 其他 | -- | -- | -- |

### 5. ENCODE / DECODE（base64 / hex / escape）

注意 PostgreSQL 的 `encode(bytea, format)` 与 Oracle 的 `DECODE(expr, ...)`（CASE 别名）完全不同。

| 引擎 | encode(bytes, fmt) | decode(str, fmt) | base64 | hex | escape | 备注 |
|------|---------------------|-------------------|--------|-----|--------|------|
| PostgreSQL | 是 | 是 | 是 | 是 | 是 | bytea↔text |
| MySQL | -- | -- | `TO_BASE64`/`HEX` | `HEX`/`UNHEX` | -- | 单独函数 |
| MariaDB | -- | -- | `TO_BASE64`/`FROM_BASE64` | `HEX`/`UNHEX` | -- | -- |
| SQLite | -- | -- | -- | `hex()` | -- | 仅 hex |
| Oracle | -- | -- | `UTL_ENCODE.BASE64_*` | `RAWTOHEX`/`HEXTORAW` | -- | DBMS 包 |
| SQL Server | -- | -- | XML PATH 技巧 | `CONVERT(varbinary)` | -- | 无原生 base64 |
| DB2 | -- | -- | `BASE64ENCODE`/`BASE64DECODE` | `HEX`/`HEX2BIN` | -- | LUW 11.5+ |
| Snowflake | -- | -- | `BASE64_ENCODE`/`BASE64_DECODE_*` | `HEX_ENCODE`/`HEX_DECODE_*` | -- | 完整 |
| BigQuery | -- | -- | `TO_BASE64`/`FROM_BASE64` | `TO_HEX`/`FROM_HEX` | -- | 完整 |
| Redshift | -- | -- | -- | -- | -- | 仅 `MD5`/`HEX` |
| DuckDB | `encode` | `decode` | `to_base64`/`from_base64` | `to_hex`/`from_hex` | 是 | 完整 |
| ClickHouse | -- | -- | `base64Encode`/`base64Decode` | `hex`/`unhex` | -- | 完整 |
| Trino | -- | -- | `to_base64`/`from_base64` | `to_hex`/`from_hex` | -- | 完整 |
| Presto | -- | -- | 同 Trino | 同 Trino | -- | 完整 |
| Spark SQL | `encode` | `decode` | `base64`/`unbase64` | `hex`/`unhex` | -- | 完整 |
| Hive | `encode` | `decode` | `base64`/`unbase64` | `hex`/`unhex` | -- | 完整 |
| Flink SQL | `ENCODE` | `DECODE` | `TO_BASE64`/`FROM_BASE64` | `HEX`/`UNHEX` | -- | 完整 |
| Databricks | `encode` | `decode` | `base64`/`unbase64` | `hex`/`unhex` | -- | 完整 |
| Teradata | -- | -- | `TO_BYTES`/`FROM_BYTES` | 同 | -- | 通过 TO_BYTES |
| CockroachDB | `encode` | `decode` | 是 | 是 | 是 | 兼容 PG |
| 其他 PG 派生 | 同 PG | 同 PG | 同 PG | 同 PG | 同 PG | -- |

### 6. TO_CHAR / TO_BYTES / RAWTOHEX 系列

主要是 Oracle / Teradata 的"字符 ↔ 字节"工具。

| 引擎 | TO_CHAR(bytes) | TO_BYTES | RAWTOHEX | UTL_RAW.CAST_TO_VARCHAR2 |
|------|----------------|----------|----------|--------------------------|
| Oracle | 是 | -- | 是 | 是 |
| Teradata | 是 | 是（base16/64/ASCII） | -- | -- |
| DB2 | `VARCHAR_BIT_FORMAT` | -- | `HEX` | -- |
| 其他 | -- | -- | -- | -- |

### 7. NCHAR 字面量语法（N'...'）

`N'...'` 在 SQL:1999 定义为 NATIONAL CHARACTER STRING LITERAL，使用引擎的 NATIONAL_CHARSET（通常 UTF-16/UCS2）。

| 引擎 | N'...' | NATIONAL CHARACTER 类型 | 默认 NCHAR 编码 |
|------|--------|--------------------------|------------------|
| SQL Server | 是 | NCHAR/NVARCHAR | UCS-2 / UTF-16 |
| Oracle | 是 | NCHAR/NVARCHAR2 | AL16UTF16 / UTF8 |
| DB2 | 是 | NCHAR/NVARCHAR | UTF-16 (1200) |
| MySQL | 是 | NCHAR | utf8 (3-byte) |
| MariaDB | 是 | NCHAR | utf8 |
| PostgreSQL | 是（解析忽略 N） | NCHAR=CHAR | 与 CHAR 相同 |
| SAP HANA | 是 | NCHAR/NVARCHAR | CESU-8 |
| Firebird | 是 | NCHAR | ISO8859_1 |
| Informix | 是 | NCHAR | NLS_LANG |
| 其他 | -- | -- | -- |

### 8. _charset 引介词（MySQL 风格 introducer）

| 引擎 | 引介词 | 示例 |
|------|--------|------|
| MySQL | 是 | `_utf8mb4'résumé'` |
| MariaDB | 是 | `_utf8mb4'résumé'` |
| TiDB | 是 | 兼容 MySQL |
| OceanBase | 是 | 兼容 MySQL |
| SingleStore | 是 | 兼容 MySQL |
| Firebird | 是 | `_WIN1252 'abc'` |
| StarRocks | 部分 | 解析但忽略 |
| Doris | 部分 | 同上 |
| 其他 | -- | -- |

### 9. TRANSLATE（USING transcoding 形式）

注意区别：`TRANSLATE(s, from_chars, to_chars)` 是 Oracle 风格的字符替换；`TRANSLATE(s USING name)` 才是 SQL 标准的字符集转换。

| 引擎 | TRANSLATE USING | 示例 |
|------|-----------------|------|
| DB2 LUW | 是 | `TRANSLATE(s USING ASCII_TO_EBCDIC)` |
| Teradata | 是 | `TRANSLATE(s USING UNICODE_TO_LATIN)` |
| Oracle | 是（变体） | `TRANSLATE(s USING NCHAR_CS)` / `USING CHAR_CS` |
| 其他 | -- | -- |

### 10. UNISTR / Unicode 字面量

| 引擎 | UNISTR | U&'...' (SQL 标准) | 转义示例 |
|------|--------|---------------------|---------|
| Oracle | 是 | -- | `UNISTR('\00e9')` |
| PostgreSQL | -- | 是 | `U&'d\0061t\+000061'` |
| DB2 | 是 | 是 | `UNISTR('\00e9')` |
| SQL Server | -- | -- | `NCHAR(0x00e9)` 替代 |
| MySQL | -- | -- | 通过 `_utf8mb4 X'...'` |
| Snowflake | -- | -- | `\u00e9` 在字符串中识别 |
| BigQuery | -- | -- | `\u00e9` 在字符串中识别 |
| ClickHouse | -- | -- | `\xe9\x82` 字节转义 |
| 其他 | -- | -- | -- |

## 主流引擎深度解析

### PostgreSQL：bytea↔text 的纯净分层

PostgreSQL 的字符集模型异常清晰：**整个数据库只有一个服务器编码**（initdb 时确定，通常 `UTF8`），所有 `text` / `varchar` 都是该编码下的字符串。所有"字符集转换"都发生在三个边界上：

1. **客户端连接**：`client_encoding` GUC，每条连接独立设置
2. **bytea ↔ text 显式函数**：`convert_from` / `convert_to` / `convert`
3. **COPY / 文件 I/O**：`COPY ... ENCODING 'GBK'`

```sql
-- 1) 把 bytea 中的 GBK 字节解码成数据库内部 UTF-8 文本
SELECT convert_from(E'\\xc4e3bac3', 'GBK');         -- 你好

-- 2) 把内部 UTF-8 文本编码为 GBK 字节后写入 bytea 列
SELECT convert_to('你好', 'GBK');                   -- \xc4e3bac3

-- 3) 三参数 convert：bytea → bytea，源 → 目的，全程不经过 text
SELECT convert(E'\\xc4e3bac3'::bytea, 'GBK', 'UTF8'); -- \xe4bda0e5a5bd

-- 4) encode/decode：base64/hex/escape，与字符集无关，只是字节↔ASCII
SELECT encode(convert_to('你好', 'UTF8'), 'base64'); -- 5L2g5aW9
SELECT convert_from(decode('5L2g5aW9', 'base64'), 'UTF8'); -- 你好

-- 5) SET CLIENT_ENCODING：会话级，影响所有进出字符串
SET client_encoding = 'GBK';
SELECT '你好';     -- 服务器把 UTF-8 转 GBK 后发给客户端
RESET client_encoding;

-- 6) 查看支持的所有编码
SELECT * FROM pg_catalog.pg_conversion LIMIT 5;
```

PostgreSQL 不支持 `CAST(... AS text CHARACTER SET ...)`，因为根本就不存在 "另一种编码的 text"。这种**单编码 + 边界转换**模型让所有内部操作（比较、索引、正则）都不必担心编码问题，是 PostgreSQL 字符串处理稳定可靠的根本原因。

### MySQL：四层默认值与 utf8 的历史包袱

MySQL 的字符集模型恰好相反——"无处不在的字符集"：

- **服务器**：`character_set_server`
- **数据库**：`CREATE DATABASE ... DEFAULT CHARACTER SET ...`
- **表**：`CREATE TABLE ... CHARACTER SET ...`
- **列**：`column VARCHAR(50) CHARACTER SET ...`
- **连接**：`character_set_client` / `character_set_connection` / `character_set_results`
- **字面量**：`_utf8mb4'abc'` 引介词

任何字符串表达式都有一个推导出来的字符集，比较两个不同字符集的字符串会触发隐式转换或报错（"Illegal mix of collations"）。

```sql
-- 显式转换的两种等价语法
SELECT CONVERT('résumé' USING utf8mb4);
SELECT CAST('résumé' AS CHAR CHARACTER SET utf8mb4);

-- 引介词指定字面量字符集
SELECT _utf8mb4'résumé';
SELECT _latin1 X'72e973756dE9';   -- 用十六进制表达 latin1 字节

-- 修复"双重编码"乱码：原本 utf8 的字节被错误存为 latin1
SELECT CONVERT(BINARY CONVERT('å­¦æ ¡' USING latin1) USING utf8mb4);
-- 结果: 学校

-- 查看连接级字符集
SHOW VARIABLES LIKE 'character_set%';
```

**utf8 的历史包袱**：MySQL 5.x 中 `utf8` 实际上只是 3 字节 BMP 子集（`utf8mb3`），无法存储 emoji 和 CJK 扩展平面字符。`utf8mb4` 才是真正的 RFC 3629 UTF-8。MySQL 8.0 起默认字符集从 `latin1` 改为 `utf8mb4`，默认排序规则改为 `utf8mb4_0900_ai_ci`。MySQL 8.0.30 已将 `utf8` 标记为 `utf8mb3` 的别名并弃用，未来主版本计划让 `utf8` 指向 `utf8mb4`。

### Oracle：NLS 体系与双字符集架构

Oracle 数据库实际上有**两个独立字符集**：

- `NLS_CHARACTERSET`：CHAR/VARCHAR2/CLOB 使用，建库时确定，事实上不可在线修改
- `NLS_NCHAR_CHARACTERSET`：NCHAR/NVARCHAR2/NCLOB 使用，仅可选 `AL16UTF16`（UTF-16BE）或 `UTF8`

```sql
-- 查看当前数据库字符集
SELECT * FROM nls_database_parameters
 WHERE parameter LIKE 'NLS%CHARACTERSET';

-- CONVERT(char, dest_charset [, source_charset])
-- 注意参数顺序：dest 在前
SELECT CONVERT('résumé', 'US7ASCII', 'WE8ISO8859P1') FROM dual;
-- 结果: r?sum?  （非 ASCII 字符变成替换符）

-- UNISTR：用 \xxxx 转义构造 NVARCHAR2
SELECT UNISTR('\4F60\597D') FROM dual;   -- 你好
SELECT UNISTR('Sm\00F8rebr\00F8d') FROM dual;  -- Smørebrød

-- 查询字符集 ID
SELECT NLS_CHARSET_ID('AL32UTF8') FROM dual;        -- 873
SELECT NLS_CHARSET_NAME(873) FROM dual;             -- AL32UTF8

-- ASCIISTR：反向，把 NVARCHAR2 转为 ASCII 安全的 \xxxx 序列
SELECT ASCIISTR('你好') FROM dual;   -- \4F60\597D
```

Oracle 的 `AL32UTF8` 是真正的 UTF-8（最长 4 字节），而 `UTF8` 是 CESU-8（最长 6 字节，BMP 外字符用代理对编码）。新建库应该选 `AL32UTF8`。

### SQL Server：代码页与 COLLATE

SQL Server 的字符集模型基于"代码页 + 排序规则"：

- `CHAR/VARCHAR` 使用代码页（由 collation 决定，例如 `Chinese_PRC_CI_AS` → CP936/GBK）
- `NCHAR/NVARCHAR` 一直是 UCS-2/UTF-16
- SQL Server 2019+ 支持 `UTF8` 排序规则（`Latin1_General_100_CI_AS_SC_UTF8`），让 `VARCHAR` 直接存储 UTF-8

```sql
-- COLLATE 子句切换列/表达式的代码页
SELECT CAST('résumé' AS VARCHAR(20))
       COLLATE Chinese_PRC_CI_AS AS gbk_text;

-- CONVERT 函数主要用于类型 + 格式转换
SELECT CONVERT(VARCHAR(20), N'résumé');
SELECT CONVERT(VARBINARY(20), N'résumé');   -- 得到 UTF-16LE 字节

-- N'...' 字面量始终是 NVARCHAR
SELECT N'你好';
SELECT NCHAR(0x4F60) + NCHAR(0x597D);       -- 你好

-- ALTER DATABASE 修改默认 collation（影响后续 CHAR/VARCHAR）
ALTER DATABASE mydb COLLATE Latin1_General_100_CI_AS_SC_UTF8;
```

SQL Server 没有 `convert_from` / `convert_to` 这样的纯字节转换函数，需要先 `CAST AS VARBINARY` 再用 `CAST AS VARCHAR` + `COLLATE` 间接实现，但只能在系统支持的代码页之间转换。

### DB2：CCSID 与 VARCHAR_BIT_FORMAT

DB2 用 **CCSID（Coded Character Set Identifier）**作为字符集编号，例如 1208 = UTF-8、1200 = UTF-16、367 = US-ASCII、1386 = GBK。

```sql
-- VARCHAR(expr, length, codeunits16 | codeunits32 | octets)
SELECT VARCHAR('résumé', 10, OCTETS);

-- CAST 携带 CCSID
SELECT CAST('résumé' AS VARCHAR(20) CCSID 1208);

-- TRANSLATE USING 转码
VALUES TRANSLATE('ABC' USING ASCII_TO_EBCDIC);

-- VARCHAR_BIT_FORMAT：字节↔hex 字符串
VALUES VARCHAR_BIT_FORMAT(BX'C4E3BAC3');     -- 'C4E3BAC3'
VALUES VARCHAR_FORMAT_BIT('C4E3BAC3');       -- BX'C4E3BAC3'

-- HEX/HEX2BIN
VALUES HEX('résumé');
```

DB2 的 z/OS 版本在 EBCDIC 与 ASCII 之间频繁转换，`TRANSLATE USING` 是 z/OS 应用迁移到 LUW 的关键兼容点。

### ClickHouse：convertCharset

```sql
-- ClickHouse 20.1+ (April 2020) 引入
SELECT convertCharset('你好', 'UTF-8', 'GBK');
-- 注意 ClickHouse 没有显式的 bytea 类型，这里输入是 String，
-- 引擎按 UTF-8 解码后再编码成 GBK，结果仍是 String 但字节是 GBK 序列。

-- 配合 hex/unhex 实现字节级转换
SELECT hex(convertCharset('你好', 'UTF-8', 'GBK'));   -- C4E3BAC3
```

ClickHouse 内部使用 ICU 库，支持的字符集列表非常齐全（200+）。但因为 String 类型本身没有元数据携带字符集，转换后仍可能与其他 UTF-8 String 一起参与运算导致乱码——使用时需要约定 String 列的"语义编码"。

### Snowflake / BigQuery：UTF-8 单一世界

Snowflake 与 BigQuery 都规定**所有字符串列都是 UTF-8**，不存在字符集转换。它们提供的是 base64 / hex / 字节↔字符串的转换：

```sql
-- Snowflake
SELECT BASE64_ENCODE('你好');                   -- 5L2g5aW9
SELECT BASE64_DECODE_STRING('5L2g5aW9');       -- 你好
SELECT HEX_ENCODE('你好');                      -- E4BDA0E5A5BD
SELECT HEX_DECODE_STRING('E4BDA0E5A5BD');      -- 你好

-- BigQuery
SELECT TO_BASE64(b'你好');                      -- 5L2g5aW9
SELECT FROM_BASE64('5L2g5aW9');                -- b'\xe4\xbd\xa0\xe5\xa5\xbd'
SELECT CODE_POINTS_TO_STRING([20320, 22909]);  -- 你好
SELECT TO_CODE_POINTS('你好');                  -- [20320, 22909]
```

如果一定要在 Snowflake / BigQuery 中处理非 UTF-8 数据，必须先在外部（例如导入工具）转好，或者把字节存进 BINARY/BYTES 列，由应用层负责解码。

## PostgreSQL 编码目录与 UTF8 中心化

PostgreSQL 通过系统目录 `pg_conversion` 维护所有可用的字符集转换。每条记录定义"源编码 → 目的编码"的转换函数：

```sql
SELECT conname, conforencoding::int AS src_enc, contoencoding::int AS dst_enc,
       conproc AS proc_name
  FROM pg_catalog.pg_conversion
 WHERE conname LIKE '%utf8%'
 ORDER BY conname
 LIMIT 10;
```

关键设计：所有非 UTF8 编码之间的转换都**经过 UTF8 作为中间枢纽**。例如 GBK → Big5 实际上执行的是 GBK → UTF8 → Big5 两步转换。这样 N 个编码只需要 2N 个转换函数（N 个进 + N 个出），而不是 N×(N-1) 个。代价是某些"封闭世界"内的转换（例如 Shift_JIS → EUC-JP）多了一次 UTF-8 中转，但收益是字符集矩阵管理大大简化。

支持的编码大类：

| 类别 | 示例 | 用途 |
|------|------|------|
| Unicode | UTF8 | 服务器内部 |
| 拉丁 | LATIN1-LATIN10, WIN1250-WIN1258 | 欧洲语言 |
| 中日韩 | GB18030, GBK, BIG5, EUC_JP, SJIS, EUC_KR, UHC | CJK |
| 西里尔/希腊 | KOI8R, WIN1251, ISO_8859_5, WIN1253 | 俄语/希腊语 |
| 阿拉伯/希伯来 | WIN1256, ISO_8859_8 | -- |
| 其他 | MULE_INTERNAL, SQL_ASCII | 兼容 |

> **SQL_ASCII 陷阱**：当数据库以 `SQL_ASCII` 编码创建时，PostgreSQL **不做任何字符集校验或转换**——所有字节按原样存储和返回。这看似灵活，实际上是数据混乱的根源：同一个表里可能既有 UTF-8 又有 GBK 字节。生产数据库永远不应使用 SQL_ASCII。

## MySQL 字符集层级

MySQL 字符集决议规则按如下优先级（高到低）：

```
1. 列定义                      → 最高优先级，列级 CHARACTER SET
2. 表默认                      → CREATE TABLE ... DEFAULT CHARACTER SET
3. 数据库默认                  → CREATE DATABASE ... DEFAULT CHARACTER SET
4. character_set_server        → 服务器全局变量
```

连接相关变量同样有四个：

| 变量 | 作用 |
|------|------|
| `character_set_client` | 客户端发来的 SQL 语句使用的字符集 |
| `character_set_connection` | 字符串字面量（无引介词时）的默认字符集 |
| `character_set_results` | 服务器发送结果集时转换到的字符集 |
| `character_set_database` | 当前数据库默认字符集 |

`SET NAMES utf8mb4` 是一条快捷命令，等价于：

```sql
SET character_set_client     = utf8mb4;
SET character_set_connection = utf8mb4;
SET character_set_results    = utf8mb4;
```

理解四层默认 + 三个连接变量 + 字面量引介词，是排查 MySQL "乱码 bug" 的必备地图。任何一层错配都会导致写入正常但读取乱码（或反之）。

## 引擎实现要点（给写引擎的人看）

### 1. 表达式字符集推导

需要在表达式树上为每个字符串节点维护两个属性：

- **charset**：编码（决定字节如何解释）
- **collation**：排序规则（决定字节如何比较）

二元运算符（拼接、比较、CASE）需要做"字符集合并"：

```
两侧字符集相同  → 直接合并
其中一侧是 ASCII → 取另一侧
其中一侧是 binary → 取另一侧
两侧都是非 ASCII 字符集 → 报错或按"可强制性 (coercibility)" 决定
```

MySQL 的 `coercibility` 等级（0=显式 COLLATE，1=表达式，2=列，3=系统常量，4=字面量，5=NULL，6=NUMERIC）就是为了解决"哪一侧赢"的问题。引擎可以参考这套机制。

### 2. 转换函数的两种实现策略

| 策略 | 优点 | 缺点 |
|------|------|------|
| ICU 库一把梭 | 编码齐全，维护少 | 额外依赖，体积大 |
| 手写常用编码表 | 零依赖，性能可控 | 需自己实现每种编码 |

PostgreSQL 选了第二种（lib/conversion/）；ClickHouse、SQL Server、Oracle 都依赖 ICU；DuckDB 在没有 ICU extension 时只支持 ASCII。

### 3. 校验 vs 替换策略

输入字节序列在目标编码中无对应字符时，转换函数有几种可选行为：

| 策略 | 示例 | 适用场景 |
|------|------|---------|
| 报错 | PostgreSQL `convert_from` | 数据完整性优先 |
| 替换为 `?` | Oracle `CONVERT` 默认 | 兼容性优先 |
| 替换为 U+FFFD | ICU 默认 | 健壮性优先 |
| 保留原字节 | SQL_ASCII | 不推荐 |
| 丢弃 | -- | 不推荐 |

引擎应允许用户选择策略，至少在 `COPY ... ENCODING` 这类批量场景。

### 4. 性能：避免无谓转换

```sql
-- 反例: 列是 utf8mb4，字面量被引介词强转 utf8mb3
SELECT * FROM t WHERE name = _utf8mb3'张三';
-- 优化器需要在比较前把右侧转成 utf8mb4，无法用索引

-- 正例: 让字面量与列字符集一致
SELECT * FROM t WHERE name = _utf8mb4'张三';
-- 直接走索引
```

引擎的优化器应当：

1. 识别"无损转换"（utf8mb3 → utf8mb4 是无损的，可以下推到字面量侧）
2. 识别"等价字符集"（utf8 与 utf8mb3 实际相同）
3. 拒绝把"有损转换"下推到列侧（utf8mb4 → latin1 可能丢字符，不能用索引）

## 关键发现

1. **三种世界观并存**：PostgreSQL 流派（数据库单一编码 + 边界转换）、MySQL 流派（无处不在的字符集 + 隐式转换 + 引介词）、Snowflake 流派（统一 UTF-8 不需转换）。新引擎大多选第三种，存量引擎绕不开前两种。

2. **CONVERT 是 SQL 中最歧义的函数名**：MySQL/Oracle 用作字符集转换、SQL Server 用作类型 + 格式化、PostgreSQL 用作 bytea↔bytea。不要假设跨引擎语义一致。

3. **MySQL 的 utf8 历史包袱仍在**：5.x 的 utf8 = 3 字节子集（无法存 emoji），8.0 默认改为 utf8mb4。但旧表、旧 schema、旧应用代码里大量残留 `CHARACTER SET utf8`，迁移时必须显式改为 `utf8mb4`。

4. **PostgreSQL 用 UTF8 作为转换枢纽**：所有非 UTF8 编码之间的转换都中转 UTF8，N 个编码只需 2N 个函数。代价是 GBK→Big5 这类同 CJK 圈转换多一次中转。

5. **SQL Server 2019 才支持 VARCHAR UTF-8**：之前 VARCHAR 只能用代码页，需要 emoji 必须 NVARCHAR。`Latin1_General_100_CI_AS_SC_UTF8` 这种 collation 让 VARCHAR 也能存 UTF-8。

6. **Oracle 的 AL32UTF8 vs UTF8**：前者是真 UTF-8（4 字节），后者是 CESU-8（BMP 外字符用代理对，6 字节）。新库必须用 AL32UTF8。

7. **SQLite 始终 UTF-8（或 UTF-16）**：完全没有字符集转换函数。需要处理其他编码必须在应用层转好再写入。

8. **ClickHouse convertCharset 较新**：20.1（2020 年 4 月）才引入，使用 ICU。早期版本只能用 hex+应用层转换。

9. **Redshift 没有 CONVERT 字符集函数**：所有字符串按 UTF-8 字节存储，VARCHAR(n) 是字节数而非字符数，CJK 字符占 3 字节，定义 `VARCHAR(10)` 只能存 3 个汉字。

10. **N'...' 字面量 ≠ Unicode 字面量**：在 SQL Server/Oracle 里 N'...' 是 UTF-16 NCHAR，在 PostgreSQL 里 N 前缀被解析但忽略（因为 NCHAR=CHAR）。要写 Unicode 字面量更通用的写法是 SQL 标准的 `U&'\00e9'`。

11. **convert_from / convert_to 是 PG 系最纯净的转换 API**：`text` 永远是 UTF-8，bytea 携带任意字节，转换函数明确指定方向。CockroachDB、Materialize、RisingWave 等 PG 兼容系都继承了这套 API。

12. **TRANSLATE 有两种语义**：Oracle 风格 `TRANSLATE(s, 'abc', 'xyz')` 是字符替换，DB2/Teradata 风格 `TRANSLATE(s USING name)` 是字符集转换。同名函数完全不同语义，跨引擎移植必须警惕。

13. **乱码修复的通用模式**：`CONVERT(BINARY CONVERT(s USING wrong_charset) USING right_charset)`——先把字符强转为字节、按错误编码解释，再按正确编码重新组合。这种"反向修复"在 MySQL 里是常用的应急手段。

14. **base64 / hex 不属于字符集转换**：它们是字节↔ASCII 字符的可逆映射，跟编码无关。但常被错误地用作"字符集转换"，因为它们把任意字节变成可传输的 ASCII。

15. **大数据引擎普遍只支持 from_utf8 / to_utf8**：Trino/Presto/Athena/Spark/Flink/DatabendDB 都假设字符串是 UTF-8，只暴露 binary↔string 的入口。要处理其他编码必须先 binary 进系统、应用层转码。

16. **DB2 的 CCSID 是数字编号**：1208=UTF-8、1200=UTF-16、367=ASCII、1386=GBK。这种数字标识在 IBM 主机生态中是行业标准，跨平台脚本需要 CCSID↔IANA 名映射表。

17. **NLS_CHARACTERSET 不可在线修改**：Oracle 数据库一旦建库，主字符集就基本定型。`ALTER DATABASE CHARACTER SET` 仅在新字符集是旧字符集严格超集时允许，且是高风险操作。生产环境从 WE8MSWIN1252 升级到 AL32UTF8 通常通过导出 + 新库导入完成。

18. **SAP HANA 内部用 CESU-8**：对 BMP 外字符（如 emoji、罕见汉字）使用 6 字节而非 4 字节，与"真 UTF-8"不完全互通。集成时需要在边界转换。

19. **统一 UTF-8 是新引擎的共识**：Snowflake、BigQuery、DuckDB、ClickHouse（默认）、Spanner、Materialize、Firebolt、Yellowbrick、Spanner 等几乎所有 2010 年后新生引擎都选择 UTF-8 单一字符集，把字符集转换的复杂度推到数据加载工具或应用层。

20. **字符集与排序规则的耦合是天然的**：任何排序规则都隐含字符集（`utf8mb4_0900_ai_ci` 必须配 utf8mb4），但反之不然。引擎实现时建议把 charset 视为 collation 的一个属性，避免出现"字符集 A + 排序规则 B"这种逻辑上不可能的组合。

## 总结对比矩阵

| 能力 | PostgreSQL | MySQL | Oracle | SQL Server | DB2 | ClickHouse | Snowflake | BigQuery | DuckDB | Spark |
|------|-----------|-------|--------|------------|-----|------------|-----------|----------|--------|-------|
| CONVERT 字符集 | bytea | USING | dest,src | -- | -- | convertCharset | -- | -- | -- | -- |
| CAST AS ... CHARSET | -- | 是 | -- | -- | CCSID | -- | -- | -- | -- | -- |
| convert_from/to | 是 | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| encode/decode (PG) | 是 | -- | -- | -- | -- | -- | -- | -- | 是 | encode/decode |
| base64 | encode | TO_BASE64 | UTL_ENCODE | XML 技巧 | BASE64ENCODE | base64Encode | BASE64_ENCODE | TO_BASE64 | to_base64 | base64 |
| hex | encode | HEX | RAWTOHEX | CONVERT | HEX | hex | HEX_ENCODE | TO_HEX | to_hex | hex |
| N'...' 字面量 | 解析忽略 | 是 | 是 | 是 | 是 | -- | -- | -- | -- | -- |
| _charset 引介词 | -- | 是 | -- | -- | -- | -- | -- | -- | -- | -- |
| UNISTR | -- | -- | 是 | -- | 是 | -- | -- | -- | -- | -- |
| U&'...' | 是 | -- | -- | -- | 是 | -- | -- | -- | -- | -- |
| TRANSLATE USING | -- | -- | 是 | -- | 是 | -- | -- | -- | -- | -- |
| 内部统一编码 | UTF8 | 多 | 双 | 多 | 多 | UTF-8 | UTF-8 | UTF-8 | UTF-8 | UTF-8 |

## 引擎选型建议

| 场景 | 推荐方案 | 原因 |
|------|---------|------|
| 多语言混合 OLTP | PostgreSQL UTF8 + 客户端编码协商 | 单编码内核 + 边界转换 |
| 兼容遗留 latin1 数据 | MySQL utf8mb4 + CONVERT USING | 引介词 + 显式 USING 灵活 |
| 主机/EBCDIC 集成 | DB2 + TRANSLATE USING | EBCDIC↔ASCII 原生 |
| 数据湖 / 仓库 | Snowflake / BigQuery / DuckDB | 统一 UTF-8 没有转换烦恼 |
| 高频字符集互转 | ClickHouse + convertCharset | ICU 后端，编码齐全 |
| 跨字符集大批量导入 | PostgreSQL `COPY ... ENCODING` | 流式编码识别 + 转换 |
| 二进制通道传输文本 | base64 / hex 编码 | 字节安全，与字符集无关 |

## 参考资料

- SQL:1999 标准: ISO/IEC 9075-2, Section 6.22 ⟨cast specification⟩
- SQL:2003 标准: Section 6.30 ⟨string value function⟩ - CONVERT, TRANSLATE
- PostgreSQL: [Character Set Support](https://www.postgresql.org/docs/current/multibyte.html)
- PostgreSQL: [String Functions - convert_from / convert_to](https://www.postgresql.org/docs/current/functions-string.html)
- MySQL: [Character Set Support](https://dev.mysql.com/doc/refman/8.0/en/charset.html)
- MySQL: [CONVERT(expr USING transcoding_name)](https://dev.mysql.com/doc/refman/8.0/en/cast-functions.html#function_convert)
- Oracle: [CONVERT Function](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/CONVERT.html)
- Oracle: [Database Globalization Support Guide](https://docs.oracle.com/en/database/oracle/oracle-database/19/nlspg/index.html)
- SQL Server: [Collation and Unicode Support](https://learn.microsoft.com/en-us/sql/relational-databases/collations/collation-and-unicode-support)
- DB2: [TRANSLATE scalar function](https://www.ibm.com/docs/en/db2-for-zos/13?topic=functions-translate)
- ClickHouse: [convertCharset](https://clickhouse.com/docs/en/sql-reference/functions/string-functions#convertcharset)
- Snowflake: [String Functions (Binary)](https://docs.snowflake.com/en/sql-reference/functions-string)
- BigQuery: [String Functions](https://cloud.google.com/bigquery/docs/reference/standard-sql/string_functions)
- Trino: [Binary Functions](https://trino.io/docs/current/functions/binary.html)
- Unicode Standard: [UTF-8, UTF-16, CESU-8](https://www.unicode.org/reports/tr26/)
- IBM CCSID Repository: [Character Data Representation Architecture](https://www.ibm.com/docs/en/i/7.5?topic=concepts-ccsids)
