# 只读表与只读模式 (Read-Only Tables and Modes)

把一张几百 GB 的归档分区表标记为只读，DBA 就再也不用为它做日常备份、不用担心误更新、不用为它分配回滚段——只读模式是 DBA 工具箱里最不起眼却最实用的一项能力，但 SQL 标准对它只字未提，各家数据库的实现千差万别。

## 只读的多个层级

数据库系统中"只读"概念出现在多个层级，每一级解决不同的问题：

1. **表级 (TABLE READ ONLY)**：单张表禁止 DML，常用于分区归档
2. **表空间级 (TABLESPACE READ ONLY)**：整个表空间所有数据文件物理只读
3. **数据库级 (DATABASE READ ONLY)**：整个数据库禁止写入
4. **实例级 (instance read-only)**：整个数据库实例禁止写入
5. **会话级 (SET TRANSACTION READ ONLY)**：当前事务只允许读
6. **物理副本只读 (replica read-only)**：备库结构性只读
7. **角色/账号只读 (revoke privileges)**：通过权限实现

## 典型使用场景

只读模式不是为了"防止误操作"这么简单的需求。真正驱动它出现的场景包括：

- **归档分区**：按时间分区的事实表，超过保留期的旧分区切换为只读，降低备份压力、避免误更新、让块校验和不再变化以便冷存储压缩
- **EOL（End of Life）数据**：财年关账后的明细数据、合规要求保留 7 年的交易日志
- **物理备库**：流复制 / 物理日志 apply 的备库结构性禁止写入
- **报表副本**：从主库克隆出的只读快照，专供 BI 报表
- **跨可用区迁移**：源库切只读、最后一批日志同步、目标库接管
- **维护期保护**：升级期间防止应用误连写库
- **零信任审计**：连接到生产库时强制 SET TRANSACTION READ ONLY 以避免误执行 UPDATE/DELETE

## SQL 标准的态度

ISO/IEC 9075（SQL:1999 ~ SQL:2023）中关于只读的内容：

- **SQL 标准只定义了 `SET TRANSACTION READ ONLY`**（Section 17.3 Transaction Characteristics）作为事务级别的只读模式
- **没有定义** `ALTER TABLE READ ONLY`、`ALTER TABLESPACE READ ONLY`、`ALTER DATABASE READ ONLY` 任何一种
- **没有定义** 表空间（TABLESPACE）这一概念本身——是各厂商的物理存储扩展
- **没有定义** 数据库级（DATABASE）只读

因此除了 `SET TRANSACTION READ ONLY` 这一句之外，所有的只读语法都是各家数据库的方言。

## 支持矩阵（综合）

### 表级与表空间级只读

| 引擎 | ALTER TABLE READ ONLY | ALTER TABLESPACE READ ONLY | 数据库级只读 | 备注 |
|------|----------------------|---------------------------|------------|------|
| Oracle | 是（11g 2007+） | 是（8.0 1997+） | 是（ALTER DATABASE OPEN READ ONLY） | 三级齐全 |
| SQL Server | -- (用 FILEGROUP) | 是（FILEGROUP READ_ONLY） | 是（ALTER DATABASE SET READ_ONLY） | 文件组级 |
| PostgreSQL | -- | 是（ALTER TABLESPACE 仅控制权限） | 是（default_transaction_read_only） | 仅事务级 + 物理只读 |
| MySQL | -- | -- | -- | 全局变量 read_only |
| MariaDB | -- | -- | -- | 继承 MySQL |
| SQLite | -- | -- | 是（PRAGMA query_only） | 单文件特性 |
| DB2 | -- | 是（ALTER TABLESPACE） | 是（QUIESCE） | -- |
| Snowflake | -- | -- | -- | 通过权限 + STREAM 实现 |
| BigQuery | -- | -- | -- | 通过 IAM 权限 |
| Redshift | -- | -- | -- | 通过权限 |
| Vertica | 是（ALTER TABLE READ ONLY） | -- | 是（READ ONLY 模式） | 真正的表级 |
| ClickHouse | -- | -- | 是（readonly 用户配置） | 用户级 |
| Greenplum | -- | -- | 是（gp_read_only 参数） | 继承 PG |
| Teradata | -- | -- | -- | 通过 LOCKED FOR ACCESS |
| SAP HANA | -- | -- | 是（ALTER SYSTEM ALTER DATABASE FOR READ ONLY） | 系统级 |
| Sybase ASE | -- | -- | 是（sp_dboption read only） | 数据库选项 |
| Informix | -- | 是（DATABASE LOG 模式） | -- | 间接支持 |
| Firebird | -- | -- | 是（ALTER DATABASE SET READ ONLY） | 数据库级 |
| H2 | -- | -- | 是（ACCESS_MODE_DATA=r） | URL 参数 |
| HSQLDB | -- | -- | 是（SET DATABASE READ ONLY） | 单表也可 |
| Derby | -- | -- | 是（readOnly URL 属性） | 启动参数 |
| TiDB | -- | -- | 是（tidb_super_read_only） | 5.0+ |
| OceanBase | -- | 是（tablespace 只读） | -- | 4.x |
| YugabyteDB | -- | -- | 是（继承 PG） | -- |
| CockroachDB | -- | -- | -- | AS OF SYSTEM TIME 实现读 |
| Spanner | -- | -- | -- | 仅会话级 |
| Yellowbrick | -- | -- | 是 | 数据库级 |
| SingleStore | -- | -- | -- | -- |
| StarRocks | -- | -- | -- | -- |
| Doris | -- | -- | -- | -- |
| MonetDB | -- | -- | 是（read-only mode） | 启动参数 |
| Crate DB | -- | -- | 是（cluster.blocks.read_only） | 集群级 |
| TimescaleDB | -- | 是（继承 PG） | 是（继承 PG） | -- |
| QuestDB | -- | -- | -- | -- |
| Exasol | -- | -- | -- | 通过权限 |
| Ignite | -- | -- | 是（Cluster activation） | 集群激活 |
| Athena | -- | -- | -- | 默认只查询 |
| DuckDB | -- | -- | 是（ATTACH ... READ_ONLY） | 文件级 |
| Materialize | -- | -- | -- | 流处理 |
| RisingWave | -- | -- | -- | 流处理 |
| InfluxDB | -- | -- | 是（authorization 控制） | 用户级 |
| Databend | -- | -- | -- | 通过权限 |
| Firebolt | -- | -- | -- | 通过权限 |
| Trino | -- | -- | -- | catalog.read-only |
| Presto | -- | -- | -- | catalog.read-only |
| Hive | -- | -- | -- | hive.metastore.read-only |
| Spark SQL | -- | -- | -- | catalog 配置 |
| Impala | -- | -- | -- | -- |
| Flink SQL | -- | -- | -- | -- |
| Synapse | -- | 是（FILEGROUP READ_ONLY） | 是 | 继承 SQL Server |

