# 表空间与文件布局 (Tablespaces and Storage Layout)

数据库的表数据最终都要落到磁盘上的文件里，但"表"和"文件"之间的映射关系——是一表一文件，还是所有表共享一个大文件，能否跨多块盘条带化，能否独立备份——决定了一个数据库能管理多大数据、能否在线扩容、能否做物理迁移。表空间（Tablespace）正是这层逻辑到物理映射的抽象。

## 为什么要有表空间

最朴素的存储方案是单文件：所有表、索引、元数据都塞进一个文件，SQLite 至今如此。这种方案极简单，但有三个根本限制：

1. **单盘容量上限**：单文件不能跨设备，数据库容量被单块磁盘锁死
2. **无法管理 I/O 局部性**：热表和冷表混在一起，无法把热数据放 SSD、冷数据放 HDD
3. **无法做对象级运维**：不能单独备份/迁移/移动一个表的物理数据，只能整库做

表空间的发明（Oracle 1980 年代早期，DB2 同期）就是为了解决这些问题。它在 SQL 表（逻辑对象）和操作系统文件（物理对象）之间引入一层逻辑容器：

- 一个**表空间**包含若干**数据文件**（DATAFILE）
- 每个**表/索引**存储于某个表空间
- DBA 可以为不同表空间指定不同存储路径（不同磁盘）、不同块大小、不同备份策略
- 表空间可以**联机扩容**（添加数据文件）、**只读化**、**整体迁移**

随后产生的核心能力：跨盘条带化、表级 quota、表空间级备份/恢复、表空间加密（TDE）、Oracle 独有的 Transportable Tablespace（跨数据库物理迁移）。

## SQL 标准的态度

SQL:2003 部分（ISO/IEC 9075-9 SQL/MED 与 9075-11 Information Schema）涉及一些物理存储概念，但 **SQL 标准从未真正规范 `CREATE TABLESPACE` 语法**。表空间始终是各数据库厂商自行扩展的领域：

```sql
-- 各厂商风格示例
-- Oracle
CREATE TABLESPACE users DATAFILE '/u01/oradata/users01.dbf' SIZE 100M
    AUTOEXTEND ON NEXT 10M MAXSIZE 2G;

-- PostgreSQL
CREATE TABLESPACE fastspace LOCATION '/ssd1/postgres';

-- DB2
CREATE TABLESPACE ts1 MANAGED BY DATABASE
    USING (FILE '/db2/ts1_c1' 5000);

-- SQL Server (filegroup, 不叫 tablespace)
ALTER DATABASE mydb ADD FILEGROUP fg_archive;
ALTER DATABASE mydb ADD FILE
    (NAME = 'archive_data', FILENAME = 'D:\data\archive.ndf', SIZE = 100MB)
    TO FILEGROUP fg_archive;
```

正因为没有标准，各引擎在表空间这个领域的差异是 SQL 世界中最大的之一。

## 支持矩阵（45+ 引擎综合）

### 1. CREATE TABLESPACE 与基本能力

| 引擎 | CREATE TABLESPACE | 表/索引指定表空间 | 文件每表 | 用户/Schema 默认表空间 | 版本 |
|------|------------------|---------------|---------|------------------|------|
| Oracle | 是 | `TABLESPACE` 子句 | 是（segment per table） | 是 | 早期版本 |
| PostgreSQL | 是 | `TABLESPACE` 子句 | 是（每关系多文件） | 是 | 8.0 (2005) |
| SQL Server | 文件组 | `ON filegroup` | 是 | 否（数据库级） | 7.0 (1998) |
| MySQL InnoDB | 是 | 是 | `innodb_file_per_table`（默认 ON） | 否 | 5.6.6 (2012) / 5.7 通用表空间 |
| MariaDB | 部分 | 部分 | 是（继承 MySQL） | 否 | 10.0+ |
| DB2 LUW | 是 | 是 | 是（DMS） | 是 | 早期版本 |
| SQLite | -- | -- | -- (单文件) | -- | -- |
| Snowflake | -- | -- | -- (云存储不可见) | -- | -- |
| BigQuery | -- | -- | -- (Capacitor 文件托管) | -- | -- |
| Redshift | -- | -- | -- (托管) | -- | -- |
| DuckDB | -- | -- | -- (单文件 / ATTACH) | -- | -- |
| ClickHouse | 否（用 storage policy） | 是（policy） | 部分 | -- | 19.15+ |
| Trino | -- (依赖 connector) | -- | -- | -- | -- |
| Presto | -- (依赖 connector) | -- | -- | -- | -- |
| Spark SQL | -- (DATABASE LOCATION) | -- | -- | -- | -- |
| Hive | -- (DATABASE LOCATION) | -- | -- | -- | -- |
| Flink SQL | -- | -- | -- | -- | -- |
| Databricks | -- (Unity Catalog LOCATION) | -- | -- | -- | -- |
| Teradata | 否（cylinder 自动） | -- | -- | -- | -- |
| Greenplum | 是 | 是 | 是（每段） | 是 | 4.0+ |
| CockroachDB | -- (replication zone) | -- | -- | -- | -- |
| TiDB | -- (region) | -- | -- | -- | -- |
| OceanBase | 是 | 是 | -- | 是 | 2.x+ |
| YugabyteDB | 是 | 是（地理分区） | -- | -- | 2.5+ |
| SingleStore | -- | -- | -- | -- | -- |
| Vertica | 存储位置（storage location） | 是（存储策略） | -- | -- | 早期 |
| Impala | -- | -- | -- | -- | -- |
| StarRocks | -- (存储介质 medium) | 是 | -- | -- | 2.x+ |
| Doris | -- (存储介质 medium) | 是 | -- | -- | 1.2+ |
| MonetDB | -- (列存目录) | -- | -- | -- | -- |
| CrateDB | -- | -- | -- | -- | -- |
| TimescaleDB | 继承 PG | 是 | 是 | 是 | 继承 PG |
| QuestDB | -- (单目录) | -- | -- | -- | -- |
| Exasol | -- | -- | -- | -- | -- |
| SAP HANA | -- (内存) | -- | -- | -- | -- |
| Informix | DBSPACE | 是 | 是 | 是 | 早期 |
| Firebird | -- (单文件 / 多文件 secondary) | -- | -- | -- | -- |
| H2 | -- | -- | -- | -- | -- |
| HSQLDB | -- | -- | -- | -- | -- |
| Derby | -- | -- | -- | -- | -- |
| Amazon Athena | -- (S3 路径) | -- | -- | -- | -- |
| Azure Synapse | 文件组（专用池） | 是 | -- | -- | GA |
| Google Spanner | -- | -- | -- | -- | -- |
| Materialize | -- | -- | -- | -- | -- |
| RisingWave | -- | -- | -- | -- | -- |
| InfluxDB | -- | -- | -- | -- | -- |
| Databend | -- (对象存储) | -- | -- | -- | -- |
| Yellowbrick | -- (托管) | -- | -- | -- | -- |
| Firebolt | -- (托管) | -- | -- | -- | -- |

