# 多租户数据库模式 (Multi-Tenant Database Patterns)

一个 SaaS 系统服务一万家公司，是给每家开一个独立数据库、还是让所有人共享一张大表？这道架构问题没有银弹——它把成本、隔离强度、运维复杂度、跨租户分析能力撕成四个相互冲突的目标，每个引擎用不同的物理结构和元数据机制给出自己的答卷。Oracle 在 2013 年用 CDB/PDB 把"租户"做成第一公民、PostgreSQL 用 schema + RLS 的轻量组合、Citus 把 `tenant_id` 升级为分布式分片键、Vitess 让每个租户落在独立 keyspace、Snowflake 让 account 成为天然边界——把这些不同思路放在同一张矩阵上对照，才能看清"多租户"在物理世界的真实样貌。

## 三种基本部署模式

无论数据库引擎是什么，多租户的物理实现可以归纳为以下三种基本模式（以及 Oracle 独有的"原生多租户"作为第四种）：

### 模式 1：Database-per-Tenant（每租户一库）

```
+--------------------+--------------------+--------------------+
|    DB instance     |   DB instance      |    DB instance     |
|                    |                    |                    |
|  acme_corp DB      |  globex DB         |  initech DB        |
|  +-orders          |  +-orders          |  +-orders          |
|  +-customers       |  +-customers       |  +-customers       |
|  +-invoices        |  +-invoices        |  +-invoices        |
+--------------------+--------------------+--------------------+
```

每个租户拥有独立的物理数据库实例（或独立的逻辑数据库）。隔离最强，连接独立、备份独立、可单独升级，但每个新租户都要付出实例级开销（连接池、共享缓冲区、WAL/redo），数千租户会让运维不可承受。适合 B2B 大客户、需要独立合规审计、每个租户数据量大的场景。

### 模式 2：Schema-per-Tenant（每租户一 Schema）

```
+----------------------------------------------------------+
|                    Single DB instance                    |
|                                                          |
|  schema acme       schema globex      schema initech    |
|  +-orders          +-orders           +-orders          |
|  +-customers       +-customers        +-customers       |
|  +-invoices        +-invoices         +-invoices        |
+----------------------------------------------------------+
```

所有租户共享同一个数据库实例，但每个租户拥有独立的 schema（命名空间）。数据隔离仍然清晰（DDL 互不影响），共享连接池和缓冲区，迁移和升级一次完成。短板：catalog 元数据膨胀（10,000 租户 × 50 表 = 500,000 表对象），DDL 漂移（不同 schema 版本不一致），跨 schema 查询需要 UNION ALL。适合中小规模 SaaS。

### 模式 3：Shared-Schema with tenant_id（共享表 + 租户列）

```
+----------------------------------------------------------+
|              Single DB / Single Schema                   |
|                                                          |
|  orders                                                  |
|  +----+-----------+--------+----------+                  |
|  | id | tenant_id | amount | ...      |                  |
|  +----+-----------+--------+----------+                  |
|  | 1  | acme      | 100    | ...      |                  |
|  | 2  | globex    | 200    | ...      |                  |
|  | 3  | acme      | 150    | ...      |                  |
+----------------------------------------------------------+
```

所有租户的数据共存于同一组表中，通过 `tenant_id` 列区分。资源利用率最高，加新租户零成本，跨租户分析只是一次 GROUP BY，但隔离最弱——单条遗忘的 `WHERE tenant_id = ?` 就是数据泄露事故。这种模式催生了行级安全（RLS）、连接池中的 `SET app.tenant_id`、以及在主键和索引中始终包含 `tenant_id` 作前缀的设计纪律。适合海量小租户、数据规模差距大的 SaaS。

### 模式 4：原生 CDB/PDB 多租户（Oracle 独有）

```
+---------------------------------------------------------------+
|                Container Database (CDB)                       |
|                                                               |
|  CDB$ROOT  <- shared metadata, common users, redo, undo       |
|     |                                                         |
|     +-- PDB$SEED  <- template for new PDBs                    |
|     +-- PDB acme   <- pluggable: own catalog, users, tablespaces
|     +-- PDB globex <- can be unplugged / plugged to another CDB
|     +-- PDB initech <- looks like a full database to apps     |
+---------------------------------------------------------------+
```

Oracle 12c (2013) 引入的 Multitenant Container Database 将"多租户"做进数据库内核：CDB 是容器、PDB 是可插拔的租户实例。每个 PDB 拥有独立的数据字典、用户空间、SYSTEM/SYSAUX 表空间，但共享 CDB 的进程、SGA、redo、undo。从应用视角，PDB 就是一个完整的数据库；从 DBA 视角，所有 PDB 在同一个实例下，可以像 USB 设备一样 unplug 和 plug。这是目前商用数据库中唯一原生的多租户实现。

## 没有 SQL 标准

ISO/IEC 9075（SQL 标准）从未定义"多租户"或"租户隔离"的概念——这是一个**纯实现层**的话题，标准只规范了语法和语义，物理部署模式由厂商自行决定。

最接近的标准化语义：

1. **SQL:2003 Schema 概念**：`<schema definition>` 定义 schema 是命名空间，可作为 schema-per-tenant 的语法基础，但标准未涉及隔离强度或元数据隔离。
2. **SQL/MED (SQL:2003)**：`CREATE FOREIGN SERVER` 提供跨数据源访问的语法基础，可用于 federated multi-tenancy，但与"租户"无直接关联。
3. **SQL:2016 Row Pattern Recognition + RLS 雏形**：行级安全相关语法在 SQL:2016 中被规范化（虽然各厂商实现差异极大），可作为"shared-schema + tenant_id"模式的安全基础。

CDB/PDB、shard-by-tenant、resource group、account hierarchy 等核心机制全部是**厂商扩展**。

## 多租户能力矩阵（45+ 引擎）

### 矩阵一：原生多租户支持

| 引擎 | 原生多租户 | 关键机制 | 起始版本 | 备注 |
|------|-----------|---------|---------|------|
| Oracle | 是 | Container DB / Pluggable DB | 12c (2013) | **唯一内核级原生实现** |
| SQL Server | 部分 | Elastic Pool（仅 Azure SQL DB）| 2014+ | 资源池共享，非真正"租户" |
| PostgreSQL | -- | schema + RLS 组合 | 9.5+ | 无原生概念，靠组合实现 |
| MySQL | -- | -- | -- | -- |
| MariaDB | -- | -- | -- | -- |
| SQLite | -- | -- | -- | 嵌入式，每个文件即一"租户" |
| DB2 | -- | -- | -- | -- |
| Snowflake | 是 | Account / Org / 数据共享 | GA | account 即天然租户边界 |
| BigQuery | 部分 | Project / Dataset / 资源预留 | GA | project 即天然租户边界 |
| Redshift | -- | RA3 + 数据共享 | -- | 通过 cluster 隔离 |
| DuckDB | -- | -- | -- | 嵌入式 |
| ClickHouse | 部分 | Cloud Service（Cloud 版） | -- | OSS 无原生支持 |
| Trino | 部分 | catalog / resource group | 350+ | catalog 间隔离 |
| Presto | 部分 | catalog | -- | 同 Trino |
| Spark SQL | -- | -- | -- | 计算引擎，依赖底层 catalog |
| Hive | -- | database 命名空间 | -- | 仅命名隔离 |
| Flink SQL | -- | -- | -- | 流引擎 |
| Databricks | 是 | Workspace + Unity Catalog | UC GA 2022 | catalog 层级隔离 |
| Teradata | 部分 | Resource Group / Database hierarchy | V2R5+ | 早期支持资源隔离 |
| Greenplum | -- | schema + RLS（继承 PG） | -- | -- |
| CockroachDB | 部分 | Multi-Region + Cluster Region | 21.1+ (2021) | 跨地理隔离非租户隔离 |
| TiDB | 是 | Resource Control / Resource Group | 7.1+ (2023) | 资源租户化 |
| OceanBase | 是 | **Tenant** 一等概念 | 1.x | 租户即顶级容器 |
| YugabyteDB | -- | RLS + schema | -- | 继承 PG |
| SingleStore | 部分 | Workspace（自建模式） | 8.5+ | -- |
| Vertica | -- | schema + 资源池 | -- | -- |
| Impala | -- | -- | -- | -- |
| StarRocks | 部分 | Resource Group | 3.0+ | -- |
| Doris | 部分 | Resource Group | 1.2+ | -- |
| MonetDB | -- | -- | -- | -- |
| CrateDB | -- | -- | -- | -- |
| TimescaleDB | -- | 继承 PG | -- | -- |
| QuestDB | -- | -- | -- | -- |
| Exasol | -- | schema | -- | -- |
| SAP HANA | 部分 | Tenant Database (MDC) | SP9+ | 类似 CDB/PDB 概念 |
| Informix | -- | -- | -- | -- |
| Firebird | -- | 多 alias | -- | 仅文件级 |
| H2 | -- | -- | -- | -- |
| HSQLDB | -- | -- | -- | -- |
| Derby | -- | -- | -- | -- |
| Athena | -- | Workgroup | -- | 资源隔离 |
| Azure Synapse | -- | -- | -- | -- |
| Spanner | 部分 | Instance / Database / Backup 隔离 | GA | 多数据库共实例 |
| Materialize | -- | Cluster | -- | 计算与存储分离 |
| RisingWave | -- | -- | -- | -- |
| InfluxDB SQL | 部分 | Bucket | -- | -- |
| Databend | 部分 | Tenant 概念 | GA | -- |
| Yellowbrick | -- | -- | -- | -- |
| Firebolt | 部分 | Workspace + Engine | GA | -- |
| Citus | 是 | Distributed table by tenant_id | 2010+ | **shard-by-tenant 典范** |
| Vitess | 是 | Keyspace per tenant / VIndex | 2012+ | 每租户 keyspace |
| Aurora Limitless | 是 | Sharded Group + tenant_id | 2024 GA | 自动分片 |

