# 滚动升级 (Rolling Upgrade)

数据库升级一直是运维工程师最害怕的工作——业务停机、数据回滚、版本回退、复制断链，每一项都可能让一次例行升级演变为通宵抢修。滚动升级 (Rolling Upgrade) 是工业界对"零停机升级"的标准答案：在多副本拓扑里逐台滚动替换，让客户端始终能连到至少一个可用副本，把不可避免的版本切换分散到一段安全的时间窗口里。

## 为什么需要滚动升级

数据库升级的本质矛盾是：**新版本与旧版本必须能在同一时刻共存**。

- **传统 in-place 升级**：停服 → 二进制替换 → 数据文件升级 → 重启。优点是简单，缺点是停机时间不可控（数据字典升级在大库上可能数十分钟），并且一旦出错难以回退。
- **side-by-side 升级**：搭建新集群 → 数据迁移 → 切流量。优点是回退方便，缺点是占用双倍硬件资源，并且需要停业务做最后一次同步。
- **滚动升级 (Rolling Upgrade)**：利用主从/多副本拓扑，逐节点升级，每次升级只让一台副本下线。优点是接近零停机，缺点是要求新旧版本能跨版本复制，并且需要明确的 fallback 路径。

围绕"新旧版本如何共存"这个问题，业界形成了三类解决方案：

1. **物理复制兼容**：新旧版本的 redo/WAL 格式必须兼容，主库可以发送给副本回放。这通常只支持小版本（minor version）滚动升级。PostgreSQL 流复制、Oracle Data Guard Physical Standby、SQL Server AlwaysOn 都属此类。
2. **逻辑复制兼容**：新旧版本通过 SQL 级别（行变更）回放，跨大版本（major version）也能工作。PostgreSQL Logical Replication、MySQL binlog、Oracle GoldenGate / Transient Logical Standby 都属此类。
3. **共识协议内置**：分布式数据库通过 Raft/Paxos 协议天然支持节点逐个替换。CockroachDB、TiDB、YugabyteDB 等都属此类。

> 本文不涉及 SQL 标准——滚动升级至今没有任何 ISO SQL 标准化条款，所有语法、流程、版本兼容矩阵都是厂商专有的。

跨版本复制的兼容窗口对滚动升级至关重要：

- **MySQL** 官方支持低版本主库 → 高版本从库（向上兼容），反向不保证
- **PostgreSQL** 物理复制要求主从相同主版本 + 相同 WAL 格式，逻辑复制可跨主版本
- **Oracle Data Guard** 物理 standby 要求版本相同，**transient logical standby** 是官方推荐的跨版本升级路径
- **SQL Server AlwaysOn** 支持滚动升级，但要求次要版本兼容

## 支持矩阵

### 1. 滚动升级与跨版本复制能力

| 引擎 | 滚动升级（小版本） | 滚动升级（大版本） | 跨版本物理复制 | 跨版本逻辑复制 | 引入年份 |
|------|------------------|------------------|---------------|---------------|---------|
| PostgreSQL | 是（物理复制） | 是（逻辑复制） | -- | 10+ (2017) | 2010 (pg_upgrade), 2017 (logical) |
| MySQL | 是（GR / 主从） | 受限（dump/restore） | -- | binlog | 5.7+ (2015), GR 8.0 |
| MariaDB | 是（Galera / 主从） | 受限（dump/restore） | -- | binlog | 10.x |
| SQLite | -- | -- | -- | -- | 不适用 |
| Oracle | 是（Data Guard） | 是（Transient Logical Standby） | 部分（Active Data Guard） | GoldenGate | 11g (2007) |
| SQL Server | 是（AlwaysOn / 镜像） | 受限（迁移） | -- | Transactional Replication | 2012 |
| DB2 | 是（HADR） | 受限（dump/restore） | 受限 | Q Replication | 9.x |
| Snowflake | 是（云托管） | 是（云托管） | -- | -- | GA |
| BigQuery | 是（云托管） | 是（云托管） | -- | -- | GA |
| Redshift | 是（云托管） | 是（云托管） | -- | -- | GA |
| DuckDB | -- | -- | -- | -- | 不适用 |
| ClickHouse | 是（ReplicatedMergeTree） | 受限 | -- | -- | 早期 |
| Trino | 是（无状态查询引擎） | 是（无状态） | -- | -- | 早期 |
| Presto | 是（无状态查询引擎） | 是（无状态） | -- | -- | 早期 |
| Spark SQL | 是（无状态） | 是（无状态） | -- | -- | 早期 |
| Hive | 是（HiveServer2 多实例） | 是（多实例） | -- | -- | 1.x |
| Flink SQL | 是（Savepoint 升级） | 是（Savepoint 升级） | -- | -- | 1.0+ |
| Databricks | 是（云托管） | 是（云托管） | -- | -- | GA |
| Teradata | 是（Dual Active） | 受限 | 部分 | Replication Services | 早期 |
| Greenplum | 是（mirror） | 受限（gpbackup） | -- | -- | 5.x |
| CockroachDB | 是（cluster.preserve_downgrade_option） | 是 | -- | -- | 1.x (2017) |
| TiDB | 是（TiUP） | 是（TiUP） | -- | TiCDC | 4.0+ |
| OceanBase | 是（多 Zone） | 是（多 Zone） | -- | OBCDC | 1.x |
| YugabyteDB | 是（yb-master + yb-tserver） | 是 | -- | xCluster | 2.x |
| SingleStore | 是（多副本） | 是 | -- | -- | 6.0+ |
| Vertica | 是（K-safety） | 受限 | -- | -- | 早期 |
| Impala | 是（无状态） | 是（无状态） | -- | -- | 早期 |
| StarRocks | 是（FE/BE 多副本） | 是 | -- | -- | 2.0+ |
| Doris | 是（FE/BE 多副本） | 是 | -- | -- | 1.0+ |
| MonetDB | -- | -- | -- | -- | 不支持 |
| CrateDB | 是（滚动重启） | 是（dump/restore） | -- | -- | 4.0+ |
| TimescaleDB | 继承 PG | 继承 PG | 继承 PG | 继承 PG | 继承 PG |
| QuestDB | -- | -- | -- | -- | 不支持 |
| Exasol | 是（多节点） | 受限 | -- | -- | 早期 |
| SAP HANA | 是（System Replication） | 是（hdblcm） | -- | -- | 2.0 SPS01+ |
| Informix | 是（HDR / RSS） | 受限 | -- | Enterprise Replication | 早期 |
| Firebird | -- | -- | -- | -- | 不支持 |
| H2 | -- | -- | -- | -- | 不适用 |
| HSQLDB | -- | -- | -- | -- | 不适用 |
| Derby | -- | -- | -- | -- | 不适用 |
| Amazon Athena | 云托管 | 云托管 | -- | -- | GA |
| Azure Synapse | 云托管 | 云托管 | -- | -- | GA |
| Google Spanner | 是（云托管） | 是（云托管） | -- | -- | GA |
| Materialize | 是（云托管） | 是（云托管） | -- | -- | GA |
| RisingWave | 是（云托管） | 是（云托管） | -- | -- | GA |
| InfluxDB | 是（多副本） | 受限 | -- | -- | 2.x |
| MongoDB | 是（Replica Set） | 是（Replica Set） | -- | -- | 2.x |
| Cassandra | 是（节点逐台替换） | 是 | -- | -- | 早期 |
| ScyllaDB | 是（节点逐台替换） | 是 | -- | -- | 早期 |
| DatabendDB | 是（云托管） | 是（云托管） | -- | -- | GA |
| Yellowbrick | 是（多副本） | 受限 | -- | -- | GA |
| Firebolt | 云托管 | 云托管 | -- | -- | GA |

