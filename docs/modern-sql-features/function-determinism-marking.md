# 函数确定性标记 (Function Determinism Marking)

`CREATE FUNCTION calc_tax(x NUMBER) RETURN NUMBER ...` —— 当用户写下这样一行 DDL 时，有一个关键信息没有体现在函数体里：**这个函数对相同输入是否总是返回相同输出？** 优化器无法仅靠阅读源代码判定（递归调用、动态 SQL、外部库、操作系统状态都可能让"看似纯净"的函数变得不确定），它必须依赖用户的显式契约 —— `DETERMINISTIC` / `IMMUTABLE` / `SCHEMABINDING` 之类的标记。

确定性标记的作用远不止"是否可以缓存"。它直接决定一个函数能否：

1. **作为索引表达式**（函数索引、表达式索引）
2. **作为生成列的表达式**（GENERATED ALWAYS AS）
3. **支持物化视图增量刷新**
4. **被并行执行**（PARALLEL SAFE / PARALLEL_ENABLE）
5. **支持谓词下推到分区裁剪**
6. **作为 CHECK 约束的子表达式**
7. **支持 statement-based binlog 复制**（MySQL 特有）
8. **被优化器消除重复调用（CSE）或常量折叠**

各家引擎对这一契约的表达方式天差地别 —— SQL:1999 标准只给出 `DETERMINISTIC` 一个二元关键字，但 PostgreSQL 用三级 `IMMUTABLE/STABLE/VOLATILE`，Oracle 用 `DETERMINISTIC + PARALLEL_ENABLE`，SQL Server 不允许用户直接声明而是通过 `WITH SCHEMABINDING` + 自动推断，MySQL 把 `DETERMINISTIC` 与 `NO SQL/READS SQL DATA` 等正交组合，SQLite 通过 C API 标志位传递。本文系统对比 45+ 引擎的标记关键字、推断规则、与索引/物化视图/并行查询的交互。

> 与本文紧密相关的两篇：[函数波动性 (Function Volatility)](function-volatility.md) 偏重 PostgreSQL 三级模型与优化器细节，[表达式索引 (Expression Indexes)](expression-indexes.md) 偏重索引侧的语法对比。本文聚焦"标记关键字"本身的跨引擎差异。

## 为什么优化器需要确定性契约

### 优化器无法自动证明确定性

考虑一个看起来"明显纯净"的函数：

```sql
CREATE FUNCTION normalize(s TEXT) RETURNS TEXT AS $$
  SELECT lower(trim(s));
$$ LANGUAGE sql;
```

人类读者会直觉地说"这是 IMMUTABLE 的"。但优化器需要考虑：

1. `lower()` 在不同 collation/locale 下结果不同（土耳其语 'İ' 的小写不是 'i'）。
2. `trim()` 默认去除空白，但什么算空白依赖区域设置。
3. 如果函数内部访问 `random()` 或 `now()`，结果立即变得不确定。
4. C 实现的函数可能读取静态变量、调用 syscall、依赖 errno —— 这些都无法静态分析。

因此 SQL 标准的设计哲学是：**用户对函数的确定性做出契约，优化器信任并据此优化；如果用户违约（用 IMMUTABLE 标了一个会变化的函数），后果由用户承担**。

### 索引一致性依赖确定性

索引的核心不变量是"键值与行的对应关系稳定"。如果索引键由函数计算得来：

```
INSERT 时:    key = f(input)  → 存入 B-Tree
SELECT 时:    key = f(input)  → 在 B-Tree 中查找
```

只要 `f` 不是确定性的，第二次计算可能得到不同的键，索引就崩溃了。这是为什么所有支持函数索引的引擎都要求底层函数是 `IMMUTABLE` / `DETERMINISTIC`。

### 物化视图的增量刷新

物化视图的增量刷新（incremental refresh）通过保留前次结果 + 应用 delta 来更新：

```
View_t1 = MV_old  ⊕  delta(t0 → t1)
```

只有当视图定义中的所有函数都对相同输入返回相同输出时，这种"局部更新"才能等价于"全量重算"。`now()`、`random()` 这类时间相关或随机函数会让 delta 合并产生与全量重算不同的结果。

### 并行执行的副作用控制

并行查询把单一执行划分给多个 worker。如果函数有副作用（写表、改会话变量、写文件），并发执行会导致不一致。即使没有副作用，访问线程局部状态（thread-local random seed）的函数在多 worker 下也可能行为异常。因此 PostgreSQL 9.6 引入独立于波动性的 `PARALLEL SAFE` / `PARALLEL RESTRICTED` / `PARALLEL UNSAFE` 三级标签。

## SQL:1999 DETERMINISTIC 标准定义

SQL:1999（ISO/IEC 9075-4，SQL/PSM）在 `<routine characteristic>` 中定义了 `DETERMINISTIC` / `NOT DETERMINISTIC` 子句：

```sql
<routine characteristics> ::= [ <routine characteristic> ... ]

<routine characteristic> ::=
      <language clause>
    | <parameter style>
    | <deterministic characteristic>     -- DETERMINISTIC | NOT DETERMINISTIC
    | <SQL-data access indication>       -- NO SQL | CONTAINS SQL | READS SQL DATA | MODIFIES SQL DATA
    | <null-call clause>                 -- RETURNS NULL ON NULL INPUT | CALLED ON NULL INPUT
    | <returned result sets characteristic>
    | <savepoint level indication>

<deterministic characteristic> ::= DETERMINISTIC | NOT DETERMINISTIC
```

标准的关键设计点：

1. **二元分类**：只有 `DETERMINISTIC` 与 `NOT DETERMINISTIC` 两种状态，没有 `STABLE` 中间级别。
2. **默认 NOT DETERMINISTIC**：保守默认，避免用户误标导致优化器做错误推断。
3. **与 SQL-data 访问正交**：`DETERMINISTIC` 与 `READS SQL DATA` 可共存（读数据但结果由读到的数据决定），但实际优化效果依赖引擎实现。
4. **NULL 处理独立**：`RETURNS NULL ON NULL INPUT` 与 `CALLED ON NULL INPUT` 控制 NULL 输入时是否调用函数体，这是另一种"短路"优化的契约。
5. **未约束副作用**：标准不要求 `DETERMINISTIC` 函数无副作用 —— 写日志、发送邮件等副作用不被禁止，仅要求"可见返回值"满足确定性。
6. **未定义 NOT DETERMINISTIC 的细分**：标准把"会话内稳定但跨会话变化"和"每行变化"混为一谈。PostgreSQL 等引擎在标准之外细分。

后续标准修订未对这一节做大改动 —— SQL:2003 引入了表函数与窗口函数，SQL:2011 引入时态特性，但 `DETERMINISTIC` 关键字的语义沿用 SQL:1999 至今。

## 支持矩阵

### DETERMINISTIC 关键字与等价标记

