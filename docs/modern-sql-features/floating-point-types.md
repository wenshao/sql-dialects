# 浮点类型 (Floating-Point Types)

`SELECT 0.1 + 0.2` 在 PostgreSQL、MySQL、Oracle 中都返回 `0.3`——但当你比较 `(0.1 + 0.2) = 0.3` 时，它返回 `false`。这不是 bug，而是 IEEE 754 二进制浮点数对十进制小数的有限精度表示。浮点类型是 SQL 引擎中最容易被忽视、却又最容易踩坑的数值类型——从精度选择、存储成本，到 ML 工作负载的 BFLOAT16/FP16，再到金融场景的 DECFLOAT，每一个决策都会显著影响系统行为。本文系统梳理 45+ SQL 方言对浮点类型的支持，覆盖 IEEE 754 二进制浮点、SQL:2003 DECFLOAT 十进制浮点，以及 ML 时代新兴的 16 位浮点格式。

## IEEE 754 二进制浮点 vs DECFLOAT 十进制浮点

浮点数是计算机表示实数的核心机制，但 "浮点" 一词覆盖了两种本质不同的设计哲学。

### 二进制浮点 (Binary Float)

绝大多数 CPU 直接支持的浮点格式遵循 IEEE 754-1985/2008 标准，使用二进制基数 (基数 2)。一个 IEEE 754 浮点数由三部分组成：

```
+----------+--------------+-------------------+
|  符号位  |  指数位       |   尾数位 (mantissa) |
+----------+--------------+-------------------+
   1 bit       8/11 bit         23/52 bit
```

- **REAL / FLOAT32 / `binary32`**：1 + 8 + 23 = 32 位，精度约 7 位十进制有效数字，范围约 ±3.4 × 10³⁸
- **DOUBLE / FLOAT64 / `binary64`**：1 + 11 + 52 = 64 位，精度约 15-17 位十进制有效数字，范围约 ±1.8 × 10³⁰⁸

二进制浮点对硬件友好（CPU 有专用 FPU 指令，GPU 有 SIMD 支持），运算速度极快，但无法精确表示某些十进制小数（如 `0.1`），导致金融、会计场景中的累积误差。

### 十进制浮点 (Decimal Float / DECFLOAT)

为解决二进制浮点的十进制精度问题，IEEE 754-2008 引入了十进制浮点格式 (基数 10)，SQL:2016 标准化为 `DECFLOAT(p)`：

```
DECFLOAT(16): 1 + 5 + 50 = 64 位 (decimal64), 16 位十进制有效数字
DECFLOAT(34): 1 + 14 + 110 = 128 位 (decimal128), 34 位十进制有效数字
```

DECFLOAT 能精确表示 `0.1`、`0.01` 等常见小数，避免累积误差，但需要软件模拟（少数主机 CPU 如 IBM POWER 提供硬件支持），运算速度比二进制浮点慢一个数量级。

### 精度 / 范围 / 速度的三角权衡

| 维度 | REAL (4B) | DOUBLE (8B) | DECFLOAT(34) | DECIMAL(38) |
|------|-----------|-------------|--------------|-------------|
| 存储大小 | 4 字节 | 8 字节 | 16 字节 | 16-17 字节 |
| 精度 | ~7 位十进制 | ~15 位十进制 | 精确 34 位十进制 | 精确 38 位十进制 |
| 范围 | ±3.4 × 10³⁸ | ±1.8 × 10³⁰⁸ | ±10⁶¹⁴⁵ | ±10³⁸ |
| 硬件加速 | 是 (FPU) | 是 (FPU) | 部分 (POWER) | 否 (软件) |
| 运算速度 | 最快 | 快 | 慢 (10x+) | 最慢 |
| 十进制精确性 | 无 | 无 | 是 | 是 |
| 典型用途 | 图形/科学计算 | 通用数值/科学计算 | 金融/会计 | 金融/会计 |

### ML 工作负载推动的新格式

随着深度学习兴起，传统 32/64 位浮点对训练和推理来说既"过于精确"又"过于昂贵"。三种 16 位浮点格式因此进入数据库：

| 格式 | 总位数 | 符号 | 指数 | 尾数 | 精度 | 范围 |
|------|--------|------|------|------|------|------|
| IEEE 754 `binary16` (HALF FLOAT, FP16) | 16 | 1 | 5 | 10 | ~3-4 位十进制 | ±6.5 × 10⁴ |
| BFLOAT16 (Brain Float 16) | 16 | 1 | 8 | 7 | ~2-3 位十进制 | ±3.4 × 10³⁸ (同 FP32) |
| TF32 (TensorFloat-32, NVIDIA) | 19 | 1 | 8 | 10 | ~3-4 位十进制 | ±3.4 × 10³⁸ |

BFLOAT16 与 FP32 共享指数位数 (8 位)，因此**范围相同**，但尾数仅 7 位（相比 FP16 的 10 位、FP32 的 23 位）。这使 BFLOAT16 成为深度学习训练的主流 16 位格式——梯度数值范围大但对精度容忍度高，BFLOAT16 比 FP16 更不易溢出/下溢。

ClickHouse 在 24.6 (2024 年 6 月) 引入 `BFloat16` 类型，是首个原生支持该类型的开源 OLAP 引擎，主要面向向量搜索、机器学习特征存储等场景。

## SQL 标准的浮点定义

### SQL:1992 — REAL / DOUBLE PRECISION / FLOAT(p)

ISO/IEC 9075:1992 在 Section 4.4 (Numbers) 定义了三个近似数值类型：

```sql
<approximate numeric type> ::=
    FLOAT [ <left paren> <precision> <right paren> ]
  | REAL
  | DOUBLE PRECISION

<precision> ::= <unsigned integer>  -- 二进制位数
```

标准的语义：

- `REAL`: 实现定义的"单精度"浮点，通常映射到 IEEE 754 单精度 (4 字节)
- `DOUBLE PRECISION`: 实现定义的"双精度"浮点，通常映射到 IEEE 754 双精度 (8 字节)
- `FLOAT(p)`: 至少能表示 `p` 个二进制有效位的浮点；`p` 是二进制位数（不是十进制位数！）
- 实现可定义 `REAL` 和 `DOUBLE PRECISION` 的精度阈值；通常 `FLOAT(1..24)` → REAL, `FLOAT(25..53)` → DOUBLE

注意：SQL:1992 的 `FLOAT(p)` 中的 `p` 是**二进制位**，不是十进制位。这一点与 `DECIMAL(p,s)` 的 `p` 是**十进制位**形成鲜明对比。Oracle 是少数严格遵守"FLOAT(p) 中 p 是二进制位"语义的引擎之一。

### SQL:2003 / SQL:2016 — DECFLOAT

ISO/IEC 9075:2003 在 Section 4.5 引入了 `DECFLOAT(p)` 类型 (实际广泛实施在 SQL:2016)：

```sql
<decimal floating-point type> ::=
    DECFLOAT [ <left paren> <precision> <right paren> ]
```

- `DECFLOAT(16)`: 16 位十进制有效数字 (decimal64, 8 字节)
- `DECFLOAT(34)`: 34 位十进制有效数字 (decimal128, 16 字节)

DECFLOAT 与 DECIMAL 的关键区别：

- DECIMAL(p, s) 是定点数 (fixed-point)：精度 p 和小数位 s 都固定
- DECFLOAT(p) 是浮点数：有效数字 p 固定，小数点位置随指数变化

DB2 是最早实现 DECFLOAT 的主流引擎 (DB2 9.5, 2007)。

### IEEE 754 标准的演变

| 版本 | 年份 | 关键特性 |
|------|------|---------|
| IEEE 754-1985 | 1985 | 首个标准，定义二进制 32 位 (single)、64 位 (double) 浮点 |
| IEEE 754-2008 | 2008 | 加入 `binary16` (FP16)、`binary128` (quad)，新增十进制浮点 `decimal32/64/128`、FMA 指令、舍入模式 |
| IEEE 754-2019 | 2019 | 微调 (MIN/MAX 行为、`augmentedAddition` 等)，无重大新格式 |

BFLOAT16 不是 IEEE 754 标准的一部分，但 IEEE 754-2008 的设计原则启发了它。

## 支持矩阵：45+ 数据库浮点类型

### REAL / 单精度 (4 字节)