> 统计：**6 个引擎**支持表级或表空间级只读 DDL（Oracle/Vertica/SQL Server/DB2/Informix/OceanBase）；**约 22 个引擎**支持数据库级只读模式；**绝大多数引擎**只能通过事务级或权限级实现只读。

### SET TRANSACTION READ ONLY 支持矩阵

| 引擎 | SET TRANSACTION READ ONLY | START TRANSACTION READ ONLY | 默认读写设置 | 引入版本 |
|------|---------------------------|------------------------------|-------------|---------|
| Oracle | 是 | 是 | 是 | 6.x（早期） |
| SQL Server | -- (用 SET 隔离级别 SNAPSHOT) | -- | -- | 不支持标准语法 |
| PostgreSQL | 是 | 是 | `default_transaction_read_only` | 7.0（2000） |
| MySQL | 是 | 是 | `transaction_read_only` 变量 | 5.6.5（2012-04） |
| MariaDB | 是 | 是 | `transaction_read_only` 变量 | 10.0+ |
| SQLite | -- | -- | `PRAGMA query_only` | 不支持事务级 |
| DB2 | 是 | -- | -- | 早期 |
| Snowflake | -- | -- | -- | 不支持 |
| BigQuery | -- | -- | -- | 不支持 |
| Redshift | 是 | 是 | -- | 继承 PG |
| Vertica | 是 | -- | -- | -- |
| ClickHouse | -- | -- | -- | 不支持事务 |
| Greenplum | 是 | 是 | 继承 PG | -- |
| Teradata | -- (用 ACCESS LOCK) | -- | -- | -- |
| SAP HANA | 是 | -- | -- | -- |
| TiDB | 是 | -- | -- | 4.0+ |
| OceanBase | 是 | -- | -- | -- |
| YugabyteDB | 是 | 是 | 继承 PG | -- |
| CockroachDB | 是 | 是 | -- | 1.0+ |
| Spanner | 是 (BeginTransaction read-only) | -- | -- | -- |
| H2 | 是 | -- | -- | -- |
| HSQLDB | 是 | -- | -- | -- |
| Derby | 是 | -- | -- | -- |
| Firebird | 是 | -- | -- | -- |
| DuckDB | -- | -- | -- | 仅 ATTACH 时指定 |
| Trino | -- | -- | -- | 隐式 |

### 物理副本只读（结构性只读）

| 引擎 | 物理副本只读 | 实现机制 | 引入版本 |
|------|-------------|---------|---------|
| Oracle | Active Data Guard | 备库 read-only with apply | 11g（2007） |
| SQL Server | Always On 可读副本 | secondary readable | 2012 |
| PostgreSQL | Hot Standby | recovery 状态自动只读 | 9.0（2010） |
| MySQL | replica（read_only） | super_read_only | 5.7.8（2015） |
| MariaDB | slave（read_only） | 继承 MySQL | -- |
| TiDB | TiKV follower read | 默认强一致从读 | 4.0+ |
| OceanBase | follower 只读 | Paxos 机制 | -- |
| CockroachDB | follower read | AS OF SYSTEM TIME | 19.2+ |
| YugabyteDB | follower / read replica | 默认强一致 | -- |
| Spanner | read-only replica | 协议级 | -- |
| Greenplum | mirror（standby） | 备库不可读（与 PG 不同） | -- |
| ClickHouse | replica | ZooKeeper 协调，所有副本可写可读 | -- |
| Snowflake | reader account / replica | 跨账号克隆 | -- |
| Redshift | concurrency scaling | 临时只读集群 | -- |

## 各引擎实现详解

### Oracle：三级齐全的只读体系

Oracle 在三个层级（表、表空间、数据库）都提供了只读 DDL，且历史悠久。

#### ALTER TABLE READ ONLY（11g 2007+）

```sql
-- 11g 引入的表级只读（Oracle Database 11g Release 1, 2007 年发布）
ALTER TABLE orders_2010 READ ONLY;

-- 解除只读
ALTER TABLE orders_2010 READ WRITE;

-- 查询当前只读状态（USER_TABLES 数据字典 READ_ONLY 列）
SELECT table_name, read_only
FROM user_tables
WHERE table_name = 'ORDERS_2010';
```

只读表的语义：
- DML（INSERT/UPDATE/DELETE/MERGE）报错 ORA-12081
- 大部分 DDL 也被禁止（ALTER TABLE 修改列、ADD/DROP 索引等）
- **仍允许的操作**：DROP TABLE、TRUNCATE TABLE、ALTER TABLE...READ WRITE、收集统计信息（DBMS_STATS）、BUILD/REBUILD 索引（部分情况）
- 触发器在只读表上不会触发（因为没有 DML）
- 物化视图基表只读不影响刷新（特殊路径）

历史背景：Oracle 11g 之前要把表设为只读，DBA 必须把表移到只读表空间——这意味着归档分区时还要规划表空间布局。11g 后单表 DDL 即可完成，大幅简化了归档操作。

#### ALTER TABLESPACE READ ONLY（8.0 1997+）

```sql
-- Oracle 8.0（1997 年）就已支持表空间级只读
ALTER TABLESPACE archive_2010 READ ONLY;

-- 切换回读写
ALTER TABLESPACE archive_2010 READ WRITE;

-- 查询表空间状态
SELECT tablespace_name, status
FROM dba_tablespaces;
-- STATUS 可能值: ONLINE / OFFLINE / READ ONLY
```

表空间只读的物理含义（这是 Oracle 区别于其他数据库的关键）：
1. **数据文件被检查点（checkpoint）**：所有脏块刷盘
2. **数据文件头被冻结**：SCN 不再更新
3. **可以放到只读介质上**：CD-ROM、WORM、对象存储
4. **跨平台移动**：可在不同 endian 的平台间传输
5. **不再写日志**：但读操作仍然走正常缓冲区
6. **可传输表空间（Transportable Tablespace）**：备份只需备份一次

