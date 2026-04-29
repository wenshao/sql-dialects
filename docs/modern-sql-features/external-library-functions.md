# 外部库函数加载 (External Library Functions)

数据库引擎本质上是一个长期运行的服务进程，而把一段用户写的 C/C++ 代码加载进这个进程地址空间——通过 `dlopen` 打开 `.so`、`LoadLibraryEx` 打开 `.dll`、`dlsym` 解析符号——这是性能最高、安全风险也最大的扩展方式。本文聚焦"外部共享库加载"这条路径：DDL 语法、动态链接器交互、ABI 兼容承诺、安全模型与 ASLR/RELRO/沙箱设计。

> 本文是 [udf-external-functions.md](./udf-external-functions.md) 的"低层补集"。前者横向覆盖 C/Java/Python/JS/Wasm/Remote 全部外部语言，本文只看**动态链接器加载本地原生代码**这一种机制——`.so` / `.dll` / `.dylib` 如何走进数据库进程，以及由此带来的 ABI、安全、运维耦合问题。也请参阅 [stored-procedures-udf.md](./stored-procedures-udf.md) 关于 PL/SQL、PL/pgSQL、T-SQL 等方言函数的内容，本文不重复。

## 为什么"加载共享库"是独立的话题

把"外部函数"和"外部共享库加载"区分开，是因为它们对引擎的影响完全不在一个层级：

1. **进程地址空间共享**：`.so` 加载后与服务器进程共享同一虚拟地址空间。一个段错误就会带走整个数据库实例。Java/Python/JS UDF 跑在解释器/虚拟机里，最多崩掉解释器，原生 `.so` 直接 SIGSEGV 整个 PostgreSQL/MySQL/Oracle 主进程。
2. **ABI 而非 API 兼容**：调用约定、结构体字段顺序、宏展开、TLS 模型、`size_t` 宽度——任意一处不匹配都会触发难以定位的崩溃。脚本语言只要 API 稳定就能跑，原生库要保证 ABI 稳定。
3. **二进制分发与运维**：每个 OS × CPU 架构都需要单独编译；libc/libstdc++ 版本必须匹配数据库自身；plugin 目录、`LD_LIBRARY_PATH`、`SELinux` 策略、容器镜像都需要协调。
4. **安全边界完全不同**：脚本沙箱可以限制系统调用，原生 `.so` 拥有数据库进程的全部权限——读 `pg_authid` 密码哈希、修改共享内存、调用 `system("rm -rf /")`，完全没有边界。
5. **链接器副作用**：`.so` 的全局构造函数、TLS 初始化、`dlopen` 的 `RTLD_GLOBAL` 都可能污染主进程的符号表，导致后续加载冲突。

把"加载本地共享库"视为独立机制看待，才能理性评估它在自管/托管、内核/用户态隔离、ASLR/RELRO 等维度的成本与收益。

## 没有 SQL 标准

ISO/IEC 9075-2 标准只规定 `CREATE FUNCTION ... LANGUAGE <lang>` 的语法骨架，没有任何关于：

- 动态链接器（`dlopen`/`LoadLibraryEx`）的语义
- 共享库的搜索路径（`LD_LIBRARY_PATH`、`PATH`、注册表）
- ABI 版本检查的标记机制
- 共享内存与全局变量的隔离要求

各家厂商完全自定义。最接近的标准条款是 SQL/PSM 中的 `CREATE LIBRARY` 声明（Oracle 8i 引入并实现），但这只是一个目录式的命名注册，距离真正的"加载机制"仍然很远。结论：**外部共享库加载是各引擎方言差异最大的领域**，比 UDF 整体差异更大。

## 支持矩阵

### 共享库加载机制（45+ 引擎）

| 引擎 | DDL 语法 | 加载方式 | 平台 | 在线加载 | 隔离 | 起始版本 |
|------|---------|---------|------|---------|------|---------|
| PostgreSQL | `CREATE FUNCTION ... LANGUAGE C` + `LOAD '<so>'` | dlopen + PG_MODULE_MAGIC | Linux/macOS/Windows | 是 | 进程内 | PG 7.x (2000) |
| Oracle | `CREATE LIBRARY` + `CREATE FUNCTION ... AS LANGUAGE C` | extproc 进程外 RPC | 全 | 是 | 子进程 | 8i (1999) |
| SQL Server | `CREATE ASSEMBLY` (CLR DLL) | LoadLibrary + AppDomain | Windows/Linux | 是 | CLR 沙箱 | 2005 |
| MySQL | `CREATE FUNCTION ... SONAME '<so>'` | dlopen + 符号扫描 | Linux/macOS/Windows | 是 | 进程内 | 5.0 (2005) |
| MariaDB | `CREATE FUNCTION ... SONAME '<so>'` | 同 MySQL | 全 | 是 | 进程内 | 兼容 5.x |
| SQLite | `sqlite3_load_extension()` API + `.load` shell | dlopen | 全 | 是 | 进程内 | 3.5 (2007) |
| DB2 | `CREATE FUNCTION ... LANGUAGE C EXTERNAL NAME 'lib!sym'` | dlopen，FENCED 子进程或 UNFENCED | 全 | 是 | 二选一 | V5+ |
| Snowflake | -- | -- | -- | -- | -- | 不支持 |
| BigQuery | -- | -- | -- | -- | -- | 不支持 |
| Redshift | -- | -- | -- | -- | -- | 不支持 |
| DuckDB | `INSTALL <ext>; LOAD <ext>;` | dlopen + 数字签名 | 全 | 是 | 进程内 | 0.3+ (2021) |
| ClickHouse | C++ plugin（编译期）+ executable UDF（进程外） | 静态链接为主 | 全 | 重启 | 进程内/子进程 | 早期 |
| Trino | Plugin SPI（Java JAR） | JVM ClassLoader | 全（JVM） | 重启 | JVM 内 | 早期 |
| Presto | Plugin SPI（Java JAR） | JVM ClassLoader | 全（JVM） | 重启 | JVM 内 | 早期 |
| Spark SQL | -- | -- | -- | -- | -- | 仅 JVM |
| Hive | -- | -- | -- | -- | -- | 仅 JVM |
| Flink SQL | -- | -- | -- | -- | -- | 仅 JVM |
| Databricks | -- | -- | -- | -- | -- | 托管禁止 |
| Teradata | `CREATE FUNCTION ... LANGUAGE C EXTERNAL NAME 'CS!sym'` | dlopen + PROTECTED MODE | Linux/AIX | 重启可选 | 二选一 | V2R5 |
| Greenplum | 继承 PG | 同 PG，分发到所有 segment | Linux | 是 | 进程内 | 早期 |
| CockroachDB | -- | -- | -- | -- | -- | 不支持 |
| TiDB | -- | -- | -- | -- | -- | 不支持 |
| OceanBase | -- | -- | -- | -- | -- | 不支持 |
| YugabyteDB | 继承 PG（部分） | 同 PG | Linux | 是 | 进程内 | 早期 |
| SingleStore | C ABI 共享库 + Wasm | dlopen 或 Wasmer | Linux | 是 | 二选一 | 早期 |
| Vertica | C++ UDx `.so` | dlopen + Fenced 容器或 UNFENCED | Linux | 是 | 二选一 | 5.0+ |
| Impala | `CREATE FUNCTION ... LOCATION '*.so'` | dlopen，HDFS 分发 | Linux | 是 | 进程内 | 1.x+ |
| StarRocks | -- | -- | -- | -- | -- | Java/Python 优先 |
| Doris | -- | -- | -- | -- | -- | Java/Python 优先 |
| MonetDB | C UDF (MAL 模块) | dlopen | Linux/macOS | 是 | 进程内 | 早期 |
| CrateDB | -- | -- | -- | -- | -- | 仅 JS UDF |
| TimescaleDB | 继承 PG | 同 PG | Linux | 是 | 进程内 | 1.x+ |
| QuestDB | -- | -- | -- | -- | -- | 仅 Java |
| Exasol | C++ Script Container | 容器化 dlopen | Linux | 是 | 容器隔离 | 6.x+ |
| SAP HANA | AFL（Application Function Library） | dlopen + HANA studio 部署 | Linux | 部分 | 进程内 | 1.x+ |
| Informix | C UDR / DataBlade | dlopen | 全 | 是 | 进程内 | 7.x+ |
| Firebird | UDR (modern) / UDF (legacy) | dlopen | 全 | 是 | 进程内 | 3.0+ |
| H2 | -- | -- | -- | -- | -- | 仅 Java |
| HSQLDB | -- | -- | -- | -- | -- | 仅 Java |
| Derby | -- | -- | -- | -- | -- | 仅 Java |
| Amazon Athena | -- | -- | -- | -- | -- | 不支持 |
| Azure Synapse | -- | -- | -- | -- | -- | 不支持 |
| Google Spanner | -- | -- | -- | -- | -- | 不支持 |
| Materialize | -- | -- | -- | -- | -- | 不支持 |
| RisingWave | -- | -- | -- | -- | -- | 仅远程 UDF |
| InfluxDB (SQL) | -- | -- | -- | -- | -- | 不支持 |
| DatabendDB | -- | -- | -- | -- | -- | Wasm 优先 |
| Yellowbrick | C/C++ UDx (继承 Vertica 血缘) | dlopen | Linux | 是 | 二选一 | 早期 |
| Firebolt | -- | -- | -- | -- | -- | 不支持 |