| 引擎 | REAL 关键字 | 同义名 | 标准合规 | 版本 |
|------|------------|--------|---------|------|
| PostgreSQL | `REAL` | `FLOAT4`, `FLOAT(1..24)` | 是 (IEEE 754) | 全版本 |
| MySQL | `FLOAT` | `FLOAT4` | 是 (IEEE 754) | 全版本 |
| MariaDB | `FLOAT` | `FLOAT4` | 是 (IEEE 754) | 全版本 |
| SQLite | (REAL 亲和性) | -- | REAL 实际为 8B | 全版本 |
| Oracle | -- | `BINARY_FLOAT` (4B) | 是 (IEEE 754, 10g+) | 10g (2003) |
| SQL Server | `REAL` | `FLOAT(1..24)` | 是 (IEEE 754) | 全版本 |
| DB2 | `REAL` | `FLOAT(1..24)` | 是 (IEEE 754) | 全版本 |
| Snowflake | -- | (映射到 DOUBLE) | 否 (无独立 4B) | -- |
| BigQuery | -- | (无 4B) | 否 (仅 FLOAT64) | -- |
| Redshift | `REAL` | `FLOAT4` | 是 (IEEE 754) | 全版本 |
| DuckDB | `REAL` | `FLOAT`, `FLOAT4` | 是 (IEEE 754) | 0.3+ |
| ClickHouse | `Float32` | -- | 是 (IEEE 754) | 全版本 |
| Trino | `REAL` | `FLOAT` (别名) | 是 (IEEE 754) | 全版本 |
| Presto | `REAL` | `FLOAT` (别名) | 是 (IEEE 754) | 全版本 |
| Spark SQL | `FLOAT` | `REAL` | 是 (IEEE 754) | 全版本 |
| Hive | `FLOAT` | -- | 是 (IEEE 754) | 全版本 |
| Flink SQL | `FLOAT` | -- | 是 (IEEE 754) | 全版本 |
| Databricks | `FLOAT` | `REAL` | 是 (IEEE 754) | 全版本 |
| Teradata | `REAL` | -- | 是 (IEEE 754) | 全版本 |
| Greenplum | `REAL` | `FLOAT4` | 是 (IEEE 754) | 继承 PG |
| CockroachDB | `REAL` | `FLOAT4` | 是 (IEEE 754) | 全版本 |
| TiDB | `FLOAT` | -- | 是 (IEEE 754) | 全版本 |
| OceanBase | `FLOAT` (MySQL 模式) | `BINARY_FLOAT` (Oracle 模式) | 是 (IEEE 754) | 全版本 |
| YugabyteDB | `REAL` | `FLOAT4` | 是 (IEEE 754) | 兼容 PG |
| SingleStore | `FLOAT` | -- | 是 (IEEE 754) | 全版本 |
| Vertica | -- | (映射到 DOUBLE) | 否 (无独立 4B) | -- |
| Impala | `FLOAT` | -- | 是 (IEEE 754) | 全版本 |
| StarRocks | `FLOAT` | -- | 是 (IEEE 754) | 全版本 |
| Doris | `FLOAT` | -- | 是 (IEEE 754) | 全版本 |
| MonetDB | `REAL` | `FLOAT(1..24)` | 是 (IEEE 754) | 全版本 |
| CrateDB | `REAL` | -- | 是 (IEEE 754) | 全版本 |
| TimescaleDB | `REAL` | -- | 是 (IEEE 754) | 继承 PG |
| QuestDB | `FLOAT` | -- | 是 (IEEE 754) | 全版本 |
| Exasol | -- | (映射到 DOUBLE) | 否 (无独立 4B) | -- |
| SAP HANA | `REAL` | -- | 是 (IEEE 754) | 全版本 |
| Informix | `SMALLFLOAT` | `REAL` | 是 (IEEE 754) | 全版本 |
| Firebird | `FLOAT` | `FLOAT(1..7)` | 是 (IEEE 754) | 全版本 |
| H2 | `REAL` | `FLOAT(1..24)` | 是 (IEEE 754) | 全版本 |
| HSQLDB | `REAL` | `FLOAT(1..24)` | 是 (IEEE 754) | 全版本 |
| Derby | `REAL` | -- | 是 (IEEE 754) | 全版本 |
| Amazon Athena | `REAL` | `FLOAT` (别名) | 是 (IEEE 754) | 继承 Trino |
| Azure Synapse | `REAL` | `FLOAT(1..24)` | 是 (IEEE 754) | 继承 SQL Server |
| Google Spanner | -- | `FLOAT32` (preview) | 是 (IEEE 754, GA 前) | 预览 |
| Materialize | `REAL` | `FLOAT4` | 是 (IEEE 754) | 兼容 PG |
| RisingWave | `REAL` | `FLOAT4` | 是 (IEEE 754) | 兼容 PG |
| InfluxDB (SQL) | -- | (仅 f64) | 否 (仅 f64) | -- |
| DatabendDB | `Float32` | -- | 是 (IEEE 754) | 全版本 |
| Yellowbrick | `REAL` | `FLOAT4` | 是 (IEEE 754) | 全版本 |
| Firebolt | `REAL` | `FLOAT4` | 是 (IEEE 754) | 全版本 |

> 统计：45 个引擎中，约 41 个支持独立的 4 字节 REAL/FLOAT；4 个 (Snowflake、BigQuery、Vertica、Exasol) 仅支持 8 字节浮点，将 REAL 映射或拒绝。InfluxDB IOx 仅有 `f64`。

### DOUBLE PRECISION / 双精度 (8 字节)

| 引擎 | DOUBLE 关键字 | 同义名 | 标准合规 | 版本 |
|------|--------------|--------|---------|------|
| PostgreSQL | `DOUBLE PRECISION` | `FLOAT8`, `FLOAT(25..53)` | 是 (IEEE 754) | 全版本 |
| MySQL | `DOUBLE` | `DOUBLE PRECISION`, `FLOAT8` | 是 (IEEE 754) | 全版本 |
| MariaDB | `DOUBLE` | `DOUBLE PRECISION`, `FLOAT8` | 是 (IEEE 754) | 全版本 |
| SQLite | (REAL 亲和性) | -- | 是 (IEEE 754) | 全版本 |
| Oracle | -- | `BINARY_DOUBLE` (8B) | 是 (IEEE 754, 10g+) | 10g (2003) |
| SQL Server | `FLOAT` | `FLOAT(53)`, `DOUBLE PRECISION` | 是 (IEEE 754) | 全版本 |
| DB2 | `DOUBLE` | `FLOAT(25..53)`, `DOUBLE PRECISION` | 是 (IEEE 754) | 全版本 |
| Snowflake | `DOUBLE` | `FLOAT`, `DOUBLE PRECISION`, `REAL` | 是 (IEEE 754) | 全版本 |
| BigQuery | `FLOAT64` | `FLOAT` (别名) | 是 (IEEE 754) | 全版本 |
| Redshift | `DOUBLE PRECISION` | `FLOAT8`, `FLOAT` | 是 (IEEE 754) | 全版本 |
| DuckDB | `DOUBLE` | `FLOAT8`, `DOUBLE PRECISION` | 是 (IEEE 754) | 0.3+ |
| ClickHouse | `Float64` | -- | 是 (IEEE 754) | 全版本 |
| Trino | `DOUBLE` | -- | 是 (IEEE 754) | 全版本 |
| Presto | `DOUBLE` | -- | 是 (IEEE 754) | 全版本 |
| Spark SQL | `DOUBLE` | `DOUBLE PRECISION` | 是 (IEEE 754) | 全版本 |
| Hive | `DOUBLE` | `DOUBLE PRECISION` | 是 (IEEE 754) | 全版本 |
| Flink SQL | `DOUBLE` | `DOUBLE PRECISION` | 是 (IEEE 754) | 全版本 |
| Databricks | `DOUBLE` | `DOUBLE PRECISION` | 是 (IEEE 754) | 全版本 |
| Teradata | `DOUBLE PRECISION` | `FLOAT(25..54)` | 是 (IEEE 754) | 全版本 |
| Greenplum | `DOUBLE PRECISION` | `FLOAT8` | 是 (IEEE 754) | 继承 PG |
| CockroachDB | `DOUBLE PRECISION` | `FLOAT8`, `FLOAT(25..53)` | 是 (IEEE 754) | 全版本 |
| TiDB | `DOUBLE` | -- | 是 (IEEE 754) | 全版本 |
| OceanBase | `DOUBLE` (MySQL 模式) | `BINARY_DOUBLE` (Oracle 模式) | 是 (IEEE 754) | 全版本 |
| YugabyteDB | `DOUBLE PRECISION` | `FLOAT8` | 是 (IEEE 754) | 兼容 PG |
| SingleStore | `DOUBLE` | `DOUBLE PRECISION` | 是 (IEEE 754) | 全版本 |
| Vertica | `DOUBLE PRECISION` | `FLOAT`, `REAL` | 是 (IEEE 754) | 全版本 |
| Impala | `DOUBLE` | `REAL` | 是 (IEEE 754) | 全版本 |
| StarRocks | `DOUBLE` | -- | 是 (IEEE 754) | 全版本 |
| Doris | `DOUBLE` | -- | 是 (IEEE 754) | 全版本 |
| MonetDB | `DOUBLE` | `FLOAT(25..53)`, `DOUBLE PRECISION` | 是 (IEEE 754) | 全版本 |
| CrateDB | `DOUBLE PRECISION` | -- | 是 (IEEE 754) | 全版本 |
| TimescaleDB | `DOUBLE PRECISION` | -- | 是 (IEEE 754) | 继承 PG |
| QuestDB | `DOUBLE` | -- | 是 (IEEE 754) | 全版本 |
| Exasol | `DOUBLE PRECISION` | `FLOAT`, `DOUBLE` | 是 (IEEE 754) | 全版本 |
| SAP HANA | `DOUBLE` | `DOUBLE PRECISION` | 是 (IEEE 754) | 全版本 |
| Informix | `DOUBLE PRECISION` | `FLOAT` | 是 (IEEE 754) | 全版本 |
| Firebird | `DOUBLE PRECISION` | `FLOAT(8..38)` | 是 (IEEE 754) | 全版本 |
| H2 | `DOUBLE PRECISION` | `FLOAT`, `FLOAT(25..53)` | 是 (IEEE 754) | 全版本 |
| HSQLDB | `DOUBLE` | `FLOAT`, `FLOAT(25..53)` | 是 (IEEE 754) | 全版本 |
| Derby | `DOUBLE` | `DOUBLE PRECISION`, `FLOAT` | 是 (IEEE 754) | 全版本 |
| Amazon Athena | `DOUBLE` | -- | 是 (IEEE 754) | 继承 Trino |
| Azure Synapse | `FLOAT` | `FLOAT(53)` | 是 (IEEE 754) | 继承 SQL Server |
| Google Spanner | `FLOAT64` | -- | 是 (IEEE 754) | 全版本 |
| Materialize | `DOUBLE PRECISION` | `FLOAT8` | 是 (IEEE 754) | 兼容 PG |
| RisingWave | `DOUBLE PRECISION` | `FLOAT8` | 是 (IEEE 754) | 兼容 PG |
| InfluxDB (SQL) | `DOUBLE` | `f64` | 是 (IEEE 754) | 全版本 |
| DatabendDB | `Float64` | -- | 是 (IEEE 754) | 全版本 |
| Yellowbrick | `DOUBLE PRECISION` | `FLOAT8` | 是 (IEEE 754) | 全版本 |
| Firebolt | `DOUBLE PRECISION` | `FLOAT8` | 是 (IEEE 754) | 全版本 |

