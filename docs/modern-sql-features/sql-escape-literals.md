# SQL 字符串字面量转义 (String Literal Escaping and Prefixes)

一个看似简单的 `'it''s ok'` 在不同数据库中可能是合法的、非法的、或者有完全不同的语义——字符串字面量的转义规则是 SQL 方言差异中最碎片化的角落，也是 SQL 注入漏洞最常见的温床。

## 为什么字符串转义如此分裂

SQL 字符串字面量表面上只是一段被单引号包围的字符序列，但围绕"如何在字符串中表达一个单引号"这个基础问题，各大厂商在近四十年里给出了完全不同的答案：

- **SQL 标准路线**: 用两个连续单引号（`''`）表示一个单引号字符，这是 SQL:1992 以来的官方做法
- **C 语言路线**: 用反斜杠（`\'`）转义单引号，这是 MySQL、SQLite（在特定模式下）、部分驱动程序的历史选择
- **前缀标识路线**: PostgreSQL 的 `E'...'`（扩展转义字符串）、SQL Server/Oracle 的 `N'...'`（National Character）、DB2/PostgreSQL 的 `U&'...'`（Unicode 转义）
- **定界符替代路线**: Oracle 的 `Q'{...}'`、PostgreSQL 的 `$$...$$` 美元定界字符串、BigQuery 的 `r"..."` 原始字符串
- **十六进制/二进制字面量路线**: `X'DEADBEEF'`、`0x...`、`B'0101'`

这种分裂的根源有三：(1) SQL:1992 标准确立得晚，MySQL 等引擎早已采用 C 风格转义；(2) Unicode 支持在不同年代以不同扩展加入；(3) 各厂商为了在字符串中嵌入代码（PL/SQL、PL/pgSQL、正则表达式）发明了各自的"原始字符串"语法。

一个跨引擎 SQL 生成器若忽视这些差异，极易生成语法错误或——更糟——产生 SQL 注入漏洞。

## SQL 标准对字符串字面量的定义

### SQL:1992（SQL-92）

SQL:1992 标准（ISO/IEC 9075:1992）首次系统定义了字符串字面量：

```sql
<character string literal> ::=
    [ <introducer> <character set specification> ]
    <quote> [ <character representation>... ] <quote>
    [ { <separator>... <quote> [ <character representation>... ] <quote> }... ]

<character representation> ::=
    <nonquote character>
  | <quote symbol>

<quote symbol> ::= <quote> <quote>   -- 即 ''

<separator> ::= { <comment> | <space> | <newline> }...
```

标准要点：

1. **单引号用作定界符**：字符串由一对单引号包围
2. **双写单引号转义**：字符串内的单引号用 `''` 表示
3. **不支持反斜杠转义**：标准中反斜杠没有特殊含义，`'\n'` 就是反斜杠后接字母 n，而不是换行符
4. **字符串连接**：相邻两个字符串字面量（中间仅含空白和注释）自动拼接为一个字符串
5. **introducer 前缀**：用 `_charset_name 'literal'` 指定字符集，例如 `_latin1 'hello'`

### SQL:1999

SQL:1999 引入：

- **National character string literal**：`N'literal'`，对应 `NATIONAL CHARACTER` 类型（通常为 UTF-16/UCS-2）
- **Bit string literal**：`B'01010101'`
- **Hex string literal**：`X'4D7953514C'`（大小写混合 `x`/`X` 均可，每两个十六进制字符对应一字节）

### SQL:2003 与 SQL:2008

- **Unicode string literal**：`U&'\00E9'`（Unicode delimited identifier/literal），通过 `U&` 前缀激活 `\XXXX` / `\+XXXXXX` 转义，SQL:2003 引入、SQL:2008 完善
- **UESCAPE 子句**：可自定义转义字符，如 `U&'!00E9' UESCAPE '!'`
- **非常量字符串扩展**：各厂商在标准之外增加了美元定界（PostgreSQL）、q-quote（Oracle）、raw（BigQuery）等扩展

### 标准未定义的内容

SQL 标准明确**未定义**以下常见"特性"：

- 反斜杠转义序列（`\n`、`\t`、`\\` 等）
- 美元定界字符串（`$$...$$`）
- C-style `\xHH` 或 `\uXXXX` 转义
- 原始字符串（r"..." / R"..."）
- 多字节字符的可变长度转义

凡是使用这些特性的 SQL 都是**方言扩展**，跨引擎时必须小心。

## 支持矩阵

### 基础引号与转义支持

