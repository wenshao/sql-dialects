# 服务端配置文件 (Server Configuration Files)

数据库引擎的灵魂往往不在 SQL 语法里，而在那个不起眼的 `postgresql.conf`、`my.cnf` 或 `init.ora` 文件里。一个参数的差异，可能让相同的 SQL 在两台服务器上性能相差百倍——服务端配置文件是引擎对外暴露的"声明式旋钮"，是 DBA 与引擎对话的主要语言，也是引擎开发者必须仔细设计的元层接口。

## 配置的基础概念

### 声明式旋钮 (Declarative Knobs)

数据库的运行参数构成一个庞大的"旋钮空间"：

```
共享内存大小          shared_buffers = 4GB
WAL 提交模式          synchronous_commit = on
连接数上限            max_connections = 200
查询规划器开关        enable_hashjoin = on
日志级别              log_min_messages = warning
...
```

每个参数声明了引擎在某个维度上的行为偏好。这是一种声明式接口：用户只声明"想要什么"，不指定"如何实现"。引擎在启动或运行时读取这些声明，调整内部数据结构、算法选择、资源分配。

声明式旋钮的核心特征：

1. **正交性**：理想情况下每个参数独立可调，但实际上参数间存在隐式依赖（如 `shared_buffers` 与 `effective_cache_size`）
2. **类型化**：每个参数有明确的类型（整数、布尔、枚举、字符串、字节数）
3. **范围约束**：合法值有上下界（如 `max_connections` 通常 1-65535）
4. **作用域**：参数生效的层级（全局/数据库/角色/会话/语句）
5. **持久化**：是写入磁盘永久生效，还是仅本会话临时生效
6. **可发现性**：用户能否查询当前所有参数及其元数据

### 静态参数 vs 动态参数 (Static vs Dynamic)

参数按"修改后是否需要重启"分为两类：

```
静态参数 (Static / Restart-required):
  - 影响进程启动时分配的资源（共享内存大小、监听端口）
  - 影响数据文件物理结构（页大小、字符集编码）
  - 修改后必须重启服务进程

动态参数 (Dynamic / Reload-able):
  - 影响运行时行为（日志级别、查询超时、规划器开关）
  - 不涉及共享内存或数据文件结构
  - 可在运行时通过 reload / SIGHUP / SET 修改
```

PostgreSQL 在 `pg_settings.context` 列暴露了细粒度的作用域分类（`postmaster`、`sighup`、`backend`、`superuser`、`user`），是这个层级最完整的实现。

### Reload 语义 (Reload Semantics)

修改配置文件后，让新值生效的方式：

```
方式 1: 重启服务（最暴力，所有参数生效）
  - PostgreSQL: pg_ctl restart
  - MySQL: systemctl restart mysqld
  - Oracle: SHUTDOWN IMMEDIATE; STARTUP

方式 2: 信号 reload（中断更小，仅动态参数生效）
  - SIGHUP: PostgreSQL / MySQL（部分）/ ClickHouse
  - SIGUSR1/SIGUSR2: 其他控制信号

方式 3: SQL 命令 reload（连接级，无需 OS 权限）
  - PostgreSQL: SELECT pg_reload_conf();
  - MySQL: 无统一命令（部分参数可 SET GLOBAL）
  - Oracle: ALTER SYSTEM SET ... SCOPE=BOTH;
  - SQL Server: RECONFIGURE;

方式 4: 持久化 SQL 写法（写文件 + 运行时双重生效）
  - PostgreSQL: ALTER SYSTEM SET ...    -> 写入 postgresql.auto.conf
  - MySQL:      SET PERSIST var = val    -> 写入 mysqld-auto.cnf
  - Oracle:     ALTER SYSTEM SET ... SCOPE=BOTH  -> 写入 SPFILE
```

每种方式背后是不同的设计取舍：信号 reload 简单但需要 OS 权限；SQL reload 不需要 OS 权限但需要解析器入口；持久化 SQL 写法需要引擎管理 conf 文件的生命周期。

## SQL 标准的态度

SQL 标准（SQL:1999 / SQL:2003 / SQL:2023）对服务端配置文件**完全没有规定**：

- 没有定义"配置文件"的概念
- 没有规定参数命名空间（如 `max_connections` 还是 `MAX_CONNECTIONS`）
- 没有规定 reload 语法
- 没有规定参数查询方式（`pg_settings` vs `SHOW VARIABLES` vs `V$PARAMETER`）

唯一与之相关的标准条目是 SQL:1999 的 `SET <session characteristic>` 语句，但那只覆盖会话级属性，与服务端持久配置无关。结果就是各引擎按自己历史路径独立演化：

- Unix 风：纯文本 key=value 文件（`postgresql.conf`、`my.cnf`）
- Oracle 风：从文本 init.ora 演进到二进制 spfile.ora
- Windows 风：注册表 + 系统目录混用（SQL Server）
- XML 风：层次化 XML（ClickHouse `config.xml`）
- TOML 风：现代云数据库（TiDB `tidb.toml`）
- 无文件风：完全用 SQL 命令管理（CockroachDB cluster settings）

## 支持矩阵

### 配置文件位置与格式

| 引擎 | 主配置文件 | 格式 | 默认位置 (Unix) | 备注 |
|------|----------|------|---------------|------|
| PostgreSQL | postgresql.conf | key = value | $PGDATA/postgresql.conf | + postgresql.auto.conf, pg_hba.conf, pg_ident.conf |
| MySQL | my.cnf | INI | /etc/my.cnf, /etc/mysql/my.cnf, ~/.my.cnf | 支持 !include / !includedir |
| MariaDB | my.cnf | INI | 同 MySQL | 兼容 MySQL 路径搜索顺序 |
| Oracle | init.ora / spfile.ora | text / binary | $ORACLE_HOME/dbs/ | spfile 是二进制，禁手工编辑 |
| SQL Server | 注册表 + sys.configurations | binary | Windows 注册表 / mssql.conf (Linux) | sp_configure 为主接口 |
| SQLite | -- | -- | -- | 无配置文件，全部通过 PRAGMA |
| ClickHouse | config.xml + users.xml | XML | /etc/clickhouse-server/ | 支持 config.d/ 与 users.d/ 子目录 |
| DB2 | DB2 配置文件（DBM/DB CFG） | binary | /home/db2inst1/sqllib/ | UPDATE DBM CFG / DB CFG 命令 |
| CockroachDB | -- | -- | -- | 无文件，cluster settings + 启动 flag |
| TiDB | tidb.toml | TOML | /etc/tidb/tidb.toml | + cluster setting 通过 SET CLUSTER SETTING |
| OceanBase | observer.config.bin | binary | /home/admin/oceanbase/etc/ | 主要通过 ALTER SYSTEM SET |
| Snowflake | -- | -- | -- | 全托管，无可见配置文件 |
| BigQuery | -- | -- | -- | 全托管，仅暴露 Reservation API |
| Redshift | -- | -- | -- | Parameter Group（控制台/API） |
| DuckDB | -- | -- | -- | 进程内库，无独立 conf |
| Trino | config.properties + jvm.config + node.properties | properties | /etc/trino/ | 多文件分层 |
| Presto | 同 Trino | properties | /etc/presto/ | 同 Trino 起源 |
| Spark SQL | spark-defaults.conf | key value | $SPARK_HOME/conf/ | + log4j2.properties + spark-env.sh |
| Hive | hive-site.xml | XML | $HIVE_HOME/conf/ | + hive-env.sh + hivemetastore-site.xml |
| Flink SQL | flink-conf.yaml | YAML | $FLINK_HOME/conf/ | 完全 YAML |
| Databricks | cluster init script + Spark config | mixed | -- | 平台管理 |
| Teradata | dbscontrol fields | binary | -- | dbscontrol 工具操作 |
| Greenplum | postgresql.conf + pg_hba.conf | key = value | $MASTER_DATA_DIRECTORY/ | 继承 PG，gpconfig 工具 |
| YugabyteDB | postgresql.conf + tserver.conf + master.conf | key = value | -- | yb-tserver / yb-master 各有 flagfile |
| SingleStore | memsql.cnf | INI | /var/lib/memsql/ | 类 MySQL 文件 |
| Vertica | vertica.conf | key = value | /opt/vertica/config/ | + admintools 管理 |
| Impala | impala-flagfile / impalad-default.flgs | flagfile | /etc/impala/conf/ | 基于 gflags |
| StarRocks | be.conf + fe.conf | key=value | /opt/starrocks/{be,fe}/conf/ | BE/FE 分离 |
| Doris | be.conf + fe.conf | key=value | /opt/doris/{be,fe}/conf/ | 同 StarRocks 起源 |
| MonetDB | conf/monetdb5.conf | key=value | /etc/monetdb/ | 多数参数 monetdb 工具管理 |
| CrateDB | crate.yml | YAML | /etc/crate/ | YAML 风格 |
| TimescaleDB | postgresql.conf | key = value | $PGDATA/postgresql.conf | 继承 PG |
| QuestDB | server.conf | key=value | /opt/questdb/conf/ | 简单 properties |
| Exasol | EXAConf | INI-like | -- | EXAClusterOS 集群管理 |
| SAP HANA | global.ini, indexserver.ini, ... | INI | /usr/sap/$SID/SYS/global/hdb/custom/config/ | 多 ini 分层 |
| Informix | onconfig | key value | $INFORMIXDIR/etc/ | onmode -wf / onmode -wm |
| Firebird | firebird.conf + databases.conf | key = value | /etc/firebird/ | 单文件 |
| H2 | -- | -- | -- | 嵌入式，URL 参数为主 |
| HSQLDB | server.properties | properties | -- | 嵌入式可选文件 |
| Derby | derby.properties | properties | -- | 系统级 + 数据库级 properties |
| Amazon Athena | -- | -- | -- | 全托管，Workgroup 配置 |
| Azure Synapse | -- | -- | -- | 全托管，DB-scoped configurations |
| Google Spanner | -- | -- | -- | 全托管，Instance config |
| Materialize | -- | -- | -- | 全托管/CLI 启动 flag |
| RisingWave | risingwave.toml | TOML | -- | 系统参数 + SET CLUSTER SETTING |
| InfluxDB (SQL) | config.toml | TOML | /etc/influxdb/ | TOML 配置 |
| Databend | databend-query.toml + databend-meta.toml | TOML | /etc/databend/ | 分 query / meta 两层 |
| Yellowbrick | -- | -- | -- | 控制台 + Parameter Group |
| Firebolt | -- | -- | -- | 全托管，Engine setting |
| Tarantool | box.cfg{} | Lua | -- | Lua 表（独特模型） |
| Cassandra | cassandra.yaml | YAML | /etc/cassandra/ | 同集群一致 |
| MongoDB | mongod.conf | YAML | /etc/mongod.conf | YAML key:value |

