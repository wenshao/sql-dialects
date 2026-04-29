# BOOLEAN 类型与三值逻辑 (BOOLEAN Type and Three-Valued Logic)

`BOOLEAN` 看似是 SQL 中最简单的类型——只有两个真值 TRUE 和 FALSE，外加 NULL，加起来不过三种状态。但翻开 45+ 个 SQL 引擎的实现，你会发现这是一片采用极不均衡的"灰色地带"：PostgreSQL 自 6.x 就有原生 `BOOLEAN`；MySQL 把 `BOOLEAN` 偷偷映射成 `TINYINT(1)`；SQL Server 至今没有 `BOOLEAN`，只有 `BIT`；而 Oracle 在 2024 年发布的 23ai 之前，SQL 层根本无法声明布尔列（PL/SQL 倒是早早就有了）。SQLite 干脆不区分，直接把 0/1 存成 INTEGER。

跨引擎迁移时，BOOLEAN 列的语义差异是仅次于 NULL 处理的"沉默错误"来源。本文系统梳理 SQL 标准定义、各引擎采用情况、3VL（三值逻辑）真值表，以及 Oracle 23ai 的"姗姗来迟"。

## 开篇：BOOLEAN 类型的"非典型"采用史

很少有 SQL 类型像 BOOLEAN 这样，在数据库历史上呈现如此不规则的采用曲线：

- **1992**: SQL:1992 标准明确**未**包含 BOOLEAN 类型（这是最初的反讽）
- **1995**: SQL Server 6.0 引入 `BIT` 类型作为布尔替代（早于 SQL:1999 标准）
- **1996/1997**: PostgreSQL 6.x 引入原生 `BOOLEAN`（早于 SQL:1999 但已实现 TRUE/FALSE/UNKNOWN 的标准语义）
- **1999**: SQL:1999 标准（ISO/IEC 9075-2:1999）正式引入 `BOOLEAN` 类型，但作为可选特征 T031
- **2004**: MySQL 4.1 引入 `BOOLEAN` 关键字，但实际只是 `TINYINT(1)` 的别名
- **2016**: DB2 11.1 引入原生 `BOOLEAN`（IBM 长期使用 SMALLINT 代替）
- **2022-03**: ClickHouse 22.3 引入 `Bool` 类型（之前用 `UInt8`）
- **2024**: Oracle 23ai (Database 23c) 终于在 SQL 层引入 `BOOLEAN`（PL/SQL 自 v7 即支持）

这条时间线揭示了一个深刻的现实：**BOOLEAN 是 SQL 标准中采用最慢、最不一致的基础类型之一**。其根本原因在于：

1. **SQL:1992 标准未定义 BOOLEAN**，导致早期商用数据库各自实现替代方案
2. **存储优化驱使各引擎使用 BIT/TINYINT** 而非显式布尔
3. **SQL 标准的三值逻辑（含 UNKNOWN）与 NULL 的关系**让 BOOLEAN 比看起来要复杂
4. **历史包袱**：迁移和兼容性需求压倒了重新引入新类型的动力

## SQL 标准定义

### SQL:1999 引入 BOOLEAN

SQL:1999（ISO/IEC 9075-2:1999, 第 4.4 节）首次将 BOOLEAN 列入标准类型体系。其规范：

```sql
<boolean type> ::= BOOLEAN

<boolean literal> ::= TRUE | FALSE | UNKNOWN

<boolean value expression> ::=
    <boolean term>
    | <boolean value expression> OR <boolean term>
```

标准的关键语义：

1. **三个真值**：`TRUE`、`FALSE`、`UNKNOWN`
2. **`UNKNOWN` 与 NULL 等价**：标准明确规定 `UNKNOWN` 字面量可与 NULL 互换
3. **逻辑运算遵循三值逻辑**：AND / OR / NOT 按 3VL 真值表求值
4. **WHERE / CHECK / ON 子句**：仅 TRUE 通过，FALSE 和 UNKNOWN 都被拒绝
5. **可比较性**：BOOLEAN 与 BOOLEAN 之间可进行 `=`、`<>`、`<`、`>`、`<=`、`>=` 比较（TRUE > FALSE）
6. **隐式类型转换**：标准不强制要求 BOOLEAN ↔ INTEGER 的隐式转换

### 特征 T031（BOOLEAN data type）

SQL:1999 将 BOOLEAN 列为**可选特征 T031**（"BOOLEAN data type"），这意味着合规实现**不强制**支持。这个"可选"标签直接导致了后续二十多年的采用混乱。

```
特征 ID:   T031
名称:      BOOLEAN data type
类型:      可选
要求:      实现 BOOLEAN 类型、TRUE/FALSE/UNKNOWN 字面量、3VL 求值
```

### SQL:2003 与之后的细化

SQL:2003 进一步细化：

- BOOLEAN 与字符串的转换规则（`CAST(boolean AS VARCHAR)` 返回 `'TRUE'` / `'FALSE'` / `'UNKNOWN'`）
- BOOLEAN 字面量在 INSERT、UPDATE 中的使用
- `IS TRUE` / `IS FALSE` / `IS UNKNOWN` 谓词

## 支持矩阵：45+ 引擎全景

### 原生 BOOLEAN 与替代类型对照表

下面这张表覆盖 45+ 个 SQL 引擎，列出每个引擎的布尔表达方式、TRUE/FALSE 字面量支持、隐式整数转换行为，以及标准化时间线：

| 引擎 | 原生 BOOLEAN | 替代类型 | TRUE/FALSE 字面量 | NULL 行为 | 隐式转 INT | 引入版本 |
|------|------------|---------|------------------|----------|-----------|---------|
| PostgreSQL | 是 | -- | 是 (`TRUE`/`FALSE`) | 标准 3VL | 否（需 CAST） | 6.x (1996) |
| MySQL | 别名 | `TINYINT(1)` | 是 (`TRUE`=1/`FALSE`=0) | 标准 3VL | 是 | 4.1 (2004) |
| MariaDB | 别名 | `TINYINT(1)` | 是 (1/0) | 标准 3VL | 是 | 全版本（继承 MySQL）|
| SQLite | 否 | `INTEGER` (0/1) | 是 (3.23+ 关键字) | 标准 3VL | 是 | 3.23 (2018) 关键字 |
| Oracle | 是 (SQL 层) | 之前用 NUMBER(1)/CHAR(1) | 是 | 标准 3VL | 否 | **23ai (2024)** |
| SQL Server | 否 | `BIT` (NULL/0/1) | 否（用 1/0 或字符串） | 类似 3VL | 是 | BIT 自 6.0 (1995) |
| DB2 (LUW) | 是 | -- | 是 | 标准 3VL | 否 | 11.1 (2016) |
| DB2 i / z | 是 | 之前用 SMALLINT | 是 | 标准 3VL | 否 | 较新版本 |
| Snowflake | 是 | -- | 是 (大量字符串字面量) | 标准 3VL | 是（双向） | 全版本 |
| BigQuery | 是 (`BOOL`) | -- | 是 (`TRUE`/`FALSE`) | 标准 3VL | 否（需 CAST） | 全版本 |
| Redshift | 是 | -- | 是 (含 `'t'`/`'f'`/`'yes'`/`'no'`) | 标准 3VL | 否 | 全版本 |
| DuckDB | 是 | -- | 是 | 标准 3VL | 否（需 CAST） | 早期 |
| ClickHouse | 是 (`Bool`) | 之前用 `UInt8` | 是 | 类似 3VL | 是（Bool ↔ UInt8） | **22.3 (2022-03)** |
| Trino | 是 | -- | 是 | 标准 3VL | 否 | 全版本 |
| Presto | 是 | -- | 是 | 标准 3VL | 否 | 全版本 |
| Spark SQL | 是 | -- | 是 | 标准 3VL | 否 | 全版本 |
| Hive | 是 | -- | 是 | 标准 3VL | 否 | 0.5+ |
| Flink SQL | 是 | -- | 是 | 标准 3VL | 否 | 全版本 |
| Databricks | 是 | -- | 是 | 标准 3VL | 否 | 全版本 |
| Teradata | 否 | `BYTEINT` 0/1 | 否 | -- | 是 | -- |
| Greenplum | 是 | -- | 是 | 标准 3VL | 否 | 全版本（继承 PG） |
| CockroachDB | 是 | -- | 是 | 标准 3VL | 否 | 全版本（PG 兼容） |
| TiDB | 别名 | `TINYINT(1)` | 是 | 标准 3VL | 是 | 全版本（MySQL 兼容） |
| OceanBase | 双模式 | MySQL: `TINYINT(1)`；Oracle: `NUMBER(1)` | 取决于模式 | 标准 3VL | MySQL 模式：是 | -- |
| YugabyteDB | 是 | -- | 是 | 标准 3VL | 否 | 全版本（PG 兼容） |
| SingleStore | 别名 | `TINYINT(1)` | 是 | 标准 3VL | 是 | 全版本（MySQL 兼容） |
| Vertica | 是 | -- | 是 (含 `'t'`/`'f'`) | 标准 3VL | 否 | 全版本 |
| Impala | 是 | -- | 是 | 标准 3VL | 否 | 全版本 |
| StarRocks | 是 | `TINYINT` 也常用 | 是 | 标准 3VL | 是（部分） | 全版本 |
| Doris | 是 | -- | 是 | 标准 3VL | 否 | 全版本 |
| MonetDB | 是 | -- | 是 | 标准 3VL | 否 | 全版本 |
| CrateDB | 是 | -- | 是 | 标准 3VL | 否 | 全版本 |
| TimescaleDB | 是 | -- | 是 | 标准 3VL | 否 | 全版本（继承 PG） |
| QuestDB | 是 | -- | 是 | 类似 3VL | 否 | 全版本 |
| Exasol | 是 | -- | 是 | 标准 3VL | 否 | 全版本 |
| SAP HANA | 是 | -- | 是 | 标准 3VL | 否 | 全版本 |
| Informix | 是 | 也支持 `CHAR(1)` 'T'/'F' | 是 | 标准 3VL | 否 | 全版本 |
| Firebird | 是 | -- | 是 | 标准 3VL | 否 | 3.0+ (2016) |
| H2 | 是 | -- | 是 | 标准 3VL | 否 | 全版本 |
| HSQLDB | 是 | -- | 是 | 标准 3VL | 否 | 全版本 |
| Derby | 是 | -- | 是 | 标准 3VL | 否 | 10.7+ (2011) |
| Amazon Athena | 是 | -- | 是 | 标准 3VL | 否 | 全版本（继承 Trino） |
| Azure Synapse | 否 | `BIT` | 否 | 类似 3VL | 是 | -- |
| Google Spanner | 是 (`BOOL`) | -- | 是 | 标准 3VL | 否 | 全版本 |
| Materialize | 是 | -- | 是 | 标准 3VL | 否 | 全版本（PG 兼容） |
| RisingWave | 是 | -- | 是 | 标准 3VL | 否 | 全版本（PG 兼容） |
| InfluxDB (SQL) | 是 | -- | 是 | 类似 3VL | 否 | IOx 引擎 |
| DatabendDB | 是 | -- | 是 | 标准 3VL | 否 | 全版本 |
| Yellowbrick | 是 | -- | 是 | 标准 3VL | 否 | 全版本 |
| Firebolt | 是 | -- | 是 | 标准 3VL | 否 | 全版本 |

