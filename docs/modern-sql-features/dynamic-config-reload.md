# 动态配置重载 (Dynamic Configuration Reload)

凌晨三点，慢查询告警频发，DBA 想把 `log_min_duration_statement` 从 1 秒调到 100 毫秒以抓取更多慢查询样本——如果这一改动需要重启数据库，业务高峰期没有任何 DBA 敢按下回车键。**动态配置重载**就是为这种场景设计的：在不中断服务的前提下，让新的参数值在运行中的进程内立即生效。它是数据库可观测性、可运维性的基石，也是衡量一个引擎成熟度的关键指标。

## 静态参数 vs 动态参数 vs SET 会话级

数据库配置参数按"修改后生效路径"分为三大类：

```
静态参数 (Static / Restart-required):
  - 影响进程启动期分配的资源（共享内存大小、监听端口、字符集编码）
  - 影响数据文件物理结构（页大小、WAL 段大小）
  - 必须重启才能生效，无法热加载
  - 例: PG shared_buffers, MySQL innodb_buffer_pool_size (8.0 之前)

动态参数 (Dynamic / Reload-able):
  - 影响运行时行为（日志级别、查询超时、规划器开关）
  - 不涉及共享内存或物理结构
  - 修改配置文件 + 发送 SIGHUP / 调用 pg_reload_conf() 即可生效
  - 例: PG log_min_duration_statement, MySQL slow_query_log

会话级参数 (Session / SET):
  - 仅影响当前连接，断开即恢复
  - 通过 SQL 命令 SET / SET SESSION / ALTER SESSION 修改
  - 不写入任何持久化文件
  - 例: PG SET work_mem, Oracle ALTER SESSION SET NLS_DATE_FORMAT
```

三者的边界并非绝对：很多参数同时支持多个层级。例如 PostgreSQL 的 `work_mem`：

- 写入 postgresql.conf + reload → 全局动态生效
- `ALTER SYSTEM SET work_mem = '64MB'` → 持久化 + 全局动态
- `ALTER ROLE alice SET work_mem = '128MB'` → 角色级
- `ALTER DATABASE mydb SET work_mem = '256MB'` → 数据库级
- `SET work_mem = '512MB'` → 会话级
- `SET LOCAL work_mem = '1GB'` → 仅当前事务

这种"作用域阶梯"是 GUC（Grand Unified Configuration）系统的精髓，PostgreSQL 把它发挥到了极致，其他引擎多少都借鉴了它的影子。

## SQL 标准的态度

历代 SQL 标准（SQL:1999 / SQL:2003 / SQL:2008 / SQL:2011 / SQL:2016 / SQL:2023）对动态配置重载**完全没有规定**：

- 没有定义"参数"的概念
- 没有规定 reload 语法（SIGHUP？SQL 命令？API 调用？）
- 没有规定参数命名空间
- 没有规定持久化语义
- 没有规定动态/静态分类

唯一与之擦边的是 SQL:1999 的 `SET <session characteristic>` 语句，但它只覆盖会话级（schema、catalog、time zone、isolation level），与服务端持久配置和 reload 完全无关。

结果就是各引擎按各自的历史路径独立演化：

- PostgreSQL 选择了 SIGHUP + SQL 函数 `pg_reload_conf()` + 9.4 引入的 `ALTER SYSTEM`
- MySQL 走 `SET GLOBAL` 路线，2018 年才用 `SET PERSIST` 补齐持久化
- Oracle 把 `SCOPE=SPFILE/MEMORY/BOTH` 三档放在 `ALTER SYSTEM SET` 里
- SQL Server 用近 30 年的 `sp_configure + RECONFIGURE` 双步骤
- ClickHouse 玩文件监视 + `SYSTEM RELOAD CONFIG` 双保险
- CockroachDB / TiDB 走分布式时代的 `SET CLUSTER SETTING`

## 支持矩阵

### SQL ALTER SYSTEM 持久化与重载

修改 SQL 即同时持久化到磁盘 + 运行时生效：

| 引擎 | 持久化语法 | 写入文件 | 引入版本 | 立即生效 | 重启后保留 |
|------|----------|---------|---------|---------|-----------|
| PostgreSQL | `ALTER SYSTEM SET param = val` | postgresql.auto.conf | 9.4 (2014-12) | 需 `pg_reload_conf()` | 是 |
| MySQL | `SET PERSIST var = val` | mysqld-auto.cnf | 8.0 GA (2018-04) | 是 | 是 |
| MySQL | `SET PERSIST_ONLY var = val` | mysqld-auto.cnf | 8.0 GA (2018-04) | 否（仅写文件） | 是 |
| MariaDB | -- | -- | -- | 不支持（10.x/11.x 仍未实现） | -- |
| Oracle | `ALTER SYSTEM SET ... SCOPE=SPFILE` | spfile.ora | 9i (2001) | 否 | 是 |
| Oracle | `ALTER SYSTEM SET ... SCOPE=MEMORY` | -- | 9i (2001) | 是 | 否 |
| Oracle | `ALTER SYSTEM SET ... SCOPE=BOTH` | spfile.ora + 内存 | 9i (2001) | 是 | 是 |
| SQL Server | `sp_configure 'name', val; RECONFIGURE;` | sys.configurations | 6.5 (1996-04) | 是（多数） | 是 |
| SQL Server | `ALTER DATABASE SCOPED CONFIGURATION SET ...` | 数据库元数据 | 2016+ | 是 | 是 |
| SQLite | `PRAGMA name = val` | sqlite_master 头部部分参数 | 3.x | 是 | 部分（如 user_version, journal_mode） |
| ClickHouse | `ALTER USER / ALTER PROFILE` | users.xml + profiles.xml | 早期 | 是 | 是 |
| DB2 | `UPDATE DBM CFG / DB CFG USING param val` | DBM CFG / DB CFG | 早期 | 部分 IMMEDIATE | 是 |
| CockroachDB | `SET CLUSTER SETTING name = val` | system 表（KV） | 1.0 (2017-05) | 是（多数） | 是 |
| TiDB | `SET CLUSTER SETTING / SET GLOBAL` | TiKV 元数据 | 4.0+ (2020) | 是（GLOBAL） | 是 |
| TiDB | `SET CONFIG TIDB / TIKV / PD` | 集群级 | 5.0+ (2021) | 是 | 是 |
| OceanBase | `ALTER SYSTEM SET param = val [TENANT=...]` | observer 元数据 | 1.0+ | 是（多数） | 是 |
| Snowflake | `ALTER ACCOUNT/USER/SESSION SET param = val` | 平台元数据 | GA | 是 | 是（ACCOUNT/USER 层） |
| BigQuery | -- | -- | -- | 不支持，仅 Workgroup/Reservation | -- |
| Redshift | `ALTER USER ... SET / ALTER DATABASE ... SET` | 系统目录 | 早期 | 是 | 是 |
| DuckDB | -- | -- | -- | 不支持持久化（进程级） | -- |
| Trino | -- | -- | -- | 不支持运行时持久化 | -- |
| Presto | -- | -- | -- | 不支持运行时持久化 | -- |
| Spark SQL | `SET`（仅会话） | -- | 2.0+ | 仅会话 | 否 |
| Hive | `SET`（仅会话） | -- | 0.7+ | 仅会话 | 否 |
| Flink SQL | `SET`（仅会话） | -- | 1.11+ | 仅会话 | 否 |
| Greenplum | `ALTER SYSTEM SET`（继承 PG） | postgresql.auto.conf | 6.0+ | 需 `pg_reload_conf()` | 是 |
| YugabyteDB | `ALTER SYSTEM SET`（继承 PG） | postgresql.auto.conf | 2.0+ | 需 `pg_reload_conf()` | 是 |
| TimescaleDB | 继承 PG | 继承 PG | 继承 PG | 同 PG | 是 |
| RisingWave | `ALTER SYSTEM SET / SET CLUSTER SETTING` | meta 节点元数据 | 1.0+ | 是 | 是 |
| Databend | `SET GLOBAL var = val` | meta 节点元数据 | GA | 是 | 是 |
| SAP HANA | `ALTER SYSTEM ALTER CONFIGURATION` | *.ini 多层 | 1.0+ | 是（多数） | 是 |
| Vertica | `ALTER DATABASE / NODE SET` | 系统目录 | 早期 | 是（多数） | 是 |
| Informix | `onmode -wf / -wm` | onconfig | 早期 | wf=writable file, wm=memory | 是 |
| Firebird | `ALTER DATABASE` 部分参数 | 数据库头部 | 2.0+ | 部分 | 是 |
| SingleStore | `SET GLOBAL var = val` | 元数据 | 6.0+ | 是 | 是 |
| StarRocks | `ADMIN SET FRONTEND CONFIG('name'='val')` | FE 元数据 | 早期 | 是（FE 多数） | 是 |
| Doris | `ADMIN SET FRONTEND CONFIG` | FE 元数据 | 早期 | 是（FE 多数） | 是 |
| MonetDB | -- | -- | -- | 多数需 `monetdb stop/start` | -- |
| CrateDB | `SET GLOBAL` | 集群元数据 | 早期 | 是 | 是 |
| QuestDB | -- | -- | -- | 多数需重启 | -- |
| Materialize | `ALTER SYSTEM SET` | 平台元数据 | 0.26+ | 是 | 是 |
| Tarantool | `box.cfg{...}`（Lua） | -- | 1.x | 是（多数） | 否（需脚本持久化） |
| Cassandra | -- | -- | -- | 多数需 nodetool/重启 | -- |
| MongoDB | `db.adminCommand({setParameter: ...})` | -- | 早期 | 是（多数） | 否（重启丢失） |
| H2 | `SET <param>` | -- | 1.0+ | 仅会话/数据库 | 部分 |
| HSQLDB | `SET DATABASE ...` | 数据库文件 | 2.0+ | 是 | 是 |
| Derby | `SYSCS_UTIL.SYSCS_SET_DATABASE_PROPERTY` | 系统目录 | 早期 | 是 | 是 |
| Amazon Athena | -- | -- | -- | 仅 Workgroup/Engine 配置 | -- |
| Azure Synapse | `ALTER DATABASE SCOPED CONFIGURATION` | 数据库元数据 | GA | 是 | 是 |
| Google Spanner | -- | -- | -- | 全托管，Instance 配置 | -- |
| InfluxDB (SQL) | -- | -- | -- | 多数需重启 | -- |
| Yellowbrick | `ALTER SYSTEM SET`（PG 兼容） | -- | GA | 是 | 是 |
| Firebolt | -- | -- | -- | 全托管，Engine setting | -- |
| Teradata | dbscontrol 工具 | DBS Control 二进制 | 早期 | 部分 IMMEDIATE | 是 |
| Impala | -- | -- | -- | 多数需重启 impalad | -- |