> 统计：约 18 个引擎支持原生共享库加载，27+ 个引擎不支持或仅通过 JVM/Wasm 间接支持。云托管引擎几乎全部禁止此机制。

### CREATE LIBRARY DDL 对比

不少引擎将"声明库"和"声明函数"分成两步——先注册库的物理路径，再把函数绑定到库的某个符号。这一方面是 ANSI SQL 风格的命名空间设计，另一方面是为了重命名/移动 `.so` 时不必更新所有函数定义。

| 引擎 | 库注册 DDL | 函数绑定 DDL | 重命名能力 |
|------|-----------|-------------|-----------|
| Oracle | `CREATE LIBRARY my_lib AS '/path/lib.so'` | `CREATE FUNCTION ... LIBRARY my_lib NAME "sym"` | 改 LIBRARY 即可 |
| DB2 | -- | `CREATE FUNCTION ... EXTERNAL NAME 'lib!sym'` | 直接修改 EXTERNAL NAME |
| PostgreSQL | -- | `CREATE FUNCTION ... AS '$libdir/myext', 'sym'` | 必须 DROP/CREATE |
| MySQL | -- | `CREATE FUNCTION foo RETURNS INT SONAME 'lib.so'` | 必须 DROP/CREATE |
| Teradata | -- | `CREATE FUNCTION ... EXTERNAL NAME 'CS!sym'` | 直接修改 |
| Vertica | `CREATE LIBRARY my_lib AS '/path/lib.so'` | `CREATE FUNCTION ... AS LANGUAGE 'C++' NAME 'factory_class' LIBRARY my_lib` | 改 LIBRARY 即可 |
| Yellowbrick | `CREATE LIBRARY` | 同 Vertica | -- |
| Impala | -- | `CREATE FUNCTION ... LOCATION 'hdfs://path/lib.so' SYMBOL='sym'` | 必须 DROP/CREATE |
| SingleStore | -- | `CREATE FUNCTION ... AS WASM FROM 'path' WITH (HANDLER='sym')` | -- |

> 注：拥有 `CREATE LIBRARY` 的引擎通常源于 ANSI SQL/PSM 的传统设计哲学（Oracle、Vertica）。MySQL/PostgreSQL/Teradata/DB2 选择把库路径直接嵌在函数定义中，简化但缺乏复用。

### 安全模型与沙箱

| 引擎 | 沙箱方式 | 关键机制 | 默认安全级别 |
|------|---------|---------|-------------|
| PostgreSQL | 无（进程内） | 仅 superuser 可加载 | 高权限要求 |
| Oracle | 子进程 (extproc) | 独立 OS 进程 + 认证 | 完全进程隔离 |
| SQL Server (CLR) | AppDomain + CAS | SAFE/EXTERNAL_ACCESS/UNSAFE 三级 | SAFE 默认 |
| MySQL | 无 | `secure_file_priv`、plugin_dir 限制 | DROP SUPER 隔离 |
| DB2 | FENCED 子进程 | db2fmp 进程组 | FENCED 默认 |
| Vertica | Fenced 容器 (cgroups) | 资源限制 + sudo 限制 | FENCED 默认 |
| Teradata | PROTECTED MODE | 子进程隔离 | PROTECTED 默认 |
| SQLite | 无 | 编译期可禁用 | 默认禁用扩展 |
| DuckDB | 数字签名 | 官方扩展白名单 | 仅签名扩展默认允许 |
| Exasol | 容器化 (LXC) | UDF Script Container | 容器内默认 |
| Snowflake / BigQuery | 完全禁止 | 禁止本地库加载 | -- |

### LD_LIBRARY_PATH / 二进制搜索路径

不同引擎对 `.so` 文件的搜索路径处理差别很大，这直接影响升级、容器化部署、共存安装：

| 引擎 | 默认搜索路径 | 配置变量 | 安全考虑 |
|------|------------|---------|---------|
| PostgreSQL | `$libdir`（由 `pg_config --pkglibdir` 决定） | `dynamic_library_path` | 相对路径加载需 superuser |
| MySQL | `plugin_dir` 系统变量（编译期默认） | `--plugin-dir` | 不允许相对路径 |
| MariaDB | `plugin_dir` | 同 MySQL | -- |
| SQLite | 当前目录 + `LD_LIBRARY_PATH` | -- | 默认禁用扩展 |
| Oracle | `extproc.ora` 中显式声明 | `EXTPROC_DLLS` | 默认仅允许显式列表 |
| DB2 | `function/routine` 子目录 + 系统库路径 | `DB2_FENCED_LIB_PATH` | -- |
| Vertica | `/opt/vertica/sdk/...` | -- | 必须 dbadmin 安装 |
| SQL Server | (CLR) 数据库内字节流 | -- | DLL 字节流注入 |
| ClickHouse | (静态) 编译期 | -- | -- |
| DuckDB | `~/.duckdb/extensions/` | `extension_directory` | 数字签名校验 |

### ABI 稳定性与版本魔数

跨大版本/小版本是否需要重新编译 `.so`？

| 引擎 | ABI 标记 | 跨小版本兼容 | 跨大版本兼容 | 不匹配后果 |
|------|---------|-------------|-------------|-----------|
| PostgreSQL | `PG_MODULE_MAGIC` 魔数（含版本号、长度等） | 是 | 否 | 加载报错，拒绝加载 |
| MySQL | `STANDARD_CHARSET_INFO` ABI 检查 | 通常是 | 否 | 加载失败 |
| SQLite | API 版本号宏 | 是 | 是（多数情况） | 函数签名错误 |
| Oracle | extproc 协议版本 | 是 | 协议层兼容 | RPC 错误 |
| SQL Server (CLR) | .NET CLR 版本绑定 | 是 | 否（4.x→.NET Core） | 编译失败 |
| Vertica | UDx ABI Hash | 是 | 否 | 主动拒绝 |
| DB2 | LANGUAGE C 头文件版本 | 通常是 | 编译宏控制 | 签名错误 |
| DuckDB | 扩展头文件版本 + 签名 | 是（同次要版本） | 否 | 拒绝加载 |
| Teradata | UDF Library Version | 是 | -- | 拒绝加载 |
| ClickHouse | (静态链接为主) | -- | -- | -- |
| MonetDB | MAL 接口版本 | 是 | 否 | 拒绝加载 |
| Firebird | UDR ABI 头文件 | 是 | 否 | 拒绝加载 |
| Informix | DataBlade SDK 版本 | 是 | 编译期检查 | 拒绝加载 |

### ASLR / RELRO / DEP 与共享库

地址空间随机化（ASLR）、只读重定位表（RELRO）、不可执行栈（NX/DEP）是现代 Linux/Windows 默认开启的安全防护。`.so` 加载到数据库进程后，同时受这些约束：

| 安全机制 | PostgreSQL | MySQL | SQLite | Oracle (extproc) | SQL Server (CLR) | DuckDB | Vertica |
|---------|-----------|-------|--------|------------------|------------------|--------|---------|
| ASLR 兼容 | 是 (PIE 编译) | 是 | 是 | 是（extproc 进程独立） | -- (CLR sandboxed) | 是 | 是 |
| Full RELRO | 推荐 | 推荐 | -- | -- | -- (CLR) | 是 | 推荐 |
| NX 栈 | 是 | 是 | 是 | 是 | -- | 是 | 是 |
| Stack canary | `-fstack-protector` | 同 | 同 | 同 | -- | 同 | 同 |
| W^X 内存页 | 是 | 是 | 是 | 是 | (CLR) | 是 | 是 |

> 编译扩展时建议 `gcc -fPIC -fstack-protector-strong -Wl,-z,relro -Wl,-z,now -shared`。这样的链接选项与现代发行版的 hardening 默认保持一致，避免引擎升级时遇到 ELF section 错误或 DEP 违例。

### 容器/cgroups 隔离

部分引擎将外部库执行隔离到独立容器或 cgroup：

| 引擎 | 容器机制 | 隔离粒度 |
|------|---------|---------|
| Vertica | Fenced UDx Container | 进程组 + cgroup |
| Exasol | LXC 容器 | 完整 OS 命名空间 |
| Oracle | extproc 子进程 | 进程隔离（无 cgroup） |
| DB2 | db2fmp 进程组 | 进程组 |
| Teradata | PROTECTED MODE 子进程 | 进程隔离 |
| Snowpark Container Services | Kubernetes Pod | 完整容器 |
| 其他 | 无 | 进程内 |

## PostgreSQL：C 扩展的金标准

PostgreSQL 的 C 扩展机制是过去 30 年最稳定、生态最丰富、文档最完整的 SQL 引擎扩展模型。它的设计影响了 Greenplum、TimescaleDB、Yugabyte、CitusDB、Cockroach（部分）等无数派生产品。

### 加载流程

```
1. 用户执行 CREATE FUNCTION ... LANGUAGE C
2. 函数定义存入 pg_proc，但 .so 还没真正加载
3. 第一次调用时，fmgr_c_validator 触发 dlopen($libdir/myext.so)
4. PostgreSQL 在 .so 中查找 Pg_magic_func 符号，验证版本
5. 验证通过 → 缓存句柄 → 通过 dlsym 解析 'my_add' 符号
6. 实际调用 my_add(PG_FUNCTION_ARGS)
```

### V1 调用约定