```sql
-- 经典使用：归档历史分区到只读表空间
-- 步骤 1：创建归档表空间
CREATE TABLESPACE archive_2010
DATAFILE '/oradata/archive_2010.dbf' SIZE 100G;

-- 步骤 2：移动分区到归档表空间
ALTER TABLE sales MOVE PARTITION sales_2010
TABLESPACE archive_2010 ONLINE;

-- 步骤 3：标记为只读
ALTER TABLESPACE archive_2010 READ ONLY;

-- 步骤 4（可选）：物理迁移到慢速存储
-- ALTER TABLESPACE archive_2010 OFFLINE;
-- mv /oradata/archive_2010.dbf /slowstorage/
-- ALTER TABLESPACE archive_2010 RENAME DATAFILE ...
-- ALTER TABLESPACE archive_2010 ONLINE;
```

#### ALTER DATABASE OPEN READ ONLY

```sql
-- 数据库级只读（启动时指定）
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE OPEN READ ONLY;

-- 查询当前数据库打开模式
SELECT name, open_mode FROM v$database;
-- OPEN_MODE: READ WRITE / READ ONLY / READ ONLY WITH APPLY (Active DG)
```

数据库只读的典型场景：
- **物理备库**：standby 数据库默认只读（apply 日志的同时允许查询）
- **冷备恢复**：开放给只读应用做最后查询
- **介质恢复测试**：演练 RMAN 恢复时验证可用性

#### Active Data Guard（11g+）

Active Data Guard 是 Oracle 物理备库 + 实时查询的组合：备库一边 apply redo log，一边接受只读查询。从 19c 开始还支持 DML Redirection——把备库上的写自动转发给主库。

```sql
-- 在备库上启用 Active DG
ALTER DATABASE OPEN READ ONLY;
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE
  USING CURRENT LOGFILE DISCONNECT;

-- 查询时自动看到接近实时的数据（取决于网络延迟）
```

#### SET TRANSACTION READ ONLY

```sql
-- Oracle 6.x 即支持事务只读（标准 SQL 语法）
SET TRANSACTION READ ONLY;
-- 此事务内所有 SELECT 都看到 SET TRANSACTION 时刻的快照
-- 等价于 READ ONLY 隔离级别 + SERIALIZABLE 一致性

-- 配合命名事务
SET TRANSACTION READ ONLY NAME 'monthly_report';

-- 切回读写需要重新 SET（一次事务内不能切换）
COMMIT;  -- 结束事务
SET TRANSACTION READ WRITE;
```

Oracle 的 READ ONLY 事务有一个关键特性：它使用 SCN 快照保证查询期间数据一致，但只能 SELECT，不能 DML——这正是标准 SQL 定义的语义。

### SQL Server：FILEGROUP 与 DATABASE 双层

SQL Server 没有独立的 ALTER TABLE READ ONLY，只读控制在文件组（FILEGROUP）和数据库两个层级。

#### ALTER DATABASE SET READ_ONLY

```sql
-- 整个数据库设为只读（用户必须断开）
ALTER DATABASE archive_db SET READ_ONLY WITH ROLLBACK IMMEDIATE;

-- 切回读写
ALTER DATABASE archive_db SET READ_WRITE WITH ROLLBACK IMMEDIATE;

-- 查询数据库状态
SELECT name, is_read_only, state_desc
FROM sys.databases
WHERE name = 'archive_db';
```

#### FILEGROUP READ_ONLY

```sql
-- 文件组级只读（接近 Oracle 表空间只读的语义）
ALTER DATABASE my_db
MODIFY FILEGROUP fg_archive_2010 READ_ONLY;

-- 切回读写
ALTER DATABASE my_db
MODIFY FILEGROUP fg_archive_2010 READ_WRITE;

-- 查询文件组状态
SELECT name, is_read_only, type_desc
FROM sys.filegroups;
```

典型用法：
```sql
-- 步骤 1：创建归档文件组
ALTER DATABASE my_db
ADD FILEGROUP fg_archive_2010;

ALTER DATABASE my_db
ADD FILE (
    NAME = 'archive_2010',
    FILENAME = 'D:\Data\archive_2010.ndf',
    SIZE = 50GB
) TO FILEGROUP fg_archive_2010;

-- 步骤 2：把分区移到归档文件组
-- (需要分区方案重建)

-- 步骤 3：设为只读
ALTER DATABASE my_db
MODIFY FILEGROUP fg_archive_2010 READ_ONLY;
```

#### Always On 可读副本（2012+）

```sql
-- 在主副本上配置可读副本
ALTER AVAILABILITY GROUP ag_prod
MODIFY REPLICA ON 'secondary_node'
WITH (
    SECONDARY_ROLE (ALLOW_CONNECTIONS = READ_ONLY)
);

-- 客户端连接字符串使用 ApplicationIntent=ReadOnly 路由到只读副本
-- Server=lb;Database=db;ApplicationIntent=ReadOnly;
```

### PostgreSQL：没有 ALTER TABLE READ ONLY

PostgreSQL 哲学：通过权限和事务控制，而非表级 DDL。这是 PG 与 Oracle/SQL Server 的核心理念差异。

#### 没有原生 ALTER TABLE READ ONLY

```sql
-- 以下语句在 PG 中不存在：
-- ALTER TABLE orders_2010 READ ONLY;  -- ERROR: syntax error

-- 替代方案 1：撤销 DML 权限
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON orders_2010 FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON orders_2010 FROM app_user;

-- 替代方案 2：触发器拦截
CREATE OR REPLACE FUNCTION raise_readonly() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'Table % is read only', TG_TABLE_NAME;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER orders_2010_readonly
BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON orders_2010
FOR EACH STATEMENT EXECUTE FUNCTION raise_readonly();

-- 替代方案 3：扩展（pg_readonly）
CREATE EXTENSION pg_readonly;
SELECT set_table_read_only('orders_2010'::regclass);
```

PG 不实现 ALTER TABLE READ ONLY 的设计理由（社区讨论摘要）：
- 权限系统已经能表达"禁止写"的意图
- 触发器机制提供了灵活的拦截点
- 表级只读涉及多个组件（HOT updates、autovacuum、重写规则）的复杂耦合
- 历史邮件列表多次提议都未通过

#### SET TRANSACTION READ ONLY（7.0+，2000）

```sql
-- 标准 SQL 语法（PG 7.0 引入，2000 年）
BEGIN;
SET TRANSACTION READ ONLY;
SELECT * FROM orders;
-- 任何写操作（除临时表）会报错
-- ERROR: cannot execute INSERT in a read-only transaction
COMMIT;

-- START TRANSACTION 形式
START TRANSACTION READ ONLY;
SELECT * FROM orders;
COMMIT;

-- 会话级默认
SET default_transaction_read_only = on;

-- 数据库级默认
ALTER DATABASE my_db SET default_transaction_read_only = on;

-- 用户级默认（连进来就只读）
ALTER USER readonly_user SET default_transaction_read_only = on;
```

#### Hot Standby（9.0+，2010）