| 引擎 | `''` 双写 | `\'` 反斜杠 | 可配置反斜杠 | `E'...'` | `N'...'` | `U&'...'` | `$$...$$` | 引擎版本来源 |
|------|---------|-----------|------------|---------|---------|-----------|-----------|-------------|
| PostgreSQL | 标准 | 仅 E'..' | `standard_conforming_strings` | 是 | 标准行为 | 是 | 是 | 8.3+ 标准化 |
| MySQL | 标准 | 默认启用 | `NO_BACKSLASH_ESCAPES` | -- | 是（仅前缀） | -- | -- | 5.0+ |
| MariaDB | 标准 | 默认启用 | `NO_BACKSLASH_ESCAPES` | -- | 是（仅前缀） | -- | -- | 继承 MySQL |
| Oracle | 标准 | 禁用 | 无（非字符串转义） | -- | 是（nchar） | 扩展 | -- | Q'{..}' 10g+ |
| SQL Server | 标准 | 禁用 | 无 | -- | 是（nvarchar） | -- | -- | 所有版本 |
| SQLite | 标准 | 默认禁用 | 编译时可启 | -- | -- | -- | -- | 所有版本 |
| DB2 (Db2 LUW) | 标准 | 禁用 | 无 | -- | 是 | 是 | -- | 9.5+ 的 U& |
| Snowflake | 标准 | 默认启用 | 会话参数 | -- | 识别但忽略 | -- | 是（变体） | GA |
| BigQuery | 标准 | 默认启用 | 无切换 | -- | -- | -- | -- | GA（C 风格） |
| Redshift | 标准 | 默认启用 | `STANDARD_CONFORMING_STRINGS` | 是 | -- | -- | -- | 继承 PG |
| Trino | 标准 | 禁用 | 无 | -- | -- | U& 标准 | -- | 全版本 |
| Presto | 标准 | 禁用 | 无 | -- | -- | -- | -- | 全版本 |
| DuckDB | 标准 | 禁用 | 无 | 是（扩展） | -- | -- | -- | 全版本 |
| ClickHouse | 标准 | 默认启用 | 无切换 | -- | -- | -- | -- | 全版本 |
| Spark SQL | 标准 | 默认启用 | `spark.sql.parser.escapedStringLiterals` | -- | -- | -- | -- | 2.0+ |
| Databricks | 标准 | 默认启用 | 同上 | -- | -- | -- | -- | GA |
| Hive | 标准 | 默认启用 | 无切换 | -- | -- | -- | -- | 全版本 |
| Flink SQL | 标准 | 默认启用 | 无切换 | -- | -- | -- | -- | 全版本 |
| Teradata | 标准 | 禁用 | 无 | -- | -- | -- | -- | 全版本 |
| Greenplum | 标准 | 仅 E'..' | `standard_conforming_strings` | 是 | 标准行为 | 是 | 是 | 继承 PG |
| CockroachDB | 标准 | 仅 e'..'/E'..' | 默认符合标准 | 是 | -- | -- | 是 | 全版本 |
| TiDB | 标准 | 默认启用 | `NO_BACKSLASH_ESCAPES` | -- | 是（前缀） | -- | -- | 继承 MySQL |
| OceanBase | 标准 | 默认启用（MySQL 模式）/禁用（Oracle 模式） | 模式相关 | -- | 是 | -- | -- | 全版本 |
| YugabyteDB | 标准 | 仅 E'..' | `standard_conforming_strings` | 是 | 标准行为 | 是 | 是 | 继承 PG |
| SingleStore | 标准 | 默认启用 | `NO_BACKSLASH_ESCAPES` | -- | 是 | -- | -- | 继承 MySQL |
| Vertica | 标准 | 默认启用 | `StandardConformingStrings` | 是 | -- | -- | -- | 全版本 |
| Impala | 标准 | 默认启用 | 无切换 | -- | -- | -- | -- | 全版本 |
| StarRocks | 标准 | 默认启用 | 无 | -- | -- | -- | -- | 继承 MySQL 协议 |
| Doris | 标准 | 默认启用 | 无 | -- | -- | -- | -- | 继承 MySQL 协议 |
| MonetDB | 标准 | 默认启用 | 无 | -- | -- | -- | -- | 全版本 |
| CrateDB | 标准 | 默认禁用 | `standard_conforming_strings` | 是 | -- | -- | 是 | 继承 PG |
| TimescaleDB | 标准 | 仅 E'..' | 同 PG | 是 | 标准行为 | 是 | 是 | 继承 PG |
| QuestDB | 标准 | 禁用 | 无 | -- | -- | -- | -- | 全版本 |
| Exasol | 标准 | 禁用 | 无 | -- | -- | -- | -- | 全版本 |
| SAP HANA | 标准 | 禁用 | 无 | -- | 是 | -- | -- | 全版本 |
| Informix | 标准 | 可配置 | `DELIMIDENT`/转义 | -- | -- | -- | -- | 全版本 |
| Firebird | 标准 | 禁用 | 无 | -- | 是（变体） | -- | -- | 2.5+ |
| H2 | 标准 | 默认禁用 | MODE 相关 | -- | 是（MSSQL 模式） | -- | -- | 全版本 |
| HSQLDB | 标准 | 禁用 | 无 | -- | -- | -- | -- | 全版本 |
| Derby | 标准 | 禁用 | 无 | -- | -- | -- | -- | 全版本 |
| Amazon Athena | 标准 | 禁用 | 无 | -- | -- | -- | -- | 继承 Trino |
| Azure Synapse | 标准 | 禁用 | 无 | -- | 是（nvarchar） | -- | -- | 继承 MSSQL |
| Google Spanner | 标准 | 支持（GoogleSQL） | 无 | -- | -- | -- | -- | GoogleSQL |
| Materialize | 标准 | 仅 E'..' | `standard_conforming_strings` | 是 | -- | 是 | 是 | 继承 PG |
| RisingWave | 标准 | 仅 E'..' | `standard_conforming_strings` | 是 | -- | 是 | 是 | 继承 PG |
| InfluxDB (SQL) | 标准 | 禁用 | 无 | -- | -- | -- | -- | 全版本 |
| Databend | 标准 | 默认启用（MySQL 兼容） | 无切换 | -- | -- | -- | 是 | 全版本 |
| Yellowbrick | 标准 | 仅 E'..' | `standard_conforming_strings` | 是 | 标准行为 | 是 | 是 | 继承 PG |
| Firebolt | 标准 | 默认启用 | 无 | -- | -- | -- | -- | 全版本 |

> 统计：约 50 个引擎统计中，全部支持标准 `''` 双写；约 20 个引擎默认启用反斜杠转义（主要来自 MySQL 系和 Spark/BigQuery 系）；`E'..'` 在 PG 系中普及；`N'..'` 在 SQL Server/Oracle/HANA 等传统厂商支持；`U&'..'` 仅 PG、DB2、Trino、Materialize、RisingWave 等少数引擎严格支持；`$$...$$` 基本等同于 PG 生态标志。

### 特殊字符串字面量前缀

| 引擎 | `X'..'` 十六进制 | `0x..` 十六进制 | `B'..'` 二进制 | `R'..'`/`r'..'` 原始 | `Q'{..}'` q-quote | `_charset '..'` introducer |
|------|----------------|----------------|--------------|---------------------|-------------------|-------------------------|
| PostgreSQL | 是 | -- | 是 | -- | -- | -- |
| MySQL | 是 | 是 | 是 | -- | -- | `_charset` 是 |
| MariaDB | 是 | 是 | 是 | -- | -- | `_charset` 是 |
| Oracle | 是 | -- | -- | -- | 是（10g+） | -- |
| SQL Server | 是（0x..） | 是 | -- | -- | -- | -- |
| SQLite | 是 | 是 | -- | -- | -- | -- |
| DB2 | 是 | -- | 是 | -- | -- | -- |
| Snowflake | 是 | -- | 是 | -- | -- | -- |
| BigQuery | 是 | -- | -- | `r'..'`/`R'..'` | -- | -- |
| Redshift | 是 | -- | 是 | -- | -- | -- |
| Trino | 是 | -- | -- | -- | -- | -- |
| DuckDB | 是 | -- | -- | -- | -- | -- |
| ClickHouse | 是 | -- | 是 | -- | -- | -- |
| Spark SQL | 是 | -- | -- | `r'..'`/`R'..'` | -- | -- |
| Hive | 是（Parquet 侧） | -- | -- | -- | -- | -- |
| CockroachDB | 是 | -- | 是 | -- | -- | -- |
| Firebird | 是 | -- | -- | -- | -- | -- |
| H2 | 是 | 是 | -- | -- | -- | -- |
| SAP HANA | 是 | -- | -- | -- | -- | -- |
| Vertica | 是 | -- | 是 | -- | -- | -- |

### Unicode 转义能力

| 引擎 | `\uXXXX` 4 位 | `\UXXXXXXXX` 8 位 | `U&'\XXXX'` 标准 | `UESCAPE '!'` 自定义 | `\xHH` 字节 |
|------|-------------|------------------|------------------|---------------------|-----------|
| PostgreSQL | 仅 E'..' | 仅 E'..' | 是 | 是 | 仅 E'..' |
| MySQL | -- | -- | -- | -- | -- |
| MariaDB | -- | -- | -- | -- | -- |
| Oracle | -- | -- | `UNISTR('\00E9')` | -- | -- |
| SQL Server | -- | -- | -- | -- | -- |
| SQLite | -- | -- | -- | -- | -- |
| DB2 | -- | -- | 是 | 是 | -- |
| Snowflake | -- | -- | -- | -- | -- |
| BigQuery | 是 | 是 | -- | -- | 是 |
| Trino | -- | -- | 是 | 是 | -- |
| DuckDB | -- | -- | -- | -- | -- |
| Spark SQL | 是 | -- | -- | -- | 是 |
| ClickHouse | 是 | -- | -- | -- | 是 |
| Databend | 是 | -- | -- | -- | 是 |
| CockroachDB | 是（e'..'） | 是（e'..'） | -- | -- | 是（e'..'） |

### 字符串连接运算符