PostgreSQL 自 7.x 起强制使用 **V1 calling convention**——所有外部 C 函数都通过统一的 `Datum` 类型传参，宏 `PG_GETARG_*` 和 `PG_RETURN_*` 负责类型转换。这是 ABI 稳定性的核心：

```c
#include "postgres.h"
#include "fmgr.h"
#include "utils/builtins.h"

PG_MODULE_MAGIC;   /* 必须存在 - 含 ABI 魔数 */

PG_FUNCTION_INFO_V1(square_root);

Datum square_root(PG_FUNCTION_ARGS)
{
    float8 x = PG_GETARG_FLOAT8(0);
    if (x < 0) {
        ereport(ERROR,
            (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
             errmsg("cannot compute sqrt of negative number")));
    }
    PG_RETURN_FLOAT8(sqrt(x));
}
```

```sql
CREATE FUNCTION square_root(double precision) RETURNS double precision
AS '$libdir/mathext', 'square_root'
LANGUAGE C STRICT IMMUTABLE;
```

`PG_MODULE_MAGIC` 宏展开后是一个结构体常量，包含：

```c
typedef struct {
    int     len;
    int     version;
    int     funcmaxargs;
    int     indexmaxkeys;
    int     namedatalen;
    int     float8byval;
    char    abi_extra[32];
} Pg_magic_struct;
```

如果加载的 `.so` 的 `Pg_magic_struct` 与服务器进程不匹配（比如 `funcmaxargs` 改了），PG 会立即拒绝加载并报错 `incompatible library`。这是 PG 跨版本最重要的安全网。

### `$libdir` 与 `dynamic_library_path`

```sql
SHOW dynamic_library_path;       -- 默认 $libdir
SET dynamic_library_path = '$libdir:/opt/myext/lib';

-- $libdir 在编译期固定为 pkglibdir，可通过：
SELECT setting FROM pg_settings WHERE name = 'data_directory';
SHOW shared_preload_libraries;   -- 启动时预加载列表
```

### 扩展（Extension）vs 函数

PostgreSQL 9.1 引入 `CREATE EXTENSION` 概念，把若干个函数、操作符、类型、表打包成可命名、可升级的单元：

```sql
CREATE EXTENSION pg_trgm;
\dx pg_trgm

-- 内部其实是执行 share/extension/pg_trgm--1.6.sql 中的 DDL
-- DDL 中可包含 CREATE FUNCTION ... LANGUAGE C
```

设计要点：

- **扩展 = SQL 脚本 + 控制文件 (.control)**：不是新的加载机制，仍然走 LANGUAGE C
- **超级用户特权**：CREATE EXTENSION 可在普通模式安装受信任扩展（`trusted = true`）
- **可升级**：`ALTER EXTENSION pg_trgm UPDATE TO '1.6'` 自动执行 `pg_trgm--1.5--1.6.sql` 增量脚本
- **依赖跟踪**：`pg_depend` 记录扩展拥有的对象，`DROP EXTENSION` 自动级联

### 共享内存与 GUC

C 扩展可以通过 `RequestAddinShmemSpace` 申请共享内存、通过 `DefineCustomXxxVariable` 注册 GUC 配置项：

```c
void _PG_init(void) {
    DefineCustomIntVariable(
        "myext.max_workers",     /* 名称 */
        "Maximum worker count",   /* 描述 */
        NULL,
        &max_workers, 4, 1, 64,
        PGC_POSTMASTER,           /* 启动时不可改 */
        0, NULL, NULL, NULL);

    RequestAddinShmemSpace(MyShmemSize());
    RequestNamedLWLockTranche("myext", 1);
}
```

但这要求扩展在 `shared_preload_libraries` 中预加载（postmaster 启动时），不能动态加载。

### Hooks 系统

PG 内置数十个 hook 点（planner_hook、ExecutorRun_hook、ProcessUtility_hook 等），扩展通过赋值 hook 函数指针来劫持核心流程。这是 pg_stat_statements、pgaudit、pgvector 等扩展工作的关键。

```c
static planner_hook_type prev_planner_hook = NULL;
PlannedStmt *my_planner(Query *parse, const char *qstring, int opts, ParamListInfo bp) {
    /* ... */
    return prev_planner_hook ? prev_planner_hook(parse, qstring, opts, bp) : standard_planner(parse, qstring, opts, bp);
}

void _PG_init(void) {
    prev_planner_hook = planner_hook;
    planner_hook = my_planner;
}
```

设计上这是"零界面广播"模型——任何扩展都能拦截全局 hook，但有责任保持兼容（链式调用前一个 hook）。

## Oracle：CREATE LIBRARY + extproc 进程隔离

Oracle 的外部 C 库加载是**唯一一个默认走子进程的设计**。它早在 8i（1999）就采用，目的是不要让任意 C 代码运行在 Oracle 共享池里。

### 架构

```
SQL*Plus  →  Oracle Server (oracle 进程)
                    ↓ Net8 / IPC
              extproc Listener
                    ↓ fork
              extproc Agent
                    ↓ dlopen
              libmyfunc.so
```

每次调用外部函数，Oracle Server 通过 RPC 把参数序列化送给 `extproc` 进程，由 `extproc` 在自己的地址空间内 dlopen `.so`、执行函数、把结果再序列化回来。

### DDL

```sql
-- 第一步：声明库（仅指向 .so 路径）
CREATE OR REPLACE LIBRARY mathlib AS '/u01/oracle/ext/libmath.so';

-- 第二步：声明函数与 LIBRARY/SYMBOL 绑定
CREATE OR REPLACE FUNCTION square_root(x BINARY_DOUBLE) RETURN BINARY_DOUBLE
AS LANGUAGE C
LIBRARY mathlib
NAME "square_root"
PARAMETERS (x DOUBLE, RETURN DOUBLE);
```

### extproc 配置

`$ORACLE_HOME/hs/admin/extproc.ora`：

```
SET EXTPROC_DLLS=ANY                        -- 允许任意路径（默认禁止）
SET EXTPROC_DLLS=ONLY:/u01/oracle/ext/libmath.so:/u01/...
SET EXTPROC_DLLS=                           -- 完全禁用
```

`tnsnames.ora`：

```
EXTPROC_CONNECTION_DATA =
  (DESCRIPTION =
    (ADDRESS_LIST = (ADDRESS = (PROTOCOL = IPC)(KEY = EXTPROC1)))
    (CONNECT_DATA = (SID = PLSExtProc)(PRESENTATION = RO)))
```

### 安全意义

- **崩溃隔离**：即使 `.so` SIGSEGV，只有 extproc 子进程退出，Oracle 主实例不受影响
- **权限隔离**：extproc 通常以 oracle 用户运行，但可通过 `EXTPROC_DLLS` 白名单进一步限制
- **审计**：所有 RPC 都经过 listener，可在 listener.log 中审计调用频次

代价是 RPC 开销——每次调用约 100~500 微秒，远大于进程内调用的 50~200 纳秒。这就是为什么 Oracle PL/SQL 主推内嵌 Java（OJVM）和 MLE GraalVM，而不是大规模使用 EXTPROC。

### Oracle MLE（Multilingual Engine, 21c+）

Oracle 21c 起引入 **MLE**，基于 GraalVM 在数据库进程内运行 JavaScript / Python。这是 Oracle 应对"原生 C 太危险、Java 太重"困境的现代答卷。MLE 不走 extproc，是嵌入式 JIT 解释器。

虽然不是本文主角，但理解 Oracle 已逐渐在边缘化 EXTPROC：

- **新功能首选 MLE**（沙箱、零运维、JIT 性能）
- **EXTPROC 仍保留**用于历史 C 库
- **OJVM 仍是企业 ERP 与 EBS 的主力**

## SQL Server：CREATE ASSEMBLY 与 CLR 整合

SQL Server 2005 引入 **SQL CLR Integration**，允许把 .NET DLL（C#/F#/VB.NET）注册为 T-SQL UDF、SP、Trigger、Type、Aggregate。这是 SQL Server 的"原生扩展"路径——但**不是真正的 dlopen**，而是 LoadLibrary + CLR AppDomain。

### DDL

```sql
-- 启用 CLR
EXEC sp_configure 'clr enabled', 1;
RECONFIGURE;

-- 注册程序集（DLL 字节流存到数据库内）
CREATE ASSEMBLY MathExt
FROM 'C:\bin\MathExt.dll'
WITH PERMISSION_SET = SAFE;

-- 注册函数
CREATE FUNCTION dbo.SqrtPlus(@x float) RETURNS float
AS EXTERNAL NAME MathExt.[MathExt.MathFunctions].SqrtPlus;
```

### 三级权限

| 权限 | 允许操作 | 风险 |
|------|---------|------|
| SAFE | 仅托管代码、仅访问当前数据库 | 低 |
| EXTERNAL_ACCESS | 文件、网络、注册表、环境变量 | 中 |
| UNSAFE | P/Invoke、unmanaged 代码、unverifiable IL | 高 |

### CLR 沙箱机制

不同于 PostgreSQL 直接 dlopen 信任所有代码，SQL Server CLR 通过：

- **AppDomain 隔离**：不同 ASSEMBLY 加载到不同 AppDomain，崩溃可恢复
- **Code Access Security (CAS)**：基于权限集限制 .NET 代码能调用的 API
- **Strong Name 签名**：UNSAFE/EXTERNAL_ACCESS 的程序集必须签名
- **TRUSTWORTHY DB 标志**：限制跨数据库调用