> 统计：约 12 个引擎拥有真正意义上的表空间/文件组语法，约 8 个引擎用类似机制（存储策略、存储位置、存储介质）实现等效能力，其余 25+ 引擎要么是单文件嵌入式，要么是云托管/对象存储模型，用户不直接管理物理布局。

### 2. 表空间扩容、自增与上限

| 引擎 | ADD DATAFILE | AUTOEXTEND | MAXSIZE / 上限 | BIGFILE / 单文件大表空间 |
|------|--------------|------------|----------------|---------------------|
| Oracle | `ALTER TABLESPACE ... ADD DATAFILE` | `AUTOEXTEND ON NEXT n MAXSIZE m` | 是 | BIGFILE TABLESPACE (10g+) |
| PostgreSQL | -- (单 LOCATION，文件由系统管理) | 自动 | 操作系统决定 | -- |
| SQL Server | `ALTER DATABASE ADD FILE` | `FILEGROWTH` | `MAXSIZE` | -- |
| MySQL InnoDB | `ALTER TABLESPACE ADD DATAFILE`（通用表空间） | `innodb_autoextend_increment` | `autoextend_size` | 是（系统表空间） |
| DB2 LUW | `ALTER TABLESPACE ADD` | `AUTORESIZE YES` | `MAXSIZE` | -- |
| Greenplum | `ALTER TABLESPACE` | -- (每段一个目录) | -- | -- |
| Vertica | `ALTER LOCATION` | 自动 | 是 | -- |
| Informix | `onspaces -a dbspace -p file -o offset -s size` | 是 | 是 | -- |
| ClickHouse | `<path>` 配置；多盘 | 自动 | `keep_free_space_bytes` | -- |

### 3. 表空间高级能力

| 引擎 | 只读表空间 | 表空间备份 | 表空间加密 (TDE) | Transportable | 临时表空间 | UNDO 表空间 |
|------|----------|-----------|---------------|--------------|-----------|------------|
| Oracle | `ALTER TABLESPACE ... READ ONLY` | RMAN tablespace | 是 (TDE) | **是（独有）** | TEMP TABLESPACE | UNDO TABLESPACE |
| PostgreSQL | -- (整库 read-only) | 文件级（非在线） | 通过文件系统 | -- | `temp_tablespaces` | -- (XID/MVCC) |
| SQL Server | `READ_ONLY` filegroup | filegroup backup | 是 (TDE) | -- | tempdb | -- (transaction log) |
| MySQL InnoDB | -- | -- (表空间级 export/import via FLUSH TABLES FOR EXPORT) | 是 (8.0 keyring) | 部分（通过 EXPORT/IMPORT） | 临时表空间 | 多 UNDO 表空间（8.0+） |
| DB2 LUW | -- | `BACKUP TABLESPACE` | 是 | 部分 | TEMPORARY TABLESPACE | -- |
| MariaDB | -- | 同 MySQL | 是 | 部分 | -- | -- |
| Greenplum | -- | -- | -- | -- | -- | -- |
| Vertica | -- | 是 | 是 | -- | -- | -- |
| ClickHouse | -- | 卷级 freeze | 卷级 | 卷间 MOVE | -- | -- |
| Informix | 是 | onbar | 是 | 部分 | TEMP DBSPACE | -- (logical log) |

### 4. 文件组 / 多文件细分

| 引擎 | 文件组 / 多文件机制 | 主文件 + 次文件 | 流文件 / BLOB 单独 |
|------|------------------|---------------|--------------------|
| SQL Server | FILEGROUP | PRIMARY (.mdf) + secondary (.ndf) + log (.ldf) | FILESTREAM (NTFS) |
| Oracle | TABLESPACE + DATAFILE | SYSTEM/SYSAUX + 用户表空间 + UNDO + TEMP | SecureFiles LOB（独立 segment） |
| MySQL InnoDB | 表空间 + .ibd | ibdata1 + .ibd 文件 | -- |
| DB2 | TABLESPACE + container | catalog + user + temp | LOB tablespace |
| PostgreSQL | tablespace + relation file | base + pg_global + pg_default | TOAST 表（自动） |
| Firebird | 多文件数据库 | primary + secondary files | BLOB segment |

## 各引擎深入解析

### Oracle：表空间的发源地

Oracle 是商用数据库中表空间机制最成熟的厂商之一。所有数据对象都必须存储在某个表空间，DBA 通常会按用途规划表空间布局：