> 共统计约 50 个引擎，其中约 12 个是全托管或嵌入式无独立配置文件，约 38 个有可识别的配置文件入口。

### SQL 级配置查询视图

通过 SQL 查询当前生效的配置参数及元信息：

| 引擎 | 查询接口 | 元信息列 | 可写权限 |
|------|---------|---------|---------|
| PostgreSQL | `pg_settings` 视图 / `SHOW` / `SHOW ALL` | name, setting, unit, context, source, min_val, max_val, enumvals, boot_val, reset_val | 超级用户/owner |
| MySQL | `SHOW VARIABLES` / `performance_schema.global_variables` | VARIABLE_NAME, VARIABLE_VALUE | SUPER / SYSTEM_VARIABLES_ADMIN |
| MariaDB | 同 MySQL + `information_schema.SYSTEM_VARIABLES` | + DEFAULT_VALUE, VARIABLE_SOURCE | 同 MySQL |
| Oracle | `V$PARAMETER` / `V$SPPARAMETER` | NAME, VALUE, ISDEFAULT, ISMODIFIED, ISADJUSTED, DESCRIPTION | SYS / DBA |
| SQL Server | `sys.configurations` + `sys.dm_database_scoped_configurations` | name, value, value_in_use, is_dynamic, is_advanced | sysadmin |
| SQLite | `PRAGMA pragma_list` / `PRAGMA <name>` | -- | 默认所有连接 |
| ClickHouse | `system.settings` + `system.merge_tree_settings` | name, value, changed, description, type, readonly | DEFAULT |
| DB2 | `SYSIBMADM.DBMCFG` / `SYSIBMADM.DBCFG` | NAME, VALUE, DEFERRED_VALUE, DATATYPE | SYSADM |
| CockroachDB | `SHOW [ALL] CLUSTER SETTING` / `crdb_internal.cluster_settings` | variable, value, type, description | admin |
| TiDB | `SHOW [GLOBAL] VARIABLES` + `mysql.tidb` | -- | SUPER |
| OceanBase | `SHOW [GLOBAL] VARIABLES` + `__all_sys_parameter` | -- | root |
| Snowflake | `SHOW PARAMETERS [LIKE ... IN ...]` | key, value, default, level, description, type | account/role 相关 |
| BigQuery | `INFORMATION_SCHEMA.JOBS` query labels | -- | 项目权限 |
| Redshift | `SHOW [ALL]` / `pg_settings`（部分继承 PG） | name, setting, ... | superuser |
| DuckDB | `duckdb_settings()` 表函数 / `PRAGMA database_list` | name, value, description, input_type, scope | 默认 |
| Trino | `SHOW SESSION` + `system.metadata.session_properties` | name, value, default, type, description | -- |
| Spark SQL | `SET` / `SET -v` | key, value, meaning | -- |
| Hive | `SET` / `SET -v` | key, value | -- |
| Flink SQL | `SET` 列表 | -- | -- |
| Greenplum | 同 PG | 同 PG | 同 PG |
| YugabyteDB | 同 PG + `yb_pg_stat_get_settings` | 同 PG | 同 PG |
| SAP HANA | `M_INIFILE_CONTENTS` / `M_CONFIGURATION_PARAMETER_VALUES` | -- | -- |
| Informix | `onstat -g cfg` (CLI) / `sysadmin:mon_config` (SQL) | -- | -- |
| Firebird | `RDB$DATABASE` 字段 / `MON$DATABASE` | -- | SYSDBA |
| MonetDB | `sys.env()` | name, value | monetdb |
| TimescaleDB | 同 PG + `timescaledb_information.*` | 同 PG | 同 PG |
| QuestDB | `pg_settings`（部分） | -- | -- |
| RisingWave | `SHOW PARAMETERS` / `SHOW ALL` | -- | -- |
| Databend | `SHOW SETTINGS` / `system.settings` | name, value, default, range, level, type, description | -- |

### ALTER SYSTEM 持久化能力

修改 SQL 同时持久化到磁盘配置文件：

| 引擎 | 持久化语法 | 写入文件 | 引入版本 | 重启后保留 |
|------|----------|---------|---------|-----------|
| PostgreSQL | `ALTER SYSTEM SET param = val` | postgresql.auto.conf | 9.4 (2014) | 是 |
| MySQL | `SET PERSIST var = val` | mysqld-auto.cnf | 8.0 (2018) | 是 |
| MySQL | `SET PERSIST_ONLY var = val` | mysqld-auto.cnf（不立即应用） | 8.0 (2018) | 是 |
| MariaDB | -- | -- | -- | 不支持 SET PERSIST（10.x 仍未实现） |
| Oracle | `ALTER SYSTEM SET param = val SCOPE=SPFILE` | spfile.ora | 9i (2001) | 是 |
| Oracle | `ALTER SYSTEM SET param = val SCOPE=BOTH` | 内存 + SPFILE | 9i (2001) | 是 |
| SQL Server | `sp_configure 'name', val; RECONFIGURE;` | 系统目录 (sys.configurations) | 6.0 (1995) | 是 |
| SQL Server | `ALTER DATABASE SCOPED CONFIGURATION SET ...` | 数据库元数据 | 2016+ | 是 |
| SQLite | `PRAGMA name = val`（仅部分持久） | sqlite_master 头部 | 3.x | 部分（如 user_version） |
| ClickHouse | `ALTER USER SET / ALTER PROFILE` | users.xml + profiles.xml 用户层 | 早期 | 是 |
| DB2 | `UPDATE DBM CFG / DB CFG USING param val` | DBM CFG / DB CFG 二进制文件 | 早期 | 是 |
| CockroachDB | `SET CLUSTER SETTING name = val` | system 表（KV 存储） | 1.x | 是 |
| TiDB | `SET CLUSTER SETTING / SET GLOBAL` | TiKV 元数据（部分） | 4.0+ | 是（GLOBAL） |
| OceanBase | `ALTER SYSTEM SET param = val [TENANT=...]` | observer 元数据 | 1.0+ | 是 |
| Snowflake | `ALTER ACCOUNT / USER / SESSION SET param = val` | 平台元数据 | GA | 是（ACCOUNT/USER 层） |
| BigQuery | -- | -- | -- | 不支持，仅 Workgroup/Reservation |
| Redshift | `ALTER USER ... SET` / `ALTER DATABASE ... SET` | 系统目录 | 早期 | 是 |
| DuckDB | -- | -- | -- | 不支持持久化（进程级） |
| Trino | -- | -- | -- | 不支持运行时持久化 |
| Spark SQL | `SET`（仅会话） | -- | -- | 否 |
| Greenplum | `ALTER SYSTEM SET`（继承 PG） | postgresql.auto.conf | 6.0+ | 是 |
| YugabyteDB | `ALTER SYSTEM SET`（继承 PG） | postgresql.auto.conf | 2.0+ | 是 |
| TimescaleDB | 继承 PG | 继承 PG | 继承 PG | 是 |
| RisingWave | `ALTER SYSTEM SET / SET CLUSTER SETTING` | meta 节点元数据 | 1.0+ | 是 |
| Databend | `SET GLOBAL var = val` | meta 节点元数据 | GA | 是（GLOBAL） |