> 共统计 50+ 引擎，约 25 个有 SQL 级持久化重载能力，其余依赖文件 + 信号或仅支持会话级 SET。

### 信号 / OS 命令重载

通过 OS 信号或外部命令通知运行进程重读配置：

| 引擎 | SIGHUP 行为 | 显式 reload 命令 | 文件监视 | 说明 |
|------|-----------|----------------|---------|------|
| PostgreSQL | 主进程转发到所有后端 → 重读配置 | `pg_ctl reload` / `SELECT pg_reload_conf()` / `kill -HUP <pid>` | 否 | sighup context 参数立即生效 |
| MySQL | mysqld 仅刷新错误日志/binlog/慢查询日志 | `mysqladmin flush-logs / flush-privileges` | 否 | 不会重读 my.cnf |
| MariaDB | 同 MySQL | 同 MySQL | 否 | 同 MySQL |
| Oracle | -- | `ALTER SYSTEM SET ... SCOPE=MEMORY/BOTH` | 否 | 不依赖 OS 信号 |
| SQL Server | -- | `RECONFIGURE` / `RECONFIGURE WITH OVERRIDE` | 否 | 部分 advanced 参数需重启 |
| SQLite | -- | `PRAGMA` 立即生效 | -- | 进程内库 |
| ClickHouse | 是（自动检测 config.xml mtime） | `SYSTEM RELOAD CONFIG` | 是（每秒轮询） | 三重保险 |
| DB2 | -- | `db2 update dbm cfg using ... immediate` | 否 | IMMEDIATE / DEFERRED 二选一 |
| CockroachDB | -- | `SET CLUSTER SETTING` | 否 | 分布式 KV 同步 |
| TiDB | -- | `SET CLUSTER SETTING / SET CONFIG TIDB ... ` | 否 | PD 协调器分发 |
| OceanBase | -- | `ALTER SYSTEM SET` | 否 | RootService 分发到 OBServer |
| Snowflake | -- | `ALTER ACCOUNT/USER/SESSION SET` | 否 | 全托管 |
| Greenplum | 是（gpstop -u） | `gpstop -u` / `pg_reload_conf()` | 否 | 多 segment 同步重载 |
| YugabyteDB | 是 | `yb-admin set_flag` / `pg_reload_conf()` | 否 | yb-tserver / yb-master flag 独立 |
| Impala | 是 | `kill -HUP impalad` | 否 | 部分 flag 仍需重启 |
| StarRocks | -- | `ADMIN SET FRONTEND CONFIG` / 重启 BE | 否 | FE 动态，BE 静态 |
| Doris | -- | `ADMIN SET FRONTEND CONFIG` / 重启 BE | 否 | 同 StarRocks |
| Vertica | -- | `ALTER DATABASE / NODE SET` | 否 | 多数 IMMEDIATE |
| MonetDB | -- | `monetdb start/stop` | 否 | 多数需重启 |
| Trino | -- | -- | 否 | 必须重启 coordinator/worker |
| Presto | -- | -- | 否 | 必须重启 |
| Spark SQL | -- | `SET`（会话） | 否 | 集群配置改动需重启 |
| Hive | -- | `SET`（会话） | 否 | HiveServer2 改动需重启 |
| Flink SQL | -- | `SET`（会话） | 否 | 集群配置改动需重启 |
| Cassandra | -- | `nodetool reloadlocalschema` 等局部命令 | 否 | cassandra.yaml 多数需重启 |
| MongoDB | 是（mongod 重读日志、刷新部分参数） | `db.adminCommand({setParameter:...})` | 否 | -- |
| SAP HANA | -- | `ALTER SYSTEM ALTER CONFIGURATION` | 否 | RECONFIGURE 子句 |
| Informix | -- | `onmode -wf / -wm` | 否 | wf=写文件+内存, wm=仅内存 |
| Firebird | -- | -- | 否 | 多数需重启 |

### 每会话 SET（运行时不持久化）

仅修改当前会话/连接的参数值：

| 引擎 | 语法 | 重置方式 | 持久化 | 备注 |
|------|------|--------|--------|------|
| PostgreSQL | `SET param = val` / `SET LOCAL param = val` | `RESET param` / `RESET ALL` | 否 | LOCAL 仅当前事务 |
| MySQL | `SET [SESSION] var = val` / `SET @@var = val` | 重连 | 否 | -- |
| MariaDB | 同 MySQL | 同 MySQL | 否 | -- |
| Oracle | `ALTER SESSION SET param = val` | `ALTER SESSION RESET param` | 否 | -- |
| SQL Server | `SET option { ON \| OFF }` | 重连 | 否 | T-SQL 选项语法多样 |
| SQLite | `PRAGMA name = val` | 重连或 `PRAGMA name = default` | 部分 | 部分 PRAGMA 写库头部 |
| ClickHouse | `SET param = val` | 重连或 `SET param = DEFAULT` | 否 | 也支持查询内 `SETTINGS param = val` |
| DB2 | `SET CURRENT param val` | 重连 | 否 | -- |
| CockroachDB | `SET param = val` / `SET LOCAL` | `RESET param` | 否 | -- |
| TiDB | `SET [SESSION] var = val` | 重连 | 否 | -- |
| OceanBase | `SET [SESSION] var = val` / `ALTER SESSION SET` | 重连 | 否 | MySQL/Oracle 模式各自语法 |
| Snowflake | `ALTER SESSION SET param = val` | `ALTER SESSION UNSET` | 否 | -- |
| BigQuery | `SET @@var = val`（脚本级） | 脚本结束 | 否 | -- |
| Redshift | `SET param = val` | `RESET param` | 否 | -- |
| DuckDB | `SET param = val` / `SET SESSION` | `RESET param` | 否 | -- |
| Trino | `SET SESSION prop = val` | `RESET SESSION prop` | 否 | -- |
| Presto | 同 Trino | 同 Trino | 否 | -- |
| Spark SQL | `SET key = val` | -- | 否 | -- |
| Hive | `SET key = val` | -- | 否 | -- |
| Flink SQL | `SET 'key' = 'val'` | `RESET 'key'` | 否 | -- |
| Greenplum | 同 PG | 同 PG | 否 | -- |
| YugabyteDB | 同 PG | 同 PG | 否 | -- |
| TimescaleDB | 同 PG | 同 PG | 否 | -- |
| Vertica | `SET SESSION ...` | -- | 否 | -- |
| StarRocks | `SET [SESSION] var = val` | 重连 | 否 | MySQL 兼容 |
| Doris | 同 StarRocks | 同 StarRocks | 否 | -- |
| SAP HANA | `SET SESSION param = val` | 重连 | 否 | -- |
| H2 | `SET param = val` | 重连 | 否 | -- |
| HSQLDB | `SET SESSION ...` | 重连 | 否 | -- |
| Materialize | `SET param = val` | `RESET param` | 否 | -- |
| RisingWave | `SET param = val` | `RESET param` | 否 | -- |
| Databend | `SET var = val` | -- | 否 | `SET GLOBAL` 才持久化 |
| SingleStore | `SET [SESSION] var = val` | 重连 | 否 | MySQL 兼容 |
| Yellowbrick | `SET param = val` | -- | 否 | PG 兼容 |
| Firebolt | `SET param = val` | -- | 否 | -- |
| Tarantool | `box.session.settings` | -- | 否 | Lua API |
| MongoDB | `setParameter` 命令 | -- | 否 | -- |
| Cassandra | -- | -- | -- | 不支持 SET |
| Impala | `SET option = val` | `UNSET option` | 否 | 查询选项 |
| QuestDB | `SET param = val` | -- | 否 | -- |
| Informix | `SET ENVIRONMENT param val` | -- | 否 | -- |
| MonetDB | `SET param = val` | -- | 否 | -- |
| Firebird | `SET BIND OF / SET TIME ZONE` 等 | -- | 否 | -- |
| Derby | -- | -- | -- | 仅过程内 |
| Athena | -- | -- | -- | 不支持 SET |
| Synapse | `SET option ...`（T-SQL） | 重连 | 否 | -- |
| InfluxDB (SQL) | -- | -- | -- | 不支持 SET |