```sql
-- 创建一个 SMALLFILE 表空间（默认），由多个数据文件组成
CREATE TABLESPACE users
    DATAFILE '/u01/oradata/orcl/users01.dbf' SIZE 100M
             AUTOEXTEND ON NEXT 10M MAXSIZE 2G,
             '/u02/oradata/orcl/users02.dbf' SIZE 100M
             AUTOEXTEND ON NEXT 10M MAXSIZE 2G
    LOGGING
    ONLINE
    EXTENT MANAGEMENT LOCAL AUTOALLOCATE
    SEGMENT SPACE MANAGEMENT AUTO;

-- 创建 BIGFILE 表空间（10g+），仅一个数据文件，但单文件可达 128 TB
CREATE BIGFILE TABLESPACE big_data
    DATAFILE '/u01/oradata/orcl/big_data01.dbf' SIZE 10G
    AUTOEXTEND ON NEXT 1G MAXSIZE UNLIMITED;

-- 临时表空间（用于排序/哈希/全局临时表）
CREATE TEMPORARY TABLESPACE temp1
    TEMPFILE '/u01/oradata/orcl/temp01.dbf' SIZE 500M
    AUTOEXTEND ON NEXT 50M MAXSIZE 2G;

-- UNDO 表空间（存储多版本一致性数据）
CREATE UNDO TABLESPACE undotbs2
    DATAFILE '/u01/oradata/orcl/undotbs2.dbf' SIZE 200M
    AUTOEXTEND ON NEXT 20M MAXSIZE 4G
    RETENTION GUARANTEE;

-- 添加数据文件（在线扩容）
ALTER TABLESPACE users
    ADD DATAFILE '/u03/oradata/orcl/users03.dbf' SIZE 100M
    AUTOEXTEND ON NEXT 10M MAXSIZE 2G;

-- 调整数据文件大小
ALTER DATABASE DATAFILE '/u01/oradata/orcl/users01.dbf' RESIZE 500M;

-- 表空间设为只读（用于历史归档分区）
ALTER TABLESPACE archive_2023 READ ONLY;

-- 重命名 / 移动数据文件
ALTER DATABASE MOVE DATAFILE '/u01/oradata/orcl/users01.dbf'
    TO '/u04/oradata/orcl/users01.dbf';

-- 加密表空间（TDE）
CREATE TABLESPACE secure_data
    DATAFILE '/u01/oradata/orcl/secure01.dbf' SIZE 100M
    ENCRYPTION USING 'AES256'
    DEFAULT STORAGE(ENCRYPT);

-- 表与表空间绑定
CREATE TABLE customers (
    id NUMBER PRIMARY KEY,
    name VARCHAR2(100)
) TABLESPACE users;

-- 索引可单独放到不同表空间（机械分离 I/O）
CREATE INDEX idx_customers_name ON customers(name)
    TABLESPACE indexes;

-- 用户默认表空间
CREATE USER app1 IDENTIFIED BY pwd
    DEFAULT TABLESPACE users
    TEMPORARY TABLESPACE temp1
    QUOTA 5G ON users;
```

Oracle 的关键点：

- **SMALLFILE vs BIGFILE**：默认是 SMALLFILE，单个数据文件最大 32GB（8KB 块）。BIGFILE 表空间只能有一个数据文件，但该文件最大 128 TB（32KB 块下达 512 TB），适合超大数据仓库。
- **LOCAL EXTENT MANAGEMENT**：现代 Oracle 默认本地管理区段（位图），废弃了字典管理的旧方式。
- **AUTOALLOCATE vs UNIFORM**：AUTOALLOCATE 由 Oracle 选择 64K/1M/8M/64M 等区段大小；UNIFORM 强制相同大小，便于回收。
- **段空间管理 ASSM**：自动段空间管理用位图替代了 freelists，减少了高并发插入下的争用。

### Oracle Transportable Tablespace 深度剖析

Transportable Tablespace（可传输表空间）是 Oracle 自 8i 引入、至今其他主流数据库都没有完整对标的能力。它允许把一个表空间的物理数据文件**直接复制**到另一个 Oracle 数据库使用，跳过了逻辑导出/导入的解析与重建过程。对于 TB 级历史数据迁移，可比 expdp/impdp 快几十倍。

工作流程：

```sql
-- 1. 在源库：检查表空间是否自包含（不引用其他表空间的对象）
EXEC DBMS_TTS.TRANSPORT_SET_CHECK('archive_2023', TRUE);
SELECT * FROM TRANSPORT_SET_VIOLATIONS;
-- 必须为空，否则不能传输

-- 2. 在源库：将表空间设为只读
ALTER TABLESPACE archive_2023 READ ONLY;

-- 3. 在源库：使用 expdp 导出元数据（仅元数据，不导数据）
-- shell:
-- expdp system/pwd directory=dpdump dumpfile=ts.dmp \
--   transport_tablespaces=archive_2023 \
--   transport_full_check=y

-- 4. 物理复制数据文件到目标主机（cp / scp / rsync / ASM 工具）
--   /u01/oradata/orcl/archive_2023_01.dbf -> 目标主机

-- 5. 在目标库：使用 impdp 注册元数据并附加数据文件
-- impdp system/pwd directory=dpdump dumpfile=ts.dmp \
--   transport_datafiles='/u01/oradata/dest/archive_2023_01.dbf'

-- 6. 在源库与目标库：恢复 read/write
ALTER TABLESPACE archive_2023 READ WRITE;
```

Cross-Platform Transportable Tablespace（10g+）允许在不同操作系统/字节序之间传输，需要使用 RMAN CONVERT 转换字节序：

```sql
-- 在源库（big-endian Solaris）转换为 little-endian 文件
RMAN> CONVERT TABLESPACE archive_2023
      TO PLATFORM 'Linux x86 64-bit'
      FORMAT '/tmp/archive_2023_%U.dbf';
```

### PostgreSQL：简洁但完整

PostgreSQL 的 CREATE TABLESPACE 自 8.0（2005）引入。它的设计哲学不同于 Oracle：表空间只是**目录的别名**，所有文件管理交给 PostgreSQL 自己。