### Reload 信号与显式 reload

让运行中的服务重新读取配置文件：

| 引擎 | SIGHUP | 显式 reload SQL | OS 命令 | 是否需重启 |
|------|--------|----------------|--------|-----------|
| PostgreSQL | 是 | `SELECT pg_reload_conf()` | `pg_ctl reload` | 仅静态参数需重启 |
| MySQL | 部分（mysqld 仅刷新日志） | `FLUSH LOGS` / 部分 SET GLOBAL | `mysqladmin flush-...` | 多数参数需重启或 SET GLOBAL |
| MariaDB | 同 MySQL | 同 MySQL | 同 MySQL | 同 MySQL |
| Oracle | -- | `ALTER SYSTEM SET ... SCOPE=MEMORY/BOTH` | `sqlplus / as sysdba` | 仅静态参数需重启 |
| SQL Server | -- | `RECONFIGURE` / `RECONFIGURE WITH OVERRIDE` | -- | 部分 advanced 参数需重启 |
| SQLite | -- | `PRAGMA name = val` | -- | 多数 PRAGMA 立即生效 |
| ClickHouse | 是（自动检测文件变化） | `SYSTEM RELOAD CONFIG` | `clickhouse-client -q 'SYSTEM RELOAD CONFIG'` | 仅启动参数需重启 |
| DB2 | -- | `UPDATE DBM CFG / DB CFG`（部分立即） | -- | 多数 IMMEDIATE，部分 DEFERRED |
| CockroachDB | -- | `SET CLUSTER SETTING`（多数立即） | -- | 极少需重启 |
| TiDB | -- | `SET CLUSTER SETTING`（多数立即） | -- | 极少需重启 |
| OceanBase | -- | `ALTER SYSTEM SET`（多数立即） | -- | 仅启动参数需重启 |
| Snowflake | -- | `ALTER ACCOUNT/USER/SESSION SET`（立即） | -- | 永远不需用户重启 |
| Redshift | -- | `SET`（会话）/ Parameter Group reboot | 控制台 | 部分需重启集群 |
| DuckDB | -- | `SET`（仅会话） | -- | 进程级 |
| Trino | -- | -- | 重启 coordinator/worker | 文件改动需重启 |
| Spark SQL | -- | `SET`（仅会话） | -- | 集群配置改动需重启 |
| Hive | -- | `SET`（仅会话） | -- | 服务端改动需重启 HiveServer2 |
| Flink SQL | -- | `SET`（仅会话） | -- | 集群配置改动需重启 |
| Greenplum | 是（gpstop -u） | `SELECT pg_reload_conf()` | `gpstop -u` | 同 PG |
| YugabyteDB | 是 | `SELECT pg_reload_conf()` | `yb-admin set_flag` | 同 PG + tserver flag |
| Impala | 是 | -- | `kill -HUP <pid>` | 部分 flag 需重启 |
| StarRocks | -- | `ADMIN SET FRONTEND CONFIG ('name'='val')` | -- | 部分 BE 参数需重启 |
| Doris | -- | `ADMIN SET FRONTEND CONFIG` | -- | 同 StarRocks |
| Vertica | -- | `ALTER DATABASE / NODE SET` | admintools | 部分需重启 |
| MonetDB | -- | -- | `monetdb start/stop` | 多数需重启 |

### 环境变量覆盖

| 引擎 | 主要环境变量 | 优先级 | 备注 |
|------|------------|--------|------|
| PostgreSQL | PGDATA, PGPORT, PGHOST, PGUSER, PGDATABASE 等 PG* 系列 | 命令行 > 环境 > 配置文件 | 客户端为主 |
| MySQL | MYSQL_HOST, MYSQL_PWD, MYSQL_TCP_PORT 等 | 命令行 > 环境 > my.cnf | 客户端为主 |
| Oracle | ORACLE_HOME, ORACLE_SID, NLS_LANG, TNS_ADMIN | 进程级，影响 init.ora 查找 | 服务端 + 客户端均用 |
| SQL Server | -- | -- | 主要靠注册表 |
| SQLite | TMPDIR, SQLITE_TMPDIR | 仅临时目录 | 通过 PRAGMA 为主 |
| ClickHouse | CLICKHOUSE_USER, CLICKHOUSE_PASSWORD, CLICKHOUSE_HOST | 客户端环境变量 | 服务端读 config.xml |
| DB2 | DB2INSTANCE, DB2DBDFT | 实例级 | -- |
| CockroachDB | COCKROACH_* 系列、KV 存储路径 | 命令行 > 环境 > 默认 | 多数走 flag |
| TiDB | TIDB_* 部分变量 | 命令行 flag 优先 | -- |
| Snowflake | SNOWSQL_*（CLI） | 客户端 | 服务端不可访问 |
| Trino | -- | 主要靠 properties 文件 | -- |
| Spark | SPARK_HOME, SPARK_CONF_DIR, JAVA_HOME, PYSPARK_PYTHON | 命令行 > 环境 > spark-defaults.conf | -- |
| Hive | HIVE_HOME, HIVE_CONF_DIR, HADOOP_HOME | 同 Spark | -- |
| Flink | FLINK_CONF_DIR, FLINK_HOME, JAVA_HOME | -- | -- |
| MongoDB | -- | YAML 文件 + 命令行 flag | 环境变量极少 |

## 各引擎深度解析

### PostgreSQL：postgresql.conf + auto.conf + ALTER SYSTEM

PostgreSQL 的配置体系是开源数据库中设计最完整的。

**主配置文件 postgresql.conf**：

```ini
# 内存
shared_buffers = 4GB                    # 共享缓冲池，需重启
effective_cache_size = 12GB             # 优化器估算 OS 缓存大小，可 reload
work_mem = 64MB                         # 排序/哈希内存，会话级可 SET

# 连接
listen_addresses = '*'                  # 监听地址，需重启
port = 5432                             # 端口，需重启
max_connections = 200                   # 最大连接数，需重启

# WAL
wal_level = replica                     # WAL 级别，需重启
synchronous_commit = on                 # 同步提交，可 reload
max_wal_size = 16GB                     # 触发 checkpoint 的 WAL 上限，可 reload
checkpoint_timeout = 15min              # 检查点超时，可 reload

# 查询规划器
enable_hashjoin = on                    # 哈希连接开关，会话级可 SET
random_page_cost = 1.1                  # SSD 推荐值，可 reload

# 日志
log_min_duration_statement = 1000       # 慢查询阈值（ms），可 reload
log_destination = 'stderr,csvlog'       # 日志输出方式，可 reload
```

**配置文件包含机制**：

```ini
# postgresql.conf 末尾推荐保留：
include_dir 'conf.d'                    # 加载 conf.d/*.conf
include 'tuning.conf'                   # 加载单个文件
include_if_exists 'site.conf'           # 文件不存在不报错
```

**postgresql.auto.conf（9.4 引入）**：

`postgresql.auto.conf` 是 ALTER SYSTEM 命令的产物。它放在 $PGDATA 根目录，由 PostgreSQL 自动管理，**用户不应手工编辑**。加载顺序：

