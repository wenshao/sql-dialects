# MONEY 与货币类型 (MONEY and Currency Types)

一笔 99.99 美元的订单存进数据库变成了 99.989999... 然后聚合后变成 100.00000001——浮点货币的灾难每天都在重演。专门的货币类型与高精度 DECIMAL 是金融系统的安全带，也是引擎类型系统中争议最多的边界之一。

## 为什么需要专门的 MONEY 类型

### 浮点的原罪

二进制浮点（IEEE 754 binary32 / binary64）无法精确表示十进制小数 0.1、0.2、99.99。例如 `0.1 + 0.2 != 0.3`，在金融场景中这是不可接受的：

```sql
-- MySQL: 浮点货币的灾难
CREATE TABLE orders (id INT, amount DOUBLE);
INSERT INTO orders VALUES (1, 0.1), (2, 0.2);
SELECT SUM(amount) FROM orders;
-- 结果: 0.30000000000000004  -- 不是 0.3!

-- PostgreSQL: 同样问题
SELECT 0.1::float8 + 0.2::float8;
-- 结果: 0.30000000000000004
```

更糟糕的是聚合后的累积误差：100 万行 0.01 元相加，DOUBLE 可能给出 9999.999999734 或 10000.00000045，而不是精确的 10000.00。审计永远过不了。

### 货币类型的三种方案

| 方案 | 代表 | 内部表示 | 范围 | 精度 |
|------|------|---------|------|------|
| 定点 MONEY | SQL Server / Sybase | scaled int64 (×10000) | ±922,337,203,685,477.5807 | 4 位小数 |
| 高精度 DECIMAL | MySQL / Oracle / DB2 | 二进制定长十进制 | 38 ~ 65 位 | 任意 |
| IEEE 754 DECFLOAT | DB2 / SAP HANA | decimal64 / decimal128 | 16 / 34 有效位 | 任意 |
| 浮点 (REJECTED) | -- | binary64 | 极大 | 不精确 |

### 货币的特殊需求

1. **精确算术**：每笔 transaction 必须可审计
2. **本地化格式**：`$1,234.56` vs `€1.234,56` vs `¥1,234`
3. **四舍五入**：HALF_EVEN（银行家舍入）vs HALF_UP（普通四舍五入）
4. **货币代码**：USD/EUR/JPY 不可混合相加
5. **税收/利率精度**：4-6 位小数
6. **大数加总**：百万行求和不能丢失分位

## SQL 标准与规范定位

SQL:1992（ISO/IEC 9075:1992）定义了 `DECIMAL(p,s)` 和 `NUMERIC(p,s)` 作为精确数值类型，但**没有定义 MONEY 类型**：

```sql
-- SQL:1992 标准
NUMERIC(precision, scale)  -- 精确表示，至少 precision 位
DECIMAL(precision, scale)  -- 精确表示，可超过 precision 位（实现可放宽）

-- 标准未规定:
-- - precision 上限（实现各异：18 ~ 65 ~ ∞）
-- - 内部表示（BCD / 二进制定长 / 字符串）
-- - 货币代码、locale 格式
-- - 算术结果的精度推导规则
```

NUMERIC 与 DECIMAL 的微妙差异：标准要求 NUMERIC 精度严格等于声明值（不可多），DECIMAL 允许实现存储更高精度。实际中绝大多数引擎将两者视为同义词。

业界共识：**Oracle 的 `NUMBER(p,s)` 是货币的事实标准推荐**。它支持 38 位精度，覆盖所有现实金融需求，无 locale 副作用，跨版本稳定。

## 支持矩阵（45+ 引擎）

### 一：原生 MONEY 类型

| 引擎 | 原生 MONEY | SMALLMONEY | 内部表示 | 小数位数 | 范围 |
|------|----------|-----------|---------|---------|------|
| SQL Server | 是 | 是 | scaled int64 | 4 | ±922,337,203,685,477.5807 |
| Sybase ASE | 是 | 是 | scaled int64 | 4 | 同 SQL Server |
| Sybase IQ | 是 | 是 | scaled int64 | 4 | 同 SQL Server |
| Azure SQL | 是 | 是 | scaled int64 | 4 | 同 SQL Server |
| Azure Synapse | 是 | 是 | scaled int64 | 4 | 同 SQL Server |
| PostgreSQL | 是 | -- | scaled int64 | locale 决定 | ±92,233,720,368,547,758.07 |
| Greenplum | 是 | -- | 继承 PG | locale 决定 | 同 PG |
| YugabyteDB | 是 | -- | 继承 PG | locale 决定 | 同 PG |
| CockroachDB | -- | -- | -- | -- | -- |
| Informix | 是 | -- | DECIMAL(p,s) 别名 | 任意 | 32 位精度 |
| Firebird | -- | -- | -- | -- | 用 NUMERIC(18,4) 替代 |
| Oracle | -- | -- | -- | -- | 推荐 NUMBER(p,s) |
| MySQL | -- | -- | -- | -- | 推荐 DECIMAL(p,s) |
| MariaDB | -- | -- | -- | -- | 推荐 DECIMAL(p,s) |
| TiDB | -- | -- | -- | -- | 推荐 DECIMAL(p,s) |
| OceanBase | -- | -- | -- | -- | 推荐 DECIMAL(p,s) |
| DB2 | -- | -- | -- | -- | 推荐 DECIMAL/DECFLOAT |
| SQLite | -- | -- | -- | -- | 仅 REAL/INTEGER（无定点） |
| H2 | -- | -- | -- | -- | 推荐 DECIMAL |
| HSQLDB | -- | -- | -- | -- | 推荐 DECIMAL |
| Derby | -- | -- | -- | -- | 推荐 DECIMAL |
| Snowflake | -- | -- | -- | -- | 推荐 NUMBER(p,s) |
| BigQuery | -- | -- | -- | -- | 推荐 NUMERIC/BIGNUMERIC |
| Redshift | -- | -- | -- | -- | 推荐 DECIMAL(p,s) |
| Athena | -- | -- | -- | -- | 推荐 DECIMAL(p,s) |
| ClickHouse | -- | -- | -- | -- | 推荐 Decimal(p,s) |
| DuckDB | -- | -- | -- | -- | 推荐 DECIMAL(p,s) |
| Trino | -- | -- | -- | -- | 推荐 DECIMAL(p,s) |
| Presto | -- | -- | -- | -- | 推荐 DECIMAL(p,s) |
| Spark SQL | -- | -- | -- | -- | 推荐 DECIMAL(p,s) |
| Hive | -- | -- | -- | -- | 推荐 DECIMAL(p,s) |
| Flink SQL | -- | -- | -- | -- | 推荐 DECIMAL(p,s) |
| Databricks | -- | -- | -- | -- | 推荐 DECIMAL(p,s) |
| Teradata | -- | -- | -- | -- | 推荐 NUMBER(p,s) |
| Vertica | -- | -- | -- | -- | 推荐 NUMERIC(p,s) |
| SAP HANA | -- | -- | -- | -- | 推荐 DECIMAL/SMALLDECIMAL |
| SingleStore | -- | -- | -- | -- | 推荐 DECIMAL(p,s) |
| Impala | -- | -- | -- | -- | 推荐 DECIMAL(p,s) |
| StarRocks | -- | -- | -- | -- | 推荐 DECIMAL(p,s) |
| Doris | -- | -- | -- | -- | 推荐 DECIMAL(p,s) |
| MonetDB | -- | -- | -- | -- | 推荐 DECIMAL(p,s) |
| Exasol | -- | -- | -- | -- | 推荐 DECIMAL(p,s) |
| Crate DB | -- | -- | -- | -- | 推荐 NUMERIC |
| TimescaleDB | 是 | -- | 继承 PG | locale 决定 | 同 PG（不推荐使用）|
| QuestDB | -- | -- | -- | -- | 推荐 DOUBLE / LONG |
| Materialize | 是 | -- | 继承 PG | locale 决定 | 兼容 PG |
| RisingWave | -- | -- | -- | -- | 推荐 DECIMAL(p,s) |
| Firebolt | -- | -- | -- | -- | 推荐 DECIMAL(p,s) |
| Yellowbrick | -- | -- | -- | -- | 推荐 NUMERIC(p,s) |
| DatabendDB | -- | -- | -- | -- | 推荐 DECIMAL(p,s) |
| Google Spanner | -- | -- | -- | -- | 推荐 NUMERIC（38,9）|