PostgreSQL 9.0（2010 年 9 月发布）引入 Hot Standby——物理备库可以接受查询。

```sql
-- 备库 postgresql.conf
hot_standby = on              -- 9.0+ 默认 on
max_standby_streaming_delay = 30s  -- 查询冲突容忍时间

-- 备库连接进来后会发现：
INSERT INTO orders VALUES (...);
-- ERROR: cannot execute INSERT in a read-only transaction

-- 查询备库状态
SELECT pg_is_in_recovery();   -- t = 备库
SELECT pg_last_wal_replay_lsn();  -- 当前 apply 到的 WAL 位置
```

Hot Standby 的关键限制：
- 备库不能执行任何写操作（包括临时表的某些操作）
- 备库上长查询可能阻塞主库 WAL apply（max_standby_streaming_delay）
- 备库 VACUUM 由主库决定（hot_standby_feedback 可调整）

#### default_transaction_read_only

PostgreSQL 没有 `ALTER DATABASE ... READ ONLY` 这种 DDL，但通过参数实现等价效果：

```sql
-- 数据库级默认事务只读
ALTER DATABASE archive_db SET default_transaction_read_only = on;
-- 此后连入 archive_db 的所有事务默认只读

-- 但用户仍可显式 SET TRANSACTION READ WRITE 覆盖（除非 superuser=off）
```

### MySQL：read_only 与 super_read_only

MySQL 没有表级、表空间级、数据库级只读 DDL，全部通过实例级变量控制。

#### read_only（3.23+）

```sql
-- read_only 自 MySQL 3.23 起即存在
SET GLOBAL read_only = 1;

-- 含义：非 SUPER 权限用户不能写
-- SUPER 用户（root）仍可写——这是关键！

-- 查询当前状态
SHOW VARIABLES LIKE 'read_only';
SELECT @@global.read_only;

-- 验证：普通用户写会报错
-- ERROR 1290 (HY000): The MySQL server is running with the --read-only option
```

#### super_read_only（5.7.8+，2015 年 9 月）

`super_read_only` 解决了 `read_only` 不限制 SUPER 用户的问题。MySQL 5.7.8（2015 年 9 月发布）引入此变量。

```sql
-- 启用 super_read_only 后，连 SUPER 用户也不能写
SET GLOBAL super_read_only = 1;
-- 自动隐式启用 read_only
SHOW VARIABLES LIKE '%read_only%';
-- read_only        = ON
-- super_read_only  = ON
```

#### read_only vs super_read_only 对比

| 维度 | read_only | super_read_only |
|------|-----------|-----------------|
| 引入版本 | 3.23（早期） | 5.7.8（2015 年 9 月） |
| 限制对象 | 非 SUPER 用户 | 所有用户（含 SUPER） |
| 关闭操作 | SUPER 可关 | SUPER 可关（参数本身受控） |
| 复制写入 | 不影响（slave 复制线程例外） | 不影响 |
| 临时表 | 仍可创建 | 仍可创建 |
| ANALYZE/OPTIMIZE | SUPER 可执行 | 仍可执行（不算 DML） |
| DDL | 受限 | 受限 |
| 典型用途 | 备库防写 | 备库防 root 误操作 |

```sql
-- 启用顺序很重要
-- 错误：先设 super 后设 read_only 会失败
-- 正确：直接设 super_read_only=1（自动启用 read_only）
SET GLOBAL super_read_only = 1;

-- 关闭顺序（与启用相反）
SET GLOBAL super_read_only = 0;
SET GLOBAL read_only = 0;
```

#### SET TRANSACTION READ ONLY（5.6+）

```sql
-- MySQL 5.6.5（2012-04）引入标准事务只读
SET TRANSACTION READ ONLY;
START TRANSACTION READ ONLY;

-- 会话级
SET SESSION transaction_read_only = ON;

-- 全局级
SET GLOBAL transaction_read_only = ON;
```

只读事务在 MySQL 中有一个性能优化：避免分配事务 ID（trx_id），减少 InnoDB undo log 开销。这使 MySQL 5.6+ 把"明确只读的事务"优化为更轻量的快照查询。

#### 表空间只读？

InnoDB 的 file-per-table 表空间不支持 READ ONLY 状态（与 Oracle 不同）。最接近的能力：**Transportable Tablespace**（5.7+）允许导出/导入 .ibd 文件，但需要 FLUSH TABLES FOR EXPORT 锁住整个表。

### MariaDB：继承 MySQL

MariaDB 几乎完全继承 MySQL 的只读模型：
- `read_only` / `super_read_only` 同名变量
- `SET TRANSACTION READ ONLY`
- 复制场景下的备库只读用法相同

差异点：
- MariaDB 10.x 增加了 `read_only_compression` 等附加参数
- MariaDB 的 ColumnStore 引擎有自己的批量加载只读语义

### SQLite：单文件特性

SQLite 是嵌入式数据库，只读概念更直接：

```sql
-- 整个连接只读（PRAGMA）
PRAGMA query_only = ON;
-- 该连接此后所有写操作返回 SQLITE_READONLY 错误

-- 打开数据库时指定只读模式
-- C API: sqlite3_open_v2(file, db, SQLITE_OPEN_READONLY, NULL);

-- URI 参数
-- sqlite3_open_v2("file:test.db?mode=ro", &db, SQLITE_OPEN_URI, NULL);

-- 命令行
sqlite3 -readonly test.db
```

SQLite 的只读模式是单文件级别的——文件系统权限就是最直接的只读控制。

### Vertica：真正的 ALTER TABLE READ ONLY

Vertica 是少数支持表级 READ ONLY DDL 的分析型数据库：

```sql
-- 把表设为只读
ALTER TABLE orders_2020 SET READ ONLY;

-- 切回读写
ALTER TABLE orders_2020 SET READ WRITE;

-- 整个数据库只读模式
SELECT MAKE_AHM_NOW();  -- 推进 AHM
ALTER DATABASE my_db SET READ_ONLY;
```

Vertica 的 READ ONLY 表对存储优化器有特殊意义：只读后可以执行更激进的 ROS（Read Optimized Store）合并和压缩。

### DB2：表空间为主

```sql
-- DB2 表空间设为只读
ALTER TABLESPACE archive_ts STATE READ_ONLY;

-- 切换回正常状态
ALTER TABLESPACE archive_ts STATE NORMAL;

-- 数据库 QUIESCE（更强的全局只读）
QUIESCE DATABASE IMMEDIATE FORCE CONNECTIONS;
UNQUIESCE DATABASE;

-- 表级只读？通过权限实现
REVOKE INSERT, UPDATE, DELETE, ALTER ON orders_2010 FROM PUBLIC;
```