| 引擎 | 标记关键字 | 默认值 | 三级模型 | 自动推断 | 首次支持版本 | 备注 |
|------|-----------|--------|---------|---------|-------------|------|
| **SQL 标准** | `DETERMINISTIC` / `NOT DETERMINISTIC` | NOT DETERMINISTIC | 否 | 否 | SQL:1999 | -- |
| PostgreSQL | `IMMUTABLE` / `STABLE` / `VOLATILE` | VOLATILE | **是** | 否 | 7.2 (2002) | 业界三级模型奠基者 |
| Oracle | `DETERMINISTIC` | 非确定性（无关键字） | 否 | 11g 起部分推断 | 8i (1999) | 同期跟进标准 |
| SQL Server | `WITH SCHEMABINDING` + 推断 | 非确定性 | 否（推断三态） | **是** | 2000 | 不允许用户直接声明 DETERMINISTIC |
| MySQL | `DETERMINISTIC` / `NOT DETERMINISTIC` | NOT DETERMINISTIC | 否 | 否 | 5.0 (2005) | 与 binlog 强相关 |
| MariaDB | `DETERMINISTIC` / `NOT DETERMINISTIC` | NOT DETERMINISTIC | 否 | 否 | 5.0 (2009) | 兼容 MySQL |
| DB2 | `DETERMINISTIC` / `NOT DETERMINISTIC` | NOT DETERMINISTIC | 否 | 否 | 7.0 (2000) | 严格遵循 SQL:1999 |
| SQLite | `SQLITE_DETERMINISTIC` 标志（C API） | 非确定性 | 否 | 否 | 3.8.3 (2014) | 通过函数注册时位标志 |
| Snowflake | `IMMUTABLE` / `VOLATILE` | VOLATILE | 否（二级） | 否 | GA | 借鉴 PG 但只用两级 |
| BigQuery | 隐式推断 | 隐式 | 否 | **是** | GA | 用户不可声明 |
| Redshift | `IMMUTABLE` / `STABLE` / `VOLATILE`（Python/SQL UDF） | VOLATILE | 是 | 否 | 2015+ | 兼容 PG 三级 |
| DuckDB | 内部函数属性 | -- | 否 | **是** | GA | UDF 通常按非确定处理 |
| ClickHouse | `is_deterministic` 内部标志 | -- | 否 | **是** | GA | 用户不可声明 |
| Trino | `DETERMINISTIC` / `NOT DETERMINISTIC`（SQL routine） | NOT DETERMINISTIC | 否 | 否 | 419 (2023) | SQL routine 起步较晚 |
| Presto | 同 Trino | NOT DETERMINISTIC | 否 | 否 | 0.x | 与 Trino 平行演进 |
| Spark SQL | UDF `deterministic()` 方法 | true | 否 | 否 | 1.x (2014) | 与 SQL DDL 分离 |
| Databricks | UDF `deterministic` 标志 | true | 否 | 否 | GA | 继承 Spark |
| Hive | `@UDFType(deterministic = true/false)` | true | 否 | 否 | 0.7 (2011) | Java 注解风格 |
| Flink SQL | `isDeterministic()` 方法 | true | 否 | 否 | 1.x | 流处理语义敏感 |
| CockroachDB | `IMMUTABLE` / `STABLE` / `VOLATILE` | VOLATILE | 是 | 否 | 22.2 (2022) | PG 兼容 |
| YugabyteDB | `IMMUTABLE` / `STABLE` / `VOLATILE` | VOLATILE | 是 | 否 | 2.0 | 继承 PG |
| Greenplum | `IMMUTABLE` / `STABLE` / `VOLATILE` | VOLATILE | 是 | 否 | 全版本 | 继承 PG |
| TimescaleDB | `IMMUTABLE` / `STABLE` / `VOLATILE` | VOLATILE | 是 | 否 | 继承 PG | 扩展 |
| SAP HANA | `DETERMINISTIC` | 非确定性 | 否 | 否 | 1.0+ | 与 SQL:1999 一致 |
| Teradata | `DETERMINISTIC` / `NOT DETERMINISTIC` | NOT DETERMINISTIC | 否 | 否 | V2R5 | -- |
| Vertica | `IMMUTABLE` / `STABLE` / `VOLATILE` | VOLATILE | 是 | 否 | 7.0 | PG 风格 |
| Informix | `VARIANT` / `NOT VARIANT`（反向语义） | VARIANT | 否 | 否 | 9.x | 反向标记：VARIANT 表示非确定性 |
| Firebird | `DETERMINISTIC` | 非确定性 | 否 | 否 | 2.1 (2008) | -- |
| H2 | `DETERMINISTIC` | 非确定性 | 否 | 否 | 1.0 | -- |
| HSQLDB | `DETERMINISTIC` / `NOT DETERMINISTIC` | NOT DETERMINISTIC | 否 | 否 | 2.x | -- |
| Derby | `DETERMINISTIC` / `NOT DETERMINISTIC` | NOT DETERMINISTIC | 否 | 否 | 10.5 | -- |
| TiDB | `DETERMINISTIC` / `NOT DETERMINISTIC` | NOT DETERMINISTIC | 否 | 否 | 兼容 MySQL | -- |
| OceanBase | `DETERMINISTIC` | 兼容源 | 否 | 否 | 3.0+ | MySQL/Oracle 双模式 |
| Doris | 函数注册时声明 | -- | 否 | 否 | 1.2 | -- |
| StarRocks | 函数注册时声明 | -- | 否 | 否 | 2.2 | -- |
| MaxCompute | `@Deterministic` 注解 | -- | 否 | 否 | GA | Java 注解 |
| Hologres | `IMMUTABLE` / `STABLE` / `VOLATILE` | VOLATILE | 是 | 否 | 兼容 PG | -- |
| Impala | UDF 创建时声明 | -- | 否 | 否 | 2.0 | -- |
| openGauss | `IMMUTABLE` / `STABLE` / `VOLATILE` | VOLATILE | 是 | 否 | 1.0 | 继承 PG |
| KingbaseES | `IMMUTABLE` / `STABLE` / `VOLATILE` | VOLATILE | 是 | 否 | V8+ | 继承 PG |
| 达梦 (DM) | `DETERMINISTIC` | 非确定性 | 否 | 否 | V7+ | -- |
| TDSQL | `DETERMINISTIC` | 兼容源 | 否 | 否 | 兼容源 | MySQL 兼容版 |
| PolarDB | 兼容源（PG/MySQL） | 兼容源 | 兼容源 | 兼容源 | 兼容源 | -- |
| Azure Synapse | 继承 SQL Server | 非确定性 | 否（推断） | **是** | GA | 沿用 SCHEMABINDING |
| Amazon Athena | 继承 Trino | NOT DETERMINISTIC | 否 | 否 | GA | -- |
| SingleStore | `DETERMINISTIC` | NOT DETERMINISTIC | 否 | 否 | 7.x | -- |
| Materialize | 内部标志 | -- | 否 | 是 | GA | 用户不可声明 |
| RisingWave | 内部标志 | -- | 否 | 是 | GA | 用户不可声明 |
| Firebolt | 内部推断 | -- | 否 | 是 | GA | -- |
| Yellowbrick | 继承 PG 三级 | VOLATILE | 是 | 否 | GA | -- |
| TDengine | UDF 属性 | -- | 否 | 否 | 3.0 | 时序场景 |
| Google Spanner | 隐式推断（GENERATED ALWAYS AS 的 STORED 列） | 隐式 | 否 | **是** | GA | 用户不可声明 |
| QuestDB | -- | -- | 否 | -- | -- | UDF 受限 |
| CrateDB | `DETERMINISTIC` | 非确定性 | 否 | 否 | 4.x+ | 用于生成列 |
| Exasol | UDF 创建时声明 | -- | 否 | 否 | 6.x | -- |

> 统计：约 30 个引擎暴露用户可声明的确定性关键字；约 6 个引擎采用自动推断（SQL Server / BigQuery / DuckDB / ClickHouse / Materialize / Spanner）；其余引擎或继承自上游（Synapse 继承 SQL Server，Athena 继承 Trino）。

### IMMUTABLE / STABLE / VOLATILE 三级模型采用

PostgreSQL 7.2（2002）首创，被多家 PG 兼容引擎沿用：

| 引擎 | IMMUTABLE | STABLE | VOLATILE | 默认 | 备注 |
|------|:-:|:-:|:-:|------|------|
| PostgreSQL | 是 | 是 | 是 | VOLATILE | 三级模型奠基 |
| Greenplum | 是 | 是 | 是 | VOLATILE | 完全继承 |
| TimescaleDB | 是 | 是 | 是 | VOLATILE | 完全继承 |
| CockroachDB | 是 | 是 | 是 | VOLATILE | 22.2+ |
| YugabyteDB | 是 | 是 | 是 | VOLATILE | 完全继承 |
| Redshift | 是 | 是 | 是 | VOLATILE | Python/SQL UDF |
| Vertica | 是 | 是 | 是 | VOLATILE | 同 PG 语义 |
| openGauss | 是 | 是 | 是 | VOLATILE | -- |
| KingbaseES | 是 | 是 | 是 | VOLATILE | -- |
| Hologres | 是 | 是 | 是 | VOLATILE | -- |
| Yellowbrick | 是 | 是 | 是 | VOLATILE | -- |
| Snowflake | 是 | -- | 是 | VOLATILE | 仅二级（无 STABLE） |
| 其他二元模型 | 等价 IMMUTABLE | 没有等价 | 等价 VOLATILE | -- | DETERMINISTIC ↔ IMMUTABLE 近似映射 |

> 关键缺失：SQL Server / Oracle / MySQL / DB2 等都不支持 STABLE 中间级别，只能在 IMMUTABLE 与 VOLATILE 之间二选一。这导致 `now()` 这类"会话内稳定"的函数只能被标为非确定性，损失了一些优化机会。

### SCHEMABINDING（SQL Server 特有）

`WITH SCHEMABINDING` 是 SQL Server 的独特机制，与 SQL 标准的 `DETERMINISTIC` 不直接对应：

| 维度 | DETERMINISTIC（标准）| SCHEMABINDING（SQL Server）|
|------|----------------------|----------------------------|
| 语义层面 | 同输入 → 同输出 | 锁定底层 schema 不允许变更 |
| 用户能否直接声明 | 是 | 是 |
| 优化器使用方式 | 直接信任 | 作为推断 IsDeterministic 的前提条件 |
| 是否影响 schema 演进 | 否 | 是（绑定的对象不能 DROP/ALTER） |
| 索引视图的强制要求 | -- | 必须 |
| 持久化计算列索引 | 隐式要求 | 必须 |

```sql
-- 没有 SCHEMABINDING 的 UDF 默认非确定性
CREATE FUNCTION dbo.square(@x INT) RETURNS INT
AS BEGIN RETURN @x * @x; END;
-- OBJECTPROPERTY(OBJECT_ID('dbo.square'), 'IsDeterministic') = 0

-- 加上 SCHEMABINDING 后由优化器推断
CREATE FUNCTION dbo.square(@x INT) RETURNS INT
WITH SCHEMABINDING
AS BEGIN RETURN @x * @x; END;
-- IsDeterministic = 1 （推断为确定性）
```

### CALLED ON NULL INPUT vs RETURNS NULL ON NULL INPUT

SQL:1999 的 NULL 调用控制是另一个独立维度：

| 引擎 | RETURNS NULL ON NULL INPUT | CALLED ON NULL INPUT | 默认 | 别名 |
|------|:-:|:-:|------|------|
| PostgreSQL | 是 (`STRICT`) | 是（默认） | CALLED ON NULL INPUT | `STRICT` |
| Oracle | 是 | 是 | CALLED ON NULL INPUT | -- |
| SQL Server | 是 (`RETURNS NULL ON NULL INPUT`) | 是 | CALLED ON NULL INPUT | -- |
| MySQL | 否（隐式 CALLED） | 是 | CALLED ON NULL INPUT | -- |
| DB2 | 是 | 是 | CALLED ON NULL INPUT | -- |
| Trino (SQL routine) | 否 | 是 | CALLED ON NULL INPUT | -- |
| H2 | 是 | 是 | CALLED ON NULL INPUT | -- |
| HSQLDB | 是 | 是 | CALLED ON NULL INPUT | -- |
| Derby | 是 | 是 | CALLED ON NULL INPUT | -- |
| Firebird | 否 | 是 | CALLED ON NULL INPUT | -- |
| 其他多数引擎 | 仅 CALLED | -- | CALLED | -- |

`RETURNS NULL ON NULL INPUT`（PostgreSQL 中称 `STRICT`）的语义：当**任何**输入参数为 NULL 时，引擎跳过函数体直接返回 NULL，**不调用**函数。这是另一种确定性优化 —— 优化器可以在常量推断阶段消除整个表达式。

### PARALLEL SAFE / PARALLEL_ENABLE

并行安全标志独立于确定性：