| 引擎 | `\|\|` 标准 | `+` 加号 | `CONCAT()` | 相邻字面量自动拼接 |
|------|----------|---------|-----------|------------------|
| PostgreSQL | 是 | -- | 是 | 是（需换行分隔） |
| MySQL | 仅 `PIPES_AS_CONCAT` | -- | 是 | -- |
| Oracle | 是 | -- | 是 | -- |
| SQL Server | -- | 是（字符串） | 是（2012+） | -- |
| SQLite | 是 | -- | -- | -- |
| DB2 | 是 | -- | 是 | 是 |
| Snowflake | 是 | -- | 是 | -- |
| BigQuery | 是 | -- | 是 | -- |
| Trino | 是 | -- | 是 | 是 |
| DuckDB | 是 | -- | 是 | -- |
| ClickHouse | -- | -- | 是 | -- |
| Spark SQL | 是（4.0+） | -- | 是 | -- |

## 各主流引擎详解

### PostgreSQL：从反斜杠到 E'..' 的二十年变迁

PostgreSQL 的字符串字面量是所有数据库中**规则最正交也最复杂**的一套。理解它需要理解一段历史：

- **7.x 及更早**：反斜杠默认启用，`'\n'` 就是换行符，但 SQL 标准要求反斜杠无特殊含义
- **8.1（2005）**：引入 `standard_conforming_strings` GUC，默认 `off`（向后兼容），通过警告提示未来行为变化
- **8.3（2008）**：引入 `E'...'` 作为"明确的扩展转义字符串"前缀，不受 GUC 影响
- **9.1（2011）**：`standard_conforming_strings` 默认改为 `on`，普通字符串符合标准（反斜杠无特殊含义）
- **15+**：移除 `escape_string_warning` 的实际效果（参数仍存在）

#### 当前 PostgreSQL 中的四种字符串字面量

```sql
-- 1) 普通字符串（standard_conforming_strings=on 时符合 SQL 标准）
SELECT 'hello' AS s;
SELECT 'it''s ok' AS s;            -- 标准的双写
SELECT '\n' AS s;                   -- 就是两个字符：反斜杠 + n

-- 2) 扩展转义字符串（E 前缀）
SELECT E'\n' AS s;                  -- 换行符
SELECT E'\t\r\n\b\f\v\\\'\"' AS s;  -- C 风格全套
SELECT E'\x1b[31mRed\x1b[0m' AS s;  -- 十六进制字节（每 \xHH 为一字节）
SELECT E'é' AS s;              -- Unicode BMP 代码点（4 位十六进制）
SELECT E'\U0001F600' AS s;          -- Unicode 非 BMP 代码点（8 位十六进制）
SELECT E'\101' AS s;                -- 八进制（3 位），等于 'A'

-- 3) Unicode 字符串字面量
SELECT U&'caf\00E9' AS s;           -- é
SELECT U&'d\+0001F600' AS s;        -- 非 BMP，6 位前加 +
SELECT U&'caf#00E9' UESCAPE '#';    -- 自定义转义字符

-- 4) 美元定界字符串（dollar-quoted string）
SELECT $$hello, 'world'$$ AS s;
SELECT $tag$it's $$ ok$tag$ AS s;   -- 自定义标签，避免与内容冲突
```

#### standard_conforming_strings 的影响

```sql
-- 检查当前设置
SHOW standard_conforming_strings;   -- 默认 on（9.1+）

-- 临时切换到非标准模式（不推荐）
SET standard_conforming_strings = off;
SELECT '\n';   -- 现在是换行符，同时会发出警告（如果 escape_string_warning=on）

-- 迁移旧代码的最安全方式：显式使用 E'..' 前缀
SELECT E'\n';  -- 永远是换行符，不受 GUC 影响
```

#### dollar-quoting 的真正价值

美元定界字符串在嵌入函数体、正则表达式、复杂文本时无需转义任何内容：

```sql
-- 创建函数：不用每个单引号都 ''
CREATE FUNCTION greet(name text) RETURNS text AS $$
BEGIN
    RETURN 'Hello, ' || name || '!';   -- 内部单引号无需转义
END;
$$ LANGUAGE plpgsql;

-- 标签避免与内部 $$ 冲突
CREATE FUNCTION example() RETURNS text AS $body$
BEGIN
    RETURN $$inner $$ literal$$;   -- 内部还能用 $$，标签要唯一
END;
$body$ LANGUAGE plpgsql;

-- 注意：dollar-quoted 字符串**不做任何转义处理**
SELECT $$\n$$;   -- 两个字符：反斜杠 + n
```

### MySQL：反斜杠默认启用与 NO_BACKSLASH_ESCAPES

MySQL 的字符串字面量**违反 SQL 标准**的程度最深——默认启用 C 风格的反斜杠转义。这是历史遗留（MySQL 早于 SQL-92 的广泛采用），后来通过 `sql_mode` 提供切换。

```sql
-- 默认模式（反斜杠生效）
SELECT '\n';            -- 换行符（0x0A）
SELECT '\t';            -- 制表符
SELECT '\\';            -- 单个反斜杠
SELECT '\0';            -- ASCII NUL
SELECT '\Z';            -- Ctrl+Z (0x1A)，Windows EOF
SELECT '\'';            -- 单引号（两种转义方式皆可）
SELECT '''';            -- 单引号（SQL 标准方式）
SELECT 'it\'s ok';      -- 非标准
SELECT 'it''s ok';      -- 标准

-- MySQL 支持但大多数工具不处理的特殊转义
SELECT '\%';            -- 字面上的 \%（在 LIKE 中用）
SELECT '\_';            -- 字面上的 \_

-- 切换到标准模式
SET sql_mode = CONCAT(@@sql_mode, ',NO_BACKSLASH_ESCAPES');
SELECT '\n';            -- 现在就是两个字符：反斜杠 + n
```

#### MySQL 的其他字符串字面量形式

```sql
-- 字符集 introducer（SQL-92 标准，MySQL 扩展了）
SELECT _latin1 'abc';
SELECT _utf8mb4 'héllo';
SELECT _utf8mb4 0xE4B8ADE69687;   -- 中文字节码

-- N 前缀：等价于 _utf8（不是 _utf8mb4）
SELECT N'hello';

-- 十六进制字面量：两种等价形式
SELECT X'48656C6C6F';             -- SQL 标准写法
SELECT 0x48656C6C6F;              -- C 风格
-- 作为字符串使用时需要上下文，或者 CAST
SELECT HEX(X'48656C6C6F');        -- '48656C6C6F'
SELECT CAST(X'48656C6C6F' AS CHAR);  -- 'Hello'

-- 二进制字面量
SELECT B'0100100001101001';       -- 'Hi' 的二进制
SELECT 0b0100100001101001;        -- C 风格

-- 相邻字符串拼接（SQL 标准，MySQL 支持）
SELECT 'hel' 'lo';                -- 'hello'（标准语法但少用）
-- 注意：这是 SQL-92 特性，MySQL 支持但需分行/空白分隔
```

#### 为什么 NO_BACKSLASH_ESCAPES 难以推广

尽管 SQL 标准要求反斜杠无特殊含义，MySQL 默认模式至今未切换，因为：

1. **应用代码遍布 `\'` 风格转义**：mysql_real_escape_string、PDO、各 ORM 会插入反斜杠
2. **数据文件与脚本**：几十年的 mysqldump 输出默认使用反斜杠
3. **切换会造成静默行为改变**：`INSERT INTO t VALUES('\n')` 不报错，但存储的内容会从换行符变为两字符