> 统计：45 个引擎全部支持 8 字节双精度浮点。这是 SQL:1992 强制要求的。

### FLOAT(p) 参数化语义

`FLOAT(p)` 中 `p` 的语义在不同引擎差异极大：

| 引擎 | FLOAT(p) 中 p 的含义 | 阈值规则 | 备注 |
|------|---------------------|---------|------|
| PostgreSQL | 二进制位 | p ≤ 24 → REAL (4B), p ≥ 25..53 → DOUBLE (8B) | 严格遵循 SQL:1992 |
| MySQL | 二进制位 (但实际是十进制总位) | p ≤ 24 → 4B, p ≥ 25 → 8B | MySQL 8.0 起 FLOAT(M,D) 非标准用法弃用 |
| MariaDB | 同 MySQL | 同 MySQL | -- |
| Oracle | 二进制位 | FLOAT(p) 是 NUMBER 子集，p 决定精度 | FLOAT 不是 BINARY_FLOAT |
| SQL Server | 二进制位 | FLOAT(1..24) → REAL (4B), FLOAT(25..53) → 8B | 默认 FLOAT = FLOAT(53) = DOUBLE |
| DB2 | 二进制位 | FLOAT(1..24) → REAL (4B), FLOAT(25..53) → DOUBLE | 同 SQL 标准 |
| Teradata | 二进制位 | FLOAT(1..21) → 4B, FLOAT(22..54) → 8B | 边界略有不同 |
| Firebird | 二进制位 | FLOAT(1..7) → 4B, FLOAT(8..38) → 8B | 边界与他人不同 |
| H2 | 二进制位 | 同 SQL Server | -- |
| HSQLDB | 二进制位 | 同 SQL Server | -- |
| MonetDB | 二进制位 | 同 SQL Server | -- |
| CockroachDB | 二进制位 | 同 SQL Server | -- |
| Snowflake | (无意义) | FLOAT(p) 总是 8B | -- |
| BigQuery | (不接受) | 不支持 FLOAT(p) | 仅 FLOAT64 |
| Redshift | (不接受) | 不支持 FLOAT(p) | 仅 REAL/DOUBLE |
| ClickHouse | (不接受) | 不支持 FLOAT(p) | 仅 Float32/Float64 |
| Trino | (不接受) | 不支持 FLOAT(p) | 仅 REAL/DOUBLE |
| Spark SQL | (不接受) | 不支持 FLOAT(p) | 仅 FLOAT/DOUBLE |
| Hive | (不接受) | 不支持 FLOAT(p) | 仅 FLOAT/DOUBLE |

> **关键陷阱**：`FLOAT(p)` 在 SQL:1992 的语义是"至少 p 个二进制位"，但部分引擎或文档误将其解释为"十进制位"，导致用户写 `FLOAT(10)` 期望 10 位十进制精度，实际只得到 4 字节单精度（约 7 位十进制）。Oracle 是少数严格按"二进制位"语义的引擎，但 Oracle 的 `FLOAT(p)` 实际是 `NUMBER` 的子类型，和 `BINARY_FLOAT/BINARY_DOUBLE` 是不同的存储路径。

### HALF FLOAT (FP16) / BFLOAT16 / 16 位浮点

| 引擎 | FP16 (binary16) | BFLOAT16 | TF32 | 状态 | 版本 |
|------|----------------|----------|------|------|------|
| PostgreSQL | -- | -- | -- | 不支持 | -- |
| MySQL | -- | -- | -- | 不支持 | -- |
| Oracle | -- | -- | -- | 不支持 | -- |
| SQL Server | -- | -- | -- | 不支持 | -- |
| DB2 | -- | -- | -- | 不支持 | -- |
| Snowflake | -- | -- | -- | 不支持 | -- |
| BigQuery | -- | -- | -- | 不支持 | -- |
| Redshift | -- | -- | -- | 不支持 | -- |
| DuckDB | -- | -- | -- | 不支持 (有讨论) | -- |
| **ClickHouse** | -- | **`BFloat16`** | -- | 是 | 24.6 (2024-06) |
| Trino | -- | -- | -- | 不支持 | -- |
| Spark SQL | -- | -- | -- | 不支持 (Pandas API 间接) | -- |
| Hive | -- | -- | -- | 不支持 | -- |
| pgvector (PG 扩展) | `halfvec` (向量化) | -- | -- | 是 (向量元素) | 0.7+ (2024) |
| Vespa (非 SQL, 提及) | -- | `bfloat16` 张量 | -- | 是 | -- |
| 其他引擎 | -- | -- | -- | 不支持 | -- |

> ClickHouse 是首个原生支持 `BFloat16` 标量列类型的开源 OLAP 引擎 (24.6, 2024 年 6 月)。pgvector 是 PostgreSQL 扩展，提供 `halfvec` 类型作为向量元素的 IEEE FP16 表示，但不是独立标量类型。其他引擎主要将 FP16/BFLOAT16 留给应用层 (PyTorch/TensorFlow) 处理。

### DECFLOAT 十进制浮点

| 引擎 | DECFLOAT 类型 | 精度选项 | 版本 |
|------|--------------|---------|------|
| **DB2** | `DECFLOAT` | `DECFLOAT(16)`, `DECFLOAT(34)` | 9.5 (2007) |
| Firebird | `DECFLOAT` | `DECFLOAT(16)`, `DECFLOAT(34)` | 4.0 (2021) |
| Informix | `DECFLOAT` (DECIMAL 别名扩展) | -- | 部分版本 |
| **SAP HANA** | `SMALLDECIMAL` | (类似但非标准) | 全版本 |
| Oracle | -- | (用 NUMBER 替代) | -- |
| PostgreSQL | -- | (无原生支持，用 NUMERIC 替代) | -- |
| MySQL | -- | (用 DECIMAL 替代) | -- |
| SQL Server | -- | (用 DECIMAL 替代) | -- |
| 其他大多数引擎 | -- | 不支持 | -- |

> DB2 是 DECFLOAT 的旗舰实现 (9.5, 2007)。其他引擎多用 DECIMAL/NUMERIC 替代——区别是 DECIMAL 是定点数，DECFLOAT 是浮点数（指数可变）。

## 各引擎深度解析

### PostgreSQL — 标准 SQL:1992 浮点的标杆