### TiDB：兼容 MySQL + 自有变量

```sql
-- TiDB 兼容 MySQL 的 read_only 系列
SET GLOBAL tidb_super_read_only = 1;
-- 5.0+ 引入

-- 区别：TiDB 没有 super_read_only 变量名
-- 而是 tidb_super_read_only（TiDB 命名空间）

-- 查询当前状态
SHOW VARIABLES LIKE '%read_only%';
```

TiDB 的 follower read 通过 `tidb_replica_read = 'follower'` 控制——这是路由级别的"读副本"而非"只读模式"。

### CockroachDB：AS OF SYSTEM TIME

CockroachDB 没有 ALTER TABLE READ ONLY，但通过 MVCC 时间戳实现"读历史只读快照"：

```sql
-- 以 5 分钟前的快照查询（保证只读语义）
SELECT * FROM orders AS OF SYSTEM TIME '-5m';

-- 整个事务只读
BEGIN AS OF SYSTEM TIME '-5m';
SELECT * FROM orders;
COMMIT;

-- 或者 SET TRANSACTION
SET TRANSACTION AS OF SYSTEM TIME '-30s';

-- 标准 SQL 语法也支持
SET TRANSACTION READ ONLY;
```

这种做法让"只读"和"时间旅行查询"自然结合——只读查询不阻塞写入，因为它读的是历史快照。

### Snowflake：克隆 + 权限

Snowflake 的存储模型基于不可变文件，"只读"概念更多通过权限和克隆实现：

```sql
-- 从生产表克隆出只读副本（零拷贝）
CREATE TABLE orders_clone CLONE orders;
-- clone 默认是读写的，需要通过权限设为只读

GRANT SELECT ON orders_clone TO ROLE analyst;
-- 不授予 INSERT/UPDATE/DELETE = 只读

-- Stage 可以指定为只读
CREATE STAGE archive_stage
URL = 's3://archive-bucket/'
DIRECTORY = (ENABLE = TRUE)
COMMENT = 'read-only archive stage';
-- 通过 IAM 策略保证 stage 物理只读

-- Time Travel 提供历史只读
SELECT * FROM orders AT(OFFSET => -86400);
SELECT * FROM orders BEFORE(STATEMENT => '...');

-- Snowflake 不支持 SET TRANSACTION READ ONLY（语法不报错但无效）
```

### BigQuery：IAM 控制

BigQuery 通过 IAM 角色实现只读：

```text
-- BigQuery 没有任何 ALTER TABLE READ ONLY 类语法
-- 通过角色控制：
-- roles/bigquery.dataViewer  - 只能读
-- roles/bigquery.dataEditor  - 可读写
-- roles/bigquery.dataOwner   - 完全控制

-- 在数据集级别授予
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member='user:analyst@example.com' \
  --role='roles/bigquery.dataViewer'

-- 表级条件 IAM（更细粒度）
-- BigQuery 支持 row-level / column-level 的访问策略
```

BigQuery 的"只读"完全在权限层面，没有任何引擎内的只读 DDL。

### ClickHouse：用户配置

```xml
<!-- users.xml -->
<users>
    <readonly_user>
        <readonly>1</readonly>
        <!-- 0 = 读写, 1 = 只读, 2 = 只读 + 可改设置 -->
    </readonly_user>
</users>
```

```sql
-- ClickHouse 客户端连接时指定 readonly 用户
-- 该用户的所有查询自动限制为 SELECT

-- 也可在会话临时切换
SET readonly = 1;
-- 此后只能 SELECT
INSERT INTO ...;
-- ERROR: Cannot execute query in readonly mode
```

ClickHouse 没有表级或数据库级只读 DDL，只通过用户/会话级 readonly 设置实现。

## Oracle 只读表空间深度剖析

Oracle 的表空间只读是所有数据库中最完整、历史最久的实现。理解它对设计自己的存储引擎非常有启发。

### 切换为只读的执行流程

执行 `ALTER TABLESPACE archive_2010 READ ONLY` 时，Oracle 后台依次进行：

1. **等待活跃事务完成**：会话进入"切换中"状态，新事务无法在该表空间中开启写
2. **触发检查点**：把所有脏块刷到该表空间的数据文件
3. **更新数据文件头**：把状态从 ONLINE 改为 READ ONLY，记录当前 SCN
4. **冻结 SCN 推进**：此后该表空间的数据文件头 SCN 不再更新
5. **更新控制文件**：记录表空间的新状态
6. **完成提交**：DBA_TABLESPACES.STATUS 显示 READ ONLY

```sql
-- 监控切换过程
ALTER TABLESPACE archive_2010 READ ONLY;

-- 在另一会话查询：
SELECT name, status, change# AS file_scn
FROM v$datafile
WHERE ts# = (
    SELECT ts# FROM v$tablespace
    WHERE name = 'ARCHIVE_2010'
);
```

### MOUNT 模式下的只读访问

Oracle 数据库可以以"MOUNT 但未 OPEN"或"OPEN READ ONLY"模式启动：

```sql
-- 启动到 MOUNT 模式（控制文件已加载，但数据文件未打开）
STARTUP MOUNT;
-- 此时无法查询用户表，但可以恢复、备份

-- 切换到只读 OPEN
ALTER DATABASE OPEN READ ONLY;
-- 此时可以查询，但无法 DML / DDL / 提交

-- 物理备库的典型操作
RECOVER MANAGED STANDBY DATABASE DISCONNECT;
-- 后台 apply redo
ALTER DATABASE OPEN READ ONLY;
-- 同时允许查询（Active Data Guard 模式）
```

### 数据文件检查点的关键作用

Oracle 把表空间设为只读时执行的检查点（datafile checkpoint）有几个微妙的作用：

1. **保证数据文件物理一致**：可以放到只读介质而不会损坏
2. **简化备份策略**：表空间只读后只需备份一次（除非物理 corruption）
3. **支持跨平台传输**：可在不同 endian 的系统间转移（用 RMAN CONVERT）
4. **避免 ORA-01122 错误**：数据文件头 SCN 与控制文件一致

```sql
-- 验证数据文件一致性
RMAN> VALIDATE TABLESPACE archive_2010;
-- 只读表空间不会出现"physical corruption due to write"

-- 跨平台传输
RMAN> CONVERT TABLESPACE archive_2010
      TO PLATFORM 'Linux x86 64-bit'
      FORMAT '/tmp/archive_2010.dbf';
```

### 只读表空间上的允许操作

只读表空间不是完全冻结：