> 统计：约 35 个引擎支持某种形式的滚动升级（小版本至少），约 22 个引擎支持完整的跨大版本滚动升级（多通过逻辑复制或共识协议实现），约 8 个嵌入式引擎或本地工具不适用滚动升级概念。

### 2. 升级策略：in-place vs side-by-side vs rolling

| 引擎 | in-place 工具 | side-by-side 工具 | rolling 工具 | 推荐策略 |
|------|--------------|------------------|-------------|---------|
| PostgreSQL | `pg_upgrade` | dump/restore | 流复制 + failover | 小版本 rolling，大版本 logical |
| MySQL | `mysql_upgrade` | mysqldump/mydumper | Group Replication / 主从 + failover | rolling |
| MariaDB | `mariadb-upgrade` | mariadb-dump | Galera | Galera 集群 rolling |
| SQLite | -- | 文件复制 | -- | 应用嵌入升级 |
| Oracle | `dbua` / `catupgrd` | Data Pump | Data Guard switchover | Transient Logical Standby |
| SQL Server | 安装程序 | Backup/Restore | AlwaysOn rolling | AlwaysOn rolling |
| DB2 | `db2level` / `db2_install` | db2move | HADR rolling | HADR rolling |
| MongoDB | `mongod` 替换 | mongodump/mongorestore | Replica Set rolling | Replica Set rolling |
| Cassandra | `nodetool upgradesstables` | sstableloader | 逐节点替换 | 逐节点 rolling |
| CockroachDB | -- | -- | `cockroach node drain` + 二进制替换 | rolling（自动） |
| TiDB | -- | -- | TiUP cluster upgrade | TiUP rolling |
| YugabyteDB | -- | -- | yb-admin upgrade_ysql | rolling（自动） |
| ClickHouse | 二进制替换 + DETACH/ATTACH | -- | ReplicatedMergeTree 逐副本 | 逐副本 rolling |
| StarRocks | -- | -- | StarRocks Manager rolling | rolling |
| Doris | -- | -- | docs:rolling-upgrade | rolling |

### 3. 回退路径 (Rollback Path)

回退能力是滚动升级的"最后保险"，决定了出问题时能否快速回到旧版本。

| 引擎 | 回退方式 | 回退窗口 | 数据兼容 |
|------|---------|---------|---------|
| PostgreSQL pg_upgrade | 必须从 pre-upgrade 备份恢复 | 升级后无法直接回退 | 数据文件不向后兼容 |
| PostgreSQL 流复制 rolling | failover 回到旧主 | 升级期间随时回退 | WAL 兼容 |
| PostgreSQL 逻辑复制 | 切换 subscriber 回旧主 | 副本未删除时可回退 | 行级兼容 |
| MySQL 主从 rolling | failover 回到旧主 | 升级期间随时回退 | binlog 兼容 |
| Oracle Data Guard | switchover 回到旧主 | 整个升级周期 | redo 兼容（若用 transient logical） |
| Oracle DBUA | RMAN restore 或 flashback database | 升级前必须设置还原点 | 数据文件不向后兼容 |
| SQL Server AlwaysOn | failover 回旧 primary | 升级期间随时 | 数据库 compat level |
| CockroachDB | `SET CLUSTER SETTING cluster.preserve_downgrade_option` | 设定时间内 | 数据格式可降级 |
| TiDB | TiUP cluster downgrade | 测试支持，生产慎用 | 各组件数据格式 |
| MongoDB | `setFeatureCompatibilityVersion` (FCV) | FCV 设置期间 | wire/storage 协议 |
| YugabyteDB | yb-admin finalize_upgrade 之前 | finalize 之前 | 类似 CRDB 的 preserve flag |
| ClickHouse | 二进制回退 + DETACH/ATTACH | 升级期间 | 元数据兼容性 |

### 4. 大版本升级的逻辑复制路径

很多引擎在跨大版本时无法继续用物理复制，必须借助逻辑复制工具搭桥。

| 引擎 | 大版本升级官方推荐路径 | 工具 |
|------|---------------------|------|
| PostgreSQL | logical replication / pglogical | `CREATE PUBLICATION` / `pglogical` 扩展 |
| MySQL | dump/restore + binlog catch-up | mysqldump / mydumper + binlog |
| Oracle | Transient Logical Standby | `dbms_logstdby` |
| SQL Server | Backup/Restore + Replication catch-up | Transactional Replication |
| DB2 | dump/restore + Q Replication | Q Replication |
| MongoDB | Replica Set rolling（无需逻辑复制） | mongod -- 各节点直接升级 |
| Cassandra | 节点逐台替换（无需逻辑复制） | nodetool |
| CockroachDB | rolling（无需逻辑复制） | cockroach node drain |
| TiDB | rolling 或 TiCDC + 新集群 | TiUP / TiCDC |

## PostgreSQL：双线作战的滚动升级模型

PostgreSQL 是把"小版本 rolling + 大版本 logical"做得最完整的传统数据库。

### 小版本（minor）滚动升级

PostgreSQL 的小版本升级（例如 16.1 → 16.2）只涉及二进制替换，数据文件格式完全兼容。利用流复制可以实现真正的零停机：