### 每数据库 / 每角色作用域

为特定数据库或用户/角色预设参数：

| 引擎 | 数据库级 | 角色/用户级 | 预设语法 | 生效时机 |
|------|---------|-----------|---------|---------|
| PostgreSQL | 是 | 是 | `ALTER DATABASE/ROLE name SET param = val` | 新连接生效 |
| MySQL | -- | -- | -- | 不支持 |
| MariaDB | -- | -- | -- | 不支持 |
| Oracle | -- | -- | `ALTER USER ... DEFAULT TABLESPACE` 等 | 仅特定属性 |
| SQL Server | 是 | -- | `ALTER DATABASE SCOPED CONFIGURATION` | 立即 |
| ClickHouse | -- | 是（profile） | `ALTER USER name SETTINGS profile_name` | 新查询生效 |
| Snowflake | -- | 是（USER） | `ALTER USER name SET param = val` | 新会话生效 |
| Redshift | 是 | 是 | `ALTER DATABASE/USER name SET` | 新连接生效 |
| DB2 | 是（DB CFG） | -- | `db2 update db cfg for dbname using ...` | IMMEDIATE 多数 |
| CockroachDB | 是 | 是 | `ALTER ROLE/DATABASE name SET param = val` | 新连接生效 |
| TiDB | -- | 是 | `SET ROLE` 模式有限 | -- |
| OceanBase | 是（TENANT） | 是 | `ALTER SYSTEM SET ... TENANT=name` | 立即 |
| Greenplum | 是 | 是 | 同 PG | 新连接生效 |
| YugabyteDB | 是 | 是 | 同 PG | 新连接生效 |
| TimescaleDB | 是 | 是 | 同 PG | 新连接生效 |
| Vertica | 是 | 是 | `ALTER DATABASE/USER ... SET ...` | 新连接生效 |
| Materialize | 是 | 是 | `ALTER ROLE / SYSTEM` | 新连接生效 |
| RisingWave | -- | 是 | `ALTER USER name SET` | 新连接生效 |
| Yellowbrick | 是 | 是 | 同 PG | 新连接生效 |
| Synapse | 是 | -- | `ALTER DATABASE SCOPED CONFIGURATION` | 立即 |
| 其余引擎 | -- | -- | -- | 不支持 |

### 元数据视图：pending vs current

判断参数是已生效、还是等待重启：

| 引擎 | 视图 / 列名 | pending 标志 | 备注 |
|------|------------|--------------|------|
| PostgreSQL | `pg_settings.pending_restart` | 布尔 | 修改了 postmaster context 参数 |
| MySQL | `performance_schema.persisted_variables` | -- | 列出 mysqld-auto.cnf 内容 |
| MySQL | `performance_schema.variables_info` | VARIABLE_SOURCE | DYNAMIC / GLOBAL / PERSISTED |
| Oracle | `V$PARAMETER.ISMODIFIED` / `ISADJUSTED` | MODIFIED 字段 | TRUE 表示已运行时修改但未写 SPFILE |
| Oracle | `V$SPPARAMETER.ISSPECIFIED` | -- | 区分 SPFILE 与运行时值 |
| SQL Server | `sys.configurations.value` vs `value_in_use` | 是 | value=待生效, value_in_use=当前 |
| ClickHouse | `system.settings.changed` | 是 | 与默认值不同则为 1 |
| ClickHouse | `system.merge_tree_settings` | 同上 | MergeTree 专用 |
| DB2 | `SYSIBMADM.DBCFG.DEFERRED_VALUE` | 是 | DEFERRED 即下次重启生效 |
| CockroachDB | `crdb_internal.cluster_settings.value` | -- | 立即生效，无 pending 概念 |
| TiDB | `INFORMATION_SCHEMA.VARIABLES_INFO` | -- | 来源标注 |
| OceanBase | `__all_sys_parameter` / `oceanbase.GV$OB_PARAMETERS` | -- | EDIT_LEVEL 字段 |
| Snowflake | `SHOW PARAMETERS` | -- | level 字段（ACCOUNT/USER/SESSION） |
| Redshift | `pg_settings`（部分继承） | 部分 | 重启需 reboot 集群 |
| DuckDB | `duckdb_settings()` | -- | 进程级 |
| SAP HANA | `M_INIFILE_CONTENTS` | -- | LAYER_NAME 区分（DEFAULT/HOST/DATABASE） |
| Vertica | `CONFIGURATION_PARAMETERS` | 是 | CHANGE_REQUIRES_RESTART |
| Greenplum | 继承 PG | 继承 PG | 是 |
| YugabyteDB | 继承 PG + flag 状态 | 继承 PG | -- |

## 各引擎深度解析

### PostgreSQL：pg_reload_conf() / SIGHUP / ALTER SYSTEM 三位一体

PostgreSQL 的动态配置系统是开源数据库中设计最严谨、API 最完整的。核心由三件事组成：参数的 context 分类、reload 触发方式、ALTER SYSTEM 持久化。

**pg_reload_conf()：标准的 SQL 级 reload 入口（自 8.1 起）**：

```sql
-- 函数签名：返回布尔，true 表示信号发送成功
SELECT pg_reload_conf();

-- 等价于在 OS 上执行
-- pg_ctl reload -D /var/lib/postgresql/data
-- kill -HUP <postmaster_pid>

-- 检查最近一次 reload 时间
SELECT pg_conf_load_time();
```

`pg_reload_conf()` 内部实现：postmaster 收到 SIGHUP 后，遍历所有子进程（autovacuum launcher、background writer、各 backend）发送 SIGHUP，每个子进程在下一次循环时重新解析 postgresql.conf + postgresql.auto.conf + 命令行参数，并按 context 列决定哪些值能立即生效。

**ALTER SYSTEM：持久化 + 重载（自 9.4，2014-12 起）**：

```sql
-- 修改并写入 postgresql.auto.conf
ALTER SYSTEM SET log_min_duration_statement = '100ms';

-- ALTER SYSTEM 不会自动 reload，必须显式触发
SELECT pg_reload_conf();

-- 撤销 auto.conf 中的设置
ALTER SYSTEM RESET log_min_duration_statement;
ALTER SYSTEM RESET ALL;

-- 修改 postmaster 类参数会标记 pending_restart
ALTER SYSTEM SET shared_buffers = '8GB';
SELECT pg_reload_conf();   -- 不能立即生效

SELECT name, setting, pending_restart
FROM pg_settings
WHERE pending_restart;     -- shared_buffers | 8GB | t
```

`ALTER SYSTEM` 的设计妙处：

1. **绕开文件系统权限**：DBA 不需要登录 OS 主机就能持久化参数
2. **避免直接编辑冲突**：postgresql.conf 由人工维护，postgresql.auto.conf 由 ALTER SYSTEM 维护，互不干扰
3. **加载顺序固定**：postgresql.auto.conf 始终最后加载，保证 ALTER SYSTEM 优先级最高
4. **审计友好**：所有运行时持久化都写到一个文件，git diff 一目了然

**pg_settings.context 列：动态/静态分类的元数据**：

context 列的五个值是 PostgreSQL 配置系统的灵魂：

```
internal    -- 编译期决定（block_size、wal_block_size），不可改
postmaster  -- 主进程启动时决定（shared_buffers, max_connections, port）
            -- 必须重启 (pg_ctl restart) 才能改
sighup      -- 主进程 + 所有后端可热加载（log_min_messages, work_mem 全局值）
            -- pg_reload_conf() / SIGHUP 即可生效
backend     -- 单个后端启动时决定，连接建立后不可改（log_connections）
            -- 修改后只影响新建立的连接
superuser   -- 任何会话可改，但需要超级用户权限（log_executor_stats）
            -- 通过 SET / ALTER SYSTEM
user        -- 任何会话任何用户都可改（work_mem, statement_timeout）
            -- 通过 SET 即可
```

实战中如何利用：

```sql
-- 查看哪些参数需要重启
SELECT name, short_desc
FROM pg_settings
WHERE context = 'postmaster'
ORDER BY category, name;
-- 典型: max_connections, shared_buffers, port, listen_addresses,
--       data_directory, logging_collector, max_wal_senders 等

-- 查看哪些参数 reload 即可
SELECT name, short_desc
FROM pg_settings
WHERE context = 'sighup'
ORDER BY category, name;
-- 典型: log_min_duration_statement, autovacuum_*, wal_level (注意：wal_level 实际是 postmaster!)

-- 查看哪些参数需 superuser 权限才能 SET
SELECT name FROM pg_settings WHERE context = 'superuser';
-- 典型: log_executor_stats, log_planner_stats, log_statement_stats

-- 查看每个参数当前来源
SELECT name, setting, source, sourcefile, sourceline
FROM pg_settings
WHERE source IN ('configuration file', 'database', 'user', 'session', 'override')
ORDER BY name;

-- 找出所有"已被 ALTER SYSTEM 修改"的参数
SELECT name, setting, sourcefile, sourceline
FROM pg_settings
WHERE source = 'configuration file'
  AND sourcefile LIKE '%postgresql.auto.conf%';

-- 找出 pending（修改后尚未生效）的参数
SELECT name, setting, pending_restart
FROM pg_settings
WHERE pending_restart;
```

