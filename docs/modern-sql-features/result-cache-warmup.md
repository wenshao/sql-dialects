# 结果缓存与缓冲池预热 (Result Cache and Buffer Pool Warmup)

数据库重启后的"冷启动"是生产环境最昂贵的几个时刻之一——512GB 缓冲池从 0 命中率爬到 99% 可能需要数小时；同样，一个清空了结果缓存的数据仓库会让原本 50ms 返回的报表查询突然要 30 秒重算一遍。两类机制截然不同——结果缓存避免重算（不读底层数据），缓冲池预热避免冷启动 I/O（仍要读底层数据）——但它们的目的高度一致：**让"重启之后"和"重启之前"对用户而言几乎不可分辨**。

本文系统横向对比 45+ 数据库引擎在两条战线上的支持：

1. **结果缓存**：缓存查询的最终结果集（行数据）。命中时跳过整个执行管道，零 I/O、零 CPU、亚毫秒级延迟。
2. **缓冲池/页面缓存预热**：在重启后把热数据重新装入内存，把"空 buffer pool"快速恢复到接近重启前的状态。

> 相关阅读：
> - 结果缓存的全维度对比：`query-result-caching.md`
> - 缓冲池本身的设计、驱逐算法、内存预算：`buffer-pool-management.md`
> - 计划缓存（避免重复 parse / plan，但仍读数据）：`prepared-statement-cache.md`

## SQL 标准：完全不涉及

SQL:2023 及之前所有版本都没有定义任何结果缓存或缓冲池预热机制。这两个能力都属于物理执行/存储层的工程优化，由各引擎自行设计。结果就是：

- **关键字混乱**：`USE_CACHED_RESULT`（Snowflake）/ `RESULT_CACHE`（Oracle/SAP HANA）/ `useQueryCache`（BigQuery）/ `enable_result_cache_for_session`（Redshift）
- **生命周期混乱**：BigQuery/Snowflake 是 24h TTL；Oracle 是依赖对象失效；ClickHouse 默认 60s；Redshift 没有 TTL（LRU）
- **粒度混乱**：MySQL 缓存整个 SQL 文本；Oracle 缓存到对象级别；DB2 通过 MQT 间接实现
- **预热机制混乱**：MySQL 用文本格式 dump 文件；PostgreSQL 用二进制 `autoprewarm.blocks`；Oracle 用 KEEP pool；SAP HANA 用 PRELOAD

本文不是讨论"哪个标准更优"，而是横向梳理工程实现上的差异。

## 冷启动 vs 暖启动：性能差异有多大？

```
512GB InnoDB 缓冲池 OLTP 负载实测 (内部基准):

  冷启动 (无 dump/load):
    重启完成 → 业务 QPS 立即下降 80%
    平均响应时间从 5ms 飙升到 600ms
    99 分位响应从 50ms 飙到 2.5s
    需要约 2 小时, 命中率才能爬回 99%

  使用 dump/load (innodb_buffer_pool_dump_pct = 25):
    重启完成 → 后台 5 分钟内装入 128GB 热页
    业务 QPS 5 分钟后恢复到正常 95%
    平均响应时间峰值约 80ms, 5 分钟内回落
    20 分钟内命中率回到 99%

  数量级差异: 冷启动 2 小时 vs 暖启动 20 分钟 → 6x 加速
```

```
Snowflake / BigQuery 等数仓的结果缓存:

  无 result cache:
    每次执行复杂报表查询都重新扫描 → 30-60s + 计算成本
    1000 次重复查询 = 30000-60000s + 1000 倍计算成本

  有 result cache (24h TTL):
    首次执行 30s, 后续 999 次 < 100ms 直接返回
    总耗时降为 30s + 100s = 130s
    总成本降至原来的 0.1% (Snowflake 不计费 cached 查询)
```

## 支持矩阵 1：服务器端结果缓存

完整对比请参见 `query-result-caching.md`，本文给出与"预热"主题相关的快速速查表。

| 引擎 | 是否支持 | 默认开启 | TTL | 引入版本 |
|------|---------|---------|-----|---------|
| PostgreSQL | -- | -- | -- | 不支持 |
| MySQL | 历史有，8.0.3 移除 | 5.x 默认关闭 | LRU | 4.0 引入 |
| MariaDB | 是（不推荐） | 否 | LRU | 继承 |
| SQLite | -- | -- | -- | 无 |
| Oracle | 是 | MANUAL | 依赖对象 | 11gR1 (2007) |
| SQL Server | -- | -- | -- | 无 |
| DB2 | 间接（MQT） | 否 | -- | 9.7+ |
| Snowflake | 是 | 是 | 24h（可续）| GA |
| BigQuery | 是 | 是 | 24h | GA |
| Redshift | 是 | 是 | 无 TTL（LRU） | GA |
| DuckDB | -- | -- | -- | 设计上无需 |
| ClickHouse | 是 | 否 | 60s | 23.4 (2023-04) |
| Trino | -- | -- | -- | 无 |
| Presto | -- | -- | -- | 无 |
| Spark SQL | 部分（CACHE TABLE）| 否 | 手动 | -- |
| Hive | 是 (LLAP) | 否 | 配置 | 2.3+ |
| Flink SQL | -- | -- | -- | 不适用（流）|
| Databricks | 是 | 是（SQL Warehouse）| 24h | GA |
| Teradata | 是 | 否 | LRU | V2R6+ |
| Greenplum | -- | -- | -- | 继承 PG |
| CockroachDB | -- | -- | -- | 无 |
| TiDB | -- | -- | -- | 仅计划缓存 |
| OceanBase | 是 | 否 | 依赖对象 | 3.x |
| YugabyteDB | -- | -- | -- | 无 |
| SingleStore | 是 | 是（S2MS）| 配置 | 7.5+ |
| Vertica | -- | -- | -- | depot 不同概念 |
| Impala | -- | -- | -- | 无 |
| StarRocks | 是 | 否 | 配置 | 2.5+ |
| Doris | 是 | 否 | 配置 | 1.2+ |
| MonetDB | -- | -- | -- | 无 |
| CrateDB | -- | -- | -- | 无 |
| TimescaleDB | -- | -- | -- | 继承 PG |
| QuestDB | -- | -- | -- | 无 |
| Exasol | 是 | 是 | 版本失效 | GA |
| SAP HANA | 是 | 否 | Hint 内 | 2.0 SPS04 |
| Informix | -- | -- | -- | 仅 SQL 缓存 |
| Firebird | -- | -- | -- | 无 |
| H2 | -- | -- | -- | 无 |
| HSQLDB | -- | -- | -- | 无 |
| Derby | -- | -- | -- | 无 |
| Amazon Athena | 是 | 否 (v3) | MaxAge | 2022+ |
| Azure Synapse | 是 | 否 | LRU | GA |
| Google Spanner | -- | -- | -- | 无 |
| Materialize | 物化（增量）| 是 | 持续 | 核心能力 |
| RisingWave | 物化（增量）| 是 | 持续 | 核心能力 |
| InfluxDB (SQL) | -- | -- | -- | 无 |
| DatabendDB | 是 | 否 | 配置 | 1.x |
| Yellowbrick | 是 | 否 | LRU | GA |
| Firebolt | 是 | 是 | LRU | GA |
| Alibaba PolarDB | 是 | 否 | 配置 | GA |

> 统计：明确支持 server-side result cache 的引擎约 19 个；明确不支持的约 22 个。

## 支持矩阵 2：查询级结果缓存提示 / Hint

不同引擎让用户在单条查询上强制启用 / 禁用结果缓存的方式。

| 引擎 | 启用提示 | 禁用提示 | 备注 |
|------|---------|---------|------|
| Oracle | `/*+ RESULT_CACHE */` | `/*+ NO_RESULT_CACHE */` | 标准 hint 写法 |
| SAP HANA | `WITH HINT(RESULT_CACHE_NON_TRANSACTIONAL)` 或 `RESULT_CACHE_TRANSACTIONAL` | `WITH HINT(NO_RESULT_CACHE)` | 还可指定 TTL |
| Snowflake | -- | `ALTER SESSION SET USE_CACHED_RESULT=FALSE` | 仅会话级 |
| BigQuery | `useQueryCache=true` (job) | `useQueryCache=false` | 作业配置 |
| Redshift | `SET enable_result_cache_for_session=on` | `SET enable_result_cache_for_session=off` | 会话级 |
| ClickHouse | `SETTINGS use_query_cache=1` | `SETTINGS use_query_cache=0` | 查询级 SETTINGS |
| Databricks | -- | `SET use_cached_result=false` | 会话级 |
| Athena | `ResultReuseConfiguration` | `ResultReuseConfiguration.Enabled=false` | API 参数 |
| MySQL（历史）| `SQL_CACHE` | `SQL_NO_CACHE` | 8.0 已删 |
| MariaDB | `SQL_CACHE` | `SQL_NO_CACHE` | 兼容 |
| Hive LLAP | -- | `SET hive.query.results.cache.enabled=false` | 会话 |
| OceanBase | -- | `SET _enable_result_cache=0` | 会话/全局 |
| StarRocks | -- | `SET enable_query_cache=false` | 会话 |
| Doris | -- | `SET cache_enable_sql_mode=false` | 会话 |
| Azure Synapse | `ALTER DATABASE ... SET RESULT_SET_CACHING ON` | `OFF` | 数据库级 |