> 统计：约 12 个引擎拥有显式的"租户"概念或原生多租户机制，其余 30+ 引擎需通过 schema/数据库/RLS/分片键组合来模拟。

### 矩阵二：Schema-per-Tenant 元数据开销

`schema-per-tenant` 模式下，每个 schema 都要在 catalog 中注册一份完整的对象列表。当租户数量超过几千时，元数据查询、统计信息收集、连接池握手、catalog 缓存都会成为瓶颈。

| 引擎 | catalog 实现 | 千 schema 表现 | 元数据膨胀 | 备注 |
|------|------------|--------------|-----------|------|
| PostgreSQL | pg_catalog 系统表 | 良好（10K schema 可承受） | 中 | pg_namespace 索引 |
| MySQL | information_schema | 较差（系统表锁） | 高 | 8.0 重构后改善 |
| Oracle | data dictionary | 良好 | 低 | DBA_OBJECTS 优化 |
| SQL Server | sys.schemas | 良好 | 中 | -- |
| DB2 | SYSCAT | 良好 | 低 | -- |
| Snowflake | INFORMATION_SCHEMA + 元服务 | 优秀 | 低 | 元数据云原生 |
| BigQuery | INFORMATION_SCHEMA | 优秀 | 低 | dataset 即 schema |
| ClickHouse | system 数据库 | 良好 | 低 | -- |
| Trino | INFORMATION_SCHEMA | 视 connector | -- | -- |
| Hive | metastore | 较差（万级表困难） | 高 | metastore 单点 |
| Greenplum | 继承 PG | 良好 | 中 | 增加 segment 元同步开销 |
| CockroachDB | crdb_internal | 良好 | 中 | -- |
| TiDB | INFORMATION_SCHEMA + PD | 良好 | 中 | -- |
| Redshift | pg_class（兼容 PG） | 中等 | 中 | -- |

经验阈值：**1,000 个 schema 内基本所有主流引擎都能正常工作；10,000 个 schema 时 PostgreSQL/Oracle/Snowflake 仍稳定，MySQL 和 Hive metastore 开始显著退化；100,000 个 schema 时只有云原生 catalog（Snowflake、BigQuery）能保持秒级响应**。

### 矩阵三：RLS 用于租户隔离

| 引擎 | RLS 支持 | 语法关键 | 适合租户隔离 | 备注 |
|------|---------|---------|-------------|------|
| PostgreSQL | 是 (9.5+) | CREATE POLICY | **首选** | RLS + tenant_id 是标准方案 |
| Oracle | 是 (8i+) | DBMS_RLS / VPD | 是 | 最早实现 |
| SQL Server | 是 (2016+) | SECURITY POLICY | 是 | -- |
| Snowflake | 是 | ROW ACCESS POLICY | 是 | 与 ROLE 集成 |
| BigQuery | 是 | ROW ACCESS POLICY | 是 | 基于 IAM 主体 |
| DB2 | 是 (10.1+) | CREATE PERMISSION | 是 | -- |
| MySQL | -- | -- | -- | 需视图模拟 |
| MariaDB | -- | -- | -- | -- |
| ClickHouse | 是 (21.8+) | CREATE ROW POLICY | 是 | -- |
| Greenplum | 是 | 继承 PG | 是 | -- |
| TimescaleDB | 是 | 继承 PG | 是 | -- |
| YugabyteDB | 是 | 继承 PG | 是 | -- |
| CockroachDB | -- | (计划中) | -- | 未 GA |
| TiDB | -- | -- | -- | 7.x 路线图 |

详见 `row-level-security.md`。

### 矩阵四：租户感知的连接池与会话上下文

`shared-schema + tenant_id` 模式高度依赖"在每个查询自动注入 `tenant_id`"。各引擎提供的会话级上下文机制是关键基础。

| 引擎 | 会话变量 | 上下文 API | 设置范围 | 适合 RLS 注入 |
|------|---------|-----------|---------|--------------|
| PostgreSQL | `SET app.x = '..'` | `current_setting()` | 会话/事务 | **首选** |
| Oracle | DBMS_SESSION.SET_CONTEXT | `SYS_CONTEXT()` | 会话 | 是 |
| SQL Server | sp_set_session_context | `SESSION_CONTEXT()` | 会话 | 是 |
| MySQL | SET @var = '..' | @var | 会话 | 弱（用户可改） |
| Snowflake | -- | `CURRENT_ROLE()` 等 | 会话 | 通过角色 |
| BigQuery | -- | `SESSION_USER()` | 会话 | 是 |
| ClickHouse | settings | -- | 会话/查询 | 弱 |
| DB2 | SET SPECIAL REGISTER | `CURRENT CLIENT_*` | 会话 | 是 |
| TiDB | SET @var | -- | 会话 | -- |
| CockroachDB | SET cluster_setting / SET 会话变量 | -- | 会话 | -- |

### 矩阵五：跨租户查询能力

跨租户分析（"我们所有租户上周的 GMV"）在不同模式下难度差异巨大：

| 模式 | 跨租户查询难度 | 性能 | 典型实现 |
|------|--------------|------|---------|
| Database-per-tenant | 极难 | 差（需 federated query） | foreign tables / SCAN N databases |
| Schema-per-tenant | 中等 | 中（UNION ALL） | `SELECT * FROM acme.orders UNION ALL SELECT * FROM globex.orders ...` |
| Shared-schema | 简单 | 优秀（一次扫描） | `SELECT tenant_id, SUM(amount) FROM orders GROUP BY tenant_id` |
| Oracle CDB/PDB | 中等 | 中 | `CONTAINERS(orders)` + `CON_ID` |
| Citus shard-by-tenant | 中等 | 优 | distributed table + `EXECUTE_PARALLEL()` |
| Vitess sharding | 较难 | 中 | scatter query |
| Snowflake account hierarchy | 较难 | 中 | data sharing / 跨 account share |

## 各引擎深入分析

### Oracle Multitenant (CDB/PDB)

Oracle 12c (2013) 引入 Multitenant Container Database 是数据库内核级别多租户的奠基之作。

**核心架构**：

```
   Container DB (CDB)
  +-------------------+
  |   CDB$ROOT        |  <- 共享元数据、redo、undo、SGA
  |   (root container)|
  +--------+----------+
           |
   +-------+--------+--------+--------+
   |       |        |        |        |
PDB$SEED  PDB1    PDB2     PDB3     PDB(n)
   |       |        |        |        |
template  acme   globex   initech    ...
          (own data dictionary, users, tablespaces)
```

**关键事实**：

1. **2013 年发布**：Oracle 12.1.0.1 (12cR1)，2013 年 6 月正式 GA。
2. **Application Container（12.2，2017）**：在 PDB 之上引入 Application Container（ACS），允许多个 Application PDB 共享应用元数据。
3. **Non-CDB 弃用**：Oracle 12.2 (2017) 起 non-CDB 架构标记为 deprecated，21c (2021) 正式移除——所有新建数据库必须是 CDB。
4. **PDB 上限**：12c R1 = 252 个 PDB / CDB；19c 起最大 4096 个 PDB / CDB（需 Multitenant 选件）。
5. **Multitenant 选件**：CDB 包含一个 PDB 不需额外许可，超过一个 PDB 则需 Oracle Multitenant 选件（企业版选件，按 CPU 计）；自 19c 起，Standard Edition High Availability 与"3 PDB 免许可"政策也有调整。