| 引擎 | 并行标志关键字 | 等级数 | 默认 | 首次版本 |
|------|--------------|--------|------|---------|
| PostgreSQL | `PARALLEL SAFE` / `RESTRICTED` / `UNSAFE` | 三级 | UNSAFE | 9.6 (2016) |
| Oracle | `PARALLEL_ENABLE` | 二元（开/关） | 关 | 8i (1999) |
| SQL Server | 优化器自动推断 | -- | -- | -- |
| DB2 | `ALLOW PARALLEL` / `DISALLOW PARALLEL` | 二元 | ALLOW | 7.0 |
| MySQL | -- | -- | -- | 不支持函数级并行 |
| Snowflake | 平台自动 | -- | -- | 平台 |
| BigQuery | 平台自动 | -- | -- | 平台 |
| Redshift | 自动（与 UDF 类型相关） | -- | -- | -- |
| Spark SQL | 推断（基于 deterministic 标志） | -- | -- | -- |
| Teradata | `PARALLEL` 声明 | 二元 | -- | V2R5 |
| Vertica | `fenced` / `unfenced`（隔离 vs 并行） | 二元 | fenced | 7.0 |
| Greenplum | 继承 PG 三级 | 三级 | UNSAFE | -- |
| CockroachDB | 继承 PG（分布式有额外限制） | 三级 | UNSAFE | 22.2+ |
| YugabyteDB | 继承 PG | 三级 | UNSAFE | 2.0+ |
| Trino | 平台自动（distributed） | -- | -- | -- |

### SQL-data 访问等级与确定性的正交关系

| 引擎 | NO SQL | CONTAINS SQL | READS SQL DATA | MODIFIES SQL DATA | 默认 |
|------|:-:|:-:|:-:|:-:|------|
| MySQL | 是 | 是 | 是 | 是 | CONTAINS SQL |
| MariaDB | 是 | 是 | 是 | 是 | CONTAINS SQL |
| DB2 | 是 | 是 | 是 | 是 | READS SQL DATA |
| Teradata | 是 | 是 | 是 | 是 | CONTAINS SQL |
| H2 | 是 | 是 | 是 | 是 | CONTAINS SQL |
| HSQLDB | 是 | 是 | 是 | 是 | CONTAINS SQL |
| Derby | 是 | 是 | 是 | 是 | CONTAINS SQL |
| PostgreSQL | 否（用 STABLE/VOLATILE 隐含） | -- | -- | -- | -- |
| Oracle | 否（用 PRAGMA） | -- | -- | -- | -- |
| SQL Server | 否（自动推断） | -- | -- | -- | -- |
| Snowflake | 否 | -- | -- | -- | -- |
| BigQuery | 否 | -- | -- | -- | -- |
| Trino | 否（SQL routine 仅 CONTAINS SQL 语义） | -- | -- | -- | -- |
| CockroachDB | 解析但忽略 | -- | -- | -- | -- |

> SQL:1999 设计 `DETERMINISTIC` 与 `READS SQL DATA` 正交可共存，但实务上多数引擎只采纳其中一面。

### 内置函数的典型分类

| 函数 | PostgreSQL | Oracle | SQL Server | MySQL | DB2 | 备注 |
|------|------------|--------|-----------|-------|-----|------|
| `abs(x)` / `mod(x,y)` | IMMUTABLE | DETERMINISTIC | IsDeterministic=1 | DETERMINISTIC | DETERMINISTIC | 纯算术 |
| `lower(s)` / `upper(s)` | IMMUTABLE* | DETERMINISTIC | IsDeterministic=1 | DETERMINISTIC | DETERMINISTIC | *依赖 collation |
| `length(s)` | IMMUTABLE | DETERMINISTIC | IsDeterministic=1 | DETERMINISTIC | DETERMINISTIC | -- |
| `now()` / `current_timestamp` | STABLE | 非确定性 | IsDeterministic=0 | NOT DETERMINISTIC | NOT DETERMINISTIC | 同事务内稳定（PG） |
| `clock_timestamp()` | VOLATILE | -- | -- | -- | -- | 每次调用不同 |
| `random()` / `rand()` | VOLATILE | 非确定性 | IsDeterministic=0 | NOT DETERMINISTIC | NOT DETERMINISTIC | 必须不同 |
| `nextval('seq')` | VOLATILE | 非确定性 | -- | -- | -- | 副作用 |
| `current_user` | STABLE | DETERMINISTIC | IsDeterministic=0 | -- | -- | PG 视为 STABLE |
| `to_char(ts, fmt)` | STABLE* | 非确定性 | -- | -- | -- | *依赖会话 timezone/lc_time |
| `json_extract` / `->>` | IMMUTABLE | DETERMINISTIC | IsDeterministic=1 | DETERMINISTIC | DETERMINISTIC | -- |
| `uuid_generate_v4()` | VOLATILE | -- | NEWID() IsDeterministic=0 | UUID() NOT DETERMINISTIC | -- | 随机 |
| `pg_backend_pid()` | STABLE | -- | @@SPID 非确定性 | CONNECTION_ID() | -- | 会话标识 |
| `length(blob)` | IMMUTABLE | DETERMINISTIC | DATALENGTH IsDeterministic=1 | DETERMINISTIC | DETERMINISTIC | -- |
| `coalesce(a,b)` | IMMUTABLE | DETERMINISTIC | IsDeterministic=1 | DETERMINISTIC | DETERMINISTIC | -- |

### 函数索引/生成列对确定性的要求

| 引擎 | 函数索引要求 | 生成列要求（STORED） | 生成列要求（VIRTUAL） | 物化视图增量刷新 |
|------|------------|---------------------|---------------------|-----------------|
| PostgreSQL | IMMUTABLE | IMMUTABLE | -- (12+ 仅 STORED) | IMMUTABLE |
| Oracle | DETERMINISTIC | DETERMINISTIC | DETERMINISTIC | 推断 |
| SQL Server | IsDeterministic + IsPrecise + SCHEMABINDING | 同左 | 计算列存在 schema 检查 | INDEXED VIEW 限制更严 |
| MySQL | DETERMINISTIC | DETERMINISTIC | DETERMINISTIC | 不支持物化视图 |
| MariaDB | -- (通过生成列) | DETERMINISTIC | DETERMINISTIC | -- |
| SQLite | SQLITE_DETERMINISTIC | SQLITE_DETERMINISTIC | SQLITE_DETERMINISTIC | -- (无物化视图) |
| DB2 | DETERMINISTIC | DETERMINISTIC | -- | DETERMINISTIC |
| Snowflake | -- (Search Optimization Service) | IMMUTABLE | -- | IMMUTABLE |
| BigQuery | -- (无传统索引) | 隐式确定性 | 隐式 | 自动推断 |
| Spanner | STORED | STORED | -- | -- |

## 各引擎详解

### SQL 标准（SQL:1999）DETERMINISTIC

```sql
-- 标准语法
CREATE FUNCTION sales_tax(amt DECIMAL(10,2))
  RETURNS DECIMAL(10,2)
  LANGUAGE SQL
  DETERMINISTIC
  CONTAINS SQL
  RETURNS NULL ON NULL INPUT
  RETURN amt * 0.08;

-- 对应的 NOT DETERMINISTIC 函数
CREATE FUNCTION current_session_id()
  RETURNS VARCHAR(36)
  LANGUAGE SQL
  NOT DETERMINISTIC          -- 默认值，可省略
  NO SQL
  CALLED ON NULL INPUT       -- 默认值，可省略
  RETURN CURRENT_USER || '@' || CURRENT_DATE;
```

完整的标准修饰符（按出现顺序惯例）：

```
LANGUAGE { SQL | <external language> }
DETERMINISTIC | NOT DETERMINISTIC
NO SQL | CONTAINS SQL | READS SQL DATA | MODIFIES SQL DATA
RETURNS NULL ON NULL INPUT | CALLED ON NULL INPUT
EXTERNAL ACTION | NO EXTERNAL ACTION   -- DB2 等扩展
```

### PostgreSQL：三级模型 + 并行安全

PostgreSQL 7.2（2002）引入 IMMUTABLE / STABLE / VOLATILE 三级模型，是最细致的实现：

```sql
-- IMMUTABLE：相同输入永远相同输出，完全无副作用
CREATE FUNCTION my_hash(text) RETURNS bigint
  LANGUAGE sql
  IMMUTABLE                  -- 波动性
  PARALLEL SAFE              -- 并行安全（独立维度）
  STRICT                     -- = RETURNS NULL ON NULL INPUT
  AS $$ SELECT hashtext($1)::bigint $$;

-- STABLE：同一查询/快照内稳定，跨快照可能变化
-- 适用于：依赖会话变量、可见性受 MVCC 影响的查询
CREATE FUNCTION current_tz_now() RETURNS timestamptz
  LANGUAGE sql
  STABLE                     -- 标准 SQL 没有这个等级
  PARALLEL SAFE
  AS $$ SELECT now() AT TIME ZONE current_setting('TimeZone') $$;

-- VOLATILE：每次调用可能不同（默认）
CREATE FUNCTION log_and_return(int) RETURNS int
  LANGUAGE plpgsql
  VOLATILE                   -- 默认值，可省略
  PARALLEL UNSAFE
  AS $$
  BEGIN
    INSERT INTO audit_log VALUES ($1);   -- 副作用！
    RETURN $1;
  END;
  $$;
```

#### 默认值与 PARALLEL 标志（9.6+）

PG 默认 VOLATILE，体现"安全比性能更重要"的设计哲学 —— 用户主动声明 IMMUTABLE 才能享受优化。`PARALLEL SAFE / RESTRICTED / UNSAFE` 与波动性正交：IMMUTABLE 通常 SAFE，但访问线程全局状态的 C 函数可能 UNSAFE；`random()` 是 VOLATILE PARALLEL RESTRICTED（多 worker 共享 PRNG 会导致不可预期序列）。

```sql
SELECT proname, provolatile, proparallel, proisstrict
FROM pg_proc
WHERE proname IN ('now', 'random', 'abs', 'lower', 'nextval');
--    proname  | provolatile | proparallel | proisstrict
-- ------------+-------------+-------------+-------------
--  abs        | i           | s           | t
--  lower      | i           | s           | t
--  nextval    | v           | u           | t
--  now        | s           | s           | t
--  random     | v           | r           | t
```

`provolatile`：'i'=IMMUTABLE / 's'=STABLE / 'v'=VOLATILE；`proparallel`：'s'=SAFE / 'r'=RESTRICTED / 'u'=UNSAFE；`proisstrict`：true 等价于 `RETURNS NULL ON NULL INPUT`。

### Oracle：DETERMINISTIC + PARALLEL_ENABLE + RESULT_CACHE

Oracle 8i（1999）同期跟进 SQL:1999，使用二元 `DETERMINISTIC`：