### 自 2017 起的"边缘化"

SQL Server 2017 引入 `clr strict security` 配置（默认开启），强制：

- 所有 ASSEMBLY 必须在 master 数据库登记签名公钥
- TRUSTWORTHY 设置不再被默认信任
- UNSAFE 程序集必须使用证书或非对称密钥签名

实际后果：

- 现有 SAFE 级别程序集大多需要重签名
- 升级 SQL Server 时 CLR 故障率显著升高
- 微软文档明确把 CLR **降为"维护模式"**

后续替代方向：

- **SQL Server Machine Learning Services (2017+)**：通过外部 Python/R 跑模型
- **JavaScript UDF**（Azure SQL 预览）
- **Microsoft Fabric/Synapse 转向 Spark 与 Python UDF**

CLR 仍可用，但新项目不推荐。

## MySQL：UDF SONAME 与 mysql.func 表

MySQL 5.0（2005）引入正式的 **UDF（User Defined Function）** 加载机制。它是这一代开源数据库中最早的"在线加载共享库"设计之一。

### DDL

```sql
-- 安装 UDF（要求超级权限）
CREATE FUNCTION metaphon
RETURNS STRING
SONAME 'libmymetaphon.so';

-- 卸载
DROP FUNCTION metaphon;
```

### 内部机制

MySQL 维护一张 `mysql.func` 系统表（5.7 及之前为 MyISAM，8.0 起为 InnoDB），存储所有已加载的 UDF：

```
+-------------+------+----------------------+----------+
| name        | ret  | dl                   | type     |
+-------------+------+----------------------+----------+
| metaphon    |    0 | libmymetaphon.so     | function |
| group_concat|    0 | libgroupconcat.so    | aggregate|
+-------------+------+----------------------+----------+
```

服务器启动时遍历 `mysql.func`，对每行 `dlopen(plugin_dir + dl)`、`dlsym(name)` 检查符号存在。如果符号缺失则跳过这一行（不阻止启动）。

### plugin_dir 与安全

MySQL 强制要求 `.so` 必须在 `plugin_dir` 配置的目录中（一般 `/usr/lib/mysql/plugin/`）：

```
mysql> SHOW VARIABLES LIKE 'plugin_dir';
+---------------+-----------------------+
| Variable_name | Value                 |
+---------------+-----------------------+
| plugin_dir    | /usr/lib/mysql/plugin/|
+---------------+-----------------------+
```

```sql
-- 不允许相对路径或目录跳出
CREATE FUNCTION x RETURNS INT SONAME '../bad.so';   -- ERROR 1126
CREATE FUNCTION y RETURNS INT SONAME '/tmp/bad.so'; -- ERROR 1126
```

`secure_file_priv` 进一步限制 LOAD DATA INFILE，但与 SONAME 无直接关联。

### UDF 接口

UDF 必须导出三组函数（C 风格签名）：

```c
/* 初始化：分配上下文 */
my_bool metaphon_init(UDF_INIT *initid, UDF_ARGS *args, char *message);

/* 主逻辑 */
char *metaphon(UDF_INIT *initid, UDF_ARGS *args,
               char *result, unsigned long *length,
               char *is_null, char *error);

/* 清理 */
void metaphon_deinit(UDF_INIT *initid);
```

聚合 UDF 还需要 `_clear / _add / _reset`。这是 MySQL UDF API 自 5.0 至今 21 年保持高度兼容的接口签名。

### 安全演进

- **5.x 早期**：`mysql.func` 是 MyISAM 表，权限不够细
- **5.6**：增加 `INSERT INTO mysql.func` 的 `SUPER` 权限要求
- **5.7**：正式引入 `--secure-load-plugins`（默认禁止 INSERT mysql.func，要求走 CREATE FUNCTION）
- **8.0**：`mysql.func` 升级为 InnoDB；`COMPONENTS` 框架并行存在（更现代的插件机制）

### MariaDB

MariaDB 完整继承 MySQL UDF 接口，但增加了：

- **更广泛的扩展白名单**（LDAP、行级安全、列加密等以 plugin 形式）
- **服务级插件**（query rewrite、authentication、storage engine）

`CREATE FUNCTION ... SONAME` 与 MySQL 完全兼容，多数旧 UDF 可以二进制重用。

## SQLite：sqlite3_load_extension 与编译期开关

SQLite 是嵌入式数据库，外部库加载的设计哲学完全不同：**默认禁用，按需启用，每个 connection 独立决定**。

### API（不是 SQL）

```c
sqlite3 *db;
sqlite3_open(":memory:", &db);

/* 默认禁用扩展加载 */
sqlite3_enable_load_extension(db, 1);

/* 加载 .so/.dll */
char *errmsg = NULL;
if (sqlite3_load_extension(db, "/path/libmyext.so", "sqlite3_extension_init", &errmsg) != SQLITE_OK) {
    fprintf(stderr, "load failed: %s\n", errmsg);
    sqlite3_free(errmsg);
}
```

### Shell

```sql
sqlite> .load /path/libmyext.so
```

### 自定义函数 API

`.so` 内的入口函数必须叫 `sqlite3_extension_init`（或自定义），调用 `sqlite3_create_function`：

```c
#include "sqlite3ext.h"
SQLITE_EXTENSION_INIT1

static void my_upper(sqlite3_context *ctx, int argc, sqlite3_value **argv) {
    const char *s = (const char*)sqlite3_value_text(argv[0]);
    if (!s) { sqlite3_result_null(ctx); return; }

    int len = strlen(s);
    char *out = sqlite3_malloc(len + 1);
    for (int i = 0; i < len; i++) out[i] = toupper(s[i]);
    out[len] = 0;
    sqlite3_result_text(ctx, out, len, sqlite3_free);
}

int sqlite3_extension_init(sqlite3 *db, char **errmsg, const sqlite3_api_routines *api) {
    SQLITE_EXTENSION_INIT2(api);
    return sqlite3_create_function(db, "myupper", 1, SQLITE_UTF8, NULL,
                                   my_upper, NULL, NULL);
}
```

### 内置扩展 vs 加载式扩展

SQLite 大量功能其实是**预编译的扩展**，运行时不需要 `.so`：

| 扩展 | 默认编译 | 启用方式 |
|------|---------|---------|
| FTS5 | 是 | `SQLITE_ENABLE_FTS5` |
| R-Tree | 是 | `SQLITE_ENABLE_RTREE` |
| JSON1 | 是（3.38+） | `SQLITE_ENABLE_JSON1` |
| GEOPOLY | 是 | `SQLITE_ENABLE_GEOPOLY` |
| ICU | 否 | 链接 libicu，单独加载 |
| RegExp | 否 | 加载 sqlite3_re |

这与 PostgreSQL 的 `CREATE EXTENSION` 是哲学相反的方向：SQLite 偏好编译期"全员入伙"，PostgreSQL 偏好运行时按需安装。

### 安全开关

由于嵌入式部署的特殊性，许多发行版把 `SQLITE_OMIT_LOAD_EXTENSION` 编译宏打开（如 macOS 内置的 sqlite），完全禁用扩展加载——这避免了 web 应用沙箱被 SQLite 扩展绕过。

### 扩展生态

- **SQLean**：常用扩展集合（fileio、crypto、stats、ulid 等）
- **sqlite-vec**：向量搜索
- **libduckdb-sqlite**：在 SQLite 进程内运行 DuckDB 查询
- **Spatialite**：完整 GIS 扩展，依赖 Geos/Proj/libxml2

## DB2：FENCED / UNFENCED 双模型

DB2 是首批形式化"沙箱级别"的商用数据库之一。它把外部 C 函数划分为：

- **FENCED**：在独立的 `db2fmp` 子进程内运行，崩溃不影响主进程
- **NOT FENCED / UNFENCED**：在数据库进程内运行，性能最高

### DDL

```sql
CREATE FUNCTION my_add(INT, INT) RETURNS INT
EXTERNAL NAME 'mylib!my_add'
LANGUAGE C
PARAMETER STYLE SQL
DETERMINISTIC
NO SQL
NOT FENCED
ALLOW PARALLEL;
```

`mylib!my_add` 中的 `!` 是 DB2 特有的库名/符号分隔符，等价于 PostgreSQL 的逗号分隔。

### FENCED 进程模型

- `db2fmp` 守护进程在 db2sysc 启动时一同 fork
- 每个 FENCED 函数调用通过共享内存 + 信号量做参数传递
- 崩溃时 db2fmp 重启，原 SQL 报 `SQL1131N`（agent 故障）但数据库继续运行
- 多个 FENCED 函数可在同一 db2fmp 进程内复用，避免反复 fork

### 配置

```sql
-- 创建时强制 FENCED（管理员策略）
ALTER FUNCTION my_add FENCED;
ALTER FUNCTION my_add NOT FENCED;        -- 需 SECADM

-- 默认值（DB cfg）
db2 update db cfg using KEEPFENCED YES;  -- 不退出 db2fmp
```

### 何时选 NOT FENCED

- 函数已经过严格验证（生产稳定）
- 极度高频调用（避免 IPC 开销）
- 需要访问数据库内部 SQL（NOT FENCED 才允许 `MODIFIES SQL DATA`）

何时必须 FENCED：