```
启动加载顺序:
  1. postgresql.conf
  2. include / include_dir 引入的文件
  3. postgresql.auto.conf  ← 始终最后加载，覆盖前面值
  4. 命令行 -c 选项
  5. 环境变量 PG*
```

也就是说 `ALTER SYSTEM SET shared_buffers = '8GB'` 后，无论 postgresql.conf 写了什么，auto.conf 的值都会生效。

```sql
-- 修改并持久化
ALTER SYSTEM SET work_mem = '128MB';

-- 让动态参数立即生效（不需重启）
SELECT pg_reload_conf();

-- 撤销 auto.conf 中的设置（恢复 postgresql.conf 中的值）
ALTER SYSTEM RESET work_mem;
ALTER SYSTEM RESET ALL;

-- 检查 auto.conf 内容
SELECT name, setting, source, sourcefile
FROM pg_settings
WHERE source = 'configuration file'
  AND sourcefile LIKE '%auto.conf%';
```

**pg_hba.conf（认证规则）**：

```
# TYPE   DATABASE   USER       ADDRESS         METHOD
local    all        postgres                   peer
host     all        all        127.0.0.1/32    scram-sha-256
host     all        all        ::1/128         scram-sha-256
host     replication replicator 10.0.0.0/8     scram-sha-256
hostssl  appdb      app_user   0.0.0.0/0       cert clientcert=verify-full
```

pg_hba.conf 控制连接是否被允许、认证方式（peer / md5 / scram-sha-256 / cert / ldap / radius）。修改后 SIGHUP 立即生效，已建立的连接不受影响。

**pg_ident.conf（OS 用户到数据库用户映射）**：

```
# MAPNAME       SYSTEM-USERNAME         PG-USERNAME
mymap           alice                   alice
mymap           /^(.*)@example\.com$    \1
```

主要配合 ident / peer / cert 认证使用。

**pg_settings 视图：最完整的元数据**：

```sql
-- 查看所有动态参数
SELECT name, setting, unit, category, context
FROM pg_settings
WHERE context IN ('user', 'sighup', 'superuser')
ORDER BY category, name;

-- 查看哪些参数需要重启
SELECT name, setting, source FROM pg_settings WHERE context = 'postmaster';

-- 查看每个参数的来源
SELECT name, setting, source, sourcefile, sourceline
FROM pg_settings
WHERE source NOT IN ('default', 'override');

-- 查看 pending（修改后尚未 reload 生效）的设置
SELECT name, setting, pending_restart FROM pg_settings WHERE pending_restart;
```

`pg_settings.context` 值含义：

```
internal    -- 编译期决定（如 block_size），不可改
postmaster  -- 主进程启动时决定，需重启 (pg_ctl restart)
sighup      -- 可通过 SIGHUP / pg_reload_conf() 生效
superuser-backend, backend  -- 连接建立时决定
superuser   -- 超级用户在会话内可 SET
user        -- 普通用户在会话内可 SET
```

### MySQL：my.cnf + system_variables + SET PERSIST

**my.cnf 文件路径搜索顺序**（Linux）：

```
1. /etc/my.cnf
2. /etc/mysql/my.cnf
3. SYSCONFDIR/my.cnf       (编译时决定)
4. $MYSQL_HOME/my.cnf
5. --defaults-file 命令行
6. ~/.my.cnf               (客户端用)
7. ~/.mylogin.cnf          (加密登录路径)
```

后读取的文件覆盖前面（除 --defaults-file 立即结束查找）。可用 `mysqld --verbose --help | head -20` 查看真实顺序。

**典型 my.cnf 结构**：

```ini
[client]
port            = 3306
socket          = /var/lib/mysql/mysql.sock

[mysqld]
# 基础
port            = 3306
bind-address    = 0.0.0.0
datadir         = /var/lib/mysql
socket          = /var/lib/mysql/mysql.sock

# InnoDB
innodb_buffer_pool_size = 8G
innodb_log_file_size    = 1G
innodb_flush_log_at_trx_commit = 1
innodb_flush_method     = O_DIRECT

# 复制
server-id       = 100
log-bin         = mysql-bin
binlog_format   = ROW
gtid_mode       = ON
enforce_gtid_consistency = ON

# 连接
max_connections = 500
thread_cache_size = 16

# 字符集
character-set-server = utf8mb4
collation-server     = utf8mb4_0900_ai_ci

# 包含其他文件
!include  /etc/mysql/conf.d/local.cnf
!includedir /etc/mysql/conf.d/
```

**SET PERSIST（8.0 引入）**：

MySQL 8.0 之前，修改 `my.cnf` 必须重启或用 `SET GLOBAL`（重启后丢失）。SET PERSIST 解决了这个矛盾：

```sql
-- 立即应用 + 持久化到 mysqld-auto.cnf
SET PERSIST max_connections = 1000;

-- 仅持久化到 mysqld-auto.cnf，不立即应用（用于 read-only 静态参数）
SET PERSIST_ONLY innodb_buffer_pool_size = '16G';

-- 撤销持久化（删除 mysqld-auto.cnf 中的条目）
RESET PERSIST max_connections;
RESET PERSIST;  -- 全部撤销

-- 查看持久化的参数
SELECT * FROM performance_schema.persisted_variables;
```

**mysqld-auto.cnf 文件**（datadir 下，JSON 格式）：

```json
{
  "Version": 1,
  "mysql_server": {
    "max_connections": {
      "Value": "1000",
      "Metadata": {
        "Timestamp": 1648800000123456,
        "User": "root",
        "Host": "localhost"
      }
    },
    "mysql_server_static_options": {
      "innodb_buffer_pool_size": {
        "Value": "17179869184",
        "Metadata": {
          "Timestamp": 1648800001234567,
          "User": "root",
          "Host": "localhost"
        }
      }
    }
  }
}
```

**变量作用域三层**：

```sql
-- 全局变量（影响新连接）
SET GLOBAL max_connections = 500;
SHOW GLOBAL VARIABLES LIKE 'max_connections';
SELECT @@global.max_connections;

-- 会话变量（仅当前连接）
SET SESSION sort_buffer_size = '4M';
SHOW SESSION VARIABLES LIKE 'sort_buffer_size';
SELECT @@session.sort_buffer_size, @@sort_buffer_size;  -- 默认 SESSION

-- 持久化变量（写入 mysqld-auto.cnf）
SET PERSIST max_connections = 500;        -- 全局 + 持久
SET PERSIST_ONLY innodb_buffer_pool_size = '8G';  -- 仅写文件，需重启
```

### Oracle：init.ora vs spfile.ora

Oracle 的配置演进史最有代表性。

**init.ora（旧文本配置文件）**：

```
# init.ora 示例
db_name = 'ORCL'
db_files = 200
control_files = ('/u01/oracle/oradata/control01.ctl',
                 '/u01/oracle/oradata/control02.ctl')
db_block_size = 8192
sga_max_size = 8G
sga_target  = 6G
pga_aggregate_target = 2G
processes = 500
log_buffer = 16M
undo_management = AUTO
undo_tablespace = UNDOTBS1
```

文本格式好读好改，但有几个根本缺陷：

1. 多实例 RAC 配置同步困难
2. 实例运行时修改不能持久化
3. 字符集和 NLS 等 binding 时机难以保证

**spfile.ora（9i 引入的二进制配置文件）**：

Oracle 9i（2001）引入 SPFILE（Server Parameter File），是二进制格式。它的关键特性：

- 服务端管理：DBA 不能（也不应）手工编辑
- ALTER SYSTEM 可直接修改并持久化
- RAC 多实例共享单个 SPFILE
- 支持 SCOPE 语义（MEMORY / SPFILE / BOTH）

```sql
-- 查看当前 SPFILE 路径
SHOW PARAMETER spfile;

-- 从 SPFILE 创建 PFILE（可读副本）
CREATE PFILE FROM SPFILE;
CREATE PFILE='/tmp/init.ora' FROM SPFILE;

-- 从 PFILE 创建 SPFILE
CREATE SPFILE FROM PFILE;

-- 修改参数三种 SCOPE
ALTER SYSTEM SET sga_target = 8G SCOPE=MEMORY;     -- 仅内存，重启丢失
ALTER SYSTEM SET sga_target = 8G SCOPE=SPFILE;     -- 仅文件，重启后生效
ALTER SYSTEM SET sga_target = 8G SCOPE=BOTH;       -- 同时（默认）

-- 撤销修改
ALTER SYSTEM RESET sga_target SCOPE=BOTH;

-- 查看参数
SELECT NAME, VALUE, ISDEFAULT, ISMODIFIED
FROM V$PARAMETER
WHERE NAME LIKE '%sga%';

-- 查看 SPFILE 中存储的值（与运行时分开）
SELECT NAME, VALUE FROM V$SPPARAMETER WHERE ISSPECIFIED = 'TRUE';
```