```bash
# 拓扑：primary (16.1) ←─stream─→ standby (16.1)

# 步骤 1：升级 standby
sudo systemctl stop postgresql@16-main      # 停止 standby
# 替换二进制（apt upgrade postgresql-16）
sudo systemctl start postgresql@16-main      # 启动 standby
# 验证：psql -c "SELECT pg_is_in_recovery();" 应返回 t

# 步骤 2：promote standby 为新 primary
psql -h standby -c "SELECT pg_promote();"
# 此时应用流量从 primary (16.1) 切到 standby (16.2)

# 步骤 3：升级旧 primary 后作为新 standby
sudo systemctl stop postgresql@16-main       # 停止旧 primary
# 替换二进制
pg_basebackup -h new-primary -D /var/lib/postgresql/16/main -R   # 重做基础备份
sudo systemctl start postgresql@16-main      # 启动后追上新 primary
```

切换瞬间通过 VIP 漂移或 pgbouncer/HAProxy 重连完成，对应用的影响通常 < 10 秒。

### 大版本（major）滚动升级：pg_upgrade（in-place）

`pg_upgrade` 自 PostgreSQL 9.0 (2010) 引入，使用硬链接（`--link`）方式可以让升级在分钟级完成，但**仍需停机**——升级期间数据库不可写：

```bash
# pg_upgrade 典型流程
pg_upgrade \
    --old-bindir=/usr/lib/postgresql/15/bin \
    --new-bindir=/usr/lib/postgresql/16/bin \
    --old-datadir=/var/lib/postgresql/15/main \
    --new-datadir=/var/lib/postgresql/16/main \
    --link \
    --check    # 先 dry run

# 实际执行（去掉 --check）
pg_upgrade ... --link
# 升级时间：取决于元数据规模，几分钟到一小时

# 升级后必须重新统计
analyze_new_cluster.sh

# 注意：硬链接模式下，旧集群的数据文件已被复用，无法回退
# 如需回退，必须从升级前的 pg_basebackup 或 pg_dump 恢复
```

`pg_upgrade --link` 不是真正的滚动升级——它需要停服。但它对元数据级别（系统目录）的升级速度极快，是**单实例**场景下最常用的大版本升级工具。

### 大版本滚动升级：逻辑复制（自 PG 10 / 2017）

从 PostgreSQL 10 (2017) 起，社区版内置逻辑复制让大版本零停机升级成为可能：

```bash
# 拓扑：旧主 PG 14 (publisher) → 新主 PG 17 (subscriber)
#       两个集群独立部署，通过逻辑复制同步

# 步骤 1：在新版本（PG 17）上搭建空集群
initdb -D /var/lib/postgresql/17/main
pg_ctl -D /var/lib/postgresql/17/main start

# 步骤 2：导出旧库 schema（不含数据）
pg_dump -h old-primary --schema-only mydb > schema.sql
psql -h new-primary -d mydb -f schema.sql

# 步骤 3：在旧主上创建 publication
psql -h old-primary -d mydb -c "
    CREATE PUBLICATION upgrade_pub FOR ALL TABLES;
"

# 步骤 4：在新主上创建 subscription（自动复制存量 + 增量）
psql -h new-primary -d mydb -c "
    CREATE SUBSCRIPTION upgrade_sub
    CONNECTION 'host=old-primary dbname=mydb user=replicator'
    PUBLICATION upgrade_pub;
"

# 步骤 5：等待 initial sync 完成
psql -h new-primary -c "
    SELECT subname, srsubstate FROM pg_subscription_rel;
    -- srsubstate = 'r' (ready) 表示完成
"

# 步骤 6：等待 lag 接近 0
psql -h old-primary -c "
    SELECT pid, application_name,
           pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn) AS sent_lag,
           pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS replay_lag
    FROM pg_stat_replication;
"

# 步骤 7：业务切流量到新主（应用层切换）
# 应用先停写，等 replay_lag = 0 后切连接到 new-primary

# 步骤 8：在新主上同步 sequences（逻辑复制不复制 sequence 状态）
psql -h old-primary -d mydb -c "
    SELECT 'SELECT setval(' || quote_literal(sequencename) ||
           ', ' || last_value || ');'
    FROM pg_sequences;
" -A -t > sync_seqs.sql
psql -h new-primary -d mydb -f sync_seqs.sql

# 步骤 9：drop subscription，下线旧主
psql -h new-primary -c "DROP SUBSCRIPTION upgrade_sub;"
```

PostgreSQL 18（2025）进一步增强：`failover slots`（PG 17）确保 logical replication slot 在 streaming standby 之间可故障转移，让逻辑复制本身也具备 HA 能力。

### 关键限制

- 逻辑复制不复制 DDL（PG 17 起部分支持，需 `CREATE PUBLICATION ... WITH (publish_via_partition_root = true)`）
- 逻辑复制不复制 sequences 状态（必须切换前手工同步）
- 逻辑复制对大表的 initial sync 可能耗时数小时
- 大对象（Large Object, OID-based）不被复制
- 非 logged 表不被复制

## MySQL：从 dump/restore 到 Group Replication

MySQL 的滚动升级路径经历了三代演进：

### 第一代：dump/restore（5.0 / 5.1 时代）

最古老的方法是停机后用 `mysqldump` 导出，新版本启动后导入。优点是版本无关，缺点是停机时间随数据量线性增长，TB 级别就不可接受。

### 第二代：mysql_upgrade + 主从（5.5 - 5.7）

```bash
# 主从拓扑：primary (5.7) ←─binlog─→ replica (5.7)

# 步骤 1：升级 replica 到 8.0
sudo systemctl stop mysql
sudo apt install mysql-server-8.0
sudo systemctl start mysql
mysql_upgrade -uroot -p     # 升级系统表（8.0.16+ 已合并到 mysqld 启动流程）

# 步骤 2：promote replica 为新主
mysql -h replica -e "STOP REPLICA; RESET REPLICA ALL;"
# 应用切到 replica（VIP 或 ProxySQL）

# 步骤 3：升级旧主，作为新 replica
sudo systemctl stop mysql
sudo apt install mysql-server-8.0
sudo systemctl start mysql
# 重做主从（从新主拉 binlog）
mysql -e "CHANGE REPLICATION SOURCE TO SOURCE_HOST='new-primary', ...; START REPLICA;"
```

`mysql_upgrade`（已并入 8.0.16+ 的 mysqld 启动流程）做的是系统表（mysql.user / mysql.proxies_priv 等）的元数据升级，并 OPTIMIZE 那些数据格式有变化的用户表。