**只有 Oracle 和 SAP HANA 把"启用结果缓存"做成了行内 hint**。其他引擎要么是会话/数据库级开关，要么是 API 参数。这种差异源于设计哲学：Oracle 鼓励 DBA 按查询粒度精细控制，而 Snowflake/BigQuery 等"零运维"系统把缓存当成默认行为。

## 支持矩阵 3：缓冲池 dump/load on restart

| 引擎 | 重启时自动 dump | 自动 load | 引入版本 | 文件格式 |
|------|--------------|----------|---------|---------|
| PostgreSQL | -- | -- | -- | 默认无（需扩展） |
| PostgreSQL + pg_prewarm 11+ | 周期性 | 自动 | 11 (2018) | binary `autoprewarm.blocks` |
| MySQL | `innodb_buffer_pool_dump_at_shutdown` | `innodb_buffer_pool_load_at_startup` | 5.6 (2013) | 文本 `ib_buffer_pool` |
| MariaDB | 同 MySQL | 同 MySQL | 10.0+ | 文本 |
| Percona Server | 同 MySQL | 同 MySQL | 5.5+ (XtraDB Lru Dump) | 文本 |
| Oracle | -- | -- | -- | KEEP pool 方式 |
| SQL Server | -- | -- | -- | 无内置 |
| DB2 | -- | -- | -- | 无内置 |
| SQLite | -- | -- | -- | 不需要（OS cache）|
| Snowflake | 托管 | 托管 | -- | 不可见 |
| BigQuery | 托管 | 托管 | -- | 不可见 |
| Redshift | 托管 | 托管 | -- | 不可见 |
| DuckDB | -- | -- | -- | 进程退出即清 |
| ClickHouse | -- | -- | -- | 仅 mark cache 持久 |
| Trino | -- | -- | -- | 无（split scheduler）|
| Spark SQL | -- | -- | -- | CACHE TABLE 显式 |
| Hive on HDFS | -- | -- | -- | 依赖 HDFS cache |
| Databricks | Delta Cache 持久化 | 自动 | -- | SSD 二进制 |
| Teradata | -- | -- | -- | FSG cache 重建 |
| Greenplum | -- | -- | -- | 继承 PG |
| CockroachDB | -- | -- | -- | 无 |
| TiDB (TiKV) | -- | -- | -- | block cache 重建 |
| OceanBase | -- | -- | -- | 无 |
| YugabyteDB | -- | -- | -- | 无 |
| SingleStore | blob cache 文件持久 | 自动 | GA | SSD 二进制 |
| Vertica | depot SSD cache | 自动 | GA | 二进制 |
| Impala | -- | -- | -- | HDFS Centralized Cache |
| StarRocks | -- | -- | -- | 无 |
| Doris | -- | -- | -- | 无 |
| MonetDB | mmap 自然持久 | 自然 | -- | 文件系统 |
| Exasol | 自动 warm-up | 自动 | -- | 启动时自动 |
| SAP HANA | column 元数据持久 | LOAD INTO MEMORY | 长期 | 列存元数据 |
| Informix | -- | -- | -- | 无 |
| Firebird | -- | -- | -- | 无 |
| H2 | -- | -- | -- | 无 |
| HSQLDB | -- | -- | -- | 无 |
| Derby | -- | -- | -- | 无 |
| Athena | 托管 | 托管 | -- | 不可见 |
| Azure Synapse | 托管 | 托管 | -- | 不可见 |
| Spanner | 托管 | 托管 | -- | 不可见 |
| Materialize | 持久 arrangement | 自动 | GA | 增量状态 |
| RisingWave | 持久 hummock state | 自动 | GA | LSM state |
| InfluxDB (IOx) | TSM / Parquet 持久 | 重建 cache | -- | -- |
| DatabendDB | object storage cache | 重建 | -- | -- |
| Yellowbrick | blade cache | 自动 | GA | -- |
| Firebolt | F3 SSD cache | 自动 | GA | SSD |
| Alibaba PolarDB | 同 MySQL | 同 MySQL | 5.6+ | 文本 |

> 统计：明确提供"重启时自动 dump/load 缓冲池"机制的开源/商业引擎只有 **MySQL + MariaDB + Percona** 一脉（基于 InnoDB），以及 **PostgreSQL pg_prewarm autoprewarm** 自 PG 11 起。其他引擎要么是托管云服务（用户看不见）、要么不提供（依赖业务自己用 `SELECT *` 扫描预热）。

## 支持矩阵 4：预热脚本 / 命令支持

不少引擎不提供"自动重启预热"，但提供了"用户主动触发预热"的语法。

| 引擎 | 预热命令 | 粒度 | 备注 |
|------|---------|------|------|
| PostgreSQL | `SELECT pg_prewarm('table')` | 表/索引 | buffer/read/prefetch 三模式 |
| PostgreSQL 11+ | `pg_prewarm.autoprewarm` | 后台周期 | 重启自动恢复 |
| MySQL | `SET GLOBAL innodb_buffer_pool_dump_now=ON` | 全局 | 手动 dump |
| MySQL | `SET GLOBAL innodb_buffer_pool_load_now=ON` | 全局 | 手动 load |
| Oracle | `ALTER TABLE t CACHE` + `SELECT * FROM t` | 表 | 配合 KEEP pool |
| Oracle | `DBMS_SHARED_POOL.MARKHOT` | 内部对象 | -- |
| SQL Server | 无官方；`SELECT *` 扫描 | -- | 通常用 BPE |
| SQL Server | `DBCC BUFFERPOOL` | 诊断 | 不是预热 |
| DB2 | `BLOCK BASED BUFFER POOLS` + `db2pd -buffer` | 表空间 | 脚本化 |
| ClickHouse | 无官方预热；`OPTIMIZE TABLE` 扫描 | 表 | 间接 |
| ClickHouse | `SYSTEM RELOAD DICTIONARY` | 字典 | 字典级 |
| Spark SQL | `CACHE TABLE t` / `cache()` | 表/DataFrame | RDD 级 |
| Databricks | `CACHE SELECT * FROM t` | 列子集 | Delta Cache |
| Hive | 无；`SELECT *` 扫描 | -- | -- |
| Impala | `ALTER TABLE t SET CACHED IN 'pool'` | 表/分区 | HDFS 缓存 |
| Trino | 无 | -- | 无缓冲池 |
| SAP HANA | `LOAD t INTO MEMORY` | 列 | 列存预热 |
| SAP HANA | `ALTER TABLE t PRELOAD ALL` | 表 | -- |
| SingleStore | `OPTIMIZE TABLE t WARM BLOB CACHE` | 表 | columnstore |
| Snowflake | 无（warehouse 预热）| -- | 启动 warehouse 触发 |
| BigQuery | 无 | -- | 托管 |
| Redshift | `VACUUM` 间接 | 表 | -- |
| Vertica | `SELECT * FROM ...` | 表 | depot 加载 |
| TiDB | `LOAD STATS` + 自动热点 | 统计/数据 | 自动 |
| OceanBase | `ALTER SYSTEM ... WARM UP` | -- | 内部 |

## 各引擎深度剖析

### PostgreSQL：pg_prewarm + autoprewarm

PostgreSQL **核心团队明确拒绝结果缓存**，但对缓冲池预热提供了完整支持。预热的单一权威工具是 `pg_prewarm` 扩展（自 9.4 起）。

```sql
-- 安装扩展
CREATE EXTENSION pg_prewarm;

-- 三种预热模式
SELECT pg_prewarm('orders', 'buffer');     -- 进 shared_buffers
SELECT pg_prewarm('orders', 'read');       -- 只进 OS cache (read())
SELECT pg_prewarm('orders', 'prefetch');   -- posix_fadvise 仅预取
```

`pg_prewarm` 三种模式的语义对比：

| 模式 | 实际操作 | 进入位置 | 是否触发驱逐 |
|------|---------|---------|-------------|
| buffer | 逐页 ReadBuffer() | shared_buffers + OS cache | 是 |
| read | read() 逐块读 | 仅 OS cache | 否 |
| prefetch | posix_fadvise(POSIX_FADV_WILLNEED) | OS 异步预取 | 否 |

**PG 11 引入的 autoprewarm**（2018 年）解决了"重启即冷启动"痛点：

```ini
# postgresql.conf
shared_preload_libraries = 'pg_prewarm'
pg_prewarm.autoprewarm = on
pg_prewarm.autoprewarm_interval = 300s     # 默认 5 分钟
```

工作流程：