> 统计概要：
> - 约 35 个引擎提供原生 `BOOLEAN`（含 `BOOL` 等同名变体）
> - 4 个引擎用别名（MySQL、MariaDB、TiDB、SingleStore，本质都是 TINYINT(1)）
> - 3 个引擎仅有 `BIT`（SQL Server、Azure Synapse）或 `BYTEINT`（Teradata）作为替代
> - 1 个引擎（SQLite）完全无 BOOLEAN 概念，仅在 3.23 后将 TRUE/FALSE 作为关键字识别

### 字符串字面量识别能力

各引擎对字符串到布尔的"宽容度"差异巨大：

| 引擎 | `'true'/'false'` | `'t'/'f'` | `'yes'/'no'` | `'y'/'n'` | `'1'/'0'` | `'on'/'off'` |
|------|-----------------|----------|-------------|----------|-----------|-------------|
| PostgreSQL | 是 | 是 | 是 | 是 | 是 | 是 |
| Redshift | 是 | 是 | 是 | 是 | 是 | 是 |
| Vertica | 是 | 是 | 是 | 是 | 是 | 是 |
| Snowflake | 是 | 是 | 是 | 是 | 是 | 是 |
| MySQL | -- (整数语义) | -- | -- | -- | 是 | -- |
| SQL Server | -- | -- | -- | -- | 是 | -- |
| DB2 | 是 | 否 | 否 | 否 | 否 | 否 |
| Oracle 23ai | 是 | 是 | 是 | 是 | 否 | 否 |
| SQLite | 是 (3.23+) | 否 | 否 | 否 | 是 | 否 |
| BigQuery | 是 | 否 | 否 | 否 | 否 | 否 |
| ClickHouse | 是 | 是 | 否 | 否 | 是 | 否 |
| Trino | 是 (CAST) | 否 | 否 | 否 | 否 | 否 |
| Spark SQL | 是 (CAST) | 否 | 否 | 否 | 否 | 否 |
| DuckDB | 是 (CAST) | 是 | 否 | 否 | 否 | 否 |
| H2 | 是 | 是 | 否 | 否 | 是 | 否 |

> PostgreSQL 是字符串字面量识别"最宽容"的引擎之一，连 `'on'`/`'off'` 都接受。这种宽容度在跨引擎迁移时是把双刃剑：导出端工作但导入端报错。

### NULL 在 WHERE / CHECK 中的行为

虽然几乎所有引擎都遵循"WHERE 仅保留 TRUE 行"的标准 3VL，但具体到 BOOLEAN 列的 NULL 处理仍有差异：

| 引擎 | `WHERE bool_col` (NULL → ?) | `WHERE NOT bool_col` (NULL → ?) | `IS TRUE` 谓词 | `IS FALSE` 谓词 | `IS UNKNOWN` 谓词 |
|------|---------------------------|--------------------------------|---------------|----------------|------------------|
| PostgreSQL | 过滤 (UNKNOWN) | 过滤 (UNKNOWN) | 是 | 是 | 是 |
| MySQL | 过滤 | 过滤 | 是 | 是 | 否（用 `IS NULL`） |
| Oracle 23ai | 过滤 | 过滤 | 是 | 是 | 是 |
| SQL Server | -- (BIT 不能直接用作条件) | -- | 否 | 否 | 否 |
| DB2 | 过滤 | 过滤 | 是 | 是 | 是 |
| Snowflake | 过滤 | 过滤 | 是 | 是 | 是 |
| BigQuery | 过滤 | 过滤 | 是 | 是 | 否（用 `IS NULL`） |
| Redshift | 过滤 | 过滤 | 是 | 是 | 是 |
| DuckDB | 过滤 | 过滤 | 是 | 是 | 是 |
| ClickHouse | 过滤 | 过滤 | 否（直接用比较） | 否 | 否 |
| Trino | 过滤 | 过滤 | 是 | 是 | 是 |
| Spark SQL | 过滤 | 过滤 | 否 | 否 | 否 |

注意 **SQL Server 的 BIT 不能直接作为 WHERE 条件**：必须写 `WHERE bit_col = 1`，否则报语法错误。这是 BIT 与真正的 BOOLEAN 最显著的区别之一。

### CHECK 约束中的处理

CHECK 约束是另一个三值逻辑陷阱常出之处。SQL 标准规定：CHECK 只在求值为 FALSE 时拒绝，UNKNOWN 视同 TRUE 接受（与 WHERE 相反！）：

```sql
-- 标准语义（与 WHERE 相反）
-- CHECK 约束: 求值为 TRUE 或 UNKNOWN 时通过, 仅 FALSE 时拒绝
CREATE TABLE t (x INT CHECK (x > 0));
INSERT INTO t VALUES (NULL);  -- 通过! (NULL > 0 = UNKNOWN, CHECK 视同接受)
```

| 引擎 | CHECK 对 UNKNOWN 行为 | 备注 |
|------|---------------------|------|
| PostgreSQL | 接受 (与标准一致) | -- |
| MySQL 8.0.16+ | 接受 | 8.0.16 之前 CHECK 被忽略 |
| Oracle | 接受 | -- |
| SQL Server | 接受 | -- |
| DB2 | 接受 | -- |
| SQLite | 接受 | -- |
| Snowflake | 不支持 CHECK | 仅做声明性记录 |
| BigQuery | 不支持 CHECK | -- |

## 各引擎深入：BOOLEAN 在生产环境的真实形态

### PostgreSQL：标准 BOOLEAN 的"教科书实现"

PostgreSQL 自 6.x 即支持原生 `BOOLEAN`，是 SQL 标准 3VL 最完整的开源实现：