```sql
CREATE OR REPLACE FUNCTION tax_rate(p_region VARCHAR2)
  RETURN NUMBER
  DETERMINISTIC
IS
BEGIN
  CASE p_region
    WHEN 'US' THEN RETURN 0.08;
    WHEN 'EU' THEN RETURN 0.20;
    ELSE RETURN 0.10;
  END CASE;
END;
/

-- 函数索引（FBI）的前置条件
CREATE INDEX idx_tax ON invoices(tax_rate(region_code));
-- 必须 DETERMINISTIC，否则 ORA-30553

-- PARALLEL_ENABLE：允许函数在并行查询中执行
CREATE OR REPLACE FUNCTION expensive_calc(n NUMBER)
  RETURN NUMBER
  DETERMINISTIC
  PARALLEL_ENABLE
IS BEGIN RETURN n * n; END;
/

-- RESULT_CACHE：跨会话缓存确定性函数的结果（11g+）
CREATE OR REPLACE FUNCTION lookup_name(id NUMBER)
  RETURN VARCHAR2
  DETERMINISTIC
  RESULT_CACHE
IS
  v VARCHAR2(100);
BEGIN
  SELECT name INTO v FROM lookup_table WHERE id = id;
  RETURN v;
END;
/
```

#### PRAGMA RESTRICT_REFERENCES（11g 之前）

11g 之前用 `PRAGMA RESTRICT_REFERENCES(fn, WNDS, WNPS, RNDS, RNPS)` 声明纯度（Writes/Reads No Database/Package State）。11g 起优化器自动推断，PRAGMA 仅用于向后兼容。流水线表函数支持 `PARALLEL_ENABLE(PARTITION cur BY HASH(id)) CLUSTER cur BY (customer_id)` 声明分区/聚簇策略。

### SQL Server：WITH SCHEMABINDING + 自动推断

SQL Server 不允许用户直接声明 DETERMINISTIC，而是通过 SCHEMABINDING + 一组规则自动推断：

```sql
-- 不带 SCHEMABINDING 的 UDF 默认非确定性
CREATE FUNCTION dbo.square(@x INT) RETURNS INT
AS BEGIN RETURN @x * @x; END;
GO
SELECT OBJECTPROPERTY(OBJECT_ID('dbo.square'), 'IsDeterministic');  -- 0

-- 加 SCHEMABINDING 后由优化器推断
CREATE FUNCTION dbo.square_v2(@x INT) RETURNS INT
WITH SCHEMABINDING
AS BEGIN RETURN @x * @x; END;
GO
SELECT
  OBJECTPROPERTY(OBJECT_ID('dbo.square_v2'), 'IsDeterministic') AS det,
  OBJECTPROPERTY(OBJECT_ID('dbo.square_v2'), 'IsPrecise') AS pre,
  OBJECTPROPERTY(OBJECT_ID('dbo.square_v2'), 'IsSystemVerified') AS verified;
-- det=1, pre=1, verified=1
```

#### IsDeterministic 的推断规则

UDF 被视为确定性当且仅当全部满足：
1. 声明了 `WITH SCHEMABINDING`。
2. 不调用任何非确定性内置函数（NEWID, RAND, GETDATE, CURRENT_TIMESTAMP, NEWSEQUENTIALID 等）。
3. 不访问扩展存储过程。
4. 不引用其他非确定性的 schema-bound UDF。
5. 函数体不使用非确定性字段（如 `TIMESTAMP` / `ROWVERSION` 列）。
6. 内联表值函数（inline TVF）单独有更严苛规则。

#### 持久化计算列的索引要求

```sql
CREATE TABLE orders (
  id INT PRIMARY KEY,
  amount DECIMAL(10,2),
  tax_amount AS (dbo.calc_tax(amount)) PERSISTED   -- 必须 PERSISTED
);

-- 对计算列建索引
CREATE INDEX idx_tax ON orders(tax_amount);
-- 仅当 calc_tax 满足：IsDeterministic=1 AND IsPrecise=1 AND SCHEMABINDING
```

#### 索引视图的强制要求

索引视图（indexed view）必须 `WITH SCHEMABINDING`，聚合必须用 `SUM_BIG` / `COUNT_BIG` 避免 INT 溢出，不能含 OUTER JOIN / UNION / DISTINCT / TOP / 子查询，引用的所有 UDF 必须 IsDeterministic=1。

#### IsPrecise 维度

`IsPrecise` 是另一个独立维度：函数是否依赖浮点近似。FLOAT 运算 → IsPrecise=0；DECIMAL 运算 → IsPrecise=1。持久化计算列建索引要求 IsPrecise=1（避免不同硬件浮点行为差异导致键不一致）。

### MySQL：DETERMINISTIC + binlog 安全

MySQL 5.0（2005）引入 SQL:1999 风格的 DETERMINISTIC：

```sql
DELIMITER //

-- 显式确定性
CREATE FUNCTION my_square(x INT)
RETURNS INT
DETERMINISTIC
NO SQL                       -- SQL-data 访问等级
BEGIN
  RETURN x * x;
END //

-- 读表的确定性函数
CREATE FUNCTION get_tax(region VARCHAR(2))
RETURNS DECIMAL(5,4)
DETERMINISTIC
READS SQL DATA               -- 可与 DETERMINISTIC 共存
BEGIN
  DECLARE rate DECIMAL(5,4);
  SELECT tax_rate INTO rate FROM regions WHERE code = region;
  RETURN rate;
END //

-- 默认 NOT DETERMINISTIC
CREATE FUNCTION age_days(birthdate DATE)
RETURNS INT
NOT DETERMINISTIC            -- 显式声明
NO SQL
BEGIN
  RETURN DATEDIFF(CURRENT_DATE, birthdate);   -- 包含 CURRENT_DATE → 非确定
END //

DELIMITER ;
```

#### 与 binlog 的紧密耦合

MySQL 的 statement-based binlog（SBR）要求确定性，否则主从复制会产生不一致：

```sql
-- 默认情况下，创建带副作用的函数会被拒绝
SET GLOBAL log_bin = ON;
SET GLOBAL binlog_format = STATEMENT;

DELIMITER //
CREATE FUNCTION risky_fn() RETURNS INT
NOT DETERMINISTIC MODIFIES SQL DATA
BEGIN
  INSERT INTO audit VALUES (UUID());
  RETURN 1;
END //
-- ERROR 1418 (HY000): This function has none of DETERMINISTIC, NO SQL,
-- or READS SQL DATA in its declaration and binary logging is enabled
-- (you *might* want to use the less safe log_bin_trust_function_creators variable)

-- 解决方案 1：显式声明（如果确实是的话）
DELIMITER //
CREATE FUNCTION safe_fn() RETURNS INT
DETERMINISTIC NO SQL
BEGIN RETURN 42; END //

-- 解决方案 2：开启信任（不推荐）
SET GLOBAL log_bin_trust_function_creators = 1;
```

这是 MySQL 特有的限制：其他引擎不会因为 binlog 拒绝创建函数。

#### 默认值陷阱

```sql
-- MySQL 的"宽松默认"：如果不显式声明，按 NOT DETERMINISTIC 处理
DELIMITER //
CREATE FUNCTION pure_fn(x INT) RETURNS INT
BEGIN RETURN x * x; END //
-- 没有 DETERMINISTIC → 默认非确定 → 函数索引、生成列等都不能用
```

最佳实践：始终显式声明（DETERMINISTIC + NO SQL/READS SQL DATA + 是否 STRICT）。

#### 函数索引的要求（8.0.13+）

```sql
-- 函数索引要求所有引用的函数都是 DETERMINISTIC
CREATE FUNCTION normalize(s VARCHAR(255)) RETURNS VARCHAR(255)
DETERMINISTIC NO SQL
RETURN LOWER(TRIM(s));

CREATE TABLE users (
  email VARCHAR(255),
  INDEX idx_norm ((normalize(email)))   -- 8.0.13+
);

-- 如果 normalize 是 NOT DETERMINISTIC，CREATE INDEX 失败
```

### MariaDB：与 MySQL 兼容

MariaDB 5.0+ 完全兼容 MySQL 的 DETERMINISTIC 语法，包括 `log_bin_trust_function_creators` 限制。10.2+ 通过虚拟生成列实现表达式索引。

### DB2：严格的 SQL:1999 实现

DB2 7.0（2000）按 SQL:1999 完整实现修饰符：

```sql
CREATE FUNCTION calc_bonus(salary DECIMAL(10,2))
  RETURNS DECIMAL(10,2)
  LANGUAGE SQL
  DETERMINISTIC
  NO EXTERNAL ACTION              -- DB2 扩展：是否对 DB2 之外的世界有影响
  CONTAINS SQL
  RETURN salary * 0.15;
```

完整修饰符：
```
DETERMINISTIC | NOT DETERMINISTIC
EXTERNAL ACTION | NO EXTERNAL ACTION
NO SQL | CONTAINS SQL | READS SQL DATA | MODIFIES SQL DATA
ALLOW PARALLEL | DISALLOW PARALLEL
FENCED | NOT FENCED                -- 外部 UDF 隔离
RETURNS NULL ON NULL INPUT | CALLED ON NULL INPUT
```

#### EXTERNAL ACTION 的独特语义

DB2 引入 `EXTERNAL ACTION` 概念：函数是否对 DB2 数据库之外的世界（文件系统、网络、邮件）有影响。这与 SQL-data 访问等级（仅限 DB2 内部）正交：

```sql
-- 写日志、发邮件、调 Web 服务的函数
CREATE FUNCTION send_alert(msg VARCHAR(1000))
  RETURNS INT
  LANGUAGE C
  EXTERNAL NAME 'mylib!send_alert_impl'
  EXTERNAL ACTION                 -- 优化器不能消除重复调用
  NOT DETERMINISTIC
  NO SQL
  ALLOW PARALLEL;

-- 纯计算函数
CREATE FUNCTION pure_calc(x INT) RETURNS INT
  LANGUAGE SQL
  DETERMINISTIC
  NO EXTERNAL ACTION              -- 优化器可消除重复调用
  CONTAINS SQL
  RETURN x * x;
```