### 第三代：Group Replication 滚动升级（8.0+）

MySQL 8.0 Group Replication 支持原生的滚动升级，节点逐个 OFFLINE → 升级 → ONLINE：

```sql
-- 集群拓扑：primary (8.0.34) + 2 个 secondary
-- 目标：升级到 8.0.36

-- 步骤 1：从 secondary 开始，逐个停止 GR
SELECT MEMBER_HOST FROM performance_schema.replication_group_members
ORDER BY MEMBER_ROLE;
-- 选择一台 secondary
STOP GROUP_REPLICATION;
-- 升级二进制（apt install mysql-server=8.0.36）
-- 重启 mysqld
START GROUP_REPLICATION;
-- 等待 ONLINE，验证 GTID 一致

-- 步骤 2：对 primary 执行 group_replication_set_as_primary 切到其他节点
SELECT group_replication_set_as_primary('uuid-of-other-node');
-- 然后用步骤 1 的方式升级旧 primary

-- 重要：MySQL 不支持 GR 跨大版本运行（8.0 ↔ 8.4 视为同主版本，但 5.7 → 8.0 不行）
```

GR 集群滚动升级有一个核心限制：所有成员必须在同一主版本系列内（5.7 不能与 8.0 同台运行 GR）。跨大版本必须 dump/restore 或外挂 binlog 复制。

### MySQL 大版本升级（5.7 → 8.0 的标准做法）

```bash
# 方案 A：dump/restore + binlog catch-up
mysqldump --single-transaction --master-data=2 -uroot -p mydb > dump.sql
# 在新版本上 import
mysql -h new-primary -uroot -p mydb < dump.sql
# 设置主从（从 dump 的 GTID 起追 binlog）
mysql -h new-primary -e "CHANGE REPLICATION SOURCE TO ..., SOURCE_AUTO_POSITION=1;"

# 方案 B：mysql_upgrade in-place（停机）
sudo systemctl stop mysql
sudo apt install mysql-server-8.0    # 替换二进制
sudo systemctl start mysql           # 启动时自动执行升级
# 5.7 → 8.0 不可逆，必须先备份
```

## Oracle：Transient Logical Standby（11g+）

Oracle 跨大版本升级的官方推荐路径是 **Transient Logical Standby (TLS)**，这是 Data Guard 自 11g (2007) 以来的核心升级技术。

核心思路：把一台 Physical Standby 临时转换为 Logical Standby，让它运行新版本，然后通过 SQL Apply 接收旧版本的 redo，最后切换。

```sql
-- 升级前拓扑：Primary (12c) ←─Data Guard─→ Standby (12c, Physical)

-- 步骤 1：在 standby 上创建保证还原点（用于失败回退）
ALTER SYSTEM SET dg_broker_start=FALSE;
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
CREATE RESTORE POINT pre_upgrade GUARANTEE FLASHBACK DATABASE;

-- 步骤 2：在 standby 上把 physical standby 转换为 logical standby
ALTER DATABASE RECOVER TO LOGICAL STANDBY keep_identity;
-- 此时 standby 进入 SQL Apply 模式

-- 步骤 3：在 standby 上原地升级到新版本（19c）
-- 替换 ORACLE_HOME，运行 dbua 或 catupgrd.sql
$ORACLE_HOME/bin/dbua -silent -sid STDBY -newOracleHome /u01/app/oracle/product/19.0.0/dbhome_1

-- 步骤 4：恢复 SQL Apply，让 logical standby 应用 redo
ALTER DATABASE START LOGICAL STANDBY APPLY IMMEDIATE;

-- 步骤 5：监控 redo 应用进度，等 lag 趋近 0
SELECT NAME, VALUE FROM V$DATAGUARD_STATS WHERE NAME='apply lag';

-- 步骤 6：切换角色（switchover），让升级后的 standby 成为 primary
ALTER DATABASE COMMIT TO SWITCHOVER TO PRIMARY;
-- 此时业务切到新版本

-- 步骤 7：旧 primary（12c）变 logical standby，按相同流程升级到 19c
-- 升级完成后 switchover 回正常的 primary/physical standby 拓扑

-- 步骤 8：drop guarantee restore point
DROP RESTORE POINT pre_upgrade;
```

这个流程的关键点：
- **业务停机时间 = 一次 switchover 的时间**（通常几秒）
- 跨大版本：12c → 19c、19c → 23ai 都支持
- 失败回退：guarantee restore point + flashback database 可以恢复到升级前
- 只需要一台额外副本，不需要双倍硬件

Oracle 也支持基于 **GoldenGate** 的零停机升级，适合 RAC 多实例并 GoldenGate 已部署的场景，但属于附加付费产品。

## SQL Server：AlwaysOn Availability Group 滚动升级

SQL Server 自 SQL Server 2012 (AlwaysOn AG) 开始原生支持滚动升级；2008 R2 及更早版本只能依赖 Database Mirroring 实现近似的滚动升级：

```sql
-- 拓扑：Primary (2019) + 2 个 Synchronous Secondary (2019)
-- 目标：升级到 2022

-- 步骤 1：从 Asynchronous Secondary 开始（如果有）
-- 如果都是 Synchronous，临时改一台为 Async 减少 primary 的延迟影响
ALTER AVAILABILITY GROUP MyAG
MODIFY REPLICA ON 'Secondary1' WITH (AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT);

-- 步骤 2：在 Secondary1 上：
-- 2.1 停止 SQL Server 服务
-- 2.2 升级到 2022（运行 setup.exe）
-- 2.3 启动服务，等待 Secondary 状态变为 SYNCHRONIZED 或 SYNCHRONIZING

-- 步骤 3：对 Secondary2 重复步骤 2

-- 步骤 4：手动 failover 到一台已升级的 secondary
ALTER AVAILABILITY GROUP MyAG FAILOVER;
-- 此时业务连接到新版本（2022）

-- 步骤 5：升级原 primary（现已变成 secondary）
-- 流程同步骤 2

-- 步骤 6：根据需要回切 primary 角色
-- 步骤 7：恢复同步模式
ALTER AVAILABILITY GROUP MyAG
MODIFY REPLICA ON 'Secondary1' WITH (AVAILABILITY_MODE = SYNCHRONOUS_COMMIT);
```