```sql
-- 类型声明
CREATE TABLE accounts (
    id          SERIAL PRIMARY KEY,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    is_admin    BOOLEAN DEFAULT FALSE,
    has_premium BOOLEAN  -- 允许 NULL
);

-- 插入：支持多种字面量
INSERT INTO accounts (is_active, is_admin, has_premium) VALUES
    (TRUE,  FALSE, NULL),
    (true,  false, NULL),         -- 大小写不敏感
    ('t',   'f',   'unknown'),    -- 字符串识别
    ('yes', 'no',  NULL),
    ('y',   'n',   NULL),
    ('on',  'off', NULL),
    ('1',   '0',   NULL);

-- 查询：BOOLEAN 列可直接作为 WHERE 条件
SELECT * FROM accounts WHERE is_active;        -- 仅 TRUE
SELECT * FROM accounts WHERE NOT is_active;    -- 仅 FALSE
SELECT * FROM accounts WHERE is_active IS TRUE;
SELECT * FROM accounts WHERE has_premium IS UNKNOWN;  -- 等价于 IS NULL
SELECT * FROM accounts WHERE has_premium IS NULL;     -- 同上

-- 显示：默认显示为 't'/'f'
SELECT is_active FROM accounts;
-- t
-- t
-- f

-- 显式 CAST 输出
SELECT is_active::TEXT FROM accounts;       -- 'true' / 'false'
SELECT is_active::INT FROM accounts;        -- 1 / 0  (PG 9.0+)

-- 注意：PG 不允许 BOOLEAN 与 INT 隐式互转（除 CAST 外）
SELECT 1::INT + TRUE::INT;     -- 合法 (显式转换)
SELECT 1 + TRUE;               -- 错误: operator does not exist: integer + boolean
```

PostgreSQL 的 BOOLEAN 物理存储为 1 字节，但行格式可能因列对齐而占用更多空间。

### SQL Server：BIT 不是 BOOLEAN

SQL Server 至今（2025 年）没有 BOOLEAN 类型。`BIT` 是其唯一的"布尔替代"：

```sql
-- BIT 类型: 1 / 0 / NULL
CREATE TABLE accounts (
    id          INT IDENTITY(1,1) PRIMARY KEY,
    is_active   BIT NOT NULL DEFAULT 1,
    is_admin    BIT DEFAULT 0,
    has_premium BIT NULL
);

-- 插入：必须用 1/0，不能用 TRUE/FALSE
INSERT INTO accounts (is_active, is_admin, has_premium) VALUES
    (1, 0, NULL),
    (1, 1, 1);

-- 关键限制：BIT 不能直接作为条件
-- SELECT * FROM accounts WHERE is_active;  -- 错误！
SELECT * FROM accounts WHERE is_active = 1;  -- 必须显式比较
SELECT * FROM accounts WHERE is_active <> 0;

-- BIT 与字符串：仅识别 '0'/'1'/'true'/'false'
INSERT INTO accounts VALUES (DEFAULT, 'true', 'false', NULL);  -- 合法
INSERT INTO accounts VALUES (DEFAULT, 'yes', 'no', NULL);      -- 错误

-- BIT 在表达式中的隐式转换
SELECT CAST(1 AS BIT) + 1;       -- 2 (BIT → INT)
SELECT 1 + CAST(1 AS BIT);       -- 2

-- 多个 BIT 列的存储优化
-- SQL Server 自动将同一行中最多 8 个 BIT 列打包到 1 字节
CREATE TABLE flags (
    f1 BIT, f2 BIT, f3 BIT, f4 BIT,
    f5 BIT, f6 BIT, f7 BIT, f8 BIT,
    f9 BIT  -- 第 9 个 BIT 才占用第 2 字节
);
```

`BIT` 与真正 BOOLEAN 的核心差异：

1. **不能直接作为 WHERE 条件**（必须 `= 1` 或 `<> 0`）
2. **不接受 TRUE/FALSE 字面量**（仅 1/0/NULL）
3. **隐式参与算术运算**（与 INT 自动转换）
4. **存储为整数**（多列打包到字节）

这些差异让 SQL Server → PostgreSQL 的迁移工作量被严重低估。

### MySQL / MariaDB：TINYINT(1) 的"假 BOOLEAN"

MySQL 4.1（2004 年）引入 `BOOLEAN` 关键字，但**只是 `TINYINT(1)` 的别名**：

```sql
-- 这两条语句完全等价
CREATE TABLE accounts (is_active BOOLEAN);
CREATE TABLE accounts (is_active TINYINT(1));

-- 验证：通过 information_schema 查看
SELECT column_type FROM information_schema.columns
WHERE table_name = 'accounts' AND column_name = 'is_active';
-- 结果: tinyint(1)        ← BOOLEAN 痕迹完全消失！

-- TRUE / FALSE 关键字识别为 1 / 0
SELECT TRUE, FALSE;
-- +------+-------+
-- | TRUE | FALSE |
-- +------+-------+
-- |    1 |     0 |
-- +------+-------+

-- 因此 BOOLEAN 列可以存储任意 TINYINT 值
INSERT INTO accounts (is_active) VALUES (TRUE), (FALSE), (2), (-1), (127);
SELECT * FROM accounts;
-- 1, 0, 2, -1, 127  ← 不只是 0/1!

-- 这导致 WHERE 条件的语义陷阱
SELECT * FROM accounts WHERE is_active = TRUE;     -- 仅返回 1
SELECT * FROM accounts WHERE is_active = 1;        -- 仅返回 1
SELECT * FROM accounts WHERE is_active;            -- 返回 1, 2, -1, 127 (所有非零)
SELECT * FROM accounts WHERE is_active <> FALSE;   -- 返回 1, 2, -1, 127
```

**TINYINT(1) 的显示宽度陷阱**：

```sql
-- TINYINT(1) 的 "1" 是显示宽度，不限制取值范围
-- 它影响 ZEROFILL 时的左侧填充，对实际存储无影响
CREATE TABLE t (x TINYINT(1) ZEROFILL);
INSERT INTO t VALUES (5);    -- 显示为 5（宽度 1，不需要填充）
INSERT INTO t VALUES (15);   -- 仍显示为 15（超出宽度只是不填充）
INSERT INTO t VALUES (200);  -- 错误：超出 TINYINT 范围 (-128, 127) ✗
                            -- 但若 UNSIGNED：合法，显示为 200

-- MySQL 8.0.17+ 甚至废弃了 TINYINT(N) 的显示宽度
SHOW CREATE TABLE t;
-- 在 8.0.17 之前: TINYINT(1)
-- 在 8.0.17 之后: TINYINT  (显示宽度被忽略)
```

**ORM 工具的特殊处理**：

许多 ORM（如 Hibernate、SQLAlchemy、Django ORM）通过 `TINYINT(1)` 这个特定声明识别 BOOLEAN 字段。如果你写 `TINYINT(2)` 或 `TINYINT`（无显示宽度），ORM 可能不会将其识别为 boolean，造成应用层类型错乱。

JDBC 连接参数 `tinyInt1isBit=true`（默认 true）控制此行为：连接器把 TINYINT(1) 报告为 java.sql.Types.BIT。设为 false 则报告为 TINYINT。

```
迁移检查清单（MySQL → PG 时）:
1. 找出所有 TINYINT(1) / BOOLEAN 列
2. 验证实际值是否仅为 0/1
3. 应用代码是否依赖整数语义（例如 WHERE col = 2）
4. ORM 配置是否绑定 TINYINT(1)
5. JDBC 连接串中的 tinyInt1isBit 参数
```

### Oracle：迟到 27 年的 SQL 层 BOOLEAN

Oracle 是主流数据库中最后一个在 SQL 层支持 BOOLEAN 的——直到 **Oracle Database 23ai（2024 年 5 月发布）**。

#### 23ai 之前：唯一选项是模拟

```sql
-- Oracle 21c 及更早：SQL 层无 BOOLEAN
-- 选项 1: NUMBER(1) 0/1
CREATE TABLE accounts_v1 (
    id          NUMBER PRIMARY KEY,
    is_active   NUMBER(1) DEFAULT 1 CHECK (is_active IN (0, 1))
);

-- 选项 2: CHAR(1) 'Y'/'N' 或 'T'/'F'
CREATE TABLE accounts_v2 (
    id          NUMBER PRIMARY KEY,
    is_active   CHAR(1) DEFAULT 'Y' CHECK (is_active IN ('Y', 'N'))
);

-- 选项 3: VARCHAR2 'TRUE'/'FALSE'
CREATE TABLE accounts_v3 (
    is_active   VARCHAR2(5) CHECK (is_active IN ('TRUE', 'FALSE'))
);

-- 限制：所有这些方案下，列都不能直接作为 WHERE 条件
SELECT * FROM accounts_v1 WHERE is_active;  -- 错误：not boolean expression
SELECT * FROM accounts_v1 WHERE is_active = 1;  -- 必须显式比较
```