```
启动期:
  1. postmaster 启动后, 启动 autoprewarm worker
  2. worker 读取 $PGDATA/autoprewarm.blocks 文件
  3. 文件格式: <db_oid>,<tablespace>,<rel>,<fork>,<block_no>
  4. 按 (db_oid, tablespace, rel, fork, block) 排序 → 顺序 I/O
  5. 调用 ReadBuffer() 装入 shared_buffers, 直到 buffer 满

运行期:
  1. 每隔 autoprewarm_interval (默认 300s) 触发一次
  2. 扫描 shared_buffers, 把当前 buffer 列表写到临时文件
  3. 原子 rename 到 autoprewarm.blocks (避免半写)

关机期:
  1. SIGTERM 时立即触发一次 dump
  2. 等 worker 完成后再退出
```

**为什么排序后再装入是"顺序 I/O"？** 同一表的相邻块在数据文件中物理相邻，排序后变成对单个文件的顺序读，HDD 上从随机 I/O 转为顺序 I/O 性能提升 10-50 倍，SSD 上也能利用 NVMe 队列的批量提交能力。

```sql
-- 查看当前 shared_buffers 装载情况
CREATE EXTENSION pg_buffercache;

SELECT c.relname,
       count(*) AS buffers,
       pg_size_pretty(count(*) * 8192) AS cached_size,
       round(100.0 * count(*) / (SELECT setting::int FROM pg_settings WHERE name='shared_buffers'), 2) AS pct_of_buffer
FROM pg_buffercache b
JOIN pg_class c ON b.relfilenode = pg_relation_filenode(c.oid)
WHERE c.relkind IN ('r', 'i')
GROUP BY c.relname
ORDER BY 2 DESC
LIMIT 20;

-- 命中率
SELECT datname,
       blks_hit,
       blks_read,
       round(100.0 * blks_hit / nullif(blks_hit + blks_read, 0), 2) AS hit_pct
FROM pg_stat_database;
```

**和结果缓存的对比**：PG 没有 server-side result cache。社区最近的努力包括 PG 14+ 的 Memoize 节点（仅在 nested loop 内部对参数化 inner subquery 缓存）和 PG 17 的 explicit incremental sort 等，但这些都不是"跨查询的结果缓存"。如果需要 PG 上的 result cache，唯一现实路径是应用层或代理层（pgpool, pgbouncer 不支持，但有第三方扩展 pg_qualstats、ProxySQL for PG）。

### MySQL：InnoDB Buffer Pool dump/load

MySQL 5.6（2013 年发布）引入的 buffer pool dump/load 是这个领域的开创性工作之一。

**配置**：

```ini
# my.cnf
[mysqld]
innodb_buffer_pool_dump_at_shutdown = ON
innodb_buffer_pool_load_at_startup  = ON
innodb_buffer_pool_dump_pct         = 25     # 只 dump LRU 头 25%
innodb_buffer_pool_filename         = ib_buffer_pool
innodb_buffer_pool_load_abort       = OFF
```

**dump 文件格式**：

```
# $datadir/ib_buffer_pool (纯文本)
# 每行: <space_id>,<page_no>
0,12
0,14
4,1523
4,1524
...
```

**关机/启动流程**：

```
关机时 (innodb_buffer_pool_dump_at_shutdown=ON):
  1. 遍历所有 buffer_pool_instances
  2. 按 LRU young → old 顺序扫描每个实例
  3. 取前 dump_pct 比例的 (space_id, page_no)
  4. 合并去重后写入 ib_buffer_pool 文件
  
启动时 (innodb_buffer_pool_load_at_startup=ON):
  1. InnoDB 初始化完成后, 启动后台 load 线程
  2. 读 ib_buffer_pool, 按 (space_id, page_no) 排序
  3. 排序后变为顺序 I/O, 利用预读
  4. 多线程并发读入 buffer_pool_instances
  5. 前台服务立即可用 (load 不阻塞)
```

**手动触发**（运行时）：

```sql
-- 立即 dump (不等关机)
SET GLOBAL innodb_buffer_pool_dump_now = ON;

-- 立即 load (不等启动)
SET GLOBAL innodb_buffer_pool_load_now = ON;

-- 中止正在进行的 load
SET GLOBAL innodb_buffer_pool_load_abort = ON;

-- 检查进度
SHOW STATUS LIKE 'Innodb_buffer_pool_dump_status';
-- → "Buffer pool(s) dump completed at 240429 18:31:42"

SHOW STATUS LIKE 'Innodb_buffer_pool_load_status';
-- → "Loaded 32400/32400 pages."
```

**dump_pct 的工程权衡**：

```
dump_pct = 100 (全部 dump):
  ✓ 重启后命中率立即 ~100%
  ✗ dump 文件大 (200MB on 500GB pool)
  ✗ load 时间长 (5-15 分钟)
  
dump_pct = 25 (默认):
  ✓ dump 文件小 (50MB)
  ✓ load 时间短 (1-3 分钟)
  ✓ 25% 最热的页通常覆盖 80%+ 命中
  ✗ 重启后前几分钟需要逐步加载剩余热页

dump_pct = 5 (只 dump 最热):
  ✓ 极快预热
  ✗ 命中率上升曲线较缓
```

**MySQL 不支持结果缓存了吗？** MySQL 8.0.3（2017 年）正式删除了 query cache 功能。原因：

1. **写多读少负载下负收益**：任何 INSERT/UPDATE/DELETE 触发整表所有 cached 查询失效，开销巨大。
2. **全局 mutex 瓶颈**：早期 query cache 是单一 mutex 保护，32 核以上机器成为瓶颈。
3. **缓存键太死板**：`SELECT * FROM t` 与 `select * from t`（小写）被视为不同查询，浪费内存。
4. **大结果集污染缓存**：单个 100MB 结果可能挤掉数千个小结果。

MariaDB 选择保留 query cache，但官方文档自 10.4（2019）起标注**已不推荐**，鼓励用户改用应用层缓存或物化视图。

### Oracle Result Cache 深度剖析

Oracle 在 11gR1（2007 年）引入了 Result Cache，是商业数据库中最早把"结果缓存"做成一等公民的产品。

**两类粒度**：

```
1. SQL Query Result Cache: 缓存 SELECT 整个结果集
2. PL/SQL Function Result Cache: 缓存 PL/SQL 函数返回值
```

**配置参数**：

```sql
-- 全局开关
ALTER SYSTEM SET RESULT_CACHE_MAX_SIZE = 256M;   -- 总大小 (默认 0.5% SGA)
ALTER SYSTEM SET RESULT_CACHE_MAX_RESULT = 5;    -- 单个结果最大占比 % (默认 5%)
ALTER SYSTEM SET RESULT_CACHE_MODE = MANUAL;     -- MANUAL / FORCE
ALTER SYSTEM SET RESULT_CACHE_REMOTE_EXPIRATION = 0; -- 远程对象 TTL (分钟)

-- 三种模式:
-- MANUAL: 默认, 仅当查询带 /*+ RESULT_CACHE */ hint 时才缓存
-- FORCE:  所有查询都缓存 (除非带 NO_RESULT_CACHE hint)
-- AUTO (历史模式, 已废弃)
```

**RESULT_CACHE Hint 用法**：

```sql
-- 查询级启用
SELECT /*+ RESULT_CACHE */
       department_id,
       AVG(salary) AS avg_salary,
       COUNT(*) AS count
FROM employees
GROUP BY department_id;

-- 第二次执行同样 SQL → 直接从 result cache 返回
-- 即使数据改变, Oracle 通过 dependency tracking 自动失效

-- 显式禁用
SELECT /*+ NO_RESULT_CACHE */ * FROM events WHERE created_at > SYSDATE - 1;

-- 视图级启用 (所有引用此视图的查询都被缓存)
CREATE OR REPLACE VIEW v_dept_summary
RESULT_CACHE (MODE FORCE) AS
SELECT department_id, AVG(salary) FROM employees GROUP BY department_id;

-- 表级注解 (类似关键字)
ALTER TABLE small_lookup_table RESULT_CACHE (MODE FORCE);
```

**PL/SQL Function Result Cache**：

```sql
CREATE OR REPLACE FUNCTION get_dept_count(p_dept_id NUMBER)
RETURN NUMBER
RESULT_CACHE
RELIES_ON (employees)        -- 显式声明依赖关系 (12c 起非必需)
IS
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM employees WHERE department_id = p_dept_id;
    RETURN v_count;
END;
/

-- 调用: 第一次执行查询并缓存; 之后相同 p_dept_id 直接返回
SELECT get_dept_count(10) FROM dual;  -- 计算并缓存
SELECT get_dept_count(10) FROM dual;  -- 命中 cache
```

**缓存键构成**：

```
key = hash(
    canonicalized SQL text,
    bind variable values,
    NLS settings (语言/字符集),
    optimizer parameters,
    user / role context
)
```

注意：Oracle 的缓存键考虑了 `NLS_DATE_FORMAT` 等会话参数——同一 SQL 在两个不同 NLS 设置的会话下会产生两份独立缓存。