SQL Server 滚动升级的版本兼容窗口：
- **同主版本**之间的小版本（CU/SP）滚动升级官方支持
- **跨主版本**（2019 → 2022）也支持滚动升级，但要求 Compatibility Level 不能立刻提升（先维持原来的兼容级别，全部升级完后再 ALTER DATABASE SET COMPATIBILITY_LEVEL）
- AlwaysOn FCI（Failover Cluster Instance）在节点级也支持类似滚动升级，但只是节点级，不能跨主版本

### Reverse Log Shipping（迁移工具）

对于不能用 AlwaysOn 的老版本（2008 / 2012），微软推荐 **Backup/Restore + Log Shipping** 模式：把旧版本备份恢复到新版本上，定期发送日志，最后停业务做最后一次日志切换。这本质上是 side-by-side 而非 rolling，但停机时间可控。

## CockroachDB：preserve_downgrade_option 的设计哲学

CockroachDB 是云原生数据库的滚动升级范式之一。它通过共识协议（Raft）天然支持节点逐台替换，但**版本兼容性**通过一个集群设置精确控制：

```sql
-- 升级前：必须设置回退保护
SET CLUSTER SETTING cluster.preserve_downgrade_option = '23.1';
-- 这个设置告诉 CRDB：在 finalize 之前，所有新版本节点写入的数据格式
-- 必须保持向 23.1 兼容，即可以回退到 23.1

-- 升级流程：逐节点替换二进制
-- 每个节点：
--   cockroach node drain --self          -- 优雅排空
--   systemctl stop cockroach
--   apt install cockroach=23.2.x         -- 替换二进制
--   systemctl start cockroach

-- 升级期间所有节点都是 23.2 二进制，但功能仍按 23.1 模式运行
-- 此时如果发现问题，可以回退到 23.1 二进制（数据格式仍然兼容）

-- 验证集群状态
SELECT * FROM crdb_internal.kv_node_status;

-- 全部升级完毕、运行稳定后，finalize 升级
RESET CLUSTER SETTING cluster.preserve_downgrade_option;
-- 这一步会执行所有 23.2 引入的 schema 变更和数据格式升级
-- 一旦执行就无法回退到 23.1
```

`cluster.preserve_downgrade_option` 是一个非常优雅的设计：
- **在升级期间**：所有节点已是新二进制，但因为兼容旧数据格式，仍可回退
- **finalize 之后**：彻底切换到新版本的功能，旧二进制无法读取新数据格式
- **运维人员的决策点**：从二进制升级到 finalize 之间这段时间是观察期，可以验证应用兼容性后再决定是否 commit

CockroachDB 的滚动升级所有协调都由 cluster manager（早期叫 `roachprod`，K8s 部署用 Operator）自动完成，DBA 只需要按下"升级"按钮。

## TiDB：TiUP 的协调式滚动升级

TiDB 集群有三类组件：PD（控制平面）、TiKV（存储）、TiDB（SQL 计算节点）。TiUP 是官方运维工具，封装了滚动升级的所有细节：

```bash
# 升级前检查
tiup cluster check <cluster-name> --cluster

# 升级到指定版本
tiup cluster upgrade <cluster-name> v7.5.0

# TiUP 内部流程：
# 1. 升级 PD 节点（逐台 transfer leader → stop → upgrade → start）
# 2. 升级 TiKV 节点（逐台 evict region leader → stop → upgrade → start）
# 3. 升级 TiDB 节点（逐台从 LB 摘除 → stop → upgrade → start）
# 4. 升级 TiFlash / TiCDC 等周边组件
```

TiKV 升级时会先 evict region leader，避免节点重启导致 leader 选举抖动。TiDB 节点本身是无状态的 SQL 入口，升级简单。

跨大版本升级（v6.x → v7.x）TiDB 也支持滚动，但建议：
- 先在测试环境完整跑一次升级
- 必要时 TiCDC 同步到新集群作为备份
- 监控升级期间的 99.9 延迟，必要时暂停

## YugabyteDB：yb-master + yb-tserver 滚动升级

YugabyteDB（基于 PG 协议但底层是 RocksDB + Raft）也支持滚动升级，模式类似 CRDB：

```bash
# 步骤 1：滚动升级 yb-master（控制平面）
# 每个 master：
#   yb-admin -master_addresses ... change_master_role pre-elections
#   systemctl stop yb-master
#   /opt/yugabyte/install_software_new_version.sh
#   systemctl start yb-master

# 步骤 2：滚动升级 yb-tserver（存储 + 计算）
# 每个 tserver：
#   yb-admin -master_addresses ... drain_tserver <host:port>
#   systemctl stop yb-tserver
#   /opt/yugabyte/install_software_new_version.sh
#   systemctl start yb-tserver

# 步骤 3：升级元数据（DDL）
yb-admin upgrade_ysql

# 步骤 4：finalize（不可回退）
yb-admin finalize_upgrade
```

YugabyteDB 在 finalize 之前可以通过重新部署旧二进制回退，类似 CRDB 的 preserve_downgrade 设计。

## MongoDB：Replica Set 的天然滚动升级

MongoDB 自 2.x（2010）起就支持基于 Replica Set 的滚动升级，是 NoSQL 阵营最早把滚动升级标准化的引擎之一：

```javascript
// 拓扑：rs.status() 显示 1 primary + 2 secondary

// 步骤 1：从 secondary 开始（PSS 拓扑里有 2 个 secondary）
// 在被升级的 secondary 上：
db.adminCommand({ replSetStepDown: 60 });    // 如果是 primary 才需要
sudo systemctl stop mongod
sudo apt install mongodb-org=7.0.x
sudo systemctl start mongod
// 等待 secondary 状态变为 SECONDARY，且复制延迟 ≈ 0

// 步骤 2：对另一台 secondary 重复步骤 1

// 步骤 3：让 primary stepDown
rs.stepDown();
// 此时其中一台 secondary 升为 primary，业务连接到新版本

// 步骤 4：升级旧 primary（现已变 secondary），流程同步骤 1

// 步骤 5：FCV 升级（关键！）
db.adminCommand({ setFeatureCompatibilityVersion: "7.0" });
// 这一步启用新版本的所有 wire/storage 特性
// 在执行此命令之前，可以回退到旧版本二进制
```

MongoDB 的 **FCV (Feature Compatibility Version)** 类似 CRDB 的 preserve_downgrade_option：在 setFeatureCompatibilityVersion 之前，新二进制运行在向后兼容模式，可以随时回退到旧版本。

跨大版本升级（5.0 → 7.0）必须**逐个版本**完成（5.0 → 6.0 → 7.0），不能跳版本，因为每一代只兼容前一代的 FCV。

## 完整的跨版本升级工作流：PostgreSQL 14 → 17 案例