### Oracle：Q'{...}' 与 N'...'

Oracle 的字符串字面量**严格符合 SQL 标准**：无反斜杠转义，只能用双写单引号。在 10g 引入了独创的 q-quote 语法。

```sql
-- 标准单引号
SELECT 'it''s ok' FROM dual;

-- N 前缀（NCHAR/NVARCHAR2，National Character Set，通常是 AL16UTF16）
SELECT N'café' FROM dual;        -- 注意：\u 在 Oracle 中不是转义
SELECT N'héllo' FROM dual;             -- 只能直接输入 Unicode 字符
SELECT UNISTR('caf\00e9') FROM dual;   -- 通过 UNISTR 函数做 \XXXX 转义

-- Q-quote 语法（10g 引入）
SELECT q'{it's ok}' FROM dual;            -- 用 { } 作定界符
SELECT q'[it's also ok]' FROM dual;       -- 用 [ ]
SELECT q'(it's ok too)' FROM dual;        -- 用 ( )
SELECT q'<angled>' FROM dual;             -- 用 < >
SELECT q'!any char!' FROM dual;           -- 任意非字母数字非空白字符
SELECT q'#with # inside is problematic#' FROM dual;  -- 要点：定界符不能出现在内部
SELECT NQ'{N-char: héllo}' FROM dual;     -- NQ 组合：National + q-quote

-- 混合 q 与连接
SELECT q'{SELECT * FROM }' || table_name || q'{ WHERE x='A'}'
FROM user_tables;

-- 与 \n 换行符的关系
SELECT q'[Line 1
Line 2]' FROM dual;   -- 字面换行是合法的，但建议用 CHR(10)
SELECT 'Line 1' || CHR(10) || 'Line 2' FROM dual;
```

#### Oracle 的二进制与十六进制

```sql
SELECT HEXTORAW('48656C6C6F') FROM dual;   -- 'Hello' 字节
SELECT UTL_RAW.CAST_TO_VARCHAR2(HEXTORAW('48656C6C6F')) FROM dual;
-- Oracle 无独立的 X'..' 字面量语法，靠 HEXTORAW 函数
```

### SQL Server：N'...' 与字符集处理

SQL Server 严格使用标准字符串字面量，没有反斜杠转义。`N'..'` 前缀标识 Unicode (UTF-16) 字符串。

```sql
-- 标准字符串
SELECT 'it''s ok';

-- 反斜杠无特殊含义
SELECT '\n';            -- 字面两个字符：\ 和 n
SELECT LEN('\n');       -- 返回 2

-- N 前缀（Unicode nvarchar）
SELECT N'héllo';
SELECT N'中文字符';
SELECT DATALENGTH(N'A');   -- 2（UTF-16 每字符 2 字节）
SELECT DATALENGTH('A');    -- 1（varchar 单字节）

-- 不加 N 前缀时，字符串按当前数据库排序规则的代码页解析
-- 若代码页不支持某字符，数据可能损失（常见坑）：
INSERT INTO t(nvarchar_col) VALUES ('中文');     -- 错！可能存为 '??'
INSERT INTO t(nvarchar_col) VALUES (N'中文');    -- 对

-- 2019+ 起 UTF-8 排序规则可绕过此问题
CREATE DATABASE utf8db COLLATE Latin1_General_100_CI_AI_SC_UTF8;

-- 字符串字面量拼接：必须显式用 + 或 CONCAT
SELECT 'foo' + 'bar';                -- 'foobar'
SELECT CONCAT('foo', NULL, 'bar');   -- 'foobar'（CONCAT 忽略 NULL）
-- 注意：+ 在 NULL 上会返回 NULL（除非 CONCAT_NULL_YIELDS_NULL 为 OFF，已废弃）

-- 十六进制常量
SELECT CONVERT(char(5), 0x48656C6C6F);   -- 'Hello'
-- SQL Server 没有 X'..' 语法，使用 0x.. 作为 binary 字面量

-- 转义通配符（用于 LIKE）
SELECT * FROM t WHERE col LIKE '50[%]' ESCAPE '\';
-- LIKE 有自己的通配符语义，和字符串转义不同
```

### SQLite：最简主义

SQLite 的字符串字面量处理堪称极简：

```sql
-- 标准字符串，反斜杠无特殊含义
SELECT 'hello\nworld';      -- 字面 12 字符，含反斜杠 n
SELECT length('hello\nworld');  -- 12

-- 双写单引号转义（唯一方式）
SELECT 'it''s ok';

-- 十六进制字节字面量（作为 BLOB）
SELECT x'48656C6C6F';       -- BLOB: 'Hello' 的字节

-- SQLite 的独特"陷阱"：双引号被当成字符串
SELECT "hello";             -- 如果没有名为 hello 的列，当作字符串返回 'hello'
                            -- 这是 SQLite 为了 MS Access 兼容保留的"功能"
-- 建议总是用单引号避免此坑

-- 可以通过编译选项关闭此容忍：
-- SQLITE_DQS=0（禁用字符串中的双引号）

-- 相邻字符串拼接：SQLite 不支持
-- SELECT 'foo' 'bar';   -- 语法错误
SELECT 'foo' || 'bar';   -- 正确：显式拼接运算符
```

### DB2 (Db2 LUW)：最完整的标准支持

Db2 是为数不多**完全实现 SQL:2008 标准** Unicode 字符串字面量的商业引擎：

```sql
-- 标准字符串
VALUES 'it''s ok';

-- N 前缀（NCHAR/NVARCHAR，仅 Db2 for z/OS 和部分版本）
VALUES N'héllo';

-- Unicode 字符串字面量（SQL 标准）
VALUES U&'caf\00E9';               -- 'café'
VALUES U&'d\+0001F600';            -- 😀（非 BMP，用 \+XXXXXX）
VALUES U&'caf!00E9' UESCAPE '!';   -- 自定义转义字符

-- 标识符也支持 Unicode 转义
SELECT U&"col\00E9" FROM t;

-- 十六进制、二进制
VALUES X'48656C6C6F';              -- Hello 字节
VALUES BX'01010101';               -- bit string (仅部分版本)

-- 字符串连接
VALUES 'foo' || 'bar';             -- 'foobar'
-- 相邻字面量拼接（SQL 标准）
VALUES 'foo'
       'bar';                      -- 'foobar'（需换行）
```

### Snowflake：宽容的混合方言

Snowflake 同时接受标准 `''` 双写和反斜杠转义（默认启用），并且支持 dollar-quoting 作为 Python/JavaScript UDF 的便利语法：

```sql
-- 两种都接受（默认）
SELECT 'it''s ok';            -- 标准
SELECT 'it\'s ok';            -- 反斜杠

-- 反斜杠转义序列
SELECT '\n';                  -- 换行
SELECT '\t';                  -- 制表
SELECT '\\';                  -- 反斜杠
SELECT '\x41';                -- 'A'
SELECT 'é';              -- 'é'（4 位）
SELECT '\U0001f600';          -- '😀'（8 位，非 BMP）

-- 禁用反斜杠（会话级）
ALTER SESSION SET ESCAPE_UNENCLOSED_FIELD = 'NONE';  -- 仅 COPY 相关
-- Snowflake 没有严格的 NO_BACKSLASH_ESCAPES 开关

-- dollar-quoting（主要用于 UDF 定义）
CREATE OR REPLACE FUNCTION greet(name VARCHAR) RETURNS VARCHAR
LANGUAGE JAVASCRIPT AS $$
    return 'Hello, ' + NAME + "!";  // JS 内部随意用单双引号
$$;

-- N 前缀被识别但不区分：Snowflake 统一用 UTF-8
SELECT N'héllo';              -- 等同于 'héllo'
```