> 统计：约 12 个引擎提供原生 MONEY 类型；其余 33+ 引擎依赖 DECIMAL/NUMERIC。
>
> 重要：PostgreSQL 系（PG/Greenplum/Yugabyte/TimescaleDB/Materialize）虽提供 money 类型，**官方文档明确不推荐**使用，而是推荐 numeric/decimal。

### 二：DECIMAL/NUMERIC 精度上限

| 引擎 | DECIMAL/NUMERIC 最大精度 | 默认精度 | 内部存储 | 引入版本 |
|------|----------------------|---------|---------|---------|
| MySQL | 65 | 10 | 二进制定长，每 9 位 4 字节 | 5.0 (2005) |
| MariaDB | 65 | 10 | 同 MySQL | 继承 |
| PostgreSQL | 1000（理论），131072（无限） | 任意 | base-10000 变长 | 8.0+ |
| Greenplum | 1000 | 任意 | 继承 PG | 继承 |
| Oracle | 38 | -- | scientific 变长（最多 22 字节） | 早期 |
| SQL Server | 38 | 18 | 1-17 字节定长 | 早期 |
| DB2 LUW | 31 | 5 | packed decimal (BCD) | 早期 |
| DB2 z/OS | 31 | 5 | packed decimal | 早期 |
| Sybase ASE | 38 | -- | 1-17 字节定长 | 早期 |
| TiDB | 65 | 10 | 兼容 MySQL | GA |
| OceanBase | 38（MySQL 模式 65） | 10 | 兼容模式可调 | GA |
| SAP HANA | 38（DECIMAL）/ 16（SMALLDECIMAL） | 由模式 | 16 字节 IEEE 754-2008 | 早期 |
| Vertica | 38 | 18 | 8-24 字节定长 | 早期 |
| Snowflake | 38 | 10 | 1-16 字节定长 | GA |
| BigQuery | 38（NUMERIC）/ 76（BIGNUMERIC） | 38, 9 | 16 字节 / 32 字节 | NUMERIC: 2018, BIGNUMERIC: 2020 |
| Redshift | 38 | 18 | 8-16 字节定长 | 早期 |
| Athena | 38 | -- | 同 Trino | 继承 |
| Trino | 38 | -- | 8-16 字节定长 | 早期 |
| Presto | 38 | -- | 同 Trino | 早期 |
| Spark SQL | 38 | 10 | Java BigDecimal | 1.5+ |
| Hive | 38 | 10 | Java BigDecimal | 0.13+ |
| Flink SQL | 38 | 10 | Java BigDecimal | 1.0+ |
| Databricks | 38 | 10 | 同 Spark SQL | 继承 |
| ClickHouse | 76（Decimal256） | -- | Decimal32(4B) / Decimal64(8B) / Decimal128(16B) / Decimal256(32B) | 1.1.x+ |
| DuckDB | 38（HUGEINT 后端） | 18, 3 | 4-16 字节 | GA |
| SQLite | 不支持精确十进制 | -- | REAL (binary64) 或 TEXT | -- |
| Teradata | 38 | -- | 1-16 字节 | V2R4+ |
| Impala | 38 | 9 | 4-16 字节 | 2.0+ |
| StarRocks | 38（v2.5+） | 10 | 4-16 字节 | 2.5+ |
| Doris | 38（DECIMAL128） | 9 | 4-16 字节 | 2.0+ |
| MonetDB | 38 | 18 | 1-16 字节 | 早期 |
| Exasol | 36 | 18 | 8-16 字节 | 早期 |
| H2 | 100,000（理论） | 100,000 | Java BigDecimal | 早期 |
| HSQLDB | 任意（受内存限制） | 100 | Java BigDecimal | 早期 |
| Derby | 31 | 5 | packed decimal | 早期 |
| Firebird | 38（v4+），原 18 | 9 | 1-16 字节 | v4.0 (2021) |
| Informix | 32 | 16 | 1-17 字节 | 早期 |
| Crate DB | -- | -- | NUMERIC 变长 | GA |
| TimescaleDB | 1000 | -- | 继承 PG | 继承 |
| QuestDB | -- | -- | LONG / DOUBLE 替代 | -- |
| Materialize | 39 | 39, 0 | 兼容 PG numeric | GA |
| RisingWave | 28（DECIMAL） | -- | Rust BigDecimal | GA |
| Firebolt | 38 | 38, 9 | 16 字节 | GA |
| Yellowbrick | 38 | 18 | 8-16 字节 | GA |
| DatabendDB | 76 | -- | Decimal128 / Decimal256 | GA |
| Google Spanner | 38（NUMERIC） | 38, 9 | 16 字节 | GA |
| Azure Synapse | 38 | 18 | 同 SQL Server | 继承 |
| SingleStore | 65 | 10 | 兼容 MySQL | 继承 |
| Sybase IQ | 38 | -- | 1-17 字节 | 早期 |

> 关键：MySQL/MariaDB/TiDB/SingleStore 的 65 位精度是异类，覆盖 ISO 4217 任意货币。
>
> PostgreSQL 的 numeric 是唯一接近无限精度的（理论 131072 位），但运算性能与精度成反比。

### 三：本地化格式与货币代码

| 引擎 | locale 格式化函数 | 货币代码常量 | 多货币列存储 |
|------|----------------|-----------|-----------|
| PostgreSQL | `to_char(n, 'L9G999D99')` | `lc_monetary` 配置 | 不直接支持 |
| SQL Server | `FORMAT(n, 'C', 'en-US')` | -- | 不直接支持 |
| Oracle | `to_char(n, 'L9G999D99')` | `NLS_CURRENCY` | -- |
| MySQL | `FORMAT(n, 2, 'en_US')` | -- | -- |
| DB2 | `to_char` 函数 | `LOCALE` | -- |
| SAP HANA | `TO_VARCHAR(n, ...)` | `SESSION_CONTEXT` | 是（货币列）|
| Snowflake | `to_varchar(n, '$999,999.00')` | -- | -- |
| BigQuery | `FORMAT('%\'.2f', n)` | -- | -- |
| Spark SQL | `format_number` | -- | -- |
| ClickHouse | `formatReadableQuantity` | -- | -- |
| Trino | `format_number(n, 'en-US')` | -- | -- |

> 大多数引擎不直接支持「在数据库内强制每列单一货币代码」的能力。常见做法是用复合列 `(amount DECIMAL, currency CHAR(3))`。SAP HANA 在金融行业历史上有专门的"货币列"概念。

### 四：四舍五入模式

| 引擎 | 默认 ROUND 模式 | HALF_EVEN（银行家） | HALF_UP | 自定义 |
|------|--------------|------------------|---------|--------|
| Oracle | HALF_AWAY_FROM_ZERO | -- | 默认 | DBMS_OBFUSCATION 等 |
| SQL Server | HALF_UP（ROUND）/ HALF_EVEN（CONVERT） | 是 | 是 | -- |
| PostgreSQL | HALF_EVEN（自 8.0） | 是 | 通过 `round_half_up` 扩展 | -- |
| MySQL | HALF_UP（ROUND）/ HALF_EVEN（cast 部分场景） | 部分 | 是 | -- |
| MariaDB | HALF_UP | -- | 是 | -- |
| DB2 | HALF_EVEN | 是 | -- | DECFLOAT 受 IEEE 754 控制 |
| Sybase ASE | HALF_UP | -- | 是 | -- |
| SAP HANA | HALF_UP | -- | 是 | -- |
| Snowflake | HALF_AWAY_FROM_ZERO | -- | 是 | -- |
| Spark SQL | HALF_UP | -- | 是 | `round(x,d,mode)` 不直接 |
| ClickHouse | HALF_TO_EVEN（自 19.x） | 是 | -- | `roundBankers` |
| DuckDB | HALF_TO_EVEN | 是 | -- | -- |
| Trino | HALF_UP | -- | 是 | `round_to_even` |
| BigQuery | HALF_AWAY_FROM_ZERO | -- | 是 | -- |
| Vertica | HALF_AWAY_FROM_ZERO | -- | 是 | -- |
| Teradata | HALF_EVEN | 是 | -- | -- |