**SCOPE=BOTH 的语义**：

```
SCOPE=BOTH 时，引擎会：
  1. 验证参数值合法（类型、范围）
  2. 修改运行时内存中的参数
  3. 修改 SPFILE 中对应条目（原子写）
  4. 如果当前是动态参数，立即生效
  5. 如果是静态参数，仅写入 SPFILE，重启后才生效
```

**RAC 实例特定参数**：

```sql
-- 仅修改某个实例（SID = inst1）
ALTER SYSTEM SET sga_target = 4G SCOPE=BOTH SID='inst1';

-- 修改所有实例（SID='*' 默认）
ALTER SYSTEM SET sga_target = 4G SCOPE=BOTH SID='*';
```

### SQL Server：sp_configure + Database Scoped Configurations

SQL Server 的配置体系是相对独特的：没有传统配置文件，全部通过系统目录管理。

**sp_configure（实例级，6.0 引入）**：

```sql
-- 查看所有实例参数
EXEC sp_configure;

-- 显示高级选项
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;

-- 修改参数
EXEC sp_configure 'max server memory', 16384;  -- MB
RECONFIGURE;  -- 立即生效（动态参数）
RECONFIGURE WITH OVERRIDE;  -- 强制（即使值越界）

-- 一些参数需重启
EXEC sp_configure 'priority boost', 1;
RECONFIGURE;
-- 提示重启服务
```

**sys.configurations 视图**：

```sql
SELECT name, value, value_in_use, minimum, maximum,
       is_dynamic, is_advanced, description
FROM sys.configurations
ORDER BY name;
```

`is_dynamic = 1` 表示 RECONFIGURE 后立即生效；`is_dynamic = 0` 表示需重启 SQL Server。`value` 是 sp_configure 设置的值，`value_in_use` 是引擎实际使用的值（RECONFIGURE 后两者相等）。

**Database Scoped Configurations（2016 引入）**：

```sql
-- 数据库级参数（不影响其他数据库）
ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 4;
ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = ON;
ALTER DATABASE SCOPED CONFIGURATION SET QUERY_OPTIMIZER_HOTFIXES = ON;

-- secondary（用于 AlwaysOn 副本）
ALTER DATABASE SCOPED CONFIGURATION FOR SECONDARY SET MAXDOP = 2;

-- 重置
ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = PRIMARY;

-- 查看
SELECT * FROM sys.database_scoped_configurations;
```

**mssql.conf（Linux 上 SQL Server）**：

```ini
[network]
tcpport = 1433

[memory]
memorylimitmb = 16384

[telemetry]
customerfeedback = false
```

mssql-conf set / mssql-conf list 工具操作。

### ClickHouse：config.xml + users.xml + profiles.xml

ClickHouse 用 XML 配置，分服务参数和用户参数两层。

**config.xml（服务端参数）**：

```xml
<clickhouse>
    <logger>
        <level>information</level>
        <log>/var/log/clickhouse-server/clickhouse-server.log</log>
        <errorlog>/var/log/clickhouse-server/clickhouse-server.err.log</errorlog>
        <size>1000M</size>
        <count>10</count>
    </logger>

    <listen_host>::</listen_host>
    <http_port>8123</http_port>
    <tcp_port>9000</tcp_port>
    <interserver_http_port>9009</interserver_http_port>

    <max_connections>4096</max_connections>
    <keep_alive_timeout>3</keep_alive_timeout>

    <max_concurrent_queries>100</max_concurrent_queries>
    <max_server_memory_usage>0</max_server_memory_usage>

    <path>/var/lib/clickhouse/</path>
    <tmp_path>/var/lib/clickhouse/tmp/</tmp_path>
    <user_files_path>/var/lib/clickhouse/user_files/</user_files_path>

    <users_config>users.xml</users_config>
    <default_profile>default</default_profile>
    <default_database>default</default_database>

    <remote_servers>
        <my_cluster>
            <shard>
                <replica>
                    <host>node1</host>
                    <port>9000</port>
                </replica>
            </shard>
        </my_cluster>
    </remote_servers>

    <zookeeper>
        <node>
            <host>zk1</host>
            <port>2181</port>
        </node>
    </zookeeper>
</clickhouse>
```

**users.xml + profiles.xml（用户与配置文件）**：

```xml
<clickhouse>
    <profiles>
        <default>
            <max_memory_usage>10000000000</max_memory_usage>
            <use_uncompressed_cache>0</use_uncompressed_cache>
            <load_balancing>random</load_balancing>
        </default>
        <readonly>
            <readonly>1</readonly>
        </readonly>
    </profiles>

    <users>
        <default>
            <password></password>
            <networks><ip>::/0</ip></networks>
            <profile>default</profile>
            <quota>default</quota>
        </default>
        <reader>
            <password_sha256_hex>...</password_sha256_hex>
            <networks><ip>10.0.0.0/8</ip></networks>
            <profile>readonly</profile>
            <quota>default</quota>
        </reader>
    </users>

    <quotas>
        <default>
            <interval>
                <duration>3600</duration>
                <queries>0</queries>
                <errors>0</errors>
                <result_rows>0</result_rows>
                <read_rows>0</read_rows>
                <execution_time>0</execution_time>
            </interval>
        </default>
    </quotas>
</clickhouse>
```

**SQL 级修改**：

```sql
-- 查看所有运行参数
SELECT name, value, changed FROM system.settings WHERE changed = 1;

-- 会话参数
SET max_threads = 16;
SET max_memory_usage = 20000000000;

-- 用户/profile 持久化（22.x+）
ALTER USER reader SETTINGS max_memory_usage = 30000000000;
CREATE SETTINGS PROFILE heavy SETTINGS max_threads = 64;
ALTER USER analyst SETTINGS PROFILE = 'heavy';

-- 重新加载配置文件（无需重启）
SYSTEM RELOAD CONFIG;

-- 查看 merge_tree 表引擎参数
SELECT * FROM system.merge_tree_settings WHERE name LIKE '%merge%';
```

ClickHouse 的核心特点：**自动监视文件变化**，文件改动后大部分参数会自动重载，无需主动 SIGHUP。

### SQLite：无配置文件

SQLite 是嵌入式库，没有服务端进程，因此**没有配置文件**。所有调优通过 `PRAGMA` 完成：

```sql
-- 在每个连接打开时设置
PRAGMA journal_mode = WAL;             -- 启用 WAL 日志
PRAGMA synchronous = NORMAL;           -- WAL 模式下推荐
PRAGMA cache_size = -64000;            -- 64MB（负数表示 KB，正数表示页数）
PRAGMA mmap_size = 268435456;          -- 256MB mmap
PRAGMA temp_store = MEMORY;            -- 临时表放内存
PRAGMA foreign_keys = ON;              -- 默认关闭外键约束！
PRAGMA busy_timeout = 5000;            -- 锁等待 5 秒
PRAGMA threads = 4;                    -- 排序/索引创建并行度

-- 持久化的 PRAGMA（写入数据库文件头部）
PRAGMA application_id = 0xCAFE0001;
PRAGMA user_version = 12;
PRAGMA page_size = 4096;               -- 仅 VACUUM / 新库时生效
PRAGMA auto_vacuum = INCREMENTAL;       -- 写入文件头

-- 查询所有 PRAGMA
SELECT * FROM pragma_pragma_list ORDER BY name;
```

绝大多数 PRAGMA 是**连接级**的，每个新连接需重新设置。这是 SQLite 嵌入模型的自然结果——没有"服务端"可以保存全局设置。

### CockroachDB：cluster settings via SET CLUSTER SETTING

CockroachDB 完全废弃了配置文件，全部参数通过 SQL 命令管理。