**作用域阶梯：从全局到事务**：

```sql
-- 1. 全局持久化
ALTER SYSTEM SET work_mem = '64MB';
SELECT pg_reload_conf();

-- 2. 数据库级（新连接到此 db 时生效）
ALTER DATABASE analytics SET work_mem = '128MB';

-- 3. 角色级（该角色新连接时生效）
ALTER ROLE etl_user SET work_mem = '256MB';

-- 4. 会话级
SET work_mem = '512MB';

-- 5. 事务级（COMMIT/ROLLBACK 后失效）
BEGIN;
SET LOCAL work_mem = '1GB';
SELECT * FROM huge_join;
COMMIT;

-- 6. 查询级（PG 16+ 仅特定函数支持）
SELECT * FROM big_table /*+ work_mem='2GB' */;  -- 非标准
```

**实战脚本：扫描 pending_restart 并提示重启**：

```sql
DO $$
DECLARE
    r record;
    cnt int := 0;
BEGIN
    FOR r IN
        SELECT name, setting FROM pg_settings WHERE pending_restart
    LOOP
        RAISE NOTICE 'PENDING RESTART: % = %', r.name, r.setting;
        cnt := cnt + 1;
    END LOOP;
    IF cnt > 0 THEN
        RAISE NOTICE '需要重启数据库以使 % 个参数生效', cnt;
    ELSE
        RAISE NOTICE '所有参数已生效，无需重启';
    END IF;
END $$;
```

### MySQL：SET GLOBAL → SET PERSIST 的演进史

MySQL 的动态配置经历了三个阶段：

1. **MySQL 4.x / 5.x**：`SET GLOBAL` 仅修改运行时值，重启后丢失。改 my.cnf 是唯一的持久化方式
2. **MySQL 8.0 GA（2018-04）**：引入 `SET PERSIST` / `SET PERSIST_ONLY`，把持久化能力收回 SQL 层
3. **MySQL 8.0+**：performance_schema 提供完整的来源追溯

**SET GLOBAL：会话外的全局动态修改**：

```sql
-- 修改全局动态变量，立即对新连接生效
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 0.1;
SET GLOBAL max_connections = 1000;

-- 注意：现有连接不会感知到 GLOBAL 修改（除非该变量也是 SESSION 变量且未被本地 SET）

-- 重启后丢失！
-- mysql > systemctl restart mysqld; mysql >  SHOW GLOBAL VARIABLES LIKE 'long_query_time';
-- 又恢复到 my.cnf 中的值（默认 10）
```

**SET PERSIST：8.0 引入的持久化（2018-04）**：

```sql
-- 修改运行时值 + 写入 mysqld-auto.cnf
SET PERSIST slow_query_log = 'ON';
SET PERSIST long_query_time = 0.1;

-- mysqld-auto.cnf 是 JSON 格式（不是 INI！）
-- 位置: $datadir/mysqld-auto.cnf
{
  "Version": 1,
  "mysql_server": {
    "slow_query_log": {
      "Value": "ON",
      "Metadata": {
        "Timestamp": 1714483200000000,
        "User": "root",
        "Host": "localhost"
      }
    },
    ...
  }
}

-- 启动时加载顺序：
-- 1. /etc/my.cnf (and includes)
-- 2. /etc/mysql/my.cnf
-- 3. ~/.my.cnf
-- 4. mysqld-auto.cnf  ← 始终最后加载，覆盖前面
```

**SET PERSIST_ONLY：仅写文件，不立即应用**：

```sql
-- 适用于静态参数（必须重启的）
SET PERSIST_ONLY innodb_buffer_pool_size = 8589934592;   -- 8GB
-- 不会报"variable cannot be set dynamically"，而是写入 mysqld-auto.cnf
-- 下次重启时生效

-- SET PERSIST 对静态参数会报错：
-- ERROR 1238 (HY000): Variable 'innodb_buffer_pool_size' is a non-dynamic variable
```

**RESET PERSIST：撤销持久化**：

```sql
-- 移除单个变量的持久化
RESET PERSIST slow_query_log;

-- 清空 mysqld-auto.cnf
RESET PERSIST;
-- 等价于删除文件，但通过 SQL 完成审计
```

**FLUSH PRIVILEGES vs FLUSH LOGS**：

MySQL 没有 PG 那种通用的 SIGHUP reload 机制。一些特定的"刷新"命令通过 FLUSH 实现：

```sql
-- 重新加载授权表（grant tables）
-- 适用于直接 INSERT INTO mysql.user 的旧用法
FLUSH PRIVILEGES;
-- 注意：现代用法应使用 CREATE USER / GRANT，无需 FLUSH

-- 关闭并重新打开所有日志文件
-- 用于 logrotate
FLUSH LOGS;
FLUSH BINARY LOGS;
FLUSH SLOW LOGS;
FLUSH ERROR LOGS;

-- 关闭并重新打开表（释放表锁）
FLUSH TABLES;
FLUSH TABLES WITH READ LOCK;   -- 备份用

-- 清空查询缓存（5.7 及之前）
FLUSH QUERY CACHE;
RESET QUERY CACHE;
```

mysqld 收到 SIGHUP 时执行的也只是 `FLUSH LOGS` 类操作，**不会重读 my.cnf**——这是 MySQL 与 PostgreSQL 哲学的根本差异。

**performance_schema 的来源追溯**：

```sql
-- 列出所有持久化变量
SELECT * FROM performance_schema.persisted_variables;
-- VARIABLE_NAME      VARIABLE_VALUE
-- slow_query_log     ON
-- long_query_time    0.1

-- 详细的来源信息
SELECT VARIABLE_NAME, VARIABLE_VALUE,
       VARIABLE_SOURCE,    -- DYNAMIC / GLOBAL / PERSISTED / COMPILED / EXPLICIT
       VARIABLE_PATH,      -- /etc/my.cnf 等
       MIN_VALUE, MAX_VALUE,
       SET_TIME, SET_USER, SET_HOST
FROM performance_schema.variables_info
WHERE VARIABLE_NAME IN ('slow_query_log', 'long_query_time', 'innodb_buffer_pool_size');
```

VARIABLE_SOURCE 的取值：

```
COMPILED        -- 编译期默认值
GLOBAL          -- /etc/my.cnf 等全局配置文件
SERVER          -- $MYSQL_HOME/my.cnf
EXPLICIT        -- 命令行 --variable=value
EXTRA           -- --defaults-extra-file
LOGIN           -- --login-path
COMMAND_LINE    -- 启动命令行
PERSISTED       -- mysqld-auto.cnf
DYNAMIC         -- SET GLOBAL / SET SESSION
```

**MySQL 动态/静态变量分类**：

MySQL 没有 PG 的 context 列那样精细的元数据。要判断动态/静态，需要查 manual：

```sql
-- 大致检测方法：尝试 SET GLOBAL，看是否报错
-- 报错 1238 = 静态变量

-- 实际查询：performance_schema 提供 IS_DYNAMIC（部分版本）
SELECT VARIABLE_NAME
FROM information_schema.GLOBAL_VARIABLES;   -- MySQL 5.x 路径

-- MySQL 8.0 推荐：
SELECT VARIABLE_NAME, VARIABLE_VALUE
FROM performance_schema.global_variables
ORDER BY VARIABLE_NAME;

-- 典型动态：long_query_time, slow_query_log, max_connections (8.0+),
--          binlog_format, sql_mode, time_zone
-- 典型静态：innodb_log_file_size (8.0 之前), datadir, port, socket,
--          character_set_server, collation_server, server_id (大多数版本)
```

### Oracle：SCOPE=SPFILE/MEMORY/BOTH 的三档明示

Oracle 把"修改写到哪里"做成了显式的 SCOPE 子句。这种设计反而最直观：用户每次修改时都明确指定意图。

**SPFILE vs PFILE**：

```bash
# PFILE (init<SID>.ora): 文本文件，可手工编辑
# 9i 之前的唯一选择
$ORACLE_HOME/dbs/initORCL.ora
db_block_size = 8192
sga_target = 2G
processes = 200

# SPFILE (spfile<SID>.ora): 二进制服务器参数文件
# 9i (2001) 引入，禁手工编辑
$ORACLE_HOME/dbs/spfileORCL.ora
```

**ALTER SYSTEM SET ... SCOPE=...**：

```sql
-- SCOPE=SPFILE: 仅写 SPFILE，不影响运行时
-- 适用于静态参数（必须重启）
ALTER SYSTEM SET sga_max_size = 8G SCOPE=SPFILE;
-- 下次重启生效

-- SCOPE=MEMORY: 仅修改运行时，不写 SPFILE
-- 适用于临时调整、测试
ALTER SYSTEM SET optimizer_mode = 'FIRST_ROWS_10' SCOPE=MEMORY;
-- 重启后丢失

-- SCOPE=BOTH: 同时修改运行时 + SPFILE（默认值）
-- 99% 的日常场景
ALTER SYSTEM SET optimizer_mode = 'FIRST_ROWS_10' SCOPE=BOTH;
ALTER SYSTEM SET optimizer_mode = 'FIRST_ROWS_10';   -- 等价

-- 不指定 SCOPE 的默认行为：
-- 如果使用 SPFILE 启动：SCOPE=BOTH
-- 如果使用 PFILE 启动：仅 SCOPE=MEMORY 可用，BOTH 会报错
```