- 第三方未审计代码
- 调用 OS 资源（网络、文件）
- 测试期间

DB2 的这套设计是 PG 没有的"细粒度信任分层"。

## ClickHouse：编译期 plugin + 进程外 executable UDF

ClickHouse 的 **C++ plugin** 不是运行时 dlopen 的，而是编译期静态链接到 clickhouse-server 二进制。这是与 PG/MySQL 完全不同的设计哲学。

### 编译期 plugin

```bash
# 在 ClickHouse 源码树中
cd contrib/my-plugin
cmake .. -DENABLE_MYPLUGIN=ON
ninja clickhouse-server
```

新功能编译进二进制 → 重启 → 生效。这是为什么 ClickHouse 文档里几乎没有"扩展"章节——它的扩展性是源码级别的。

### Executable UDF（21.11+）

为了不要求用户改源码，ClickHouse 21.11（2021）引入 **executable user-defined functions**：通过 fork/exec 启动外部进程，stdin/stdout 批量传递数据：

```xml
<!-- /etc/clickhouse-server/user_defined_functions.xml -->
<functions>
  <function>
    <type>executable</type>
    <name>py_metaphon</name>
    <return_type>String</return_type>
    <argument><type>String</type></argument>
    <format>TabSeparated</format>
    <command>python3 /var/lib/ch/metaphon.py</command>
    <execute_direct>1</execute_direct>
  </function>
</functions>
```

```sql
SELECT py_metaphon(name) FROM users;
```

### 设计要点

- **批处理**：每次调用送整批，摊薄启动成本（启动 ~5-50ms）
- **多种格式**：TabSeparated、JSONEachRow、Native、Parquet
- **任意语言**：bash、python3、go binary、自写程序均可
- **崩溃隔离**：子进程 SIGSEGV 不影响 ClickHouse 主进程
- **没有 dlopen**：与共享库完全解耦

`<type>` 还可选 `executable_pool`，复用进程减少启动开销：

```xml
<type>executable_pool</type>
<pool_size>10</pool_size>
```

### 设计动机

ClickHouse 团队明确表态：**不会引入 dlopen 式插件加载**。原因：

1. C++ ABI 不稳定（Itanium ABI 跨编译器版本仍有差异）
2. 全局符号污染容易导致 RTTI 冲突
3. 用户写 C++ 容易因内存泄漏/野指针搞垮服务

executable UDF 是它折中的方案——拥抱"任何语言"的同时保留隔离性。

## DuckDB：扩展系统与签名加载

DuckDB 自 0.3（2021）起提供完整的扩展机制，特点是数字签名 + 自动下载：

```sql
-- 安装（首次从 https://extensions.duckdb.org 下载）
INSTALL httpfs;
INSTALL spatial;
INSTALL fts;

-- 加载到当前进程
LOAD httpfs;
LOAD spatial;
LOAD fts;

-- 使用
SELECT * FROM read_parquet('s3://bucket/data.parquet');
SELECT ST_Distance(p1.geom, p2.geom) FROM places p1, places p2;
```

### 安全模型

DuckDB 把扩展分两类：

- **Signed extensions**：DuckDB 团队签名的官方扩展，默认允许加载
- **Unsigned extensions**：第三方未签名扩展，需要显式 `SET allow_unsigned_extensions = true;`

```sql
SET allow_unsigned_extensions = true;
LOAD '/path/to/my_unsigned_ext.duckdb_extension';
```

签名机制：

- 每个 `.duckdb_extension` 文件附带 256 字节 RSA 签名
- DuckDB 二进制内嵌 DuckDB 团队的公钥
- 加载时校验签名，失败拒绝加载
- 这是 PostgreSQL/MySQL 都没有的安全设计

### 扩展开发

```cpp
// my_ext/my_ext.cpp
#define DUCKDB_EXTENSION_MAIN
#include "duckdb.hpp"
using namespace duckdb;

class MyExtension : public Extension {
public:
    void Load(DuckDB &db) override {
        Connection con(db);
        con.CreateScalarFunction<string_t, string_t>("myupper",
            [](string_t s) { return string_t(s.GetString().c_str()); });
    }
    string Name() override { return "my_ext"; }
};

extern "C" {
DUCKDB_EXTENSION_API void my_ext_init(duckdb::DatabaseInstance &db) {
    Connection con(db);
    /* register functions */
}
DUCKDB_EXTENSION_API const char *my_ext_version() {
    return DuckDB::LibraryVersion();
}
}
```

`my_ext_version()` 返回当前编译时的 DuckDB 版本，运行时与 server 版本对比，不匹配拒绝加载。这是 DuckDB 的 ABI 兼容防线。

### 扩展生态

| 扩展 | 用途 | 类型 |
|------|------|------|
| httpfs | HTTP/S3/Azure 读取 | 官方 |
| spatial | GIS 函数（GEOS） | 官方 |
| fts | 全文搜索 | 官方 |
| json | JSON 函数 | 官方 |
| parquet | Parquet 读写 | 官方（多内置） |
| postgres_scanner | 直接读 PG | 官方 |
| iceberg | Apache Iceberg | 官方 |
| delta | Delta Lake | 官方 |
| sqlite_scanner | 直接读 SQLite | 官方 |
| icu | ICU 国际化 | 官方 |
| autocomplete | shell 补全 | 官方 |
| substrait | Substrait 计划交换 | 官方 |
| arrow | Arrow Flight 接口 | 官方 |
| 第三方 | 用户自建 | 需 unsigned |

## SingleStore：C 共享库 + Wasm 双路径

SingleStore（前 MemSQL）支持两条原生扩展路径：

1. **传统 C/C++ 共享库**：`.so` + `LANGUAGE C`
2. **Wasm**（8.1+）：`.wasm` + `AS WASM FROM`

### Wasm 路径

```sql
CREATE FUNCTION power_mod(base BIGINT, exp BIGINT, m BIGINT) RETURNS BIGINT
AS WASM FROM 'power_mod.wasm'
WITH (HANDLER = 'power_mod');
```

SingleStore 是首批商用 Wasm UDF 数据库，主推 Rust 编译为 Wasm。原生 C 共享库仍保留但不再主推——Wasm 提供同等性能 + 沙箱化。

## Vertica：UDx 与 Fenced 容器

Vertica 的 **UDx (User Defined Extension)** 是工业级最完整的 C++ 扩展框架之一：

```sql
CREATE LIBRARY add2lib AS '/opt/vertica/sdk/examples/build/Add2Ints.so';

CREATE FUNCTION add2 AS LANGUAGE 'C++'
NAME 'Add2IntsFactory' LIBRARY add2lib FENCED;
```

```cpp
class Add2Ints : public ScalarFunction {
public:
    virtual void processBlock(ServerInterface &srv, BlockReader &arg_reader,
                              BlockWriter &res_writer) {
        do {
            vint a = arg_reader.getIntRef(0);
            vint b = arg_reader.getIntRef(1);
            res_writer.setInt(a + b);
            res_writer.next();
        } while (arg_reader.next());
    }
};
```

### Fenced 容器

UDx 默认 FENCED，运行在独立 cgroup 控制的进程组：

- 资源限制（CPU、内存、文件描述符）
- 崩溃自动重启
- 用户可显式 `UNFENCED`，但需 dbadmin 显式开权限

Vertica 的 UDx 与 Yellowbrick 一脉相承（Yellowbrick 团队源自 Vertica），二者 API 高度相似。

## Teradata：PROTECTED MODE

Teradata 的 C UDF 自 V2R5 起就有 **PROTECTED / UNPROTECTED MODE** 区分：

```sql
CREATE FUNCTION my_add(int, int) RETURNS int
LANGUAGE C
NO SQL
PARAMETER STYLE TD_GENERAL
EXTERNAL NAME 'CS!my_add!CO!my_add.c!OF!OBJECT'
PROTECTED;
```

- **PROTECTED MODE**：UDF 在专用 `udfsectsk` 进程组内运行
- **UNPROTECTED MODE**：在数据库 AMP 进程内运行（最快但无隔离）

Teradata 的 PROTECTED MODE 早于 DB2 的 FENCED 数年，是 MPP 数据仓库 UDF 隔离模型的先驱。

## Impala：HDFS 分发 + dlopen

Impala 的 C UDF 有一个独特设计——通过 HDFS 分发 `.so` 到所有节点：

```sql
CREATE FUNCTION my_lower(STRING) RETURNS STRING
LOCATION 'hdfs://my-cluster/udf/libmyudf.so'
SYMBOL='my_lower';
```

每个 impalad 节点收到 catalog 同步后，从 HDFS 下载 `.so` 到本地缓存目录，再 `dlopen` 加载。这避免了"每个节点单独安装"的运维负担——但也意味着 HDFS 必须可访问且 `.so` 必须为 Linux x86_64 单架构。

## MonetDB：MAL 模块加载

MonetDB 的扩展机制基于其内部代数语言 **MAL (Monet Assembly Language)**。每个 MAL 模块可以是纯 MAL 脚本，也可以是 C 函数包装：

```c
str MyFunctions_my_upper(Client cntxt, MalBlkPtr mb, MalStkPtr stk, InstrPtr pci) {
    str *res = getArgReference_str(stk, pci, 0);
    str s   = *getArgReference_str(stk, pci, 1);
    *res = GDKstrdup(s);
    /* ... */
    return MAL_SUCCEED;
}

mel_func myfunctions_init_funcs[] = {
    pattern("myfuncs", "my_upper", MyFunctions_my_upper, false, "my upper",
            args(1, 2, arg("",str), arg("s",str))),
    { .imp = NULL }
};
```