> 银行家舍入（HALF_EVEN）：5 舍入到偶数（2.5→2, 3.5→4），减少长期累积偏差。IEEE 754 默认。
>
> 普通舍入（HALF_UP）：5 总是向上（2.5→3, 3.5→4）。直觉但有偏差。

## 各引擎深入

### SQL Server（MONEY/SMALLMONEY 经典实现）

SQL Server 的 MONEY 类型可追溯至 1990 年代初 Sybase 与 Microsoft 的合作（SQL Server 早期版本就是 Sybase ASE 的派生）。它是定点 64 位整型表示，**实际是个 scaled int64 with implicit scale=4**。

```sql
-- 类型定义
DECLARE @price MONEY = 99.99;          -- 8 字节
DECLARE @small SMALLMONEY = 99.99;     -- 4 字节

-- 范围
-- MONEY:      ±922,337,203,685,477.5807   (8 字节 / int64 / 1e-4)
-- SMALLMONEY: ±214,748.3647                (4 字节 / int32 / 1e-4)

-- 内部存储原理
-- 99.99 实际存储为 int64: 999900
-- 100.00 存储为 int64: 1000000
-- 因此 + - 直接是 int64 加减，极快
INSERT INTO orders VALUES (1, 99.99);
SELECT amount FROM orders;      -- 返回 99.9900（始终 4 位）

-- 货币符号字面量（仅在赋值/字面量解析时识别）
DECLARE @p MONEY = $1234.56;    -- 等同于 1234.56
DECLARE @e MONEY = €1234.56;    -- 解析时丢弃符号
```

**陷阱：MONEY × MONEY 会丢精度**

```sql
DECLARE @a MONEY = 0.0001;
DECLARE @b MONEY = 100;
SELECT @a * @b AS product;   -- 0.0100 (正确)

-- 但中间结果可能下溢:
DECLARE @c MONEY = 0.00001;
SELECT @c;                    -- 0.0000  -- 下溢: 0.00001 < 1e-4 精度

-- 除法陷阱：
DECLARE @x MONEY = 100;
DECLARE @y MONEY = 3;
SELECT @x / @y;               -- 33.3333 (4 位精度，截断)
SELECT CAST(@x AS DECIMAL(19,9)) / @y;  -- 33.333333333 (推荐)
```

**MONEY 是过时的设计**：现代 SQL Server 文档建议在新代码中使用 `DECIMAL(19,4)` 替代，仅为兼容性保留。

### Sybase ASE / IQ（MONEY 起源地）

Sybase 的 MONEY 类型是 SQL Server 的鼻祖（1980 年代）。语义、范围、精度完全一致：

```sql
-- Sybase ASE
CREATE TABLE invoices (
    id INT,
    total MONEY,
    discount SMALLMONEY
);
-- MONEY: 8 字节 int64, scale 4
-- SMALLMONEY: 4 字节 int32, scale 4

-- Sybase IQ（列存储版本）继承 ASE 的 MONEY 类型
-- 列存的压缩对 MONEY 特别有效（聚集分布）
```

**SAP 收购 Sybase 后**：ASE 仍保留 MONEY；SAP HANA 选择走 IEEE 754-2008 SMALLDECIMAL 路线。

### PostgreSQL（problematic money 类型）

PostgreSQL 的 `money` 类型从 6.x 起就存在，但**官方明确警告不推荐**：

```sql
CREATE TABLE invoices (id INT, amount MONEY);
INSERT INTO invoices VALUES (1, '$99.99');

-- 内部：scaled int64, scale 由 lc_monetary 决定
SHOW lc_monetary;     -- 通常 'en_US.UTF-8' (2 位小数)

-- Locale 切换的灾难
SET lc_monetary = 'en_US.UTF-8';
SELECT '$99.99'::money;        -- $99.99
SET lc_monetary = 'ja_JP.UTF-8';
SELECT '99.99'::money;          -- ¥99 (小数被截断！)
SELECT amount FROM invoices;   -- 之前插入的 $99.99 现在显示 ¥99 (二次解读)
```

**为什么 PG money 是问题**:

1. **locale 决定小数位数**：`en_US` 是 2 位，`ja_JP` 是 0 位，`bh_IN` 等可能是 3 位
2. **数据迁移破坏**：dump → restore 到不同 locale 服务器，数值意义改变
3. **不能与 NUMERIC 直接运算**：必须显式 CAST
4. **没有指定货币代码**：'$99.99' 在 EU 服务器解析报错或解读为本地货币
5. **无 SUM 时的精度保证**：lc_monetary 切换中途可能出现混乱

```sql
-- PG 官方推荐：用 numeric 替代
CREATE TABLE invoices (
    id INT,
    amount NUMERIC(19,4),
    currency CHAR(3)        -- ISO 4217: USD, EUR, JPY, ...
);

-- 文档原话:
-- "Use of the money data type is discouraged.
-- Many databases use numeric or decimal types for money values."
```

### Oracle（NUMBER(p,s)：行业标准）

Oracle 的 `NUMBER` 类型是金融行业的事实标准。它支持 38 位有效数字、变长存储、统一表示整数和小数：

```sql
-- 不指定精度
CREATE TABLE accounts (
    id NUMBER,                        -- 最多 38 位有效数字
    balance NUMBER(19,4),             -- 4 位小数，总 19 位
    rate NUMBER(7,4),                 -- 利率，如 0.0500
    big_amount NUMBER(38,18)          -- 极端精度
);

-- 内部表示：scientific notation
-- 1.234e3: mantissa=1234, exponent=3
-- 存储 1-22 字节，与 magnitude 成正比
-- 0 占 1 字节，最大数 22 字节

-- 数学运算精度由参与运算的操作数决定
SELECT 1/3 FROM dual;      -- 0.33333333333333333333333333333333333333 (38 位)

-- ROUND 模式（Oracle 默认 HALF_AWAY_FROM_ZERO）
SELECT ROUND(2.5), ROUND(3.5);   -- 3, 4 (向远离零方向)
SELECT ROUND(-2.5);               -- -3
```

**Oracle 的 NUMBER 优势**:

1. 38 位精度覆盖所有现实金融场景
2. 变长存储节省空间（小数 1-2 字节，大数 22 字节）
3. 类型统一：整数和小数都用 NUMBER
4. NLS（Natural Language Support）提供 locale 格式化
5. 跨版本完全稳定（自 Oracle 7+ 无重大变化）

### MySQL（DECIMAL 65 位的传奇）

MySQL 的 DECIMAL 演变是数据库史上少见的精度革命：

```sql
-- 5.0 之前（2005 之前）：DECIMAL(M,D) 是字符串存储
-- M 是字符数，最大 254；精度依赖于格式

-- 5.0+ (2005)：DECIMAL 变成二进制定长十进制
CREATE TABLE prices (
    p1 DECIMAL(10,2),       -- 6 字节
    p2 DECIMAL(20,4),       -- 11 字节
    p3 DECIMAL(65,30)       -- 30 字节, 极限精度
);

-- 编码规则：base-1e9，每 9 位十进制 → 4 字节
-- 11.99 (M=10, D=2):
--   整数部分: 11 (0-9 共 1 位 mod 9 = 1 字节)
--   小数部分: 99 (0-2 共 2 位 mod 9 = 1 字节)
--   总 6 字节（含符号位）

-- 精度上限：
SELECT 12345678901234567890123456789012345.123456789012345678901234567890 AS x;
-- 上面 35 位整数 + 30 位小数 = 65 位（DECIMAL 上限）

-- 算术结果精度
SELECT 1/3;             -- 0.3333 (默认 div_precision_increment=4)
SET SESSION div_precision_increment = 30;
SELECT 1/3;             -- 0.333333333333333333333333333333
```