```sql
-- 查看所有 cluster settings
SHOW CLUSTER SETTINGS;
SHOW ALL CLUSTER SETTINGS;

-- 查看单个
SHOW CLUSTER SETTING server.shutdown.drain_wait;

-- 修改
SET CLUSTER SETTING sql.defaults.serial_normalization = 'sql_sequence';
SET CLUSTER SETTING kv.snapshot_rebalance.max_rate = '64MiB';

-- 重置为默认
RESET CLUSTER SETTING kv.snapshot_rebalance.max_rate;

-- 查看所有的设置定义
SELECT variable, value, type, public, description
FROM crdb_internal.cluster_settings
ORDER BY variable;
```

启动参数（节点级）通过命令行 flag：

```bash
cockroach start --advertise-addr=node1 \
  --cache=4GiB \
  --max-sql-memory=2GiB \
  --listen-addr=0.0.0.0:26257 \
  --http-addr=0.0.0.0:8080 \
  --certs-dir=/certs \
  --join=node1,node2,node3
```

### TiDB：tidb.toml + SET CLUSTER SETTING

TiDB 是混合模型：节点启动用 TOML 文件，运行时参数用 MySQL 兼容 + 自定义命令。

**tidb.toml 示例**：

```toml
# 实例级参数
host = "0.0.0.0"
port = 4000
status-port = 10080
path = "127.0.0.1:2379"  # PD 地址

[log]
level = "info"
file.filename = "/var/log/tidb/tidb.log"
file.max-size = 300
file.max-days = 7

[security]
ssl-cert = ""
ssl-key  = ""
ssl-ca   = ""

[performance]
max-procs = 0
max-memory = 0
stats-lease = "3s"
tcp-keep-alive = true

[tikv-client]
grpc-connection-count = 4
grpc-keepalive-time = 10
copr-cache.capacity-mb = 1000.0
```

**SQL 级修改**：

```sql
-- 系统变量（兼容 MySQL）
SHOW GLOBAL VARIABLES LIKE 'tidb_%';
SET GLOBAL tidb_distsql_scan_concurrency = 30;

-- TiDB 特定 cluster settings
SHOW CONFIG;
SET CONFIG tikv `coprocessor.region-split-size` = '128MiB';
SET CONFIG tidb `log.level` = 'debug';
```

### DuckDB：纯运行时参数

DuckDB 作为进程内分析库，**没有任何配置文件**：

```sql
-- 全部通过 PRAGMA / SET
PRAGMA threads = 8;
PRAGMA memory_limit = '8GB';
PRAGMA temp_directory = '/tmp/duckdb';
PRAGMA enable_progress_bar;

-- 查看所有
SELECT * FROM duckdb_settings();

SET memory_limit = '16GB';
SET threads = 16;
```

可通过命令行 `-init <file>` 在启动时执行 SQL 文件，模拟"配置脚本"。

### Trino / Presto：多文件分层

Trino 把配置拆成多个 properties 文件：

```
/etc/trino/
├── config.properties      # 进程角色（coordinator / worker）+ 通用参数
├── jvm.config             # JVM 启动选项
├── node.properties        # 节点身份
├── log.properties         # 日志级别
└── catalog/               # 每个数据源一个文件
    ├── hive.properties
    ├── mysql.properties
    └── memory.properties
```

**config.properties 示例**：

```properties
coordinator=true
node-scheduler.include-coordinator=false
http-server.http.port=8080
discovery.uri=http://coordinator:8080
query.max-memory=50GB
query.max-memory-per-node=8GB
```

**catalog/hive.properties**：

```properties
connector.name=hive
hive.metastore.uri=thrift://hms:9083
hive.config.resources=/etc/trino/core-site.xml,/etc/trino/hdfs-site.xml
```

运行时通过 `SET SESSION` 修改但仅限会话：

```sql
SET SESSION query_max_memory = '4GB';
SHOW SESSION;
RESET SESSION query_max_memory;
```

### Snowflake：完全 SQL 化的参数管理

Snowflake 没有配置文件（云原生），全部通过分层 SET：

```sql
-- 账户级（所有用户和会话默认值）
ALTER ACCOUNT SET STATEMENT_TIMEOUT_IN_SECONDS = 3600;
ALTER ACCOUNT SET DEFAULT_DDL_COLLATION = 'utf8';

-- 用户级
ALTER USER alice SET QUERY_TAG = 'analyst';
ALTER USER alice SET DEFAULT_WAREHOUSE = 'COMPUTE_WH';

-- 会话级
ALTER SESSION SET QUERY_TAG = 'etl_pipeline';
ALTER SESSION SET TIMEZONE = 'America/Los_Angeles';

-- 单独 RESET
ALTER ACCOUNT UNSET STATEMENT_TIMEOUT_IN_SECONDS;

-- 查看
SHOW PARAMETERS;
SHOW PARAMETERS LIKE 'STATEMENT_TIMEOUT%' IN ACCOUNT;
SHOW PARAMETERS IN USER alice;

-- 查看参数继承层级
SELECT "key", "value", "default", "level", "description"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
```

参数解析时按 SESSION > USER > ACCOUNT > 系统默认 顺序生效。

## ALTER SYSTEM 与 postgresql.auto.conf 持久化机制

PostgreSQL 9.4（2014）引入 ALTER SYSTEM，从此用户无需 OS 文件权限即可永久修改配置。

**写入机制**：

```
ALTER SYSTEM SET shared_buffers = '8GB';

引擎内部步骤:
  1. 解析 + 验证参数名和值合法性
  2. 锁定 ConfigurationLock (排他锁)
  3. 读 postgresql.auto.conf
  4. 在内存中生成新内容（覆盖或追加 shared_buffers 行）
  5. 写入临时文件 postgresql.auto.conf.tmp
  6. fsync(临时文件)
  7. rename(临时文件, postgresql.auto.conf)
  8. fsync(目录)
  9. 释放锁
  10. 不立即生效（除非 SIGHUP）
```

注意 ALTER SYSTEM **本身不立即应用到运行时**——它只写文件。要生效仍需：

- 动态参数：`SELECT pg_reload_conf()` 或 SIGHUP
- 静态参数：重启服务

**postgresql.auto.conf 的格式**：

```ini
# Do not edit this file manually!
# It will be overwritten by the ALTER SYSTEM command.
shared_buffers = '8GB'
work_mem = '64MB'
log_min_duration_statement = '500ms'
```

文件格式与 postgresql.conf 完全相同，但首行有警告注释。**最后加载**意味着它的值始终覆盖 postgresql.conf。

**冲突解决**：

```
postgresql.conf:        max_connections = 100
postgresql.auto.conf:   max_connections = 200
启动后实际值:           200  ← auto.conf 后加载，覆盖

如果 ALTER SYSTEM RESET max_connections:
postgresql.auto.conf:   <max_connections 行被删除>
启动后实际值:           100  ← 回到 postgresql.conf 值
```

**安全限制**：

ALTER SYSTEM 默认要求超级用户。某些参数（如 `data_directory`、`config_file`）是只读的，无法通过 ALTER SYSTEM 修改。可通过 `pg_settings.context = 'internal'` 识别这类参数。

## MySQL SET PERSIST 与 mysqld-auto.cnf

MySQL 8.0（2018-04 GA）引入 SET PERSIST，与 PG 的 ALTER SYSTEM 在概念上极相似但实现细节不同。

**两个变体**：

```sql
-- SET PERSIST: 立即应用 + 持久化
SET PERSIST max_connections = 1000;

-- SET PERSIST_ONLY: 只持久化不立即应用（适用于只读启动参数）
SET PERSIST_ONLY innodb_buffer_pool_size = '16G';
SET PERSIST_ONLY innodb_log_file_size = '2G';
```

**mysqld-auto.cnf 的位置**：

文件位于 `datadir`（如 `/var/lib/mysql/mysqld-auto.cnf`），加载顺序：

```
启动加载顺序:
  1. /etc/my.cnf
  2. /etc/mysql/my.cnf
  3. SYSCONFDIR/my.cnf
  4. $MYSQL_HOME/my.cnf
  5. --defaults-file
  6. ~/.my.cnf
  7. mysqld-auto.cnf       ← 最后加载，覆盖前面
```

**JSON 格式**（与 PG 的纯文本不同）：

```json
{
  "Version": 1,
  "mysql_server": {
    "max_connections": {
      "Value": "1000",
      "Metadata": {
        "Timestamp": 1648800000123456,
        "User": "admin",
        "Host": "%"
      }
    },
    "mysql_server_static_options": {
      "innodb_buffer_pool_size": {
        "Value": "17179869184",
        "Metadata": {
          "Timestamp": 1648800001234567,
          "User": "admin",
          "Host": "%"
        }
      }
    }
  }
}
```