注意：Oracle 的 PL/SQL（即过程语言部分）**自 v7（1992 年）起就支持 BOOLEAN**：

```sql
-- PL/SQL 中合法（但 23ai 之前不能用于建表）
DECLARE
    v_active BOOLEAN := TRUE;
BEGIN
    IF v_active THEN
        DBMS_OUTPUT.PUT_LINE('Active');
    END IF;
END;

-- 关键限制（23ai 之前）：
-- 1. CREATE TABLE 不能用 BOOLEAN 列
-- 2. SELECT 语句不能返回 BOOLEAN
-- 3. 不能在 SQL 中使用 BOOLEAN 字面量 TRUE/FALSE
-- 4. PL/SQL 与 SQL 之间的 BOOLEAN 必须显式转换
```

这种 SQL 与 PL/SQL 的"双层人格"长期是 Oracle 的标志性槽点。

#### Oracle 23ai：终于在 SQL 层引入 BOOLEAN

```sql
-- Oracle 23ai (Database 23c) 新特性
CREATE TABLE accounts (
    id          NUMBER PRIMARY KEY,
    is_active   BOOLEAN DEFAULT TRUE NOT NULL,
    is_admin    BOOLEAN DEFAULT FALSE,
    has_premium BOOLEAN  -- 允许 NULL
);

-- 字面量
INSERT INTO accounts VALUES (1, TRUE, FALSE, NULL);
INSERT INTO accounts VALUES (2, true, false, NULL);
INSERT INTO accounts VALUES (3, 'TRUE', 'FALSE', 'UNKNOWN');
INSERT INTO accounts VALUES (4, 'T', 'F', NULL);
INSERT INTO accounts VALUES (5, 'YES', 'NO', NULL);
INSERT INTO accounts VALUES (6, 'Y', 'N', NULL);

-- BOOLEAN 列可直接作为 WHERE 条件（这是与之前最大的不同）
SELECT * FROM accounts WHERE is_active;
SELECT * FROM accounts WHERE NOT is_active;
SELECT * FROM accounts WHERE is_active IS TRUE;
SELECT * FROM accounts WHERE has_premium IS UNKNOWN;

-- 输出格式
SELECT is_active FROM accounts;
-- TRUE / FALSE （字符串形式输出）

-- 隐式整数转换：不支持
SELECT 1 + TRUE FROM dual;  -- 错误

-- 显式 CAST
SELECT CAST(TRUE AS NUMBER) FROM dual;     -- 1
SELECT CAST(FALSE AS NUMBER) FROM dual;    -- 0
SELECT CAST(1 AS BOOLEAN) FROM dual;        -- TRUE

-- 与 PL/SQL 的互操作终于无缝
DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM accounts WHERE is_active;  -- ← 23ai 才合法
END;
```

23ai 的 BOOLEAN 支持以下能力（之前都不支持）：

1. CREATE TABLE 中的 BOOLEAN 列
2. SELECT、INSERT、UPDATE 中的 BOOLEAN 字面量
3. WHERE / CHECK / ON 条件中直接使用
4. SELECT 输出中的 BOOLEAN 列
5. 与 PL/SQL 的双向无缝传递

这是 Oracle 数据库类型系统**自 v7 以来最重要的增强之一**，但代价是 27 年的等待。

### MySQL 4.1 的"伪布尔"：TINYINT(1) 的实际位宽

MySQL 在 4.1（2004 年）引入了 `BOOLEAN` 和 `BOOL` 关键字，TRUE 和 FALSE 字面量，看似合规——但表面之下是 `TINYINT(1)`：

```sql
CREATE TABLE flags (
    f1 BOOL,
    f2 BOOLEAN,
    f3 TINYINT(1)
);

DESCRIBE flags;
-- +-------+------------+------+-----+---------+-------+
-- | Field | Type       | Null | Key | Default | Extra |
-- +-------+------------+------+-----+---------+-------+
-- | f1    | tinyint(1) | YES  |     | NULL    |       |
-- | f2    | tinyint(1) | YES  |     | NULL    |       |
-- | f3    | tinyint(1) | YES  |     | NULL    |       |
-- +-------+------------+------+-----+---------+-------+

-- 三列在底层完全等价
```

**陷阱清单**：

```sql
-- 陷阱 1: 可存储任意整数 (-128 ~ 127)
INSERT INTO flags VALUES (5, 100, -1);   -- 全部成功！

-- 陷阱 2: TRUE != 5 (尽管两者都是真值)
SELECT 5 = TRUE, 5 != FALSE;
-- 0, 1
-- 解释：5 = TRUE 实际为 5 = 1 = 0 (false)
--      5 != FALSE 实际为 5 != 0 = 1 (true)
--      不一致！

-- 陷阱 3: ORM 假设 TINYINT(1) 总是 boolean
-- 当某行被人为塞入 2 时，应用读取得到 true，但 update 后端可能强制 0/1

-- 陷阱 4: 显示宽度不限制取值
INSERT INTO flags VALUES (127, 100, 50);  -- 全部成功！

-- 陷阱 5: MySQL 8.0.17+ 显示宽度被废弃
-- SHOW CREATE TABLE 不再显示 (1)，但语义保留
```

**官方迁移建议**：使用 `TINYINT(1) UNSIGNED CHECK (col IN (0, 1))` 强约束 + 应用层防御。

### DB2：BOOLEAN 的"姗姗来迟"（11.1, 2016）

IBM DB2 LUW 在 **11.1（2016 年）**引入 BOOLEAN，之前长期使用 SMALLINT 模拟。

```sql
-- DB2 11.1+
CREATE TABLE accounts (
    id          INT NOT NULL,
    is_active   BOOLEAN DEFAULT TRUE NOT NULL,
    is_admin    BOOLEAN DEFAULT FALSE,
    has_premium BOOLEAN
);

INSERT INTO accounts VALUES (1, TRUE, FALSE, NULL);
INSERT INTO accounts VALUES (2, 'TRUE', 'FALSE', NULL);  -- 字符串字面量

-- 直接用作条件
SELECT * FROM accounts WHERE is_active;
SELECT * FROM accounts WHERE is_active IS TRUE;
SELECT * FROM accounts WHERE has_premium IS UNKNOWN;

-- 11.1 之前的常用模式
CREATE TABLE accounts_old (
    id          INT,
    is_active   SMALLINT DEFAULT 1 CHECK (is_active IN (0, 1))
);
```

DB2 z/OS 和 IBM i 直到更晚的版本才有 BOOLEAN，这两个平台的 SQL 兼容性常常滞后于 LUW。

### ClickHouse：从 UInt8 到 Bool（22.3, 2022 年 3 月）

ClickHouse 早期没有 BOOLEAN，约定俗成使用 `UInt8`：

```sql
-- ClickHouse 22.3 之前
CREATE TABLE events (
    id UInt64,
    is_processed UInt8 DEFAULT 0  -- 模拟 boolean
) ENGINE = MergeTree() ORDER BY id;
```

22.3 引入了 `Bool` 类型（注意是 `Bool`，不是 `BOOLEAN`）：

```sql
-- ClickHouse 22.3+
CREATE TABLE events (
    id UInt64,
    is_processed Bool DEFAULT false
) ENGINE = MergeTree() ORDER BY id;

-- 字面量：true / false（小写优先）
INSERT INTO events VALUES (1, true), (2, false), (3, 1), (4, 0);

-- Bool 与 UInt8 双向隐式转换
SELECT toUInt8(true), toBool(1);
-- 1, true

-- 内部存储仍是 1 字节
SELECT count() FROM events WHERE is_processed;
```

ClickHouse 的 Bool 与标准 BOOLEAN 的差异：

1. 名称为 `Bool`（而非 `BOOLEAN`）
2. Nullable 必须显式声明（`Nullable(Bool)`）
3. 与 UInt8 的隐式转换比标准 BOOLEAN 更宽松
4. 列存储下，Bool 列的压缩率优于 String('true'/'false')

### SQLite：永远没有真正的 BOOLEAN

SQLite 的类型系统本质是动态的（"类型亲和性"）：

