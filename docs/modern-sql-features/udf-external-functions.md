# 外部函数与 UDF 扩展 (External UDFs and Native Extensions)

当 SQL 表达力遇到瓶颈，当业务逻辑需要调用机器学习模型、加解密算法、专有协议解析、地理编码服务时——外部函数（External UDF）就是数据库延伸出的"原生触手"。它让数据库引擎能够装载 C/Rust 共享库、嵌入 JVM/Python/V8 解释器，甚至 fork 出独立进程来执行用户代码，是把"通用计算"塞进"声明式查询"最直接的桥梁。

> 本文聚焦"外部代码加载机制"——共享库、字节码、容器化运行时、远程函数调用——而不重复 PL/SQL、PL/pgSQL、T-SQL 等 SQL 方言函数的内容，那部分请参阅 [stored-procedures-udf.md](./stored-procedures-udf.md)。

## 为什么需要原生 UDF

纯 SQL 函数（CREATE FUNCTION ... LANGUAGE SQL）的优势是优化器友好、可内联展开，但有三大局限：

1. **表达能力受限**：无循环、无字符串处理库、无浮点数学库（除内置）、无第三方算法。
2. **性能瓶颈**：解释执行的 PL/* 脚本通常比原生代码慢 10~100 倍。
3. **生态隔离**：无法直接调用 OpenSSL、protobuf、TensorFlow、numpy 这类成熟生态。

外部函数通过加载本地共享库（C/C++/Rust）或嵌入解释器（Python/Java/JS/Lua）解决这些问题，让数据库能够：

- 用 SIMD/AVX 加速向量化计算
- 调用 GPU/AI 推理
- 复用现有 C/Java 库（jansson、Apache POI、scikit-learn）
- 实现自定义聚合（UDAF）、表函数（UDTF）、窗口函数

代价是**安全性**（崩溃可能导致整个数据库进程退出）、**升级耦合**（ABI 兼容）、**可移植性**（与底层操作系统/CPU 绑定）。所有引擎在表达力、性能、隔离三角中做不同取舍，这正是本文要梳理的图景。

## 没有 SQL 标准

SQL/MED（ISO/IEC 9075-9）规定了"外部数据"（Foreign Data Wrapper）的接入方式，最接近"外部函数"的概念是 **CREATE FUNCTION ... EXTERNAL NAME**。然而：

- 标准只定义了"声明 EXTERNAL 函数"的语法骨架，没有规定运行时（C ABI、JNI、进程模型等）。
- 大多数引擎自行扩展 `LANGUAGE C`、`LANGUAGE JAVA`、`LANGUAGE PYTHON`、`LANGUAGE JAVASCRIPT` 等。
- WASM 是 2023 年后才出现的新趋势，标准尚未涉及。

因此"外部函数"是各引擎自定义机制最强的领域之一，差异比 SQL 函数本身大得多。

## 支持矩阵

### C / C++ 共享库扩展

通过 `dlopen` / `LoadLibraryEx` 加载 `.so`/`.dll`/`.dylib`，调用导出的符号。这是性能最高、安全风险也最大的方式。

| 引擎 | 加载方式 | API 稳定性 | 在线加载 | 说明 |
|------|---------|-----------|---------|------|
| PostgreSQL | `CREATE FUNCTION ... LANGUAGE C` + `LOAD '<so>'` | 高（PG_MODULE_MAGIC） | 是 | 经典扩展系统 |
| MySQL | `CREATE FUNCTION ... SONAME` (UDF API) | 中 | 是 | plugin 目录 |
| MariaDB | `CREATE FUNCTION ... SONAME` | 中 | 是 | 与 MySQL 兼容 |
| SQLite | `sqlite3_load_extension()` | 高 | 是 | 嵌入式扩展 |
| Oracle | EXTERNAL PROCEDURE via `extproc` | 高 | 是 | 通过 listener 进程隔离 |
| SQL Server | -- | -- | -- | 不开放 C 扩展，使用 CLR |
| DB2 | `CREATE FUNCTION ... LANGUAGE C` | 高 | 是 | FENCED/UNFENCED 模式 |
| Snowflake | -- | -- | -- | 托管服务，禁止本地库 |
| BigQuery | -- | -- | -- | 托管服务，仅 JS/Remote |
| Redshift | -- | -- | -- | 仅 Python/Lambda UDF |
| DuckDB | C++ Extension API（`.duckdb_extension`） | 中（迭代中） | 是 | 签名扩展 |
| ClickHouse | C++ plugin (build-time) + executable UDF | 中 | 重启 | 进程外 UDF 更常用 |
| Trino | Plugin SPI（Java，非 C） | 高 | 重启 | 用 JVM 实现 |
| Presto | Plugin SPI（Java） | 高 | 重启 | 同 Trino |
| Spark SQL | -- | -- | -- | 通过 JVM 而非 C |
| Hive | -- | -- | -- | 同 Spark，JVM only |
| Flink SQL | -- | -- | -- | JVM only |
| Databricks | -- | -- | -- | 托管，禁止本地库 |
| Teradata | C/C++ UDF (`CREATE FUNCTION ... LANGUAGE C`) | 高 | 重启可选 | PROTECTED/UNPROTECTED |
| Greenplum | 继承 PostgreSQL C API | 高 | 是 | 集群分发 .so |
| CockroachDB | -- | -- | -- | 仅 SQL/PLpgSQL |
| TiDB | -- | -- | -- | 仅 SQL UDF (实验) |
| OceanBase | -- | -- | -- | 仅 PL/SQL |
| YugabyteDB | 继承 PostgreSQL（部分） | 中 | 是 | 节点本地安装 |
| SingleStore | C 共享库 + Wasm | 高 | 是 | Wasm 优先 |
| Vertica | C++ UDx API | 高 | 是 | FENCED/UNFENCED |
| Impala | `CREATE FUNCTION ... LOCATION '*.so'` | 中 | 是 | HDFS 分发 |
| StarRocks | -- | -- | -- | Java/Python 优先 |
| Doris | -- | -- | -- | Java/Python 优先 |
| MonetDB | C UDF via MAL | 中 | 是 | 直接调用 BAT |
| CrateDB | -- | -- | -- | 仅 JS UDF |
| TimescaleDB | 继承 PostgreSQL | 高 | 是 | -- |
| QuestDB | Java SPI | 中 | 重启 | -- |
| Exasol | C++ Script | 中 | 是 | UDF Script Container |
| SAP HANA | AFL（Application Function Library） C++ | 中 | 是 | 需 HANA studio 部署 |
| Informix | C UDR（User Defined Routine） | 高 | 是 | 经典 IDS DataBlade |
| Firebird | UDF (legacy) / UDR (modern) | 中 | 是 | UDF 已弃用，UDR 替代 |
| H2 | Java only | -- | -- | -- |
| HSQLDB | Java only | -- | -- | -- |
| Derby | Java only | -- | -- | -- |
| Amazon Athena | -- | -- | -- | 仅 Lambda UDF |
| Azure Synapse | -- | -- | -- | 仅 .NET/SQL |
| Google Spanner | -- | -- | -- | 仅 SQL UDF |
| Materialize | -- | -- | -- | 仅 SQL UDF |
| RisingWave | -- | -- | -- | Python/Java 远程 |
| InfluxDB (SQL) | -- | -- | -- | 不支持 |
| DatabendDB | -- | -- | -- | Wasm/Python 优先 |
| Yellowbrick | C/C++ UDx (继承 Vertica 血缘) | 中 | 是 | -- |
| Firebolt | -- | -- | -- | 仅 SQL UDF |

> 统计：约 18 个引擎支持原生 C/C++ 加载，绝大多数云托管服务出于安全考虑禁止此机制。

### Java / JVM UDF

| 引擎 | 注册方式 | 运行环境 | 类型 | 说明 |
|------|---------|---------|------|------|
| PostgreSQL | PL/Java 扩展 | 进程内 JVM | UDF/UDAF | 第三方扩展 |
| Oracle | `CREATE JAVA SOURCE` / loadjava | 内嵌 OJVM | UDF/SP | 原生集成 |
| SQL Server | -- | -- | -- | 用 CLR 而非 JVM |
| DB2 | `CREATE FUNCTION ... LANGUAGE JAVA` | JVM (FENCED) | UDF/UDAF | -- |
| Snowflake | `CREATE FUNCTION ... LANGUAGE JAVA` | Snowpark 容器 | UDF/UDTF | 2021 GA |
| BigQuery | -- | -- | -- | 不支持 Java |
| Redshift | -- | -- | -- | 已废弃 Lambda Java |
| DuckDB | -- | -- | -- | -- |
| ClickHouse | -- | -- | -- | -- |
| Trino | Plugin SPI | 进程内 JVM | UDF/UDAF/连接器 | 主要扩展机制 |
| Presto | Plugin SPI | 进程内 JVM | -- | 同 Trino |
| Spark SQL | `spark.udf.register(name, func)` | 进程内 JVM | UDF/UDAF | Scala/Java |
| Hive | `CREATE FUNCTION ... AS 'class' USING JAR` | 进程内 JVM | UDF/UDAF/UDTF | 经典 GenericUDF |
| Flink SQL | `CREATE FUNCTION ... AS 'class' LANGUAGE JAVA` | TaskManager JVM | UDF/UDAF/UDTF | -- |
| Databricks | 同 Spark | JVM | -- | -- |
| Teradata | `CREATE FUNCTION ... LANGUAGE JAVA` | 内嵌 JVM | UDF | -- |
| Greenplum | PL/Java | 进程外 JVM | UDF | -- |
| CockroachDB | -- | -- | -- | -- |
| TiDB | -- | -- | -- | -- |
| OceanBase | -- | -- | -- | -- |
| YugabyteDB | -- | -- | -- | -- |
| SingleStore | -- | -- | -- | -- |
| Vertica | Java UDx | 容器化 JVM | UDF/UDAF/UDTF | -- |
| Impala | `LANGUAGE JAVA` (Hive 兼容) | JVM | UDF | -- |
| StarRocks | `CREATE FUNCTION ... USING jar` | JVM | UDF | 2.4+ |
| Doris | `CREATE FUNCTION ... USING jar` | JVM | UDF | 1.2+ |
| MonetDB | -- | -- | -- | -- |
| CrateDB | -- | -- | -- | -- |
| TimescaleDB | 继承 PG (PL/Java) | -- | -- | -- |
| QuestDB | Java native | JVM | UDF | -- |
| Exasol | Java Script | 容器 | UDF | -- |
| SAP HANA | -- | -- | -- | -- |
| Informix | `LANGUAGE JAVA` | 内嵌 JVM | UDF/UDR | -- |
| Firebird | -- | -- | -- | -- |
| H2 | `CREATE ALIAS ... FOR "ClassName.method"` | 内嵌 JVM | UDF | 唯一原生方式 |
| HSQLDB | `CREATE FUNCTION ... LANGUAGE JAVA` | JVM | UDF | -- |
| Derby | `CREATE FUNCTION ... LANGUAGE JAVA PARAMETER STYLE JAVA` | JVM | UDF | -- |
| Amazon Athena | -- | -- | -- | -- |
| Azure Synapse | -- | -- | -- | -- |
| Google Spanner | -- | -- | -- | -- |
| Materialize | -- | -- | -- | -- |
| RisingWave | Java UDF (远程) | 进程外 JVM | UDF/UDAF | -- |
| InfluxDB | -- | -- | -- | -- |
| DatabendDB | -- | -- | -- | -- |
| Yellowbrick | -- | -- | -- | -- |
| Firebolt | -- | -- | -- | -- |

> 统计：约 24 个引擎支持 Java/JVM UDF，是所有外部语言中覆盖面最广的——这与 Hadoop 生态的 JVM 主导地位直接相关。

### Python UDF

按运行模式分两类：**进程内**（Python 解释器嵌入数据库进程，性能高但 GIL 受限）与**进程外**（独立 Python 进程通过 IPC/Arrow 通信，隔离性好）。

| 引擎 | 模式 | Arrow 优化 | 版本 | 说明 |
|------|------|-----------|------|------|
| PostgreSQL | PL/Python (进程内) | -- | 早期 | plpython3u trusted/untrusted |
| Oracle | -- | -- | -- | 不支持原生 Python |
| SQL Server | sp_execute_external_script (进程外) | -- | 2017+ | Machine Learning Services |
| DB2 | -- | -- | -- | 仅有 Python 客户端 |
| Snowflake | Snowpark Python (沙箱进程) | 是 (向量化) | 2022 GA | 单独的 Python 运行时 |
| BigQuery | -- | -- | -- | 仅 Remote Function 可调 Python |
| Redshift | UDF (进程内 Python 2.7) | -- | 早期；2023 弃用 | 仅老集群 |
| DuckDB | DuckDB Python API (进程内 zero-copy) | 是 (Arrow) | 0.5+ | 通过 Python 包注册 |
| ClickHouse | executable UDF (进程外 fork) | TSV/JSON | 22.x+ | 不限于 Python |
| Trino | -- | -- | -- | -- |
| Presto | -- | -- | -- | -- |
| Spark SQL | PySpark UDF + Pandas UDF (进程外) | 是 (Arrow，3.0+) | -- | Worker 启动 Python |
| Hive | TRANSFORM via stdin/stdout (进程外) | -- | 早期 | streaming 模式 |
| Flink SQL | Python UDF (进程外，PyFlink) | 是 (Arrow) | 1.10+ | -- |
| Databricks | PySpark + Python UDF (进程外) | 是 (Arrow) | -- | 同 Spark |
| Teradata | Script Table Operator (进程外) | -- | 15+ | Stream 模式 |
| Greenplum | PL/Python (进程内) | -- | -- | 继承 PG |
| CockroachDB | -- | -- | -- | -- |
| TiDB | -- | -- | -- | -- |
| OceanBase | -- | -- | -- | -- |
| YugabyteDB | PL/Python (有限) | -- | -- | -- |
| SingleStore | -- | -- | -- | Wasm 优先 |
| Vertica | Python UDx (进程外/Fenced) | -- | -- | -- |
| Impala | -- | -- | -- | -- |
| StarRocks | Python UDF (进程外) | 是 (Arrow) | 3.2+ | -- |
| Doris | Python UDF (进程外) | -- | 2.1+ | -- |
| MonetDB | PyAPI (进程内) | 是 (zero-copy ndarray) | -- | 学术里程碑 |
| CrateDB | -- | -- | -- | -- |
| TimescaleDB | PL/Python | -- | -- | -- |
| QuestDB | -- | -- | -- | -- |
| Exasol | Python Script (容器) | -- | -- | -- |
| SAP HANA | -- | -- | -- | -- |
| Informix | -- | -- | -- | -- |
| Firebird | -- | -- | -- | -- |
| H2 | -- | -- | -- | -- |
| HSQLDB | -- | -- | -- | -- |
| Derby | -- | -- | -- | -- |
| Amazon Athena | Lambda UDF (Python via Lambda) | -- | GA | -- |
| Azure Synapse | -- | -- | -- | -- |
| Google Spanner | -- | -- | -- | -- |
| Materialize | -- | -- | -- | -- |
| RisingWave | Python UDF (gRPC 远程) | 是 (Arrow Flight) | 0.18+ | -- |
| InfluxDB (SQL) | -- | -- | -- | -- |
| DatabendDB | Python UDF (Wasm via pyo3) | 是 (Arrow) | 1.2+ | -- |
| Yellowbrick | -- | -- | -- | -- |
| Firebolt | -- | -- | -- | -- |

### JavaScript UDF

| 引擎 | 引擎实现 | 模式 | 版本 | 说明 |
|------|---------|------|------|------|
| PostgreSQL | PL/V8 | 进程内 V8 | 第三方 | UDF/UDAF |
| Oracle | MLE (GraalVM JS) | 进程内 | 21c+ | 同时支持 Python |
| SQL Server | -- | -- | -- | -- |
| DB2 | -- | -- | -- | -- |
| Snowflake | 内嵌 (V8 fork) | 沙箱 | GA | 严格沙箱，无 IO |
| BigQuery | V8 | 沙箱 | 自始即有 | 是 BQ 早期主推 UDF 形态 |
| Redshift | -- | -- | -- | -- |
| DuckDB | -- | -- | -- | 通过 Wasm 间接 |
| ClickHouse | -- | -- | -- | -- |
| Trino | -- | -- | -- | -- |
| Spark SQL | -- | -- | -- | -- |
| Flink SQL | -- | -- | -- | -- |
| CockroachDB | -- | -- | -- | -- |
| MariaDB | -- | -- | -- | -- |
| Vertica | -- | -- | -- | -- |
| MonetDB | -- | -- | -- | -- |
| CrateDB | Nashorn / GraalVM | JVM 内 | 老版本；4.2 后弃用 | 不安全被移除 |
| Exasol | Lua/JS Script | 容器 | -- | 多语言脚本 |
| YugabyteDB | -- | -- | -- | -- |
| Materialize | -- | -- | -- | -- |
| RisingWave | -- | -- | -- | -- |
| DatabendDB | JS (QuickJS) | Wasm | 1.2+ | -- |
| ScyllaDB / SingleStore | Lua / Wasm | -- | -- | 不主推 JS |

> 三大托管引擎（Snowflake、BigQuery、Databricks）的 JavaScript 支持差异显著，详见后文专题对比。

### Rust UDF

| 引擎 | 框架 | 模式 | 说明 |
|------|------|------|------|
| PostgreSQL | pgrx (前称 pgx) | 编译为 .so | 由 PG_MODULE_MAGIC 兼容 |
| DuckDB | extension-template (Rust bindings) | C++ FFI | 实验中 |
| ClickHouse | ext-rs (社区) | C++ FFI | 实验 |
| Materialize | 内置使用 Rust，但不开放 UDF | -- | -- |
| RisingWave | 内置使用 Rust，不开放 UDF | -- | -- |
| InfluxDB IOx | 内置 Rust，不开放 | -- | -- |
| DatabendDB | Wasm (Rust → Wasm) | Wasm runtime | 主推路径 |
| SingleStore | Wasm (Rust → Wasm) | Wasm runtime | 主推路径 |
| Snowflake | -- | -- | -- |
| BigQuery | -- | -- | -- |

> Rust UDF 的主流路径是 **Rust → WASM → 数据库 Wasm runtime**，而非直接编译 .so，以避免 ABI 兼容问题。

### WASM UDF（新兴趋势）

WASM 提供"沙箱化、跨平台、近原生"的运行时，是 2023 年后 OLAP/Cloud 引擎的明星方案。

| 引擎 | Wasm runtime | 状态 | 版本 | 说明 |
|------|------------|------|------|------|
| PostgreSQL | 第三方扩展 plrust / wasm_executor | 实验 | -- | -- |
| SingleStore | Wasmer | GA | 8.1+ | 首个商用 Wasm UDF DB |
| DuckDB | DuckDB-Wasm 运行 DuckDB 自身；UDF Wasm 实验 | 部分 | -- | DuckDB-Wasm 是浏览器侧 |
| ClickHouse | 内置 (24.4+) | Beta | 24.4+ | 首个引入 Wasm UDF 的 OLAP |
| DatabendDB | Wasmtime | GA | 1.2+ | Python/Rust/JS 都跑在 Wasm |
| Snowflake | -- | -- | -- | 暂无公开 |
| BigQuery | -- | -- | -- | -- |
| Materialize | -- | -- | -- | 已讨论中 |
| RisingWave | -- | -- | -- | -- |
| InfluxDB IOx | -- | -- | -- | -- |
| ScyllaDB | Wasmtime | GA | 5.x+ | 用户定义函数 |

### 纯 SQL UDF（可内联展开）

| 引擎 | 关键字 | 内联展开 | 说明 |
|------|--------|---------|------|
| PostgreSQL | `CREATE FUNCTION ... LANGUAGE SQL` | 是（标量） | 经典内联 |
| Oracle | `CREATE FUNCTION ... DETERMINISTIC` | WITH 子句中可内联 | -- |
| SQL Server | `CREATE FUNCTION` (inline TVF) | 是（iTVF） | 标量函数不内联（性能差） |
| DB2 | `CREATE FUNCTION ... LANGUAGE SQL` | 是 | -- |
| Snowflake | `CREATE FUNCTION ... LANGUAGE SQL` | 是 | -- |
| BigQuery | `CREATE FUNCTION ... AS (expr)` | 是 | 必须是单一表达式 |
| Redshift | `CREATE FUNCTION ... LANGUAGE SQL` | 是 | -- |
| DuckDB | `CREATE MACRO` / `CREATE FUNCTION` | 是（macro） | macro 强制内联 |
| ClickHouse | `CREATE FUNCTION` | 是 | 仅 lambda 表达式 |
| Trino | `CREATE FUNCTION` (内联 SQL) | 是 | 423+ |
| Spark SQL | `CREATE FUNCTION` (SQL 函数) | 是 | 3.5+ |
| Materialize | `CREATE FUNCTION` (LANGUAGE SQL) | 是 | 唯一 UDF 形式 |
| Google Spanner | `CREATE FUNCTION` | 是 | 唯一 UDF 形式 |
| Firebolt | `CREATE FUNCTION` | 是 | 唯一 UDF 形式 |
| CockroachDB | `CREATE FUNCTION` (SQL/PLpgSQL) | 是 | 22.2+ |
| YugabyteDB | 继承 PG | 是 | -- |
| TiDB | -- | -- | 不支持 |
| OceanBase | PL/SQL 函数 | 否 | -- |

> 纯 SQL UDF 是最安全、可被优化器完全展开的形式，许多托管数据库（Materialize、Firebolt、Spanner）只支持这一种。

### 外部表函数 / Remote Function

把 UDF 放在数据库进程外的独立服务中，通过 RPC（gRPC/HTTP/Lambda）调用：

| 引擎 | 机制 | 协议 | 版本 |
|------|------|------|------|
| BigQuery | Remote Functions | HTTPS → Cloud Functions / Cloud Run | 2022 GA |
| Snowflake | External Functions | HTTPS → API Gateway | 2020 GA |
| Redshift | Lambda UDF | AWS Lambda invoke | 2018 GA |
| Athena | Lambda UDF | AWS Lambda invoke | 2020 GA |
| ClickHouse | Executable UDF | fork + stdin/stdout | 22.x+ |
| Spark SQL | -- | -- | 通过 PySpark Worker 间接 |
| Flink SQL | -- | -- | -- |
| RisingWave | UDF Server | gRPC + Arrow Flight | 0.18+ |
| Doris | Remote UDF (RPC) | gRPC | 1.2+ |
| StarRocks | Remote UDF | gRPC | 3.0+ |
| DatabendDB | UDF Server | HTTP/gRPC | 1.2+ |
| Trino | -- | -- | 通过插件加载 |
| Vertica | -- | -- | -- |

### 沙箱与信任级别

| 引擎 | UNTRUSTED/FENCED | TRUSTED/UNFENCED | 默认 |
|------|------------------|-------------------|------|
| PostgreSQL | plpython3u, plperlu, C | plpgsql, plperl, sql | TRUSTED 默认 |
| DB2 | FENCED（独立进程） | UNFENCED（数据库进程内） | FENCED |
| Oracle | extproc 隔离 | inline | extproc |
| SQL Server CLR | EXTERNAL_ACCESS / UNSAFE | SAFE | SAFE |
| Vertica | FENCED 容器 | UNFENCED | FENCED |
| Snowflake | Snowpark 容器隔离 | -- | 默认隔离 |
| BigQuery | 完全沙箱 (V8) | -- | 沙箱 |
| ClickHouse executable | 子进程（崩溃可恢复） | -- | 默认 |
| WASM 引擎（任意） | 内置沙箱 | -- | 沙箱 |

### GPU UDF

| 引擎 | 机制 | 说明 |
|------|------|------|
| HEAVY.AI (OmniSci) | LLVM JIT 到 NVPTX | 标量 UDF/UDAF |
| BlazingSQL (停更) | Numba CUDA | -- |
| RAPIDS cuDF | Python UDF JIT 到 CUDA | -- |
| Spark RAPIDS | Pandas UDF GPU 路径 | NVIDIA 插件 |
| Snowpark for ML | Container Services (含 GPU 容器) | 间接 |
| BigQuery ML INFERENCE | -- | 内置模型 |

绝大多数主流 OLTP/OLAP 引擎不直接支持 GPU UDF，而是通过 Python/容器侧间接调用。

## 重点引擎深入

### PostgreSQL：UDF 生态的金标准

PostgreSQL 的可扩展性是其几十年积累下来的核心竞争力。它支持：

1. **C 扩展**：通过 `PG_MODULE_MAGIC` 宏标记 ABI 版本，加载共享库注册函数。

```c
#include "postgres.h"
#include "fmgr.h"

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(my_add);
Datum my_add(PG_FUNCTION_ARGS) {
    int32 a = PG_GETARG_INT32(0);
    int32 b = PG_GETARG_INT32(1);
    PG_RETURN_INT32(a + b);
}
```

```sql
CREATE FUNCTION my_add(int, int) RETURNS int
AS '$libdir/myext', 'my_add'
LANGUAGE C STRICT;
```

2. **PL/Python (plpython3u)**：进程内嵌入 Python 解释器。

```sql
CREATE FUNCTION py_word_count(t text) RETURNS int
AS $$ return len(t.split()) $$
LANGUAGE plpython3u;
```

3. **PL/Perl, PL/Tcl, PL/V8 (JavaScript), PL/R, PL/Java, pgrx (Rust)**：第三方扩展提供。

4. **pgrx（Rust）**：现代 Rust 框架，编译产物即标准 PG 扩展，是过去三年增长最快的扩展形态。

5. **WASM**：实验性 plrust / wasm_executor 扩展。

PostgreSQL 的 ABI 在大版本之间稳定，C 扩展跨小版本通常无需重编译，是可移植性最好的本地 UDF 系统。

### Oracle：Java + extproc + MLE 三栈并行

Oracle 的外部函数有三条独立路线：

1. **EXTERNAL PROCEDURE（C）**：通过 `extproc` 监听器代理调用，OS 进程隔离。

```sql
CREATE LIBRARY my_lib AS '/u01/app/lib/myadd.so';
CREATE FUNCTION my_add(a NUMBER, b NUMBER) RETURN NUMBER
AS LANGUAGE C
LIBRARY my_lib
NAME "my_add"
PARAMETERS (a OCINUMBER, b OCINUMBER, RETURN OCINUMBER);
```

2. **Java 存储过程**：内嵌 OJVM（Oracle JVM），通过 `loadjava` 上传 JAR。

3. **MLE (Multilingual Engine, 21c+)**：基于 GraalVM，支持 JavaScript 和 Python。

```sql
CREATE MLE LANGUAGE javascript;
CREATE FUNCTION js_upper(s VARCHAR2) RETURN VARCHAR2 AS
MLE LANGUAGE javascript $$ return s.toUpperCase(); $$;
```

MLE 是 Oracle 应对"多语言 UDF"潮流的现代答卷，但目前生态尚未普及。

### SQL Server：CLR 整合，但已不再推荐

SQL Server 通过 SQLCLR 让 .NET（C#/F#/VB.NET）函数注册为 T-SQL UDF：

```sql
CREATE ASSEMBLY MyAsm FROM 'C:\bin\MyAsm.dll' WITH PERMISSION_SET = SAFE;
CREATE FUNCTION dbo.RegexMatch(@pattern nvarchar(400), @input nvarchar(max))
RETURNS bit AS EXTERNAL NAME MyAsm.[MyNs.RegexUtils].Match;
```

权限分三级：`SAFE`（仅托管代码）、`EXTERNAL_ACCESS`（可访问 OS 资源）、`UNSAFE`（可调用非托管 P/Invoke）。

自 SQL Server 2017 起，CLR 默认禁用并需要 `clr strict security` 设置严格签名。**微软已不再积极推动 CLR**，新功能优先放到 SQL Server Machine Learning Services（外部 Python/R）和 Azure SQL 的 JavaScript UDF 预览。

### DB2：FENCED / UNFENCED 双模型典范

DB2 是首批形式化"沙箱级别"的商用数据库之一：

```sql
CREATE FUNCTION my_add(int, int) RETURNS int
EXTERNAL NAME 'mylib!my_add'
LANGUAGE C
PARAMETER STYLE SQL
NOT FENCED
DETERMINISTIC
NO SQL;
```

`NOT FENCED` 在数据库进程内运行（最快），`FENCED` 在专用 `db2fmp` 进程内运行（崩溃不影响主进程）。Java UDF 永远是 FENCED。

### Snowflake：Java/Python/Scala/JavaScript 全栈

Snowflake UDF 演进里程碑：

- 2017：JavaScript UDF（V8 沙箱）
- 2021：Java UDF / Java UDTF（Snowpark）
- 2022：Python UDF（Snowpark Python）
- 2023：Scala UDF
- 2024：Snowflake Container Services（容器 UDF/SP）

```sql
CREATE FUNCTION py_normalize(s STRING)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
HANDLER = 'normalize'
PACKAGES = ('numpy', 'unidecode')
AS $$
from unidecode import unidecode
def normalize(s):
    return unidecode(s).lower()
$$;
```

Snowflake 是 Conda 风格的"包白名单"模式：只能用预审核的 Anaconda 包（约 5000 个），无法 pip 安装任意库。这是它在易用性与安全性之间的权衡。

### BigQuery：JS UDF + Remote Functions

BigQuery 自始即支持 JavaScript UDF（进程内 V8 沙箱）：

```sql
CREATE TEMP FUNCTION js_levenshtein(a STRING, b STRING)
RETURNS INT64
LANGUAGE js AS r"""
  // 经典 Levenshtein 实现
  if (a.length == 0) return b.length;
  if (b.length == 0) return a.length;
  // ...
""";
```

JS UDF 严格沙箱：无网络、无文件、无系统调用，且单次调用堆内存有限制。

2022 年推出的 **Remote Functions** 通过 HTTPS 调用 Cloud Functions / Cloud Run：

```sql
CREATE FUNCTION my_dataset.classify(text STRING) RETURNS STRING
REMOTE WITH CONNECTION `us.my_conn`
OPTIONS (endpoint = 'https://my-cf.cloudfunctions.net/classify');
```

Remote Functions 解锁了"用 Python 调任意 ML 模型"的能力，但每次调用有 ~50ms 网络延迟，吞吐瓶颈在 Cloud Functions 并发上。

### DuckDB：嵌入式扩展模型

DuckDB 的扩展系统针对嵌入式场景设计：

1. **C++ Extension**：编译为 `.duckdb_extension`，由 DuckDB 二进制加载。官方扩展包括 `httpfs`、`postgres_scanner`、`spatial`、`json`、`parquet` 等。

```sql
INSTALL spatial;
LOAD spatial;
SELECT ST_Distance(ST_Point(1, 1), ST_Point(2, 2));
```

2. **Python UDF（DuckDB Python API）**：在嵌入式 Python 进程中注册函数：

```python
import duckdb
con = duckdb.connect()
con.create_function("py_upper", lambda s: s.upper(), ['VARCHAR'], 'VARCHAR')
con.execute("SELECT py_upper('hello')").fetchall()
```

由于 DuckDB 与 Python 在同进程，Arrow 数据可零拷贝传递。

3. **DuckDB-Wasm**：把 DuckDB 自身编译为 Wasm，运行在浏览器中，是其独有亮点（注意：这指的是 DuckDB 本身跑在 Wasm 上，UDF 的 Wasm 加载机制仍在实验）。

### ClickHouse：进程外可执行 UDF

ClickHouse 的**executable UDF** 是非常独特的设计——通过 fork/exec 启动子进程，将批量数据通过 stdin 推入，从 stdout 读取结果：

```xml
<!-- /etc/clickhouse-server/user_defined_functions.xml -->
<function>
  <type>executable</type>
  <name>py_upper</name>
  <return_type>String</return_type>
  <argument><type>String</type></argument>
  <format>TabSeparated</format>
  <command>python3 /var/lib/ch/upper.py</command>
</function>
```

```sql
SELECT py_upper(name) FROM users;
```

特点：

- **批处理**：每次调用传入整批数据，摊薄进程启动成本
- **多种格式**：TabSeparated、JSONEachRow、Native、Parquet
- **任意语言**：Python、Bash、Go、二进制都可
- **进程崩溃不影响 ClickHouse**：自然隔离

24.4 起 ClickHouse 还引入了 **Wasm UDF**（实验阶段），让用户用 Rust 编译 Wasm 模块加载，规避了 fork/exec 的开销。

### Spark SQL / Databricks：Pandas UDF + Arrow 加速

Spark Python UDF 早期是逐行调用（每行一次序列化往返），性能极差。Spark 2.3 引入 **Pandas UDF**，3.0 全面用 Apache Arrow 优化：

```python
from pyspark.sql.functions import pandas_udf
import pandas as pd

@pandas_udf("double")
def fahrenheit_to_celsius(temp: pd.Series) -> pd.Series:
    return (temp - 32) * 5 / 9

df.select(fahrenheit_to_celsius("temp_f")).show()
```

Arrow 避免了 Pickle 序列化，吞吐提升 3~100 倍。Databricks 进一步在 Photon 引擎中支持向量化的 Python UDF 路径。Scala/Java UDF 仍是性能最优选项（同 JVM、无序列化）。

### Vertica：UDx 的工业级范式

Vertica 的 **UDx (User Defined Extensions)** 是一套完整的 C++/Java/Python/R 框架，覆盖：

- ScalarFunction
- AggregateFunction
- AnalyticFunction（窗口）
- TransformFunction（表函数）
- LoadSource / LoadFilter / LoadParser（自定义加载）

```cpp
class Add2Ints : public ScalarFunction {
  virtual void processBlock(ServerInterface &srv, BlockReader &arg_reader, BlockWriter &res_writer) {
    do {
      vint a = arg_reader.getIntRef(0);
      vint b = arg_reader.getIntRef(1);
      res_writer.setInt(a + b);
      res_writer.next();
    } while (arg_reader.next());
  }
};
```

Vertica 强调**批 API**，避免逐行调用开销。Yellowbrick 派生自 Vertica 血缘，UDx API 高度相似。

### Teradata：C / Java / R / Script Table Operator

Teradata 是 MPP 数据仓库 UDF 的早期实践者：

- **C/C++ UDF**：`PROTECTED MODE`（隔离进程）/ `UNPROTECTED MODE`
- **Java UDF**：内嵌 JVM，需要 Java External Stored Procedures 套件
- **R / Script Table Operator**：通过子进程执行任意脚本（Python、R），按表函数调用

Teradata 对 PROTECTED MODE 的设计早于 DB2 的 FENCED，是商用 MPP 中 UDF 隔离模型的先驱之一。

## JavaScript UDF：三家云仓的对比

| 维度 | Snowflake | BigQuery | Databricks |
|------|-----------|----------|-----------|
| 引擎 | V8 fork | V8 | -- (无 JS UDF) |
| 引入年代 | 2017 | 2014 (自始即有) | -- |
| 沙箱 | 严格（无 IO/网络） | 严格（无 IO/网络） | -- |
| 内存上限 | 文档 ~100MB | ~256MB（按 slot） | -- |
| 第三方库 | 不支持 | 不支持（仅 ES2015+ 内置） | -- |
| 数据类型映射 | NUMBER ↔ Number（精度截断） | INT64 ↔ Number（53 位精度警告） | -- |
| TVF 支持 | 是（JavaScript UDTF） | 否 | -- |
| 推荐场景 | 轻量字符串/数学 | 同上 | (用 Python/Scala) |

> 关键陷阱：JavaScript Number 是 IEEE 754 double（53 位尾数），无法精确表示 64 位整数。Snowflake 和 BigQuery 都建议大整数以字符串传入再转换。

```sql
-- Snowflake JS UDF
CREATE FUNCTION js_camel(s STRING) RETURNS STRING
LANGUAGE JAVASCRIPT AS $$
  return S.replace(/_([a-z])/g, function (m, p) { return p.toUpperCase(); });
$$;

-- BigQuery JS UDF
CREATE TEMP FUNCTION bq_camel(s STRING) RETURNS STRING
LANGUAGE js AS r"""
  return s.replace(/_([a-z])/g, (m, p) => p.toUpperCase());
""";
```

注意 Snowflake 中 JS 的入参变量名是**全大写**（与 SQL 列名大小写规则对齐），BigQuery 则保持小写。

## WASM UDF 新趋势

WASM（WebAssembly）从浏览器走向服务器，正成为数据库 UDF 的新基础设施。它的吸引力在于同时满足三个传统上互相冲突的要求：

| 要求 | 传统 C 扩展 | JVM/Python | WASM |
|------|------------|-----------|------|
| 接近原生性能 | 是 | 否 | 是（约 80~95%） |
| 强沙箱（崩溃可恢复，无逃逸） | 否 | 部分 | 是 |
| 跨平台分发 | 否（每架构一份） | 是 | 是 |
| 多语言（Rust/C++/Go/AS）| 否 | 否 | 是 |
| 启动延迟 | 极低 | 高（JVM）/ 中（Py） | 极低 |

代表性实现：

- **SingleStore (8.1)**：第一个商用 Wasm UDF 数据库，使用 Wasmer 运行时，主推 Rust UDF。
- **ClickHouse 24.4**：实验性 Wasm UDF，跑在 Wasmtime。
- **DatabendDB**：UDF 的"事实标准"形式即 Wasm，Python 代码通过 PyO3 编译为 Wasm。
- **ScyllaDB 5.x**：Wasmtime 实现的标量函数。
- **PostgreSQL plrust + wasm_executor**：第三方实验。

```sql
-- SingleStore: Rust → Wasm UDF
CREATE FUNCTION power_mod(base BIGINT, exp BIGINT, m BIGINT) RETURNS BIGINT
AS WASM FROM 'power_mod.wasm' WITH (HANDLER = 'power_mod');
```

需要注意的现实：

- WASM 当前 64 位整数和 SIMD 支持仍有差距，复杂数据类型（Decimal、Array、Map）需自建编解码。
- 主流 Wasm runtime（Wasmtime / Wasmer）在 hot loop 上比原生 C++ 慢 1.5~3 倍。
- 主流引擎对 **Component Model** 与 **WASI Preview2** 的支持还不一致，标准化在路上。

可以预测：未来 3~5 年，新一代云原生 OLAP（DatabendDB、SingleStore、ClickHouse、Materialize 等）将以 Wasm 作为 UDF 的主路径，而成熟的关系数据库（PostgreSQL、Oracle、SQL Server）会保留 C/CLR/JVM 多栈并存。

## 关键发现

### 1. 托管 vs 自管：UDF 模型截然不同

**自管数据库**（PostgreSQL、Oracle、DB2、ClickHouse 等）允许用户加载本地 .so/JAR，因为运维者就是用户自己，安全责任清晰。**托管云仓**（Snowflake、BigQuery、Redshift、Athena）几乎全部禁止本地共享库，转而提供：

- 严格沙箱化的脚本语言（JS、托管 Python）
- Remote Function（HTTP/Lambda）
- 容器化运行时（Snowpark Container Services、BigQuery Connection）

这是云数据库不可避免的取舍。

### 2. JVM 是覆盖最广的 UDF 运行时

24+ 引擎支持 Java/JVM UDF（包括 Spark/Flink/Hive/Trino/StarRocks/Doris 等所有 Hadoop 系，加上 H2/HSQLDB/Derby 这类纯 Java DB），是覆盖面最广的外部语言。这是 Hadoop 生态遗产。

### 3. Python UDF 性能差距巨大

- **进程内嵌入式**（PostgreSQL PL/Python、DuckDB Python API）：零拷贝、最快
- **Arrow 优化进程外**（Spark Pandas UDF、Snowpark Python、StarRocks）：高吞吐
- **逐行进程外**（Hive TRANSFORM、Spark 老式 UDF）：最慢，可比 Scala UDF 慢 50~100 倍

选择 Python UDF 时**必须确认是否有 Arrow 路径**。

### 4. Wasm 是新建系统的主流方向

新一代 OLAP（SingleStore Wasm、DatabendDB Wasm、ClickHouse 24.4 Wasm、ScyllaDB Wasm）几乎都把 Wasm 当成 UDF 的"第一路径"，因为它一次性解决了沙箱、跨平台、多语言三个传统痛点。预计未来 5 年 Wasm UDF 将成为云原生数据库的标配。

### 5. SQL-only UDF 才是优化器的最爱

无论 UDF 用什么语言写，对优化器而言都是**黑盒**——无法谓词下推、无法常量折叠、无法重写。只有 `LANGUAGE SQL` 的简单标量/inline TVF 能被完全展开。Snowflake、BigQuery、Materialize 等多次在文档中明确建议"能用 SQL 写就别写 UDF"。

### 6. ClickHouse 的 fork/exec 模型独树一帜

绝大多数引擎选择嵌入解释器或加载共享库，唯独 ClickHouse 默认走"批量数据 + 子进程"路线。优势是天然隔离、可用任意语言、批处理摊薄进程开销；劣势是单次启动延迟 5~50ms，不适合极小批查询。这种"脏快好"的工程哲学很 ClickHouse。

### 7. CLR / JVM 老路逐渐边缘化

SQL Server CLR 在 2017 之后被官方降权，PL/Java 在 PostgreSQL 生态边缘存在但不主流，Oracle Java SP 在新项目中越来越少。**微软**用 ML Services 和 JS UDF 接班，**Oracle** 用 MLE（GraalVM）接班，**PostgreSQL** 用 pgrx 与 PL/Python3 接班。

### 8. Remote Function 是云仓的"兜底"

Snowflake External Function、BigQuery Remote Function、Redshift/Athena Lambda UDF 都是同一个解决方案：**用网络调用绕过运行时限制**。优点是任意语言/任意库；缺点是高延迟（10~100ms/调用）、依赖云供应商生态、跨云不可移植。

### 9. UDF 的数据类型转换是隐藏成本

跨语言传递 Decimal、Date、Timestamp、Array、Map、Struct 时往往涉及编解码：

- Spark Python UDF 早期靠 Pickle，每行约 5~20μs
- Pandas UDF 用 Arrow，单值约 10~100ns
- Snowflake Java UDF 走类似 Arrow 的列式 batch
- ClickHouse executable UDF 走 TSV/Native 文本/二进制

这部分往往比 UDF 算法本身耗时还多，**测量真实执行时建议先减去 IO/序列化时间**。

### 10. GPU UDF 仍是研究主题

除 HEAVY.AI 等专用 GPU DBMS 外，主流引擎几乎不直接支持 GPU UDF。常见做法是：Python UDF 内调 PyTorch/TensorFlow（Spark RAPIDS、Snowpark Container），或通过 BigQuery ML、Snowflake Cortex 等"内置 ML 函数"间接利用 GPU。完全引擎层面的 GPU UDF 仍未出现统一接口。

## 总结对比矩阵

| 能力 | PostgreSQL | Oracle | SQL Server | DB2 | Snowflake | BigQuery | DuckDB | ClickHouse | Spark | Vertica |
|------|-----------|--------|-----------|-----|-----------|----------|--------|------------|-------|---------|
| C/C++ 共享库 | 是 | 是 (extproc) | -- | 是 | -- | -- | 是 | 是 (build) | -- | 是 |
| Java UDF | 第三方 | 是 (OJVM) | -- | 是 | 是 | -- | -- | -- | 是 | 是 |
| Python UDF | 是 (PL/Py) | -- | ML Services | -- | 是 (Snowpark) | -- | 是 | 进程外 | 是 (Pandas) | 是 |
| JavaScript UDF | PL/V8 | MLE | -- | -- | 是 (V8) | 是 (V8) | -- | -- | -- | -- |
| Rust UDF | pgrx | -- | -- | -- | -- | -- | 实验 | 实验 | -- | -- |
| WASM UDF | 实验 | -- | -- | -- | -- | -- | 实验 | 24.4+ | -- | -- |
| 远程函数 | 自建 | -- | -- | -- | 是 | 是 | -- | executable | -- | -- |
| FENCED 模式 | 通过进程 | extproc | -- | 是 | 是 | 是 | -- | 是 | -- | 是 |
| GPU UDF | -- | -- | -- | -- | 间接 | ML 函数 | -- | -- | RAPIDS | -- |

### 引擎选型建议

| 场景 | 推荐 | 原因 |
|------|------|------|
| 高性能本地 C UDF | PostgreSQL + pgrx | C ABI 稳定，Rust 现代 |
| 数据仓库内统一 ML 推理 | Snowflake Snowpark Python | 全托管、Conda 包白名单 |
| 严格沙箱 + 简单字符串处理 | BigQuery JS UDF | 即写即用，无运维 |
| 大数据 ETL 自定义清洗 | Spark Pandas UDF (Arrow) | 高吞吐，与 DataFrame 无缝 |
| 自定义连接器 + 工业级 UDx | Vertica 或 Trino 插件 | 完整 SPI |
| 嵌入式 Python 数据科学 | DuckDB + Python API | 零拷贝 Arrow |
| 多语言进程外 UDF | ClickHouse executable UDF | 任意语言、自然隔离 |
| 云原生 + 跨平台沙箱 | SingleStore / DatabendDB Wasm | 一次编译多处运行 |
| 跨云调任意服务 | Snowflake External Function / BigQuery Remote Function | HTTP 任意后端 |
| 纯 SQL 优化器友好 | DuckDB MACRO / PostgreSQL SQL function | 100% 内联展开 |

## 参考资料

- PostgreSQL: [C-Language Functions](https://www.postgresql.org/docs/current/xfunc-c.html), [PL/Python](https://www.postgresql.org/docs/current/plpython.html)
- pgrx (Rust for PostgreSQL): https://github.com/pgcentralfoundation/pgrx
- Oracle: [External Procedures](https://docs.oracle.com/en/database/oracle/oracle-database/19/adfns/calling-external-procedures.html), [MLE / GraalVM](https://docs.oracle.com/en/database/oracle/oracle-database/21/mlejs/index.html)
- SQL Server: [CLR Integration Programming Model](https://learn.microsoft.com/en-us/sql/relational-databases/clr-integration/clr-integration-programming-model)
- DB2: [External Functions](https://www.ibm.com/docs/en/db2/11.5?topic=routines-external-routines)
- Snowflake: [Java UDFs](https://docs.snowflake.com/en/developer-guide/udf/java/udf-java), [Python UDFs](https://docs.snowflake.com/en/developer-guide/udf/python/udf-python)
- BigQuery: [JavaScript UDFs](https://cloud.google.com/bigquery/docs/user-defined-functions), [Remote Functions](https://cloud.google.com/bigquery/docs/remote-functions)
- DuckDB: [Extensions](https://duckdb.org/docs/extensions/overview), [Python API create_function](https://duckdb.org/docs/api/python/function)
- ClickHouse: [Executable User Defined Functions](https://clickhouse.com/docs/en/sql-reference/functions/udf)
- Spark: [Pandas UDFs](https://spark.apache.org/docs/latest/sql-ref-functions-udf-scalar-pandas.html)
- Vertica: [Developing User-Defined Extensions](https://docs.vertica.com/latest/en/extending/developing-udxs/)
- SingleStore: [Wasm UDF](https://docs.singlestore.com/db/latest/reference/code-engine-powered-by-wasm/)
- DatabendDB: [User-Defined Functions](https://docs.databend.com/sql/sql-commands/ddl/udf/)
- ScyllaDB: [User Defined Functions (Wasm)](https://opensource.docs.scylladb.com/stable/cql/functions.html)
- WebAssembly Component Model: https://github.com/WebAssembly/component-model
- ISO/IEC 9075-9: SQL/MED (Management of External Data)