### BigQuery (GoogleSQL)：Python 风格的原始字符串

BigQuery 采用 GoogleSQL 方言，字符串规则最接近 Python：

```sql
-- 接受单引号和双引号定界（两者等价）
SELECT 'hello';
SELECT "hello";

-- 反斜杠转义（默认启用）
SELECT '\n';                      -- 换行
SELECT '\t';                      -- 制表
SELECT '\\';                      -- 反斜杠
SELECT '\x41';                    -- 'A'
SELECT 'é';                  -- 'é'
SELECT '\U0001f600';              -- '😀'

-- 原始字符串（raw string），反斜杠无特殊含义
SELECT r'\n';                     -- 2 字符：\n
SELECT R'C:\Users\foo';           -- Windows 路径无需双反斜杠
SELECT r"regex: \d+\.\d+";        -- 正则表达式友好

-- 三引号字符串（多行）
SELECT '''
multiple
lines
''';
SELECT """
also works with double quotes
""";
SELECT r'''raw \n multi
line''';

-- 字节字符串
SELECT b'\x00\x01\x02';           -- BYTES 类型
SELECT rb'\n';                    -- raw bytes

-- 十六进制字节字面量
SELECT b'\x48\x65\x6c\x6c\x6f';   -- 'Hello' 的字节
```

### Trino / Presto：严格的 SQL 标准

Trino（以及 Presto）严格遵循 SQL 标准，没有反斜杠转义：

```sql
-- 只支持双写转义
SELECT 'it''s ok';

-- 反斜杠无意义
SELECT '\n';                     -- 2 字符
SELECT length('\n');             -- 2

-- Unicode 字符串字面量（SQL 标准）
SELECT U&'caf\00E9';             -- 'café'
SELECT U&'d\+0001F600';          -- 😀
SELECT U&'caf!00E9' UESCAPE '!';

-- 十六进制字节
SELECT X'48656C6C6F';            -- VARBINARY: 'Hello' 字节

-- 字符串拼接
SELECT 'foo' || 'bar';
SELECT CONCAT('foo', 'bar', 'baz');

-- Trino 会话参数不能切换到反斜杠模式
-- 跨引擎迁移时从 MySQL 到 Trino 必须主动清洗 \n 为 CHR(10) 等
```

### DuckDB：PostgreSQL 兼容与扩展

DuckDB 对外标榜 PostgreSQL 兼容性，字符串字面量基本沿用 PG 规则，但有自己的简化：

```sql
-- 标准字符串
SELECT 'it''s ok';
SELECT '\n';                     -- 2 字符（不启用反斜杠）

-- 扩展转义字符串（PG 风格）
SELECT E'\n';                    -- 换行
SELECT E'\t\r\n';                -- C 风格
SELECT E'\x41';                  -- 'A'

-- 十六进制字节字面量（BLOB）
SELECT '\x48\x65\x6c\x6c\x6f'::BLOB;

-- DuckDB 支持 $$...$$ 作为函数定义体（与 PG 一致）
-- 但在一般 SELECT 中不推广使用
```

### Spark SQL / Databricks：可配置的转义

Spark SQL 允许通过会话参数切换字符串转义行为：

```sql
-- 默认：反斜杠转义启用
SELECT '\n';                     -- 换行
SELECT '\t';                     -- 制表
SELECT '\\';                     -- 反斜杠
SELECT 'é';                 -- 'é'

-- 原始字符串（r 前缀，3.0+）
SELECT r'\n';                    -- 2 字符
SELECT R'\regex\+pattern';

-- 切换到"转义字符串字面量"模式（禁用反斜杠转义）
SET spark.sql.parser.escapedStringLiterals = true;
-- 注意：命名有点反直觉，true 表示"保留转义序列不解释"
SELECT '\n';                     -- 2 字符
-- 这个选项主要为了向后兼容 Hive 早期版本

-- 十六进制字面量
SELECT X'48656C6C6F';            -- 二进制：Hello 字节
```

### ClickHouse：类 C 风格

ClickHouse 默认启用 C 风格反斜杠转义：

```sql
-- 单引号字符串，反斜杠默认转义
SELECT 'it''s ok';               -- 标准（ClickHouse 也支持）
SELECT 'it\'s ok';               -- 反斜杠
SELECT '\n';                     -- 换行
SELECT '\t\r\n\b\f\\\'\"\\0';    -- C 风格全套
SELECT '\x1b[31m';               -- 十六进制字节
SELECT 'é';                 -- 'é'

-- 十六进制字面量（二进制）
SELECT unhex('48656C6C6F');      -- 通过函数

-- ClickHouse 的 format 字面量用于插入二进制
INSERT INTO t FORMAT RawBLOB ...;
```

### CockroachDB：PostgreSQL 兼容 + 改进

CockroachDB 严格遵循 SQL 标准，但沿用 PostgreSQL 的 `E'..'` / `e'..'` 扩展语法：

```sql
-- 普通字符串（符合标准，反斜杠无意义）
SELECT 'it''s ok';
SELECT '\n';                     -- 2 字符

-- 扩展转义字符串
SELECT e'\n';                    -- 换行（e 或 E 都可）
SELECT e'\t\r\n';
SELECT e'\x41';                  -- 'A'
SELECT e'é';                -- 'é'
SELECT e'\U0001f600';            -- '😀'

-- dollar-quoting
SELECT $$it's ok$$;
SELECT $body$inner$$still ok$body$;

-- 十六进制字节字面量
SELECT b'\x48\x65\x6c\x6c\x6f';  -- BYTES
SELECT x'48656C6C6F';            -- 同样是 BYTES
```

### TiDB / OceanBase（MySQL 模式）

TiDB 在字符串处理上全面兼容 MySQL：

```sql
-- 默认启用反斜杠（与 MySQL 一致）
SELECT '\n';                     -- 换行
SELECT '\'';                     -- 单引号

-- 通过 sql_mode 切换
SET SESSION sql_mode = CONCAT(@@sql_mode, ',NO_BACKSLASH_ESCAPES');

-- 十六进制、二进制字面量
SELECT X'48656C6C6F';
SELECT 0x48656C6C6F;
SELECT B'01010101';
SELECT 0b01010101;

-- N 前缀（_utf8 introducer）
SELECT N'hello';
SELECT _utf8mb4 'héllo';
```

OceanBase 在 MySQL 模式下与 MySQL 一致，在 Oracle 模式下与 Oracle 一致（包括 Q'{..}'、UNISTR 等）。

### SAP HANA：严格 + N 前缀

```sql
-- 标准字符串
SELECT 'it''s ok' FROM DUMMY;

-- 反斜杠无意义
SELECT '\n' FROM DUMMY;          -- 2 字符

-- N 前缀：Unicode 字符串
SELECT N'héllo' FROM DUMMY;

-- 十六进制
SELECT X'48656C6C6F' FROM DUMMY;
```