加载时 MonetDB 直接 dlopen 对应的 `.so` 并扫描 `*_init_funcs[]` 数组。这种"模块自描述"风格类似 PG 的 `_PG_init`，但与 BAT (Binary Association Table) 数据结构紧密耦合。

## Informix / Firebird：经典 IDS DataBlade 与 UDR

### Informix DataBlade

Informix 的 **DataBlade** 是 90 年代最早的"对象关系型扩展"，每个 DataBlade 是一个 `.bld` 包（实质上是 .so + 配置文件 + SQL DDL）。Bladelet 用 C 写，通过 `bladeunpack` 安装到数据库：

```sql
CREATE FUNCTION my_distance(POINT, POINT) RETURNING REAL
EXTERNAL NAME '/path/myblade.so(my_distance)'
LANGUAGE C;
```

经典 DataBlade：TimeSeries、Spatial、Web、Excalibur Text Search。

### Firebird UDR

Firebird 3.0 用 **UDR (User Defined Routine)** 取代了 1.0/2.x 的旧 UDF。UDR 提供：

- 现代 C++ 接口
- 严格的内存所有权
- 错误回传机制
- Java/.NET 桥接（通过 Plugin Manager）

```sql
CREATE FUNCTION my_upper(s VARCHAR(100)) RETURNS VARCHAR(100)
EXTERNAL NAME 'mylib!my_upper'
ENGINE UDR;
```

旧的 `DECLARE EXTERNAL FUNCTION` 在 Firebird 4.0 已弃用。

## SAP HANA：AFL 库

SAP HANA 的 **Application Function Library (AFL)** 是其原生 C++ 扩展机制，主要用于：

- 预测分析库（PAL）
- 业务函数库（BFL）
- 自定义企业计算

AFL 不是公开 API——只有大客户和合作伙伴在 SAP 协助下开发。安装通过 HANA Studio 或 hdbalm 工具，类似 RPM 包管理。这与 PG 开放扩展生态形成鲜明对比。

## Exasol：Script Container

Exasol 把所有外部代码都装进 **Script Container**（基于 LXC）。容器内可以是 C++、Python、R、Lua、Java：

```sql
OPEN SCHEMA myudf;

CREATE C++ SCALAR SCRIPT my_add(a INT, b INT) RETURNS INT AS
    #include "ScriptInterface.h"
    extern "C" int my_add(int a, int b) { return a + b; }
/

SELECT myudf.my_add(1, 2);
```

容器化设计的好处：

- 完整 OS 命名空间隔离
- CPU/内存/文件 cgroup 限制
- 任意第三方库 yum/pip install
- 崩溃完全隔离

代价是：每次 UDF 首次调用启动容器约 200-500ms，长期运行后通过 connection pool 缓存。

## CREATE LIBRARY DDL 深入

### Oracle：完整 CREATE LIBRARY

```sql
-- 创建库（定义路径）
CREATE OR REPLACE LIBRARY mathlib
AS '/u01/oracle/ext/libmath.so'
AGENT 'extproc_dedicated';   -- 12c+ 可指定 extproc 实例

-- 查看库
SELECT object_name, status FROM user_libraries;

-- 修改库
ALTER LIBRARY mathlib EDITIONABLE;

-- 删除库（级联删除依赖函数）
DROP LIBRARY mathlib;
```

`AGENT` 子句在 12c 引入，允许把不同的库分配到不同的 extproc 进程，实现资源/权限分组。

### Vertica：CREATE LIBRARY 与 DEPENDS

```sql
CREATE OR REPLACE LIBRARY mylib
AS '/path/lib.so'
DEPENDS '/path/dep1.so:/path/dep2.so'
LANGUAGE 'C++';
```

`DEPENDS` 列出额外依赖库，Vertica 会在 dlopen 时同时加载。这避免了系统库版本冲突。

### PostgreSQL：没有 CREATE LIBRARY

PG 选择把库路径直接嵌入 CREATE FUNCTION：

```sql
CREATE FUNCTION sqrt_plus(double precision) RETURNS double precision
AS '$libdir/mathext', 'sqrt_plus'    -- 库 + 符号
LANGUAGE C;
```

优点是简单，缺点是同一个 .so 的不同函数定义中如果路径不一致，可能加载多份副本。`CREATE EXTENSION` 部分缓解了这个问题。

## ABI 与版本兼容深入

### PG_MODULE_MAGIC 详解

```c
/* fmgr.h（节选） */
typedef struct {
    int     len;                        /* magic 结构体长度 */
    int     version;                    /* PostgreSQL 主版本 */
    int     funcmaxargs;                /* FUNC_MAX_ARGS（默认 100） */
    int     indexmaxkeys;               /* INDEX_MAX_KEYS（默认 32） */
    int     namedatalen;                /* NAMEDATALEN（默认 64） */
    int     float8byval;                /* USE_FLOAT8_BYVAL（平台相关） */
    char    abi_extra[ABI_EXTRA_LEN];   /* 17+：版本字符串 */
} Pg_magic_struct;
```

每个 PostgreSQL 大版本编译都会生成不同的魔数。运行时加载 `.so` 时，`internal_load_library` 调用：

```c
const Pg_magic_struct *m = PG_MAGIC_FUNCTION_SYMBOL(); /* dlsym Pg_magic_func */
if (m->len != sizeof(Pg_magic_struct) ||
    m->version != PG_VERSION_NUM / 100 ||
    m->funcmaxargs != FUNC_MAX_ARGS ||
    /* ... */) {
    ereport(ERROR, (errmsg("incompatible library \"%s\"", filename)));
}
```

任何字段不匹配都会拒绝加载。这意味着：

- PG 14 的扩展不能在 PG 15 服务器上加载（version 不同）
- 自定义编译时改了 `FUNC_MAX_ARGS` 必须重新编译扩展
- 32 位 vs 64 位混用必然失败

### MySQL UDF ABI

MySQL 没有像 PG 那样的强魔数检查，但通过：

- **mysql.h 头文件版本宏**：编译期检查
- **CHARSET_INFO 结构**：5.6 → 5.7 → 8.0 字段顺序保持兼容
- **plugin_dir 二进制扫描**：启动时 `dlopen` 失败则忽略该项

这导致 MySQL UDF 通常需要在每个大版本重新编译，但运行时报错较少（直接段错误）。

### DuckDB 扩展版本

```c
DUCKDB_EXTENSION_API const char *my_ext_version() {
    return DuckDB::LibraryVersion();    // 运行时返回编译时版本
}
```

DuckDB 主进程运行时调用 `my_ext_version()`，对比自己的 `LibraryVersion()`，不一致就拒绝。这是结合签名的双重保护。

### SQLite 兼容性

SQLite 是**唯一**承诺扩展跨多个版本兼容的数据库。`sqlite3ext.h` 中的 `sqlite3_api_routines` 结构体只追加不删除，旧扩展在新 SQLite 上通常仍可加载。这是 SQLite 嵌入式哲学的一部分。

## 调用约定与参数传递

### PG 的 V0 vs V1

PostgreSQL 早期（< 7.x）使用 V0 约定——直接 C 函数签名。V1（现行）通过 `PG_FUNCTION_ARGS` 宏统一参数：

```c
/* V0：已弃用 */
int v0_add(int a, int b) { return a + b; }

/* V1：现行 */
PG_FUNCTION_INFO_V1(v1_add);
Datum v1_add(PG_FUNCTION_ARGS) {
    int32 a = PG_GETARG_INT32(0);
    int32 b = PG_GETARG_INT32(1);
    PG_RETURN_INT32(a + b);
}
```

V1 的优势：

- **NULL 处理**：`PG_ARGISNULL(n)` 检查空值
- **可变参数**：函数可声明任意 PARAMETER 数
- **Toast 数据**：`PG_GETARG_TEXT_PP` 自动处理 short header
- **集合返回**：SRF（Set Returning Function）需要 V1

### MySQL UDF 参数

MySQL UDF 通过 `UDF_ARGS` 结构传参：

```c
struct UDF_ARGS {
    unsigned int   arg_count;          // 参数个数
    enum Item_result *arg_type;         // 类型数组
    char         **args;                // 值指针数组
    unsigned long *lengths;             // 字符串长度
    char          *maybe_null;          // NULL 标志
    char         **attributes;          // 列属性
    unsigned long *attribute_lengths;
    void          *extension;           // 8.0+ 保留扩展
};
```

字符串参数通过 `args[i]` + `lengths[i]` 传递（不必 NULL 终止）。返回值通过 `result` + `length` 双输出。

### Oracle EXTPROC 参数

Oracle 通过 OCI 类型映射 PL/SQL ↔ C：

```sql
CREATE FUNCTION test(x NUMBER) RETURN NUMBER
AS LANGUAGE C
LIBRARY mylib NAME "test"
PARAMETERS (
    x         OCINUMBER,        -- 数字 → OCINumber
    RETURN    OCINUMBER,
    INDICATOR x INT,            -- NULL 标志
    LENGTH    x INT,            -- 字符串长度
    CONTEXT                     -- OCI 上下文
);
```

通过 OCI API 解析 OCINumber，再用 OCI 函数转换为 double。这套设计虽然冗长但极度严格——任何类型不匹配都在编译期拦截。