**依赖跟踪与自动失效**：

```
RESULT_CACHE entry 维护:
  - SQL text hash
  - bind variables
  - 依赖对象列表 (table OID + DDL_TIMESTAMP)

任何依赖对象的变更触发失效:
  - DML on table → 失效引用该表的所有 cached results
  - DDL on table → 失效
  - GRANT / REVOKE → 失效

跨 RAC 节点的失效通过 Cache Fusion 协议传播
```

**监控视图**：

```sql
-- 缓存使用情况
SELECT * FROM V$RESULT_CACHE_STATISTICS;

-- 缓存条目
SELECT id, type, status, name, namespace,
       creation_timestamp, block_count
FROM V$RESULT_CACHE_OBJECTS
WHERE status = 'Published'
ORDER BY creation_timestamp DESC;

-- 内存使用 (按对象)
SELECT object_name, sum(block_count) blocks, count(*) entries
FROM V$RESULT_CACHE_DEPENDENCY d
JOIN V$RESULT_CACHE_OBJECTS o ON d.result_id = o.id
GROUP BY object_name;

-- 强制清空
EXEC DBMS_RESULT_CACHE.FLUSH;
```

**Oracle Client Result Cache (OCI)**：

Oracle 11gR1 同时引入了**客户端结果缓存**——OCI 驱动在客户端进程内存中缓存结果，服务器通过 RPI 推送失效消息。

```sql
-- 服务端启用客户端缓存
ALTER SYSTEM SET CLIENT_RESULT_CACHE_SIZE = 32M;
ALTER SYSTEM SET CLIENT_RESULT_CACHE_LAG = 3000;  -- ms, 失效延迟容忍
```

**这是行业里少见的"客户端 result cache 一等公民"实现**——Oracle OCI 之外几乎没有数据库提供同等能力。

### MySQL Buffer Pool Dump/Load 深度剖析

承接前文，进一步看几个关键工程细节：

**为什么 dump 不保存页内容？**

```
方案 A (保存页内容):
  ✓ 启动后立即可用, 跳过磁盘 I/O
  ✗ dump 文件巨大 (= buffer pool 全量)
  ✗ 与磁盘数据不一致风险 (重启间隙若有 crash recovery 写入新数据)
  ✗ 必须重放 redo 才能保证一致性

方案 B (只保存 page 标识):
  ✓ dump 文件极小 (200MB on 500GB pool)
  ✓ 总是从最新磁盘读, 无一致性问题
  ✗ 启动时仍需读盘 (但顺序 I/O 已大幅加速)

MySQL 选择 B。理由是 SSD/NVMe 时代, 顺序读 500GB 仅需几分钟.
```

**load 顺序 I/O 优化**：

```
原始 LRU 顺序 (空间局部性差):
  (space=4, page=15234)
  (space=0, page=78)
  (space=4, page=92)
  (space=12, page=2003)
  ...
  → 随机 I/O, HDD 上 ~150 IOPS, 装入 100GB 需要数小时

排序后 (空间局部性优):
  (space=0, page=78)
  (space=4, page=15)
  (space=4, page=92)
  (space=4, page=15234)
  (space=12, page=2003)
  ...
  → 单文件内顺序读, HDD 上 ~500 MB/s, 100GB 仅需 4 分钟
```

**多实例并发**：

```
innodb_buffer_pool_instances = 8:
  → load 启动 8 个并发线程, 各负责一个 instance
  → 总吞吐近线性扩展, 16GB 实例 5 分钟装完
```

**与 PostgreSQL autoprewarm 的对比**：

| 维度 | PG autoprewarm | MySQL dump/load |
|------|---------------|-----------------|
| 触发点 | 周期 (300s) + 关机 | 关机 + 手动 |
| 周期持久化 | 是 (每 5 分钟) | 否 (仅关机) |
| 存储格式 | binary (5 字段) | 文本 (2 字段) |
| 装入方式 | 前台单线程 | 后台多线程 |
| 装入比例 | 全部 | 可配 (dump_pct) |
| 默认启用 | 否 (需 shared_preload_libraries) | 是 (8.0+) |
| 中止支持 | -- | 是 (load_abort) |
| 适用 | 单机/小集群 | 单机/大内存 |

**MySQL 8.0 默认 dump/load 启用，PG 默认不启用**——这反映了两家社区的不同优先级：MySQL 把 dump/load 当成"运维标配"，PG 则当成"可选扩展"。

### SQL Server：无内置预热，依赖 BPE

SQL Server 出人意料地**没有官方的缓冲池 dump/load 机制**。社区常用的方案：

**方案 1：手动 SELECT 扫描**

```sql
-- 启动后扫描热表
SELECT COUNT(*) FROM dbo.Orders WITH (NOLOCK);
SELECT COUNT(*) FROM dbo.Customers WITH (NOLOCK);
-- 强制把表的所有页读入 buffer pool
```

**方案 2：DBCC BUFFERPOOL（只读诊断）**

```sql
-- 查看 buffer pool 状态 (诊断用, 不预热)
DBCC BUFFERPOOL;

-- 推荐: 用 DMV 替代
SELECT 
    DB_NAME(database_id) AS db_name,
    COUNT(*) AS pages_in_buffer,
    COUNT(*) * 8 / 1024 AS MB_in_buffer
FROM sys.dm_os_buffer_descriptors
GROUP BY database_id
ORDER BY pages_in_buffer DESC;

-- 单表的 buffer 占用
SELECT 
    OBJECT_NAME(p.object_id) AS table_name,
    COUNT(*) AS pages,
    SUM(b.row_count) AS total_rows
FROM sys.dm_os_buffer_descriptors b
JOIN sys.allocation_units a ON b.allocation_unit_id = a.allocation_unit_id
JOIN sys.partitions p ON a.container_id = p.partition_id
WHERE b.database_id = DB_ID()
GROUP BY p.object_id
ORDER BY pages DESC;
```

**方案 3：Buffer Pool Extension（2014+）**

BPE 不是预热机制，但在重启场景下有类似效果——它把"温页"持久化到 SSD：

```sql
-- 启用 BPE
ALTER SERVER CONFIGURATION
SET BUFFER POOL EXTENSION ON
    (FILENAME = 'D:\SSD\bpe.bpe', SIZE = 128 GB);

-- 重启后 BPE 文件保留, 内存中冷页恢复时若已在 BPE 则跳过磁盘 I/O
-- 但 SQL Server 重启时 BPE 内容**仍会被清空**, 不能跨重启复用
```

**tempdb 的特殊性**：SQL Server 的 tempdb 在每次启动时被重建，不可预热。但 tempdb 的 auto-grow 机制需要单独调优——`tempdb_growth` 设置过小会导致频繁扩展，影响启动期性能。

```sql
-- tempdb 文件配置
ALTER DATABASE tempdb 
MODIFY FILE (NAME = tempdev, SIZE = 8GB, FILEGROWTH = 1GB);
```

### Snowflake：24 小时自动结果缓存

Snowflake 把结果缓存做成了云数仓产品的招牌特性：

```sql
-- 默认启用, 无需开启
SELECT order_id, customer_id, amount
FROM orders
WHERE order_date >= '2024-01-01';

-- 第二次执行: 命中 cache, 跳过整个 warehouse, 立即返回
-- (即使 warehouse 已挂起也会返回)

-- 禁用 (会话级)
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

-- 检查是否命中
SELECT *, query_id FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_text LIKE '%orders%'
ORDER BY start_time DESC
LIMIT 10;

-- query_history 中的 EXECUTION_STATUS = 'SUCCESS' 且 QUERY_TYPE = 'SELECT'
-- BYTES_SCANNED = 0 → 命中 result cache
```

**Snowflake 三层缓存架构**：

| 层 | 存储位置 | 内容 | 生命周期 |
|----|---------|------|---------|
| Result Cache | Cloud Services 层 | SQL 结果集 | 24h (访问续期), 31 天硬上限 |
| Local Disk Cache | Warehouse SSD | micro-partition 文件 | warehouse 暂停后清空 |
| Remote Storage | S3/Azure/GCS | micro-partition 持久 | 永久 |

**Result Cache 的关键属性**：

- 跨用户复用：只要权限相同，A 用户的查询结果 B 用户也能命中
- 元数据版本失效：底层表的任何 micro-partition 变化即失效
- 角色敏感：`USE ROLE` 切换后缓存键变化
- 不计算费用：命中 cache 的查询完全不消耗 credit

**24 小时 + 续期 + 31 天硬上限**：

```
T = 0  执行查询 A → 缓存写入, TTL = 24h
T = 23h 再次执行 A → 命中 cache, TTL 重置为 24h (相对当前时间)
T = 24h+ε 不访问 → cache 过期清除
T = 任意 数据变化 → 立即失效

最长可保留 31 天 (即使持续访问也会被强制清除, 防止用户依赖陈旧数据)
```

### BigQuery：默认 24 小时 + 字段级失效

BigQuery 的设计与 Snowflake 类似但有几个独特之处：