## 历史：反斜杠转义引发的 SQL 注入灾难

### 为什么反斜杠是安全漏洞的温床

SQL 注入的经典场景：应用将用户输入拼接进 SQL 字符串。如果引擎启用反斜杠转义，看似安全的"双写单引号"防御可以被绕过：

```python
# 危险代码示例（概念，非具体语言）
user_input = request.form['name']
safe = user_input.replace("'", "''")   # 开发者以为这够了
sql = f"SELECT * FROM users WHERE name = '{safe}'"

# 攻击载荷：
# user_input = "\\'; DROP TABLE users; --"
# 转义后变成 "\\''; DROP TABLE users; --"
# 拼接后的 SQL：
#   SELECT * FROM users WHERE name = '\''; DROP TABLE users; --'
# 在 MySQL 默认模式下：
#   \\' 被解析为 \ + '
#   第一个 ' 被吃掉，字符串到 ''; 结束
#   后续语句 DROP TABLE users 被执行
```

### Zend/PHP 2006 mysql_real_escape_string 漏洞

历史上最著名的案例之一：某些多字节字符集（如 GBK、SJIS）与反斜杠组合可造成"吃掉反斜杠"。攻击者提交 `0xBF27`（GBK 中是合法字符，但末字节是 0x27 即 `'`），`mysql_real_escape_string` 按单字节处理会生成 `\xbf\x5c\x27`，MySQL 在 GBK 下解析 `\xbf\x5c` 为一个字符，留下独立的 `\x27` 作为字符串终结符。

补救措施：应用必须使用参数化查询（prepared statements），而不是字符串拼接。这是为何今天所有主流驱动（JDBC、libpq、go-sql-driver）都推荐参数绑定。

### NO_BACKSLASH_ESCAPES 的折中

MySQL 的 `NO_BACKSLASH_ESCAPES` 模式让字符串严格符合 SQL 标准，彻底关闭反斜杠的特殊含义。启用此模式后：

```sql
SET sql_mode = 'NO_BACKSLASH_ESCAPES';
INSERT INTO t VALUES ('C:\path');       -- 存储 "C:\path"
INSERT INTO t VALUES ('it\'s');          -- 语法错误！反斜杠无意义，末尾缺引号
INSERT INTO t VALUES ('it''s');          -- 正确
```

迁移阻力：几乎所有生产 MySQL 应用默认依赖反斜杠，切换需逐一审计。

### PostgreSQL 的优雅转型

PostgreSQL 在 2005-2011 年间完成了从"默认反斜杠"到"默认符合标准"的转型，核心手段是：

1. 引入 `E'..'` 前缀作为"我明确需要扩展转义"的标记
2. `standard_conforming_strings` GUC 渐进推广，先默认 `off` 告警，再默认 `on`
3. `escape_string_warning` 对含反斜杠的普通字符串发出警告，推动迁移

今天 PostgreSQL 是在"标准符合"与"实用转义"之间做到最好的分离的引擎之一。

## Unicode 字符串字面量（SQL:2008 标准）

### 语法结构

SQL:2008 规定：

```
<Unicode character string literal> ::=
    [ <introducer> <character set specification> ]
    U & <quote> [ <Unicode representation>... ] <quote>
    [ { <separator>... <quote> [ <Unicode representation>... ] <quote> }... ]
    [ ESCAPE <character escape character> ]

<Unicode representation> ::=
    <character representation>
  | <Unicode escape value>

<Unicode escape value> ::=
    <Unicode 4 digit escape value>
  | <Unicode 6 digit escape value>
  | <Unicode character escape value>

<Unicode 4 digit escape value> ::=
    <Unicode escape character> <hexit><hexit><hexit><hexit>

<Unicode 6 digit escape value> ::=
    <Unicode escape character> <plus sign> <hexit><hexit><hexit><hexit><hexit><hexit>

<Unicode character escape value> ::=
    <Unicode escape character> <Unicode escape character>
```

### 示例

```sql
-- PostgreSQL / DB2 / Trino
SELECT U&'caf\00E9';            -- 'café'（\XXXX 为 4 位十六进制）
SELECT U&'d\+0001F600';         -- '😀'（\+XXXXXX 为 6 位，超过 BMP）
SELECT U&'\0041\0042\0043';     -- 'ABC'

-- 转义反斜杠本身
SELECT U&'back\\slash';         -- 'back\slash'（两个 \ 表示一个）

-- 自定义转义字符
SELECT U&'caf!00E9' UESCAPE '!';     -- 'café'
SELECT U&'caf#00E9' UESCAPE '#';     -- 'café'

-- 标识符也支持（delimited identifier）
SELECT U&"column_caf\00E9" FROM t;
```

### 各引擎实现差异

| 特性 | PostgreSQL | DB2 | Trino | Materialize | RisingWave |
|------|-----------|-----|-------|-------------|-----------|
| `\XXXX` 4 位 | 是 | 是 | 是 | 是 | 是 |
| `\+XXXXXX` 6 位 | 是 | 是 | 是 | 是 | 是 |
| `UESCAPE '!'` | 是 | 是 | 是 | 是 | 是 |
| 标识符中的 U& | 是 | 是 | 是 | 是 | 是 |
| 拒绝非法代码点 | 是 | 是 | 是 | 是 | 是 |
| 字符串连接 | `\|\|` | `\|\|` | `\|\|` | `\|\|` | `\|\|` |

### 使用场景

- 源码编辑器不支持某些字符的输入
- SQL 脚本需通过只支持 ASCII 的管道（邮件、某些版本控制钩子）
- 跨平台脚本，避免字符集解释歧义（某一客户端认为是 Latin-1 vs 另一客户端认为是 UTF-8）
- 测试特殊字符（如零宽空格、方向标记）

## 字符串连接与相邻字面量拼接

### SQL 标准：相邻字面量自动拼接

SQL-92 规定两个相邻的字符串字面量（中间仅有空白和注释）自动拼接：

```sql
-- SQL 标准写法
SELECT 'line 1 '
       'line 2';        -- 结果：'line 1 line 2'

-- 支持的引擎
-- PostgreSQL, DB2, Trino, MySQL, Oracle, SQL Server(仅部分), HSQLDB
```

这是个常被忽视的特性，主要价值在于**多行 SQL 的长字符串拆分**，不改变语义。

### 显式连接运算符

| 语法 | 支持引擎 | 标准 |
|------|---------|------|
| `\|\|` | PostgreSQL, Oracle, DB2, SQLite, Snowflake, BigQuery, Trino, Spark 4+ | SQL-92 标准 |
| `+` | SQL Server, Sybase, 某些老旧引擎 | 非标准 |
| `CONCAT(a, b, c, ...)` | MySQL, SQL Server 2012+, PostgreSQL, 等 | SQL-99 引入 |
| `CONCAT_WS(sep, a, b, ...)` | MySQL, PostgreSQL, 大部分大数据引擎 | 非标准但普及 |

### NULL 与连接的行为分歧