```sql
-- 4 字节单精度
CREATE TABLE measurements (
    sensor_id  INT,
    temperature REAL,         -- 别名: float4
    voltage    FLOAT(10),     -- p=10 二进制位 → REAL (4B)
    raw_value  FLOAT(24)      -- p=24 二进制位 → REAL (4B)
);

-- 8 字节双精度
CREATE TABLE measurements_d (
    sensor_id  INT,
    temperature DOUBLE PRECISION,  -- 别名: float8
    voltage    FLOAT,              -- 无参数 = DOUBLE PRECISION (8B)
    raw_value  FLOAT(53)           -- p=53 二进制位 → DOUBLE (8B)
);

-- 特殊值
SELECT 'NaN'::REAL,
       'Infinity'::DOUBLE PRECISION,
       '-Infinity'::DOUBLE PRECISION;

-- IEEE 754 行为：NaN != NaN
SELECT 'NaN'::REAL = 'NaN'::REAL;   -- false
-- 但 PostgreSQL 在 ORDER BY 中将 NaN 视为最大值 (实现选择)
SELECT temperature FROM measurements ORDER BY temperature;
-- 顺序：负数 < 0 < 正数 < +Infinity < NaN

-- 精度损失示例
SELECT 0.1::REAL + 0.2::REAL;       -- 0.3 (但内部 ≠ 0.3)
SELECT (0.1::REAL + 0.2::REAL) = 0.3::REAL;  -- true (在 REAL 精度下)
SELECT (0.1::DOUBLE PRECISION + 0.2::DOUBLE PRECISION) = 0.3::DOUBLE PRECISION;  -- false
```

PostgreSQL 是 SQL:1992 浮点语义最严格的实现之一：

- `REAL` 严格 4 字节，`DOUBLE PRECISION` 严格 8 字节
- `FLOAT(p)` 中 p 是二进制位，p ≤ 24 → REAL，p ≥ 25..53 → DOUBLE
- `FLOAT` 无参数 = `DOUBLE PRECISION` (与 SQL Server 相同)
- 不支持 DECFLOAT，但 `NUMERIC` 类型支持任意精度十进制（实际上 NUMERIC 在 PG 中是变长 BCD 编码，性能比 DECFLOAT 慢但精度无限）

### SQL Server — `FLOAT` 默认是 DOUBLE

```sql
-- SQL Server 的 FLOAT 默认是 8 字节
CREATE TABLE measurements (
    sensor_id INT,
    temperature FLOAT,          -- 默认 = FLOAT(53) = 8 字节 DOUBLE
    voltage    FLOAT(53),       -- 显式 8 字节
    pressure   FLOAT(24),       -- 4 字节 REAL
    humidity   REAL             -- 4 字节 (= FLOAT(24))
);

-- FLOAT(p) 阈值
-- FLOAT(1..24)  → 4 字节 REAL (尾数 24 位 = 7 十进制位)
-- FLOAT(25..53) → 8 字节 DOUBLE (尾数 53 位 = 15 十进制位)

-- 注意：SQL Server 的 FLOAT(n) 中 n 是尾数二进制位
-- 与 PostgreSQL 一致

-- 特殊值
SELECT CAST('NaN' AS FLOAT);    -- 错误：SQL Server 不接受字符串 'NaN'
SELECT 1.0E308 * 10.0;          -- 算术溢出错误（不是 +Inf）

-- IEEE 754 兼容性
SELECT POWER(0.0, -1);          -- 算术溢出错误
```

SQL Server 的关键特点：

- `FLOAT` 不带参数默认是 `FLOAT(53)` = 8 字节双精度 (与 SQL:1992 一致，但与 MySQL 不同)
- 严格的算术异常：除零、溢出抛错而非返回 `Inf`/`NaN`
- 通过 `SET ARITHABORT OFF` + `SET ANSI_WARNINGS OFF` 可让算术异常返回 NULL

### Oracle — BINARY_FLOAT / BINARY_DOUBLE (10g+)

Oracle 在 10g (2003) 引入 IEEE 754 二进制浮点类型：

```sql
CREATE TABLE measurements (
    sensor_id  NUMBER,
    -- 4 字节 IEEE 754 单精度
    temperature BINARY_FLOAT,
    -- 8 字节 IEEE 754 双精度
    voltage    BINARY_DOUBLE,
    -- FLOAT(p) 是 NUMBER 子类型，p 是二进制位 (≤ 126)
    pressure   FLOAT(63)            -- ≈ 19 位十进制精度
);

-- Oracle 特殊浮点字面量
INSERT INTO measurements VALUES (1, 1.5f, 2.5d, 100);   -- f=BINARY_FLOAT, d=BINARY_DOUBLE
INSERT INTO measurements VALUES (2, BINARY_FLOAT_NAN, BINARY_DOUBLE_INFINITY, 200);
INSERT INTO measurements VALUES (3, BINARY_FLOAT_MIN_NORMAL, BINARY_DOUBLE_MAX_NORMAL, 300);

-- Oracle 的 FLOAT(p) 不是 IEEE 浮点！
-- FLOAT(p) 是 NUMBER(precision, scale) 的子类型，p 是二进制位
-- 内部存储仍是 NUMBER 的变长 BCD 编码

SELECT FLOAT_PRECISION_VALUE
FROM (SELECT CAST(123.456 AS FLOAT(10)) FROM dual);
-- 实际是 NUMBER 的精度近似

-- IEEE 754 行为 (BINARY_FLOAT/BINARY_DOUBLE)
SELECT BINARY_FLOAT_INFINITY * 0;  -- NaN
SELECT 1/0::BINARY_FLOAT;          -- BINARY_FLOAT_INFINITY (不抛错)
```

Oracle 的浮点策略独树一帜：

- **`FLOAT` / `FLOAT(p)`**：是 `NUMBER` 的子类型，仍是十进制浮点（变长 BCD）
- **`BINARY_FLOAT` (10g+)**：4 字节 IEEE 754 单精度，硬件加速
- **`BINARY_DOUBLE` (10g+)**：8 字节 IEEE 754 双精度
- 三者互不混用：`FLOAT(p)` 加 `BINARY_FLOAT` 隐式转换会损失精度
- 这是为什么 Oracle 应用通常显式使用 `BINARY_FLOAT/BINARY_DOUBLE` 而非 `FLOAT(p)`

### MySQL / MariaDB — `FLOAT` 是 4 字节

```sql
-- MySQL 的 FLOAT 不带参数 = 4 字节单精度 (与 PG/SQL Server 不同！)
CREATE TABLE measurements (
    sensor_id   INT,
    temperature FLOAT,             -- 4 字节单精度 (注意!)
    voltage     DOUBLE,            -- 8 字节双精度
    pressure    DOUBLE PRECISION,  -- = DOUBLE
    -- FLOAT(p) 中 p 是二进制位 (但实际存储有阈值)
    raw_a       FLOAT(20),         -- p ≤ 24 → 4 字节
    raw_b       FLOAT(30)          -- p ≥ 25 → 8 字节
);

-- MySQL 8.0+ 弃用语法
CREATE TABLE deprecated (
    -- FLOAT(M, D)：M=总位数，D=小数位 (MySQL 5.x 风格)
    -- 在 MySQL 8.0.17+ 已弃用，建议用 DECIMAL(M, D)
    legacy_value FLOAT(7, 4)       -- 警告
);

-- IEEE 754 行为
SELECT 0.1 + 0.2;                  -- 返回 0.3 (但内部 ≠ 0.3)
SELECT (0.1 + 0.2) = 0.3;          -- 0 (false)，因二进制浮点累积误差

-- MySQL 不支持 NaN/Infinity 字面量直接写入
SELECT CAST('NaN' AS DOUBLE);      -- 0 (静默错误)
SELECT 1e308 * 10;                 -- 警告 + NULL/inf (取决于 SQL 模式)
```

MySQL 的关键特点：

- `FLOAT` 不带参数 = **4 字节** (与 PG/SQL Server 不同)
- `DOUBLE` / `DOUBLE PRECISION` / `REAL` 都是 8 字节
- `FLOAT(M, D)` 旧语法在 MySQL 8.0.17+ 弃用，应使用 `DECIMAL(M, D)`
- 不能直接存储 NaN / Infinity (CAST 会静默返回 0 或触发警告)

### ClickHouse — Float32 / Float64 / BFloat16 (24.6+)