下面这个完整案例展示如何用 PostgreSQL 逻辑复制把生产库从 14 升级到 17，目标：业务停机 ≤ 30 秒。

### 准备阶段（升级前 1-2 周）

```bash
# 1. 评估表结构兼容性
# 检查是否有逻辑复制不支持的对象
psql -h old-primary -d mydb -c "
    SELECT n.nspname, c.relname
    FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE c.relkind = 'r'
      AND NOT EXISTS (
          SELECT 1 FROM pg_index i
          WHERE i.indrelid = c.oid
            AND (i.indisprimary OR i.indisunique)
      );
"
# 没有 PK/UNIQUE 的表必须 ALTER TABLE ... REPLICA IDENTITY FULL（性能差）
# 推荐：先给所有大表添加 PK

# 2. 评估扩展兼容性
psql -h old-primary -d mydb -c "SELECT * FROM pg_extension;"
# 检查每个扩展在 PG 17 是否有兼容版本

# 3. 调整 wal_level（如果当前不是 logical）
ALTER SYSTEM SET wal_level = 'logical';
# 重启生效（这一步是 wal_level 升级唯一的小停机）
```

### 部署新集群

```bash
# 4. 部署 PG 17 集群（独立机器或 VM）
initdb -D /var/lib/postgresql/17/main \
       --data-checksums \
       --encoding=UTF8 \
       --locale=en_US.UTF-8

# 5. 配置 postgresql.conf（建议跟旧库一致）
# wal_level = logical
# max_replication_slots = 50
# max_logical_replication_workers = 16
# max_wal_senders = 50
# max_worker_processes = 32

pg_ctl -D /var/lib/postgresql/17/main start
```

### 同步 schema

```bash
# 6. 在旧库上 dump schema（不含数据）
pg_dump -h old-primary -d mydb \
        --schema-only \
        --no-owner \
        --no-acl \
        > schema.sql

# 7. 在新库上重建 schema
psql -h new-primary -d postgres -c "CREATE DATABASE mydb;"
psql -h new-primary -d mydb -f schema.sql

# 8. 创建复制用户
psql -h old-primary -c "
    CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'xxx';
    GRANT USAGE ON SCHEMA public TO replicator;
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO replicator;
"
```

### 启动逻辑复制

```sql
-- 9. 旧库创建 publication
\c mydb
-- 旧库（PG 14）
CREATE PUBLICATION upgrade_pub FOR ALL TABLES;

-- 10. 新库创建 subscription（initial sync 自动启动）
-- 新库（PG 17）
CREATE SUBSCRIPTION upgrade_sub
CONNECTION 'host=old-primary port=5432 dbname=mydb user=replicator password=xxx'
PUBLICATION upgrade_pub
WITH (
    copy_data = true,
    create_slot = true,
    enabled = true,
    streaming = on,           -- PG 14+ 的流式 initial sync
    synchronous_commit = off  -- 提升初始拷贝吞吐
);
```

### 监控同步进度

```sql
-- 11. 在新库观察每张表的同步状态
SELECT srsubstate, COUNT(*)
FROM pg_subscription_rel
GROUP BY srsubstate;
-- 'i' = initial copy in progress
-- 'd' = data is being copied
-- 's' = synchronization is finished
-- 'r' = ready (apply phase)

-- 12. 在旧库观察 lag
SELECT slot_name,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) AS lag
FROM pg_replication_slots
WHERE slot_type = 'logical';
```

### 切换业务

```bash
# 13. 等到所有表 srsubstate = 'r'，且 lag < 1 MB
# 这通常是夜间业务低峰窗口

# 14. 应用层停写 30 秒（可通过 pgbouncer 暂停连接池实现）
pgbouncer -p 6432 -R   # 在 pgbouncer 上 PAUSE

# 15. 验证 lag = 0
psql -h new-primary -d mydb -c "SELECT pg_last_wal_replay_lsn();"
psql -h old-primary -d mydb -c "SELECT pg_current_wal_lsn();"
# 两者相等

# 16. 同步 sequences（逻辑复制不复制 sequence）
psql -h old-primary -d mydb -At -c "
    SELECT format('SELECT setval(%L, %s, true);',
                  schemaname || '.' || sequencename,
                  last_value)
    FROM pg_sequences;
" > sync_seqs.sql
psql -h new-primary -d mydb -f sync_seqs.sql

# 17. 切换 DNS / VIP / pgbouncer 上游到新库
# 应用恢复连接

# 18. drop subscription
psql -h new-primary -d mydb -c "DROP SUBSCRIPTION upgrade_sub;"
```

### 收尾

```bash
# 19. 旧库 drop replication slot（如果 subscription 没自动清理）
psql -h old-primary -c "
    SELECT pg_drop_replication_slot('upgrade_sub');
"

# 20. 验证业务功能 + 性能基线
# 24-72 小时观察期后再下线旧库

# 21. ANALYZE 收集统计信息
psql -h new-primary -d mydb -c "ANALYZE;"

# 22. VACUUM（可选，若使用 --copy-data 后碎片较多）
psql -h new-primary -d mydb -c "VACUUM ANALYZE;"
```

整个流程的关键指标：
- **业务实际停机时间**：步骤 14-17，通常 < 30 秒
- **总耗时**：取决于 initial sync 的数据量，TB 级数据可能需要数小时到数天
- **失败回退**：在步骤 17 之前可以随时回退到旧库（subscription 仍在运行）

## Oracle Transient Logical Standby 详细工作流

Oracle 的 transient logical standby 升级是大企业核心库 zero downtime upgrade 的标杆方案。下面给出详细工作流：

### 准备阶段

```sql
-- 1. 在 Primary 上启用 supplemental logging
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (PRIMARY KEY, UNIQUE INDEX) COLUMNS;

-- 2. 检查 unsupported 对象
SELECT * FROM DBA_LOGSTDBY_UNSUPPORTED;
SELECT * FROM DBA_LOGSTDBY_NOT_UNIQUE;
-- 没有 PK/UI 的表会被 SQL Apply 跳过

-- 3. 在 Standby 上创建 guarantee restore point（升级失败时 flashback 回去）
ALTER SYSTEM SET dg_broker_start=FALSE SCOPE=BOTH;
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE FLASHBACK ON;
CREATE RESTORE POINT pre_upgrade GUARANTEE FLASHBACK DATABASE;
ALTER DATABASE OPEN;
```

### 转换为 Logical Standby