**关键 SQL 示例**：

```sql
-- 1. 创建 PDB（从种子模板）
CREATE PLUGGABLE DATABASE acme_pdb
    ADMIN USER acme_dba IDENTIFIED BY "..."
    FILE_NAME_CONVERT = ('/oracle/seed', '/oracle/acme');

-- 2. 打开 PDB
ALTER PLUGGABLE DATABASE acme_pdb OPEN;

-- 3. 切换到 PDB
ALTER SESSION SET CONTAINER = acme_pdb;

-- 4. 在 PDB 中工作（与普通数据库无差别）
CREATE TABLE orders (id NUMBER, amount NUMBER);
INSERT INTO orders VALUES (1, 100);

-- 5. 拔出 PDB（变成可移动文件）
ALTER PLUGGABLE DATABASE acme_pdb CLOSE;
ALTER PLUGGABLE DATABASE acme_pdb UNPLUG INTO '/backup/acme.xml';

-- 6. 从备份插入到另一个 CDB
CREATE PLUGGABLE DATABASE acme_pdb
    USING '/backup/acme.xml'
    NOCOPY TEMPFILE REUSE;

-- 7. 复制 PDB（克隆租户）
CREATE PLUGGABLE DATABASE acme_clone FROM acme_pdb;
```

**字典视图**：

```sql
-- 列出所有 PDB
SELECT pdb_id, pdb_name, status, creation_time
FROM dba_pdbs
ORDER BY pdb_id;

-- PDB 的开放状态
SELECT con_id, name, open_mode, restricted
FROM v$pdbs;

-- 查看每个 PDB 的资源使用
SELECT con_id, pdb_name, total_size / 1024 / 1024 / 1024 AS size_gb
FROM cdb_pdbs
JOIN cdb_data_files USING (con_id);

-- 跨 PDB 查询（CONTAINERS 函数，Oracle 12.1.0.2+）
SELECT con_id, * FROM CONTAINERS(orders);  -- 跨所有 PDB 扫描 orders 表
```

**资源管理（Resource Manager + PDB）**：

```sql
-- 创建 CDB 级资源计划，限制每个 PDB 的 CPU/IO
BEGIN
    DBMS_RESOURCE_MANAGER.CREATE_CDB_PLAN(plan => 'multi_tenant_plan');
    DBMS_RESOURCE_MANAGER.CREATE_CDB_PLAN_DIRECTIVE(
        plan        => 'multi_tenant_plan',
        pluggable_database => 'acme_pdb',
        shares      => 50,           -- 相对权重
        utilization_limit => 80,      -- CPU 利用率上限 %
        parallel_server_limit => 50   -- 并行进程数上限 %
    );
END;
/
```

**Oracle Multitenant 的杀手级特性**：

1. **快速 PDB 拔插**：PDB 是一组数据文件 + 一个 XML 元数据文件，可在数秒内 unplug-from-CDB-A、plug-into-CDB-B。
2. **Snapshot Copy**：基于存储级 copy-on-write 的 PDB 克隆，1TB 的租户克隆只需数秒。
3. **PDB 级备份/恢复**：每个 PDB 可独立 RMAN 备份，单 PDB 恢复不影响其他 PDB。
4. **Common Users**：CDB 级别的 `c##admin` 用户可登录所有 PDB（运维便利）；Local Users 仅在单个 PDB 内有效（租户隔离）。
5. **Application Container（12.2+）**：多个 Application PDB 共享 Application Root 中的代码（PL/SQL 包、视图、序列），便于多租户 SaaS 应用统一升级。

### SQL Server Elastic Pools (Azure SQL Database)

Azure SQL Database 的 Elastic Pool 是多租户场景中的资源共享方案：

```sql
-- Elastic Pool 在 Azure 门户/Powershell/REST 中创建
-- 每个池中有多个 single database，共享 DTU/vCore 配额

-- 应用层选择租户数据库
USE acme_db;        -- 切换到 acme 租户
SELECT * FROM orders;

USE globex_db;
SELECT * FROM orders;
```

**特点**：
- Elastic Pool 适合"多个数据库 + 用量参差不齐"的 SaaS（资源整合，按池计费而非按库）。
- 数据库间完全隔离（独立 catalog、独立连接），但共享 Pool 级资源配额。
- 不支持自动 failover 跨数据库一致性，每个数据库独立 HA。
- **2014 年开始预览，2015 年 GA**。

**Azure SQL DB Elastic Database Tools**：
- Elastic Database Client Library 提供 shard map manager，应用代码自动按 tenant_id 路由到对应数据库。
- Split-Merge 工具支持 tenant 数据搬迁。

### PostgreSQL: Schema + RLS 组合方案

PostgreSQL 没有原生"租户"概念，但通过 schema 和 RLS 的组合实现了灵活的多租户：

**方案 A：Schema-per-tenant**

```sql
-- 1. 为每个新租户创建 schema
CREATE SCHEMA tenant_acme AUTHORIZATION acme_role;
CREATE SCHEMA tenant_globex AUTHORIZATION globex_role;

-- 2. 在每个 schema 中复用相同的表结构
CREATE TABLE tenant_acme.orders (id SERIAL PRIMARY KEY, amount NUMERIC);
CREATE TABLE tenant_globex.orders (id SERIAL PRIMARY KEY, amount NUMERIC);

-- 3. 应用层连接时切换 search_path
SET search_path TO tenant_acme, public;
SELECT * FROM orders;     -- 实际查询 tenant_acme.orders

-- 4. 跨租户分析（UNION ALL）
SELECT 'acme' AS tenant, SUM(amount) FROM tenant_acme.orders
UNION ALL
SELECT 'globex', SUM(amount) FROM tenant_globex.orders;

-- 5. DDL 统一升级（需要外部工具，如 pg-tenant 或自研脚本）
DO $$
DECLARE
    s_name TEXT;
BEGIN
    FOR s_name IN SELECT schema_name FROM information_schema.schemata
                  WHERE schema_name LIKE 'tenant_%'
    LOOP
        EXECUTE format('ALTER TABLE %I.orders ADD COLUMN status VARCHAR(20)', s_name);
    END LOOP;
END$$;
```

**方案 B：Shared-schema + tenant_id + RLS（最常见）**

```sql
-- 1. 表结构添加 tenant_id 列
CREATE TABLE orders (
    id BIGSERIAL PRIMARY KEY,
    tenant_id TEXT NOT NULL,
    amount NUMERIC NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. tenant_id 加入所有索引前缀
CREATE INDEX idx_orders_tenant_created ON orders (tenant_id, created_at DESC);

-- 3. 启用 RLS
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- 4. 创建租户隔离策略
CREATE POLICY tenant_isolation ON orders
    USING (tenant_id = current_setting('app.tenant_id'));

-- 5. 强制所有者也受 RLS 约束
ALTER TABLE orders FORCE ROW LEVEL SECURITY;

-- 6. 应用连接时设置上下文（连接池中执行）
SET app.tenant_id = 'acme';
-- 之后所有查询自动注入 WHERE tenant_id = 'acme'
SELECT * FROM orders;

-- 7. 跨租户查询（管理员角色）
SET ROLE postgres;     -- superuser/owner（无 FORCE 时绕过）
SELECT tenant_id, SUM(amount) FROM orders GROUP BY tenant_id;
```

**关键设计纪律**：

1. 所有表的主键应包含 `tenant_id`：`PRIMARY KEY (tenant_id, id)`，便于 partition 和 sharding。
2. 所有索引前缀必须是 `tenant_id`：避免跨租户扫描。
3. 所有外键 ON DELETE CASCADE 应包括 `tenant_id` 列：维护租户内一致性。
4. 唯一约束必须包含 `tenant_id`：`UNIQUE (tenant_id, email)`，避免侧信道泄露租户边界。
5. 连接池配置：每条连接 checkout 时执行 `SET app.tenant_id = ?`，return 时执行 `RESET app.tenant_id`。

**租户分区（PostgreSQL 11+ 声明式分区）**：

```sql
-- 大租户独占分区，小租户共享 default 分区
CREATE TABLE orders (
    tenant_id TEXT NOT NULL,
    id BIGINT NOT NULL,
    amount NUMERIC,
    PRIMARY KEY (tenant_id, id)
) PARTITION BY LIST (tenant_id);

CREATE TABLE orders_acme PARTITION OF orders FOR VALUES IN ('acme');
CREATE TABLE orders_globex PARTITION OF orders FOR VALUES IN ('globex');
CREATE TABLE orders_default PARTITION OF orders DEFAULT;
```