**仅静态参数有 SCOPE=SPFILE 的必要**：

```sql
-- 静态参数：必须 SCOPE=SPFILE 或 BOTH（实际是 SPFILE）
ALTER SYSTEM SET db_block_size = 16384 SCOPE=SPFILE;
-- 注意：db_block_size 实际上不能这么改（创建数据库时已固定）
-- 仅作语法示例

ALTER SYSTEM SET processes = 500 SCOPE=SPFILE;
SHUTDOWN IMMEDIATE;
STARTUP;

-- 动态参数：所有三档都可用
ALTER SYSTEM SET sga_target = 4G;          -- 默认 BOTH
ALTER SYSTEM SET cursor_sharing = 'EXACT'; -- 默认 BOTH
```

**RESET：恢复默认**：

```sql
-- 从 SPFILE 移除，恢复 Oracle 内置默认值
ALTER SYSTEM RESET optimizer_mode SCOPE=SPFILE;

-- 历史上 Oracle 9i/10g 需要 SID 子句
ALTER SYSTEM RESET optimizer_mode SCOPE=SPFILE SID='*';
```

**V$PARAMETER：当前生效值与是否被修改**：

```sql
-- 主要查询视图
SELECT name, value, isdefault, isses_modifiable, issys_modifiable, ismodified
FROM v$parameter
WHERE name LIKE '%cursor%';

-- isses_modifiable: 是否可在会话级 ALTER SESSION
-- issys_modifiable: 是否可在系统级 ALTER SYSTEM
--   IMMEDIATE = 立即生效
--   DEFERRED = 仅对新会话生效
--   FALSE = 必须重启

-- ismodified: 当前会话/系统是否已修改
--   FALSE = 默认值
--   MODIFIED = 已被 ALTER SYSTEM 修改过
--   SYSTEM_MOD = 已被 ALTER SYSTEM 在系统级修改

-- V$SPPARAMETER: 仅查看 SPFILE 中的值
SELECT sid, name, value
FROM v$spparameter
WHERE isspecified = 'TRUE';
-- isspecified: 该参数是否在 SPFILE 中显式设置
```

**SCOPE=DEFERRED 的特殊语义**：

```sql
-- 一些参数支持 DEFERRED：
-- 当前会话保持旧值，新会话使用新值
ALTER SYSTEM SET sort_area_size = 1048576 DEFERRED;

-- 标识哪些参数支持 DEFERRED
SELECT name FROM v$parameter WHERE issys_modifiable = 'DEFERRED';
-- 典型：sort_area_size, sort_area_retained_size, recyclebin
```

**Oracle Data Guard 与 SCOPE 的交互**：

```sql
-- 在主备库之间需要保持参数一致
-- ALTER SYSTEM SET ... SCOPE=BOTH 会自动同步到备库

-- 仅本地（不同步）：
ALTER SYSTEM SET log_archive_dest_state_2 = 'DEFER' SCOPE=BOTH SID='ORCL';
-- SID='ORCL' 限制只在 ORCL 实例生效（RAC 集群）
```

### SQL Server：sp_configure + RECONFIGURE 双步骤（自 6.5 起）

SQL Server 自 1996 年的 6.5 版本起就采用 `sp_configure + RECONFIGURE` 的两步模型，这种设计在分布式时代仍然影响着许多商业数据库。

**两步模型**：

```sql
-- 第一步：修改配置元数据
EXEC sp_configure 'max degree of parallelism', 4;
-- 此时：sys.configurations.value = 4
--       sys.configurations.value_in_use = 0 (旧值)

-- 第二步：让新值在运行时生效
RECONFIGURE;
-- 此时：sys.configurations.value_in_use = 4
```

**为什么要分两步**：

1. **审批流**：DBA 修改配置后，运维负责 RECONFIGURE，避免误改
2. **批量修改**：一次性修改多个参数，最后一次 RECONFIGURE
3. **回滚机会**：sp_configure 后可以 sp_configure 'revert' 取消

**RECONFIGURE WITH OVERRIDE**：

```sql
-- 普通 RECONFIGURE 会校验参数合理性，失败时报错
EXEC sp_configure 'max server memory (MB)', 1;   -- 1MB 太小，会被拒
RECONFIGURE;
-- Msg 5807: ...

-- WITH OVERRIDE 强制接受
EXEC sp_configure 'max server memory (MB)', 1;
RECONFIGURE WITH OVERRIDE;
-- 危险：可能让 SQL Server 启动后立即 OOM
```

**show advanced options：解锁高级参数**：

```sql
-- 默认 sp_configure 只显示基础参数
EXEC sp_configure;

-- 解锁高级参数
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;

-- 现在可以看到/修改 cost threshold for parallelism, max worker threads 等
EXEC sp_configure 'cost threshold for parallelism', 50;
RECONFIGURE;
```

**sys.configurations 元数据**：

```sql
SELECT
    name,
    value,           -- 已 sp_configure 设置的值
    value_in_use,    -- 当前运行时实际使用的值
    minimum,
    maximum,
    is_dynamic,      -- 1 = 动态，无需重启
    is_advanced
FROM sys.configurations
ORDER BY name;

-- 查看哪些设置 pending（已 sp_configure 但未 RECONFIGURE）
SELECT name, value, value_in_use
FROM sys.configurations
WHERE value <> value_in_use;
```

**ALTER DATABASE SCOPED CONFIGURATION（2016+）**：

```sql
-- 数据库级配置，独立于全局
USE myapp;
GO

ALTER DATABASE SCOPED CONFIGURATION
    SET MAXDOP = 8;

ALTER DATABASE SCOPED CONFIGURATION
    SET LEGACY_CARDINALITY_ESTIMATION = ON;

-- 查询数据库级配置
SELECT * FROM sys.database_scoped_configurations;
```

**自 SQL Server 2022 的 IDENTITY_CACHE 等动态新参数**：

近期 SQL Server 把更多参数从静态升级为动态：

```sql
-- 2017+: IDENTITY_CACHE 数据库级
ALTER DATABASE SCOPED CONFIGURATION SET IDENTITY_CACHE = OFF;

-- 2022+: PAUSED_RESUMABLE_INDEX_ABORT_DURATION_MINUTES 等
ALTER DATABASE SCOPED CONFIGURATION
    SET PAUSED_RESUMABLE_INDEX_ABORT_DURATION_MINUTES = 1440;
```

### ClickHouse：SYSTEM RELOAD CONFIG 与文件监视

ClickHouse 走了"双保险"路线：既支持 SQL 命令显式 reload，又对配置文件做时间戳轮询自动 reload。

**SYSTEM RELOAD CONFIG**：

```sql
-- 显式重载所有 config.xml / users.xml 及 *.d/ 子目录
SYSTEM RELOAD CONFIG;

-- 仅重载用户配置（users.xml + users.d/）
SYSTEM RELOAD USERS;

-- 重载字典
SYSTEM RELOAD DICTIONARIES;
SYSTEM RELOAD DICTIONARY mydict;

-- 重载嵌入式字典
SYSTEM RELOAD EMBEDDED DICTIONARIES;

-- 重载查询模型 / 函数
SYSTEM RELOAD MODELS;
SYSTEM RELOAD FUNCTION my_udf;
```

**文件监视（自动 reload）**：

```xml
<!-- config.xml -->
<clickhouse>
    <!-- 文件监视开启（默认 1 秒轮询） -->
    <watch_config_file_period>1</watch_config_file_period>
</clickhouse>
```

ClickHouse 后台线程每秒检查 config.xml / users.xml 的 mtime，发现变化则自动调用 `SYSTEM RELOAD CONFIG`。这意味着：

```bash
# 修改文件即可生效，无需任何额外命令
echo '<clickhouse><logger><level>debug</level></logger></clickhouse>' \
    > /etc/clickhouse-server/config.d/log_level.xml
# 1 秒后日志级别已变为 debug
```

**SIGHUP 同样有效**：

```bash
kill -HUP $(pidof clickhouse-server)
# 等价于 SYSTEM RELOAD CONFIG
```

**zero-downtime 的关键设计**：

ClickHouse 是为高吞吐分析场景设计的，运行中重载配置不能影响查询性能。它通过以下机制保证 zero-downtime：

1. **配置对象不可变**：每次 reload 都重新构造完整的配置对象，正在执行的查询继续持有旧配置的智能指针
2. **写时复制**：用户/角色/profile 修改不影响活动会话
3. **原子切换**：新配置整体生效，没有"半生效"状态
4. **错误回滚**：reload 失败时保留旧配置，不会让进程进入异常状态

```sql
-- 典型场景：调整查询并发限制
-- /etc/clickhouse-server/users.d/limits.xml
SYSTEM RELOAD CONFIG;
-- 已建立的连接：旧 max_concurrent_queries 值
-- 新建连接：新值

-- 查看当前生效设置
SELECT name, value, changed
FROM system.settings
WHERE changed = 1;

-- 查看 MergeTree 设置
SELECT name, value, changed, type, description
FROM system.merge_tree_settings
WHERE changed = 1;
```

**ALTER USER / ALTER PROFILE：SQL 级用户管理**：