```sql
-- SQLite 没有原生 BOOLEAN，所有数据落入五大存储类
-- NULL / INTEGER / REAL / TEXT / BLOB

CREATE TABLE accounts (
    id INTEGER PRIMARY KEY,
    is_active BOOLEAN  -- 这里 BOOLEAN 仅是文字标签
);

-- 列亲和性是 NUMERIC（基于 BOOLEAN 字符串包含 'INT'）
-- 实际存储：值若为整数则存为 INTEGER

INSERT INTO accounts VALUES (1, TRUE);   -- 存为 1 (INTEGER)
INSERT INTO accounts VALUES (2, FALSE);  -- 存为 0 (INTEGER)
INSERT INTO accounts VALUES (3, 'true'); -- 存为 'true' (TEXT)！

SELECT typeof(is_active) FROM accounts;
-- integer
-- integer
-- text         ← 不一致

-- 不能直接用作 WHERE 条件（因为它就是 INTEGER）
SELECT * FROM accounts WHERE is_active;
-- 返回 id=1 (1 为真), id=3 ('true' 文本被识别为非数值的真)
-- 实际行为依赖 SQLite 版本和配置

-- 3.23+ 增加了 TRUE / FALSE 关键字识别
SELECT TRUE = 1, FALSE = 0;
-- 1 | 1   (3.23+)
```

**SQLite 的 boolean 储存指南**：

```sql
-- 推荐做法 1: 用 0/1 INTEGER + CHECK
CREATE TABLE accounts (
    id INTEGER PRIMARY KEY,
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1))
);

-- 推荐做法 2: 使用 SQLite 的 STRICT 表（3.37+）
CREATE TABLE accounts (
    id INTEGER PRIMARY KEY,
    is_active INTEGER NOT NULL CHECK (is_active IN (0, 1))
) STRICT;
-- STRICT 模式下类型严格检查
```

### Snowflake：真正的 BOOLEAN，识别能力最强

Snowflake 是 OLAP 引擎中 BOOLEAN 实现最完整的之一：

```sql
CREATE TABLE accounts (
    id NUMBER,
    is_active BOOLEAN DEFAULT TRUE,
    has_premium BOOLEAN
);

-- 字符串字面量识别能力非常强
INSERT INTO accounts VALUES
    (1, TRUE, FALSE),
    (2, 'true', 'false'),
    (3, 't', 'f'),
    (4, 'yes', 'no'),
    (5, 'y', 'n'),
    (6, 'on', 'off'),
    (7, '1', '0');

-- 双向隐式转换
SELECT TRUE = 1, FALSE = 0;        -- TRUE, TRUE
SELECT TRUE + 1;                   -- 2 (隐式转 INTEGER)
SELECT 0::BOOLEAN, 1::BOOLEAN;     -- FALSE, TRUE

-- WHERE 中
SELECT * FROM accounts WHERE is_active;
SELECT * FROM accounts WHERE has_premium IS UNKNOWN;  -- 等价 IS NULL

-- 输出形式：TRUE / FALSE
SELECT is_active FROM accounts;
```

### BigQuery：BOOL（不是 BOOLEAN）

BigQuery 使用类型名 `BOOL`，且不接受字符串字面量：

```sql
CREATE TABLE dataset.accounts (
    id INT64,
    is_active BOOL,
    has_premium BOOL
);

INSERT INTO dataset.accounts VALUES
    (1, TRUE,  FALSE),
    (2, FALSE, NULL);
-- 'true' / 't' / 1 等都不被接受作为 BOOL 字面量
-- 必须显式 CAST(1 AS BOOL) 或 CAST('true' AS BOOL)

-- 直接用作条件
SELECT * FROM dataset.accounts WHERE is_active;
SELECT * FROM dataset.accounts WHERE NOT is_active;

-- IS UNKNOWN 不支持，必须用 IS NULL
SELECT * FROM dataset.accounts WHERE has_premium IS NULL;

-- CAST 行为
SELECT CAST(1 AS BOOL);    -- TRUE
SELECT CAST(0 AS BOOL);    -- FALSE
SELECT CAST(NULL AS BOOL); -- NULL
SELECT CAST('TRUE' AS BOOL);  -- TRUE (大小写不敏感)
SELECT CAST('Y' AS BOOL);    -- 错误
```

### Trino / Presto / Spark SQL：标准遵循者

```sql
-- Trino / Presto
CREATE TABLE accounts (
    id BIGINT,
    is_active BOOLEAN
);

INSERT INTO accounts VALUES (1, TRUE);
INSERT INTO accounts VALUES (2, false);

SELECT * FROM accounts WHERE is_active;
SELECT * FROM accounts WHERE is_active IS TRUE;
SELECT * FROM accounts WHERE is_active IS UNKNOWN;

-- 字符串到 BOOLEAN 仅通过 CAST
SELECT CAST('true' AS BOOLEAN);   -- true
SELECT CAST('false' AS BOOLEAN);  -- false
SELECT CAST('t' AS BOOLEAN);      -- 错误：仅 'true'/'false' 被识别

-- Spark SQL 类似 Trino：仅 CAST 识别 'true'/'false'
```

### Redshift：宽松的字符串识别（继承 PostgreSQL）

```sql
-- Redshift（基于 PostgreSQL 8.0.2 fork）
CREATE TABLE accounts (
    id INT,
    is_active BOOLEAN
);

-- 与 PostgreSQL 类似的宽松字面量
INSERT INTO accounts VALUES
    (1, TRUE),
    (2, 't'),
    (3, 'yes'),
    (4, 'y'),
    (5, '1'),
    (6, 'on');

-- 注意：Redshift 的 BOOLEAN 实际占 1 字节
-- 列存储下压缩率良好
```

## 三值逻辑（3VL）真值表

BOOLEAN 类型的核心是其逻辑运算的三值真值表。SQL 标准（SQL:1999, 第 6.34 节）严格定义如下：

### AND 运算

```
       TRUE    FALSE   UNKNOWN
TRUE   TRUE    FALSE   UNKNOWN
FALSE  FALSE   FALSE   FALSE
UNKNOWN UNKNOWN FALSE   UNKNOWN
```

口诀：**FALSE 短路**——只要有一个 FALSE，整个 AND 表达式就是 FALSE，无论其他参数是什么。

```sql
SELECT TRUE AND TRUE;       -- TRUE
SELECT TRUE AND FALSE;      -- FALSE
SELECT TRUE AND NULL;       -- NULL (UNKNOWN)
SELECT FALSE AND NULL;      -- FALSE  ← 注意！短路
SELECT NULL AND NULL;       -- NULL
```

### OR 运算

```
       TRUE    FALSE   UNKNOWN
TRUE   TRUE    TRUE    TRUE
FALSE  TRUE    FALSE   UNKNOWN
UNKNOWN TRUE   UNKNOWN UNKNOWN
```

口诀：**TRUE 短路**——只要有一个 TRUE，整个 OR 表达式就是 TRUE，无论其他参数是什么。

```sql
SELECT TRUE OR TRUE;        -- TRUE
SELECT TRUE OR FALSE;       -- TRUE
SELECT TRUE OR NULL;        -- TRUE   ← 注意！短路
SELECT FALSE OR NULL;       -- NULL (UNKNOWN)
SELECT NULL OR NULL;        -- NULL
```

### NOT 运算

```
NOT TRUE    = FALSE
NOT FALSE   = TRUE
NOT UNKNOWN = UNKNOWN  (NULL 的"否定"仍是 NULL)
```

```sql
SELECT NOT TRUE;            -- FALSE
SELECT NOT FALSE;           -- TRUE
SELECT NOT NULL;            -- NULL  ← 关键！
```

### 推论：`NOT (x)` 不是 `(x = FALSE)`

这是新手最常犯的错误之一：

```sql
-- 假设 x IS NULL
NOT x          -- NULL
x = FALSE      -- NULL (因为 NULL = anything 是 NULL)
x IS FALSE     -- FALSE  ← 注意区别

-- WHERE 子句的过滤效果
SELECT * FROM t WHERE NOT x;        -- NULL 被过滤
SELECT * FROM t WHERE x = FALSE;    -- NULL 被过滤
SELECT * FROM t WHERE x IS FALSE;   -- NULL 被过滤（与上面相同）

-- 但写法 1 和 3 在 NOT NULL 列上行为一致；
-- 在可空列上，IS FALSE 是"明确为 FALSE"，而 NOT 和 = FALSE 都是"非 TRUE"
```

### 完整的 IS 谓词集

SQL:1999 定义了一组特殊谓词处理 BOOLEAN 与 NULL 的关系：