### Citus: 分布式 shard-by-tenant

Citus 是 PostgreSQL 的分布式扩展，自 2010 年起开发，2016 年开源，2019 年被 Microsoft 收购，现作为 Azure Cosmos DB for PostgreSQL 的核心。

**Citus 的多租户哲学**：

将 `tenant_id` 设为分布式表的 distribution column，相同 `tenant_id` 的所有数据落在同一个 worker 节点上。这意味着：

1. 租户内的 JOIN/事务/外键全部本地化（无跨节点开销）。
2. 跨租户查询变为 scatter-gather（每个 worker 独立执行 + coordinator 汇总）。
3. 加新租户只需 hash 分配到现有 shard，无需新建数据库。

**关键 SQL**：

```sql
-- 1. 创建分布式表，按 tenant_id 分布
CREATE TABLE orders (
    tenant_id BIGINT NOT NULL,
    id BIGSERIAL,
    amount NUMERIC,
    PRIMARY KEY (tenant_id, id)
);
SELECT create_distributed_table('orders', 'tenant_id');

CREATE TABLE customers (
    tenant_id BIGINT NOT NULL,
    id BIGSERIAL,
    name TEXT,
    PRIMARY KEY (tenant_id, id)
);
SELECT create_distributed_table('customers', 'tenant_id', colocate_with => 'orders');

-- 2. 共置（colocation）保证同一 tenant_id 的 orders 和 customers 在同一 worker 上
-- 这样 JOIN 不需要跨节点

-- 3. 引用表（reference table）：所有 worker 上完整复制
-- 适合小型维度表（如 country、currency）
CREATE TABLE countries (code CHAR(2) PRIMARY KEY, name TEXT);
SELECT create_reference_table('countries');

-- 4. 租户内的 JOIN（本地执行）
SELECT o.id, o.amount, c.name
FROM orders o
JOIN customers c ON o.tenant_id = c.tenant_id AND o.customer_id = c.id
WHERE o.tenant_id = 42;

-- 5. 跨租户聚合（scatter-gather）
SELECT tenant_id, SUM(amount) FROM orders GROUP BY tenant_id;

-- 6. 单租户隔离（迁移大租户到独立 worker）
SELECT isolate_tenant_to_new_shard('orders', 100);
-- 把 tenant_id = 100 的数据迁移到一个独立 shard
```

**Citus 多租户的最佳实践**：

1. **共置组**：所有租户相关表（orders、customers、invoices...）使用相同的 distribution column 和 `colocate_with`。
2. **租户内的外键**：`FOREIGN KEY (tenant_id, customer_id) REFERENCES customers(tenant_id, id)` 必须包含 `tenant_id` 列。
3. **大租户隔离**：用 `isolate_tenant_to_new_shard` 把 hot tenant 单独搬到一个 shard。
4. **shard count 选择**：`citus.shard_count = 32`（默认）适合中小集群；大集群用 64 或 128。

### Vitess: Shard-by-Tenant on MySQL

Vitess 是 YouTube 在 2010 年开始开发、2012 年开源的 MySQL 水平分片中间件，现在由 PlanetScale 和 CNCF 支持。

**Vitess 的多租户实现**：

```
+--------------------+
|     vtgate         |  <- 路由层，应用唯一连接点
+---------+----------+
          |
   +------+------+------+
   |      |      |      |
keyspace customer keyspace
   |      |      
+--+--+ +--+--+
|     | |     |
shard shard shard shard
(0)   (1)   (2)   (3)
```

**两种典型多租户方案**：

**方案 A：Keyspace per Tenant**（强隔离）

```sql
-- 每个大租户独立 keyspace（即独立的逻辑分片集合）
-- VSchema 定义：
{
    "keyspaces": {
        "acme": { "sharded": false },
        "globex": { "sharded": false },
        "shared": { "sharded": true, "tables": {...} }
    }
}

-- 应用通过 USE keyspace 切换
USE acme;
SELECT * FROM orders;

USE globex;
SELECT * FROM orders;
```

适合需要强隔离的大客户。Vitess 提供 `vtctl ApplyVSchema` 在线修改 schema。

**方案 B：Sharded Keyspace + tenant_id VIndex**（共享 + 分片）

```json
{
    "keyspaces": {
        "saas_db": {
            "sharded": true,
            "vindexes": {
                "tenant_hash": { "type": "hash" }
            },
            "tables": {
                "orders": {
                    "column_vindexes": [
                        { "column": "tenant_id", "name": "tenant_hash" }
                    ]
                },
                "customers": {
                    "column_vindexes": [
                        { "column": "tenant_id", "name": "tenant_hash" }
                    ]
                }
            }
        }
    }
}
```

应用层无需感知分片，VTGate 根据 `tenant_id` 自动路由。同 `tenant_id` 的数据始终落在同一 shard，本地 JOIN 高效；跨租户查询变 scatter。

**Vitess 的核心机制**：

- **VTGate**：无状态路由层，解析 SQL 并路由到对应 shard。
- **VTTablet**：每个 shard 一个，对底层 MySQL 实例做查询代理 + 限流 + 缓存。
- **VStream**：基于 binlog 的 CDC，用于 resharding（在线 split shard）。
- **Resharding**：Vitess 最强大的能力之一，可在线把一个 shard 拆成两个或合并两个 shard，对应用透明。

### CockroachDB: Multi-Region 与 Cluster 隔离

CockroachDB 不主打"多租户"，但其多区域能力（21.1 GA, 2021）为合规驱动的租户隔离提供基础：

```sql
-- 1. 配置集群区域
ALTER DATABASE saas_db CONFIGURE ZONE USING
    num_replicas = 5,
    constraints = '{+region=us-east: 2, +region=eu-west: 2, +region=ap-south: 1}';

-- 2. REGIONAL BY ROW: 每行根据 region 列决定主副本所在区域
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id TEXT NOT NULL,
    region crdb_internal_region NOT NULL DEFAULT 'us-east',
    amount NUMERIC
) LOCALITY REGIONAL BY ROW AS region;

-- 3. 租户的数据可以根据合规要求落在指定区域
INSERT INTO orders VALUES (gen_random_uuid(), 'acme_eu', 'eu-west', 100);
-- 这条记录的 leaseholder 在 eu-west 区域，写入和读取都本地化
```

**Multi-Region 关键能力**：

- **REGIONAL BY ROW**：行级地理放置（21.1+，2021）。
- **REGIONAL BY TABLE**：表级放置（21.1+）。
- **GLOBAL**：表在所有区域只读快速（21.1+）。
- **Survival goals**：`survive zone failure` vs `survive region failure`。

CockroachDB 的"多租户"更接近"多 cluster + 数据共享"，目前没有 Oracle 式的 PDB 概念。

### TiDB: Resource Control 与 Resource Group

TiDB 7.1 (2023 年 6 月) GA 的 Resource Control 是其多租户故事的核心：

```sql
-- 1. 创建资源组（每个组可视为一个"逻辑租户"）
CREATE RESOURCE GROUP acme_rg
    RU_PER_SEC = 5000        -- 每秒可用 Request Unit
    PRIORITY = HIGH
    BURSTABLE;                -- 允许临时超用

CREATE RESOURCE GROUP globex_rg
    RU_PER_SEC = 2000
    PRIORITY = MEDIUM;

-- 2. 用户绑定到资源组
ALTER USER acme_user RESOURCE GROUP acme_rg;
ALTER USER globex_user RESOURCE GROUP globex_rg;

-- 3. 会话级切换资源组
SET RESOURCE GROUP acme_rg;
SELECT * FROM orders;        -- 这次查询的资源消耗计入 acme_rg

-- 4. 监控
SELECT * FROM information_schema.resource_groups;
SELECT * FROM information_schema.runaway_watches;
```

**Resource Unit (RU)**：

TiDB 把 CPU、IO、网络等资源抽象为统一的 RU，每个查询的资源消耗折算成 RU 数量。Resource Group 限定每秒可消耗的 RU 总量，超出则限流。

**Runaway Query**：

```sql
-- 7.2+ 支持 Runaway Query 检测，自动 KILL 长查询
ALTER RESOURCE GROUP acme_rg
    QUERY_LIMIT = (EXEC_ELAPSED='30s', ACTION=KILL);
```

TiDB 的多租户思路与 OceanBase 的 Tenant 概念不同：TiDB 不做物理隔离（所有 tenant 共用 KV 存储和 PD），而是通过 RU 配额做软隔离，类似 Oracle Resource Manager。

### OceanBase: Tenant 一等公民