**MySQL DECIMAL 历史里程碑**:

| 版本 | 年份 | 改进 |
|------|------|------|
| < 5.0 | 早期 | 字符串存储，最大 64 字符 |
| 5.0 | 2005 | 二进制定长，精度 65 位 |
| 5.6 | 2013 | 时间类型加入小数秒 |
| 8.0 | 2018 | DECIMAL 索引优化 |
| 8.4 | 2024 | 仍保持 65 位上限 |

**与货币的兼容**：DECIMAL(19,4) 几乎是所有 MySQL 货币应用的事实标准。

### MariaDB / TiDB / OceanBase / SingleStore（MySQL 协议族）

均继承 MySQL 的 DECIMAL(65,30) 精度规则：

```sql
-- TiDB
CREATE TABLE accounts (balance DECIMAL(19,4));
-- 完全兼容 MySQL，分布式聚合保持精度

-- OceanBase MySQL 模式
CREATE TABLE accounts (balance DECIMAL(65,4));

-- OceanBase Oracle 模式
CREATE TABLE accounts (balance NUMBER(38,4));

-- SingleStore (MemSQL)
CREATE TABLE accounts (balance DECIMAL(19,4));
-- 列存储下 DECIMAL 压缩与 MONEY 等价
```

### DB2（DECFLOAT 的旗手）

DB2 是 IEEE 754-2008 decimal floating-point 的最重要推广者：

```sql
-- 经典 DECIMAL（packed decimal/BCD）
CREATE TABLE old_accounts (
    balance DECIMAL(31, 4)         -- 最多 31 位精度，BCD 编码
);
-- 31 位是 packed decimal 的硬性限制（每 2 个数字 1 字节，16 字节存 31 位）

-- DECFLOAT（自 9.5, 2007）：IEEE 754-2008 decimal128/decimal64
CREATE TABLE accounts (
    balance DECFLOAT,              -- 默认 DECFLOAT(34)
    big_balance DECFLOAT(34),      -- 16 字节, 34 位精度, ±10^6145
    small_balance DECFLOAT(16)     -- 8 字节, 16 位精度, ±10^385
);

-- DECFLOAT 的优势:
-- 1. IEEE 754-2008 标准，硬件支持（IBM POWER6+, z9+）
-- 2. 精确十进制（无 0.1 + 0.2 ≠ 0.3 问题）
-- 3. 浮点性能（比 packed decimal 快 5-10x）
-- 4. 巨大范围（10^-6143 ~ 10^6144）

-- 浮点 vs 定点的本质差异:
-- DECIMAL(19,4):  精度固定 4 位，运算无精度变化
-- DECFLOAT(34):   精度跟随数值大小自动调整，类似 binary float

-- 算术对比:
SELECT CAST(1 AS DECIMAL(19,4)) / 3;     -- 0.3333 (截断到 4 位)
SELECT CAST(1 AS DECFLOAT(34)) / 3;      -- 0.3333333333333333333333333333333333 (34 位)

-- DECFLOAT 的舍入模式（IEEE 754-2008 定义 5 种）
-- ROUND_CEILING       向上
-- ROUND_FLOOR         向下
-- ROUND_HALF_EVEN     银行家（默认）
-- ROUND_HALF_UP       普通四舍五入
-- ROUND_HALF_DOWN     向下半数
SET CURRENT DECFLOAT ROUNDING MODE = 'ROUND_HALF_UP';
```

**DB2 DECFLOAT 时间线**:
- 9.5 (2007)：DECFLOAT(34) 在 LUW 引入
- 9.7 (2009)：z/OS 引入 DECFLOAT
- 11.5 (2019)：性能继续优化

### SAP HANA（SMALLDECIMAL 16 字节决战）

SAP HANA 选择 IEEE 754-2008 decimal128（16 字节）作为核心数值类型：

```sql
-- SMALLDECIMAL: 16 字节 IEEE 754-2008 decimal128
CREATE TABLE invoices (
    id INT,
    amount SMALLDECIMAL,    -- 16 字节，类似 DECFLOAT(34)
    fee SMALLDECIMAL
);

-- DECIMAL: 默认是 SMALLDECIMAL 的 ANSI 兼容形式
-- 但 DECIMAL(p,s) 是 packed decimal 定点

-- 精度比较
-- SMALLDECIMAL: 1-34 位精度，IEEE 754 浮点
-- DECIMAL(38, 10): 固定 38 位精度，定点

-- 算术
SELECT CAST(1 AS SMALLDECIMAL) / 3;   -- 浮点除法，34 位
SELECT CAST(1 AS DECIMAL(38, 10)) / 3; -- 定点除法，10 位小数

-- HANA 货币列（金融模型）
-- 自 SAP 时代起，HANA 在 SAP S/4HANA 数据模型中使用配对列:
-- AMOUNT SMALLDECIMAL,
-- CURRENCY CHAR(3)        -- ISO 4217 货币代码
```

### Snowflake（NUMBER 别名族）

Snowflake 的数值类型是别名繁多但底层统一：

```sql
-- 所有这些都是同一类型 NUMBER(38, 0):
INT, INTEGER, BIGINT, SMALLINT, TINYINT, BYTEINT
-- 内部 = NUMBER(38, 0)

-- DECIMAL/NUMERIC/NUMBER 完全等价
CREATE TABLE accounts (
    balance NUMBER(19, 4),         -- 推荐货币
    rate NUMBER(7, 4)
);

-- 精度上限 38, scale 0-37
-- 内部存储：变长 1-16 字节
-- 编码与 SQL Server 类似（scaled int128）
```

### BigQuery（NUMERIC vs BIGNUMERIC）

BigQuery 在 2018-2020 间推出了金融级数值类型：

```sql
-- NUMERIC: 38 位精度, 9 位小数（固定 scale）
CREATE TABLE invoices (
    amount NUMERIC                 -- 等同 NUMERIC(38, 9)
);
-- 范围: ±9.9999999999999999999999999999999999999E+28

-- BIGNUMERIC: 76 位精度, 38 位小数（2020+）
CREATE TABLE big_invoices (
    huge_amount BIGNUMERIC         -- 76 位精度，金融极端场景
);
-- 范围: ±5.7896044618658097711785492504343953926634E+38

-- 自定义 scale (2024 起)
CREATE TABLE custom (
    a NUMERIC(19, 4),
    b BIGNUMERIC(60, 20)
);
```

### ClickHouse（4 种 Decimal 宽度）

ClickHouse 提供四种宽度的 Decimal，匹配性能与精度：

```sql
CREATE TABLE accounts (
    a Decimal32(4),       -- 4 字节, 9 位精度（保留 4 位小数）
    b Decimal64(4),       -- 8 字节, 18 位精度
    c Decimal128(4),      -- 16 字节, 38 位精度
    d Decimal256(4)       -- 32 字节, 76 位精度
) ENGINE = MergeTree;

-- 类型选择策略:
-- Decimal32:  日常订单金额（不超过 ±99,999.9999）
-- Decimal64:  大额交易（不超过 ±9.99e13）
-- Decimal128: 金融投资银行（覆盖任意货币）
-- Decimal256: 加密货币（满足 wei 等极小单位）

-- 加密货币精度场景：以太坊 wei 单位
-- 1 ETH = 1e18 wei，存储 ETH 余额需要至少 18 位小数
-- 大额持仓 + 微小手续费 → Decimal256(18) 是必须

CREATE TABLE crypto_balances (
    address String,
    eth_balance Decimal256(18)    -- 完整精度，无下溢
) ENGINE = MergeTree;
```