```sql
-- 默认启用 result cache (job config 中 useQueryCache=true)
SELECT customer_id, COUNT(*) AS order_count
FROM `project.dataset.orders`
GROUP BY customer_id;

-- 结果默认存储在临时表 (anonymous dataset), 24 小时后自动删除
```

**BigQuery 命中条件**：

- 查询字符串字节级一致（whitespace 敏感）
- 引用的表自上次结果之后未变化
- 查询不引用非确定性函数（`CURRENT_TIMESTAMP()`, `RAND()`, `SESSION_USER()` 等）
- 查询不使用 `_TABLE_SUFFIX` 通配符
- 用户对所有引用对象有读权限

**Cache 不命中的常见陷阱**：

```sql
-- ❌ 永不命中 cache (含非确定性函数)
SELECT *, CURRENT_TIMESTAMP() AS query_time FROM orders LIMIT 10;

-- ❌ 永不命中 cache (通配符引用)
SELECT * FROM `project.dataset.events_*` WHERE _TABLE_SUFFIX = '20240101';

-- ❌ 永不命中 cache (流式插入表)
-- 表正在被 streaming insert 写入时, cache 自动禁用

-- ✓ 命中 cache
SELECT customer_id, SUM(amount) FROM orders GROUP BY customer_id;
```

**关闭 cache**：

```python
# Python client
job_config = bigquery.QueryJobConfig(use_query_cache=False)
client.query(sql, job_config=job_config)
```

```bash
# bq CLI
bq query --use_cache=false 'SELECT ...'
```

### ClickHouse：23.4 引入 Query Cache

ClickHouse **23.4（2023 年 4 月）** 才正式引入 query cache，是这一波"传统 OLAP 引擎补全 result cache"潮流的代表。

```xml
<!-- config.xml -->
<query_cache>
    <max_size_in_bytes>1073741824</max_size_in_bytes>  <!-- 1GB -->
    <max_entries>1024</max_entries>
    <max_entry_size_in_bytes>1048576</max_entry_size_in_bytes>  <!-- 1MB -->
    <max_entry_size_in_rows>30000000</max_entry_size_in_rows>
</query_cache>
```

```sql
-- 启用 (会话级)
SET use_query_cache = 1;

-- 单查询启用
SELECT count() FROM hits SETTINGS use_query_cache = 1;

-- TTL 配置 (默认 60 秒, 而非 Snowflake/BigQuery 的 24 小时)
SET query_cache_ttl = 600;  -- 10 分钟

-- 仅缓存运行 > N 秒的查询 (避免缓存秒级查询的开销)
SET query_cache_min_query_duration = 1000;  -- ms

-- 仅在第 N 次执行后缓存
SET query_cache_min_query_runs = 3;

-- 系统视图查看
SELECT query, result_size, hit_count
FROM system.query_cache;
```

**ClickHouse query cache 的设计哲学**：

- **TTL 默认 60 秒**：偏向"短寿命"策略，反映了 OLAP 用户对"近实时"的要求
- **min_query_runs = 0 默认**：即第一次就缓存，与传统 LRU 不同
- **明确不保证一致性**：DML 后的失效是异步的，可能短暂返回过期结果（用户可显式调 `SYSTEM DROP QUERY CACHE`）

**ClickHouse 多缓存协同**：

| 缓存 | 内容 | 默认大小 (22.x+) | TTL |
|------|------|----------------|-----|
| query cache | SELECT 结果 | 1GB | 60s |
| mark cache | 列索引标记 | 5GB | 不过期 |
| uncompressed cache | 解压后的列块 | 8GB | LRU |
| mmap cache | 已 mmap 文件句柄 | 1000 个 | LRU |
| compiled expression cache | JIT 编译表达式 | 134MB | LRU |

**为什么 ClickHouse 这么晚才加 query cache？** 早期社区强调"扫描足够快，不需要缓存"——大多数 ClickHouse 查询在物理上只读 1-10 个 column granule，毫秒级完成。但当 ClickHouse 进入实时 BI / Dashboard 场景（同一查询每 5 秒被前端轮询），原始的 SELECT 哪怕 50ms 也变成了 N×50ms 的浪费——这才是 query cache 的价值场景。

### Databricks：Disk Cache + Result Cache 分层

Databricks SQL Warehouse 提供了**双重缓存**：

```sql
-- Disk Cache: 把 Parquet/Delta 文件解码后缓存到节点 SSD
CACHE SELECT * FROM main.orders WHERE order_date >= '2024-01-01';

-- 自动: 任何查询读过的文件都进 disk cache
-- 持久: 集群重启 disk cache 保留 (除非显式清除)

-- Result Cache: 24h, 类似 Snowflake
-- 默认启用 (SQL Warehouse), 关闭:
SET use_cached_result = false;
```

**两层的差异**：

| 维度 | Disk Cache | Result Cache |
|------|-----------|-------------|
| 内容 | Parquet 文件解码后 | SQL 结果集 |
| 存储 | 节点本地 SSD | Cloud Services 层 |
| 命中条件 | 同样的文件 | 同样的 SQL + 数据未变 |
| TTL | 容量驱逐 | 24 小时 |
| 跨用户共享 | 是 | 是（权限内） |

**预热策略**：

```sql
-- 主动预热 disk cache
CACHE SELECT * FROM main.large_table 
WHERE partition_date BETWEEN '2024-01-01' AND '2024-12-31';

-- 查看 disk cache 状态
SELECT * FROM `system`.`information_schema`.`disk_cache_status`;
```

### SAP HANA：内存常驻 + LOAD INTO MEMORY

SAP HANA 是**全列存内存数据库**，所有的 column store 表默认完全装入内存。"预热"对 HANA 的语义略有不同：

```sql
-- 强制把整表所有列装入 main memory
ALTER TABLE orders PRELOAD ALL;

-- 仅装入特定列
ALTER TABLE orders PRELOAD (order_id, customer_id, amount);

-- 异步 LOAD (不阻塞)
LOAD orders INTO MEMORY ALL;
LOAD orders DELTA INTO MEMORY;        -- 仅 delta 部分
LOAD orders MAIN INTO MEMORY;         -- 仅 main store

-- 卸载 (释放内存)
UNLOAD orders;

-- 设置 unload priority (0-9, 数字越小越不优先卸载)
ALTER TABLE orders ALTER UNLOAD PRIORITY 9;  -- 几乎永久驻留

-- 监控
SELECT table_name, loaded, memory_size_in_total
FROM m_cs_tables
WHERE schema_name = 'MY_SCHEMA'
ORDER BY memory_size_in_total DESC;
```

**HANA 的 RESULT_CACHE Hint（2.0 SPS04 起）**：

```sql
-- 非事务结果缓存 (允许短暂陈旧)
SELECT * FROM orders WHERE region = 'APAC'
WITH HINT(RESULT_CACHE_NON_TRANSACTIONAL);

-- 事务一致结果缓存 (DML 立即失效)
SELECT COUNT(*) FROM events WHERE event_type = 'click'
WITH HINT(RESULT_CACHE_TRANSACTIONAL);

-- 自定义 TTL (秒)
SELECT * FROM heavy_aggregation
WITH HINT(RESULT_CACHE_NON_TRANSACTIONAL(3600));

-- 禁用
SELECT * FROM t WITH HINT(NO_RESULT_CACHE);
```

**HANA RESULT_CACHE_TRANSACTIONAL vs NON_TRANSACTIONAL** 是行业里少见的"显式让用户选择一致性级别"的设计：

| 模式 | 一致性 | 性能 | 适用 |
|------|-------|------|------|
| TRANSACTIONAL | DML 立即失效 | 较慢（需追踪依赖） | 事务报表 |
| NON_TRANSACTIONAL | TTL 内可能陈旧 | 极快 | Dashboard、BI |

### SingleStore：blob cache + WARM CACHE

SingleStore（原 MemSQL）的 columnstore 数据存储在云端 blob storage（S3/Azure），节点本地 SSD 作为 blob cache：

```sql
-- 预热 columnstore blob cache
OPTIMIZE TABLE orders WARM BLOB CACHE FOR TABLE;

-- 仅热点分区
OPTIMIZE TABLE orders WARM BLOB CACHE FOR PARTITIONS (0, 1, 2);

-- 查看 blob cache 状态
SELECT NODE_ID, USED_BYTES, MAX_BYTES, NUM_REMOTE_FILES
FROM information_schema.MV_BLOB_CACHE_USAGE;
```

**Result Set Cache**：

```sql
-- 全局启用
SET GLOBAL result_set_cache_size = 1024;       -- MB
SET GLOBAL enable_result_cache = TRUE;

-- 查询级
SELECT /*+ RESULT_CACHE */ * FROM big_table WHERE ...;

-- 监控
SELECT * FROM information_schema.MV_RESULT_CACHE_STATS;
```

### 其他引擎速览