JSON 元信息包括修改时间、修改人、来源主机，便于审计。

**RESET PERSIST**：

```sql
-- 删除单个持久化条目（不影响运行时值）
RESET PERSIST max_connections;

-- IF EXISTS 避免错误
RESET PERSIST IF EXISTS max_connections;

-- 删除全部（清空 mysqld-auto.cnf 内容）
RESET PERSIST;
```

**performance_schema.persisted_variables**：

```sql
SELECT VARIABLE_NAME, VARIABLE_VALUE
FROM performance_schema.persisted_variables;
```

### MariaDB 的态度

MariaDB 截至 11.x 仍**不支持** SET PERSIST。社区原因：

- MariaDB 团队认为 my.cnf 编辑足够透明
- 引入 JSON 配置文件破坏 INI 格式一致性
- 担心 SET PERSIST 在主从复制下的行为不一致

绕过方案：手工写入 `/etc/mysql/conf.d/local.cnf` 然后重启。

## Oracle PFILE vs SPFILE

Oracle 的 PFILE / SPFILE 设计是配置管理的代表作，影响了后来的 PG ALTER SYSTEM 等设计。

**PFILE（Parameter File）**：

```
init<SID>.ora 默认位置:
  Unix:  $ORACLE_HOME/dbs/init<SID>.ora
  Windows: %ORACLE_HOME%\database\init<SID>.ora
```

文本格式，可手工编辑。启动时一次性读取，运行时不再访问。

**SPFILE（Server Parameter File）**：

```
spfile<SID>.ora 默认位置:
  Unix:  $ORACLE_HOME/dbs/spfile<SID>.ora
  Windows: %ORACLE_HOME%\database\spfile<SID>.ora
  Or:    ASM 共享存储 (RAC 推荐)
```

二进制格式，禁手工编辑。运行时引擎可写入。

**启动优先级**：

```
1. STARTUP PFILE='路径'                             -- 显式 PFILE
2. STARTUP                                          -- 默认查找:
   2a. spfile<SID>.ora        ← 优先
   2b. spfile.ora             ← 通用 SPFILE
   2c. init<SID>.ora          ← PFILE 回退
```

如果 SPFILE 不存在，回退到 PFILE。这种渐进降级让升级路径平滑。

**SCOPE 三种语义**：

```sql
-- SCOPE=MEMORY: 仅修改运行时（不写 SPFILE）
ALTER SYSTEM SET sga_target = 8G SCOPE=MEMORY;
-- 重启后丢失，回到 SPFILE 中的旧值

-- SCOPE=SPFILE: 仅写 SPFILE（不影响当前实例）
ALTER SYSTEM SET sga_target = 8G SCOPE=SPFILE;
-- 当前不变，下次启动时生效

-- SCOPE=BOTH: 同时（默认值）
ALTER SYSTEM SET sga_target = 8G SCOPE=BOTH;
ALTER SYSTEM SET sga_target = 8G;  -- 等价（默认 BOTH）
-- 立即修改运行时 + 写入 SPFILE

-- 静态参数仅支持 SCOPE=SPFILE
ALTER SYSTEM SET db_block_size = 8192 SCOPE=SPFILE;
-- 必须 SCOPE=SPFILE，使用 BOTH 会报错
```

**RAC 实例特定**：

```sql
-- 只修改 inst1
ALTER SYSTEM SET sga_target = 4G SCOPE=BOTH SID='inst1';

-- 修改所有实例（默认）
ALTER SYSTEM SET sga_target = 4G SCOPE=BOTH SID='*';

-- 多实例独立配置
ALTER SYSTEM SET shared_pool_size = 1G SCOPE=SPFILE SID='inst1';
ALTER SYSTEM SET shared_pool_size = 2G SCOPE=SPFILE SID='inst2';
```

**SPFILE 与 PFILE 互转**：

```sql
-- SPFILE -> PFILE（备份/查看）
CREATE PFILE FROM SPFILE;
CREATE PFILE='/tmp/init_backup.ora' FROM SPFILE;

-- PFILE -> SPFILE（应用变更）
CREATE SPFILE FROM PFILE='/tmp/init_modified.ora';

-- 从内存创建 PFILE（包含运行时所有参数）
CREATE PFILE='/tmp/init_runtime.ora' FROM MEMORY;
CREATE SPFILE FROM MEMORY;
```

**两个核心视图**：

```sql
-- V$PARAMETER: 当前会话/实例运行时值
SELECT NAME, VALUE, ISDEFAULT, ISMODIFIED, ISADJUSTED
FROM V$PARAMETER
WHERE NAME LIKE '%sga%';

-- V$SPPARAMETER: SPFILE 中存储的值（与运行时分开）
SELECT SID, NAME, VALUE, ISSPECIFIED
FROM V$SPPARAMETER
WHERE ISSPECIFIED = 'TRUE'
ORDER BY NAME;

-- 找出 SPFILE 中已设但运行时被 SCOPE=MEMORY 改过的参数
SELECT s.NAME, s.VALUE AS SPFILE_VALUE, p.VALUE AS RUNTIME_VALUE
FROM V$SPPARAMETER s
JOIN V$PARAMETER p ON s.NAME = p.NAME
WHERE s.ISSPECIFIED = 'TRUE' AND s.VALUE != p.VALUE;
```

## 关键发现

### 持久化能力是现代数据库的标配

```
配置持久化能力时间线:
  1995  SQL Server: sp_configure + RECONFIGURE
  2001  Oracle 9i:  SPFILE + ALTER SYSTEM SCOPE=BOTH
  2014  PostgreSQL 9.4: ALTER SYSTEM + auto.conf
  2018  MySQL 8.0:  SET PERSIST + mysqld-auto.cnf
  2014~ 云数据库:    完全 SQL 化（CockroachDB / Snowflake / TiDB）
```

经过 20+ 年演化，"无需 OS 权限即可永久修改"已成基本要求。MariaDB 是少数仍坚持文件编辑的主流引擎。

### "配置文件 + SQL 命令"双轨制是主流

PostgreSQL / MySQL / Oracle 三大开源/商业引擎都采用双轨制：

- **文件**：DBA 直接编辑，备份/版本控制友好，集群同步用 Ansible / Puppet
- **SQL 命令**：应用程序自助修改，CI/CD 自动化，热更新

两条路径同时维护增加引擎复杂度，但兼顾不同用户群。

### 云数据库走向"完全 SQL 化"

Snowflake / BigQuery / CockroachDB 这类云原生数据库**完全没有配置文件**。理由：

- 用户不应接触底层文件系统
- 多租户共享需要按层级隔离
- 升级/迁移由平台管理

但代价是参数发现性差——必须通过 `SHOW PARAMETERS` 或控制台浏览。

### XML 与 YAML 是少数派

ClickHouse（XML）、CrateDB / Cassandra / MongoDB / Flink（YAML）选择了非传统格式。优点：

- 层次化（profiles / users / quotas 嵌套）
- 类型化（YAML 区分字符串/数字/布尔）
- 包含机制（XML XInclude / YAML anchor）

缺点：编辑器支持差、grep 困难、行号难定位错误。

### TOML 是新生云数据库的选择

TiDB / RisingWave / Databend / InfluxDB 都用 TOML。原因：

- 比 INI 更结构化（支持嵌套表）
- 比 YAML 简单（无缩进陷阱）
- Rust 生态首选（serde_toml）

```toml
# 比 YAML 更适合配置
[security]
ssl-cert = "/cert/server.pem"

[performance]
max-procs = 16
batch-size = 1024

[performance.cache]
hit-ratio = 0.95
```

### Reload 信号 vs SQL reload 的 trade-off

```
SIGHUP 信号:
  优点: 简单可靠，OS 级标准
  缺点: 需 OS 权限（sudo），云环境难触发，Windows 不原生支持

SQL reload (pg_reload_conf):
  优点: 无需 OS 权限，跨平台一致，可走代理/连接池
  缺点: 需要解析器入口（启动期失败时无法用）
```

PostgreSQL 同时提供两种，是权衡的最佳实践。

### 启动期间的"chicken-and-egg"问题

部分参数（如 `shared_buffers`、`max_connections`）必须在进程启动前确定。这导致：