`NO EXTERNAL ACTION` + `DETERMINISTIC` 联合允许优化器：
1. 在常量参数下做 planning 时折叠。
2. 跨行 CSE。
3. 不必保证函数体的物理调用次数（可减少调用）。

`EXTERNAL ACTION` 强制优化器保留每个语义上必要的调用（不能合并、不能减少调用次数）。

### SQLite：C API 标志位

SQLite 通过 C API 注册 UDF 时传递 `SQLITE_DETERMINISTIC` 标志位（3.8.3+，2014 年）：

```c
sqlite3_create_function_v2(
    db,
    "my_hash",
    1,                                           // 参数个数
    SQLITE_UTF8 | SQLITE_DETERMINISTIC,          // 标志位
    NULL,                                        // 用户数据
    my_hash_impl,                                // xFunc
    NULL, NULL, NULL                             // 聚合相关
);
```

不通过 SQL DDL 声明，因为 SQLite 不支持 SQL 函数语言。

```sql
-- 确定性 UDF 可用于：
CREATE INDEX idx_hash ON t(my_hash(col));     -- 表达式索引
CREATE TABLE t (
  raw TEXT,
  norm TEXT GENERATED ALWAYS AS (my_hash(raw)) STORED   -- 生成列
);
ALTER TABLE t ADD CONSTRAINT chk CHECK (my_hash(col) > 0);  -- CHECK 约束

-- 部分索引的 WHERE 表达式
CREATE INDEX idx_active ON users(name) WHERE my_hash(status) = 1;
```

### Snowflake：IMMUTABLE / VOLATILE 二级

```sql
CREATE OR REPLACE FUNCTION add_tax(amt NUMBER)
RETURNS NUMBER
LANGUAGE SQL
IMMUTABLE
AS $$ amt * 1.10 $$;

CREATE OR REPLACE FUNCTION current_rate()
RETURNS NUMBER
LANGUAGE SQL
VOLATILE
AS $$ (SELECT rate FROM rates ORDER BY ts DESC LIMIT 1) $$;
```

只有 IMMUTABLE 与 VOLATILE 两级，没有 STABLE 中间级别。默认 VOLATILE。

```sql
-- 物化视图要求底层表达式 IMMUTABLE
CREATE MATERIALIZED VIEW mv AS
SELECT id, add_tax(amount) AS tax_amt FROM orders;
-- add_tax 是 IMMUTABLE → 允许
-- 如果引用 current_rate() → 报错
```

### BigQuery：完全自动推断

BigQuery 不允许用户声明 DETERMINISTIC，根据函数体语义自动分类：

```sql
-- 自动判定：纯计算 → 确定性
CREATE FUNCTION ds.add_tax(amt FLOAT64)
RETURNS FLOAT64
AS (amt * 1.10);

-- 自动判定：引用 RAND() → 非确定性
CREATE FUNCTION ds.random_score()
RETURNS FLOAT64
AS (RAND() * 100);

-- 自动判定：引用 CURRENT_TIMESTAMP() → 非确定性
CREATE FUNCTION ds.now_plus(delta INT64)
RETURNS TIMESTAMP
AS (TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL delta SECOND));
```

非确定性函数的影响：
- 物化视图只支持确定性表达式。
- 查询缓存对包含非确定性函数的查询禁用。
- 表函数的 cost 估算更保守。

### Trino / Presto：SQL routine（419+, 2023）

Trino 419（2023）引入 SQL routine，支持 DETERMINISTIC：

```sql
CREATE FUNCTION add_tax(amt DOUBLE)
RETURNS DOUBLE
LANGUAGE SQL
DETERMINISTIC
RETURN amt * 1.10;

-- NOT DETERMINISTIC（默认）
CREATE FUNCTION random_score()
RETURNS DOUBLE
LANGUAGE SQL
RETURN RANDOM();
```

Trino 内部函数也有 `deterministic` 标志，通过 `@ScalarFunction(deterministic = true)` 声明：

```java
@ScalarFunction(value = "my_hash", deterministic = true)
@SqlType(StandardTypes.BIGINT)
public static long myHash(@SqlType(StandardTypes.VARCHAR) Slice s) {
    return XxHash64.hash(s);
}
```

非确定性函数在 Trino 中的特殊行为：
- 不能被推到 connector（`Connector` 接口的 `pushdown` 拒绝）。
- 不参与 CSE。
- AQE 的某些优化被禁用。

### Spark SQL / Databricks

Spark 的 UDF API 通过方法标记 deterministic（不通过 SQL DDL）：

```scala
val pureUdf = udf((x: Int) => x * 2)                                 // 默认 deterministic
val randomUdf = udf(() => Random.nextDouble()).asNonDeterministic()  // 显式非确定
```

```python
random_udf = udf(lambda: random.random()).asNondeterministic()
```

确定性 UDF 允许：谓词下推到数据源、常量折叠、CSE、投影裁剪。非确定性 UDF 阻止上述优化，并影响 AQE。

### Hive：@UDFType 注解

```java
@UDFType(deterministic = true, stateful = false)
public class MyHashUDF extends UDF {
    public long evaluate(String input) { return input.hashCode() & 0xFFFFFFFFL; }
}
```

`@UDFType` 有两个独立属性：`deterministic` 是否确定性、`stateful` 是否有状态（跨行累加）。stateful UDF 即使 deterministic=true 也会强制禁用某些优化（如 vectorization）。

### Flink SQL：流处理的特殊语义

```java
public class MyUDF extends ScalarFunction {
    @Override public boolean isDeterministic() { return true; }   // 默认 true
    public Integer eval(Integer x) { return x * 2; }
}
```

Flink 流处理对非确定性函数的语义影响特别大：

1. **状态恢复**：checkpoint 恢复后，非确定性函数可能产生与之前不同的结果，破坏 exactly-once 语义。
2. **回溯计算（Retraction）**：动态表的更新流要求"撤回 + 重发"，非确定性函数会让两次计算结果不同，撤回失败。
3. **物化视图维护**：增量更新算子要求所有表达式确定性。
4. **Watermark 传播**：基于事件时间的逻辑要求时间提取函数确定。

### CockroachDB / YugabyteDB / Greenplum / TimescaleDB：PG 兼容

完全继承 PostgreSQL 的 IMMUTABLE / STABLE / VOLATILE 三级模型：

```sql
-- CockroachDB 22.2+
CREATE FUNCTION add_tax(amt DECIMAL) RETURNS DECIMAL
  LANGUAGE SQL
  IMMUTABLE
  AS 'SELECT amt * 1.10';
```

差异点：
- **CockroachDB**：分布式执行下 PARALLEL 标志被忽略（自带分布式调度），但波动性会用于 follower read 的可见性判断。
- **YugabyteDB**：完整继承，加上 raft 一致性保证。
- **Greenplum**：MPP 下波动性影响数据分布与 motion 算子。
- **TimescaleDB**：超表的连续聚合要求底层函数 IMMUTABLE。

### SAP HANA：DETERMINISTIC 关键字

```sql
CREATE FUNCTION calc_bonus(salary DECIMAL(10,2))
RETURNS DECIMAL(10,2)
DETERMINISTIC
AS BEGIN
  RETURN :salary * 0.15;
END;
```

HANA 的 DETERMINISTIC 与计算列、CDS 视图的列投影紧密相关。

### Teradata：DETERMINISTIC + PARALLEL

```sql
REPLACE FUNCTION calc_hash(input VARCHAR(100))
RETURNS VARCHAR(32)
LANGUAGE SQL
DETERMINISTIC
PARALLEL                  -- Teradata 扩展
CONTAINS SQL
RETURN SUBSTR(hashrow(input), 1, 32);
```

### Vertica：PG 风格三级

Vertica 沿用 PG 的 IMMUTABLE / STABLE / VOLATILE，默认 VOLATILE。Vertica 的"投影"（projection）替代传统索引，但确定性要求与 PG 类似。

### Informix：反向标记 VARIANT

Informix 用 `VARIANT` / `NOT VARIANT` 反向标记确定性：

```sql
CREATE FUNCTION calc_score(x INT) RETURNS INT
WITH (NOT VARIANT)              -- 等价于 DETERMINISTIC
RETURN x * 100;

CREATE FUNCTION random_pick(arr LVARCHAR) RETURNS LVARCHAR
WITH (VARIANT)                  -- 等价于 NOT DETERMINISTIC（默认）
...
```

`VARIANT` = "结果会变" = NOT DETERMINISTIC。这种反向命名是历史遗留。

### Firebird / H2 / HSQLDB / Derby

Firebird 2.1（2008）、H2、HSQLDB、Derby 都支持标准 SQL:1999 风格 `DETERMINISTIC`：

```sql
-- HSQLDB / Derby
CREATE FUNCTION calc_score(x INT) RETURNS INT
LANGUAGE SQL DETERMINISTIC NO SQL
RETURN x * 100;
```

Firebird 的 `COMPUTED BY` 计算列可引用 DETERMINISTIC 函数。这些嵌入式引擎实现深度有限，主要用于约束验证而非真正的优化器决策。

### TiDB / OceanBase / 国产引擎

TiDB、OceanBase 兼容 MySQL/Oracle 的 DETERMINISTIC 语法。openGauss、KingbaseES、Hologres 完全继承 PG 三级模型与并行安全标志。达梦 (DM) V7+ 支持 SQL:1999 风格的 `DETERMINISTIC` 关键字。TiDB 的分布式执行考虑波动性决定 coprocessor 下推，CockroachDB 的分布式调度自带并行所以 PARALLEL 标志被忽略。

## IMMUTABLE / STABLE / VOLATILE 三级模型详解

### PostgreSQL 三级模型的设计动机

PostgreSQL 7.2（2002）引入三级模型时的核心观察：SQL:1999 的二元 `DETERMINISTIC / NOT DETERMINISTIC` 不足以区分以下两类函数：

1. **`now()`**：相同输入（无参数）在同一 SELECT 内多次调用返回相同值，但跨事务/跨快照可能不同。
2. **`random()`**：每次调用都不同，连同一行内多次调用都可能不同。

二者都是"NOT DETERMINISTIC"，但优化器对二者的处理截然不同：
- `now()`：可在查询开始时计算一次，整个 SELECT 内复用 → 等价于"快照内 IMMUTABLE"。
- `random()`：每次必算 → 不可复用。