**Vertica（depot SSD cache，EON 模式 2017+）**：数据存 S3，本地 SSD 作 depot 缓存。`ALTER NODE node01 ADD DEPOT '/depot' SIZE '500GB';` 配置；`SELECT MAKE_DEPOT_DATA('events', 'YYYYMMDD <= 20241231');` 强制预热；任何 `SELECT` 命中后会自动把对应分区数据从 S3 拉到 depot。

**TiDB / TiKV**：无显式 buffer dump/load，但底层 TiKV 基于 RocksDB 的 block cache（`storage.block-cache.capacity = "45%"`）在重启后由 RocksDB 自身的 read-ahead 自动预读热点 SST。TiDB 也有计划缓存（`tidb_enable_prepared_plan_cache`）但不属 result cache。

**OceanBase**：类 Oracle 设计——`SET GLOBAL _enable_result_cache = 1;` + `_result_cache_size = '256M';` + `/*+ RESULT_CACHE */` hint。监控走 `GV$OB_RESULT_CACHE_STATISTICS`。

**Hive LLAP（2.3+）**：`hive.query.results.cache.enabled=true` + `hive.query.results.cache.max.entry.lifetime=3600s` 配置；`SET hive.query.results.cache.enabled=false;` 会话级关闭。结果存 HDFS 的 `_resultscache_` 目录。

**AWS Athena（v3, 2022+）**：`ResultReuseConfiguration.ResultReuseByAgeConfiguration.Enabled=true` + `MaxAgeInMinutes=60` API 参数。**不自动启用，每次显式开启**，TTL 最长 7 天，反映 ad-hoc 分析少重复查询的产品定位。

## Oracle Result Cache 完整工作流

```
SELECT 执行流程:
  1. 解析 SQL, 计算 cache key (SQL hash + bind + NLS + role)
  2. RESULT_CACHE_MODE 决定是否查找 cache:
     - MANUAL: 仅当 query 带 /*+ RESULT_CACHE */ hint 时查找
     - FORCE:  所有查询默认查找 (除非 NO_RESULT_CACHE)
  3. 在 Result Cache memory 区查找:
     - 命中且依赖对象未变化 → 直接返回结果集
     - 未命中或失效 → 走正常执行
  4. 执行后, 若结果集大小 ≤ RESULT_CACHE_MAX_RESULT (默认 5%) → 写入并注册依赖
  
依赖跟踪与失效:
  - 写入时记录 SQL 引用的 base table OID + DDL_TIMESTAMP
  - DML 触发后台进程标记相关 entry 为 invalid
  - RAC 多节点: 通过 GES (Global Enqueue Service) 广播失效消息
```

每个 RC entry 包含 header（id, type, status, hash, dependencies[]）+ body（列定义 + 结果行二进制压缩）+ 时间戳与命中计数。SQL Result Cache、PL/SQL Function Result Cache、OCI Client Result Cache 元数据共享同一片 RC memory。

## MySQL Buffer Pool Dump/Load 完整工作流

```
关机:
  1. 停止接受新事务, 等待已有事务结束, flush 所有脏页
  2. 若 innodb_buffer_pool_dump_at_shutdown=ON:
     - 遍历 N 个 buffer_pool_instances
     - 每个 instance 按 LRU young → old 扫描
     - 取前 dump_pct 的 (space_id, page_no), 合并去重
     - 原子 rename → ib_buffer_pool

启动:
  1. InnoDB 初始化, redo log crash recovery, 初始化 buffer_pool_instances (空)
  2. 若 innodb_buffer_pool_load_at_startup=ON:
     - 读 ib_buffer_pool, 解析 + 按 (space_id, page_no) 排序
     - 启动 N 个 load worker (每个 instance 一个)
     - 每 worker 并发 ReadPage(), 不阻塞前台服务
  3. 业务命中已 load 的页 = 命中; 未 load 触发同步读

典型时间线 (512GB 实例, NVMe):
  无 dump/load: 启动 1 分钟 → 命中率 0% → 1 小时后 80% → 2 小时后 99%
  有 dump/load: 启动 1 分钟 → load 5 分钟 → 命中率 95% → 30 分钟后 99%
```

## PostgreSQL pg_prewarm autoprewarm 完整工作流

```
配置:
  shared_preload_libraries = 'pg_prewarm'
  pg_prewarm.autoprewarm = on
  pg_prewarm.autoprewarm_interval = 300s

启动时:
  Phase 1: postmaster 启动
  ├── 初始化 shared_buffers (空)
  ├── recovery (如有)
  └── 启动 background workers
  
  Phase 2: autoprewarm worker 启动
  ├── attach 到 postgres database (默认)
  ├── 读 $PGDATA/autoprewarm.blocks
  ├── 解析每行: <db_oid>,<tablespace_oid>,<rel_filenode>,<fork>,<block_no>
  ├── 按 (db, tablespace, rel, fork, block) 排序
  ├── 逐个 ReadBuffer() 装入 shared_buffers
  ├── 装满 buffer pool 或读完文件即停止
  └── log: "autoprewarm successfully prewarmed N buffers"

运行时 (每 autoprewarm_interval 秒):
  ├── worker 唤醒
  ├── 扫描 shared_buffers, 收集 (db, ts, rel, fork, block) 列表
  ├── 写入临时文件 $PGDATA/autoprewarm.blocks.tmp
  ├── 原子 rename → autoprewarm.blocks
  └── sleep autoprewarm_interval

关机时:
  ├── postmaster 收到 SIGTERM
  ├── 通知 autoprewarm worker 立即 dump
  ├── worker 完成 dump 后退出
  └── 其他后台进程退出
```

**与 MySQL dump/load 的核心差异**：

```
MySQL: 关机 dump, 启动 load (单次)
  - 关机失败 (kill -9) → dump 文件可能丢失或不完整
  - 一次 dump 反映"关机瞬间"的状态
  - 简单, 可靠, 但抗故障能力弱

PG: 周期 dump, 启动 load (多次)
  - 即使 OS crash, 最近 5 分钟前的 dump 文件保留
  - 能捕捉"运行期间动态变化"
  - 复杂, 但抗故障能力强
```

## ClickHouse 的多缓存架构

ClickHouse 既有传统的 mark/uncompressed cache（数据缓存），又有新加的 query cache（结果缓存）：

```
查询执行管道:

  SQL → parse → optimize → execute
                              ↓
                        [query cache hit?]
                              ↓ no
                        [扫描 part data]
                              ↓
                        [mark cache hit?] → no → read .mrk file
                              ↓ yes
                        [uncompressed cache hit?] → no → decompress block
                              ↓ yes
                        [处理列数据] → aggregate
                              ↓
                        写入 query cache (TTL 60s)
                              ↓
                        返回结果
```

每一层都可以独立调优：

```sql
-- 查看各缓存命中率
SELECT event, value 
FROM system.events
WHERE event LIKE '%Cache%'
ORDER BY event;

-- 输出示例:
-- MarkCacheHits          1234567
-- MarkCacheMisses          1234
-- UncompressedCacheHits  234567
-- UncompressedCacheMisses 89012
-- QueryCacheHits         12345
-- QueryCacheMisses       67890
```

**预热 ClickHouse**（无内置机制，需要手动）：

```sql
-- 预热 mark cache (扫描所有 part 元数据)
SELECT name, total_marks 
FROM system.parts 
WHERE active AND database = 'default' AND table = 'events';

-- 预热 uncompressed cache (执行一次大扫描)
SELECT count() FROM events WHERE event_date >= today() - 7;

-- 预热 query cache (无法主动, 只能通过查询触发)
```

## 设计争议

### 1. 结果缓存的"诱惑陷阱"

```
工程角度看, result cache 是一把双刃剑:

正收益场景:
  ✓ 数据仓库 / BI 报表 (写少读多, 重复查询率 90%+)
  ✓ 多租户 SaaS (公共数据被多用户重复查询)
  ✓ Dashboard 自动刷新 (秒级查询每 5s 一次)
  ✓ 计算成本高的聚合 (大窗口、复杂 join)

负收益场景:
  ✗ OLTP (DML 频繁, 缓存失效成本 > 命中收益)
  ✗ ad-hoc 分析 (查询独特, 命中率低)
  ✗ 极短查询 (cache 维护开销 > 节省的查询时间)
  ✗ 含非确定性函数 (永远 cache miss, 但仍尝试缓存)

各引擎的策略反映了主战场:
  Snowflake/BigQuery: 默认开启 → 数据仓库
  MySQL: 删除功能 → OLTP
  PostgreSQL: 拒绝引入 → "应用层做"
  Oracle: MANUAL 默认 → 由 DBA 决定
```

### 2. 缓冲池预热"持久化策略"的谱系