```sql
-- 创建表空间（必须指向已存在的、postgres 用户拥有的空目录）
CREATE TABLESPACE fastspace
    LOCATION '/ssd1/postgres'
    WITH (random_page_cost = 1.1);

-- 把现有表移动到表空间
ALTER TABLE orders SET TABLESPACE fastspace;

-- 索引也可放在不同表空间
CREATE INDEX idx_orders_date ON orders(order_date) TABLESPACE fastspace;

-- 临时对象表空间（排序/哈希溢出）
ALTER SYSTEM SET temp_tablespaces = 'fastspace';

-- 用户默认表空间
ALTER ROLE app1 SET default_tablespace = 'fastspace';

-- 数据库默认表空间
CREATE DATABASE warehouse TABLESPACE fastspace;

-- 删除表空间（必须先迁出所有对象）
DROP TABLESPACE fastspace;
```

PostgreSQL 内置两个系统表空间：

| 名称 | 用途 |
|------|------|
| `pg_default` | 默认表空间，物理位置在 `$PGDATA/base` |
| `pg_global` | 集群全局对象（如 pg_database, pg_authid），位置在 `$PGDATA/global` |

PostgreSQL 文件布局：

- 每个数据库一个子目录（以 OID 命名）
- 每个关系（表/索引/TOAST 表）至少一个文件，文件名是 relfilenode（OID 的初始值）
- 单文件超过 1 GB 自动分段：`<relfilenode>`、`<relfilenode>.1`、`<relfilenode>.2` ...
- 每个表还有 `_fsm`（free space map）、`_vm`（visibility map）副文件
- 大对象通过 TOAST 自动外联，存储在 `pg_toast` schema 的辅助表中

PostgreSQL 不支持 `ADD DATAFILE` 风格的扩容——一个表空间只对应一个 LOCATION，扩容靠操作系统层（LVM、ZFS、文件系统扩展）完成。也没有原生 TDE，加密通常通过 LUKS、ZFS 加密或 pg_tde 第三方扩展实现。

### SQL Server：FILEGROUP 与多文件

SQL Server 不用 "tablespace" 一词，而是 **FILEGROUP**（文件组）。一个数据库由若干文件组成：

- `.mdf`：主数据文件，必须存在，归属 PRIMARY 文件组
- `.ndf`：次数据文件，可属于任意文件组
- `.ldf`：事务日志文件（不属于任何文件组）

```sql
-- 创建数据库时指定多个文件组
CREATE DATABASE sales
ON PRIMARY
(   NAME = sales_primary,
    FILENAME = 'D:\data\sales.mdf',
    SIZE = 100MB, MAXSIZE = 500MB, FILEGROWTH = 50MB ),
FILEGROUP fg_data
(   NAME = sales_data1,
    FILENAME = 'D:\data\sales_data1.ndf',
    SIZE = 1GB, FILEGROWTH = 100MB ),
(   NAME = sales_data2,
    FILENAME = 'E:\data\sales_data2.ndf',
    SIZE = 1GB, FILEGROWTH = 100MB ),
FILEGROUP fg_archive
(   NAME = sales_archive,
    FILENAME = 'F:\data\sales_archive.ndf',
    SIZE = 5GB, FILEGROWTH = 500MB )
LOG ON
(   NAME = sales_log,
    FILENAME = 'G:\log\sales.ldf',
    SIZE = 500MB, FILEGROWTH = 100MB );

-- 添加新文件组
ALTER DATABASE sales ADD FILEGROUP fg_archive_2024;

-- 把表创建在指定文件组
CREATE TABLE Orders (
    OrderId BIGINT PRIMARY KEY,
    OrderDate DATE,
    Amount DECIMAL(10,2)
) ON fg_data;

-- 索引放到不同文件组
CREATE INDEX idx_orders_date ON Orders(OrderDate) ON fg_data;

-- 分区方案：按文件组划分
CREATE PARTITION FUNCTION pf_year (DATE)
    AS RANGE RIGHT FOR VALUES ('2023-01-01', '2024-01-01', '2025-01-01');

CREATE PARTITION SCHEME ps_year
    AS PARTITION pf_year
    TO (fg_archive, fg_archive, fg_data, fg_data);

-- 设为只读文件组（归档）
ALTER DATABASE sales MODIFY FILEGROUP fg_archive READ_ONLY;

-- 文件组级备份
BACKUP DATABASE sales FILEGROUP = 'fg_archive'
    TO DISK = 'H:\backup\sales_fg_archive.bak';
```

SQL Server 还支持 **FILESTREAM**：BLOB 数据直接存储为 NTFS 文件，由数据库管理事务一致性，避免了大对象进入页面的开销：

```sql
ALTER DATABASE sales ADD FILEGROUP fg_blobs CONTAINS FILESTREAM;
ALTER DATABASE sales ADD FILE
    (NAME = 'sales_blobs', FILENAME = 'D:\data\sales_blobs')
    TO FILEGROUP fg_blobs;

CREATE TABLE Documents (
    DocId UNIQUEIDENTIFIER ROWGUIDCOL UNIQUE NOT NULL,
    Content VARBINARY(MAX) FILESTREAM
);
```

SQL Server 内置 TDE（Transparent Data Encryption），可对整个数据库或单个备份加密。

### MySQL InnoDB：file-per-table 革命

MySQL InnoDB 早期所有表都放在共享表空间 `ibdata1` 中——一个不断增长且无法收缩的"黑洞"。这个设计在小数据量下没问题，但生产环境中删除大表后磁盘空间无法释放，被普遍诟病。

MySQL 5.6.6（2012）将 `innodb_file_per_table` 默认设为 ON，每张 InnoDB 表对应一个 `.ibd` 文件，删除表立即回收磁盘空间。MySQL 5.7 进一步引入 **General Tablespace**（通用表空间），允许把多个表组合到一个表空间文件中：