```sql
-- 标准 IEEE 754 类型
CREATE TABLE metrics (
    timestamp DateTime,
    sensor_id UInt32,
    temperature Float32,    -- 4 字节
    pressure   Float64,     -- 8 字节
    humidity   Float32
) ENGINE = MergeTree()
ORDER BY (sensor_id, timestamp);

-- ClickHouse 24.6+ 新增 BFloat16 (2024-06)
CREATE TABLE ml_features (
    user_id UInt64,
    feature_vector Array(BFloat16),  -- 向量搜索常用
    embedding_norm BFloat16
) ENGINE = MergeTree()
ORDER BY user_id;

-- 特殊值
SELECT toFloat32('nan');           -- nan
SELECT toFloat32('inf');           -- inf
SELECT toFloat32('-inf');          -- -inf

-- IEEE 754 行为
SELECT 1/0;                         -- inf (不抛错)
SELECT 0/0;                         -- nan
SELECT 1.0/0::Float32;             -- inf

-- BFloat16 显式转换
SELECT toBFloat16(3.14159);         -- 约 3.140625 (BFloat16 精度限制)
SELECT toFloat32(toBFloat16(3.14159));  -- 验证精度损失

-- 性能：BFloat16 的存储和带宽都是 Float32 的一半
-- 适合 ML 特征、向量搜索等对精度容忍度高的场景
```

ClickHouse 的浮点设计：

- `Float32` / `Float64`：标准 IEEE 754 4/8 字节，全版本支持
- **`BFloat16` (24.6+)**：16 位 Brain Float，主要面向 ML 和向量搜索
- BFloat16 的尾数精度仅 7 位二进制 (~2 位十进制)，不适合精确数值
- 与 IEEE 754 严格一致：`1/0 = inf`, `0/0 = nan`，不抛算术异常

### DuckDB — REAL / DOUBLE 简洁实现

```sql
CREATE TABLE measurements (
    sensor_id  INTEGER,
    temperature REAL,         -- 4 字节, 别名 FLOAT, FLOAT4
    pressure   DOUBLE,        -- 8 字节, 别名 FLOAT8, DOUBLE PRECISION
    humidity   FLOAT          -- 在 DuckDB 中 FLOAT = REAL (4 字节)
);

-- DuckDB 的 FLOAT 是 REAL 的别名 (4 字节)，与 SQL Server/PG 不同
SELECT typeof(1.5::FLOAT);    -- 'FLOAT' (= REAL, 4B)
SELECT typeof(1.5::DOUBLE);   -- 'DOUBLE' (8B)

-- 特殊值字面量
SELECT 'nan'::REAL;            -- NaN
SELECT 'inf'::DOUBLE;          -- Infinity
SELECT '-inf'::DOUBLE;         -- -Infinity

-- IEEE 754 行为
SELECT 1/0::DOUBLE;            -- Infinity
SELECT 0/0::DOUBLE;            -- NaN

-- DuckDB 暂不支持 BFloat16/FP16 (但有讨论)
```

### Snowflake — 仅 8 字节，无 4 字节

```sql
-- Snowflake 中所有浮点类型都映射到 8 字节双精度
CREATE TABLE measurements (
    sensor_id   NUMBER,
    -- 全部为 8 字节 DOUBLE
    temperature FLOAT,                -- = FLOAT8 = DOUBLE PRECISION
    voltage    FLOAT4,                -- 仍是 8 字节! (不是真 4B)
    pressure   FLOAT8,                -- 8 字节
    raw_value  REAL,                  -- = DOUBLE
    measured   DOUBLE,                -- 8 字节
    abstract_p DOUBLE PRECISION       -- 8 字节
);

-- 验证：所有浮点类型在 Snowflake 中都是 8 字节
SELECT
    SYSTEM$TYPEOF(1.5::FLOAT),      -- FLOAT(8)
    SYSTEM$TYPEOF(1.5::FLOAT4),      -- FLOAT(8) (注意!)
    SYSTEM$TYPEOF(1.5::REAL),         -- FLOAT(8)
    SYSTEM$TYPEOF(1.5::DOUBLE);       -- FLOAT(8)

-- IEEE 754 行为
SELECT 'NaN'::FLOAT;                  -- NaN
SELECT 'inf'::FLOAT;                  -- inf
SELECT 1/0::FLOAT;                    -- 错误：除零异常
```

Snowflake 简化了浮点类型：

- **所有浮点类型** (`FLOAT`, `FLOAT4`, `FLOAT8`, `REAL`, `DOUBLE`, `DOUBLE PRECISION`) 都是 8 字节
- 无 4 字节单精度，存储成本上 4B/8B 差异不可见
- 这是云数仓的常见简化策略 (BigQuery、Vertica、Exasol 类似)

### BigQuery — 仅 FLOAT64

```sql
-- BigQuery 标准 SQL：仅 FLOAT64
CREATE TABLE dataset.measurements (
    sensor_id  INT64,
    temperature FLOAT64,        -- 8 字节 IEEE 754 双精度
    voltage    FLOAT,            -- FLOAT 是 FLOAT64 的别名
    -- FLOAT32 不存在
);

-- IEEE 754 行为
SELECT IS_NAN(0.0/0.0);          -- true
SELECT IS_INF(1.0/0.0);          -- true
SELECT CAST('NaN' AS FLOAT64);    -- NaN
SELECT CAST('+inf' AS FLOAT64);   -- Infinity
SELECT CAST('-inf' AS FLOAT64);   -- -Infinity

-- 特殊值在聚合中的行为
SELECT MIN(x), MAX(x), AVG(x), COUNT(*)
FROM UNNEST([1.0, 2.0, CAST('NaN' AS FLOAT64), 3.0]) AS x;
-- BigQuery 中 NaN 在 MIN/MAX 中被忽略 (与 PG 不同！)
```

### DB2 — DECFLOAT(16/34) 旗舰实现

DB2 是首个全面支持 SQL:2003 DECFLOAT 的主流引擎 (DB2 9.5, 2007)：

```sql
-- IEEE 754 二进制浮点 (DB2 全版本支持)
CREATE TABLE measurements (
    sensor_id  INTEGER,
    -- 4 字节 IEEE 754 单精度
    temperature REAL,                  -- = FLOAT(24)
    -- 8 字节 IEEE 754 双精度
    pressure   DOUBLE,                 -- = FLOAT(53) = DOUBLE PRECISION
    raw_a      FLOAT,                  -- = DOUBLE (8B, 与 SQL Server 一致)
    -- DECFLOAT (DB2 9.5+, 2007)
    price_d16  DECFLOAT(16),           -- decimal64, 8 字节, 16 位有效数字
    price_d34  DECFLOAT(34),           -- decimal128, 16 字节, 34 位有效数字
    price_d    DECFLOAT                -- 默认 = DECFLOAT(34)
);

-- DECFLOAT 与 IEEE 754-2008 decimal 浮点完全兼容
-- 0.1 + 0.2 在 DECFLOAT 中精确为 0.3
INSERT INTO measurements VALUES
    (1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1);

SELECT temperature + temperature + temperature,    -- 二进制浮点：0.30000000447034836
       price_d16 + price_d16 + price_d16,           -- DECFLOAT: 精确 0.3
       price_d34 + price_d34 + price_d34            -- DECFLOAT: 精确 0.3
FROM measurements;

-- DECFLOAT 范围远大于 DECIMAL
-- DECIMAL(31): 最多 ±10³¹
-- DECFLOAT(34): 最多 ±10⁶¹⁴⁵ (指数位 14 位)

-- 特殊值
SELECT CAST('NaN' AS DECFLOAT(34));        -- NaN (DECFLOAT 也有)
SELECT CAST('Infinity' AS DECFLOAT(34));    -- Infinity

-- DB2 算术：DECFLOAT 优先级
-- 当 DECIMAL + DECFLOAT 时，结果为 DECFLOAT
SELECT CAST(1.5 AS DECIMAL(10,2)) + CAST(2.5 AS DECFLOAT(34));
-- 结果类型：DECFLOAT(34)
```

DB2 DECFLOAT 的关键优势：

- 精确十进制表示，无累积误差
- 范围远大于 DECIMAL：`DECFLOAT(34)` 可表示 ±10⁶¹⁴⁵
- 性能：IBM POWER 处理器有原生 DFP (Decimal Floating Point) 指令
- IEEE 754-2008 兼容，跨平台一致行为

### SAP HANA — REAL / DOUBLE / SMALLDECIMAL

```sql
-- SAP HANA 浮点类型
CREATE TABLE measurements (
    sensor_id  INTEGER,
    -- IEEE 754 二进制浮点
    temperature REAL,              -- 4 字节
    pressure   DOUBLE,             -- 8 字节
    raw_a      FLOAT,              -- = REAL (4 字节, 注意!)
    -- HANA 专有：SMALLDECIMAL (压缩十进制浮点)
    price      SMALLDECIMAL        -- 16 字节, 类似 DECFLOAT
);

-- SMALLDECIMAL 特点
-- - 8 字节存储，范围约 ±10⁻⁶³ 到 ±10⁶³
-- - 精度 16 位十进制
-- - 用于压缩存储，特别适合内存数据库
-- - 与 DECFLOAT(16) 类似但非标准

-- IEEE 754 行为
SELECT TO_DOUBLE('NaN'), TO_DOUBLE('inf');
-- HANA 支持 NaN / inf 字面量
```