| 谓词 | TRUE 时 | FALSE 时 | UNKNOWN/NULL 时 |
|------|--------|---------|----------------|
| `x IS TRUE` | TRUE | FALSE | FALSE |
| `x IS FALSE` | FALSE | TRUE | FALSE |
| `x IS UNKNOWN` | FALSE | FALSE | TRUE |
| `x IS NOT TRUE` | FALSE | TRUE | TRUE |
| `x IS NOT FALSE` | TRUE | FALSE | TRUE |
| `x IS NOT UNKNOWN` | TRUE | TRUE | FALSE |
| `x IS NULL` | FALSE | FALSE | TRUE |
| `x IS NOT NULL` | TRUE | TRUE | FALSE |

> 关键观察：`IS TRUE` / `IS FALSE` 永远返回 TRUE 或 FALSE（绝不返回 UNKNOWN），这是它们与 `=` 的根本区别。

```sql
-- 表 t (id INT, flag BOOLEAN), 三行数据 (1, TRUE), (2, FALSE), (3, NULL)

SELECT id, flag, flag IS TRUE, flag IS FALSE, flag IS UNKNOWN
FROM t ORDER BY id;
-- id  flag   IS TRUE   IS FALSE   IS UNKNOWN
-- 1   TRUE   TRUE      FALSE      FALSE
-- 2   FALSE  FALSE     TRUE       FALSE
-- 3   NULL   FALSE     FALSE      TRUE   ← 注意：永远不返回 NULL！
```

## 实战陷阱 (Gotchas)

### 陷阱 1：MySQL 中 `WHERE col = TRUE` 与 `WHERE col` 不同

```sql
-- 假设 col 是 TINYINT(1)，存有 1, 0, 5, NULL
SELECT * FROM t WHERE col = TRUE;     -- 仅 col = 1
SELECT * FROM t WHERE col;            -- col 非零非 NULL（1 和 5 都返回）
SELECT * FROM t WHERE col IS TRUE;    -- 仅 col = 1（按 boolean 解读）
SELECT * FROM t WHERE col != FALSE;   -- col 非零非 NULL（1 和 5 都返回）
```

### 陷阱 2：SQL Server BIT 不能直接条件

```sql
-- 错误！
SELECT * FROM accounts WHERE is_active;
-- Error: An expression of non-boolean type specified in a context where a condition is expected

-- 正确
SELECT * FROM accounts WHERE is_active = 1;
SELECT * FROM accounts WHERE is_active <> 0;
```

### 陷阱 3：NULL 在 BOOLEAN 表达式中的"传染性"

```sql
-- WHERE (a OR b) 当 a = TRUE 时，无论 b 如何都为 TRUE
WHERE NULL OR TRUE;        -- TRUE  ✓
WHERE FALSE OR NULL;       -- UNKNOWN → 行被过滤！

-- WHERE (a AND b) 当 a = FALSE 时，无论 b 如何都为 FALSE
WHERE NULL AND FALSE;      -- FALSE  ✓
WHERE TRUE AND NULL;       -- UNKNOWN → 行被过滤！
```

### 陷阱 4：`NOT IN` 与 NULL 的"全空集"陷阱

虽然这不是 BOOLEAN 类型本身的问题，但与 3VL 关系极大：

```sql
-- 经典 bug
SELECT * FROM employees
WHERE dept_id NOT IN (SELECT dept_id FROM excluded_depts);
-- 如果 excluded_depts 中任一行 dept_id IS NULL，结果为空

-- 内部展开
-- col NOT IN (1, 2, NULL)
-- = col <> 1 AND col <> 2 AND col <> NULL
-- = col <> 1 AND col <> 2 AND UNKNOWN
-- = ... AND UNKNOWN = UNKNOWN（被过滤）

-- 安全写法
WHERE NOT EXISTS (
    SELECT 1 FROM excluded_depts WHERE dept_id = e.dept_id
);
```

### 陷阱 5：Oracle 23ai 之前 PL/SQL ↔ SQL 的 BOOLEAN 鸿沟

```sql
-- Oracle 21c
DECLARE
    v_active BOOLEAN := TRUE;
BEGIN
    -- 错误：SQL 不能识别 BOOLEAN
    SELECT * FROM accounts WHERE is_active = v_active;
END;

-- 必须显式转换
DECLARE
    v_active BOOLEAN := TRUE;
    v_int    NUMBER;
BEGIN
    v_int := CASE WHEN v_active THEN 1 ELSE 0 END;
    SELECT * FROM accounts WHERE is_active = v_int;
END;

-- 23ai 后这个鸿沟才被填平
```

### 陷阱 6：MySQL 的 BIT 与 SQL Server 的 BIT 不一样

```sql
-- MySQL 的 BIT(N) 是 N 位整数（1 ≤ N ≤ 64）
CREATE TABLE flags (b BIT(8));    -- 8 位
INSERT INTO flags VALUES (b'10101010'), (170);  -- 170 = 0b10101010

-- 不是 boolean！
SELECT b FROM flags;
-- b'10101010' 或显示为字节序列

-- SQL Server 的 BIT 总是单 bit (0/1/NULL)
-- 跨引擎写代码时不要混用
```

### 陷阱 7：CHECK 约束对 NULL 的"反常"接受

```sql
-- WHERE 拒绝 UNKNOWN，但 CHECK 接受 UNKNOWN
CREATE TABLE accounts (
    age INT CHECK (age > 0)
);
INSERT INTO accounts VALUES (NULL);  -- 通过！age > 0 = UNKNOWN, CHECK 接受

-- 显式禁止 NULL
CREATE TABLE accounts (
    age INT CHECK (age > 0 AND age IS NOT NULL)
);
-- 或
CREATE TABLE accounts (
    age INT NOT NULL CHECK (age > 0)
);
```

## BOOLEAN 在不同 SQL 子句中的角色

### SELECT 列表

```sql
-- BOOLEAN 表达式可以直接出现在 SELECT 中
SELECT
    id,
    age >= 18 AS is_adult,           -- BOOLEAN 列
    age BETWEEN 18 AND 65 AS is_working_age,
    name LIKE 'A%' AS starts_with_A
FROM users;

-- 不同引擎的输出格式
-- PostgreSQL: t / f
-- MySQL:      1 / 0
-- SQL Server: 不允许（BIT 不是 BOOLEAN）→ 需 CAST 为 INT
-- Snowflake:  TRUE / FALSE
-- BigQuery:   true / false
-- Oracle 23ai: TRUE / FALSE
```

### CASE 表达式

```sql
-- BOOLEAN 表达式作为 CASE 的判断条件
SELECT
    CASE WHEN is_active THEN 'Active' ELSE 'Inactive' END
FROM accounts;

-- BOOLEAN 表达式作为 CASE 的返回值
SELECT
    CASE
        WHEN age < 18 THEN FALSE
        WHEN age >= 65 THEN FALSE
        ELSE TRUE
    END AS is_working_age
FROM users;
-- 在 SQL Server 中需 CAST 为 BIT，因为 BIT 不能直接作为 CASE 返回类型
```

### JOIN ON 子句

```sql
-- ON 子句的 3VL 行为与 WHERE 一致
SELECT *
FROM users u
LEFT JOIN orders o
ON u.id = o.user_id AND o.is_complete;
-- 仅当 is_complete = TRUE 时连接；FALSE 或 NULL 时该 order 被排除（保留 u）

-- 注意 LEFT JOIN 的"丢失行"陷阱
-- 如果 ON 中的 BOOLEAN 求值为 UNKNOWN，该 join 不发生（左表行保留，右表为 NULL）
```

### GROUP BY 与 HAVING

```sql
-- BOOLEAN 列可作为 GROUP BY 键
SELECT is_active, COUNT(*)
FROM accounts
GROUP BY is_active;
-- 输出最多三个组：TRUE, FALSE, NULL

-- HAVING 子句的 3VL 与 WHERE 一致
SELECT region, COUNT(*) AS cnt
FROM accounts
GROUP BY region
HAVING SUM(CASE WHEN is_active THEN 1 ELSE 0 END) > 100;
```

### ORDER BY

```sql
-- BOOLEAN 列排序：TRUE 与 FALSE 的相对顺序
-- 标准：TRUE > FALSE
-- NULL: 各引擎默认不同（见 null-semantics.md）

SELECT id, is_active FROM accounts ORDER BY is_active DESC;
-- PG/MySQL/SQLite: NULL FALSE FALSE TRUE TRUE  (NULL 默认小)
-- DESC: TRUE TRUE FALSE FALSE NULL
-- Oracle: NULL 默认大（DESC 输出 NULL TRUE TRUE FALSE FALSE）
```

## BOOLEAN 与索引

### 单列 BOOLEAN 索引：通常无价值