```sql
-- 配置：默认 file-per-table（5.6.6+ 默认 ON）
SET GLOBAL innodb_file_per_table = ON;

-- 创建表，自动产生 db_name/table_name.ibd
CREATE TABLE orders (
    id BIGINT PRIMARY KEY,
    amount DECIMAL(10,2)
) ENGINE=InnoDB;

-- 创建通用表空间（5.7+）
CREATE TABLESPACE ts_archive
    ADD DATAFILE 'ts_archive.ibd'
    FILE_BLOCK_SIZE = 16384
    ENGINE = InnoDB;

-- 把表创建在通用表空间
CREATE TABLE archive_orders (
    id BIGINT PRIMARY KEY,
    amount DECIMAL(10,2)
) TABLESPACE = ts_archive ENGINE=InnoDB;

-- 移动现有表到通用表空间
ALTER TABLE orders TABLESPACE = ts_archive;

-- 移回 file-per-table
ALTER TABLE orders TABLESPACE = innodb_file_per_table;

-- 移回系统表空间
ALTER TABLE orders TABLESPACE = innodb_system;

-- 加密表空间（8.0+ 需要 keyring 插件）
CREATE TABLESPACE ts_secure
    ADD DATAFILE 'ts_secure.ibd'
    ENGINE = InnoDB
    ENCRYPTION = 'Y';

-- UNDO 表空间（8.0+ 可独立创建/删除）
CREATE UNDO TABLESPACE undo_03 ADD DATAFILE 'undo_03.ibu';
ALTER UNDO TABLESPACE undo_03 SET INACTIVE;
DROP UNDO TABLESPACE undo_03;
```

MySQL 8.0 的关键改进：

- **8.0+ UNDO 表空间外置**：默认两个 `undo_001`、`undo_002`，可动态增加/截断
- **8.0+ 数据字典内联**：消除了 `.frm` 文件，所有元数据存于 InnoDB
- **临时表空间**：`ibtmp1` 单独管理，重启清空
- **加密**：表级、表空间级、binlog、undo、redo 都可加密

### DB2 LUW：DMS vs SMS

DB2 是少数明确区分 **System Managed Space (SMS)** 和 **Database Managed Space (DMS)** 两种表空间的数据库：

```sql
-- SMS：操作系统管理，容器是目录，表自动占用文件
CREATE TABLESPACE ts_sms
    MANAGED BY SYSTEM
    USING ('/db2/sms1', '/db2/sms2', '/db2/sms3')
    EXTENTSIZE 32
    PREFETCHSIZE 32;

-- DMS：数据库管理，容器是文件或裸设备，预分配
CREATE TABLESPACE ts_dms
    MANAGED BY DATABASE
    USING (
        FILE '/db2/dms1' 100000,    -- 单位是页
        FILE '/db2/dms2' 100000,
        DEVICE '/dev/raw/raw1' 100000
    )
    EXTENTSIZE 32
    PREFETCHSIZE AUTOMATIC
    AUTORESIZE YES
    INCREASESIZE 100 M
    MAXSIZE 50 G;

-- 自动存储（10.1+ 默认）：DBA 给一组路径，DB2 自动管理
CREATE STOGROUP sg_fast ON '/ssd1', '/ssd2'
    DEVICE READ RATE 200 MB/SEC OVERHEAD 1.0;

CREATE TABLESPACE ts_auto
    USING STOGROUP sg_fast;

-- 表空间类型
-- REGULAR: 用户表
-- LARGE: 大对象 / 索引
-- SYSTEM TEMPORARY: 系统临时
-- USER TEMPORARY: 全局声明临时表
CREATE LARGE TABLESPACE ts_lobs MANAGED BY DATABASE USING (FILE '/db2/lobs' 1G);
CREATE TEMPORARY TABLESPACE temp_ts MANAGED BY SYSTEM USING ('/db2/tmp');

-- 表空间备份
BACKUP DATABASE mydb TABLESPACE (ts_dms, ts_auto) ONLINE TO '/backup';
```

| 特性 | SMS | DMS |
|------|-----|-----|
| 容器 | 目录 | 文件 / 裸设备 |
| 空间管理 | OS | DB2 |
| 性能 | 中 | 高（可裸设备） |
| 扩展 | 自动 | ALTER TABLESPACE EXTEND |
| 推荐 | 已弃用 | 替代方案为 STOGROUP |

DB2 10.1+ 推荐使用 **自动存储（automatic storage）** + STOGROUP，避免手工管理容器。

### SQLite：极简的单文件

SQLite 走的是另一条极端路：**整个数据库就是一个文件**，没有表空间概念。文件内部按 page 组织，所有表、索引、元数据共享 page 空间，由 SQLite 自身的 free list 管理。

```sql
-- 没有 CREATE TABLESPACE
-- 所有表自动放入唯一的数据库文件
CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);

-- 唯一与"表空间"沾边的能力：ATTACH DATABASE，把另一个文件挂载为命名空间
ATTACH DATABASE 'archive.db' AS arch;

-- 现在可以跨"数据库"查询
SELECT * FROM users
UNION ALL
SELECT * FROM arch.users;

-- 把表"移动"到另一个文件
CREATE TABLE arch.users_2023 AS SELECT * FROM users WHERE created < '2024-01-01';
DELETE FROM users WHERE created < '2024-01-01';

-- 收回空间（SQLite 不会自动回收，需要 VACUUM）
VACUUM;
```

SQLite 这种设计的优点：零配置、零运维、单文件易于备份和分发；缺点是单文件最大 281 TB（理论），但实际并发性受写者排他锁限制。

### Snowflake / BigQuery：彻底隐藏存储

云原生数据仓库走向了完全相反的方向：**用户根本看不见物理文件**。