| 操作 | 允许 | 备注 |
|------|------|------|
| SELECT | 是 | 正常走 buffer cache |
| INSERT/UPDATE/DELETE | 否 | ORA-00372 |
| 创建索引 | 否 | 索引段无法分配 |
| DROP TABLE | 否 | 段无法回收 |
| TRUNCATE | 否 | 段无法回收 |
| 收集统计 | 是 | 统计存在数据字典中 |
| 执行计划编译 | 是 | 不需要写表空间 |
| 备份（RMAN） | 是 | 只读 = 可备份 |
| 恢复 | 否 | 数据文件已冻结 |
| ALTER ... READ WRITE | 是 | 切回读写 |

### 表空间切换的常见问题

```sql
-- 问题 1：切换时报 ORA-01650
-- 原因：表空间内有未提交事务
SELECT * FROM v$lock WHERE id1 IN (
    SELECT object_id FROM dba_objects
    WHERE owner = 'APP' AND object_name LIKE 'ORDERS_2010%'
);

-- 问题 2：切换时报 ORA-03287
-- 原因：表空间内有 ONLINE 索引重建
SELECT * FROM dba_objects WHERE status = 'INVALID';

-- 问题 3：切换后无法 DROP 表空间
-- 解决：先 READ WRITE，再 DROP
ALTER TABLESPACE archive_2010 READ WRITE;
DROP TABLESPACE archive_2010 INCLUDING CONTENTS AND DATAFILES;
```

## MySQL super_read_only 深度剖析

`super_read_only` 是 MySQL 5.7.8（2015 年 9 月发布）引入的特性，解决了一个长期存在的运维痛点。

### 历史背景

`read_only` 自 MySQL 3.23 起就存在，但有一个绕不过的弱点：它不限制 SUPER 权限的用户。在主从复制中，slave 设为 `read_only=1` 是标配，但只要 root 用户或任何拥有 SUPER 权限的账号连进来，就能在 slave 上执行 INSERT——这会破坏复制。

```sql
-- MySQL 5.7.8 之前
SET GLOBAL read_only = 1;
-- 普通用户：失败
-- root 用户：仍能成功！这是问题
```

实际事故案例：DBA 在主库做了维护切换到 slave，结果 slave 上残留 read_only=1，但因为 DBA 用 root 登录，"看起来"没问题，几小时后切回时数据冲突。

### super_read_only 的语义

```sql
-- 启用
SET GLOBAL super_read_only = ON;
-- 自动启用 read_only
SHOW VARIABLES LIKE '%read_only%';
-- +-----------------------+-------+
-- | Variable_name         | Value |
-- +-----------------------+-------+
-- | innodb_read_only      | OFF   |
-- | read_only             | ON    |
-- | super_read_only       | ON    |
-- | transaction_read_only | OFF   |
-- +-----------------------+-------+

-- 此时连 root 用户也无法写
INSERT INTO orders VALUES (...);
-- ERROR 1290 (HY000): The MySQL server is running with the --read-only option

-- 仍允许的操作：
-- 1. 复制线程的写入（slave SQL thread）
-- 2. 临时表的 CREATE/DROP/INSERT
-- 3. 内部 DD（data dictionary）的更新（系统自身）
```

### 启用顺序的陷阱

```sql
-- 错误顺序：先 read_only 再 super_read_only
SET GLOBAL read_only = ON;          -- OK
SET GLOBAL super_read_only = ON;    -- OK，但有窗口期

-- 正确：直接设 super_read_only=ON（自动启用 read_only）
SET GLOBAL super_read_only = ON;

-- 关闭：必须先 super_read_only=OFF 再 read_only=OFF
SET GLOBAL super_read_only = OFF;
SET GLOBAL read_only = OFF;

-- 试图在 super_read_only=ON 时直接关 read_only：
SET GLOBAL read_only = OFF;
-- ERROR: Cannot change @@global.read_only when @@global.super_read_only is ON
```

### 复制场景的标准用法

```sql
-- Slave 配置（my.cnf）
[mysqld]
read_only = ON
super_read_only = ON
-- 启动时即生效

-- 切换主备时的脚本步骤：
-- 1. 旧主库设为 super_read_only
SET GLOBAL super_read_only = ON;

-- 2. 等待复制延迟归零
SHOW SLAVE STATUS\G  -- 在新主库上观察 Seconds_Behind_Master

-- 3. 新主库关闭只读
SET GLOBAL super_read_only = OFF;
SET GLOBAL read_only = OFF;

-- 4. 应用切换连接
```

### read_only 不影响的操作

即使 `super_read_only = ON`，以下操作仍然允许：

| 操作 | 原因 |
|------|------|
| 复制线程 INSERT/UPDATE | replication 不受 read_only 限制 |
| CREATE TEMPORARY TABLE | 临时表不持久化 |
| ANALYZE TABLE | 仅更新统计信息（DD） |
| OPTIMIZE TABLE | 部分操作（视实现） |
| BINLOG 写入 | 系统行为 |
| InnoDB 后台线程 | 内部维护 |
| 用户认证 | 写 mysql 系统表（特殊路径） |

### Aurora MySQL 的扩展

AWS Aurora MySQL 在标准 super_read_only 之上还有：
- 只读副本（reader endpoint）天然只读
- `aurora_readonly_routing` 自动把写转发到 writer

## SQL Server 全局只读切换深度剖析

SQL Server 的 `ALTER DATABASE SET READ_ONLY` 比 MySQL 的 read_only 更"重"，更接近 Oracle 的表空间只读。

```sql
-- 标准切换语法
ALTER DATABASE archive_db SET READ_ONLY WITH ROLLBACK IMMEDIATE;

-- 选项详解：
-- WITH ROLLBACK IMMEDIATE  - 立即回滚活跃事务
-- WITH ROLLBACK AFTER N    - N 秒后回滚
-- WITH NO_WAIT             - 立即失败（如有活跃事务）

-- 内部行为：
-- 1. 触发数据库 checkpoint
-- 2. 等待所有事务结束
-- 3. 锁定数据库元数据
-- 4. 更新 sys.databases.is_read_only = 1
```

切换为只读后的影响：

- 数据库不会再写日志（除了系统操作如自动统计）
- 自动统计仍可读取（但更新会失败）
- 只读数据库不会持有 LOCK_HASH 表项（节省内存）
- 备份只需做一次（直到切回读写）
- AUTO_CLOSE = ON 时只读数据库可被卸载

## SET TRANSACTION READ ONLY 与隔离级别的交互