```sql
-- 创建 profile 并立即生效
CREATE SETTINGS PROFILE analyst SETTINGS
    max_memory_usage = 10000000000,
    max_execution_time = 300;

-- 修改 profile（影响所有引用此 profile 的用户）
ALTER SETTINGS PROFILE analyst SETTINGS
    max_memory_usage = 20000000000;
-- 立即生效，无需 SYSTEM RELOAD CONFIG

-- 给用户绑定 profile
ALTER USER alice SETTINGS PROFILE analyst;
```

### CockroachDB：SET CLUSTER SETTING（绝大多数立即生效）

CockroachDB 是分布式时代生长出来的新一代数据库，它从设计之初就把"零重启"作为目标。

**SET CLUSTER SETTING：唯一的全局配置入口**：

```sql
-- 修改集群级设置
SET CLUSTER SETTING sql.defaults.distsql = 'on';
SET CLUSTER SETTING server.remote_debugging.mode = 'local';
SET CLUSTER SETTING jobs.retention_time = '720h';

-- 立即生效，写入 system.settings 表
-- 通过 Raft 协议同步到所有节点，几秒内全集群一致

-- 查看所有
SHOW ALL CLUSTER SETTINGS;

-- 查看某个
SHOW CLUSTER SETTING sql.defaults.distsql;

-- 重置为默认
RESET CLUSTER SETTING sql.defaults.distsql;
```

**system.settings 表结构**：

```sql
SELECT * FROM system.settings;
-- name                          | value      | last_updated | type | reason
-- sql.defaults.distsql          | on         | 2026-04-29   | s    |
-- jobs.retention_time           | 720h0m0s   | 2026-04-29   | d    |

-- crdb_internal 提供更详细元数据
SELECT variable, value, type, public, description
FROM crdb_internal.cluster_settings
WHERE variable LIKE 'sql.defaults.%';
```

**几乎没有静态参数**：

CockroachDB 的设计哲学是"flag 用于启动 + cluster setting 用于运行时"：

```bash
# 启动时通过 flag
cockroach start --insecure --listen-addr=:26257 --http-addr=:8080 \
    --store=path=/data,size=80%

# 运行时只用 SQL
# SET CLUSTER SETTING ...
```

仅极少数参数必须重启（如 `--store` 路径、`--listen-addr`）。日常 99% 的调优都是动态的。

### TiDB：SET CONFIG TIDB / SET CLUSTER SETTING

TiDB 走了 MySQL 兼容 + 分布式扩展的路线。

**MySQL 兼容的 SET GLOBAL**：

```sql
-- 兼容 MySQL 协议
SET GLOBAL tidb_distsql_scan_concurrency = 30;
SET GLOBAL tidb_index_lookup_concurrency = 8;
SET GLOBAL tidb_disable_txn_auto_retry = OFF;

-- 立即生效，写入 mysql.tidb 表
SHOW GLOBAL VARIABLES LIKE 'tidb_distsql_scan_concurrency';
```

**SET CONFIG：跨 TiDB / TiKV / PD 组件**：

```sql
-- 修改所有 TiDB 节点的运行时配置
SET CONFIG TIDB log.level = 'info';

-- 修改特定 TiDB 实例
SET CONFIG TIDB '127.0.0.1:4000' log.level = 'debug';

-- 修改 TiKV 配置（注意：TiKV 多数配置仍需重启）
SET CONFIG TIKV raftstore.raft-base-tick-interval = '1s';

-- 修改 PD 配置
SET CONFIG PD schedule.leader-schedule-limit = 10;

-- 查询当前配置
SELECT * FROM information_schema.CLUSTER_CONFIG
WHERE TYPE = 'tidb' AND `KEY` = 'log.level';
```

**INFORMATION_SCHEMA.VARIABLES_INFO**：

```sql
-- TiDB 5.0+ 提供变量来源追溯
SELECT VARIABLE_NAME, VARIABLE_VALUE,
       DEFAULT_VALUE, CURRENT_VALUE,
       MIN_VALUE, MAX_VALUE,
       VARIABLE_SCOPE,    -- SESSION / GLOBAL / NONE
       IS_NOOP            -- 兼容性占位变量（无实际效果）
FROM INFORMATION_SCHEMA.VARIABLES_INFO
WHERE VARIABLE_NAME LIKE 'tidb_%';
```

### SAP HANA：ALTER SYSTEM ALTER CONFIGURATION

SAP HANA 把多个 .ini 文件（global.ini、indexserver.ini、nameserver.ini 等）做成"层"（LAYER）：

```sql
-- 修改全局配置
ALTER SYSTEM ALTER CONFIGURATION ('global.ini', 'SYSTEM')
    SET ('memorymanager', 'global_allocation_limit') = '107374182400'
    WITH RECONFIGURE;
-- WITH RECONFIGURE 立即生效；不加则下次重启生效

-- 修改 host 层
ALTER SYSTEM ALTER CONFIGURATION ('global.ini', 'host', 'host01')
    SET ('persistence', 'savepoint_interval_s') = '900'
    WITH RECONFIGURE;

-- 删除层（恢复上层默认）
ALTER SYSTEM ALTER CONFIGURATION ('global.ini', 'SYSTEM')
    UNSET ('memorymanager', 'global_allocation_limit')
    WITH RECONFIGURE;

-- 查询当前生效配置
SELECT * FROM M_INIFILE_CONTENTS
WHERE FILE_NAME = 'global.ini'
  AND SECTION = 'memorymanager';
-- LAYER_NAME 字段标明值来自哪一层（DEFAULT / SYSTEM / DATABASE / HOST）
```

层级解析顺序（从低到高）：

```
DEFAULT      -- HANA 内置默认
SYSTEM       -- 集群级
DATABASE     -- 数据库级（多租户）
HOST         -- 主机级
```

### DB2：db2 update db cfg / db2set

DB2 的配置分为三层：DBM CFG（实例级）、DB CFG（数据库级）、Registry（DB2SET 系统注册表）。

**DBM CFG（数据库管理器级别）**：

```bash
# 修改实例级参数
db2 update dbm cfg using NUMDB 32 immediate

# IMMEDIATE: 立即生效
# DEFERRED: 下次重启生效（默认）

db2 get dbm cfg
db2 get dbm cfg show detail   # 显示运行时值 vs DEFERRED 值
```

**DB CFG（数据库级别）**：

```bash
# 修改数据库级参数
db2 update db cfg for sales using LOGFILSIZ 4000 immediate
db2 update db cfg for sales using SORTHEAP AUTOMATIC

# 查询
db2 get db cfg for sales
db2 get db cfg for sales show detail
```

**db2set（注册表）**：

```bash
# 多数 db2set 修改需重启实例
db2set DB2_SKIPINSERTED=ON
db2set -all   # 查看
```

**SYSIBMADM.DBCFG SQL 视图**：

```sql
-- 通过 SQL 查询配置
SELECT NAME, VALUE, DEFERRED_VALUE, DATATYPE
FROM SYSIBMADM.DBCFG
WHERE NAME LIKE 'log%';

-- DEFERRED_VALUE: 下次重启生效的值（与 VALUE 不同则表示 pending）
-- DATATYPE: integer / character / varchar 等
```

## PostgreSQL pg_settings.context 列深度对比

`pg_settings.context` 是 PostgreSQL 配置元数据系统的核心，决定了参数能否在不重启的情况下生效。理解它对调优极其重要。

### 七种 context 值

PG 16+ 实际包含以下 context 值（早期版本只有五种）：

```
internal     -- 编译期决定，运行时绝对不可改
postmaster   -- 主进程启动时决定，必须重启
sighup       -- SIGHUP 后重读配置，立即生效（包括所有后端）
backend      -- 单后端启动时决定，连接后不可改
superuser-backend  -- 同 backend 但仅超级用户能改
superuser    -- 任意会话可改但需超级用户权限
user         -- 任意会话任意用户都可改
```

### 各 context 典型参数

```sql
-- internal: 编译期决定
SELECT name, setting FROM pg_settings WHERE context = 'internal';
--  block_size                | 8192
--  data_checksums            | off
--  data_directory_mode       | 0700
--  segment_size              | 131072
--  server_encoding           | UTF8
--  server_version            | 16.1
--  wal_block_size            | 8192
--  wal_segment_size          | 16777216

-- postmaster: 必须重启
SELECT name FROM pg_settings WHERE context = 'postmaster' ORDER BY name;
--  archive_mode
--  autovacuum_freeze_max_age
--  cluster_name
--  config_file
--  data_directory
--  hba_file
--  ident_file
--  listen_addresses
--  log_destination (部分情况)
--  logging_collector
--  max_connections
--  max_files_per_process
--  max_locks_per_transaction
--  max_prepared_transactions
--  max_wal_senders
--  max_worker_processes
--  port
--  shared_buffers
--  shared_preload_libraries
--  superuser_reserved_connections
--  unix_socket_directories
--  wal_buffers (PG 9.0+ 自动)
--  wal_level
--  ...

-- sighup: pg_reload_conf() 即可
SELECT count(*) FROM pg_settings WHERE context = 'sighup';
-- 约 100+ 个参数
SELECT name FROM pg_settings WHERE context = 'sighup' ORDER BY name LIMIT 30;
--  archive_command
--  authentication_timeout
--  autovacuum
--  autovacuum_max_workers
--  autovacuum_naptime
--  bgwriter_delay
--  bgwriter_lru_maxpages
--  bgwriter_lru_multiplier
--  checkpoint_completion_target
--  checkpoint_flush_after
--  checkpoint_timeout
--  checkpoint_warning
--  effective_cache_size
--  log_autovacuum_min_duration
--  log_checkpoints
--  log_connections
--  log_destination (有时)
--  log_disconnections
--  log_duration
--  log_executor_stats
--  log_hostname
--  log_line_prefix
--  log_lock_waits
--  log_min_duration_sample
--  log_min_duration_statement
--  log_min_error_statement
--  log_min_messages
--  log_planner_stats
--  log_rotation_age
--  log_rotation_size
--  ...

-- backend: 连接级
SELECT name FROM pg_settings WHERE context = 'backend' ORDER BY name;
--  ignore_system_indexes
--  jit_debugging_support
--  jit_dump_bitcode
--  jit_expressions
--  jit_profiling_support
--  log_connections
--  log_disconnections
--  post_auth_delay
--  pre_auth_delay

-- user: 任何会话可改
SELECT count(*) FROM pg_settings WHERE context = 'user';
-- 约 200+ 个参数（最大类）

-- superuser: 需要超级用户
SELECT name FROM pg_settings WHERE context = 'superuser' ORDER BY name LIMIT 10;
--  log_executor_stats
--  log_planner_stats
--  log_statement_stats
--  pg_stat_statements.track
--  zero_damaged_pages
--  ...
```