OceanBase 是少数将"租户"作为顶级数据库对象的引擎之一：

```sql
-- 1. 创建租户（DBA 操作，连到 sys 租户）
CREATE TENANT acme_tenant
    RESOURCE_POOL_LIST = ('acme_pool')
    PRIMARY_ZONE = 'zone1, zone2'
    RESOURCE = (memory_size '10G', cpu_count 4, log_disk_size '50G');

-- 2. 切换到租户连接
-- mysql -h obproxy -P 2883 -u root@acme_tenant -p

-- 3. 租户内一切独立（用户、数据库、表、权限）
CREATE DATABASE app;
CREATE TABLE orders (id BIGINT, amount DECIMAL);

-- 4. 租户类型
-- - sys 租户: 系统租户，存储集群元数据
-- - 普通租户: MySQL 模式或 Oracle 模式（OceanBase 双模式）
```

**OceanBase Tenant 的关键特性**：

1. **完全隔离**：每个租户拥有独立的 schema、用户、权限、字符集、时区，连接和查询完全互不可见。
2. **资源池绑定**：每个租户绑定一个 resource pool，pool 跨多个 zone 部署 unit（OceanBase 的部署单元）。
3. **MySQL 与 Oracle 双模式**：创建租户时指定 `MODE = 'MYSQL'` 或 `MODE = 'ORACLE'`，租户内 SQL 方言不同。
4. **租户克隆**：支持基于备份快速克隆租户。

OceanBase 是阿里云自研、为支付宝多租户场景而生的数据库，租户模型是其核心差异化能力。

### Snowflake: Account Hierarchy

Snowflake 没有"租户"显式概念，但 **Account / Organization / Data Sharing** 三件套天然支持多租户：

```
Organization (顶级)
  +-- Account: prod_acme
  |     +-- Database, Schema, Tables
  |     +-- Users, Roles, Resource Monitors
  +-- Account: prod_globex
  |     +-- ...
  +-- Account: prod_initech
        +-- ...
```

每个 account 是一个完全独立的 Snowflake 实例（独立元数据、独立计费、独立 URL），但属于同一 organization 下，便于集中管理：

```sql
-- 在 Organization 级别创建 account
CREATE ACCOUNT acme_account
    EDITION = ENTERPRISE
    ADMIN_NAME = 'acme_admin'
    EMAIL = 'admin@acme.com'
    REGION = 'aws_us_east_1';

-- Data Sharing：跨 account 共享数据（无需复制）
-- 在 provider account 中
CREATE SHARE acme_data_share;
GRANT USAGE ON DATABASE production TO SHARE acme_data_share;
GRANT SELECT ON SCHEMA production.public TO SHARE acme_data_share;

-- 在 consumer account 中
CREATE DATABASE acme_data FROM SHARE provider_account.acme_data_share;
SELECT * FROM acme_data.public.orders;     -- 查询直接从 provider 的 storage 读取
```

**Snowflake 多租户的常见模式**：

1. **Account-per-tenant**：大客户每人一个 account，强隔离 + 独立计费，运维成本高但合规简单。
2. **Schema/Role-per-tenant**：单 account 内每租户一个 schema + 一个 role，shared compute warehouse 但数据隔离。
3. **Row Access Policy + tenant_id**：单 account + 单 schema + 单表，靠 RLS 隔离（详见 `row-level-security.md`）。

### BigQuery: Project / Dataset Isolation

BigQuery 的多租户依赖 GCP IAM 和 project/dataset 层级：

```
GCP Organization
  +-- Project: saas-shared      # 公共数据 + 计算配额
  |     +-- Dataset: shared_data
  +-- Project: tenant-acme       # 租户独立 project
  |     +-- Dataset: app_data
  |     +-- BigQuery slot 预留 (1000 slots)
  +-- Project: tenant-globex
        +-- Dataset: app_data
        +-- 共享 saas-shared 的 slots
```

**BigQuery 多租户的关键机制**：

1. **Project as Tenant**：每个租户一个 project，IAM 隔离 + 独立计费 + 独立 quota，类似 Snowflake account。
2. **Dataset Isolation**：单 project 内每租户一个 dataset，IAM 在 dataset 级别授权。
3. **Authorized Views**：跨 dataset 共享数据的标准方式，view 持有读权限但底层 dataset 不需要授权给最终用户。
4. **Row Access Policy**：dataset 内表级别的 RLS（详见 `row-level-security.md`）。
5. **Reservations and Slots**：BigQuery 的 slot 预留（reservation）支持按 project 分配，做资源隔离。

### Aurora Limitless Database

AWS Aurora Limitless 在 2024 年 GA，是 PostgreSQL/MySQL 兼容的自动 sharding 方案，专为 SaaS 多租户设计：

```sql
-- Aurora Limitless 在 Aurora PostgreSQL/MySQL 集群中启用 limitless 路由器节点
-- 应用使用单一 endpoint，路由器层做自动分片

-- 1. 创建 sharded table（Aurora Limitless 扩展语法）
CREATE TABLE orders (
    tenant_id BIGINT NOT NULL,
    id BIGSERIAL,
    amount NUMERIC,
    PRIMARY KEY (tenant_id, id)
) WITH (shard_key = 'tenant_id', distribution = 'sharded');

-- 2. 创建参考表（每个 shard 完整复制）
CREATE TABLE countries (code CHAR(2) PRIMARY KEY, name TEXT)
WITH (distribution = 'reference');

-- 3. 应用层透明
-- 单一 endpoint 接收所有查询，路由器根据 tenant_id 自动分发
INSERT INTO orders (tenant_id, amount) VALUES (1, 100);     -- 路由到 shard 1
INSERT INTO orders (tenant_id, amount) VALUES (2, 200);     -- 路由到 shard 2
```

**Aurora Limitless 的核心**：

- **Router Layer**：无状态查询路由，类似 Vitess VTGate 或 Citus coordinator。
- **Shard Group**：一组 Aurora 实例构成一个 shard group，自动负载均衡。
- **Auto-Splitting**：当 shard 数据增长超过阈值，自动拆分（在线，无需停机）。
- **2024 年 GA**（PostgreSQL 兼容），MySQL 兼容版仍在 preview。

### 其他引擎概览

#### SAP HANA Multitenant Database Containers (MDC)

SAP HANA 在 SP9 (2014) 引入 MDC 模式，类似 Oracle CDB/PDB：

```sql
-- 在 SystemDB 中创建 tenant database
CREATE DATABASE acme_tenant
    SYSTEM USER PASSWORD "..."
    PORT 30041;

-- 切换到租户
-- 通过独立 port 连接，每个 tenant 一个端口
```

每个 tenant DB 拥有独立 catalog、用户、备份；共享同一台机器的内存和磁盘，但通过 NUMA 隔离。

#### Spanner: Instance / Database 层级

Google Spanner 的多租户表现为：

- **Instance**：物理资源单位（节点数、区域）。
- **Database**：实例下的逻辑数据库，独立 schema 和数据。
- 同一 instance 下多个 database 共享计算资源，跨 instance 完全隔离。
- 没有 RLS（截至 2024 年），多租户共享表需应用层注入 `tenant_id`。

#### Databricks Unity Catalog

Unity Catalog (UC) 在 2022 年 GA，提供三层命名空间：

```
metastore
  +-- catalog: prod_acme
  |     +-- schema: bronze
  |     |     +-- table: orders
  |     +-- schema: silver
  +-- catalog: prod_globex
        +-- schema: bronze
```

每个 workspace 可绑定到一个 metastore，catalog 提供租户级隔离，schema 提供数据层级。

#### Trino / Presto: Catalog 隔离

Trino 通过 catalog（数据源连接器）提供有限的多租户：

```sql
SELECT * FROM acme_catalog.public.orders;
SELECT * FROM globex_catalog.public.orders;
```

不同 catalog 可以连接到不同的物理数据源（不同 PostgreSQL 实例、不同 S3 bucket），实现"联邦多租户"。资源组（resource group）提供查询级资源隔离。

#### ClickHouse: Cloud 模式与 Row Policy

ClickHouse OSS 没有原生多租户，但 ClickHouse Cloud 通过独立 service 隔离：

```sql
-- ClickHouse 21.8+ 行级策略（用于 shared-schema 模式）
CREATE ROW POLICY acme_filter ON orders
    USING tenant_id = currentUser()
    TO acme_role;

-- 资源限制
CREATE QUOTA acme_quota
    KEYED BY user_name
    FOR INTERVAL 1 hour
        MAX queries 1000, MAX read_rows 1000000000
    TO acme_user;
```

#### CrateDB / TimescaleDB / YugabyteDB / Greenplum