```sql
-- PostgreSQL：READ ONLY + SERIALIZABLE = 优化
BEGIN ISOLATION LEVEL SERIALIZABLE READ ONLY;
-- PG 会跳过 SSI（serializable snapshot isolation）的写跟踪开销
-- 因为只读事务不会成为冲突的"目标"，仅是"观察者"
SELECT * FROM accounts;
COMMIT;

-- Oracle：SERIALIZABLE READ ONLY 退化为 READ ONLY
-- 因为 Oracle 的 SERIALIZABLE 本身就基于 SCN 快照
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SET TRANSACTION READ ONLY;  -- 后者覆盖前者的部分语义

-- DB2：READ ONLY + UR（uncommitted read）
SET CURRENT ISOLATION = UR;
SET TRANSACTION READ ONLY;
-- 最低开销的只读查询模式

-- MySQL：READ ONLY 优化避免分配 trx_id
SET TRANSACTION READ ONLY;
SELECT * FROM orders;
-- InnoDB 内部跳过 trx 系统的部分开销
```

### 性能优化机制

只读事务在引擎层有显著的性能优化空间：

| 优化点 | Oracle | PostgreSQL | MySQL/InnoDB | SQL Server |
|--------|--------|-----------|--------------|------------|
| 跳过 undo 段分配 | 是 | 是 | 是（5.6+） | 是 |
| 跳过事务 ID 分配 | 部分 | 是 | 是（5.6+） | 是 |
| 跳过锁登记 | 部分 | 是 | 是 | 是 |
| 避免日志写入 | 是 | 是 | 是 | 是 |
| 串行化版本跳过 | -- | 是（SSI） | -- | 是（snapshot） |
| 并行扫描友好 | 是 | 是 | 部分 | 是 |

## 各引擎只读语法速查

### Oracle 系列

```sql
-- 表级
ALTER TABLE orders_2010 READ ONLY;
ALTER TABLE orders_2010 READ WRITE;

-- 表空间级
ALTER TABLESPACE archive_2010 READ ONLY;
ALTER TABLESPACE archive_2010 READ WRITE;

-- 数据库级
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE OPEN READ ONLY;

-- 事务级
SET TRANSACTION READ ONLY;
SET TRANSACTION READ ONLY NAME 'monthly_report';

-- 查询状态
SELECT table_name, read_only FROM user_tables;
SELECT tablespace_name, status FROM dba_tablespaces;
SELECT name, open_mode FROM v$database;
```

### SQL Server 系列

```sql
-- 数据库级
ALTER DATABASE archive_db SET READ_ONLY WITH ROLLBACK IMMEDIATE;
ALTER DATABASE archive_db SET READ_WRITE WITH ROLLBACK IMMEDIATE;

-- 文件组级
ALTER DATABASE my_db
MODIFY FILEGROUP fg_archive_2010 READ_ONLY;

-- 事务级（用 SNAPSHOT 隔离级别近似）
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRANSACTION;
SELECT * FROM orders;  -- 一致快照
COMMIT;

-- 查询状态
SELECT name, is_read_only, state_desc FROM sys.databases;
SELECT name, is_read_only, type_desc FROM sys.filegroups;
```

### PostgreSQL 系列

```sql
-- 没有 ALTER TABLE READ ONLY，用权限或扩展
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON orders_2010 FROM PUBLIC;
CREATE EXTENSION pg_readonly;
SELECT set_table_read_only('orders_2010'::regclass);

-- 数据库级
ALTER DATABASE archive_db SET default_transaction_read_only = on;

-- 事务级（标准）
BEGIN TRANSACTION READ ONLY;
SET TRANSACTION READ ONLY;

-- Hot Standby（自动只读）
-- recovery.conf / postgresql.conf 控制

-- 查询状态
SELECT pg_is_in_recovery();
SHOW default_transaction_read_only;
SHOW transaction_read_only;
```

### MySQL/MariaDB 系列

```sql
-- 实例级
SET GLOBAL read_only = 1;
SET GLOBAL super_read_only = 1;  -- MySQL 5.7.8+

-- 事务级
SET TRANSACTION READ ONLY;
START TRANSACTION READ ONLY;

-- 会话级
SET SESSION transaction_read_only = ON;

-- 查询状态
SHOW VARIABLES LIKE '%read_only%';
SELECT @@global.super_read_only;
```

### CockroachDB

```sql
-- 没有 ALTER TABLE READ ONLY，用 AS OF SYSTEM TIME
SELECT * FROM orders AS OF SYSTEM TIME '-5m';

-- 事务级
BEGIN AS OF SYSTEM TIME '-5m';
SELECT * FROM orders;
COMMIT;

-- 标准事务只读
SET TRANSACTION READ ONLY;
```

### Snowflake

```sql
-- 没有 ALTER TABLE READ ONLY，用权限和克隆
GRANT SELECT ON TABLE orders TO ROLE analyst;
REVOKE INSERT, UPDATE, DELETE ON TABLE orders FROM ROLE analyst;

-- Time Travel 实现历史只读
SELECT * FROM orders AT(OFFSET => -86400);
SELECT * FROM orders BEFORE(STATEMENT => '...');

-- 克隆得到独立只读副本
CREATE TABLE orders_archive CLONE orders;
```

## 关键发现

### 1. SQL 标准的最小集

ISO/IEC 9075 仅定义了 `SET TRANSACTION READ ONLY`。所有的 ALTER TABLE READ ONLY、ALTER TABLESPACE READ ONLY、ALTER DATABASE READ ONLY 都是各厂商的方言，互不兼容。

### 2. Oracle 的三层模型最完整

Oracle 是唯一同时支持表级（11g 2007+）、表空间级（8.0 1997+）、数据库级（早期）只读的主流数据库。这套模型也最适合归档场景：先把分区移到归档表空间，再把表空间设为只读。

### 3. 表级 READ ONLY DDL 极其稀少

只有 Oracle（11g+）和 Vertica 等少数引擎提供 `ALTER TABLE ... READ ONLY` DDL。绝大多数引擎需要通过权限、触发器或扩展实现。PostgreSQL 社区多次提议但都未通过，理由是权限系统已能表达此意图。

### 4. PostgreSQL 哲学：权限 + 事务 + Hot Standby

PostgreSQL 不在表/库级别提供只读 DDL，而是通过：
- `REVOKE`：表级只读
- `default_transaction_read_only`：数据库级
- `SET TRANSACTION READ ONLY`：事务级
- Hot Standby（9.0+ 2010）：物理副本级

这个设计与 Unix "组合简单工具" 的哲学一致。

### 5. MySQL 的 read_only / super_read_only 有运维陷阱