### 实战脚本：智能 reload 工具

```sql
-- 检查所有未生效的配置
WITH pending AS (
    SELECT name, setting, pending_restart
    FROM pg_settings
    WHERE pending_restart
)
SELECT
    CASE
        WHEN COUNT(*) = 0 THEN '所有参数已生效'
        ELSE '需要重启 ' || COUNT(*) || ' 个参数'
    END AS status,
    string_agg(name || '=' || setting, ', ') AS pending_params
FROM pending;

-- 检查所有可热加载但 conf 与 auto.conf 不一致的
SELECT name, setting, source, sourcefile, sourceline
FROM pg_settings
WHERE context IN ('sighup', 'superuser', 'user')
  AND sourcefile LIKE '%postgresql.auto.conf%'
ORDER BY name;
```

## MySQL 动态变量 vs 静态变量分类

MySQL 没有 PG 那种 context 列的精细分类，需要从文档归类。下面给出主要变量的分类。

### 完全静态（必须重启）

```
character_set_filesystem    -- 字符集
character_set_system        -- 字符集
datadir                     -- 数据目录
default_storage_engine      -- 默认引擎（动态可改但建议重启确认）
innodb_data_file_path       -- 系统表空间
innodb_data_home_dir        -- 系统表空间路径
innodb_log_files_in_group   -- redo log 文件数（8.0 之前）
innodb_log_file_size        -- redo log 文件大小（8.0 之前）
innodb_page_size            -- innodb 页大小
innodb_undo_directory       -- undo 表空间路径
innodb_undo_tablespaces     -- undo 表空间数量（5.7+ 部分动态）
log_bin                     -- 启用 binlog
log_bin_basename            -- binlog 文件名
plugin_dir                  -- 插件目录
port                        -- 监听端口
relay_log                   -- relay log 文件名
server_id                   -- 服务器 ID（5.7 起部分版本动态）
skip_networking             -- 是否禁用 TCP
socket                      -- Unix socket 路径
ssl_ca / ssl_cert / ssl_key -- SSL 证书
sync_binlog                 -- (动态)
tmpdir                      -- 临时文件目录
```

### 动态（SET GLOBAL 即可）

```
autocommit                  -- 自动提交
binlog_cache_size           -- binlog 缓存
binlog_format               -- ROW / STATEMENT / MIXED
character_set_server        -- 服务器字符集
collation_server            -- 服务器排序规则
connect_timeout             -- 连接超时
event_scheduler             -- 事件调度器
expire_logs_days            -- binlog 过期天数（已废弃）
binlog_expire_logs_seconds  -- binlog 过期秒数（8.0+）
general_log                 -- 通用日志
general_log_file            -- 通用日志文件
group_concat_max_len        -- GROUP_CONCAT 长度
innodb_adaptive_hash_index  -- 自适应哈希
innodb_buffer_pool_size     -- 缓冲池大小（5.7+ 动态）
innodb_change_buffering     -- change buffer
innodb_flush_log_at_trx_commit  -- 提交策略
innodb_io_capacity          -- IO 能力
innodb_io_capacity_max      -- 最大 IO
innodb_lock_wait_timeout    -- 锁等待
innodb_log_buffer_size      -- redo 缓冲（8.0+ 动态）
innodb_max_dirty_pages_pct  -- 脏页阈值
innodb_purge_threads        -- (8.0+ 动态)
innodb_thread_concurrency   -- 并发线程
log_output                  -- 日志输出（FILE / TABLE / NONE）
log_slow_admin_statements   -- 记录管理慢日志
log_warnings                -- 警告日志级别
long_query_time             -- 慢查询阈值
max_allowed_packet          -- 最大包大小
max_connections             -- 最大连接（5.7+ 动态）
max_user_connections        -- 用户最大连接
performance_schema_*        -- 仅部分动态
read_only                   -- 只读模式
slow_query_log              -- 慢查询日志
slow_query_log_file         -- 慢查询文件
sql_mode                    -- SQL 模式
super_read_only             -- 超级只读
sync_binlog                 -- binlog 同步策略
table_definition_cache      -- 表定义缓存
table_open_cache            -- 表打开缓存
thread_cache_size           -- 线程缓存
tmp_table_size              -- 临时表内存阈值
transaction_isolation       -- 事务隔离
wait_timeout                -- 连接超时
```

### 仅会话级（SET SESSION）

```
autocommit                  -- 同上但会话级
foreign_key_checks          -- 外键检查
group_concat_max_len        -- 同上
sort_buffer_size            -- 排序缓冲
sql_log_bin                 -- 是否记录 binlog
sql_quote_show_create       -- SHOW CREATE 引用
time_zone                   -- 会话时区
tx_isolation                -- 同 transaction_isolation（已废弃别名）
unique_checks               -- 唯一检查
```

### 检测方法

```sql
-- 尝试 SET GLOBAL，捕获错误
DELIMITER //
CREATE PROCEDURE is_dynamic(IN var_name VARCHAR(64), OUT result VARCHAR(20))
BEGIN
    DECLARE EXIT HANDLER FOR 1238 SET result = 'STATIC';
    DECLARE EXIT HANDLER FOR 1193 SET result = 'NOT_FOUND';
    SET @sql = CONCAT('SET GLOBAL ', var_name, ' = @@', var_name);
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
    SET result = 'DYNAMIC';
END //
DELIMITER ;

CALL is_dynamic('innodb_buffer_pool_size', @r); SELECT @r;   -- DYNAMIC (8.0)
CALL is_dynamic('port', @r);                    SELECT @r;   -- STATIC
```

## ClickHouse 零停机重载的工程细节

ClickHouse 的 zero-downtime 重载是分布式分析数据库中实现得最干净的。它的核心思路：

### 不可变配置对象 + 共享指针

每次 reload 都重新构造一个完整的 `Config` 对象，旧对象由现有查询的 `shared_ptr` 持有，新查询拿到新对象的指针。当旧查询全部结束后，旧 `Config` 自动析构。

```cpp
// 伪代码
class Server {
    std::shared_ptr<Config> current_config;  // 原子指针

    void reloadConfig() {
        auto new_config = std::make_shared<Config>(parseFiles());
        std::atomic_store(&current_config, new_config);
        // 旧查询继续用旧 config，新查询拿到新 config
    }

    Query startQuery() {
        auto cfg = std::atomic_load(&current_config);  // 拿当前快照
        return Query(cfg);
    }
};
```

### 用户/角色变更不踢现有连接

```sql
-- 修改用户权限
ALTER USER alice GRANT SELECT ON db.* ;

-- 已建立的 alice 连接仍持有旧权限快照
-- 新建连接立即使用新权限
-- 这是为了避免 reload 杀死正在执行的长查询
```

### 文件分片：config.d 与 users.d

```
/etc/clickhouse-server/
├── config.xml              -- 主配置
├── config.d/               -- 配置分片
│   ├── log_level.xml
│   ├── network.xml
│   └── memory.xml
├── users.xml               -- 主用户文件
└── users.d/
    ├── default.xml
    └── analyst.xml
```

ClickHouse 同时监视所有这些文件的 mtime。任一变化触发一次完整的 reload（合并所有分片）。

### 错误回滚

```sql
-- 故意引入语法错误
echo '<clickhouse><not_valid_xml></clickhouse>' \
    > /etc/clickhouse-server/config.d/broken.xml

-- 1 秒后日志：
-- "Error reloading config: ... Parse XML failed"
-- "Keeping old config"

-- 进程不会崩溃，旧配置继续工作
SELECT name, value FROM system.settings WHERE name = 'log_level';
-- 仍是旧值
```

### system.events 中的指标

```sql
-- 监控 reload 频率与失败次数
SELECT event, value
FROM system.events
WHERE event LIKE '%Config%';
-- ConfigReloads: 153
-- ConfigReloadFailures: 2
```

## 关键发现

**1. SQL 标准对动态配置完全沉默，各引擎自行其是**

ISO/IEC 9075 任何版本都没有规定参数命名空间、reload 语义、持久化路径。结果是 PostgreSQL、MySQL、Oracle、SQL Server 在这个领域走出了四条完全不同的进化树，互相不兼容。