### DB2 PARAMETER STYLE

DB2 提供多种参数风格：

- **PARAMETER STYLE SQL**：参数 + null 指示器 + 状态
- **PARAMETER STYLE GENERAL**：仅参数（不支持 NULL 输入）
- **PARAMETER STYLE GENERAL WITH NULLS**：通用 + NULL 指示器
- **PARAMETER STYLE DB2GENERAL**：与 DB2 7.x 兼容
- **PARAMETER STYLE JAVA**：Java UDF 专用

```sql
CREATE FUNCTION add(INT, INT) RETURNS INT
EXTERNAL NAME 'mylib!add'
LANGUAGE C
PARAMETER STYLE SQL
DETERMINISTIC NO SQL;
```

`PARAMETER STYLE SQL` 的 C 签名为：

```c
void add(SQLINTEGER *a, SQLINTEGER *b, SQLINTEGER *result,
         short *anull, short *bnull, short *resnull,
         SQLINTEGER *sqlstate, char *funcname, char *specname,
         char *msgtext);
```

这种"全字段都传指针"的风格继承自 SQL/PSM 标准，是 DB2/Informix 共有的传统。

## 安全模型深入

### 进程内加载的根本风险

PostgreSQL/MySQL/SQLite 等"进程内 dlopen"模式承担三重风险：

**1. 内存损坏**

```c
/* 一个野指针毁掉数据库进程 */
PG_FUNCTION_INFO_V1(crash);
Datum crash(PG_FUNCTION_ARGS) {
    int *bad = (int*)0xdeadbeef;
    *bad = 42;          /* SIGSEGV → 整个 PG 进程退出 */
    PG_RETURN_NULL();
}
```

**2. 数据泄露**

UDF 拥有数据库进程的全部内存读取能力——可以读取 shared buffers 中的任意页，读取 `pg_authid` 密码哈希、加密密钥、其他用户的查询计划。

```c
PG_FUNCTION_INFO_V1(read_shared);
Datum read_shared(PG_FUNCTION_ARGS) {
    /* 直接访问 shared memory 是允许的 */
    BufferDesc *desc = GetBufferDescriptor(0);
    /* ... 读出任意表的内容 ... */
}
```

**3. 命令执行**

```c
PG_FUNCTION_INFO_V1(rce);
Datum rce(PG_FUNCTION_ARGS) {
    system("rm -rf /var/lib/postgresql/data");
    PG_RETURN_VOID();
}
```

引擎只能依赖 `superuser` 权限要求作为唯一边界——一旦获得 `CREATE FUNCTION ... LANGUAGE C` 权限就等同于操作系统级访问。

### 进程外加载的保护

Oracle EXTPROC、DB2 FENCED、Vertica Fenced UDx、Teradata PROTECTED MODE 通过子进程隔离把上述风险局限在子进程内：

| 风险 | 进程内 | 进程外 |
|------|-------|-------|
| SIGSEGV | 整个数据库崩溃 | 仅子进程退出 |
| 内存窃读 | 全数据库内存 | 仅本次调用上下文 |
| RCE | 数据库进程权限 | 子进程权限（可设独立用户） |
| 性能开销 | ~50ns 调用 | ~100-500μs RPC |

折中：FENCED 子进程 + 共享内存通信，把 RPC 缩到 ~10μs，是 DB2/Teradata 的设计。

### 容器化进一步隔离

Vertica Fenced UDx、Exasol Script Container、Snowpark Container Services 把 UDF 装进 cgroup/容器：

| 隔离维度 | 进程外 | 容器化 |
|---------|-------|-------|
| CPU | 共享 | cgroup 限制 |
| 内存 | 共享 | cgroup 限制 |
| 文件系统 | 共享 | mount namespace |
| 网络 | 共享 | network namespace（可选） |
| PID | 共享 | PID namespace |
| User | 共享 | user namespace |

这种隔离允许"安装任意 pip/npm 包"——即便 UDF 内 `os.system('rm -rf /')` 也只影响容器内文件，不影响数据库实例。

### 信号处理与 Hook

C 扩展中调用 `signal()` 注册 SIGINT/SIGTERM handler 是危险的——会覆盖数据库自身的信号处理，破坏 graceful shutdown。PG 文档明确禁止这一点，但语言层面无法阻止。

类似地，重写 `errno`、覆盖 `malloc/free` 钩子、注册 atexit 都可能带来灾难性副作用。

## 链接器副作用

### RTLD_GLOBAL vs RTLD_LOCAL

PostgreSQL 默认用 `RTLD_NOW | RTLD_GLOBAL` 加载扩展：

- `RTLD_NOW`：立即解析所有未定义符号，避免延后崩溃
- `RTLD_GLOBAL`：扩展导出的符号对后续加载的扩展可见

`RTLD_GLOBAL` 是双刃剑：

- **优点**：扩展间可互相依赖（PostGIS 依赖 liblwgeom，第二个扩展可重用）
- **缺点**：不同扩展同名符号冲突（两个扩展都叫 `init_helper` 就崩）

DB2 倾向于 `RTLD_LOCAL` 加上显式 `EXTERNAL NAME 'lib!sym'` 路径，避免命名空间污染。

### TLS 模型

C 扩展中 `__thread` 变量的初始化时机：

- 静态 TLS：可执行文件 + 启动时加载的 .so → DTV 槽位预分配
- 动态 TLS：`dlopen` 后加载的 .so → 第一次访问时分配

PG 的 `shared_preload_libraries` 列出的扩展是静态 TLS（更快），运行时 `LOAD` 的扩展是动态 TLS。某些古老的 glibc 版本对动态 TLS 的支持有 bug，导致信号处理 + TLS 组合崩溃。

### 全局构造函数

C++ 扩展中的全局对象会在 dlopen 时调用其构造函数：

```cpp
class MyInit {
public:
    MyInit() {
        std::cout << "loaded\n";   // 在 dlopen 时执行
    }
};
static MyInit __attribute__((init_priority(101))) g_init;
```

如果构造函数抛异常或耗时，会导致 dlopen 阻塞或失败。许多引擎（PG、DB2）建议**纯 C 接口**避开这一陷阱。

### 符号版本控制

GNU ld 支持 `.symver` 指令：

```c
__asm__(".symver my_add_v1, my_add@MY_LIB_1.0");
__asm__(".symver my_add_v2, my_add@@MY_LIB_2.0");
```

数据库扩展极少使用——因为 PG/MySQL/Oracle 都通过自己的 ABI 魔数解决版本问题，符号级版本反而带来复杂度。

## 关键发现

### 1. 共享库加载是云数据库的"红线"

Snowflake、BigQuery、Redshift、Databricks、Athena、Synapse、Spanner、Materialize 全部禁止用户加载本地 `.so`。原因不是技术做不到，而是云厂商需要保证多租户安全和 SLA——一个用户的 SIGSEGV 不能影响其他用户。云厂商替代方案是 JS UDF（V8 沙箱）、Snowpark Container（容器）、Remote Function（HTTPS）。

### 2. PostgreSQL 是 C 扩展的"金标准"

`PG_MODULE_MAGIC` + V1 调用约定 + `CREATE EXTENSION` + `Hooks` 系统组合起来，是过去 30 年最成熟的 SQL 引擎扩展机制。它孕育了 PostGIS、TimescaleDB、Citus、pgvector、pg_trgm 等无数行业级扩展，影响了 Greenplum、Yugabyte、Cockroach 等众多衍生产品。

### 3. Oracle 的 extproc 是隔离设计的先驱

1999 年 Oracle 8i 引入 EXTPROC 子进程模型，比 DB2 FENCED（2001 V8）和 Teradata PROTECTED MODE（2002 V2R5）都早，是商用数据库中最早把"外部代码进程隔离"形式化的设计。代价是 RPC 开销，但安全收益巨大。

### 4. SQL Server CLR 走向边缘

2005 引入的 CLR 是 SQL Server 最雄心勃勃的扩展机制，但 2017 起的 `clr strict security`、Azure SQL 的限制、微软对 ML Services / JS UDF 的押注，让 CLR 实际上进入"维护模式"。新项目应优先选择 ML Services + Spark + Python UDF。

### 5. MySQL UDF 是开源 OLTP 中最早的 dlopen 设计

MySQL 5.0（2005）的 UDF SONAME 是开源关系数据库中最早的运行时共享库加载机制——比 PG 9.1 的 CREATE EXTENSION 早 6 年。其 `mysql.func` 设计简单实用，但安全模型偏弱（mysql.func 直接 INSERT 在 5.7 前可绕过）。MariaDB 完整继承且扩展。

### 6. SQLite 的"默认禁用"哲学

SQLite 是嵌入式数据库，所以选择"默认禁用扩展加载"——通过 `sqlite3_enable_load_extension(db, 1)` 显式开启，且许多发行版（macOS 内置 sqlite）直接编译禁用。这与服务器数据库"默认开启 + 权限管理"完全相反，反映了嵌入式场景的安全约束。

### 7. ClickHouse 拒绝 dlopen

ClickHouse 团队明确拒绝 dlopen 式插件——理由是 C++ ABI 不稳定、内存安全难以保证。它选择 fork/exec 进程外 executable UDF + 编译期源码插件的混合策略。这种"宁可慢一点也要安全"的工程哲学很 ClickHouse。