继承 PostgreSQL 的 schema + RLS 模型，多租户实现思路与 PostgreSQL 一致。其中：

- **TimescaleDB**：在时序场景下，可按 tenant_id 设置 hypertable 分区维度。
- **YugabyteDB**：分布式 PostgreSQL，自动按 hash 分片，可用 tablespace 把租户固定到特定区域。
- **Greenplum**：MPP 数据仓库，schema-per-tenant 在数百租户级别可行。

#### StarRocks / Doris: Resource Group

StarRocks 3.0+ 和 Doris 1.2+ 引入 Resource Group，类似 TiDB：

```sql
-- StarRocks
CREATE RESOURCE GROUP acme_rg
    TO (USER='acme_user')
    WITH ('cpu_core_limit'='8', 'mem_limit'='30%', 'concurrency_limit'='10');

-- Doris  
CREATE RESOURCE GROUP acme_group
    PROPERTIES ('cpu_share'='10', 'memory_limit'='30%');
```

#### Materialize: Cluster 隔离

Materialize 计算与存储分离，每个 cluster 是独立的计算资源：

```sql
CREATE CLUSTER acme_cluster REPLICAS (r1 (SIZE = 'medium'));
SET cluster = acme_cluster;
-- 之后所有 materialized view 在 acme_cluster 上计算
```

不同 cluster 的查询互不影响，但底层数据共享。

## Oracle CDB/PDB 深入剖析

Oracle Multitenant 是目前唯一的内核级多租户实现，本节展开它的元数据视图、资源管理、备份与克隆。

### DBA 视图层级

```sql
-- CDB 全局视图（前缀 CDB_）：跨所有 PDB
SELECT con_id, table_name FROM cdb_tables WHERE owner = 'HR';

-- DBA 视图（前缀 DBA_）：当前 container 内
SELECT table_name FROM dba_tables WHERE owner = 'HR';

-- ALL 视图：当前用户可访问的对象
-- USER 视图：当前用户拥有的对象

-- PDB 元数据
SELECT pdb_id, pdb_name, status, creation_time, total_size
FROM dba_pdbs ORDER BY pdb_id;

-- PDB 实时状态
SELECT con_id, name, open_mode, restricted, creation_time
FROM v$pdbs;

-- PDB 历史（拔插事件）
SELECT pdb_name, operation, op_timestamp
FROM dba_pdb_history;

-- PDB 服务（每个 PDB 有自己的 service name）
SELECT pdb, name, network_name FROM cdb_services WHERE pdb IS NOT NULL;
```

### Common 与 Local 用户

```sql
-- Common User（CDB 级别，所有 PDB 中可见）：必须以 c## 或 C## 开头
ALTER SESSION SET CONTAINER = CDB$ROOT;
CREATE USER c##common_admin IDENTIFIED BY "..." CONTAINER = ALL;
GRANT DBA TO c##common_admin CONTAINER = ALL;

-- Local User（PDB 内）：只在该 PDB 中存在
ALTER SESSION SET CONTAINER = acme_pdb;
CREATE USER acme_user IDENTIFIED BY "..." CONTAINER = CURRENT;
GRANT CONNECT, RESOURCE TO acme_user;

-- 切换租户
ALTER SESSION SET CONTAINER = globex_pdb;
SELECT user FROM dual;     -- 返回连接时的用户

-- Common Role
CREATE ROLE c##saas_app_role CONTAINER = ALL;
GRANT SELECT ON cdb_view TO c##saas_app_role CONTAINER = ALL;
```

### PDB 备份与克隆

```sql
-- 1. RMAN 备份单个 PDB（Oracle 12c+）
RMAN> CONNECT TARGET sys/password@acme_pdb;
RMAN> BACKUP PLUGGABLE DATABASE acme_pdb;
RMAN> RESTORE PLUGGABLE DATABASE acme_pdb;

-- 2. 在线克隆 PDB（适合"沙箱"场景：从生产复制到 staging）
CREATE PLUGGABLE DATABASE acme_staging
    FROM acme_pdb@dblink_to_prod
    FILE_NAME_CONVERT = ('/oracle/prod', '/oracle/staging')
    REFRESH MODE EVERY 60 MINUTES;        -- Refreshable PDB（19c+）

-- Refreshable PDB 是 19c 关键特性：定期增量同步源 PDB

-- 3. Snapshot Copy（基于存储级 CoW，需 ASM 或 ACFS）
CREATE PLUGGABLE DATABASE acme_test
    FROM acme_pdb
    SNAPSHOT COPY
    FILE_NAME_CONVERT = ('/oracle/prod', '/oracle/test');
-- 1TB 的 PDB 克隆只需数秒（不复制数据，仅共享底层快照）
```

### Application Container（12.2+）

Application Container（ACS）是 12.2 (2017) 引入的"二级容器"概念，用于多租户 SaaS 应用统一升级：

```sql
-- 1. 创建 Application Root（在 CDB$ROOT 之下，普通 PDB 之上）
CREATE PLUGGABLE DATABASE app_root AS APPLICATION CONTAINER
    ADMIN USER app_admin IDENTIFIED BY "...";

-- 2. 在 Application Root 中创建应用代码
ALTER SESSION SET CONTAINER = app_root;
ALTER PLUGGABLE DATABASE BEGIN INSTALL 'saas_app' VERSION '1.0';
CREATE TABLE orders (id NUMBER, amount NUMBER) SHARING = METADATA;
CREATE PACKAGE order_logic AS ... SHARING = OBJECT;
ALTER PLUGGABLE DATABASE END INSTALL 'saas_app';

-- 3. 创建 Application PDB（基于 Application Root）
CREATE PLUGGABLE DATABASE acme_app FROM app_root@dblink;

-- 4. 应用升级（Application Root 一次性升级）
ALTER SESSION SET CONTAINER = app_root;
ALTER PLUGGABLE DATABASE BEGIN UPGRADE 'saas_app' FROM '1.0' TO '2.0';
ALTER TABLE orders ADD (status VARCHAR2(20)) SHARING = METADATA;
ALTER PLUGGABLE DATABASE END UPGRADE 'saas_app';

-- 5. 各 Application PDB 独立同步升级
ALTER SESSION SET CONTAINER = acme_app;
ALTER PLUGGABLE DATABASE APPLICATION 'saas_app' SYNC;
```

**Application Container 的杀手级用途**：

- 多租户 SaaS 应用代码统一管理（PL/SQL 包、视图、序列共享）。
- 每个 Application PDB 持有租户独有数据，但共享应用代码。
- 应用升级在 Application Root 中一次完成，所有 Application PDB SYNC 即可同步升级。

### 资源管理与 PDB 隔离

```sql
-- 1. 创建 CDB 级资源计划
BEGIN
    DBMS_RESOURCE_MANAGER.CREATE_PENDING_AREA();
    
    DBMS_RESOURCE_MANAGER.CREATE_CDB_PLAN(
        plan        => 'saas_plan',
        comment     => 'Multi-tenant SaaS plan');
    
    -- 给每个 PDB 分配 shares（相对权重）和 limits
    DBMS_RESOURCE_MANAGER.CREATE_CDB_PLAN_DIRECTIVE(
        plan        => 'saas_plan',
        pluggable_database => 'ACME_PDB',
        shares      => 100,                  -- 高权重
        utilization_limit => 90,             -- CPU 上限 90%
        parallel_server_limit => 50);
    
    DBMS_RESOURCE_MANAGER.CREATE_CDB_PLAN_DIRECTIVE(
        plan        => 'saas_plan',
        pluggable_database => 'GLOBEX_PDB',
        shares      => 50,
        utilization_limit => 50,
        parallel_server_limit => 25);
    
    DBMS_RESOURCE_MANAGER.SUBMIT_PENDING_AREA();
END;
/

-- 2. 启用计划
ALTER SYSTEM SET RESOURCE_MANAGER_PLAN = 'saas_plan' SCOPE = BOTH;

-- 3. 查看当前 PDB 资源消耗
SELECT con_id, pdb_name, cpu_consumed_time, io_requests, sessions_current
FROM cdb_resource_plan_directives
JOIN cdb_pdbs USING (con_id);
```

### CDB/PDB 的局限

1. **跨 PDB 查询性能**：`CONTAINERS()` 函数虽支持跨 PDB 扫描，但优化器不能跨 PDB 共享统计信息，复杂分析查询效率不高。
2. **License 成本**：Multitenant 选件按 CPU 单独计价（约 $17,500/CPU），中小客户难以承受。
3. **PDB 上限**：4096 PDB / CDB 在大型 SaaS 仍可能不够。
4. **元数据膨胀**：每个 PDB 一份完整数据字典，10000 PDB 时 catalog 占用可观。