**2. 三大主流模式：SIGHUP / SCOPE / RECONFIGURE**

- **PostgreSQL 流派**：信号触发 + SQL 函数 + ALTER SYSTEM 持久化（PG / Greenplum / YugabyteDB / TimescaleDB / 部分新引擎）
- **Oracle 流派**：SCOPE 子句明示意图（仅 Oracle，但 OceanBase 部分模仿）
- **SQL Server 流派**：sp_configure + RECONFIGURE 双步骤（仅 SQL Server）
- **新派**：SET CLUSTER SETTING（CockroachDB / TiDB / OceanBase / Snowflake / RisingWave 等分布式新引擎）

**3. 持久化能力是引擎成熟度的分水岭**

`ALTER SYSTEM` / `SET PERSIST` 这种"SQL 即持久化"的能力意味着 DBA 不需要 OS shell 权限就能完成配置变更，对云原生场景至关重要：

- PostgreSQL 9.4 (2014-12)
- Oracle 9i (2001) — 实际上 Oracle 是先驱
- SQL Server 6.5 (1996-04) — 更早，但是非 SQL 标准的 sp_configure
- MySQL 8.0 GA (2018-04) — 最晚的主流引擎之一
- MariaDB — 至今未实现，是 MySQL 兼容生态中的明显落后点

**4. context 元数据的精细化**

PostgreSQL 的 `pg_settings.context` 列（postmaster / sighup / backend / superuser / user）是同类系统中最完整的元数据视图。其他引擎多数只能通过试错（"SET GLOBAL 然后看是否报 1238 错误"）来判断动态/静态。

**5. ClickHouse 的"文件监视 + 信号 + SQL 命令"三重保险**

ClickHouse 是少数同时支持三种触发方式的引擎，且任意一种都能达到 zero-downtime。这种设计源于分析负载对 reload 的高频需求：调试、A/B 测试、动态限流。

**6. MySQL 的 SIGHUP 历史包袱**

mysqld 收到 SIGHUP 时只刷新日志文件，不会重读 my.cnf——这是从 MySQL 早期一直延续到今天的设计。结果是 SET PERSIST + mysqld-auto.cnf 才是真正的"运行时配置 API"。

**7. 分布式时代的 SET CLUSTER SETTING**

CockroachDB / TiDB 等分布式 SQL 引擎从设计之初就把"零重启"作为目标。它们几乎没有静态参数，所有调优都通过 SET CLUSTER SETTING 完成，背后用 Raft 协议同步到所有节点。这种设计将"修改配置"从一项 OPS 操作降级为一条 SQL，是云原生数据库的范式标志。

**8. 全托管引擎的"配置黑盒化"**

Snowflake / BigQuery / Aurora / 等全托管平台只暴露极少数运行时可调参数（多数走 ALTER ACCOUNT / Reservation API / Workgroup），底层引擎参数对用户不可见。这种设计减少了 DBA 心智负担，代价是失去精细调优能力。

**9. 持久化文件的格式演进**

- **文本 INI**：MySQL my.cnf, ClickHouse 部分文件
- **文本 KEY=VALUE**：PostgreSQL postgresql.conf, Spark spark-defaults.conf
- **二进制**：Oracle SPFILE, SQL Server 注册表
- **JSON**：MySQL mysqld-auto.cnf（8.0 引入，方便程序解析）
- **YAML**：Cassandra, MongoDB, Flink
- **TOML**：TiDB, RisingWave, Databend（现代云原生选择）
- **XML**：ClickHouse, Hive
- **无文件**：CockroachDB（KV 存储）, Snowflake / BigQuery（平台内部）

JSON / TOML 的兴起反映了"配置即数据"的现代理念：人写也能读，程序读也方便。

**10. pending_restart 标志的价值**

PostgreSQL 的 `pg_settings.pending_restart` 让 DBA 能精确知道哪些 ALTER SYSTEM 修改还没生效。SQL Server 的 `value vs value_in_use` 起到同样作用，DB2 的 `DEFERRED_VALUE` 类似。这种"显式区分待生效与已生效"是高质量配置系统的标志，但仍有许多引擎缺失（MySQL 直到 8.0 也没有真正的 pending 标志）。

## 对引擎实现者的建议

**1. 提供细粒度的 context 元数据**

不要让用户通过试错来发现"哪些参数能热改、哪些必须重启"。在元数据视图（如 `pg_settings.context`）中明确分类，并通过文档/工具暴露。

**2. ALTER SYSTEM 与配置文件分离**

把 ALTER SYSTEM 的产物写到独立文件（PG 的 postgresql.auto.conf, MySQL 的 mysqld-auto.cnf），不污染人工维护的主配置。加载顺序固定为最后，保证 SQL 持久化优先级最高。

**3. 提供 pending vs current 的显式区分**

通过元数据视图（pending_restart, value vs value_in_use, DEFERRED_VALUE）让用户清楚知道"现在生效的值"与"等待重启才生效的值"。否则 DBA 会在重启后发现"我以为改好了的参数其实没有生效"。

**4. zero-downtime reload 是云原生的入场券**

实现"修改配置时不影响活动查询"需要：

- 配置对象不可变（Config-as-Snapshot）
- 写时复制（COW）/ shared_ptr 引用计数
- 错误回滚（解析失败保留旧配置）
- 多文件原子合并（config.d / users.d）

**5. 信号 + SQL + 文件监视，至少支持两种**

只支持单一 reload 触发方式（如纯 SIGHUP 或纯 SQL）会限制不同运维场景的灵活性。推荐至少支持 SQL 命令 + 信号；高级实现可加文件 mtime 监视。

**6. 作用域阶梯：从全局到事务**

完整的作用域阶梯应包括：

```
全局持久化（ALTER SYSTEM）
  ↓
数据库级（ALTER DATABASE ... SET）
  ↓
角色/用户级（ALTER ROLE ... SET）
  ↓
会话级（SET）
  ↓
事务级（SET LOCAL）
  ↓
查询级（hint）
```

PostgreSQL 是这套阶梯实现最完整的，其他引擎可参考。

**7. 持久化文件用人机皆可读的格式**

JSON / TOML / YAML 优于二进制，方便：
- 备份/恢复（git diff）
- 配置漂移检测
- 多节点同步
- 灾难恢复时手动编辑

**8. 提供"配置漂移"诊断工具**

```sql
-- PG 风格：找出 conf 与 auto.conf 冲突的参数
SELECT name, setting, source, sourcefile
FROM pg_settings
WHERE source = 'configuration file'
  AND sourcefile LIKE '%auto.conf%';
```

或者提供命令行工具对比文件参数与运行时参数。

**9. 集群级 reload 的协调**

分布式数据库要解决"多节点配置一致性"：

- Raft / Paxos 同步（CockroachDB, TiDB）
- 中央 coordinator 推送（Snowflake, OceanBase）
- 滚动 reload（每个节点独立）

无论选哪种，都要保证 reload 期间不会出现"半数节点新配置 + 半数旧配置"导致的查询行为不一致。

## 参考资料

- PostgreSQL: [Server Configuration](https://www.postgresql.org/docs/current/runtime-config.html)
- PostgreSQL: [pg_reload_conf](https://www.postgresql.org/docs/current/functions-admin.html#FUNCTIONS-ADMIN-SIGNAL)
- PostgreSQL: [ALTER SYSTEM](https://www.postgresql.org/docs/current/sql-altersystem.html)
- PostgreSQL: [pg_settings View](https://www.postgresql.org/docs/current/view-pg-settings.html)
- MySQL: [Persisted System Variables](https://dev.mysql.com/doc/refman/8.0/en/persisted-system-variables.html)
- MySQL: [Dynamic and Persistent Variables](https://dev.mysql.com/doc/refman/8.0/en/dynamic-system-variables.html)
- MySQL: [SET PERSIST](https://dev.mysql.com/doc/refman/8.0/en/set-variable.html)
- Oracle: [ALTER SYSTEM](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/ALTER-SYSTEM.html)
- Oracle: [V$PARAMETER](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/V-PARAMETER.html)
- SQL Server: [sp_configure](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-configure-transact-sql)
- SQL Server: [RECONFIGURE](https://learn.microsoft.com/en-us/sql/t-sql/language-elements/reconfigure-transact-sql)
- SQL Server: [ALTER DATABASE SCOPED CONFIGURATION](https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-database-scoped-configuration-transact-sql)
- ClickHouse: [SYSTEM Statements](https://clickhouse.com/docs/en/sql-reference/statements/system)
- ClickHouse: [Configuration Files](https://clickhouse.com/docs/en/operations/configuration-files)
- CockroachDB: [SET CLUSTER SETTING](https://www.cockroachlabs.com/docs/stable/set-cluster-setting.html)
- TiDB: [System Variables](https://docs.pingcap.com/tidb/stable/system-variables)
- TiDB: [SET CONFIG](https://docs.pingcap.com/tidb/stable/sql-statement-set-config)
- DB2: [Configuration Parameters](https://www.ibm.com/docs/en/db2/11.5?topic=parameters-database-configuration)
- SAP HANA: [ALTER SYSTEM ALTER CONFIGURATION](https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/20d3eb15751910148ff5dab1eaa2b2e1.html)
- 服务端配置文件 (server-config-files.md)
- 变量与会话管理 (variables-sessions.md)