- **Snowflake**：所有数据被 Snowflake 内部切分为 micro-partition（FDN 文件，~16MB 列存压缩），存放在云对象存储（S3/Azure Blob/GCS）上。用户只能看到 schema 和表，micro-partition 由 Snowflake 自动维护、合并、聚簇。没有 `CREATE TABLESPACE`，没有数据文件路径，没有 ALTER ADD DATAFILE。表的物理布局通过 `CLUSTER BY` 提示影响，但具体文件依然不可见。
- **BigQuery**：底层是 Google 的 Capacitor 列存格式，存放在 Colossus 文件系统中。用户看到的是 dataset → table，物理分区只有 partition 列和 cluster 列两个调优维度，不存在 tablespace。

```sql
-- Snowflake：唯一与物理布局相关的语法
CREATE TABLE orders (
    id NUMBER, customer_id NUMBER, order_date DATE, amount DECIMAL(10,2)
) CLUSTER BY (order_date);

-- BigQuery：分区 + 聚簇
CREATE TABLE dataset.orders (
    id INT64, customer_id INT64, order_date DATE, amount NUMERIC
)
PARTITION BY order_date
CLUSTER BY customer_id;
```

这种"无表空间"模型把存储复杂度完全转移给云厂商，DBA 不再需要规划数据文件、监控空间、做表空间备份——但代价是**失去物理布局的精细控制权**。

### ClickHouse：存储策略 + 卷 + 多盘

ClickHouse 没有 SQL 层的 CREATE TABLESPACE，但有功能强大的 **存储策略（storage policy）** 机制，由配置文件定义，然后在 CREATE TABLE 时引用。一个存储策略由若干 **volume**（卷）组成，每个卷又由若干 **disk**（盘）组成，配合 TTL 表达式可实现自动的冷热数据分层。

```xml
<!-- /etc/clickhouse-server/config.d/storage.xml -->
<clickhouse>
  <storage_configuration>
    <disks>
      <hot_ssd>
        <path>/ssd/clickhouse/</path>
      </hot_ssd>
      <warm_hdd>
        <path>/hdd1/clickhouse/</path>
      </warm_hdd>
      <cold_s3>
        <type>s3</type>
        <endpoint>https://s3.amazonaws.com/my-bucket/clickhouse/</endpoint>
        <access_key_id>AKIA...</access_key_id>
        <secret_access_key>...</secret_access_key>
      </cold_s3>
    </disks>

    <policies>
      <tiered>
        <volumes>
          <hot>
            <disk>hot_ssd</disk>
            <max_data_part_size_bytes>10737418240</max_data_part_size_bytes>
          </hot>
          <warm>
            <disk>warm_hdd</disk>
          </warm>
          <cold>
            <disk>cold_s3</disk>
          </cold>
        </volumes>
        <move_factor>0.2</move_factor>
      </tiered>
    </policies>
  </storage_configuration>
</clickhouse>
```

```sql
-- 在表上引用存储策略并加 TTL 移动规则
CREATE TABLE events (
    event_time DateTime,
    user_id UInt64,
    action String,
    payload String
) ENGINE = MergeTree
ORDER BY (user_id, event_time)
TTL
    event_time + INTERVAL 7 DAY  TO VOLUME 'warm',
    event_time + INTERVAL 30 DAY TO VOLUME 'cold',
    event_time + INTERVAL 1 YEAR DELETE
SETTINGS storage_policy = 'tiered';

-- 手工把 part 移动到指定卷或盘
ALTER TABLE events MOVE PART '202401_1_1_0' TO VOLUME 'cold';
ALTER TABLE events MOVE PART '202401_1_1_0' TO DISK 'warm_hdd';

-- 查看每个 part 的存储位置
SELECT name, disk_name, path, bytes_on_disk
FROM system.parts
WHERE table = 'events' AND active
ORDER BY name;
```

ClickHouse 的存储策略相比传统表空间有几个独特点：

1. **声明式分层**：用 TTL 表达式描述数据生命周期，引擎自动迁移
2. **多盘 RAID-0 行为**：同一 volume 内多个 disk 自动 round-robin 分配 parts
3. **对象存储原生支持**：S3/HDFS/Azure 都可作为 disk 类型，无需 FUSE
4. **part 级粒度**：迁移单位是 part（一组列文件），不是表或文件组

### Vertica：Storage Locations 与 Storage Policies

Vertica 的存储抽象是 **storage location**（存储位置），可在节点级标记为 DATA / TEMP / DEPOT，配合 storage policy 控制对象到位置的映射：

```sql
-- 添加新的存储位置
SELECT ADD_LOCATION('/ssd/vertica_data1', 'v_node0001', 'DATA', 'SSD');
SELECT ADD_LOCATION('/hdd/vertica_data2', 'v_node0001', 'DATA', 'HDD');

-- 标记 SSD 为快速层
SELECT SET_LOCATION_PERFORMANCE('/ssd/vertica_data1', 'v_node0001', 'SSD');

-- 创建 storage policy 将表强制放到 SSD
SELECT SET_OBJECT_STORAGE_POLICY('public.orders', 'SSD');

-- 移动现有数据
SELECT ENFORCE_OBJECT_STORAGE_POLICY('public.orders');
```

### Teradata：Cylinder 与 AMP 自动管理

Teradata 走纯逻辑路线：用户**完全看不到表空间**。系统将磁盘划分为 **cylinder**（柱面），AMP（Access Module Processor，访问模块处理器）按行哈希分配数据到柱面。DBA 管理的是 PERM/TEMP/SPOOL 三种空间类型的 quota，而非物理文件：

```sql
-- 创建数据库时分配 PERM 空间
CREATE DATABASE sales AS
    PERM = 100E9            -- 100 GB 永久空间
    SPOOL = 50E9            -- 50 GB 中间结果空间
    TEMP = 10E9;            -- 10 GB 全局临时表空间

-- 修改空间配额
MODIFY DATABASE sales AS PERM = 200E9;

-- 用户级 quota
CREATE USER app1 FROM sales AS
    PASSWORD = pwd
    PERM = 10E9
    SPOOL = 5E9;
```

Teradata 的物理位置由内部的 **logical row ID** 系统决定，AMP 之间的数据再均衡是自动完成的。