```sql
-- 4. 在 Standby 上把 Physical 转 Logical（KEEP IDENTITY 保持 DBID）
ALTER DATABASE STOP LOGICAL STANDBY APPLY;   -- 如果之前是 logical
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE FINISH;
ALTER DATABASE ACTIVATE STANDBY DATABASE;

-- 在 Primary 上构建 LogMiner 字典
EXECUTE DBMS_LOGSTDBY.BUILD;

-- 在 Standby 上转换
ALTER DATABASE RECOVER TO LOGICAL STANDBY keep_identity;

-- 启动 SQL Apply
ALTER DATABASE START LOGICAL STANDBY APPLY IMMEDIATE;
```

### 升级 Logical Standby

```bash
# 5. 在 Standby 节点上停止 SQL Apply
sqlplus / as sysdba <<EOF
ALTER DATABASE STOP LOGICAL STANDBY APPLY;
SHUTDOWN IMMEDIATE;
EOF

# 6. 替换 ORACLE_HOME 到 19c
export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH

# 7. 运行 dbua（图形）或 catupgrd（CLI）
$ORACLE_HOME/bin/dbua -silent \
    -sid STDBY \
    -newOracleHome $ORACLE_HOME \
    -ignorePreReqs

# 或 CLI 方式
sqlplus / as sysdba <<EOF
STARTUP UPGRADE;
@?/rdbms/admin/catupgrd.sql
SHUTDOWN IMMEDIATE;
STARTUP;
EOF

# 8. 重启 SQL Apply（注意：现在 Primary 仍是 12c，redo 流向 19c standby）
sqlplus / as sysdba <<EOF
ALTER DATABASE START LOGICAL STANDBY APPLY IMMEDIATE;
EOF
```

### Switchover

```sql
-- 9. 监控 lag，等 SQL Apply 追平
SELECT name, value FROM v$dataguard_stats WHERE name = 'apply lag';

-- 10. 切换角色（业务停机几秒）
-- 在 12c primary 上：
ALTER DATABASE COMMIT TO SWITCHOVER TO LOGICAL STANDBY;
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;

-- 在 19c logical standby 上：
ALTER DATABASE COMMIT TO SWITCHOVER TO PRIMARY;

-- 此时 19c 是新 primary，业务应用切流量
```

### 升级旧 Primary

```bash
# 11. 旧 primary（现在是 logical standby，运行 12c）按相同流程升级到 19c
# 步骤同 5-8

# 12. 完成后 switchover 回正常拓扑（19c primary + 19c physical standby）
# 也可以保留 logical standby 拓扑用于报表查询

# 13. drop guarantee restore point
sqlplus / as sysdba <<EOF
DROP RESTORE POINT pre_upgrade;
EOF
```

整个过程的业务实际停机仅 switchover 那几秒，是真正意义的 near zero downtime upgrade。

## DBA Decision Matrix：何时用哪种升级方式

| 场景 | 推荐方式 | 理由 |
|------|---------|------|
| PostgreSQL 小版本 | pg_upgrade --link 或流复制 rolling | pg_upgrade 几分钟停机；流复制零停机 |
| PostgreSQL 大版本 + 小数据量 | pg_upgrade --link | 简单，停机几分钟可接受 |
| PostgreSQL 大版本 + 大数据量 | logical replication | TB 级数据 pg_upgrade 也要小时级 |
| MySQL 小版本 | 主从 / Group Replication rolling | 最佳实践 |
| MySQL 大版本 | dump/restore + binlog catch-up | 跨大版本不能 GR rolling |
| Oracle 大版本 | Transient Logical Standby | 业务停机仅 switchover 时间 |
| Oracle 小版本 | Data Guard rolling switchover | 同样几秒停机 |
| SQL Server 大版本 | AlwaysOn rolling | Compatibility Level 控制风险 |
| SQL Server 小版本 | AlwaysOn rolling | 标准 OPS |
| MongoDB | Replica Set rolling + FCV | NoSQL 范式 |
| CockroachDB | rolling + preserve_downgrade_option | 自动化运维 |
| TiDB | TiUP cluster upgrade | 协调式滚动 |
| 单实例 + 无副本 | 必须停机 dump/restore | 没有 HA 拓扑 |

## 关键发现

### 1. 滚动升级是 HA 拓扑的"副产品"

回顾本文涵盖的所有滚动升级方案，无一例外都依赖**多副本拓扑**——主从、AlwaysOn、Replica Set、Raft 集群。这意味着：滚动升级的能力本质上是 HA 架构的产物，单实例数据库（SQLite、Firebird、H2 等）天然没有 rolling 概念，必须停机升级。

参见 `database-failover-ha.md`、`synchronous-replication.md`：HA 拓扑是滚动升级的物理基础。

### 2. 跨版本复制兼容是滚动升级的真正难点

二进制替换永远是简单的——难的是**新旧版本如何在过渡期共存**：
- WAL/binlog 格式不兼容 → 物理复制断
- 系统目录不兼容 → SQL 函数行为分裂
- 默认值变化 → 应用语义漂移
- 锁兼容性矩阵变化 → 死锁规律变化

PostgreSQL 用逻辑复制（行级 SQL 抽象）解决；Oracle 用 SQL Apply（在 logical standby 里"重新执行"DDL/DML）解决；MySQL 用 binlog 的 ROW 格式解决。三种方案的共同点：**抛弃磁盘字节流，回到 SQL 语义层**。

### 3. "Finalize"机制：升级的承诺时刻

CRDB 的 `cluster.preserve_downgrade_option`、MongoDB 的 `setFeatureCompatibilityVersion`、YugabyteDB 的 `finalize_upgrade` 揭示了一个共同模式：**新版本的二进制部署 ≠ 启用新功能**。

升级被分成两步：
1. **二进制升级**（reversible）：所有节点跑新代码，但功能仍按旧版本工作。可以回退。
2. **finalize / FCV bump**（irreversible）：启用新功能，进入新数据格式。无法回退。

这给了运维人员一个观察期：在 finalize 之前可以随时验证应用兼容性，发现问题立即回退。这是分布式数据库相对传统数据库（pg_upgrade、mysql_upgrade）的重要进步——把"升级决策"和"二进制替换"解耦。

### 4. 物理复制 vs 逻辑复制：跨版本能力的分水岭

物理复制（流复制、Data Guard physical standby、AlwaysOn）的本质是**字节级镜像**，性能最好、延迟最低，但版本兼容窗口窄（通常仅小版本）。