### Vertica — 仅 IEEE 754 双精度

```sql
-- Vertica：所有浮点类型都映射到 8 字节
CREATE TABLE measurements (
    sensor_id  INTEGER,
    temperature FLOAT,                  -- = DOUBLE PRECISION (8B)
    voltage    REAL,                    -- 仍是 8 字节! (不是 4B)
    pressure   DOUBLE PRECISION,        -- 8 字节
    raw_a      FLOAT(15),               -- 8 字节 (FLOAT(p) 仅校验, 实际 8B)
    -- 没有 4B 浮点类型
);

-- 验证
SELECT TYPENAME(temperature), TYPENAME(voltage)
FROM measurements LIMIT 0;
-- 都返回 'float'，实际都是 8 字节
```

### MariaDB / TiDB / OceanBase — MySQL 兼容

继承 MySQL 的浮点语义：

- `FLOAT` 不带参数 = 4 字节 (注意：不是 8 字节)
- `DOUBLE` / `DOUBLE PRECISION` / `REAL` = 8 字节
- `FLOAT(p)`：p ≤ 24 → 4B, p ≥ 25 → 8B

OceanBase 双模式特殊：

- **MySQL 模式**：与 MySQL 一致 (`FLOAT` = 4B, `DOUBLE` = 8B)
- **Oracle 模式**：与 Oracle 一致 (`BINARY_FLOAT` = 4B, `BINARY_DOUBLE` = 8B)，`FLOAT(p)` 是 NUMBER 子类型

### Trino / Presto / Athena — 严格区分

```sql
-- Trino 浮点：REAL / DOUBLE，FLOAT 是 REAL 的别名
CREATE TABLE measurements (
    sensor_id  INTEGER,
    temperature REAL,                   -- 4 字节 (= FLOAT 别名)
    pressure   DOUBLE,                  -- 8 字节
    -- FLOAT 在 Trino 中是 REAL 的别名 (4 字节)
    -- 注意：与 SQL Server 的 FLOAT=DOUBLE 不同！
    raw_a      FLOAT                    -- = REAL (4 字节)
);

-- IEEE 754 行为
SELECT NAN();                           -- NaN
SELECT INFINITY();                      -- Infinity
SELECT IS_NAN(NAN());                   -- true
SELECT IS_FINITE(1.0/0.0);              -- false
```

### Spark SQL / Hive / Databricks — Java/Scala 风格

```sql
-- Spark SQL：FLOAT = 4 字节, DOUBLE = 8 字节 (与 Java 一致)
CREATE TABLE measurements (
    sensor_id  INT,
    temperature FLOAT,                  -- 4 字节 (注意!)
    pressure   DOUBLE,                  -- 8 字节
    -- 不支持 FLOAT(p) 参数化语法
    raw_a      DECIMAL(38, 10)          -- 替代精确十进制
);

-- IEEE 754 行为
SELECT 1.0/0.0;                          -- Infinity (不抛错)
SELECT 0.0/0.0;                          -- NaN
SELECT cast('NaN' AS DOUBLE);            -- NaN
```

## IEEE 754 深度剖析

### 二进制浮点的内部结构

```
IEEE 754 binary32 (REAL / FLOAT32):
  +----------+--------+-----------------------+
  |  S (1)   | E (8)  |       M (23)          |
  +----------+--------+-----------------------+
  
  数值 = (-1)^S × (1 + M/2^23) × 2^(E - 127)
  E=0:    非规格化数 / 0
  E=255:  Infinity / NaN
  其他:   规格化数

IEEE 754 binary64 (DOUBLE / FLOAT64):
  +----------+--------+--------------------------------------+
  |  S (1)   | E (11) |              M (52)                  |
  +----------+--------+--------------------------------------+
  
  数值 = (-1)^S × (1 + M/2^52) × 2^(E - 1023)
```

### 精度损失示例

`0.1` 在 IEEE 754 binary64 中的精确表示：

```
0.1 (十进制) = 0.0001100110011001100110011001100110011001100110011001101 (二进制, 截断)
            ≈ 0.1000000000000000055511151231257827021181583404541015625 (实际存储值)

误差 ≈ 5.55 × 10⁻¹⁸
```

累积示例：

```sql
-- PostgreSQL / MySQL / 任何 IEEE 754 引擎
SELECT 0.1::DOUBLE PRECISION + 0.2::DOUBLE PRECISION;
-- 返回 0.30000000000000004 (binary64 精确表示)
-- 这不是 bug，是 IEEE 754 的标准行为

-- DECFLOAT 引擎 (DB2)
SELECT CAST(0.1 AS DECFLOAT(34)) + CAST(0.2 AS DECFLOAT(34));
-- 返回精确的 0.3
```

### 特殊值

| 值 | binary32 表示 | binary64 表示 | 含义 |
|----|--------------|--------------|------|
| `+0` | `0x00000000` | `0x0000000000000000` | 正零 |
| `-0` | `0x80000000` | `0x8000000000000000` | 负零 (运算特殊) |
| `+Infinity` | `0x7F800000` | `0x7FF0000000000000` | 上溢 |
| `-Infinity` | `0xFF800000` | `0xFFF0000000000000` | 下溢 |
| `NaN` (qNaN) | `0x7FC00000` | `0x7FF8000000000000` | Not-a-Number |
| `MAX_NORMAL` | ±3.402... × 10³⁸ | ±1.797... × 10³⁰⁸ | 最大规格化值 |
| `MIN_NORMAL` | ±1.175... × 10⁻³⁸ | ±2.225... × 10⁻³⁰⁸ | 最小规格化值 |
| `MIN_DENORMAL` | ±1.401... × 10⁻⁴⁵ | ±4.940... × 10⁻³²⁴ | 最小非规格化值 |

### NaN 的反直觉行为

```sql
-- IEEE 754 规定：NaN != 自身
SELECT 'NaN'::DOUBLE PRECISION = 'NaN'::DOUBLE PRECISION;
-- false (在所有 IEEE 754 兼容引擎中)

-- 但 PostgreSQL 在 ORDER BY 中将 NaN 视为最大值（实现选择）
-- 而 BigQuery 在 ORDER BY 中将 NaN 视为最小值
-- MySQL 中 NaN 实际不能存储 (CAST 失败)

-- 比较
SELECT 1.0 < 'NaN'::DOUBLE PRECISION;   -- false
SELECT 1.0 > 'NaN'::DOUBLE PRECISION;   -- false
SELECT 1.0 = 'NaN'::DOUBLE PRECISION;   -- false
-- IEEE 754: NaN 与任何值比较都是 false (包括与自身)

-- IS NULL 的反直觉
SELECT 'NaN'::DOUBLE PRECISION IS NULL;  -- false (NaN 不是 NULL)
-- 各引擎检测 NaN 的函数:
-- PostgreSQL:    isnan(x)
-- BigQuery:      IS_NAN(x)
-- ClickHouse:    isNaN(x)
-- Spark SQL:     isnan(x)
-- DuckDB:        isnan(x)
```

### 各引擎对 NaN 的处理差异

| 引擎 | NaN 排序位置 | NaN 在 MIN/MAX | NaN 在 GROUP BY | NaN = NaN |
|------|-------------|---------------|----------------|----------|
| PostgreSQL | 最大值 (NULL > NaN > +Inf) | MAX 返回 NaN | NaN 自成一组 | false |
| MySQL | 不能存储 (拒绝) | -- | -- | -- |
| Oracle | 最大值 (NaN > +Inf) | MAX 返回 NaN | NaN 自成一组 | false |
| SQL Server | 算术抛错 (默认) | -- | -- | -- |
| ClickHouse | 最大值 | MAX 返回 NaN | NaN 自成一组 | false |
| BigQuery | 最小值 (NaN < -Inf) | MIN 返回 NaN | NaN 自成一组 | false |
| Snowflake | 最大值 | MAX 返回 NaN | NaN 自成一组 | false |
| DuckDB | 最大值 | MAX 返回 NaN | NaN 自成一组 | false |
| Spark SQL | 最大值 | MAX 返回 NaN | NaN 自成一组 | false |

> **关键陷阱**：跨数据库迁移时，NaN 的排序行为差异可能导致 ORDER BY / TOP-N 查询返回不同结果。BigQuery 与其他引擎方向相反！

### Round-trip 一致性

将 IEEE 754 浮点数转字符串再转回，能否得到完全相同的位模式？

| 引擎 | binary32 round-trip 数字位数 | binary64 round-trip 数字位数 |
|------|---------------------------|---------------------------|
| 标准要求 | 9 位 (IEEE 754-2008) | 17 位 (IEEE 754-2008) |
| PostgreSQL | 9 位 | 17 位 |
| MySQL | 6 位 (默认，可调) | 15 位 |
| ClickHouse | 9 位 | 17 位 |
| 多数引擎 | 9 位 | 17 位 |