### DuckDB（HUGEINT 后端）

```sql
CREATE TABLE accounts (
    balance DECIMAL(19, 4),        -- 默认是 HUGEINT 后端 (38 位上限)
    rate DECIMAL(7, 4)
);

-- 编码:
-- DECIMAL(p, s)  →  根据 p 选最小后端
-- p ≤ 4:    INT16   (2 字节)
-- p ≤ 9:    INT32   (4 字节)
-- p ≤ 18:   INT64   (8 字节)
-- p ≤ 38:   HUGEINT (16 字节)
-- 自动选最优，开发者无需关心
```

### SQLite（特例：仅 REAL）

SQLite 没有真正的精确十进制类型：

```sql
-- 列亲和性（type affinity）：声明 DECIMAL 实际是 NUMERIC（弱类型）
CREATE TABLE accounts (balance DECIMAL(19, 4));
-- 实际: 整数存为 INTEGER，小数存为 REAL (binary64) 或 TEXT

INSERT INTO accounts VALUES (99.99);
-- 内部: 实际存为 REAL = 99.989999999999...

-- 解决方案 1: 用整数 cents（金融行业广泛使用）
CREATE TABLE accounts (balance_cents INTEGER);
INSERT INTO accounts VALUES (9999);   -- $99.99 → 9999 cents

-- 解决方案 2: 用 TEXT 存十进制字符串（应用层处理）
CREATE TABLE accounts (balance TEXT);
INSERT INTO accounts VALUES ('99.99');
-- SUM/AVG 不可用，需应用层

-- 解决方案 3: SQLite 扩展 (decimal extension)
-- 第三方扩展提供精确十进制，但非内置
```

### H2 / HSQLDB / Derby（Java 生态）

```sql
-- H2: Java BigDecimal 直接存储, 精度可达 100,000 位（理论）
CREATE TABLE accounts (balance DECIMAL(50, 10));

-- HSQLDB: 同样基于 BigDecimal, 内存限制内任意精度
CREATE TABLE accounts (balance DECIMAL);

-- Derby: 31 位精度（packed decimal）
CREATE TABLE accounts (balance DECIMAL(31, 4));
```

### Firebird（v4 升级）

```sql
-- Firebird 3.x 之前: DECIMAL/NUMERIC 最大 18 位精度
-- Firebird 4.0 (2021): 升级到 38 位

-- Firebird 4.0+
CREATE TABLE accounts (
    balance DECIMAL(38, 4),
    rate NUMERIC(38, 18)
);

-- Firebird 也支持 DECFLOAT
CREATE TABLE accounts2 (
    big_balance DECFLOAT(34),
    small_balance DECFLOAT(16)
);
```

### Spark SQL / Hive / Flink SQL（JVM 通用）

```sql
-- 共同点：基于 Java BigDecimal
-- 上限 38 位（Hive 0.13+, Spark 1.5+）
CREATE TABLE accounts (balance DECIMAL(38, 18));

-- 算术规则（IEEE 754-2008 风格）:
-- DECIMAL(p1, s1) + DECIMAL(p2, s2) = DECIMAL(max(s1,s2)+max(p1-s1,p2-s2)+1, max(s1,s2))
-- 上限 38，超出会丢失精度

-- 著名陷阱：聚合溢出
SELECT SUM(amount) FROM big_table;
-- amount 是 DECIMAL(19,4)
-- 1 亿行 × 99.99 = 9.999e9 (10 位整数)
-- SUM 类型自动升至 DECIMAL(29,4)，仍在范围内
-- 但 1000 亿行 × 99.99 可能超出 38 位 → 错误或近似

-- Spark 3.0+ 配置：
SET spark.sql.decimalOperations.allowPrecisionLoss = false;
-- 不允许精度损失，超限报错而非默默降级

-- Hive 自定义精度（早期版本配置）
SET hive.optimize.bucketmapjoin = true;
```

### Trino / Presto / Athena

```sql
-- 标准 DECIMAL(p, s)，最大 38 位
CREATE TABLE accounts (balance DECIMAL(19, 4));

-- 内部:
-- p ≤ 18: int64
-- p > 18: int128

-- 算术结果类型推导（精确，但可能溢出）:
-- DECIMAL(19, 4) + DECIMAL(19, 4) = DECIMAL(20, 4)  -- p+1 防溢出
-- DECIMAL(19, 4) * DECIMAL(19, 4) = DECIMAL(38, 8)  -- 加 scale, 加 precision
-- DECIMAL(19, 4) / DECIMAL(19, 4) = DECIMAL(38, 6)  -- 默认增加 6 位 scale

-- 用户通过 CAST 强制保留精度
SELECT CAST(amount AS DECIMAL(38, 18)) / qty FROM orders;
```

### Vertica / Redshift（MPP 分析）

```sql
-- Vertica: NUMERIC/DECIMAL 通用
CREATE TABLE accounts (balance NUMERIC(19, 4));
-- 内部: 8-24 字节定长（精度决定）

-- Redshift: DECIMAL/NUMERIC 38 位上限
CREATE TABLE accounts (balance DECIMAL(19, 4));
-- 内部: 8-16 字节
-- 列存压缩对 DECIMAL 极有效（聚集分布）

-- Redshift Spectrum 中数据类型映射 Parquet
-- Parquet DECIMAL 限制: 38 位（受 INT128 限制）
```

### Teradata（金融老兵）

```sql
-- Teradata 的 DECIMAL/NUMERIC 兼容 Oracle 的 NUMBER 习惯
CREATE TABLE accounts (
    balance DECIMAL(19, 4),
    rate NUMBER(7, 4)              -- Oracle 兼容
);

-- 默认舍入模式 HALF_EVEN（银行家）
-- 数据仓库历史悠久，金融客户众多
```

## PostgreSQL money 类型陷阱深度剖析

PG 的 money 是反面教材，值得详细分析。

### 陷阱 1：数值意义随 lc_monetary 变化

```sql
-- 场景：PG 服务器从 en_US locale 备份，restore 到 ja_JP 服务器
SET lc_monetary = 'en_US.UTF-8';
SELECT '$1234.56'::money;       -- 1234.56 美元

-- pg_dump 输出: COPY ... '$1,234.56'
-- 在 ja_JP 服务器 restore:
SET lc_monetary = 'ja_JP.UTF-8';
SELECT '1234.56'::money;        -- 解析为 1234 日元（小数被截断）
SELECT '1,234.56'::money;       -- 报错或解析失败
```

### 陷阱 2：scale 隐式由 locale 决定

```sql
-- en_US:  scale = 2 (cents)
-- ja_JP:  scale = 0 (no decimal)
-- bh_IN:  scale 可能 3
-- 同一个 money 字段在不同 locale 下精度不同

-- 内部表示:
-- en_US 下 $1.00 存为 int64 = 100
-- ja_JP 下 ¥1   存为 int64 = 1
-- 同一 binary 在两个 locale 下意义完全不同
```

### 陷阱 3：与 numeric 不能直接混算

```sql
SELECT '$10'::money + 5;
-- 错误: operator does not exist: money + integer

SELECT '$10'::money + 5::money;     -- 必须显式转换
SELECT '$10'::money + 5::numeric;   -- 错误，类型不匹配

-- 必须用强制转换:
SELECT '$10'::money + (5::numeric * '1'::money);
```

### 陷阱 4：缺乏货币代码语义

```sql
-- 没有办法在 money 列中区分 USD vs EUR vs JPY
-- 实际生产系统必须用复合列:
CREATE TABLE proper_design (
    amount NUMERIC(19, 4),
    currency CHAR(3) NOT NULL CHECK (currency IN ('USD', 'EUR', 'JPY', 'GBP', ...))
);

-- 而 money 列假设全表单一货币（lc_monetary 决定）
-- 这在多货币系统中完全不可用
```

### 陷阱 5：聚合的精度行为