PostgreSQL 用 STABLE 表示前者，VOLATILE 表示后者，IMMUTABLE 表示真正的 SQL:1999 DETERMINISTIC。

### 三级语义的精确定义

```
IMMUTABLE:
  对所有输入参数，函数总是返回相同结果。
  与数据库状态、会话状态、时间无关。
  允许：planning 时常量折叠；索引；生成列；CHECK；分区键。

STABLE:
  在同一 SQL 语句的执行过程中（即同一 snapshot 内），
  对相同输入返回相同结果。
  跨语句/跨事务可能变化。
  允许：跨行 CSE；不允许索引/生成列。

VOLATILE:
  每次调用都可能返回不同结果，即使输入相同。
  允许：什么优化都不许做。
  默认值。
```

### 三级与优化的对照

| 优化 | IMMUTABLE | STABLE | VOLATILE |
|------|:-:|:-:|:-:|
| Planning 时常量折叠（参数也是常量） | 是 | 否 | 否 |
| 同一执行内跨行 CSE | 是 | 是 | 否 |
| 作为索引表达式 | 是 | 否 | 否 |
| 作为生成列表达式 | 是 | 否 | 否 |
| 作为分区键 | 是 | 否 | 否 |
| 作为 CHECK 约束子表达式 | 是 | 否 | 否 |
| 在 LIKE 'foo' \|\| f(x) 推断 prefix 索引扫描 | 是 | 否 | 否 |
| 用作 FDW push-down 条件 | 是 | 实现相关 | 否 |
| 物化视图增量刷新 | 是 | 否 | 否 |

### 为什么二元模型损失优化机会

```sql
-- 二元模型（如 SQL Server）下，now() 是非确定的
SELECT * FROM events WHERE ts > now() - interval '1 day';

-- 如果 now() 被标为非确定（保守正确），优化器要么：
-- 1. 每行都调用 now()  ← 显然浪费
-- 2. 调用一次然后假装是常量  ← 可能违反语义

-- PostgreSQL 三级模型下，now() 是 STABLE
-- 优化器明确知道：在同一 SELECT 内调用一次即可
-- → 可以提取为常量并下推到分区裁剪
```

### STABLE 函数与索引：为什么不允许？

```sql
-- 假设允许 STABLE 函数建索引
CREATE FUNCTION current_user_id() RETURNS INT
LANGUAGE sql STABLE
AS $$ SELECT id FROM users WHERE name = current_user $$;

-- 假想的索引
CREATE INDEX idx_owner ON docs (current_user_id());

-- 问题：插入时 current_user 是 alice，存的索引键是 alice 的 id
-- 查询时 current_user 是 bob，查的是 bob 的 id
-- → 索引中找不到（实际上的所有者是 alice）
-- → 一致性破坏

-- 因此 PG 拒绝：ERROR: functions in index expression must be marked IMMUTABLE
```

## MySQL DETERMINISTIC 与 binlog 的深度交互

### Statement-Based Replication (SBR) 的不变量

MySQL 主从复制有三种 binlog 格式：
- **STATEMENT**：记录原始 SQL 语句，从库重放。
- **ROW**：记录每一行变化的实际值。
- **MIXED**：默认，按需切换。

SBR 要求确定性：从库重放主库的语句必须产生相同结果。如果语句中包含 `RAND()` 或 `UUID()`，主从结果会不同 → 数据不一致。

### 关键限制：函数创建时的强制检查

```sql
-- 默认 binlog 启用时
SHOW VARIABLES LIKE 'log_bin';                     -- ON
SHOW VARIABLES LIKE 'log_bin_trust_function_creators';   -- OFF
SHOW VARIABLES LIKE 'binlog_format';               -- ROW or MIXED

-- 创建会修改数据的函数时，需要明确"承诺"确定性
DELIMITER //
CREATE FUNCTION risky_fn() RETURNS INT
BEGIN                                              -- 没有 DETERMINISTIC / NO SQL / READS SQL DATA
  INSERT INTO audit VALUES (UUID());
  RETURN 1;
END //
-- ERROR 1418 (HY000)
```

错误消息提示三个出路：
1. 标记 `DETERMINISTIC`（如果真的是）。
2. 标记 `NO SQL`（不读不写 SQL）。
3. 标记 `READS SQL DATA`（只读不改）。
4. 设置 `log_bin_trust_function_creators = 1`（信任所有创建者，绕过检查）。

### 即使函数是确定性的，仍可能影响 binlog 格式

```sql
-- 确定性函数 + 修改数据
DELIMITER //
CREATE FUNCTION inc_counter(name VARCHAR(50)) RETURNS INT
DETERMINISTIC                                      -- 用户承诺确定性
MODIFIES SQL DATA
BEGIN
  UPDATE counters SET v = v + 1 WHERE n = name;
  SELECT v INTO @v FROM counters WHERE n = name;
  RETURN @v;
END //
-- 创建成功

-- 但执行时 MySQL 会自动切换为 ROW binlog（因为 MODIFIES SQL DATA）
-- 即使 binlog_format = STATEMENT，单语句也会按 ROW 写入
```

### 关键陷阱：DETERMINISTIC 但实际不是

```sql
-- 用户可能错误声明
DELIMITER //
CREATE FUNCTION wrong_fn() RETURNS INT
DETERMINISTIC                                      -- 谎称确定
NO SQL
BEGIN
  RETURN UNIX_TIMESTAMP();                         -- 实际包含时间！
END //

-- MySQL 不验证函数体，相信用户声明
-- → 主从复制时，主库 ts=100，从库 ts=200 → 数据不一致
-- → 用户责任
```

最佳实践：函数体引用任何"非确定来源"（NOW、RAND、UUID、CONNECTION_ID 等）就不应标 DETERMINISTIC。

### MariaDB 的同等限制

MariaDB 完全继承 MySQL 的 binlog + DETERMINISTIC 限制。

## SQL Server SCHEMABINDING 的多重作用

### SCHEMABINDING 的"附加"语义

`WITH SCHEMABINDING` 不仅是确定性推断的前提，它本身还有 schema 锁定的副作用：

```sql
-- 不带 SCHEMABINDING 的 UDF
CREATE FUNCTION dbo.use_table_a(@id INT) RETURNS INT
AS BEGIN
  DECLARE @v INT;
  SELECT @v = val FROM dbo.table_a WHERE id = @id;
  RETURN @v;
END;

-- 之后可以自由 DROP / ALTER table_a：
DROP TABLE dbo.table_a;       -- 成功（即使函数引用了它）
-- 函数会在调用时报错
```

```sql
-- 带 SCHEMABINDING
CREATE FUNCTION dbo.use_table_a_v2(@id INT) RETURNS INT
WITH SCHEMABINDING
AS BEGIN
  DECLARE @v INT;
  SELECT @v = val FROM dbo.table_a WHERE id = @id;
  RETURN @v;
END;

-- 现在 table_a 被绑定，不能 DROP / ALTER 影响列：
DROP TABLE dbo.table_a;
-- ERROR: Cannot drop the table 'dbo.table_a' because it is being referenced by object 'dbo.use_table_a_v2'.
```

这种"双重语义"使 SCHEMABINDING 有点类似 `CREATE INDEX` —— 它创建一个物理对象绑定，限制 schema 演进。

### 为什么 SQL Server 选择 SCHEMABINDING 而非 DETERMINISTIC

历史原因：SQL Server 2000 引入计算列与索引视图时，需要保证：
1. 函数体确定（同输入同输出）。
2. 函数引用的对象不能在不通知索引的情况下被修改。

SCHEMABINDING 同时解决了这两个问题：锁定底层 schema → 优化器可以信任引用的列定义稳定 → 然后基于函数体内容推断确定性。

如果只有 DETERMINISTIC（不锁定 schema），底层表的列类型变化（如 INT → BIGINT）会让索引值类型悄悄改变，破坏一致性。

### 索引视图的强制要求

```sql
-- 索引视图必须 WITH SCHEMABINDING
CREATE VIEW dbo.daily_summary
WITH SCHEMABINDING
AS
SELECT order_date,
       SUM_BIG(amount) AS total,
       COUNT_BIG(*) AS cnt
FROM dbo.orders
GROUP BY order_date;
GO

-- 然后才能建唯一聚簇索引
CREATE UNIQUE CLUSTERED INDEX idx_summary
ON dbo.daily_summary(order_date);
```

索引视图（indexed view）的额外限制：
1. 必须 SCHEMABINDING。
2. 引用的所有 UDF 必须 SCHEMABINDING + IsDeterministic=1。
3. 不能含 OUTER JOIN / UNION（旧版本）/ DISTINCT / TOP / 子查询 / CTE。
4. 聚合必须用 SUM_BIG / COUNT_BIG。
5. SELECT 列表不能含表达式（部分版本）。
6. 表必须用两段命名（`dbo.table_a`）。

这些限制大部分是为了让"持久化的视图状态"能被增量维护。

## CALLED ON NULL INPUT vs RETURNS NULL ON NULL INPUT

### NULL 调用语义

SQL:1999 定义两种 NULL 处理方式：

```sql
-- CALLED ON NULL INPUT（默认）：NULL 也调用函数体
CREATE FUNCTION echo(x INT) RETURNS INT
CALLED ON NULL INPUT
RETURN COALESCE(x, -1);
SELECT echo(NULL);  -- 返回 -1（函数体被调用）

-- RETURNS NULL ON NULL INPUT：任何 NULL 输入直接返回 NULL
CREATE FUNCTION square(x INT) RETURNS INT
RETURNS NULL ON NULL INPUT
RETURN x * x;
SELECT square(NULL);  -- 返回 NULL（函数体未被调用）
```

### 优化意义

`RETURNS NULL ON NULL INPUT`（PostgreSQL 中称 `STRICT`）使优化器可以：
1. 在常量传播阶段：参数为 NULL 常量时，整个表达式直接折叠为 NULL。
2. 跳过函数调用开销。
3. 在 WHERE 推断时：`WHERE strict_fn(NULL)` 等价于 `WHERE NULL` → 整个查询为空集。

### 各引擎差异