## PostgreSQL RLS 多租户深度实践

`shared-schema + tenant_id + RLS` 是 PostgreSQL 在 SaaS 中最常见的多租户模式。本节展开生产实践。

### 完整的隔离方案

```sql
-- 1. 表设计
CREATE TABLE orders (
    tenant_id TEXT NOT NULL,
    id BIGSERIAL,
    customer_id BIGINT NOT NULL,
    amount NUMERIC(12, 2) NOT NULL,
    status TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (tenant_id, id)
) PARTITION BY HASH (tenant_id);

-- 创建 16 个 hash 分区（避免单分区过大）
CREATE TABLE orders_p0 PARTITION OF orders
    FOR VALUES WITH (modulus 16, remainder 0);
-- ... orders_p1 至 orders_p15

-- 2. 应用角色（最小权限）
CREATE ROLE app_role NOLOGIN;
GRANT USAGE ON SCHEMA public TO app_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON orders TO app_role;
GRANT USAGE ON SEQUENCE orders_id_seq TO app_role;

CREATE ROLE app_user LOGIN PASSWORD '...' IN ROLE app_role;

-- 3. 启用 RLS
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders FORCE ROW LEVEL SECURITY;     -- 所有者也受限

-- 4. 策略：只能看到自己的租户
CREATE POLICY tenant_select ON orders
    FOR SELECT
    TO app_role
    USING (tenant_id = current_setting('app.tenant_id', true));

CREATE POLICY tenant_insert ON orders
    FOR INSERT
    TO app_role
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true));

CREATE POLICY tenant_update ON orders
    FOR UPDATE
    TO app_role
    USING (tenant_id = current_setting('app.tenant_id', true))
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true));

CREATE POLICY tenant_delete ON orders
    FOR DELETE
    TO app_role
    USING (tenant_id = current_setting('app.tenant_id', true));

-- 5. 连接池中设置（PgBouncer 在 transaction-pooled 模式下）
-- application_code:
--   conn = pool.checkout()
--   conn.execute("SET LOCAL app.tenant_id = $1", tenant_id)
--   ...do work...
--   pool.return(conn)

-- 用 SET LOCAL 确保事务结束时上下文自动清除（避免连接泄漏污染）
```

### 避免侧信道泄露

```sql
-- 1. 唯一约束必须包含 tenant_id（避免错误信息暴露其他租户数据存在）
CREATE UNIQUE INDEX idx_users_email
    ON users (tenant_id, email);
-- 不要：CREATE UNIQUE INDEX idx_users_email ON users (email);

-- 2. 序列共享带来的预测攻击
-- 默认所有租户共享同一个 SERIAL 序列，attacker 可推断其他租户活动
-- 解决：用 UUID 主键 / 每租户独立序列 / hash 后的 ID

-- 3. EXPLAIN 暴露统计信息
-- 限制普通用户使用 EXPLAIN ANALYZE
REVOKE EXECUTE ON FUNCTION pg_stat_get_backend_pid FROM app_role;
REVOKE EXECUTE ON FUNCTION pg_stat_get_xact_blocks_fetched FROM app_role;
```

### 性能优化

```sql
-- 1. 所有索引以 tenant_id 开头
CREATE INDEX idx_orders_status ON orders (tenant_id, status);
CREATE INDEX idx_orders_created ON orders (tenant_id, created_at DESC);

-- 2. 分区裁剪
-- 配合 LIST/HASH 分区，PostgreSQL 11+ 支持 partition pruning
EXPLAIN (ANALYZE) SELECT * FROM orders WHERE tenant_id = 'acme';
-- 应该看到 "Subplans Removed: 15"，只扫描 1 个 hash 分区

-- 3. RLS 谓词的内联
-- PostgreSQL 优化器会把 RLS 的 USING 条件下推到查询计划
EXPLAIN (ANALYZE) SELECT * FROM orders WHERE status = 'paid';
-- 计划中应该看到 "Filter: ((tenant_id = current_setting('app.tenant_id', true)) AND (status = 'paid'::text))"

-- 4. 避免在 RLS USING 中使用相关子查询
-- 差：每行执行
CREATE POLICY bad ON orders USING (
    tenant_id IN (SELECT tenant_id FROM user_tenants WHERE user_id = current_user)
);
-- 好：用 STABLE 函数 + 缓存
CREATE FUNCTION get_my_tenants() RETURNS TEXT[] AS $$
    SELECT array_agg(tenant_id) FROM user_tenants WHERE user_id = current_user;
$$ LANGUAGE SQL STABLE;

CREATE POLICY good ON orders USING (tenant_id = ANY(get_my_tenants()));
```

### 跨租户管理操作

```sql
-- 管理任务（如统计、备份元数据）需要绕过 RLS
-- 方法 1: 用 SECURITY DEFINER 函数
CREATE FUNCTION admin_total_per_tenant()
RETURNS TABLE (tenant_id TEXT, total NUMERIC)
SECURITY DEFINER     -- 以函数所有者身份执行
LANGUAGE SQL AS $$
    SELECT tenant_id, SUM(amount) FROM orders GROUP BY tenant_id;
$$;

-- 方法 2: 使用拥有 BYPASSRLS 的角色
CREATE ROLE admin_role BYPASSRLS;        -- 显式绕过 RLS
GRANT admin_role TO admin_user;

-- 方法 3: 临时切换为 superuser（不推荐）
-- SET ROLE postgres;
```

## Citus Shard-by-Tenant 深度实践

Citus 把 `tenant_id` 升级为分布式分片键，是 PostgreSQL 生态中最成熟的多租户分布式方案。

### 分布式表与共置组

```sql
-- 1. 安装 Citus
CREATE EXTENSION citus;

-- 2. 添加 worker 节点（在 coordinator 上执行）
SELECT citus_add_node('worker-1.example.com', 5432);
SELECT citus_add_node('worker-2.example.com', 5432);
SELECT citus_add_node('worker-3.example.com', 5432);

-- 3. 设计租户共置的多张表
CREATE TABLE companies (
    id BIGSERIAL,
    tenant_id BIGINT NOT NULL,
    name TEXT,
    created_at TIMESTAMPTZ,
    PRIMARY KEY (tenant_id, id)
);

CREATE TABLE users (
    id BIGSERIAL,
    tenant_id BIGINT NOT NULL,
    email TEXT,
    PRIMARY KEY (tenant_id, id)
);

CREATE TABLE projects (
    id BIGSERIAL,
    tenant_id BIGINT NOT NULL,
    name TEXT,
    owner_id BIGINT,
    PRIMARY KEY (tenant_id, id),
    FOREIGN KEY (tenant_id, owner_id) REFERENCES users(tenant_id, id)
);

-- 4. 创建分布式表（按 tenant_id）
SELECT create_distributed_table('companies', 'tenant_id');
SELECT create_distributed_table('users',     'tenant_id', colocate_with => 'companies');
SELECT create_distributed_table('projects',  'tenant_id', colocate_with => 'companies');

-- colocate_with 确保相同 tenant_id 的所有数据在同一 shard 上
-- 这样租户内的 JOIN/外键/事务都本地化

-- 5. 引用表（小型公共表，每个 worker 完整复制）
CREATE TABLE plans (
    id INT PRIMARY KEY,
    name TEXT,
    monthly_price NUMERIC
);
SELECT create_reference_table('plans');
```

### 租户内事务（本地化执行）

```sql
-- 单租户事务在单个 worker 上执行（无 2PC 开销）
BEGIN;
    INSERT INTO companies (tenant_id, name) VALUES (42, 'Acme Corp');
    INSERT INTO users     (tenant_id, email) VALUES (42, 'admin@acme.com');
    INSERT INTO projects  (tenant_id, name, owner_id) VALUES (42, 'Project X', 1);
COMMIT;

-- Citus coordinator 把整个事务路由到 tenant_id=42 所在的 worker
-- worker 本地执行 + 本地 COMMIT，与单机 PG 同等性能
```

### 跨租户分析查询

```sql
-- 跨租户聚合：scatter-gather
SELECT tenant_id, SUM(monthly_revenue)
FROM (
    SELECT tenant_id, plan_id, COUNT(*) AS user_count
    FROM users GROUP BY tenant_id, plan_id
) u
JOIN plans p ON u.plan_id = p.id
GROUP BY tenant_id, monthly_revenue;

-- 执行计划：
-- 1. coordinator 将查询发到所有 worker
-- 2. 每个 worker 在本地分片上执行
-- 3. coordinator 合并结果

-- 跨租户 TOP-N
SELECT tenant_id, COUNT(*) AS user_count
FROM users
GROUP BY tenant_id
ORDER BY user_count DESC
LIMIT 10;
```