```sql
-- money 的 SUM 仍是 money，受 scale 限制
-- 如果一笔交易有 1e-5 精度需求（如 forex 报价）：
INSERT INTO trades VALUES ('$100.12345');   -- en_US 下被截断为 $100.12

-- 唯一解决方案：不用 money
CREATE TABLE trades (amount NUMERIC(20, 8));  -- 8 位小数支持 forex
```

### 官方建议

PostgreSQL 文档明确：

> "Use of the money data type is discouraged. Use the numeric type instead and cast to money for display purposes."

社区 consensus：**永远不要用 PostgreSQL 的 money 类型**。

## DECFLOAT（IEEE 754-2008）深度剖析

DECFLOAT 是 IEEE 754-2008 标准的十进制浮点。它是 binary 浮点的"修正"，让浮点真正能用于金融。

### IEEE 754-2008 三种格式

| 格式 | 字节 | 精度（十进制位）| 指数范围 | 标记 |
|------|------|--------------|---------|------|
| decimal32 | 4 | 7 | ±96 | 罕见 |
| decimal64 | 8 | 16 | ±384 | DECFLOAT(16) |
| decimal128 | 16 | 34 | ±6144 | DECFLOAT(34) |

### 内部编码（DPD）

DECFLOAT 用 DPD（Densely Packed Decimal）编码，每 10 位二进制存 3 位十进制：

```
decimal128 (16 字节 = 128 位):
  1 位符号
  5 位组合（指数高位 + 系数高位）
  12 位指数延续
  110 位 DPD 编码的系数（共 33 个十进制位 + 高位）
  总精度: 34 位十进制
```

### 算术性质

```sql
-- 与 binary float 对比
-- binary64: 0.1 + 0.2 = 0.30000000000000004 (不精确)
-- DECFLOAT: 0.1 + 0.2 = 0.3                 (精确)

-- 与 packed decimal 对比
-- DECIMAL(34, 10) + DECIMAL(34, 10): 必须对齐 scale, 慢
-- DECFLOAT(34) + DECFLOAT(34):       浮点对齐, 硬件支持, 5-10x 快

-- IEEE 754-2008 规定 5 种舍入模式
-- ROUND_CEILING        向 +∞
-- ROUND_FLOOR          向 -∞
-- ROUND_HALF_UP        4 舍 5 入
-- ROUND_HALF_DOWN      4 舍 5 入但 5 向下
-- ROUND_HALF_EVEN      银行家（默认）
```

### 硬件加速

| 处理器 | DECFLOAT 硬件支持 |
|--------|----------------|
| IBM POWER6+ | DFP unit |
| IBM z9+ | DFP unit |
| Intel x86 | 软件实现（Intel DFP Library）|
| ARM | 软件实现 |

POWER 系列处理器有专门的 DFP 单元，DECFLOAT 接近 binary float 性能。x86 是软件库实现，比 packed decimal 快但比 binary float 慢。

### DECFLOAT 支持矩阵

| 引擎 | DECFLOAT(16) | DECFLOAT(34) | 引入版本 |
|------|------------|------------|---------|
| DB2 LUW | 是 | 是 | 9.5 (2007) |
| DB2 z/OS | 是 | 是 | 9.7 (2009) |
| Firebird | 是 | 是 | 4.0 (2021) |
| SAP HANA | -- | 是（SMALLDECIMAL）| 早期 |
| Oracle | -- | -- | 用 NUMBER 替代 |
| PostgreSQL | -- | -- | 不支持 |
| MySQL | -- | -- | 不支持 |

### 何时选 DECFLOAT vs DECIMAL(p,s)

| 场景 | DECIMAL(p,s) | DECFLOAT |
|------|------------|---------|
| 已知固定 scale（如 cents）| 推荐 | 浪费 |
| 多 scale 共存（forex, commodity）| 麻烦 | 推荐 |
| 极端精度需求（>38 位）| 不支持 | DECFLOAT(34) |
| 硬件加速（POWER/z 平台）| 软件 | 硬件加速 |
| 跨平台兼容 | 标准 | 较新 |
| 财务报表（合规精确）| 推荐 | 谨慎 |
| 科学计算 | 浪费 | 推荐 |

## 常见货币列设计模式

### 模式 1：单货币 + DECIMAL(19, 4)

最简单常用，适合单货币应用：

```sql
CREATE TABLE orders (
    order_id BIGINT PRIMARY KEY,
    customer_id BIGINT,
    amount DECIMAL(19, 4),
    created_at TIMESTAMPTZ
);
-- 假设系统全 USD，应用层确保
```

### 模式 2：金额 + 货币代码

多货币系统标配：

```sql
CREATE TABLE orders (
    order_id BIGINT PRIMARY KEY,
    customer_id BIGINT,
    amount DECIMAL(19, 4),
    currency CHAR(3) NOT NULL,
    -- ISO 4217: USD, EUR, JPY, ...
    CHECK (currency IN ('USD', 'EUR', 'GBP', 'JPY', 'CNY', 'HKD', ...))
);

-- 应用层防止跨货币聚合:
-- SELECT SUM(amount) FROM orders;  -- 错误！混合货币
-- SELECT currency, SUM(amount) FROM orders GROUP BY currency;  -- 正确
```

### 模式 3：金额 + 货币 + 报告货币

国际企业财报需要：

```sql
CREATE TABLE financial_transactions (
    txn_id BIGINT PRIMARY KEY,
    txn_date DATE,
    -- 原始货币
    amount DECIMAL(19, 4),
    currency CHAR(3),
    -- 转换为报告货币（如 USD）
    amount_usd DECIMAL(19, 4),
    fx_rate DECIMAL(13, 8),
    fx_rate_source VARCHAR(64),
    fx_rate_timestamp TIMESTAMPTZ
);
```

### 模式 4：以 cents/wei 为整数

避免任何浮点风险：

```sql
-- SQLite / 嵌入式
CREATE TABLE orders (
    order_id INTEGER PRIMARY KEY,
    amount_cents BIGINT,    -- $99.99 = 9999 cents
    currency CHAR(3)
);

-- 应用层负责: amount = amount_cents / 100.0
-- 优势: 100% 精确, 整数加法极快
-- 劣势: 阅读时需转换；不适合多 scale 货币
```

### 模式 5：极端精度（加密货币）

加密货币的 wei/satoshi 单位需要超高精度：

```sql
-- ClickHouse 加密货币
CREATE TABLE eth_balances (
    address FixedString(42),
    balance Decimal256(18)         -- 18 位小数支持 wei 精度
) ENGINE = MergeTree;

-- 1 ETH = 1e18 wei
-- 大额持仓 + 微小手续费 → Decimal256(18) 完整保留
```

## 算术、聚合与精度推导

### 标准算术结果精度（多数引擎一致）

| 运算 | 输入 | 结果精度 | 备注 |
|------|------|---------|------|
| `+` `-` | DEC(p1,s1), DEC(p2,s2) | DEC(max(s1,s2)+max(p1-s1,p2-s2)+1, max(s1,s2)) | +1 防溢 |
| `*` | DEC(p1,s1), DEC(p2,s2) | DEC(p1+p2, s1+s2) | 直接求和 |
| `/` | DEC(p1,s1), DEC(p2,s2) | 实现相关 | 通常增加 scale |
| `MOD` | DEC(p1,s1), DEC(p2,s2) | DEC(min(p1-s1, p2-s2)+max(s1,s2), max(s1,s2)) | -- |

### 各引擎差异

| 引擎 | 加法 | 乘法 | 除法 |
|------|------|------|------|
| MySQL | 标准 | 标准 | 增加 4 位 scale (`div_precision_increment`) |
| Oracle | 标准 | 标准 | 取最大可能精度 |
| SQL Server | 标准 | 标准（结果上限 38）| 复杂规则，最少保留 6 位 |
| Spark SQL | 标准（上限 38）| 标准（上限 38）| 增加 6 位 scale |
| Trino | 标准 | 标准 | 增加 6 位 scale |
| ClickHouse | 严格类型 | 严格类型 | 不自动扩展 |
| PostgreSQL | numeric 任意精度 | 任意精度 | 任意精度 |