```sql
-- 单列 BOOLEAN 索引几乎无用
CREATE INDEX idx_active ON accounts (is_active);
-- 列基数仅 2-3，选择性极差，优化器多数情况不会用

-- 数据分布严重倾斜时（如 99% TRUE / 1% FALSE）才有用
-- 此时查询少数派的查询可受益
SELECT * FROM accounts WHERE NOT is_active;
```

### 部分索引（Partial Index）

许多引擎支持部分索引——只为特定 BOOLEAN 值建索引：

```sql
-- PostgreSQL
CREATE INDEX idx_active ON accounts (id) WHERE is_active;
-- 只索引 is_active = TRUE 的行
-- 大幅减少索引大小，提升查询性能

-- SQL Server
CREATE INDEX idx_active ON accounts (id) WHERE is_active = 1;

-- 类似支持: SQLite, CockroachDB, YugabyteDB
-- 不支持: MySQL（直到 8.0 仍无原生部分索引）
```

### 复合索引中的 BOOLEAN 位置

```sql
-- 通常将 BOOLEAN 列放在复合索引的非首列
-- 因为首列基数高的索引选择性更好

-- 不推荐
CREATE INDEX idx_bad ON accounts (is_active, user_id);

-- 推荐
CREATE INDEX idx_good ON accounts (user_id, is_active);

-- 或使用过滤索引代替
CREATE INDEX idx_active_users ON accounts (user_id) WHERE is_active;
```

## 跨引擎迁移建议

### MySQL → PostgreSQL

```sql
-- MySQL 源端
CREATE TABLE accounts (
    is_active TINYINT(1) DEFAULT 1
);

-- PostgreSQL 目标端
CREATE TABLE accounts (
    is_active BOOLEAN DEFAULT TRUE
);

-- 数据迁移时：
-- TINYINT 中除 0/1 外的值（2, 5 等）会失败
-- 需先在 MySQL 端清洗：UPDATE t SET is_active = 1 WHERE is_active NOT IN (0, 1);
-- 或使用条件 CAST: CAST(is_active <> 0 AS BOOLEAN)
```

### SQL Server → PostgreSQL

```sql
-- SQL Server 源端
CREATE TABLE accounts (
    is_active BIT NOT NULL DEFAULT 1
);

-- PostgreSQL 目标端
CREATE TABLE accounts (
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

-- 数据迁移时：
-- BIT 1 → TRUE, BIT 0 → FALSE
-- 应用代码中所有 WHERE is_active = 1 需改写为 WHERE is_active

-- ETL 工具（如 AWS DMS, Debezium）通常自动转换
```

### Oracle → PostgreSQL

```sql
-- Oracle 21c 源端（无 BOOLEAN）
CREATE TABLE accounts (
    is_active CHAR(1) DEFAULT 'Y' CHECK (is_active IN ('Y', 'N'))
);

-- PostgreSQL 目标端
CREATE TABLE accounts (
    is_active BOOLEAN DEFAULT TRUE
);

-- 数据迁移
-- 'Y' → TRUE, 'N' → FALSE
-- ETL: UPDATE accounts SET is_active = (oracle_col = 'Y');
```

### Oracle 21c → Oracle 23ai 升级

```sql
-- 原模式
CREATE TABLE accounts_old (
    is_active NUMBER(1) DEFAULT 1 CHECK (is_active IN (0, 1))
);

-- 升级到 23ai 后可以
ALTER TABLE accounts_old MODIFY (is_active BOOLEAN);
-- 实际能否成功取决于现有数据；通常先用 ETL 转换
```

### 应用层抽象建议

```
推荐做法：在 ORM/数据访问层统一抽象
- 应用代码使用语言原生 boolean
- 数据访问层根据底层数据库适配
  - PG/Snowflake: TRUE/FALSE
  - MySQL: 1/0
  - SQL Server: 1/0
  - Oracle 21c: 'Y'/'N' 或 1/0
  - Oracle 23ai: TRUE/FALSE
- 避免在 SQL 中直接写 = TRUE / = 1
- 优先使用 IS TRUE / IS FALSE / IS NULL 谓词（语义最严格）
```

## 设计争议

### BIT vs BOOLEAN：SQL Server 为什么不引入 BOOLEAN？

SQL Server 自 1995 年就有 BIT，在 SQL:1999 标准引入 BOOLEAN 后，微软至今未跟进。可能的原因：

1. **向后兼容**：大量代码假定 BIT 与 INT 互转，引入 BOOLEAN 会破坏现有逻辑
2. **存储优势**：BIT 列可被打包（每 8 列共享 1 字节），BOOLEAN 通常 1 字节/列
3. **客户端工具**：ADO.NET、SSMS 等工具围绕 BIT 设计
4. **市场现实**：客户已习惯 BIT，引入 BOOLEAN 价值不足以驱动变更

### Oracle 为什么等到 23ai 才引入？

类似的兼容性顾虑 + Oracle 的保守演进风格。但 23ai 推出后的反响极为积极，证明这个特性是被低估的。

### MySQL 为什么不"升级"BOOLEAN？

MySQL 的 BOOLEAN 别名实质上是 TINYINT(1)，这导致：

1. **存储层无变化**：BOOLEAN 列的二进制格式与 TINYINT 完全相同
2. **复制兼容**：Master/Slave 间的二进制复制无需特殊处理
3. **客户端无影响**：JDBC、PHP/MySQL 扩展等都按整数处理

如果引入"真正"的 BOOLEAN 需要修改存储格式 + 协议 + 所有客户端，成本巨大。MySQL 8.0 时代的开发重心在 JSON、CTE、窗口函数等更高 ROI 的特性上。

### "宽松"vs"严格"的字符串字面量识别

PostgreSQL/Snowflake/Redshift 接受 `'yes'`/`'on'`/`'y'` 等多种字面量，BigQuery/DB2 仅接受 `'true'`/`'false'`。两种取舍：

- **宽松派**：易用，从配置文件、CSV 导入更顺畅
- **严格派**：避免歧义，跨引擎迁移更安全

**推荐做法**：业务代码统一使用 `TRUE`/`FALSE` 关键字（最具普适性），避免依赖字符串字面量识别。

### 隐式整数转换的取舍

MySQL/SQL Server/ClickHouse 允许 BOOLEAN 与 INT 隐式互转，PostgreSQL/Oracle/BigQuery 要求显式 CAST。

```sql
-- MySQL: 合法
SELECT 1 + (5 > 3);    -- 2

-- PostgreSQL: 错误
SELECT 1 + (5 > 3);
-- ERROR: operator does not exist: integer + boolean

-- PostgreSQL 必须
SELECT 1 + (5 > 3)::INT;  -- 2
```

显式 CAST 派的好处：避免 `1 + TRUE` 这类潜在 bug；隐式转换派的好处：迁移自 C/Java/Python 等语言时心智负担小。

## 实现建议（引擎开发者）

### 1. 内部表示

```
推荐内部表示: 单字节 enum {FALSE=0, TRUE=1, UNKNOWN=2}
- 紧凑，对齐友好
- 区分 NULL 与 UNKNOWN：分开存储 (null bitmap + value byte)

避免: bool + null bitmap
- 优势: 标准 C++ bool 可用
- 劣势: 需在每个 3VL 求值处做 null check

避免: 三态 nullable<bool>
- 优势: 类型自然
- 劣势: ABI 复杂，跨语言绑定不便
```

### 2. 3VL 求值的 SIMD 实现

向量化引擎中 3VL 求值是热点：

```
AND 运算的 SIMD 实现:
  // 输入: a[i], b[i], a_null[i], b_null[i] (8 元素并行)
  result_value = a_value & b_value
  result_null = (a_null & ~b_value_is_false) | (b_null & ~a_value_is_false)

  // 关键优化:
  // - FALSE 短路: 任一为 FALSE 时结果 FALSE 且非 null
  // - 用 AVX2 / NEON 批量处理 64+ 元素
  // - 减少分支，分支预测命中率高
```

### 3. WHERE 谓词的过滤实现

```
WHERE 子句仅保留 TRUE 行:
  fn filter_where(rows: &[Row], pred: &Expr) -> Vec<Row>:
      let result = pred.eval(rows)  // 返回 (value, null) 数组
      rows.iter()
          .zip(result.iter())
          .filter(|(_, (v, n))| *v && !*n)  // 仅 TRUE 通过
          .map(|(r, _)| r.clone())
          .collect()

注意 IS TRUE / IS FALSE 不会返回 NULL:
  fn is_true(value, is_null) -> (bool, bool):
      return (value && !is_null, false)  // 永不为 NULL

  fn is_false(value, is_null) -> (bool, bool):
      return (!value && !is_null, false)  // 永不为 NULL
```