```sql
-- SQL 标准：NULL || 'x' => NULL
SELECT NULL || 'x';             -- NULL (PG, Oracle, DB2)

-- MySQL 使用 CONCAT：任一参数为 NULL 则整体为 NULL（与标准一致）
SELECT CONCAT(NULL, 'x');        -- NULL (MySQL)

-- PostgreSQL CONCAT 函数：忽略 NULL（与标准不一致！）
SELECT concat(NULL, 'x');        -- 'x' (PG)

-- SQL Server +: NULL 传染
SELECT NULL + 'x';               -- NULL (除非 CONCAT_NULL_YIELDS_NULL=OFF，已废弃)
SELECT CONCAT(NULL, 'x');        -- 'x' (SQL Server CONCAT 忽略 NULL)

-- BigQuery CONCAT：任一 NULL 则 NULL
SELECT CONCAT(NULL, 'x');        -- NULL
```

这是跨引擎字符串处理最常见的陷阱之一。

## 关键发现

1. **所有引擎都支持 `''` 双写**：SQL 标准的最小公分母，是最安全的转义方式
2. **反斜杠转义是 MySQL 系的标志**：MySQL、MariaDB、TiDB、OceanBase（MySQL 模式）、SingleStore、Spark（默认）、ClickHouse、BigQuery、Snowflake 启用；PG 系、SQL Server、Oracle、DB2、Trino、SQLite、DuckDB 不启用
3. **`E'..'` 是 PG 方言的"明确转义"入口**：不受 GUC 影响，在 CockroachDB、Redshift、Greenplum、Vertica、Materialize、RisingWave、YugabyteDB 中同样支持
4. **`N'..'` 的语义跨引擎不一致**：SQL Server/Oracle 表示 nvarchar/nchar，MySQL 表示 `_utf8` introducer（而非 `_utf8mb4`），Snowflake 识别但无区别
5. **`U&'..'` 是最规范的 Unicode 转义**：PostgreSQL、DB2、Trino、Materialize、RisingWave 严格支持，其他引擎多数通过 `\uXXXX`（反斜杠模式下）折中实现
6. **`Q'{..}'` 是 Oracle 的独门武器**：NQ 组合提供 Unicode 版本；MySQL/PG 通过 dollar-quoting 或不同方案填补
7. **`$$...$$` dollar-quoting 基本是 PG 生态的标志**：PostgreSQL、Greenplum、CockroachDB、YugabyteDB、Materialize、RisingWave、Databend 支持；Snowflake 主要用于 UDF 体
8. **BigQuery 的 `r'..'`/`R'..'` 原始字符串在正则和路径场景是杀手锏**：Spark SQL 3.0+ 跟进，其他引擎多数无对应
9. **十六进制字面量 `X'..'` 普及**：几乎所有引擎支持；`0x..` 是 MySQL/SQL Server/H2/SQLite 的 C 风格扩展
10. **字符串连接标准是 `\|\|`**：SQL Server、MySQL 是最显眼的例外（用 `+`/`CONCAT`）
11. **NULL 在连接中的行为差异是迁移噩梦**：PG 的 `concat` 函数忽略 NULL 但 `||` 传染，MySQL 的 `CONCAT` 传染，需要统一用 `COALESCE` 预处理
12. **SQL 注入的根源是"字符串拼接 SQL"本身**：即便使用正确的转义，多字节字符集、Unicode 规范化、引擎 bug 都可能打破转义假设。参数化查询（prepared statement）是唯一正解
13. **跨引擎 SQL 生成策略**：默认仅用 `''` 双写；Unicode 用 `U&'..'`（严格标准）或十六进制字节；避免反斜杠；避免依赖相邻字面量自动拼接
14. **引擎迁移要点**：MySQL→PG 必须清洗 `\n` 等为 `E'\n'` 或 `CHR(10)`；PG→SQL Server 要把 `||` 改成 `+`/`CONCAT`，把 `E'..'` 解展开；SQL Server→MySQL 要把 nvarchar 字面量的 `N'..'` 保留或改成 `CONVERT USING utf8mb4`
15. **SQL:2008 Unicode 字符串字面量是最佳跨引擎 Unicode 方案**：但只有少数引擎严格支持，实用上更可行的跨引擎方案是显式使用代码点的函数（`CHR(x)`、`NCHAR(x)`、`CHAR(x)`）

## 对引擎开发者的实现建议

### 1. 词法分析器的设计原则

字符串字面量是 SQL 词法分析中最复杂的部分之一。核心要点：

```
1. 单引号是字符串定界符；双引号是标识符定界符（SQLite 的例外是历史包袱）
2. 遇到 ' 后进入"字符串状态"
3. 字符串状态内看到 '：
   - 下一个字符也是 '：消耗两个 '，输出一个 '，继续字符串状态
   - 下一个字符不是 '：字符串结束
4. 反斜杠处理需要运行时配置（standard_conforming_strings 等）
5. 前缀处理（E'..'、N'..'、U&'..'、B'..'、X'..'、r'..'）需要在词法层向前看
```

### 2. 处理相邻字面量拼接

```
pg_parser 中的做法：
1. 扫描到第一个字符串结束后，先 skip 空白/注释
2. 若紧跟另一个字符串字面量（无论前缀是否相同），进入"拼接状态"
3. 拼接时前缀规则需一致化（E'..' 'x' 的 'x' 是否也按 E 规则解析？各引擎不同）
```

PostgreSQL 的规则是：相邻字面量必须**分行**（中间有换行符），仅空格不够。这是为了避免误拼接。

### 3. Unicode 验证

```
U&'..' 解析时需：
1. 将 \XXXX 转换为 UTF-8 字节序列
2. 验证代码点合法性（< U+10FFFF；排除 surrogates U+D800-U+DFFF）
3. UTF-16 surrogate pair 必须配对
4. 非法代码点：报错（ERROR: invalid Unicode code point）
```

### 4. 性能考量

```
1. 字符串字面量解析在热路径上（每条查询至少一次）
2. 避免对普通字符串做转义处理（标准字符串不包含转义）
3. SIMD 加速：用 AVX2 扫描单引号和反斜杠的位置
4. 字符串常量池：同一 SQL 中出现的相同字面量可共享内存
```

### 5. 跨引擎兼容模式

若引擎提供 MySQL/PostgreSQL/Oracle 兼容模式：

```
1. MySQL 模式：默认启用反斜杠，但提供 NO_BACKSLASH_ESCAPES
2. PostgreSQL 模式：默认符合标准，支持 E'..'/U&'..'/ $$ 等
3. Oracle 模式：支持 q'{..}'、NQ'{..}'、UNISTR()
4. 兼容模式切换必须是会话级，不能影响其他会话
5. 在 EXPLAIN 输出中应标注当前使用的转义模式
```

### 6. 错误消息友好度

```
常见错误需明确提示：
- 未终结字符串：'ERROR: unterminated quoted string at or near ...'
- 非法 Unicode 代码点：'ERROR: invalid Unicode code point U+D800'
- 非法反斜杠序列：'ERROR: invalid escape sequence \\q'（在 E'..' 模式下）
- 混合前缀错误：'ERROR: cannot combine N prefix with X prefix'
```

### 7. 测试矩阵

引擎应有完整的字符串字面量测试矩阵，至少覆盖：

```
基础：
- 空字符串 ''
- 单字符 'a'
- 双写转义 'it''s ok'
- 纯 ASCII 长字符串（1MB+）

边界：
- 字符串中的换行符
- 字符串中的 NUL 字节（部分引擎禁止）
- 字符串中的代理对 Surrogates
- 超大代码点（U+10FFFF 边界）

前缀组合：
- E'..' 所有转义序列
- N'..' 字符集边界
- U&'..' 合法/非法代码点
- X'..' 奇数长度（应报错）

交互：
- 字符串字面量 + LIKE
- 字符串字面量 + JSON 函数
- 字符串字面量 + 正则
- UTF-8 字节长度 vs 字符长度
```