### 聚合的精度

```sql
-- 大多数引擎：SUM 类型自动扩展
-- DECIMAL(19, 4) → SUM → DECIMAL(38, 4)
-- 处理 1e10+ 行的累加不易溢出

-- 但是 SQL Server 上限严格：
-- DECIMAL(19, 4) → SUM → DECIMAL(38, 4)  上限 38

-- Oracle: NUMBER 自适应

-- Spark SQL 配置:
SET spark.sql.decimalOperations.allowPrecisionLoss = false;
-- 防止默默 truncate
```

## 货币格式化

### PostgreSQL

```sql
-- 标准 to_char
SELECT to_char(99999.95, 'FM999G999D99');           -- 99,999.95 (无货币符)
SELECT to_char(99999.95, 'L999G999D99');            -- $99,999.95 (locale 货币符)
SELECT to_char(99999.95, 'FML999G999D99');          -- $99,999.95 (无前导空格)

-- 不同 locale
SET lc_monetary = 'de_DE.UTF-8';
SELECT to_char(99999.95, 'L999G999D99');            -- €99.999,95
```

### Oracle

```sql
SELECT TO_CHAR(99999.95, 'L999G999D99', 'NLS_NUMERIC_CHARACTERS=''.,'' NLS_CURRENCY=''$''')
FROM dual;   -- $99,999.95

-- 国际格式
SELECT TO_CHAR(99999.95, 'L999G999D99', 'NLS_TERRITORY=''GERMANY''')
FROM dual;   -- €99.999,95
```

### SQL Server

```sql
SELECT FORMAT(99999.95, 'C', 'en-US');  -- $99,999.95
SELECT FORMAT(99999.95, 'C', 'de-DE');  -- 99.999,95 €
SELECT FORMAT(99999.95, 'C', 'ja-JP');  -- ¥99,999.95
SELECT FORMAT(99999.95, 'C', 'fr-FR');  -- 99 999,95 €
```

### MySQL

```sql
SELECT FORMAT(99999.95, 2);                       -- 99,999.95
SELECT FORMAT(99999.95, 2, 'en_US');              -- 99,999.95
SELECT FORMAT(99999.95, 2, 'de_DE');              -- 99.999,95
-- 注意：MySQL FORMAT 不输出货币符号
SELECT CONCAT('$', FORMAT(99999.95, 2));          -- $99,999.95
```

### Snowflake

```sql
SELECT TO_VARCHAR(99999.95, '$999,999.99');       -- $99,999.95
SELECT TO_CHAR(99999.95, 'L999G999D99');          -- 部分支持
```

### BigQuery

```sql
SELECT FORMAT('%\'.2f', 99999.95);                -- 99,999.95
SELECT CONCAT('$', FORMAT('%\'.2f', 99999.95));   -- $99,999.95
```

## 性能特征

### 字节数 vs 算术速度

| 类型 | 字节 | + - 速度 | × ÷ 速度 | 适用场景 |
|------|------|---------|---------|---------|
| binary float (DOUBLE) | 8 | 极快（1 cycle）| 快（4-8 cycle）| 精度无所谓 |
| INT64 (cents 模式) | 8 | 极快 | 快 | 单货币定 scale |
| DECIMAL(18, 4) | 8-9 | 快（int64 + 调整）| 中等 | 一般货币 |
| DECIMAL(38, 4) | 16-17 | 中等（int128）| 慢 | 高精度 |
| DECFLOAT(16) | 8 | 中等（DFP）| 快（DFP 硬件）| 浮点货币 |
| DECFLOAT(34) | 16 | 中等（DFP）| 快（DFP 硬件）| 高精度浮点 |
| DECIMAL(65, 30) | 30 | 慢 | 很慢 | 极端精度 |
| numeric（PG）| 变长 | 任意慢 | 极慢 | 无上限 |

### 列存压缩

DECIMAL 在列存（Parquet/ORC/ClickHouse MergeTree）压缩极好：

- 货币金额聚集：99.99 / 89.99 / 199.99 等高位重复
- DELTA 编码效率高
- 字典编码对常见金额（如 $9.99, $19.99）非常有效
- 典型压缩率 5-10x

### Vectorization

现代向量化引擎（DuckDB, ClickHouse, Velox, Photon）对 DECIMAL 有 SIMD 优化：

```
DECIMAL(p, s) 加法在 SIMD 下:
  - 4 个 INT32 同时加（DECIMAL32）
  - 2 个 INT64 同时加（DECIMAL64）
  - 1 个 INT128（无 SIMD 加速）

性能比标量提升 2-4x
```

## 设计争议

### 争议 1：MONEY 类型该不该独立存在

支持方（SQL Server / Sybase 阵营）:
- 表达力强：`MONEY` 比 `DECIMAL(19,4)` 直观
- 字面量解析方便（`$1234.56`）
- 历史兼容性

反对方（PG 文档 / Oracle / 多数现代引擎）:
- locale 副作用风险（PG 教训）
- 4 位小数 scale 不够通用（forex 需要 6-8）
- 不支持多货币代码
- 已被 DECIMAL(p,s) 完全覆盖

**主流共识**：原生 MONEY 类型逐渐被淘汰，新引擎不再加入。

### 争议 2：DECIMAL 上限设多少

| 上限 | 代表 | 评价 |
|------|------|------|
| 31 | DB2 / Derby | 历史 packed decimal 限制 |
| 38 | Oracle / SQL Server / 多数 | 业界事实标准 |
| 65 | MySQL 系 | 异类，覆盖任意货币 |
| 76 | ClickHouse / BigQuery / DatabendDB | 加密货币动机 |
| 100,000 | H2 | Java BigDecimal 直通 |
| 任意 | PostgreSQL numeric / HSQLDB | 学术理想 |

38 位实际上覆盖几乎所有金融场景：

```
38 位精度可表示:
  - 全球 GDP（约 1e14 USD）+ cents = 16 位整数 + 2 位小数
  - 国家债务（约 1e13）+ 8 位小数 = 21 位
  - 企业市值（约 1e12）+ 高精度 forex（8-10 位）= 22 位
  - 极端高精度场景（加密货币 wei）→ 38 位 / 76 位
```

### 争议 3：默认舍入模式

- HALF_EVEN（银行家）：IEEE 754 默认，长期累积无偏，但反直觉
- HALF_UP（普通）：直觉，但有累积偏差
- HALF_AWAY_FROM_ZERO：与 HALF_UP 在正数时相同

不同引擎的默认选择反映其设计哲学：
- DB2 / PG / ClickHouse / DuckDB：HALF_EVEN（标准/科学）
- SQL Server / MySQL / Oracle：HALF_UP / HALF_AWAY_FROM_ZERO（直觉/兼容）

### 争议 4：DECIMAL vs DECFLOAT 的未来

DECFLOAT 优势：
- 浮点性能（硬件支持）
- 精度跟随数值（适合 forex / 多 scale）
- IEEE 754 标准

DECFLOAT 劣势：
- 已知 scale 时浪费空间
- 学习曲线（开发者需理解 IEEE 754-2008）
- 工具链支持不足（驱动、ORM）

主流趋势：DECFLOAT 在 IBM 系（DB2 / 主机）和 SAP 系（HANA）有市场，但 Oracle/PG/MySQL 系坚守 packed decimal/scaled int。短期内不会统一。

## 实现建议（引擎开发者）

### 选择内部表示

```
基本决策树:

是否需要 IEEE 754-2008 兼容?
├── 是 → DECFLOAT (binary DPD 编码)
└── 否 → 是否极端精度 (>38 位)?
        ├── 是 → 变长 (PG numeric / Java BigDecimal)
        └── 否 → 是否固定 scale 的金融场景?
                ├── 是 → scaled int (int32/int64/int128)
                └── 否 → packed decimal (BCD) 或 scaled int128
```