逻辑复制（pg_logical、binlog ROW、Oracle SQL Apply）的本质是**SQL 语义重放**，开销更大、延迟更高，但**跨大版本天然兼容**。

滚动升级的工程权衡正是在这个分水岭上：
- 小版本：用物理复制 rolling 即可，零停机且性能影响最小
- 大版本：必须切到逻辑复制，付出同步开销换跨版本能力

### 5. pg_upgrade 是 in-place，不是 rolling

很多 DBA 把 pg_upgrade 误称为 rolling upgrade，但严格说它是 **in-place upgrade**：单实例升级，必须停机，本质上是把旧 catalog 转换为新 catalog 的工具。它的优势是数据文件 hardlink 模式下停机时间极短（几分钟），但**不是零停机**。

要做真正的 PG rolling upgrade（零停机），必须搭配流复制（小版本）或逻辑复制（大版本）的 failover。

### 6. 回退路径是滚动升级的最后保险

升级最可怕的不是失败，而是失败后无法回退。本文涉及的所有方案都明确给出了回退路径：

| 引擎 | 回退手段 |
|------|---------|
| PostgreSQL pg_upgrade | 仅能从备份恢复（数据文件已被改写）|
| PostgreSQL logical | drop subscription，业务切回旧库 |
| Oracle TLS | guarantee restore point + flashback database |
| SQL Server AlwaysOn | failover 回旧版本 secondary |
| CRDB | 升级 finalize 之前，旧二进制可用 |
| MongoDB | FCV bump 之前可回退 |

工业级升级流程必须有**明确的 rollback runbook**，DBA 在执行升级前必须演练过回退操作。

### 7. 应用兼容性是 DBA 之外的责任

数据库引擎升级到新版本，但**应用代码的 SQL 语义可能依赖旧行为**：
- MySQL 5.7 → 8.0 默认 `sql_mode` 变化（`ONLY_FULL_GROUP_BY` 默认开）
- PostgreSQL 12 起 `OID` 不再隐式可见
- Oracle 19c 起 `TIMESTAMP WITH TIME ZONE` 默认时区精度变化
- SQL Server Compatibility Level 升级会改变查询计划

工业级升级流程必须包含：
1. 测试环境完整跑过升级流程
2. 应用回归测试（最好包括典型的 OLTP 场景）
3. 灰度切流量 + 监控 P99 延迟、错误率
4. 必要时使用 Compatibility Level（SQL Server）/ search_path 兼容性 hack

### 8. 云托管数据库的升级是黑盒，但仍需 DBA 决策

Snowflake、BigQuery、Spanner、Aurora 等云托管数据库的升级由云厂商自动完成，DBA 看不到滚动过程。但 DBA 仍需：
- 关注 release notes 里的不兼容变更（默认值、SQL 行为）
- 在 staging 环境验证应用
- 利用云厂商的 maintenance window 控制升级时机
- 部分服务（Aurora、Spanner）支持 schedule 推迟升级到业务低峰

### 9. 滚动升级是组件级而非引擎级

一个完整的数据库升级可能涉及多个组件：
- TiDB 集群有 PD、TiKV、TiDB、TiFlash、TiCDC
- 数据库前面通常有 pgbouncer、ProxySQL、HAProxy 等连接代理
- 监控有 Prometheus / Grafana / Zabbix

工业级升级流程要规划**所有组件的升级顺序**，避免组件版本组合不兼容。TiUP、Patroni、CRDB Operator 等运维工具的核心价值就是把这些组件的滚动升级编排自动化。

### 10. SQL 标准在滚动升级上的"无所作为"

ISO SQL 标准从未涉及滚动升级——这是一个完全工程化的话题。每个引擎的具体协议（WAL 格式、binlog 兼容、Compatibility Level、FCV）都是厂商专有，没有任何跨引擎兼容的可能。这意味着：
- 跨引擎迁移（如 Oracle → PostgreSQL）必须走 ETL，而不是滚动
- 多云数据库联邦升级是个开放问题
- 标准化的"升级协议"或许是下一个十年的方向（参见 lakehouse 的 Iceberg / Delta 表格式标准化运动）

参见 `database-failover-ha.md`（HA 拓扑选型）、`synchronous-replication.md`（同步语义对升级期间数据一致性的影响）、`logical-replication-gtid.md`（逻辑复制的复制位点管理）。

## 参考资料

- PostgreSQL 文档：[Upgrading a PostgreSQL Cluster](https://www.postgresql.org/docs/current/upgrading.html)
- PostgreSQL 文档：[Logical Replication](https://www.postgresql.org/docs/current/logical-replication.html)
- PostgreSQL Wiki：[Major Version Upgrade Using Logical Replication](https://wiki.postgresql.org/wiki/Logical_replication_upgrade)
- MySQL 文档：[Upgrading MySQL](https://dev.mysql.com/doc/refman/8.0/en/upgrading.html)
- MySQL 文档：[Group Replication Online Upgrade](https://dev.mysql.com/doc/refman/8.0/en/group-replication-upgrading-online.html)
- Oracle 文档：[Database Rolling Upgrades Using Transient Logical Standby](https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/using-data-guard-rolling-upgrades.html)
- Oracle MOS Note 949322.1：Rolling Database Upgrades Using Transient Logical Standby
- Microsoft 文档：[Upgrading Always On Availability Group Replica Instances](https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/upgrading-always-on-availability-group-replica-instances)
- CockroachDB 文档：[Cluster Versions and Upgrades](https://www.cockroachlabs.com/docs/stable/upgrade-cockroach-version.html)
- TiDB 文档：[Upgrade TiDB Using TiUP](https://docs.pingcap.com/tidb/stable/upgrade-tidb-using-tiup)
- YugabyteDB 文档：[Upgrade YugabyteDB](https://docs.yugabyte.com/preview/manage/upgrade-deployment/)
- MongoDB 文档：[Replica Set Rolling Upgrade](https://www.mongodb.com/docs/manual/release-notes/7.0-upgrade-replica-set/)
- IBM DB2 文档：[Rolling Upgrades for HADR](https://www.ibm.com/docs/en/db2/11.5?topic=hadr-performing-rolling-update-upgrade-environments)
- SAP HANA 文档：[System Replication Rolling Upgrade](https://help.sap.com/docs/SAP_HANA_PLATFORM/4e9b18c116aa42fc84c7dbfd02111aba)
- Cassandra 文档：[Rolling restart and upgrade](https://cassandra.apache.org/doc/latest/cassandra/managing/operating/upgrading.html)