### DuckDB：单文件或 ATTACH

DuckDB 类似 SQLite：一个数据库就是一个文件，没有 CREATE TABLESPACE。可以通过 ATTACH 挂载多个文件：

```sql
-- 主数据库
.open main.duckdb

-- 挂载第二个数据库文件作为命名空间
ATTACH 'archive.duckdb' AS arch;
ATTACH 'cold.duckdb' AS cold (READ_ONLY);

-- 跨数据库查询
SELECT * FROM main.users
UNION ALL
SELECT * FROM arch.users;

-- 把表移动到另一个 attached 数据库（手动 INSERT + DELETE）
CREATE TABLE arch.old_orders AS SELECT * FROM main.orders WHERE order_date < '2023-01-01';
DELETE FROM main.orders WHERE order_date < '2023-01-01';
```

DuckDB 也支持直接查询 Parquet/CSV/JSON 文件，相当于把"表空间"扩展到任意外部文件位置。

### Greenplum：每段独立表空间

Greenplum 继承 PostgreSQL 的 CREATE TABLESPACE，但因为是 MPP 架构，每个 segment（数据节点）都有独立的表空间路径：

```sql
-- 每个 segment 一个 location
CREATE TABLESPACE fast_ts
    LOCATION '/ssd/gp/seg{$content}'
    WITH (random_page_cost = 1.1);

-- 表上指定表空间，自动在所有 segment 创建对应目录
CREATE TABLE sales (
    id BIGINT, sale_date DATE, amount DECIMAL(10,2)
)
DISTRIBUTED BY (id)
TABLESPACE fast_ts;
```

### StarRocks / Doris：存储介质 + 多介质迁移

StarRocks 和 Apache Doris 用 **storage_medium** 属性区分 SSD 和 HDD，配合 cooldown_time 自动迁移：

```sql
-- StarRocks 创建表，初始放 SSD，30 天后迁到 HDD
CREATE TABLE events (
    event_time DATETIME, user_id BIGINT, action VARCHAR(64)
)
DUPLICATE KEY(event_time, user_id)
PARTITION BY RANGE(event_time) (
    PARTITION p202401 VALUES [('2024-01-01'), ('2024-02-01'))
)
DISTRIBUTED BY HASH(user_id) BUCKETS 32
PROPERTIES (
    "storage_medium" = "SSD",
    "storage_cooldown_time" = "2024-03-01 00:00:00"
);
```

### YugabyteDB：地理分区表空间

YugabyteDB 用 PostgreSQL 兼容的 CREATE TABLESPACE 实现地理分区——表空间不是磁盘位置，而是**副本放置策略**：

```sql
-- 美东表空间：副本放在 us-east-1 的 3 个 AZ
CREATE TABLESPACE us_east_ts WITH (
    replica_placement='{
        "num_replicas": 3,
        "placement_blocks": [
            {"cloud":"aws","region":"us-east-1","zone":"us-east-1a","min_num_replicas":1},
            {"cloud":"aws","region":"us-east-1","zone":"us-east-1b","min_num_replicas":1},
            {"cloud":"aws","region":"us-east-1","zone":"us-east-1c","min_num_replicas":1}
        ]
    }'
);

-- 表的某个分区放到该表空间，实现行级地域限制
CREATE TABLE users (user_id UUID, region TEXT, name TEXT)
PARTITION BY LIST (region);

CREATE TABLE users_us PARTITION OF users
    FOR VALUES IN ('us') TABLESPACE us_east_ts;
```

### 其他引擎速览

- **MariaDB**：基本继承 MySQL/InnoDB 的表空间能力，但 Aria/MyISAM 引擎是文件每表（`.MYD`/`.MYI`）。
- **Informix**：独有 **DBSPACE** + **CHUNK** 概念，DBSPACE 由若干 chunk 组成，chunk 可以是文件或裸设备，扩展靠 `onspaces -a`。
- **Firebird**：默认单文件，可通过 `ALTER DATABASE ADD FILE` 添加 secondary files，但只有第一个文件填满后才会写入下一个。
- **MonetDB**：列存数据库，每列一个 BAT 文件，没有表空间抽象。
- **CockroachDB / TiDB**：分布式 KV 存储（CockroachDB 用 Pebble，TiDB 用 RocksDB），没有表空间，只有 region/zone 配置。
- **OceanBase**：兼容 Oracle 的 CREATE TABLESPACE 语法（仅 Oracle 模式），底层映射到 LSM Tree 存储。
- **SAP HANA**：内存数据库，主存储是内存，"持久化"通过 data volume + log volume 实现，volume 对用户透明。
- **H2 / HSQLDB / Derby**：嵌入式 Java 数据库，单文件或目录，无表空间。
- **Athena / Trino / Presto / Spark / Hive / Flink**：查询引擎，存储完全交给 connector（HMS、Iceberg、Delta 等），表空间由数据湖目录结构间接体现（PARTITION BY）。
- **Materialize / RisingWave**：流处理数据库，状态存于 RocksDB，无表空间。
- **InfluxDB**：时序数据库，按 retention policy + shard group 自动分片，无表空间。
- **Databend / Yellowbrick / Firebolt**：云原生，与 Snowflake/BigQuery 类似，存储完全托管。

## 关键发现

### 1. 表空间是"前云时代"概念

表空间机制几乎全部诞生于 1980-2000 年代的本地磁盘时代，目的是解决单盘容量、I/O 局部性、数据文件运维三大问题。云原生数据仓库（Snowflake、BigQuery、Redshift、Databend、Firebolt、Yellowbrick）一律取消了表空间——因为对象存储本身就是无限弹性、跨多盘自动条带化的，DBA 不再需要管理物理文件。这是数据库存储模型最大的代际差异之一。

### 2. 真正完整支持表空间的只有少数老牌商用数据库