### 4. 向量化的真值表查表

```
预计算 3VL 真值表 (3x3 矩阵, 共 9 项):
  static AND_TABLE: [[u8; 3]; 3] = [
      // [a_value][b_value] = result_value
      [F, F, F],      // a=F: F AND anything = F
      [F, T, U],      // a=T: T AND F=F, T AND T=T, T AND U=U
      [F, U, U],      // a=U: U AND F=F, U AND T=U, U AND U=U
  ];

  // 查表替代分支:
  // result = AND_TABLE[encode(a)][encode(b)]
  // 其中 encode 将 (value, is_null) 编码为 0/1/2
```

### 5. 与列存储的协作

```
列存格式:
- 多数引擎: 1 字节/值 (浪费 7 bit)
- 优化方案: bitmap pack (8 个 BOOLEAN 共享 1 字节 + 1 字节 null bitmap)
  - 节省 8 倍空间
  - SIMD 解码效率高
  - Apache Parquet 的 BOOLEAN 列即采用此优化

null 表示:
- 推荐: 独立的 validity bitmap (Apache Arrow 标准)
- 避免: 三态 enum 占用值空间 (与外部库不兼容)
```

### 6. 索引层的特殊处理

```
B+ 树索引: 单列 BOOLEAN 索引基本无价值 (基数仅 2-3)
位图索引 (bitmap index): 对低基数列特别高效
  - Oracle, DB2, Vertica 都为 BOOLEAN 列自动选择 bitmap

部分索引 (partial index): 强烈推荐
  CREATE INDEX idx ON t (id) WHERE is_active;
  - 仅索引 TRUE 行, 索引体积小
  - 适合 99% TRUE / 1% FALSE 的高度倾斜分布
```

### 7. 解析器的字符串字面量识别

```
字符串到 BOOLEAN 的识别策略:
  STRICT: 仅 'TRUE' / 'FALSE' (大小写不敏感)
  POSIX:  'TRUE' / 'FALSE' / 'T' / 'F' / 'YES' / 'NO' / 'Y' / 'N' / 'ON' / 'OFF' / '1' / '0'
  JSON:   仅 'true' / 'false' (小写)

推荐: 实现 POSIX 但提供配置开关切换为 STRICT
  - 默认 POSIX 兼容遗留代码
  - STRICT 模式用于跨引擎兼容性测试
```

### 8. CAST 行为的标准化

```
推荐 CAST 行为 (参考 SQL:1999):
  BOOLEAN → CHAR/VARCHAR: 'TRUE' / 'FALSE' / 'UNKNOWN'
  CHAR/VARCHAR → BOOLEAN: 大小写不敏感识别 'TRUE' / 'FALSE'
  INT → BOOLEAN: 0 → FALSE, 非 0 → TRUE
  BOOLEAN → INT: TRUE → 1, FALSE → 0, NULL → NULL

可选支持 (取决于方言):
  CHAR/VARCHAR → BOOLEAN: 'Y'/'N', 'T'/'F', 'YES'/'NO' 等
  INT → BOOLEAN with strict mode: 仅 0/1 合法
```

## 关键发现 (Key Findings)

1. **BOOLEAN 类型采用极不均衡**：在 45+ 主流引擎中，约 35 个支持原生 BOOLEAN，但 SQL Server、Azure Synapse、Teradata 至今没有，MySQL 系仅是 TINYINT(1) 的别名。

2. **SQL:1999 才标准化，但 PostgreSQL 已经实现**：PostgreSQL 6.x（1996）即支持原生 BOOLEAN，比标准早 3 年；这种"标准滞后于实现"的现象在 SQL 中很常见。

3. **Oracle 在 SQL 层等了 27 年**：Oracle PL/SQL 自 v7（1992）支持 BOOLEAN，但 SQL 层直到 23ai（2024-05）才支持，是主流 RDBMS 中最后一个。

4. **MySQL 的 BOOLEAN 是"假"的**：MySQL 4.1（2004）引入 BOOLEAN/BOOL 关键字，但实质是 TINYINT(1) 的别名，可存任意 -128~127 整数；ORM 通过 TINYINT(1) 显示宽度识别 BOOLEAN，TINYINT(1) → TINYINT 的迁移会破坏 ORM 行为。

5. **SQL Server BIT 不是 BOOLEAN**：BIT 必须显式比较（`= 1` / `<> 0`），不能直接作为 WHERE 条件；不接受 TRUE/FALSE 字面量；与 INT 隐式互转。这些差异让跨引擎迁移工作量被严重低估。

6. **三值逻辑的关键短路规则**：FALSE AND ANY = FALSE（即使 ANY 是 NULL）；TRUE OR ANY = TRUE（即使 ANY 是 NULL）。这是引擎实现 3VL 时的优化机会。

7. **WHERE 与 CHECK 的反对称行为**：WHERE 仅保留 TRUE 行（FALSE 和 UNKNOWN 都被过滤），CHECK 仅拒绝 FALSE（TRUE 和 UNKNOWN 都被接受）。这导致很多 NULL 数据"绕过"CHECK 约束。

8. **`IS TRUE` 永不返回 UNKNOWN**：与 `=` 不同，`IS TRUE` / `IS FALSE` / `IS UNKNOWN` 是确定性谓词，永远返回 TRUE 或 FALSE，是处理 NULL 安全条件的首选。

9. **字符串字面量识别差异巨大**：PostgreSQL/Redshift/Snowflake 接受 'yes'/'on'/'y' 等多种形式，BigQuery/DB2 仅接受 'true'/'false'，跨引擎迁移容易触发解析错误。

10. **隐式整数转换分两派**：MySQL/SQL Server/ClickHouse 允许 BOOLEAN ↔ INT 隐式互转，PostgreSQL/Oracle/BigQuery 要求显式 CAST。前者迁移自 C/Java 友好，后者类型安全更好。

11. **SQLite 没有真正的 BOOLEAN**：3.23+ 仅识别 TRUE/FALSE 关键字（解析为 1/0），列声明为 BOOLEAN 时使用 NUMERIC 亲和性。值可能存为 INTEGER 或 TEXT，需配合 CHECK 约束 + STRICT 表保证一致。

12. **BIT 的存储优化**：SQL Server 自动将同一行最多 8 个 BIT 列打包到 1 字节；MySQL 的 BIT(N) 是 N 位整数（最大 64 位），与 SQL Server 的 BIT 完全不同。

13. **部分索引（partial index）是 BOOLEAN 列的最佳实践**：单列 BOOLEAN 索引基数过低无价值；部分索引（PG/SQL Server/SQLite 支持）可仅索引 TRUE 行，大幅压缩索引体积。

14. **跨引擎迁移建议**：业务代码统一使用 TRUE/FALSE 关键字（不依赖字符串字面量），优先 IS TRUE / IS FALSE / IS NULL 谓词（语义最严格），数据访问层抽象底层差异。

## 参考资料

- ISO/IEC 9075-2:1999 - SQL:1999 Standard, Section 4.4 Boolean
- ISO/IEC 9075-2:2003 - SQL:2003 Standard, Boolean operations
- PostgreSQL: [Boolean Type](https://www.postgresql.org/docs/current/datatype-boolean.html)
- MySQL: [Numeric Type Attributes](https://dev.mysql.com/doc/refman/8.0/en/numeric-type-attributes.html), [Boolean Literals](https://dev.mysql.com/doc/refman/8.0/en/boolean-literals.html)
- Oracle 23ai: [BOOLEAN Data Type](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Data-Types.html)
- SQL Server: [bit (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/data-types/bit-transact-sql)
- DB2 11.1: [BOOLEAN data type](https://www.ibm.com/docs/en/db2/11.5?topic=list-boolean)
- ClickHouse 22.3 Release Notes: Bool data type
- SQLite: [Datatypes In SQLite](https://www.sqlite.org/datatype3.html)
- Snowflake: [Logical Data Types](https://docs.snowflake.com/en/sql-reference/data-types-logical)
- BigQuery: [Data Types - BOOL](https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types#boolean_type)
- Trino: [Boolean type](https://trino.io/docs/current/language/types.html#boolean)
- Apache Arrow: [Boolean Layout](https://arrow.apache.org/docs/format/Columnar.html#fixed-size-primitive-layout)
- Date, C.J. "Database in Depth" (2005), Chapter on Three-Valued Logic
- Codd, E.F. "Missing information (applicable and inapplicable) in relational databases" (1986), ACM SIGMOD Record