```sql
-- PostgreSQL 用 STRICT 关键字（同 RETURNS NULL ON NULL INPUT）
CREATE FUNCTION calc(x INT) RETURNS INT
LANGUAGE sql IMMUTABLE STRICT
AS $$ SELECT x * 2 $$;

-- Oracle 不直接支持 RETURNS NULL ON NULL INPUT，要在函数体内显式处理
CREATE FUNCTION calc(x NUMBER) RETURN NUMBER DETERMINISTIC
IS BEGIN
  IF x IS NULL THEN RETURN NULL; END IF;
  RETURN x * 2;
END;

-- SQL Server 支持
CREATE FUNCTION dbo.calc(@x INT) RETURNS INT
WITH RETURNS NULL ON NULL INPUT, SCHEMABINDING
AS BEGIN RETURN @x * 2; END;

-- MySQL 不支持声明（隐式 CALLED ON NULL INPUT）
-- 必须在函数体内显式判断
DELIMITER //
CREATE FUNCTION calc(x INT) RETURNS INT DETERMINISTIC NO SQL
BEGIN
  IF x IS NULL THEN RETURN NULL; END IF;
  RETURN x * 2;
END //

-- DB2 完整支持
CREATE FUNCTION calc(x INT) RETURNS INT
DETERMINISTIC NO SQL
RETURNS NULL ON NULL INPUT
RETURN x * 2;
```

### 与 DETERMINISTIC 的正交性

`RETURNS NULL ON NULL INPUT` 与 `DETERMINISTIC` 完全独立。可以组合：

```
| RETURNS NULL ON NULL INPUT | CALLED ON NULL INPUT
DETERMINISTIC      |  纯且可短路（最优）        |  纯但 NULL 也调用
NOT DETERMINISTIC  |  非纯但 NULL 短路          |  完全保守
```

## PARALLEL SAFE / PARALLEL_ENABLE：跨引擎对比

### PostgreSQL 9.6+ 三级模型

```sql
CREATE FUNCTION pure_calc(int) RETURNS int
  LANGUAGE sql IMMUTABLE
  PARALLEL SAFE                  -- 默认 UNSAFE
  AS $$ SELECT $1 * 2 $$;
```

| 等级 | 语义 | 执行位置 |
|------|------|---------|
| PARALLEL SAFE | 完全可并行 | 任何 worker |
| PARALLEL RESTRICTED | 必须 leader 执行 | 仅 leader |
| PARALLEL UNSAFE | 整个查询串行 | -- |

PARALLEL UNSAFE 的常见原因：
1. 修改数据库状态（DML、DDL）。
2. 写 WAL / 创建临时对象。
3. 修改 session state（SET、prepared statement）。
4. 调用其他 PARALLEL UNSAFE 函数。
5. C 函数访问全局变量。

PARALLEL RESTRICTED 的常见原因：
1. 访问临时表（仅 leader 可见）。
2. 使用 cursor。
3. `random()` / `clock_timestamp()`（多 worker 共享 PRNG 会导致不可预期序列）。

### Oracle PARALLEL_ENABLE

```sql
CREATE OR REPLACE FUNCTION expensive_calc(n NUMBER)
  RETURN NUMBER
  DETERMINISTIC
  PARALLEL_ENABLE                -- 二元开关
IS BEGIN RETURN n * n; END;
/

-- 流水线表函数：声明分区/聚簇策略
CREATE OR REPLACE FUNCTION parallel_tab_fn(cur SYS_REFCURSOR)
  RETURN my_tab PIPELINED
  PARALLEL_ENABLE(PARTITION cur BY HASH (id))
  CLUSTER cur BY (customer_id)
IS ...
```

Oracle 的 PARALLEL_ENABLE 比 PG 简单（二元），但表函数的分区策略更丰富。

### DB2 ALLOW PARALLEL / DISALLOW PARALLEL

```sql
CREATE FUNCTION pure_calc(x INT) RETURNS INT
  LANGUAGE SQL
  DETERMINISTIC
  ALLOW PARALLEL                 -- 默认
  RETURN x * x;

CREATE FUNCTION shared_state_fn(x INT) RETURNS INT
  LANGUAGE C
  EXTERNAL NAME 'mylib!fn'
  DISALLOW PARALLEL              -- 函数访问全局状态
  ...
```

### 自动推断（Snowflake / BigQuery / SQL Server / Spark）

这些引擎不暴露并行声明，内部根据：
- DETERMINISTIC 标志（确定性 → 通常可并行）
- 函数类型（标量、表函数、聚合）
- 副作用分析

自动决定是否并行。

## 物化视图增量刷新对确定性的依赖

### 增量刷新的不变量

```
View_t1 = View_t0  +  Δ_changes(t0 → t1)
```

要让"局部应用 delta"等价于"全量重算"，必须满足：
1. 视图定义中的所有函数对相同输入返回相同输出。
2. 聚合函数支持增量更新（COUNT、SUM 是；MEDIAN 不是）。

### 各引擎的物化视图确定性要求

| 引擎 | 物化视图 | 增量刷新 | 函数确定性要求 | 备注 |
|------|---------|---------|---------------|------|
| PostgreSQL | 是 | 否（仅全量） | -- | `REFRESH MATERIALIZED VIEW`，无增量 |
| Oracle | 是 | 是（FAST REFRESH） | DETERMINISTIC | 严格 |
| SQL Server | 索引视图 | 是（自动） | IsDeterministic=1 + IsPrecise=1 + SCHEMABINDING | 严格 |
| MySQL | -- | -- | -- | 无物化视图 |
| Snowflake | 是 | 是（自动） | IMMUTABLE | -- |
| BigQuery | 是 | 是（增量） | 自动推断确定性 | 包含非确定函数则禁用 |
| Redshift | 是 | 是（增量） | IMMUTABLE | -- |
| ClickHouse | 是（实时聚合） | 是（推送式） | is_deterministic | -- |
| TimescaleDB | 是（连续聚合） | 是 | IMMUTABLE | -- |
| Databricks | 是（Delta MV） | 是（增量） | deterministic | -- |
| Materialize | 是（流式） | 是（毫秒级） | 推断 | 整个引擎围绕物化视图设计 |
| RisingWave | 是（流式） | 是 | 推断 | -- |

### 典型陷阱

```sql
-- PostgreSQL 物化视图（无增量）
CREATE MATERIALIZED VIEW daily_orders AS
SELECT date_trunc('day', created_at) AS day,
       count(*) AS cnt,
       sum(amount) AS total
FROM orders
WHERE created_at > now() - interval '30 days';
-- now() 是 STABLE，但 PG 无增量刷新所以无关紧要
-- 每次 REFRESH MATERIALIZED VIEW 都是全量

-- Oracle FAST REFRESH 严格要求
CREATE MATERIALIZED VIEW daily_orders
REFRESH FAST ON COMMIT
AS SELECT date_trunc('day', created_at) AS day, ...;
-- 如果 SELECT 含非 DETERMINISTIC 函数（包括 SYSDATE）→ FAST REFRESH 失败
-- 必须用 COMPLETE REFRESH 或改写

-- 解决方案：把"非确定的截止时间"作为查询参数而非视图定义
CREATE MATERIALIZED VIEW all_orders
AS SELECT date_trunc('day', created_at) AS day, count(*), sum(amount)
   FROM orders;       -- 视图覆盖全表
-- 查询时再过滤
SELECT * FROM all_orders WHERE day > now() - interval '30 days';
```

## 各引擎的"自动推断" vs "用户声明"

### 用户声明派

PostgreSQL / Oracle / DB2 / MySQL / Trino / Snowflake / Vertica 等：用户必须在 DDL 中显式声明，引擎信任用户。

优势：明确、可预测、用户掌握控制权。
劣势：用户错标的代价高（如 IMMUTABLE 标错了实际 STABLE 的函数 → 索引值错误）。

### 自动推断派

SQL Server / BigQuery / DuckDB / ClickHouse / Materialize / Spanner：引擎扫描函数体，根据规则推断确定性。

优势：用户不会错标，引擎保证正确。
劣势：
- 推断规则复杂，用户不一定理解。
- 推断保守 → 部分实际可优化的函数被标为非确定。
- 推断的边界（什么算"非确定输入"）跨版本可能变化。

### 混合派

Oracle 11g+：引入了部分自动推断（`PRAGMA RESTRICT_REFERENCES` 不再必须），但 DETERMINISTIC 仍由用户声明。

### SQL Server 的特殊性

SQL Server 不允许用户声明 DETERMINISTIC，是为了避免用户错标导致索引视图、持久化计算列、索引等物理对象损坏。引擎掌握判定权 → 物理一致性由引擎保证。

## 设计争议与跨引擎差异

### 争议 1：DETERMINISTIC 是否允许有副作用

SQL:1999 标准未明确禁止副作用。各家解读：
- PostgreSQL：IMMUTABLE 函数应该无副作用，但不强制（用户可写副作用，但优化器可能消除调用次数）。
- Oracle：DETERMINISTIC 函数允许副作用，但可能被消除调用。
- DB2：用 `EXTERNAL ACTION` 显式区分有/无外部影响。
- MySQL：DETERMINISTIC 不限制副作用，用 SQL-data 访问等级正交描述。

最佳实践：DETERMINISTIC / IMMUTABLE 函数应该尽量无副作用，副作用函数标 VOLATILE / NOT DETERMINISTIC。

### 争议 2：collation/locale 是否影响 IMMUTABLE

PG 中 `lower(s)` 标为 IMMUTABLE，但实际上不同 locale 下 `lower('İ')` 结果不同（土耳其大写 I → i 而非 I）。

```sql
SELECT lower('İ' COLLATE "tr-TR-x-icu");   -- i
SELECT lower('İ' COLLATE "C");             -- İ
```

PG 的妥协：把 `lower(s)` 标 IMMUTABLE，但要求建索引时显式指定 COLLATE，避免索引 collation 变化导致键不一致。

### 争议 3：默认值

| 引擎 | 默认 |
|------|------|
| PostgreSQL | VOLATILE |
| Oracle | 非确定（无关键字）|
| SQL Server | 非确定（无 SCHEMABINDING）|
| MySQL | NOT DETERMINISTIC |
| DB2 | NOT DETERMINISTIC |
| Snowflake | VOLATILE |
| Spark/Hive UDF | true（确定性）|