### 大租户隔离

```sql
-- "noisy neighbor" 问题：某个 hot tenant 把整个 shard 拖慢
-- 解决：把大租户单独迁移到一个独立 shard

-- 1. 查看当前 tenant 的 shard 分布
SELECT * FROM citus_shards WHERE tenant_id = 100;

-- 2. 把 tenant 100 隔离到新 shard（在线，无需停机）
SELECT isolate_tenant_to_new_shard('users', 100, 'CASCADE');
-- CASCADE 同时迁移所有共置表（companies、projects 等）

-- 3. 验证
SELECT shardid, COUNT(DISTINCT tenant_id) AS tenant_count
FROM users
GROUP BY shardid
ORDER BY tenant_count;
```

### Citus 的多租户最佳实践

1. **shard count**：默认 32，建议根据预期租户数和 worker 数选择（每个 worker 上 4-8 个 shard 较优）。
2. **distribution column**：永远用 `tenant_id`（BIGINT/UUID/TEXT），不要用主键 `id`。
3. **共置组**：所有租户表都用 `colocate_with` 加入同一个共置组。
4. **引用表**：小型字典表（country、currency、plan）用 reference table，大型租户表用 distributed table。
5. **JOIN 限制**：跨租户 JOIN 会触发 scatter；只在租户内 JOIN 才高性能。
6. **大租户隔离**：定期监控 shard 大小，对 hot tenant 用 `isolate_tenant_to_new_shard`。
7. **Schema 修改**：DDL 自动在所有 worker 上执行（Citus 透明转发），但大表 DDL 需要 `lock_timeout` 保护。

## 关键发现

### 1. 多租户没有"标准答案"

ISO/IEC 9075 从未定义多租户语义，物理实现完全由厂商决定。但事实上的方案高度收敛：

- **Database/Schema-per-Tenant**：基于命名空间隔离的传统方案。
- **Shared-schema with tenant_id + RLS**：最常见的 SaaS 模式。
- **Native CDB/PDB**：Oracle 独有的内核级实现。
- **Distributed shard-by-tenant**：Citus / Vitess / Aurora Limitless 的水平扩展方案。

### 2. Oracle CDB/PDB 仍是唯一内核级实现

自 12c (2013) 至今 11 年，Oracle Multitenant 是唯一在数据库内核中实现"租户"作为一等公民的方案：

- **12c (2013) GA**：CDB/PDB 雏形。
- **12.2 (2017)**：Application Container；non-CDB 弃用。
- **19c (2019)**：4096 PDB / CDB 上限；Refreshable PDB。
- **21c (2021)**：non-CDB 完全移除。

竞品如 SAP HANA MDC、OceanBase Tenant 形似神不似，仍是有限范围内的隔离机制。

### 3. PostgreSQL RLS 是开源 SaaS 的事实标准

`shared-schema + tenant_id + RLS` 在 PostgreSQL 9.5 (2016) 后成为开源 SaaS 多租户的事实标准方案，原因：

- **轻量**：单实例支持百万级租户。
- **灵活**：RLS 策略可任意复杂。
- **生态成熟**：连接池（PgBouncer）、ORM（Hibernate）、监控（pg_stat_statements）都对此友好。
- **审计可证**：所有跨租户访问都被 catalog 显式拒绝。

### 4. 分布式 shard-by-tenant 解决了"PG 单机 + 万级大租户"的极限问题

Citus（2010+ PG 扩展）、Vitess（2012+ MySQL 中间件）、Aurora Limitless（2024 GA）共享同一思路：**`tenant_id` 即分片键**：

- 同租户数据在单 worker → 本地 JOIN/事务零跨节点开销。
- 跨租户分析变 scatter-gather → 性能可控。
- 在线 resharding → 大租户隔离不停机。

这套思路已成为分布式 SaaS 后端的主流。

### 5. 资源隔离的趋势：从硬隔离到软配额

早期多租户（Oracle Resource Manager、Teradata Workload Management）依赖硬资源池（独立内存、独立进程）；2020s 起新一代引擎（TiDB Resource Control 7.1, 2023；StarRocks/Doris Resource Group；Snowflake Warehouse；BigQuery Slot Reservation）转向：

- **统一资源单位**：RU（TiDB）、Slot（BigQuery）、Credit（Snowflake）。
- **软配额**：每秒/每查询的限额，超出限流而非拒绝。
- **优先级调度**：高优租户抢占式获取资源。

这种"软多租户"对 SaaS 突发流量友好，是云原生数据库的共同方向。

### 6. 应用层路由 vs 数据库层路由

多租户的"路由"问题有两种解法：

- **数据库层路由**：Oracle CDB（`ALTER SESSION SET CONTAINER`）、Vitess VTGate、Citus coordinator、Aurora Limitless router。
- **应用层路由**：Database-per-tenant 模式下，应用根据 tenant 选择不同 connection string。

数据库层路由对应用透明但运维复杂；应用层路由实现简单但缺乏跨租户能力。云数据库（Aurora Limitless、Snowflake、BigQuery）正在把路由能力下沉到平台层，应用层只需要单一 endpoint。

### 7. 跨租户分析的根本困境

无论哪种模式，跨租户分析都是难题：

- **Database-per-tenant**：需要 federated query 或预先汇总到中央仓库（数据复制开销大）。
- **Schema-per-tenant**：UNION ALL N 个表，N 大时不可行。
- **Shared-schema**：最简单（一次 GROUP BY），但单表过大时存储引擎也吃力。
- **Sharded**：scatter-gather 性能 OK，但跨 shard JOIN 仍痛苦。

实践中，"跨租户分析"通常拆出独立的 OLAP 仓库（Snowflake、BigQuery、ClickHouse），通过 CDC 同步租户数据后做分析，本质是放弃在 OLTP 引擎中跨租户查询。

### 8. 多租户的安全三件套

无论物理模式如何，要做到真正"安全"的多租户隔离，需要三件套：

1. **强制租户上下文**：连接池中 `SET app.tenant_id`，且使用 `SET LOCAL` 防止泄漏。
2. **RLS 或 catalog 隔离**：数据库层强制注入，不依赖应用代码自觉。
3. **侧信道防御**：唯一约束包含 `tenant_id`、序列不共享、EXPLAIN 限制使用、错误信息脱敏。

漏掉任意一件都是事故隐患。

## 参考资料

- Oracle: [Multitenant Architecture](https://docs.oracle.com/en/database/oracle/oracle-database/19/multi/introduction-to-the-multitenant-architecture.html)
- Oracle: [Application Containers](https://docs.oracle.com/en/database/oracle/oracle-database/19/multi/overview-of-applications-in-an-application-container.html)
- PostgreSQL: [Row Security Policies](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)
- PostgreSQL: [Schemas](https://www.postgresql.org/docs/current/ddl-schemas.html)
- Citus: [Multi-Tenant Applications](https://docs.citusdata.com/en/stable/use_cases/multi_tenant.html)
- Citus: [Tenant Isolation](https://docs.citusdata.com/en/stable/develop/api_udf.html#isolate-tenant-to-new-shard)
- Vitess: [Multi-Tenancy](https://vitess.io/docs/concepts/keyspace/)
- AWS Aurora Limitless: [Limitless Database](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/limitless.html)
- CockroachDB: [Multi-Region Capabilities](https://www.cockroachlabs.com/docs/stable/multiregion-overview.html)
- TiDB: [Resource Control](https://docs.pingcap.com/tidb/stable/tidb-resource-control)
- OceanBase: [Tenants](https://en.oceanbase.com/docs/community-observer-en-10000000000829636)
- Snowflake: [Account Hierarchy](https://docs.snowflake.com/en/user-guide/organizations)
- BigQuery: [Resource Hierarchy](https://cloud.google.com/bigquery/docs/resource-hierarchy)
- SAP HANA: [Multitenant Database Containers](https://help.sap.com/docs/SAP_HANA_PLATFORM/6b94445c94ae495c83a19646e7c3fd56/7eca4675ae15452fa85e4934e21b9f5e.html)
- Microsoft Azure SQL Database: [Elastic Pools](https://learn.microsoft.com/en-us/azure/azure-sql/database/elastic-pool-overview)
- Curino, Carlo, et al. "Relational Cloud: A Database-as-a-Service for the Cloud" (2011), CIDR
- Chong, Frederick, et al. "Multi-Tenant Data Architecture" (2006), Microsoft Architecture Strategy Series