### 推荐 scaled int 实现

```rust
// scaled int128 风格
struct Decimal {
    value: i128,    // 包含符号
    scale: u8,      // 0-37（DECIMAL 38 上限）
}

impl Decimal {
    fn add(&self, other: &Decimal) -> Result<Decimal> {
        // 对齐 scale
        let target_scale = self.scale.max(other.scale);
        let a = self.value * 10_i128.pow((target_scale - self.scale) as u32);
        let b = other.value * 10_i128.pow((target_scale - other.scale) as u32);
        let sum = a.checked_add(b).ok_or(Overflow)?;
        Ok(Decimal { value: sum, scale: target_scale })
    }

    fn mul(&self, other: &Decimal) -> Result<Decimal> {
        // 直接相乘，scale 求和
        let product = self.value.checked_mul(other.value).ok_or(Overflow)?;
        let scale = self.scale.checked_add(other.scale).ok_or(InvalidScale)?;
        Ok(Decimal { value: product, scale })
    }
}
```

### SIMD 向量化

```
DECIMAL(p, s) 列存储 → 选择最小后端
对齐 scale 后批量计算:
  - DECIMAL32 (int32): SSE2 一次 4 个加法
  - DECIMAL64 (int64): AVX2 一次 4 个加法
  - DECIMAL128: 通常无 SIMD（int128 不是原生）

聚合的高效实现:
  - 累加器用更宽类型 (DECIMAL128 累加 DECIMAL32)
  - 防止中间溢出
  - 结果转换回原类型
```

### 溢出检测

```
DECIMAL 算术必须检测溢出:
  - 加减: checked_add / checked_sub
  - 乘法: checked_mul
  - 除法: 可能下溢到 0 (scale 不足)

向量化场景:
  - 标量: 每次操作检测
  - 批量: 一批结束后检查 OVERFLOW 标志
  - 推荐: 用更宽类型做中间运算 (int64 → int128)，结果回检
```

### 与优化器交互

```
1. 类型推导:
   DEC(p1,s1) + DEC(p2,s2) = DEC(min(38, max(s1,s2)+max(p1-s1,p2-s2)+1), max(s1,s2))
   超出 38 时:
   - 严格模式: 报错 (Spark SQL allowPrecisionLoss=false)
   - 宽松模式: 截断 scale, 保留 precision
   
2. 行数估计:
   DEC 列基数估计:
   - 货币金额聚集 (1.99, 9.99, ...) → NDV 较低
   - 利率/汇率 → NDV 高

3. 索引选择:
   B+ 树 / 列存索引对 DEC 都有效
   注意: 跨 scale 比较需对齐
```

### 测试要点

```
基本运算:
  - 加减乘除的精度推导
  - 边界值: 0, ±最大, ±最小非零
  - scale 不足导致下溢
  - precision 超限的处理

特殊值:
  - 负数表示 (二补还是符号位)
  - +0 vs -0 (DECFLOAT 区分, scaled int 不区分)
  - NULL 处理

聚合:
  - SUM/AVG 的中间累加器宽度
  - 大量行（1e8+）累加无精度损失
  - 不同 scale 列的 SUM

舍入模式:
  - 5 种 IEEE 754 模式各自正确性
  - SET ROUND MODE 切换
  - 应用于 ROUND/CAST/DIV

跨引擎兼容:
  - DEC 序列化（与 Postgres / MySQL 协议）
  - Parquet DEC 编码
  - Arrow DEC 类型
```

## 关键发现

1. **原生 MONEY 类型正在式微**：仅约 12 个引擎仍提供，新引擎几乎不再加入。SQL Server/Sybase 的 MONEY 是历史遗留，PG 的 money 被官方反对，主流方案是 DECIMAL/NUMERIC。

2. **PostgreSQL money 是反面教材**：locale 决定 scale 的设计导致跨服务器迁移、多货币混合、精度需求等多种场景全部失效。永远不要用，应使用 numeric。

3. **38 位是事实精度标准**：Oracle NUMBER、SQL Server DECIMAL、Snowflake NUMBER、BigQuery NUMERIC、Trino DECIMAL、Spark SQL DECIMAL 都设定 38 位上限。源于 int128 的 38 位十进制范围。

4. **MySQL 65 位是异类**：5.0 (2005) 后 MySQL DECIMAL 提升到 65 位，覆盖任意货币需求。每 9 位十进制压成 4 字节。MariaDB/TiDB/SingleStore 继承。

5. **DB2 引领 DECFLOAT**：自 9.5 (2007) 起，DB2 LUW 加入 IEEE 754-2008 DECFLOAT(34) 和 DECFLOAT(16)。Firebird 4.0 (2021)、SAP HANA 跟进。Oracle/PG/MySQL 至今未加。

6. **SAP HANA 走 SMALLDECIMAL 路线**：16 字节 IEEE 754-2008 decimal128 作为核心数值类型，配合"金额+货币代码"列模型。是 ERP 行业的特化设计。

7. **ClickHouse / BigQuery 76 位**：为加密货币和极端金融场景，提供 Decimal256 / BIGNUMERIC（76 位精度）。BigQuery 自 2020 加入 BIGNUMERIC。

8. **SQLite 没有真正的精确十进制**：仅 REAL（binary64），所有 DECIMAL 声明在亲和性下退化。生产应用必须用整数 cents 或 TEXT 存储字符串。

9. **舍入模式分两派**：HALF_EVEN（DB2/PG/ClickHouse/DuckDB，IEEE 754 默认）vs HALF_UP（SQL Server/MySQL/Oracle，直觉默认）。混合时必须显式指定。

10. **Oracle NUMBER(p,s) 是行业事实标准**：38 位精度、变长存储、跨版本稳定、NLS 国际化。所有新引擎在设计货币类型时都参考它。

11. **货币列设计模式**：业界共识是「金额 DECIMAL(19,4) + 货币代码 CHAR(3) ISO 4217」。不要依赖单一 MONEY 类型表达多货币。

12. **DECIMAL 列存压缩极好**：货币金额聚集分布（99.99 / 19.99 等），列存引擎（Parquet/ClickHouse/Vertica）压缩率常达 5-10x。是 DECIMAL 在分析场景比 DOUBLE 更实用的隐形优势。

## 参考资料

- ISO/IEC 9075:1992 (SQL:1992) - DECIMAL/NUMERIC 类型定义
- IEEE 754-2008 - decimal floating-point 标准
- ISO 4217 - Currency codes (USD/EUR/JPY/...)
- PostgreSQL Documentation: [Monetary Types](https://www.postgresql.org/docs/current/datatype-money.html)
- SQL Server Documentation: [money and smallmoney](https://learn.microsoft.com/en-us/sql/t-sql/data-types/money-and-smallmoney-transact-sql)
- Oracle Documentation: [NUMBER Datatype](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Data-Types.html#GUID-75209AF6-476D-4C44-A5DC-5FA70D701B78)
- MySQL Reference Manual: [The DECIMAL Data Type](https://dev.mysql.com/doc/refman/8.0/en/precision-math-decimal-characteristics.html)
- DB2: [DECFLOAT Data Type](https://www.ibm.com/docs/en/db2/11.5?topic=list-decfloat)
- SAP HANA: [SQL Reference - Numeric Types](https://help.sap.com/docs/SAP_HANA_PLATFORM)
- Snowflake: [Numeric Data Types](https://docs.snowflake.com/en/sql-reference/data-types-numeric)
- BigQuery: [NUMERIC and BIGNUMERIC](https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types#decimal_types)
- ClickHouse: [Decimal](https://clickhouse.com/docs/en/sql-reference/data-types/decimal)
- Cowlishaw, Mike. "Decimal Floating-Point: Algorism for Computers" (2003) - DPD 编码
- IBM: "DPD vs BID encoding of decimal floating-point" - DECFLOAT 内部
- Sybase ASE Reference Manual: [Money datatype](https://help.sap.com/docs/SAP_ASE)