`read_only`（3.23+）不限制 SUPER 用户，导致 root 仍能写入。MySQL 5.7.8（2015 年 9 月）引入 `super_read_only` 才彻底封死。启用顺序、关闭顺序都需要严格遵循（先 super 后 read，关闭反向）。

### 6. 只读副本是分布式 SQL 的常态

| 实现 | 引入时间 | 特点 |
|------|---------|------|
| Oracle Active Data Guard | 11g（2007） | 物理备库 + apply 同时查询 |
| SQL Server Always On | 2012 | secondary readable |
| PostgreSQL Hot Standby | 9.0（2010） | recovery 状态自动只读 |
| MySQL super_read_only | 5.7.8（2015） | 实例级强制只读 |
| TiDB follower read | 4.0+ | 强一致从读 |
| CockroachDB follower read | 19.2+ | 时间戳读 |

### 7. SET TRANSACTION READ ONLY 是性能优化点

只读事务在引擎层有大量优化空间：跳过事务 ID 分配、跳过 undo 段、跳过锁登记、避免 binlog 写入。MySQL 5.6+ 显式利用 `READ ONLY` 标记减少 InnoDB 开销，PostgreSQL 在 SSI 中跳过写跟踪。

### 8. Oracle 表空间只读支持跨平台传输

Oracle 把数据文件物理冻结后可以搬到不同 endian 的平台、不同存储介质。这是其他数据库都难以模仿的能力——本质是因为 Oracle 把"逻辑表空间"和"物理数据文件"解耦得最彻底。

### 9. 云原生数据库倾向于 IAM 而非 DDL

BigQuery、Snowflake、Athena 等云数据仓库都没有引擎内的只读 DDL，全部通过 IAM 角色控制。这反映了云数据库"不可变存储 + 权限控制"的架构选择。

### 10. SQLite/H2/Derby 有"打开模式"概念

嵌入式数据库（SQLite、H2、Derby）通过打开数据库时的标志或 URL 参数控制只读，与文件系统语义直接对应——文件只读 = 数据库只读。

### 11. 触发器拦截是 PG 用户的事实标准

由于 PostgreSQL 没有 ALTER TABLE READ ONLY，社区形成了"触发器 + raise_exception"的事实标准模式。`pg_readonly` 扩展进一步把这个模式封装为系统能力。

### 12. 只读模式与备份策略强相关

Oracle/SQL Server/DB2 的表空间或文件组只读后，备份策略可以大幅简化：只备份一次即可。这是只读模式最实际的价值——不只是"防止误操作"，更是"减少备份窗口和存储开销"。

### 13. 会话级 default_transaction_read_only 是被低估的能力

PostgreSQL 的 `ALTER USER ... SET default_transaction_read_only = on` 让"专用只读账号"成为可能——分析师连进来就只读，无需应用层代码控制。这比"开发自觉只用 SELECT"或"应用层拦截"更彻底。

### 14. 只读不等于 OFFLINE

一个易混淆的点：READ ONLY 表/表空间/数据库仍然是"在线"的——SELECT 查询正常可用。OFFLINE 才是完全不可用。Oracle 的 ALTER TABLESPACE OFFLINE 与 ALTER TABLESPACE READ ONLY 是两个完全不同的状态。

### 15. 复制场景中只读的微妙之处

主备复制中，备库设为 read_only 但复制线程仍可写——这在所有数据库中都是特例处理。MySQL 的 `super_read_only` 也不阻止复制线程的 SQL_THREAD 写入。这是设计上的妥协：如果连复制都被禁，备库就无法跟上主库。

### 16. 只读与列存压缩的协同

只读表可以执行更激进的压缩（如 Vertica 的 ROS 优化、ClickHouse 的 PART 合并）。一旦数据冻结，引擎就可以选择慢但更紧凑的压缩算法（如 Zstd 高级别），因为不需要担心后续的 INSERT 性能。

### 17. ALTER TABLESPACE READ ONLY 的真正杀手锏：跨数据库迁移

Oracle 表空间只读 + 可传输表空间的组合让一个事实表的归档分区可以从生产库直接迁移到归档库——零拷贝，秒级切换。这是其他数据库（包括 PostgreSQL）至今没有的能力。

## 参考资料

- ISO/IEC 9075-2:2016, Section 17.3 (SQL Transaction Characteristics)
- Oracle: [ALTER TABLE](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/ALTER-TABLE.html) - READ ONLY 子句
- Oracle: [ALTER TABLESPACE](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/ALTER-TABLESPACE.html) - READ ONLY 子句
- Oracle 11g New Features Guide（2007）：read-only tables 引入说明
- Oracle: [Active Data Guard 11g+](https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/)
- SQL Server: [ALTER DATABASE SET READ_ONLY](https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-database-transact-sql-set-options)
- SQL Server: [ALTER DATABASE MODIFY FILEGROUP](https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-database-transact-sql-file-and-filegroup-options)
- PostgreSQL: [SET TRANSACTION](https://www.postgresql.org/docs/current/sql-set-transaction.html) - READ ONLY 子句
- PostgreSQL: [Hot Standby](https://www.postgresql.org/docs/current/hot-standby.html)（9.0+，2010）
- PostgreSQL: [default_transaction_read_only](https://www.postgresql.org/docs/current/runtime-config-client.html)
- PostgreSQL Hackers Mailing List：多次关于 ALTER TABLE READ ONLY 提案的讨论
- MySQL: [super_read_only 5.7.8 引入说明](https://dev.mysql.com/doc/relnotes/mysql/5.7/en/news-5-7-8.html)
- MySQL: [read_only / super_read_only 系统变量](https://dev.mysql.com/doc/refman/8.0/en/server-system-variables.html#sysvar_read_only)
- MySQL: [SET TRANSACTION READ ONLY](https://dev.mysql.com/doc/refman/8.0/en/set-transaction.html)
- MariaDB: [Read-Only Replicas](https://mariadb.com/kb/en/read_only/)
- DB2: [ALTER TABLESPACE](https://www.ibm.com/docs/en/db2)
- Vertica: [ALTER TABLE SET READ ONLY](https://www.vertica.com/docs/)
- CockroachDB: [AS OF SYSTEM TIME](https://www.cockroachlabs.com/docs/stable/as-of-system-time.html)
- Snowflake: [Time Travel](https://docs.snowflake.com/en/user-guide/data-time-travel)
- TiDB: [tidb_super_read_only](https://docs.pingcap.com/tidb/stable/system-variables)
- SQLite: [PRAGMA query_only](https://www.sqlite.org/pragma.html#pragma_query_only)
- ClickHouse: [readonly setting](https://clickhouse.com/docs/en/operations/settings/permissions-for-queries/)