> 默认显示精度通常为 6 位 (binary32) 或 15 位 (binary64)，但完整 round-trip 需要 9/17 位。建议使用 `to_char` / `format` 显式控制精度。

## BFLOAT16 / FP16 趋势

### 为什么 ML 工作负载偏好 16 位浮点

深度学习模型的关键特征：

1. **权重和激活的分布**：通常集中在 [-10, 10]，不需要 FP32 的巨大范围
2. **梯度数值**：可能很小 (10⁻⁷ 量级)，但精度容忍度高
3. **乘加运算**：占模型推理 / 训练 90%+ 计算量
4. **内存带宽**：HBM 带宽有限，半精度可减少 50% 内存传输

```
存储和计算成本对比 (相对 FP32):
  FP32 (binary32):   1.0x 存储, 1.0x 计算
  FP16 (binary16):   0.5x 存储, 2.0x 计算 (在支持的 GPU 上)
  BFLOAT16:          0.5x 存储, 2.0x 计算 (Google TPU, NVIDIA A100+)
  TF32:              0.625x 存储, 8.0x 计算 (NVIDIA A100+, 仅训练)
  INT8:              0.25x 存储, 4.0x 计算 (推理量化)
```

### IEEE FP16 vs BFLOAT16 vs TF32

```
IEEE 754 binary16 (FP16):
  +--+-----+-----------+
  |S | E=5 |   M=10    |     总 16 位
  +--+-----+-----------+
  范围: ±6.55 × 10⁴
  精度: ~3-4 位十进制
  问题: 范围小，深度学习中梯度容易溢出/下溢

BFLOAT16 (Google Brain Float):
  +--+-----+--------+
  |S | E=8 |  M=7   |        总 16 位
  +--+-----+--------+
  范围: ±3.4 × 10³⁸ (与 FP32 相同!)
  精度: ~2-3 位十进制
  优势: 训练稳定，与 FP32 范围兼容，无需 loss scaling

TF32 (NVIDIA TensorFloat-32, A100+):
  +--+-----+----------+
  |S | E=8 |  M=10    |       总 19 位 (实际 32 位寄存器)
  +--+-----+----------+
  范围: ±3.4 × 10³⁸ (同 FP32)
  精度: ~3-4 位十进制 (同 FP16)
  优势: FP32 范围 + FP16 精度 + 8x FP32 训练吞吐
```

### 数据库引擎对 16 位浮点的支持

| 引擎 | 支持 | 类型 | 用途 | 版本 |
|------|------|------|------|------|
| **ClickHouse** | 是 | `BFloat16` | 标量列 / 向量元素 | 24.6 (2024-06) |
| pgvector (PG 扩展) | 是 | `halfvec` | 向量元素 (IEEE FP16) | 0.7+ (2024) |
| ClickHouse | 否 | (FP16 不支持) | -- | -- |
| 其他主流 SQL 引擎 | 否 | -- | -- | -- |

### ClickHouse BFloat16 实战

```sql
-- ClickHouse 24.6+ 使用 BFloat16
CREATE TABLE ml_embeddings (
    item_id    UInt64,
    embedding  Array(BFloat16),     -- 768 维向量，每元素 2 字节
    created_at DateTime
) ENGINE = MergeTree()
ORDER BY item_id;

-- 与 Float32 对比的存储和带宽
-- 100M 条 768 维向量：
-- - Float32: 100M × 768 × 4 = 307 GB
-- - BFloat16: 100M × 768 × 2 = 153 GB (50% 节省)

-- 精度对比
SELECT
    toFloat32(3.14159265358979) AS f32,           -- 3.1415927
    toBFloat16(3.14159265358979) AS bf16,         -- 3.140625 (尾数 7 位)
    toFloat32(toBFloat16(3.14159265358979)) AS bf16_to_f32; -- 3.140625

-- 范围测试
SELECT
    toBFloat16(1e38),        -- 9.96e+37 (BFloat16 范围内)
    toBFloat16(1e39);        -- inf (超出范围)

-- 与 BFloat16 的算术 (内部转 Float32 计算后存回 BFloat16)
SELECT toBFloat16(1.5) * toBFloat16(2.5);   -- 3.75 (在 BFloat16 精度内)
```

### pgvector 的 halfvec (IEEE FP16)

```sql
-- pgvector 0.7+ (2024) 提供 halfvec 类型
CREATE EXTENSION vector;

CREATE TABLE embeddings (
    id BIGINT PRIMARY KEY,
    embedding halfvec(768)              -- IEEE FP16 向量, 每元素 2 字节
);

-- 使用 halfvec 创建索引
CREATE INDEX ON embeddings 
    USING hnsw (embedding halfvec_l2_ops);

-- 与 vector (Float32) 对比
-- vector(768): 每行 4 × 768 = 3072 字节
-- halfvec(768): 每行 2 × 768 = 1536 字节 (50% 节省)
```

### 为什么大多数引擎暂不支持？

1. **CPU 硬件支持有限**：x86 仅 Cascade Lake+ 有 AVX-512 BF16，ARM 仅 ARMv8.6+ 有 BFloat16；老旧硬件需软件模拟
2. **算术语义复杂**：16 位浮点的中间结果通常需要 FP32 累加器
3. **应用层处理更灵活**：PyTorch/TensorFlow 已成熟管理 FP16/BF16
4. **OLTP 场景需求弱**：金融、订单等场景需要精确数值，而非小尾数浮点

### 趋势预测

随着向量数据库和 AI 应用普及，更多引擎可能跟进：

- **DuckDB**：社区有 BFloat16 / FP16 提案
- **PostgreSQL**：pgvector 已支持 halfvec，原生类型仍在讨论
- **BigQuery / Snowflake**：未公开计划，但向量搜索功能已上线
- **DB2 / Oracle**：传统企业引擎，ML 支持通过外部框架

## DECFLOAT vs 二进制浮点：何时使用哪种

### 决策矩阵

| 场景 | 推荐类型 | 原因 |
|------|---------|------|
| 金融金额 (USD, EUR) | DECIMAL(p,s) 或 DECFLOAT | 必须精确十进制，避免累积误差 |
| 会计 GL 余额 | DECIMAL(38, 4) 或 DECFLOAT(34) | 长期累加无误差 |
| 利率、汇率 (4-6 位小数) | DECIMAL(p,s) 或 DECFLOAT(16) | 精确小数 |
| 科学计算 (温度、压力) | DOUBLE PRECISION | 范围 / 速度优先 |
| 物理常数、统计量 | DOUBLE PRECISION | IEEE 754 行业标准 |
| GPS 坐标 | DOUBLE PRECISION | 精度 (15 位) 足够 |
| 图形 / 游戏 | REAL | 速度 / 内存优先 |
| ML 特征向量 | BFLOAT16 / Float32 | 内存 / 带宽优化 |
| 向量搜索 embedding | halfvec / BFloat16 | 50% 内存节省 |
| 概率值 [0, 1] | REAL | 精度 (7 位) 足够 |
| 大整数 (订单号、ID) | BIGINT, 不用 DOUBLE | DOUBLE 精度只 15 位，> 2^53 整数精度损失 |

### 性能对比 (大致量级)

```
1M 行简单求和 (单核, x86 Cascade Lake):
  - REAL (4B):       3 ms
  - DOUBLE (8B):     5 ms (受内存带宽影响)
  - BFloat16 (2B):   2 ms (内存带宽优势)
  - DECFLOAT(34):    50 ms (软件模拟, 10x slower)
  - DECIMAL(38, 6):  60 ms (任意精度软件)

100M 行向量内积 (768 维):
  - Float32:        1.5 s
  - BFloat16:       0.8 s (内存带宽 + AVX-512 BF16 指令)
  - INT8:           0.4 s (量化, 精度损失)
```

### 常见误用案例

```sql
-- 案例 1：用 DOUBLE 存货币金额
-- BAD：
CREATE TABLE orders_bad (
    amount DOUBLE PRECISION    -- 累加 100M 笔订单可能误差 1 美元
);
-- GOOD：
CREATE TABLE orders_good (
    amount DECIMAL(15, 2)      -- 精确到分，无累积误差
);

-- 案例 2：用 REAL 存大整数
-- BAD：
CREATE TABLE users_bad (
    user_id REAL    -- ID > 16,777,216 (2^24) 时精度丢失
);
INSERT INTO users_bad VALUES (16777217);   -- 实际存储为 16777216!
-- GOOD：
CREATE TABLE users_good (
    user_id BIGINT   -- 精确整数，最大 9.2 × 10^18
);

-- 案例 3：用 FLOAT(10) 期望 10 位十进制精度
-- 误解：FLOAT(10) ≠ 10 位十进制，而是 10 位二进制 (≈ 3 位十进制)
-- 在 PG/SQL Server/DB2 中，FLOAT(10) → REAL (4B)
-- 实际只有 7 位十进制有效数字！
```