```
  Strict 派 (PG autoprewarm, MySQL dump/load):
  - 显式持久化页面列表
  - 重启后按列表恢复
  - 优点: 可控、可观察
  - 缺点: 实现复杂, 文件管理负担

  Lazy 派 (大多数 NewSQL, 云数仓):
  - 不持久化, 重启后冷启动
  - 依赖业务流量"自然预热"
  - 优点: 简单, 无文件
  - 缺点: 冷启动期间性能差

  SSD 派 (Databricks Disk Cache, Vertica depot, SingleStore blob cache, SQL Server BPE):
  - 把热数据持久化到本地 SSD
  - 重启后 SSD 文件保留, 内存中冷数据回 SSD 读
  - 优点: 大容量缓存
  - 缺点: 增加一层介质, 容量管理复杂

  内存常驻派 (SAP HANA, MemSQL rowstore):
  - 数据全部装入内存, 重启后必须重新装入
  - 优点: 性能极致
  - 缺点: 内存成本高, 启动时间长

  孩子派 (Materialize, RisingWave):
  - "预热"概念被增量物化视图替代
  - 状态本身就是持久化的
  - 优点: 永远没有冷启动
  - 缺点: 范式与传统 DB 不同
```

### 3. TTL 选择的争议

```
24h (Snowflake, BigQuery, Databricks):
  ✓ 商业用户期望"昨天的报表今天还能秒回"
  ✓ 给 ETL 留足时间 (大多数批处理 < 24h)
  ✗ 数据陈旧风险 (DML 失效 + TTL 双重保险)

60s (ClickHouse 默认):
  ✓ 实时性强
  ✗ 反复查询命中率低
  ✓ 适合 dashboard 类负载

无 TTL (Redshift, Oracle):
  ✓ LRU 自动管理, 容量驱动驱逐
  ✗ "陈旧 cache" 难以预测

7 天 (Athena 上限):
  ✓ 极长保留, ad-hoc 友好
  ✗ 必须用户显式启用 (默认关闭)
```

### 4. 缓存键的设计陷阱

```
完整文本 (MySQL 历史):
  ✗ "SELECT * FROM t" 与 "select * from t" 不同
  ✗ 多一个空格不命中
  → 极低的命中率

规范化文本 / AST (Oracle, Snowflake):
  ✓ 大小写、空格、注释不敏感
  ✗ 实现复杂 (需要完整 parser)
  ✗ 哈希冲突风险

规范化 + Bind 变量分离 (Oracle):
  ✓ "WHERE id = ?" 多次执行不同参数能命中
  → 极高的命中率

但: 必须把 bind 值纳入缓存键!
  ✗ "WHERE id = 1" 与 "WHERE id = 2" 不能错命中
  ✓ Cache key = SQL hash + bind values hash
```

## 对引擎开发者的实现建议

### 1. Result Cache 的依赖跟踪

```rust
struct ResultCacheEntry {
    sql_hash: u64,
    bind_hash: u64,
    user_role: u32,
    nls_hash: u32,
    ttl: Option<Duration>,
    data: Vec<u8>,                    // 序列化的结果集
    dependencies: Vec<TableVersion>,  // (object_id, ddl_ts, data_version)
}

fn check_validity(entry: &ResultCacheEntry, current: &CatalogSnapshot) -> bool {
    entry.dependencies.iter().all(|dep| {
        let curr = current.lookup(dep.object_id);
        curr.ddl_timestamp == dep.ddl_timestamp && curr.data_version <= dep.data_version
    })
}
```

**关键设计权衡**：

- **依赖粒度**：整表级（MySQL 历史，简单粗暴）vs 分区级（Snowflake micro-partition，平衡）vs 行级（理论可能，无引擎采用）
- **失效广播**：同步（Oracle RAC GES，写入慢但立即生效）vs 异步（ClickHouse，可能短暂陈旧）vs TTL 兜底（Snowflake 24h，简单但实时性差）

### 2. 非确定性函数的检测

引擎在 parse 阶段必须遍历 AST 检测下列函数，发现后自动跳过 result cache：

```
NOW() / CURRENT_TIMESTAMP / SYSDATE         -- 时间相关
USER / CURRENT_USER / SESSION_USER          -- 用户上下文
RANDOM() / RAND() / UUID() / NEWID()        -- 随机
CURRVAL() / NEXTVAL()                       -- 序列
LAST_INSERT_ID()                            -- 会话状态
```

PostgreSQL 的 `IMMUTABLE / STABLE / VOLATILE` 三态注解就是为此而生（详见 `function-volatility.md`）。Oracle、Snowflake、BigQuery 都内建了此检查；MySQL 历史 query cache 没有，导致大量陷阱。

### 3. 缓冲池预热的并行化

预热的核心在于：**排序后的顺序 I/O + 多线程 worker 各负责一个 buffer pool instance**。关键模式：

```
1. 读 dump 文件得到 (tablespace, rel_filenode, block_no) 列表
2. 排序使物理上相邻
3. 按 instance 分片, 每个 instance 一个 worker
4. worker 并发调 ReadBuffer() 装入
5. 装入数量限制为 buffer_pool_size * 0.7 (留 30% 给运行时)
6. 使用"低优先级 LRU 位置"避免占满 young sublist
```

### 4. Result Cache 与 MVCC 的协同

快照隔离下的 result cache 必须把 snapshot 标识纳入缓存键（LSN / SCN / commit_ts）。两种主流策略：

- **Snowflake**：缓存"最新提交"结果。命中条件：`current_tx.read_ts >= cache.commit_ts`。数据变化后 `commit_ts` 推进，旧 cache 失效。
- **Oracle**：缓存严格匹配 snapshot。事务一致性更强，但命中率较低。

### 5. 监控指标设计

Result cache 必备指标：`cache.hits / misses / invalidations / evictions / size_bytes / entries / hit_rate`。

Buffer pool warmup 必备指标：`prewarm.entries_read / duration_ms / bytes_read / cache_resident_after / business_hit_rate_5min`（预热完成后 5 分钟内业务命中率，最终衡量预热效果的金标准）。

## 关键发现

### 1. 结果缓存与缓冲池预热是两条独立但互补的战线

它们解决的"性能问题"看似相似，本质完全不同：

- **Result cache** 缓存的是"已经计算好的答案"，命中时**完全跳过执行**，零 I/O、零 CPU。
- **Buffer pool warmup** 缓存的是"原始数据页"，命中时**仍要执行查询**，但跳过磁盘 I/O。

一个引擎可能两者都有（Oracle、SAP HANA），可能只有其中一种（PostgreSQL 仅 buffer warmup，MySQL 8.0+ 仅 buffer pool dump/load），也可能两者都没有显式机制（DuckDB——进程内嵌入，无重启概念；Trino——无状态计算引擎）。

### 2. 云数仓与开源 OLTP 的策略分裂

**云数仓（Snowflake / BigQuery / Databricks / Redshift / Firebolt）**：默认启用 24h result cache。理由：

- 写入与读取分离，写少读多
- 多租户场景下缓存复用率极高
- 计算资源弹性收费，cached 查询零成本对用户极有吸引力
- 用户对"零运维"的期望，自动启用是必然

**开源 OLTP（PostgreSQL / MySQL / SQL Server）**：要么不支持，要么已删除：

- PG 核心团队多次拒绝 result cache 提案，认为应用层缓存（Redis / Memcached / pg_qualstats）更合适
- MySQL 8.0.3 删除 query cache，理由是写多读少负载下负收益
- SQL Server 从未引入

### 3. Oracle 是商业数据库中两条战线都做得最完整的

```
Oracle 的全栈缓存矩阵:
  Server-side Result Cache (11g)         → SQL + PL/SQL
  Client-side Result Cache (11g)         → OCI 驱动
  Multiple Buffer Pools (8i)             → DEFAULT/KEEP/RECYCLE
  Database Smart Flash Cache (11g)       → SSD 扩展
  In-Memory Column Store (12c)           → 列存内存
  Result Cache hint (RESULT_CACHE)       → SQL 级控制
```

这是 17 年累积的工程结果，开源数据库需要数年才能追赶到一半。

### 4. PG 的"buffer warmup yes, result cache no"非常坚定

PostgreSQL 提供了 `pg_prewarm` + `autoprewarm` 这套完整的 buffer warmup 机制（2014 年 9.4 引入扩展，2018 年 11 引入 autoprewarm），但**始终拒绝 server-side result cache**。

核心团队的论点：

1. 引擎应专注于"快速执行查询"，而非"避免重复执行"
2. 应用层缓存（Redis）失效控制更灵活
3. 物化视图（含 PG 17 增量刷新）覆盖 80% result cache 用例
4. 维护 result cache 的失效成本可能高于命中收益

### 5. MySQL 的 dump/load 是"重启友好"的工程典范

5.6 引入的 dump/load 机制至今仍是开源数据库中最成熟的 buffer pool 持久化方案。**它的精妙之处在于"只 dump page 标识不 dump 内容"**——文件极小（200MB 对 500GB pool），却能在启动时通过排序后的顺序 I/O 把命中率快速恢复。

PG 的 autoprewarm 在格式上更紧凑（5 字段 binary），但默认不启用，需要用户显式 `shared_preload_libraries`。这反映了两家社区对"运维便利性"的不同优先级。