按"完整度"排序，真正实现了 CREATE TABLESPACE + 多数据文件 + 自增 + 只读 + 加密 + 备份 + 临时 + UNDO 全套能力的，只有 **Oracle、DB2、SQL Server**（FILEGROUP 形式）。PostgreSQL、MySQL 是"简化版"——PostgreSQL 一表空间一目录，不支持 ADD DATAFILE；MySQL 8.0 才补齐多 UNDO 表空间能力。

### 3. Transportable Tablespace 至今无人对标

Oracle 自 8i（1998）就支持的可传输表空间，让 TB 级数据物理迁移变为分钟级文件复制操作。其他主流数据库直到今天都没有同等能力——MySQL 的 FLUSH TABLES FOR EXPORT 只能搬单表，PostgreSQL 完全没有，SQL Server 只能 detach/attach 整库。这是 Oracle 在企业市场的护城河之一。

### 4. ClickHouse 的存储策略代表了新一代分层模型

ClickHouse 用 storage policy + volume + disk + TTL 表达式取代了静态表空间，引入了三个现代特性：（1）**声明式冷热分层**，引擎自动迁移；（2）**对象存储 disk 原生支持**，S3/HDFS 与本地盘同等对待；（3）**part 级粒度迁移**。这是分析型数据库存储模型的发展方向。

### 5. SQLite 与 DuckDB 用 ATTACH 替代了表空间

嵌入式数据库选择"一个数据库一个文件"的极简路线，用 ATTACH DATABASE 实现"多文件命名空间"——技术上不是表空间，但功能上覆盖了 DBA 想要"把冷数据挪到另一个文件"的场景，且零运维。

### 6. 文件每表 vs 共享表空间是个老争论

MySQL 早期共享 ibdata1 → 5.6.6 默认 file-per-table → 5.7 又引入通用表空间，反映了两种模型的取舍：

- **文件每表**：DROP TABLE 立即回收空间，运维简单；但海量小表场景下文件句柄/inode 压力大。
- **共享表空间**：减少 OS 文件数，写入聚集；但删表不还空间，单文件备份困难。

InnoDB 现在的方案是**让用户选**：默认 file-per-table，需要时用通用表空间打包。

### 7. 分布式数据库重新定义"表空间"

YugabyteDB 把表空间重新定义为**副本放置策略**——表空间不再是磁盘路径，而是"副本应该放在哪些数据中心/可用区"。这把传统表空间的物理含义升级为地理含义，用同一套语法解决了数据合规（GDPR、数据本地化）问题。CockroachDB 用 replication zone，TiDB 用 placement rules，都是异曲同工。

### 8. 表空间加密成为合规标配

合规驱动下（PCI DSS、HIPAA、GDPR），所有商用数据库（Oracle、SQL Server、DB2、MySQL Enterprise、MariaDB Enterprise、Vertica、Informix）都支持表空间级 TDE。开源 PostgreSQL 至今没有原生 TDE，只能依赖第三方扩展（pg_tde）或文件系统级加密（LUKS/ZFS），这是 PostgreSQL 进入金融核心系统时常被诟病的短板。

### 9. SQL 标准在表空间领域的缺席

虽然 SQL:2003 涉及若干物理存储概念，但 `CREATE TABLESPACE` 从未进入标准。每家厂商的语法、语义、运维流程都完全不同，迁移成本极高。这是 SQL 标准化最薄弱的领域之一，也很难弥补——因为表空间本身高度依赖底层存储模型，标准化反而会限制创新。

## 参考资料

- Oracle: [Managing Tablespaces](https://docs.oracle.com/en/database/oracle/oracle-database/19/admin/managing-tablespaces.html)
- Oracle: [Transporting Tablespaces Between Databases](https://docs.oracle.com/en/database/oracle/oracle-database/19/admin/transporting-data.html)
- PostgreSQL: [CREATE TABLESPACE](https://www.postgresql.org/docs/current/sql-createtablespace.html)
- PostgreSQL: [Database File Layout](https://www.postgresql.org/docs/current/storage-file-layout.html)
- SQL Server: [Database Files and Filegroups](https://learn.microsoft.com/en-us/sql/relational-databases/databases/database-files-and-filegroups)
- SQL Server: [FILESTREAM](https://learn.microsoft.com/en-us/sql/relational-databases/blob/filestream-sql-server)
- MySQL: [InnoDB File-Per-Table Tablespaces](https://dev.mysql.com/doc/refman/8.0/en/innodb-file-per-table-tablespaces.html)
- MySQL: [General Tablespaces](https://dev.mysql.com/doc/refman/8.0/en/general-tablespaces.html)
- MySQL: [Undo Tablespaces](https://dev.mysql.com/doc/refman/8.0/en/innodb-undo-tablespaces.html)
- DB2: [Table space design](https://www.ibm.com/docs/en/db2/11.5?topic=design-table-spaces)
- DB2: [Storage groups](https://www.ibm.com/docs/en/db2/11.5?topic=spaces-storage-groups)
- ClickHouse: [Multiple Volumes / Storage Policies](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree#table_engine-mergetree-multiple-volumes)
- Vertica: [Working with Storage Locations](https://docs.vertica.com/latest/en/admin/working-with-storage-locations/)
- Greenplum: [CREATE TABLESPACE](https://docs.vmware.com/en/VMware-Greenplum/index.html)
- YugabyteDB: [Tablespaces](https://docs.yugabyte.com/preview/explore/going-beyond-sql/tablespaces/)
- Teradata: [Database PERM/TEMP/SPOOL Space](https://docs.teradata.com/r/Teradata-VantageTM-Database-Administration)
- Informix: [Managing dbspaces](https://www.ibm.com/docs/en/informix-servers/14.10?topic=spaces-dbspaces)
- Snowflake: [Micro-partitions & Data Clustering](https://docs.snowflake.com/en/user-guide/tables-clustering-micropartitions)
- StarRocks: [Tiered storage](https://docs.starrocks.io/docs/administration/management/storage_volumes/)