### DECFLOAT 与 DECIMAL 的区别

| 维度 | DECIMAL(p, s) | DECFLOAT(p) |
|------|--------------|-------------|
| 类型 | 定点数 (fixed-point) | 浮点数 (floating-point) |
| 精度 p | 总位数固定 | 有效数字位数固定 |
| 小数位 s | 固定 | 随指数变化 |
| 范围 | ±10^(p-s) | ±10^huge_exponent |
| 内部表示 | 整数 + 小数位偏移 | 尾数 + 二进制指数 + 符号 |
| 加减性能 | 快 (直接整数加法) | 慢 (需要指数对齐) |
| 乘除性能 | 慢 (需扩展位宽) | 中等 (尾数乘 + 指数加) |
| 范围灵活性 | 受 p, s 限制 | 范围极大 (10⁶¹⁴⁵) |
| 用途 | 已知范围的金融金额 | 范围未知的科学/工程 |

```sql
-- DECIMAL: 固定 (10, 2)，总位数 10，小数 2 位
-- 范围: -99,999,999.99 到 99,999,999.99
DECIMAL(10, 2)

-- DECFLOAT(16): 16 位有效数字，指数位 ±383
-- 范围: 9.999...e±383 (远大于 DECIMAL)
-- 但加减运算可能损失精度（指数不同时）
DECFLOAT(16)
```

## 关键发现

### 1. 标准合规度普遍较高，但语义陷阱无处不在

45 个引擎中有 41 个支持 IEEE 754 标准的 4 字节单精度，全部 45 个支持 8 字节双精度。Snowflake、BigQuery、Vertica、Exasol 是主要例外，将单精度统一映射到双精度——简化但牺牲了存储灵活性。

陷阱集中在 **`FLOAT` 不带参数的语义**：
- PostgreSQL、SQL Server、Oracle (FLOAT)、DB2: `FLOAT` = 8 字节
- MySQL、MariaDB、TiDB、Spark SQL: `FLOAT` = 4 字节
- DuckDB: `FLOAT` = 4 字节 (与 SQL 标准不同)
- Trino: `FLOAT` = 4 字节 (= REAL 别名)

迁移时若不显式使用 `REAL` 或 `DOUBLE PRECISION`，几乎必然踩坑。

### 2. FLOAT(p) 中 p 的含义混乱

SQL:1992 标准明确 `FLOAT(p)` 中 p 是二进制位，但多数引擎用户误以为是十进制位。Oracle 是少数严格按"二进制位"语义实现的引擎，但 Oracle 的 `FLOAT(p)` 是 `NUMBER` 子类型，与 `BINARY_FLOAT/BINARY_DOUBLE` 是不同存储路径。

### 3. NaN 排序行为跨库严重不一致

PostgreSQL/Oracle/Snowflake/ClickHouse: NaN 排在最大值后  
BigQuery: NaN 排在最小值前  
MySQL: 拒绝存储 NaN  

跨库迁移 `ORDER BY` 含浮点列的查询时，TOP-N 结果可能完全不同。

### 4. DECFLOAT 仍是少数派，但有特定优势

DB2 (2007)、Firebird (2021) 是主流引擎中仅有的原生 DECFLOAT 实现。多数引擎用户用 `DECIMAL(p, s)` 替代——区别是 DECIMAL 是定点数（小数位固定），DECFLOAT 是浮点数（小数位随值变化）。对于范围未知的精确十进制数（如某些金融衍生品定价），DECFLOAT 是 DECIMAL 无法替代的。

### 5. BFLOAT16 / FP16 是新兴趋势，主要驱动力是 ML

ClickHouse 24.6 (2024-06) 是首个支持原生 `BFloat16` 标量列的开源 OLAP 引擎。pgvector 0.7+ 提供 `halfvec` 类型 (IEEE FP16) 用于向量元素。这一趋势的核心驱动力是：
- 向量搜索内存 / 带宽节省 50%
- ML 特征存储与训练框架对齐
- HBM 带宽是 GPU 推理的瓶颈

预计 DuckDB、PostgreSQL（原生支持）、BigQuery 在未来 1-2 年跟进。

### 6. Oracle 的 BINARY_FLOAT/BINARY_DOUBLE 是 IEEE 754 与十进制兼容的范本

Oracle 10g (2003) 引入的 `BINARY_FLOAT` / `BINARY_DOUBLE` 与传统 `FLOAT(p)` / `NUMBER` 完全分离，让用户能根据需求选择。这种"两套体系"的设计避免了 PostgreSQL/MySQL "FLOAT 究竟是 4B 还是 8B" 的语义混乱。

### 7. 云数仓倾向于简化为单一 8 字节浮点

Snowflake、BigQuery、Vertica、Exasol、Google Spanner 都将所有浮点统一为 8 字节双精度。这反映了云时代的设计取舍：
- 存储成本：4B vs 8B 在压缩存储下差异有限
- 类型系统简化：减少用户错误
- 计算性能：现代 CPU 上 FP32 / FP64 性能差异不大
- 跨平台一致性：无需考虑 4B 浮点的硬件支持差异

### 8. SQLite 的 REAL 始终是 8 字节

SQLite 使用类型亲和性（type affinity）系统：声明的列类型只是建议，实际存储类型由值决定。SQLite 中所有浮点都用 8 字节双精度存储，`REAL`、`FLOAT`、`DOUBLE` 等关键字仅影响"建议优先级"。这是嵌入式数据库简化设计的体现。

### 9. 推荐的可移植性最佳实践

```sql
-- 总是显式使用 REAL 或 DOUBLE PRECISION（不要用 FLOAT）
CREATE TABLE measurements (
    id    INTEGER,
    value_4b REAL,                  -- 在所有 IEEE 754 引擎中都是 4B
    value_8b DOUBLE PRECISION       -- 在所有 IEEE 754 引擎中都是 8B
);

-- 金融金额：用 DECIMAL(p, s)，不要用浮点
CREATE TABLE orders (
    id     INTEGER,
    amount DECIMAL(15, 2)            -- 精确到分，跨引擎一致
);

-- 大整数 ID：用 BIGINT，不要用 DOUBLE
CREATE TABLE users (
    user_id BIGINT                  -- DOUBLE 在 > 2^53 时精度损失
);

-- 比较浮点数：使用容差，不要用 =
SELECT * FROM measurements
WHERE ABS(value_8b - 0.3) < 1e-9;   -- 而不是 value_8b = 0.3

-- NaN 检测：使用引擎特定函数
-- PostgreSQL/DuckDB:    isnan(x)
-- BigQuery/Spanner:     IS_NAN(x)
-- ClickHouse:           isNaN(x)
-- 不要用 x = 'NaN' (永远 false)
```

## 参考资料

- IEEE Std 754-1985: IEEE Standard for Binary Floating-Point Arithmetic (1985)
- IEEE Std 754-2008: IEEE Standard for Floating-Point Arithmetic (2008) — 加入 binary16, decimal floating-point
- IEEE Std 754-2019: IEEE Standard for Floating-Point Arithmetic (2019) — 微调
- ISO/IEC 9075:1992 (SQL:1992): REAL / DOUBLE PRECISION / FLOAT(p) 定义
- ISO/IEC 9075:2003 (SQL:2003): DECFLOAT 类型引入
- David Goldberg, "What Every Computer Scientist Should Know About Floating-Point Arithmetic" (1991), ACM Computing Surveys
- Google Brain, "Mixed Precision Training" (2017): BFLOAT16 设计动机
- NVIDIA, "TensorFloat-32" Whitepaper (2020): TF32 与 A100 架构
- PostgreSQL: [Numeric Types](https://www.postgresql.org/docs/current/datatype-numeric.html)
- MySQL: [Floating-Point Types](https://dev.mysql.com/doc/refman/8.0/en/floating-point-types.html)
- SQL Server: [float and real](https://learn.microsoft.com/en-us/sql/t-sql/data-types/float-and-real-transact-sql)
- Oracle: [Floating-Point Numbers](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Data-Types.html)
- DB2: [DECFLOAT data type](https://www.ibm.com/docs/en/db2-for-zos/13?topic=types-decimal-floating-point)
- ClickHouse: [Float32, Float64](https://clickhouse.com/docs/en/sql-reference/data-types/float)
- ClickHouse: [BFloat16](https://clickhouse.com/docs/en/sql-reference/data-types/bfloat16) (24.6+)
- pgvector: [halfvec type](https://github.com/pgvector/pgvector#vector-types)
- Snowflake: [Numeric Data Types](https://docs.snowflake.com/en/sql-reference/data-types-numeric)
- BigQuery: [FLOAT64 type](https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types#floating_point_types)