多数关系数据库默认"保守"（非确定性）—— 用户主动声明才能启用优化。Spark/Hive 反向：默认确定性，用户主动声明才标为非确定。这反映出大数据栈 vs 关系数据库栈的不同设计哲学。

### 争议 4：用户能否覆盖内置函数的标记

```sql
-- PostgreSQL：可以 ALTER FUNCTION 修改用户函数的波动性
ALTER FUNCTION my_fn(int) IMMUTABLE;

-- 内置函数也可以？理论上可以但极度危险
ALTER FUNCTION pg_catalog.now() IMMUTABLE;   -- 不要这样做！
-- 索引、分区等会基于这个错误的标记建立 → 数据一致性破坏
```

多数引擎允许 ALTER 修改用户函数的标记，但内置函数被锁定或需要超级用户。

## 关键发现

1. **SQL:1999 二元模型不够用**：`DETERMINISTIC / NOT DETERMINISTIC` 把"会话内稳定"（如 `now()`）和"每行变化"（如 `random()`）混为一谈。PG 等引擎在标准之外引入 STABLE 中间级，但 Oracle / SQL Server / MySQL / DB2 等主流引擎仍用二元，只能在 IMMUTABLE 与 VOLATILE 间二选一。

2. **SCHEMABINDING 是 SQL Server 独特设计**：其他引擎只关心"函数是否确定"，SQL Server 还要求"函数引用的 schema 是否锁定"。这种"绑定语义"使 SCHEMABINDING 不仅是确定性标记，还是 schema 演进的限制器。

3. **PARALLEL 标志独立于波动性**：PG 9.6 引入的 PARALLEL SAFE / RESTRICTED / UNSAFE 与 IMMUTABLE / STABLE / VOLATILE 完全正交。一个 IMMUTABLE 函数可能 PARALLEL UNSAFE（访问线程全局状态），一个 VOLATILE 函数也可能 PARALLEL SAFE。

4. **MySQL DETERMINISTIC 与 binlog 强耦合**：MySQL 是唯一把 DETERMINISTIC 与复制语义直接绑定的主流引擎 —— 默认情况下，创建有副作用的函数会被 binlog 检查拒绝，必须明确声明或用 `log_bin_trust_function_creators` 绕过。这是 statement-based binlog 历史包袱留下的特殊设计。

5. **自动推断 vs 用户声明的取舍**：SQL Server / BigQuery / DuckDB / ClickHouse 选择自动推断，避免用户错标；PG / Oracle / MySQL / DB2 选择用户声明，给予用户优化控制权。SQL Server 的强制自动推断与索引视图、持久化计算列等强一致性要求紧密相关。

6. **默认值反映工程哲学**：PG/Snowflake 默认 VOLATILE（保守）；Spark/Hive 默认确定性（激进）—— 数据栈下大多函数本来就是纯计算，反向假设减少标记开销。MySQL 默认 NOT DETERMINISTIC + binlog 检查共同形成"必须显式承诺"的契约。

7. **CALLED ON NULL INPUT 是另一种确定性**：SQL:1999 的 NULL 调用控制（`RETURNS NULL ON NULL INPUT`）与 DETERMINISTIC 完全独立。前者控制 NULL 输入时是否调用函数体，后者控制相同输入是否相同输出。两者都是优化器需要的契约。

8. **物化视图增量刷新是确定性最严苛的应用**：SQL Server 索引视图同时要求 SCHEMABINDING + IsDeterministic + IsPrecise + 限制聚合 + 限制 JOIN。Oracle FAST REFRESH 拒绝任何非 DETERMINISTIC 函数。这反映"持久化视图状态可被增量更新"是非常强的不变量。

9. **Informix 反向命名 VARIANT 是历史遗留**：Informix 用 `VARIANT`（默认）= 非确定性，`NOT VARIANT` = 确定性。这种命名方式与多数引擎相反，反映 1990 年代不同厂商对"默认假设"的不同选择。

10. **流处理引擎的特殊性**：Flink 的 `isDeterministic()` 与状态恢复、回溯计算、exactly-once 语义紧密相关，在流处理场景下非确定性函数的代价远高于批处理。Materialize / RisingWave 等专为物化视图设计的流处理引擎更是把确定性推断作为核心机制。

## 与相关概念的对比

| 概念 | 范畴 | 关键问题 |
|------|------|---------|
| **确定性标记** | 用户契约 | 同输入是否同输出？ |
| **波动性 (Volatility)** | 优化器分类 | 缓存边界（行/语句/事务/永远）？ |
| **并行安全 (Parallel Safety)** | 执行环境 | 多 worker 是否安全？ |
| **CALLED ON NULL INPUT** | 短路语义 | NULL 是否调用函数体？ |
| **SCHEMABINDING** | Schema 绑定 | 引用的对象是否锁定？ |
| **EXTERNAL ACTION** | 副作用范围 | 是否影响 DB 之外的世界？ |
| **PERSISTED**（计算列）| 物理存储 | 计算结果是否物化？ |
| **FENCED / NOT FENCED** | 进程隔离 | UDF 在独立进程？ |
| **SQL-data 访问等级** | 语句行为 | 是否读/写 SQL 数据？ |

这些概念共同构成"函数到优化器的契约面"，缺一不可。

## 对引擎开发者的建议

1. **提供至少三级波动性**：二元模型迫使 `now()` 类函数被标为非确定 → 不能跨行 CSE。增加 1 个 STABLE 等级的实现成本换取常见时间函数的优化。
2. **PARALLEL 标志独立于波动性**：一个 IMMUTABLE 但访问线程全局状态的 C 函数应该能被标为 PARALLEL UNSAFE。
3. **自动推断 + 用户覆盖**：对内置函数自动推断（无需声明 `length()`），对用户函数允许声明（用户更了解语义）。SQL Server 不允许声明过于严格，PG 完全靠声明对内置函数繁琐。
4. **默认值选 VOLATILE / NOT DETERMINISTIC**：保守默认避免用户错标导致索引值不一致。让用户为优化付出"主动声明"代价，比错标造成数据损坏便宜。
5. **提供查询接口**：`pg_proc.provolatile` / `OBJECTPROPERTY(..., 'IsDeterministic')` / `system.functions` 等用于调试索引/物化视图问题。
6. **错误消息要具体**：明确说明哪个函数、当前标记级别、建议的 ALTER 命令，而非笼统的 "cannot create index"。
7. **文档化推断规则**：自动推断必须文档化具体规则（哪些内置函数标为非确定、SCHEMABINDING 的判定条件清单等）。
8. **跨版本稳定性**：确定性标记是 schema 的一部分，函数在版本 N 是 IMMUTABLE 升级到 STABLE 会破坏现有索引。
9. **与 collation/timezone 的交互**：文档化 `lower(s)`、`to_char(ts, fmt)` 等函数在不同 collation/timezone 下的确定性边界。
10. **测试矩阵**：覆盖显式声明 vs 默认值；索引/生成列/CHECK 对错标函数的拒绝；物化视图增量刷新；并行查询下 UNSAFE 函数串行化；跨事务 STABLE 函数可见性；IMMUTABLE 函数多余调用消除。

## 参考资料

- ISO/IEC 9075-4:1999, SQL/PSM, Section 11 (CREATE FUNCTION characteristics)
- PostgreSQL Docs: [Function Volatility Categories](https://www.postgresql.org/docs/current/xfunc-volatility.html)
- PostgreSQL Docs: [Parallel Safety](https://www.postgresql.org/docs/current/parallel-safety.html)
- Oracle Database SQL Reference: [CREATE FUNCTION - DETERMINISTIC](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/CREATE-FUNCTION.html)
- Oracle PL/SQL Language Reference: [PARALLEL_ENABLE Clause](https://docs.oracle.com/en/database/oracle/oracle-database/19/lnpls/PARALLEL_ENABLE-clause.html)
- Microsoft Docs: [Deterministic and Nondeterministic Functions](https://learn.microsoft.com/en-us/sql/relational-databases/user-defined-functions/deterministic-and-nondeterministic-functions)
- Microsoft Docs: [SCHEMABINDING in CREATE FUNCTION](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-function-transact-sql)
- MySQL Reference Manual: [CREATE FUNCTION (Stored)](https://dev.mysql.com/doc/refman/8.0/en/create-procedure.html)
- MySQL Reference Manual: [Stored Program Binary Logging](https://dev.mysql.com/doc/refman/8.0/en/stored-programs-logging.html)
- DB2 SQL Reference: [CREATE FUNCTION - DETERMINISTIC](https://www.ibm.com/docs/en/db2/11.5?topic=statements-create-function)
- SQLite Docs: [Application-Defined SQL Functions](https://sqlite.org/c3ref/create_function.html) (SQLITE_DETERMINISTIC)
- Snowflake Docs: [User-Defined Functions Overview](https://docs.snowflake.com/en/developer-guide/udf/udf-overview)
- BigQuery Docs: [User-Defined Functions](https://cloud.google.com/bigquery/docs/reference/standard-sql/user-defined-functions)
- Trino Docs: [SQL routines](https://trino.io/docs/current/routines.html)
- Spark Docs: [User-Defined Functions](https://spark.apache.org/docs/latest/sql-ref-functions-udf-scalar.html)
- Hive Wiki: [UDFType Annotation](https://cwiki.apache.org/confluence/display/Hive/HivePlugins)
- Flink Docs: [User-Defined Functions](https://nightlies.apache.org/flink/flink-docs-release-1.18/docs/dev/table/functions/udfs/)
- ClickHouse Docs: [system.functions table](https://clickhouse.com/docs/en/operations/system-tables/functions)
- CockroachDB Docs: [User-Defined Functions](https://www.cockroachlabs.com/docs/stable/user-defined-functions)
- Vertica Docs: [User-Defined Scalar Functions - Volatility](https://docs.vertica.com/24.2.x/en/extending/developing-udxs/scalar-functions/)
- Greenplum Docs: [Function Volatility Categories](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-query-topics-functions-operators.html)
- 函数波动性 - 本仓库 [function-volatility.md](function-volatility.md)
- 表达式索引 - 本仓库 [expression-indexes.md](expression-indexes.md)