### 6. ClickHouse 23.4 的 query cache 折射 OLAP 引擎的演进

早期 ClickHouse 强调"扫描足够快，不需要缓存"。但 2023 年加入 query cache 反映了几个趋势：

- 实时 BI 场景中"同一查询每 5 秒被前端轮询"成为常态
- 用户对"即使查询毫秒级也想要 cached 命中"的需求
- 默认 60s TTL 比 Snowflake 的 24h 短得多，反映 OLAP 用户对一致性的更高要求

### 7. 云数仓的 24h TTL 是"无冲突"的优雅妥协

```
为什么 24h 是"近似最优"?
  T < 1h:  同事重新打开 dashboard 还能命中
  T < 4h:  跨时区团队接力工作能命中  
  T < 24h: 隔夜 ETL 完成后, 早上的 BI 查询仍能命中
  T = 24h: 强制刷新, 防止用户依赖陈旧数据

更长 (7 天) 太陈旧, 更短 (1 小时) 跨时区不友好.
24h + 数据变化即失效是工程平衡点.
```

### 8. 预热在大内存机器上是"性能逃生通道"

```
512GB+ 缓冲池机器, 不预热的代价:
  - 重启后 1 小时内 QPS 损失 80%
  - 99 分位延迟从 50ms 飙到 2.5s
  - 业务方看到的是"系统重启 = 1 小时不可用"

有了预热:
  - 5 分钟内业务恢复正常
  - 用户感知到的"重启时间" = 5 分钟而非 1 小时
  - 才让"零停机滚动升级"成为可能
```

这就是为什么 MySQL 的 dump/load、PG 的 autoprewarm 都成了"运维标配"。云时代下，Snowflake/BigQuery 通过 multi-cluster 跨节点的预热数据交换，进一步把"看不见的预热"做到了极致。

### 9. SSD 缓存层的回归

```
2014  SQL Server BPE        → 缓冲池扩展到 SSD
2014  Oracle Flash Cache    → 同上
2017+ Databricks Delta Cache → 把 S3 Parquet 解码后缓存到 SSD
2017+ Vertica depot         → S3 → 本地 SSD
2018+ SingleStore blob cache → blob 存储 → SSD
2019+ Firebolt F3 engine    → 同上

共同模式: 内存层 (热) + SSD 层 (温) + 远端存储 (冷)
SSD 层在重启后保留, 是"长寿命预热"的代表
```

### 10. 物化视图是 result cache 的"另一种形态"

```
传统物化视图:
  CREATE MATERIALIZED VIEW mv AS SELECT ...;
  REFRESH MATERIALIZED VIEW mv;  -- 显式刷新
  
增量物化视图 (Materialize, RisingWave, PG 17):
  CREATE MATERIALIZED VIEW mv AS SELECT ...;
  -- 自动持续维护, 永远新鲜
  
对比 result cache:
  Result cache: 隐式 (用户不知道命中)
  物化视图: 显式 (用户写 mv 名字)
  
某种意义上: 物化视图 = "永不过期 + 显式 + 增量维护的 result cache"
```

这就是 Materialize/RisingWave 等流处理数据库不需要传统 result cache 的原因——**它们的物化视图本身就是持续维护的"新鲜结果"**。

## 总结对比矩阵

### 核心能力速查

| 能力 | Oracle | PG | MySQL | SQL Server | Snowflake | BigQuery | ClickHouse | Databricks | SAP HANA |
|------|--------|----|----|-----------|-----------|----------|-----------|-----------|----------|
| Server result cache | 11g+ | -- | 4.0-8.0 | -- | 默认 | 默认 | 23.4+ | 默认 | 2.0+ |
| Client result cache | OCI | -- | -- | -- | -- | -- | -- | -- | -- |
| RESULT_CACHE hint | 是 | -- | -- | -- | -- | -- | -- | -- | 是 |
| Buffer pool dump | -- | autoprewarm | 5.6+ | -- | 托管 | 托管 | -- | Delta 持久 | -- |
| Buffer pool load | -- | autoprewarm | 5.6+ | -- | 托管 | 托管 | -- | Delta 自动 | -- |
| 显式预热语法 | CACHE | pg_prewarm | dump_now | -- | warehouse | -- | OPTIMIZE | CACHE SELECT | LOAD INTO MEMORY |
| Result TTL | 依赖 | -- | LRU | -- | 24h | 24h | 60s | 24h | hint 内 |
| 失效粒度 | 对象 | -- | 表 | -- | partition | 表 | 表 | Delta TX | 表 |
| 引入年份 | 2007 | 2018 | 2013 | -- | GA | GA | 2023 | GA | 2018 |

### 选型建议

| 场景 | 推荐策略 |
|------|---------|
| 数据仓库 BI 报表 | 全托管云数仓（Snowflake/BigQuery/Databricks），享受默认 24h cache |
| Oracle 重报表负载 | RESULT_CACHE_MODE=MANUAL + 关键查询加 `/*+ RESULT_CACHE */` hint |
| MySQL 大内存 OLTP | 启用 `dump_at_shutdown=ON, load_at_startup=ON, dump_pct=25` |
| PG 大内存 OLTP | 启用 `pg_prewarm.autoprewarm=on`, 调 `interval=300s`, `shared_buffers=25%` |
| ClickHouse 实时 BI | 设 `query_cache_ttl=300`, `min_query_runs=2` 平衡命中与一致性 |
| SAP HANA 关键事实表 | `ALTER TABLE PRELOAD ALL` + `UNLOAD PRIORITY 9` 确保常驻内存 |
| SingleStore columnstore | `OPTIMIZE TABLE WARM BLOB CACHE` 启动后立即触发 |
| Delta Lake 数仓 | `CACHE SELECT *` 主动预热 disk cache, 让结果 cache 自然命中 |
| 多租户 SaaS | 用应用层 Redis 替代引擎 result cache, 避免跨租户键冲突 |
| 流处理实时数仓 | 用 Materialize/RisingWave 增量物化视图替代传统 result cache |

## 参考资料

- Oracle: [Result Cache Concepts](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgdba/tuning-result-cache.html)
- Oracle: [RESULT_CACHE Hint](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Comments.html)
- Oracle: [Client Result Cache](https://docs.oracle.com/en/database/oracle/oracle-database/19/lnoci/client-result-cache.html)
- PostgreSQL: [pg_prewarm](https://www.postgresql.org/docs/current/pgprewarm.html)
- PostgreSQL: [pg_buffercache](https://www.postgresql.org/docs/current/pgbuffercache.html)
- PostgreSQL: [autoprewarm (PG 11+)](https://www.postgresql.org/docs/11/pgprewarm.html)
- MySQL: [Saving and Restoring the Buffer Pool State](https://dev.mysql.com/doc/refman/8.0/en/innodb-preload-buffer-pool.html)
- MySQL: [Query Cache Removal (8.0.3)](https://dev.mysql.com/blog-archive/mysql-8-0-retiring-support-for-the-query-cache/)
- MariaDB: [Query Cache](https://mariadb.com/kb/en/query-cache/)
- SQL Server: [Buffer Pool Extension](https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/buffer-pool-extension)
- SQL Server: [DBCC BUFFERPOOL](https://learn.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-buffer-transact-sql)
- Snowflake: [Using Persisted Query Results](https://docs.snowflake.com/en/user-guide/querying-persisted-results)
- BigQuery: [Query Cache](https://cloud.google.com/bigquery/docs/cached-results)
- ClickHouse: [Query Cache (23.4+)](https://clickhouse.com/docs/en/operations/query-cache)
- ClickHouse: [Server Caches](https://clickhouse.com/docs/en/operations/caches)
- Databricks: [Delta Cache](https://docs.databricks.com/en/optimizations/disk-cache.html)
- Databricks: [Result Cache](https://docs.databricks.com/en/sql/admin/sql-warehouse-configuration.html)
- SAP HANA: [Result Cache Hint](https://help.sap.com/docs/SAP_HANA_PLATFORM/9de0171a6027400bb3b9bee385222eff/c4ba37b8a9994a31b1d8f77fa7da0e84.html)
- SAP HANA: [LOAD Statement](https://help.sap.com/docs/SAP_HANA_PLATFORM)
- Hive: [Query Results Cache](https://cwiki.apache.org/confluence/display/Hive/Query+Results+Cache)
- Athena: [Query result reuse](https://docs.aws.amazon.com/athena/latest/ug/reusing-query-results.html)
- SingleStore: [WARM BLOB CACHE](https://docs.singlestore.com/cloud/reference/sql-reference/data-manipulation-language-dml/optimize-table/)
- Vertica: [Depot Management](https://docs.vertica.com/latest/en/admin/managing-depot/)
- O'Neil et al. "The LRU-K Page Replacement Algorithm" (1993), SIGMOD
- Effelsberg, W. & Haerder, T. "Principles of Database Buffer Management" (1984), ACM TODS
- Stonebraker, M. "The Case Against Query Caches" (various interviews on PostgreSQL design)