- 不能通过 ALTER SYSTEM 立即生效，必须重启
- 配置文件错误会阻止启动，需保留 `psql --single` 救援模式
- 云数据库通过滚动重启隐藏这个限制

### 不区分静态/动态参数的引擎是糖衣陷阱

某些引擎（CockroachDB、TiDB cluster setting）让用户感觉"所有参数都是动态的"。但底层仍可能：

- 部分设置只对新连接生效
- 部分设置仅触发后台任务调整
- 极少数仍需重启节点

引擎应在 `SHOW CLUSTER SETTING` 输出中明确标注 `is_dynamic` 或 `effective_after`。

### 多个配置文件分层是主流大型引擎的特征

```
PostgreSQL: postgresql.conf + auto.conf + pg_hba.conf + pg_ident.conf
MySQL:      my.cnf + mysqld-auto.cnf + ~/.my.cnf
Trino:      config.properties + jvm.config + node.properties + catalog/*.properties
ClickHouse: config.xml + users.xml + 多个 *.d/ 子目录
SAP HANA:   global.ini + indexserver.ini + nameserver.ini + ...
```

分层带来管理复杂度，但每层职责清晰：实例级（运行时调优）、用户/认证级（接入控制）、连接源级（数据源 / catalog）、JVM/OS 级（进程边界）。

### 包含机制（include）的重要性

```ini
# my.cnf
!includedir /etc/mysql/conf.d/
!include    /etc/mysql/local.cnf

# postgresql.conf
include_dir 'conf.d'
include_if_exists 'site.conf'
```

包含机制让"主配置 + 增量配置"模式变得自然，便于容器镜像分层（基础镜像 + 部署时挂载 conf.d）、Ansible / Puppet 模板化部署、多环境差异隔离。

### 元数据丰富度差异巨大

```
PostgreSQL pg_settings:
  name, setting, unit, category, short_desc, extra_desc, context,
  vartype, source, min_val, max_val, enumvals, boot_val, reset_val,
  sourcefile, sourceline, pending_restart  (17 列)

MySQL SHOW VARIABLES:
  Variable_name, Value  (2 列)

DuckDB duckdb_settings():
  name, value, description, input_type, scope  (5 列)

Snowflake SHOW PARAMETERS:
  key, value, default, level, description, type  (6 列)
```

PostgreSQL 的元数据最丰富，几乎可以从 `pg_settings` 重建配置文件文档。MySQL 因历史原因元数据极少，需要查 information_schema 多个表才能拼齐。

### 环境变量用于客户端而非服务端

主流引擎的服务端**很少**通过环境变量配置。主要原因：

- 服务作为 systemd 单元运行，环境变量 = unit 文件中 `Environment=`
- 比配置文件更难审计和版本化
- 多个进程共享同一环境，污染风险大

客户端（psql / mysql / sqlplus）用环境变量很常见，因为：

- 短生命周期进程
- 用户的 shell 环境天然存在
- 适合非交互式脚本

### 引擎设计建议：让 SQL 与文件视图保持一致

推荐做法（PG / Oracle 模式）：任何参数必须能通过 SQL 视图查询；视图同时显示运行时值、文件值、来源、待重启状态；ALTER SYSTEM 修改后视图立即反映新值；文件改动后 SIGHUP / RELOAD CONFIG 能让视图同步。

反面案例（早期 MySQL）：my.cnf 改动后无法通过 SHOW VARIABLES 看到（因为没重启）；SET GLOBAL 改动后无法通过 my.cnf 看到（因为没写文件）；用户必须维护"文件值"和"运行时值"两套心智模型。

### 引擎设计建议：参数作用域应正交

理想的参数作用域分类：INTERNAL（编译期常量）、INSTANCE（进程级）、DATABASE（数据库级）、USER/ROLE（用户级）、SESSION（会话级）、TRANSACTION（事务级）、STATEMENT（语句级）。每个参数应明确属于哪一层。

### 引擎设计建议：错误信息应指向具体文件和行号

```
PG 启动失败示例:
  FATAL:  parameter "shared_bufferss" cannot be changed
  HINT:   Configuration file "/var/lib/pgsql/data/postgresql.conf" line 124.

ClickHouse 启动失败示例:
  Code: 36. Cannot parse XML config: not well-formed
  /etc/clickhouse-server/config.xml:142:18
```

提供文件 + 行号信息能让运维快速定位错误，是现代引擎的基本素养。

## 实践建议

### 给 DBA 的建议

1. 不要手工编辑 ALTER SYSTEM 写出的文件（postgresql.auto.conf / mysqld-auto.cnf / spfile.ora），应用 ALTER SYSTEM RESET / RESET PERSIST 撤销
2. 主配置文件应纳入版本控制（postgresql.conf / my.cnf / config.xml 都进 Git；auto.conf / mysqld-auto.cnf 不进）
3. 用 conf.d / include_dir 组织：基础参数 + 环境特定 + 临时调优分文件存放
4. 修改前备份当前值：PG `SELECT * FROM pg_settings WHERE source != 'default'`；Oracle `CREATE PFILE FROM SPFILE`；MySQL `cp my.cnf my.cnf.bak`
5. 静态参数修改后必须 pending_restart 检查：PG `SELECT name FROM pg_settings WHERE pending_restart`

### 给引擎开发者的建议

1. **参数发现性优先**：提供 pg_settings / SHOW PARAMETERS 等 SQL 视图；元数据应包含 type、range、default、source、description、context
2. **文件加载顺序应文档化**：列出所有可能加载的文件路径，明确覆盖关系
3. **错误信息含文件 + 行号**：解析失败时报出具体位置，拼写错误时给出 nearest match 提示
4. **提供"配置 dump"工具**：类似 pg_dumpall --globals-only，可重新加载到全新实例
5. **区分静态 vs 动态参数**：context 字段明确标注 postmaster（静态）/ sighup（可重载）/ user（会话）
6. **提供"试运行"机制**：验证参数语法但不应用，类似 nginx -t / haproxy -c
7. **生效路径应可观察**：SET 后能从 pg_settings.source 看到来源；reload 后能看到 pending_restart 状态
8. **持久化路径应原子**：写文件用 tmp + rename，防止 ALTER SYSTEM 中途崩溃留下半截文件

### 给应用程序开发者的建议

1. 不要在应用层硬编码参数依赖：用 SHOW / SELECT 在启动时检查；关键参数（时区、charset）应显式 SET SESSION
2. 应用启动时打印关键参数，让运维容易发现配置漂移
3. 长连接应用注意 reload 后的不一致：PG SIGHUP 后老连接的某些值不变，必要时主动断连重连

## 参考资料

- PostgreSQL: [Server Configuration](https://www.postgresql.org/docs/current/runtime-config.html)
- PostgreSQL: [ALTER SYSTEM](https://www.postgresql.org/docs/current/sql-altersystem.html)
- PostgreSQL: [pg_hba.conf](https://www.postgresql.org/docs/current/auth-pg-hba-conf.html)
- MySQL: [Using Option Files](https://dev.mysql.com/doc/refman/8.0/en/option-files.html)
- MySQL: [SET PERSIST](https://dev.mysql.com/doc/refman/8.0/en/persisted-system-variables.html)
- Oracle: [Initialization Parameter File](https://docs.oracle.com/en/database/oracle/oracle-database/19/admin/managing-processes.html)
- Oracle: [ALTER SYSTEM SCOPE](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/ALTER-SYSTEM.html)
- SQL Server: [sp_configure](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-configure-transact-sql)
- SQL Server: [Database Scoped Configurations](https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-database-scoped-configuration-transact-sql)
- ClickHouse: [Server Configuration Files](https://clickhouse.com/docs/en/operations/configuration-files)
- ClickHouse: [Settings](https://clickhouse.com/docs/en/operations/settings/settings)
- SQLite: [PRAGMA Statements](https://www.sqlite.org/pragma.html)
- CockroachDB: [Cluster Settings](https://www.cockroachlabs.com/docs/stable/cluster-settings.html)
- TiDB: [Configuration File](https://docs.pingcap.com/tidb/stable/tidb-configuration-file)
- Snowflake: [Parameters](https://docs.snowflake.com/en/sql-reference/parameters)
- Trino: [Properties Reference](https://trino.io/docs/current/admin/properties.html)
- DuckDB: [Configuration](https://duckdb.org/docs/sql/configuration)