### 8. DuckDB 的签名扩展是新方向

DuckDB 是首个引入"扩展数字签名验证"的开源 SQL 数据库。这填补了 PG/MySQL "信任 superuser 即信任 .so" 的安全缺口。配合自动从 `extensions.duckdb.org` CDN 下载，达到了"扩展即可信下载源 + 本地签名校验"的现代软件供应链安全标准。

### 9. Vertica/Yellowbrick/DB2/Teradata：FENCED 是 MPP 标配

四家 MPP 数据仓库（Vertica、Yellowbrick、DB2、Teradata）都把 FENCED/PROTECTED 子进程作为默认。原因：MPP 集群中单节点崩溃会导致整个查询重试，进程隔离的 ROI 远高于 OLTP。

### 10. ABI 兼容是无尽的运维负担

PG_MODULE_MAGIC、MySQL plugin 版本、SQLite api routine、DuckDB extension version——所有引擎都需要在大版本升级时强制重编译扩展。这导致：

- 生产环境升级数据库 = 全部 .so 同步升级
- 第三方扩展生态（PostGIS、TimescaleDB）必须紧跟 PG 大版本
- 长尾扩展常常落后 1-2 个大版本，制约用户升级

这是共享库加载机制无法避免的天然成本，也是 Wasm UDF（与引擎版本解耦）潜在的核心吸引力。

### 11. CREATE LIBRARY 体现了 ANSI SQL/PSM 影响

Oracle 8i、Vertica、Yellowbrick 选择"先 CREATE LIBRARY 再 CREATE FUNCTION"两步式 DDL，这继承自 SQL/PSM 标准的命名空间设计。PostgreSQL/MySQL/Teradata 选择把库路径直接写在 CREATE FUNCTION 中——简洁但缺乏复用。两种风格都有合理性，反映了 90 年代 ANSI SQL 委员会与各厂商的历史分歧。

### 12. 嵌入式 vs 服务器模式扩展机制差异

| 维度 | SQLite (嵌入式) | PostgreSQL (服务器) |
|------|---------------|---------------------|
| 默认加载 | 禁用 | 允许（superuser） |
| 信任模型 | 应用沙箱内 | 数据库 superuser |
| 加载粒度 | 每 connection | 整个数据库 |
| 卸载 | 关闭 connection | DROP EXTENSION |
| 集成 | 应用代码内 | DDL 语句 |

嵌入式设计哲学是"数据库依附于应用，应用沙箱即数据库沙箱"；服务器设计哲学是"数据库是独立服务，需要自己的权限模型"。这种根本差异决定了两者扩展机制的对立设计。

## 总结对比矩阵

### 共享库加载能力总览

| 能力 | PostgreSQL | Oracle | SQL Server | MySQL | DB2 | SQLite | DuckDB | ClickHouse | Vertica | Teradata |
|------|-----------|--------|-----------|-------|-----|--------|--------|------------|---------|---------|
| .so/.dll 加载 | 是 | extproc | -- (CLR) | 是 | 是 | API | 签名 | -- | 是 | 是 |
| 进程隔离 | -- | 是 | AppDomain | -- | FENCED | -- | -- | exec UDF | Fenced | PROTECTED |
| 数字签名 | -- | -- | StrongName | -- | -- | -- | 是 | -- | -- | -- |
| 在线加载 | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 重启 | 是 | 重启 |
| 跨小版本 | 是 | 是 | 是 | 通常是 | 是 | 是 | 是 | -- | 是 | 是 |
| 跨大版本 | 否 | 协议层 | -- | 否 | 编译宏 | 通常是 | 否 | -- | 否 | 否 |
| ABI 魔数 | 强 | 协议 | StrongName | 弱 | 头文件 | API 版本 | 是 | -- | 是 | 是 |
| CREATE LIBRARY | -- | 是 | 是 (ASM) | -- | -- | -- | -- | -- | 是 | -- |

### 安全模型对比

| 引擎 | 默认权限 | 隔离方式 | 沙箱 | 容器 |
|------|---------|---------|------|------|
| PostgreSQL | superuser | 无 | 无 | -- |
| Oracle | DBA + extproc 配置 | 子进程 | 无 | -- |
| SQL Server | sysadmin + 签名 | AppDomain | CAS | -- |
| MySQL | SUPER + plugin_dir | 无 | 无 | -- |
| DB2 | DBADM | FENCED 子进程 | 无 | -- |
| SQLite | 编译期 + API 显式启用 | 无 | 无 | 应用沙箱 |
| DuckDB | 默认仅签名扩展 | 无 | 无 | -- |
| Vertica | dbadmin + Fenced | 子进程组 | 无 | cgroup |
| Teradata | DBC 用户 + PROTECTED | 子进程 | 无 | -- |
| Exasol | 任意用户 + 容器 | 子进程 | 无 | LXC |
| Snowpark Container | 任意用户 | -- | -- | K8s Pod |

### 引擎选型建议

| 场景 | 推荐 | 原因 |
|------|------|------|
| 高性能 + 内嵌生态 | PostgreSQL + pgrx | C ABI 稳定，生态最广 |
| 严格隔离 + 商用 OLTP | Oracle EXTPROC | 子进程隔离，企业级运维 |
| MPP 数仓 + 容器化 | Vertica Fenced UDx | cgroup + UDx 完整框架 |
| 嵌入式 + 按需加载 | SQLite + load_extension | 默认禁用，应用控制 |
| 现代签名安全 | DuckDB 扩展 | 自动下载 + 签名验证 |
| OLAP + 任意语言 | ClickHouse executable UDF | fork + stdin/stdout，崩溃隔离 |
| 跨平台沙箱 | SingleStore Wasm / DatabendDB Wasm | Wasm 解耦 ABI |
| 已有 .NET 生态 | SQL Server CLR | 但应优先考虑 ML Services |
| 已有 Java 生态 | Trino/Spark/Hive 插件 | JVM 通用，不涉及 dlopen |
| 严格云托管 | Snowpark Container Services | 完整 K8s 隔离 |

## 参考资料

- PostgreSQL: [C-Language Functions](https://www.postgresql.org/docs/current/xfunc-c.html)
- PostgreSQL: [Extension Building Infrastructure](https://www.postgresql.org/docs/current/extend-pgxs.html)
- PostgreSQL: [LOAD command](https://www.postgresql.org/docs/current/sql-load.html)
- PostgreSQL: [PG_MODULE_MAGIC source](https://github.com/postgres/postgres/blob/master/src/include/fmgr.h)
- pgrx (Rust for PostgreSQL): https://github.com/pgcentralfoundation/pgrx
- Oracle: [External Procedures (extproc)](https://docs.oracle.com/en/database/oracle/oracle-database/19/adfns/calling-external-procedures.html)
- Oracle: [CREATE LIBRARY syntax](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/CREATE-LIBRARY.html)
- SQL Server: [CLR Integration Programming Model](https://learn.microsoft.com/en-us/sql/relational-databases/clr-integration/clr-integration-programming-model)
- SQL Server: [CREATE ASSEMBLY](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-assembly-transact-sql)
- SQL Server: [CLR strict security](https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/clr-strict-security)
- MySQL: [User-Defined Functions](https://dev.mysql.com/doc/refman/8.0/en/adding-loadable-function.html)
- MySQL: [CREATE FUNCTION (Loadable)](https://dev.mysql.com/doc/refman/8.0/en/create-function-loadable.html)
- MariaDB: [Creating User-Defined Functions](https://mariadb.com/kb/en/create-function-udf/)
- SQLite: [Run-Time Loadable Extensions](https://www.sqlite.org/loadext.html)
- SQLite: [sqlite3_load_extension API](https://www.sqlite.org/c3ref/load_extension.html)
- DB2: [External Functions](https://www.ibm.com/docs/en/db2/11.5?topic=routines-external-routines)
- DB2: [FENCED vs NOT FENCED](https://www.ibm.com/docs/en/db2/11.5?topic=routines-fenced-not-fenced)
- DuckDB: [Extensions](https://duckdb.org/docs/extensions/overview)
- DuckDB: [Building Extensions](https://duckdb.org/docs/extensions/working_with_extensions)
- ClickHouse: [Executable User Defined Functions](https://clickhouse.com/docs/en/sql-reference/functions/udf)
- Vertica: [Developing User-Defined Extensions](https://docs.vertica.com/latest/en/extending/developing-udxs/)
- Teradata: [User-Defined Functions](https://docs.teradata.com/r/Teradata-Database-SQL-External-Routine-Programming)
- SingleStore: [Wasm UDF](https://docs.singlestore.com/db/latest/reference/code-engine-powered-by-wasm/)
- Impala: [User-Defined Functions](https://impala.apache.org/docs/build/html/topics/impala_udf.html)
- MonetDB: [C UDFs](https://www.monetdb.org/documentation/user-guide/sql-functionality/user-defined-functions/)
- Firebird: [UDR (User Defined Routines)](https://firebirdsql.org/file/documentation/release_notes/html/en/3_0/rnfb30-engine-udr.html)
- Informix: [DataBlade Developers Kit](https://www.ibm.com/docs/en/informix-servers/14.10?topic=overview-datablade-modules)
- ISO/IEC 9075-2: SQL Standard - Foundation (CREATE FUNCTION clauses)
- ISO/IEC 9075-13: SQL Standard - Routines and Types Using Java