## 实用速查表

### 跨引擎"安全子集"写法

需要在多个引擎上运行的 SQL，推荐仅使用：

```sql
-- 1. 仅用 '' 双写转义
SELECT 'it''s ok';

-- 2. Unicode 字符直接内联（要求客户端/脚本/连接字符集为 UTF-8）
SELECT '中文 café 😀';

-- 3. 特殊字节用函数
SELECT CHAR(9) || 'tab-separated';   -- 除 SQL Server 外
SELECT CHR(9) || 'tab-separated';    -- PostgreSQL/Oracle

-- 4. 避免相邻字面量拼接（SQLite/ClickHouse 不支持）
SELECT 'part1' || 'part2';            -- 显式更安全

-- 5. 跨引擎 NULL 处理
SELECT COALESCE(col, '') || 'suffix';  -- 明确语义
```

### 字符串长度计算的三种语义

```sql
-- 字符数（CHAR_LENGTH / CHARACTER_LENGTH）：SQL 标准
SELECT CHAR_LENGTH('héllo');           -- 5（PostgreSQL/Oracle/DB2/Snowflake/Trino/BigQuery）

-- 字节数（OCTET_LENGTH）：SQL 标准
SELECT OCTET_LENGTH('héllo');          -- 6（UTF-8 下 é 占 2 字节）

-- MySQL 的 LENGTH：字节数（与 OCTET_LENGTH 同）
SELECT LENGTH('héllo');                -- 6（MySQL）
SELECT LENGTH('héllo');                -- 5（PostgreSQL，字符数！）

-- MySQL 的 CHAR_LENGTH：字符数
SELECT CHAR_LENGTH('héllo');           -- 5（MySQL）

-- SQL Server LEN（去尾随空格！）vs DATALENGTH（字节数）
SELECT LEN('héllo ');                   -- 5（去掉尾随空格）
SELECT DATALENGTH('héllo ');            -- 6（VARCHAR，含空格）
SELECT DATALENGTH(N'héllo ');           -- 12（NVARCHAR 每字符 2 字节）
```

### 字符字面量工具

引擎常用的"产生特殊字符"函数：

| 引擎 | 产生字符 | 十六进制输入 | 产生字符（代码点） |
|------|--------|-------------|-----------------|
| PostgreSQL | `CHR(10)` | `'\x0A'::bytea` | `CHR(233)` = é |
| MySQL | `CHAR(10)` | `X'0A'` | `CHAR(233 USING utf8mb4)` |
| Oracle | `CHR(10)` | -- | `UNISTR('\00E9')` |
| SQL Server | `CHAR(10)` | `0x0A` | `NCHAR(233)` |
| SQLite | `CHAR(10)` | `x'0A'` | `CHAR(233)` |
| DB2 | `CHR(10)` | `X'0A'` | `U&'\00E9'` |
| Snowflake | `CHR(10)` | -- | `CHR(233)` |
| BigQuery | `CHR(10)` | `b'\x0a'` | `CHR(233)` |
| Trino | `CHR(10)` | `X'0A'` | `U&'\00E9'` |
| DuckDB | `CHR(10)` | `'\x0A'` | `CHR(233)` |

## 设计争议

### 反斜杠转义该默认启用吗？

支持默认启用：

- C 语言开发者的本能，学习曲线平缓
- MySQL、Spark、BigQuery 的事实标准
- 嵌入换行符、制表符等更直观

反对默认启用：

- 违反 SQL 标准
- SQL 注入的历史重灾区
- 跨引擎迁移的主要痛点之一
- PG 的 `E'..'` 前缀已是良好折中

**结论**：新引擎若无特别理由，应默认**关闭**反斜杠转义（符合 SQL 标准），并提供 `E'..'` 或类似前缀以备需要。

### 双引号字符串（"hello" 作为字符串）

SQLite 为兼容 MS Access 容忍了双引号包围的字符串，MySQL 在某些 `sql_mode` 下也曾如此。标准 SQL 中双引号**仅用于定界标识符**。

混淆的代价：`SELECT "name" FROM t` 在大多数引擎中是"查询 name 列"，在某些 SQLite 模式下是"返回字符串 'name'"。

**建议**：始终用单引号表示字符串，双引号仅用于标识符，跨引擎最安全。

### Dollar-quoting 的"传染"

PostgreSQL 的 `$$...$$` 在函数体内嵌入 SQL 时，内部若有 `$$` 字面量会提前终结，需要用带标签的 `$tag$...$tag$`。这个"选标签"的决策经常被吐槽不直观。

相比之下，Oracle 的 `q'{..}'` 的优势是**自动选择配对定界符**（大括号、方括号、圆括号、尖括号各自配对），内部只有完全相同的 `}'` 才会终结。

### Unicode 字符串字面量的推广障碍

`U&'caf\00E9'` 在视觉上不如 `E'café'` 简洁，是该语法普及度低的主要原因之一。新引擎倾向于抄 C 风格（Spark、BigQuery、ClickHouse），而非 SQL 标准。

这种"事实标准与官方标准分叉"是 SQL 生态的持续话题。

## 参考资料

- SQL:1992 标准: ISO/IEC 9075:1992, Section 5.3 (character string literal)
- SQL:2003 标准: ISO/IEC 9075-2, Section 5.3 (Unicode character string literal)
- PostgreSQL: [Lexical Structure](https://www.postgresql.org/docs/current/sql-syntax-lexical.html#SQL-SYNTAX-STRINGS)
- PostgreSQL: [E'..' and standard_conforming_strings](https://www.postgresql.org/docs/current/runtime-config-compatible.html)
- MySQL: [String Literals](https://dev.mysql.com/doc/refman/8.0/en/string-literals.html)
- MySQL: [NO_BACKSLASH_ESCAPES](https://dev.mysql.com/doc/refman/8.0/en/sql-mode.html#sqlmode_no_backslash_escapes)
- Oracle: [q-quote Mechanism](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Text-Literals.html)
- SQL Server: [Constants - String](https://learn.microsoft.com/en-us/sql/t-sql/data-types/constants-transact-sql)
- SQLite: [SQL As Understood By SQLite](https://www.sqlite.org/lang_expr.html#literal_values_constants_)
- DB2: [String constants](https://www.ibm.com/docs/en/db2/11.5?topic=constants-string)
- Snowflake: [String Constants / Dollar-Quoted String Constants](https://docs.snowflake.com/en/sql-reference/data-types-text)
- BigQuery: [Lexical Structure](https://cloud.google.com/bigquery/docs/reference/standard-sql/lexical)
- Trino: [Data Types - Character](https://trino.io/docs/current/language/types.html)
- CockroachDB: [SQL Constants](https://www.cockroachlabs.com/docs/stable/sql-constants.html)
- Spark SQL: [Literals](https://spark.apache.org/docs/latest/sql-ref-literals.html)
- ClickHouse: [String Literals](https://clickhouse.com/docs/en/sql-reference/syntax#string)
- Christian Brenn / CVE-2006-2314: GBK/SJIS SQL injection via mysql_real_escape_string
- OWASP: [SQL Injection Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/SQL_Injection_Prevention_Cheat_Sheet.html)
