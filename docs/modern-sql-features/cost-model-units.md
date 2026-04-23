# 优化器代价模型 (Cost Model Units and Weights)

优化器选择执行计划的全部逻辑，都压缩在一个数字上：代价。但不同引擎对"代价"的定义天差地别——PostgreSQL 的代价接近"顺序读取一个 8KB 页面所需时间"，Oracle 的代价单位是"单块 I/O"，SQL Server 的 Subtree Cost 完全抽象（1 大约对应 2000 年硬件上的 1 秒），BigQuery 则用"slot-millisecond"按钱计算。代价模型的单位选择决定了参数可否下调、EXPLAIN 数字是否可比、调优经验是否可迁移。

## 为什么代价单位会分化

### 代价模型要解决的三个问题

```
问题 1: 如何比较两个计划?
  计划 A: 全表扫描 + Hash Join    估算: 100 万 I/O
  计划 B: 索引扫描 + Nested Loop  估算: 10 万 I/O + 100 万 CPU 运算

  仅统计 I/O 数量不够: CPU 运算也消耗时间, 且与 I/O 单位不同.
  必须把两类资源折算到同一个"代价单位"才能比较.

问题 2: 硬件差异如何建模?
  顺序 I/O 和随机 I/O 在 HDD 上速度差 50 倍, 在 SSD 上差 5 倍, 在 NVMe 上差 1.5 倍.
  优化器需要在不同硬件下给出不同选择, 这就要求参数可调.

问题 3: 用户应该看到什么?
  EXPLAIN 输出的代价, 是让用户看 "预计多少秒" 还是 "预计多少 I/O"?
  如果是抽象单位, 用户如何判断计划是否合理?
```

### 单位选择的三种流派

```
流派 A: 物理量建模 (PostgreSQL, Greenplum, 早期 MySQL)
  - 代价单位 = 顺序读一个页所需时间 (基准 1.0)
  - 其他操作 (CPU, 随机 I/O) 折算成这个基准的倍数
  - 优点: 单位具体, 参数可下调到硬件特性
  - 缺点: 折算系数需要频繁调整, SSD 时代默认值过时

流派 B: 抽象单位 (SQL Server, DB2, Sybase)
  - Subtree Cost 无单位, 只用于比较不同计划的相对优劣
  - 内部折算公式硬编码, 用户无法调整
  - 优点: 用户不用理解物理意义
  - 缺点: 跨引擎/跨版本无法对比, 参数调优依赖文档内幕

流派 C: 资源计量 (Oracle, 云数据仓库)
  - Oracle: I/O + CPU 分别计量, 用 sreadtim 等 "系统统计" 折算
  - BigQuery: slot-millisecond (按 CPU·时间计费)
  - Snowflake: credits (按 warehouse 时长 × 档位计费)
  - 优点: 与资源定价直接挂钩, 用户看得见账单
  - 缺点: 受定价策略影响, 与物理代价脱钩
```

### 没有 SQL 标准

SQL:2016 标准仅定义 `EXPLAIN` 的存在性（作为 `<explain statement>`），没有规定代价的单位、量纲或可见格式。代价模型完全是实现相关的：

- 不同引擎的 EXPLAIN 输出中 "cost" 列含义不同
- 相同查询在不同引擎的代价数值不可比
- 代价参数的命名、单位、默认值都没有标准
- 官方文档和论文中的术语混乱（"cost unit"、"access cost"、"weight"、"factor"）

引擎开发者因此拥有充分的设计自由度，但用户和 DBA 必须为每个引擎单独学习代价模型。

## 代价单位支持矩阵（45+ 引擎）

| 引擎 | 代价单位约定 | 可调参数 | EXPLAIN 是否显示代价 | 备注 |
|------|-------------|---------|--------------------|------|
| PostgreSQL | 顺序 page I/O（= 1.0） | 是（9 个 GUC） | 是（startup..total） | 流派 A 典范 |
| MySQL | 引擎相关常量（IO/CPU） | 是（`mysql.server_cost`, `mysql.engine_cost`） | 8.0+ JSON 显示 | 8.0 重构前硬编码 |
| MariaDB | 顺序 page I/O | 是（`optimizer_*_cost`） | 是（JSON） | 10.4+ 重构代价模型 |
| Oracle | 单块 I/O 折算秒数 | 间接（`optimizer_index_cost_adj`, system stats） | 是（Cost 列） | 流派 C |
| SQL Server | 抽象 Subtree Cost | 否 | 是（Estimated Subtree Cost） | 流派 B |
| DB2 | timerons（抽象单位） | 部分（注册表变量） | 是（timeron） | 流派 B |
| Sybase ASE | 逻辑 I/O + 物理 I/O | 部分 | 是 | 流派 B |
| SQLite | 抽象估算值 | 否 | 仅 EXPLAIN QUERY PLAN | 无显式代价数字 |
| SQL Server PDW / Synapse | 分布式代价（复用 SQL Server 模型） | 否 | 是 | -- |
| Informix | 抽象单位 | 部分 | 是 | -- |
| Firebird | 无传统代价模型 | 否 | 否 | 依赖规则 + 选择性 |
| H2 | 简化整数代价 | 否 | 是 | -- |
| HSQLDB | 简化代价 | 否 | 否 | -- |
| Derby | 简化代价 | 否 | 是 | -- |
| CockroachDB | 抽象代价（PG 兼容） | 部分 | 是 | -- |
| TiDB | 归一化代价（与 TiKV/TiFlash 对齐） | 是（`tidb_opt_*_factor`） | 是（EXPLAIN ANALYZE） | CBO 重构 5.x+ |
| OceanBase | 抽象代价 | 有限 | 是 | -- |
| YugabyteDB | 继承 PG 代价 | 是 | 是 | -- |
| Greenplum | 继承 PG 代价 | 是 | 是 | 分布式扩展 |
| Citus | 继承 PG 代价 | 是 | 是 | -- |
| Redshift | 抽象代价 | 否 | 是 | MPP 执行时代价 |
| Snowflake | Credits / bytes scanned | 否 | 仅 profile | 按账单计量 |
| BigQuery | slots-millisecond / bytes billed | 否 | dry-run + profile | 按账单计量 |
| Athena | bytes scanned | 否 | Trino 风格 | 按扫描量计费 |
| Databricks SQL | 分布式代价（Photon 增强） | 否 | 是 | -- |
| Azure Synapse | 抽象代价（继承 SQL Server 模型） | 否 | 是 | -- |
| Vertica | 抽象代价 | 部分 | 是 | -- |
| SAP HANA | 抽象代价 | 部分 | 是 | -- |
| Teradata | AMP 步骤代价（spool / CPU / I/O） | 部分 | 是 | -- |
| Netezza | 抽象代价 | 否 | 是 | -- |
| DuckDB | 代价估算（行数为主） | 否 | 仅 EXPLAIN ANALYZE 显示耗时 | 向量化+内存为主 |
| ClickHouse | 无传统代价模型 | 否 | EXPLAIN PIPELINE / SYNTAX | 依赖规则 + 向量化估算 |
| Trino | 抽象代价（CBO 可选） | 是（`optimizer.*`） | 是（Cost-based EXPLAIN） | -- |
| Presto | 抽象代价 | 是 | 是 | -- |
| Spark SQL | 抽象代价（CBO） | 是（`spark.sql.cbo.*`） | 是（EXPLAIN COST） | -- |
| Hive | 抽象代价（Calcite） | 是 | 是（EXPLAIN COST） | LLAP 增强 |
| Impala | 抽象代价 | 部分 | 是 | -- |
| Flink SQL | 抽象代价（Calcite） | 是 | 是 | -- |
| Drill | 抽象代价（Calcite） | 部分 | 是 | -- |
| Dremio | 抽象代价（Calcite） | 是 | 是 | -- |
| StarRocks | 抽象代价 | 是 | 是 | CBO 成熟度高 |
| Doris | 抽象代价 | 是 | 是 | -- |
| SingleStore (MemSQL) | 抽象代价 | 部分 | 是 | -- |
| MonetDB | 无传统代价模型 | 否 | 是（MAL 计划） | 列存 + 自适应 |
| QuestDB | 无传统代价模型 | 否 | 否 | 时序简化 |
| InfluxDB (IOx) | 抽象代价 | 部分 | 是 | Arrow/DataFusion |
| Materialize | 抽象代价 | 部分 | 是 | 增量视图 |
| RisingWave | 抽象代价 | 部分 | 是 | 流优化器 |
| Yellowbrick | 抽象代价 | 部分 | 是 | -- |
| Firebolt | 抽象代价 | 否 | 是 | -- |
| Exasol | 抽象代价 | 否 | 是 | -- |
| CrateDB | 抽象代价 | 否 | 是 | -- |
| TimescaleDB | 继承 PG 代价 | 是 | 是 | -- |

> 统计：约 30 个引擎暴露"代价"数字给用户；约 20 个引擎允许调整代价常量；仅 5 个引擎（PostgreSQL 系、MySQL、TiDB、Spark、Trino）提供了系统化、可配置的代价常量集合。

## EXPLAIN 中的代价单位对比

不同引擎 EXPLAIN 输出的 "cost" 数字含义不同：

| 引擎 | EXPLAIN 字段 | 单位含义 | 示例输出 |
|------|------------|---------|---------|
| PostgreSQL | `(cost=X.XX..Y.YY rows=N width=W)` | 启动代价..总代价，1.0 ≈ 顺序读一个 8KB 页 | `Seq Scan ... (cost=0.00..155.00 rows=10000 width=4)` |
| MySQL | `"cost_info": {"read_cost": X, "eval_cost": Y}` | 基于 `mysql.engine_cost` 折算 | `"read_cost": "1015.00"` |
| Oracle | `Cost` 列 | 单块 I/O 个数 × sreadtim 时间 | `Cost (%CPU): 3 (0)` |
| SQL Server | `EstimateCPU`, `EstimateIO`, `SubtreeCost` | 抽象单位（历史上约 1 秒 = 1） | `EstimatedSubtreeCost="0.0032831"` |
| DB2 | `Total Cost` | timerons（= sreadtim + CPU time 单位） | `Total Cost: 7.84 timerons` |
| TiDB | `estRows`, `estCost` | 归一化分数 | `estRows: 10000.00 estCost: 7821.50` |
| Trino | `CPU: X, Memory: Y, Network: Z` | 代价分解（`EXPLAIN ... TYPE IO/DISTRIBUTED`） | `{cpu=1.23M, memory=0, network=0}` |
| Spark SQL | `EXPLAIN COST` 输出逻辑计划统计 | 统计量（非单一代价） | `Statistics(sizeInBytes=1.2 GiB)` |
| BigQuery | 账单字节 / slots-ms（执行后） | 扫描字节 + 计算时间 | dry-run: `"totalBytesProcessed": "1073741824"` |
| Snowflake | Query Profile（执行后） | credits + bytes scanned | Profile 页展示百分比分解 |
| ClickHouse | EXPLAIN 不输出代价 | -- | 仅输出计划结构 |

要点：PostgreSQL 的代价是一个双值元组（startup..total，分别表示返回第一行的代价和返回全部行的代价）；Oracle 的 Cost 在大多数版本下会进一步换算成 "elapsed time" 的估算（看 Time 列）；SQL Server 的 SubtreeCost 并不对应具体时间，只是历史兼容性单位。

## PostgreSQL: 代价常量的标准参照系

### 代价常量默认值

```sql
-- PostgreSQL 默认代价常量 (postgresql.conf 或 SET 可动态调整)
SHOW seq_page_cost;         -- 1.0  (基准: 顺序读一个 8KB 页)
SHOW random_page_cost;      -- 4.0  (随机 I/O 是顺序 I/O 的 4 倍)
SHOW cpu_tuple_cost;        -- 0.01 (处理一个元组的 CPU 代价)
SHOW cpu_index_tuple_cost;  -- 0.005 (处理一个索引元组的 CPU 代价)
SHOW cpu_operator_cost;     -- 0.0025 (执行一个操作符/函数的 CPU 代价)
SHOW parallel_tuple_cost;   -- 0.1  (并行进程间传递一行的代价)
SHOW parallel_setup_cost;   -- 1000 (启动并行 workers 的固定代价)
SHOW jit_above_cost;        -- 100000 (代价超过此值时启用 JIT)
SHOW effective_cache_size;  -- 4GB (操作系统 + shared_buffers 预估大小)
```

### 代价常量的物理含义

```
约定: seq_page_cost = 1.0 为基准单位 "读一个顺序页的成本".
其余常量均以此为参照系:

  random_page_cost = 4.0
    -> 读一个随机页 ≈ 读 4 个顺序页
    -> HDD 上随机 I/O 平均 5-10ms, 顺序 ~0.1-1ms, 比值 5-50 倍
    -> PostgreSQL 取 4.0 是 HDD 时代的保守估计 (考虑 OS 缓存)

  cpu_tuple_cost = 0.01
    -> 处理一行 (解析记录头, 可见性检查) ≈ 读一个顺序页的 1%
    -> 8KB 页存 ~100 行 -> 处理一页的行代价 = 100 * 0.01 = 1.0
    -> 即: 读一页的 I/O 代价 ≈ 处理页内所有行的 CPU 代价

  cpu_index_tuple_cost = 0.005
    -> 处理一个索引元组 ≈ 处理一行的一半
    -> 索引元组更紧凑, 可见性检查更简单

  cpu_operator_cost = 0.0025
    -> 执行一个操作符 (如比较 `=`, 算术 `+`) ≈ 处理一行的 1/4
    -> WHERE x = 5 AND y > 10 会产生 2 * cpu_operator_cost
```

### 全表扫描代价公式推导

```
估算 SELECT * FROM t WHERE x = 5 的代价 (表 10000 行, 1000 页):

  seq_scan_cost  = seq_page_cost * pages
                 = 1.0 * 1000 = 1000

  cpu_row_cost   = cpu_tuple_cost * rows + cpu_operator_cost * rows * n_predicates
                 = 0.01 * 10000 + 0.0025 * 10000 * 1
                 = 100 + 25 = 125

  total          = 1000 + 125 = 1125

EXPLAIN 输出:
  Seq Scan on t  (cost=0.00..1125.00 rows=... width=...)
```

### 索引扫描代价推导

```
估算 SELECT * FROM t WHERE x = 5 (idx_x 存在, 选择性 1%):

  -- 索引树遍历 (小量随机 I/O)
  index_descent = random_page_cost * log2(index_pages)
                = 4.0 * log2(50) = 22.6

  -- 索引页扫描 (选择性 1% -> 10 行 -> ~1 个索引页, 随机)
  index_scan    = random_page_cost * index_pages_read + cpu_index_tuple_cost * rows
                = 4.0 * 1 + 0.005 * 100 = 4.5

  -- 回表 (100 行, 最坏每行一次随机 I/O)
  heap_fetch    = random_page_cost * rows
                = 4.0 * 100 = 400

  -- CPU 过滤
  cpu_filter    = (cpu_tuple_cost + cpu_operator_cost) * rows
                = 0.0125 * 100 = 1.25

  total         = 22.6 + 4.5 + 400 + 1.25 ≈ 428

EXPLAIN 输出:
  Index Scan using idx_x on t  (cost=0.29..428.00 rows=100 width=...)

对比全表扫描 1125 vs 索引 428: 优化器会选索引.
```

### 代价常量调优（SSD 场景）

```sql
-- 场景: 数据库全部在 NVMe SSD 上, shared_buffers 足够大
-- 默认 random_page_cost = 4.0 太悲观, 会错误地避开索引

-- 推荐调整 (PostgreSQL 官方 Wiki 建议):
SET random_page_cost = 1.1;        -- SSD 上随机 vs 顺序几乎持平
-- 或
SET random_page_cost = 1.5;        -- 混合负载, 保守一点

-- 其他 SSD 调优:
SET effective_cache_size = '16GB'; -- 告诉优化器 OS 缓存多大
SET effective_io_concurrency = 200;-- SSD 支持高并发 I/O (HDD 用 2)

-- 云数据库特定场景:
-- AWS EBS gp3: random_page_cost ≈ 1.1-1.5
-- AWS EBS io2: random_page_cost ≈ 1.0-1.1
-- Azure Premium SSD: random_page_cost ≈ 1.1
-- 本地 NVMe: random_page_cost ≈ 1.0 (顺序随机几乎无差别)

-- 注意: 仅仅调整 random_page_cost 就可能让索引使用率提升 20-30%
-- 但过低也可能导致 "索引爆炸": 即使全表扫描更快, 优化器仍选索引
```

### 何时应该调整 PostgreSQL 代价常量

```
调整 random_page_cost:
  必须: SSD/NVMe 存储 + 数据集远大于 shared_buffers (I/O 为主)
  不必要: 数据集完全在内存 (all_in_memory 已接近 seq_page_cost)
  参考值: HDD 4.0, SATA SSD 2.0, NVMe SSD 1.1, 全内存 1.0

调整 cpu_tuple_cost:
  场景: CPU 密集型查询 (大量聚合/排序/复杂表达式)
  方向: CPU 相对 I/O 更贵时调高 (如高主频 CPU + 慢盘)
  实际: 很少需要调整, 默认值经过多年验证

调整 effective_cache_size:
  必须: 这是优化器估算重复访问折扣的唯一输入
  建议: 设置为 shared_buffers + OS 文件缓存总量的 50-75%
  影响: 值越大, 优化器越倾向索引 + Nested Loop

调整 parallel_setup_cost / parallel_tuple_cost:
  场景: 启用并行查询后发现小表也被并行化, 反而更慢
  方向: 调高 parallel_setup_cost 阻止小查询并行化
```

## MySQL: 从硬编码到可配置（8.0+）

### 8.0 之前的硬编码代价

```
MySQL 5.7 及之前, 代价常量在源码中硬编码:
  - ROW_EVALUATE_COST = 0.2 (处理一行的 CPU 代价)
  - DISK_TEMPTABLE_READ_COST = 20.0
  - DISK_TEMPTABLE_CREATE_COST = 20.0
  - 等等

修改需要重新编译 MySQL, 对用户完全不可调.
优化器做出的糟糕决策无法通过参数修复.
```

### 8.0+ 的 mysql.server_cost 和 mysql.engine_cost

```sql
-- 服务端代价常量 (跨引擎共享)
SELECT * FROM mysql.server_cost;
/*
+------------------------------+------------+
| cost_name                    | cost_value |
+------------------------------+------------+
| disk_temptable_create_cost   | 20.000000  |
| disk_temptable_row_cost      | 0.500000   |
| key_compare_cost             | 0.05       |
| memory_temptable_create_cost | 1.000000   |
| memory_temptable_row_cost    | 0.100000   |
| row_evaluate_cost            | 0.1        |
+------------------------------+------------+
*/

-- 引擎特定代价常量 (InnoDB, MyISAM 等独立)
SELECT * FROM mysql.engine_cost;
/*
+-------------+-------------+------------------------+------------+
| engine_name | device_type | cost_name              | cost_value |
+-------------+-------------+------------------------+------------+
| default     |           0 | io_block_read_cost     |   1.000000 |
| default     |           0 | memory_block_read_cost |   0.250000 |
+-------------+-------------+------------------------+------------+
*/
```

### MySQL 代价常量的含义与调优

```sql
-- 单位约定: io_block_read_cost = 1.0 为基准 (读一个磁盘块的代价)
-- 其他常量均相对于这个基准

-- 调整步骤:
-- 1. 修改代价表
UPDATE mysql.server_cost SET cost_value = 0.05
  WHERE cost_name = 'row_evaluate_cost';

-- 2. 刷新优化器缓存 (否则不生效!)
FLUSH OPTIMIZER_COSTS;

-- 3. 新建立的 session 才会使用新代价
-- 现有 session 需要重连

-- SSD 场景推荐:
UPDATE mysql.engine_cost SET cost_value = 0.5
  WHERE cost_name = 'io_block_read_cost';
UPDATE mysql.engine_cost SET cost_value = 0.25
  WHERE cost_name = 'memory_block_read_cost';
FLUSH OPTIMIZER_COSTS;
```

### MySQL EXPLAIN 中的代价

```sql
-- 传统 EXPLAIN 不显示代价数字
EXPLAIN SELECT * FROM orders WHERE customer_id = 100;

-- EXPLAIN FORMAT=JSON 显示详细代价
EXPLAIN FORMAT=JSON SELECT * FROM orders WHERE customer_id = 100;
/*
{
  "query_block": {
    "select_id": 1,
    "cost_info": {
      "query_cost": "10.50"       -- 总查询代价
    },
    "table": {
      "table_name": "orders",
      "access_type": "ref",
      "cost_info": {
        "read_cost": "1.10",      -- I/O 读取代价
        "eval_cost": "0.50",      -- 行处理 CPU 代价
        "prefix_cost": "1.60",    -- 到该操作为止的累积代价
        "data_read_per_join": "800"
      }
    }
  }
}
*/

-- EXPLAIN ANALYZE (8.0.18+) 显示实际代价和执行时间
EXPLAIN ANALYZE SELECT * FROM orders WHERE customer_id = 100;
-- -> Index lookup on orders using idx_cust (customer_id=100)
--    (cost=1.60 rows=5) (actual time=0.04..0.15 rows=3 loops=1)
```

## Oracle: 系统统计 + 索引代价调整因子

### Oracle 代价单位

```
Oracle 10g+ 的 CBO 使用 "单块 I/O 时间" 作为基准:

代价公式 (简化):
  Cost = (sr * sreadtim + mr * mreadtim + CPUCycles/(cpuspeed * sreadtim)) / sreadtim

变量含义:
  sr        = 单块读次数 (single-block reads)
  mr        = 多块读次数 (multi-block reads)
  sreadtim  = 单块读平均时间 (ms), 默认约 10
  mreadtim  = 多块读平均时间 (ms), 默认约 26
  cpuspeed  = CPU 每秒百万次运算数 (MHz)

实际含义: Cost = 预计总时间 / 单块读时间
  -> Cost 数字可以理解为 "相当于多少次单块 I/O"
```

### 收集系统统计

```sql
-- 收集系统统计 (让优化器知道实际硬件特性)
BEGIN
  DBMS_STATS.GATHER_SYSTEM_STATS(gathering_mode => 'NOWORKLOAD');
END;
/

-- 查看收集的值
SELECT pname, pval1, pval2 FROM sys.aux_stats$;
/*
PNAME            PVAL1       PVAL2
---------------- ----------- -----------
SREADTIM         9.634
MREADTIM         25.463
CPUSPEEDNW       2340
IOSEEKTIM        10
IOTFRSPEED       4096
MBRC             8
*/

-- 启用工作负载统计 (收集一段时间)
BEGIN
  DBMS_STATS.GATHER_SYSTEM_STATS(gathering_mode => 'START');
  -- ... 运行典型负载 30 分钟 ...
  DBMS_STATS.GATHER_SYSTEM_STATS(gathering_mode => 'STOP');
END;
/
```

### optimizer_index_cost_adj

```sql
-- optimizer_index_cost_adj (10..10000, 默认 100)
-- 含义: 索引扫描代价乘以此百分比
-- 100 = 不调整 (默认), 50 = 索引代价减半 (更倾向索引), 200 = 索引代价翻倍

SHOW PARAMETER optimizer_index_cost_adj;

-- 场景: OLTP, 大量短查询, 默认值导致优化器选全表扫描过多
ALTER SYSTEM SET optimizer_index_cost_adj = 30;
-- 索引代价减到原来的 30%, 优化器更积极使用索引

-- 场景: OLAP, 大量聚合, 应避免回表
ALTER SYSTEM SET optimizer_index_cost_adj = 150;
-- 索引代价增到 150%, 优化器倾向全表扫描 + Hash Join

-- 相关参数:
-- optimizer_index_caching: 索引缓存命中率 (0-100), 默认 0
-- 设为 90 表示假设 90% 索引块在缓存, 进一步降低索引代价
```

### db_file_multiblock_read_count

```sql
-- 控制全表扫描时单次 I/O 读取的块数
SHOW PARAMETER db_file_multiblock_read_count;
-- 默认由 Oracle 自动调整 (11g+), 通常 8-128

-- 影响:
-- 值越大 -> 多块读代价 (mr) 越低 -> 全表扫描代价越低 -> 优化器更倾向全扫描
-- 值越小 -> 全表扫描代价越高 -> 优化器更倾向索引扫描

-- 典型场景:
-- OLTP: 4-8 (避免优化器过度倾向全表扫描)
-- OLAP: 32-128 (鼓励全表扫描 + Hash Join)
-- 数据仓库: 128 (最大化吞吐)
```

### EXPLAIN PLAN 中的代价显示

```sql
EXPLAIN PLAN FOR
SELECT * FROM orders o JOIN customers c ON o.customer_id = c.id
 WHERE c.region = 'APAC';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
/*
-------------------------------------------------------------------------------
| Id | Operation          | Name      | Rows  | Bytes | Cost (%CPU) | Time   |
-------------------------------------------------------------------------------
|  0 | SELECT STATEMENT   |           |  1000 | 65000 | 120  (10)   |00:00:02|
|  1 |  HASH JOIN         |           |  1000 | 65000 | 120  (10)   |00:00:02|
|  2 |   TABLE ACCESS FULL| CUSTOMERS |   500 | 15000 |   5   (0)   |00:00:01|
|  3 |   TABLE ACCESS FULL| ORDERS    | 10000 | 350K  | 110   (5)   |00:00:02|
-------------------------------------------------------------------------------

Cost = 120 表示总代价相当于 120 次单块 I/O (按 sreadtim=10ms 约 1.2 秒)
(%CPU) 表示 CPU 占代价的比例
Time 是推算的实际耗时
*/
```

## SQL Server: 抽象的 Subtree Cost

### 代价单位的历史由来

```
SQL Server 7.0 (1998) 引入 Cost-Based Optimizer.
当时的"单位"约定: 1 Cost Unit ≈ 在 2000 年左右的 Pentium II / 标准硬盘上,
完成相应工作所需的秒数.

此后 20 多年硬件大幅变化, 但 SQL Server 从未更新这个基准:
  - Cost = 1.0 不再等于 1 秒 (现代硬件快得多)
  - Cost 数字只是相对比较用, 绝对值无物理意义
  - 微软官方文档直接说 "Cost is a unitless number"
```

### EXPLAIN 中的代价分解

```sql
SET SHOWPLAN_XML ON;
GO

SELECT * FROM Sales.SalesOrderDetail
 WHERE ProductID = 707;

/* XML 输出的关键字段:
<RelOp NodeId="0"
       EstimateRows="188.292"
       EstimatedRowsRead="188.292"
       EstimateIO="0.003125"          -- I/O 代价
       EstimateCPU="0.0001812"        -- CPU 代价
       EstimateRebinds="0"
       EstimateRewinds="0"
       EstimatedExecutionMode="Row"
       AvgRowSize="137"
       EstimatedTotalSubtreeCost="0.0033062"    -- 子树总代价 (I/O + CPU + 子节点)
       TableCardinality="121317"
       ...
*/
```

### 代价常量硬编码，不可调

```
SQL Server 的代价模型参数全部硬编码在 qoptiprim.cpp / qooptim.cpp:

  IO Cost:
    CostRandomPage   = 0.003125          (1 / 320, 即 ~320 页/秒随机 I/O)
    CostSeqPage      = 0.000740740741    (1 / 1350, 即 ~1350 页/秒顺序 I/O)
    比值: 约 4.2 倍 (与 PG 的 4.0 接近)

  CPU Cost:
    CostCPUForRow    = 0.000001          (处理一行)
    CostCPUForHash   = 0.000001          (哈希一行)

这些数字直接对应 2000 年的硬件性能, 2026 年的实际速度快 100 倍以上.
但由于优化器只做相对比较, 参数绝对值过时不影响计划选择.
```

### 用户可用的"准调优"手段

```sql
-- 无法修改代价常量, 但可以:

-- 1. Query Hint 强制计划
SELECT * FROM orders WITH (INDEX(idx_cust))
 WHERE customer_id = 100;

SELECT * FROM orders
 WHERE customer_id = 100 OPTION (USE HINT ('FORCE_LEGACY_CARDINALITY_ESTIMATION'));

-- 2. 基数估算模型切换
ALTER DATABASE MyDb SET COMPATIBILITY_LEVEL = 130;  -- 使用旧 CE 模型
-- 或会话级:
DBCC TRACEON (9481);  -- 切换回 2012 CE

-- 3. Plan Guide 固定计划
EXEC sp_create_plan_guide
    @name = N'FixPlanForQuery',
    @stmt = N'SELECT * FROM orders WHERE customer_id = @id',
    @type = N'SQL',
    @hints = N'OPTION (OPTIMIZE FOR (@id = 100))';

-- 4. Query Store 强制执行计划
EXEC sp_query_store_force_plan @query_id = 123, @plan_id = 456;
```

### 为什么 SQL Server 不开放代价常量

```
微软的设计哲学 (根据公开技术博客和 SIGMOD 论文):

1. 抽象单位降低用户复杂度:
   - 用户不需要理解 "什么是顺序 I/O 时间"
   - EXPLAIN 中的代价只需要知道 "更小更好"

2. 硬编码防止误调:
   - 放开参数后 80% 的 DBA 会调错
   - 不如限制选项, 让优化器自己处理

3. 用 Query Hint / Plan Guide 替代:
   - 精确控制单个查询的计划
   - 不影响其他查询的全局最优

4. 自动调优 (Automatic Tuning):
   - SQL Server 2017+ 引入自动索引推荐、强制上一个好计划
   - 机器学习替代手工调参
```

## 云数仓的代价单位：与账单挂钩

### BigQuery: slots-millisecond + bytes billed

```sql
-- BigQuery 的代价模型完全由定价驱动:
-- 1. On-demand: 按扫描字节计费 ($6.25 / TB)
-- 2. Flat-rate: 按 slot-hour 计费 (slot = 虚拟 CPU)

-- Dry-run: 不执行查询, 只估算代价
-- bq query --dry_run --use_legacy_sql=false '
--   SELECT ... FROM my_dataset.orders WHERE date >= "2024-01-01"
-- '
-- 输出: Total bytes processed: 10.5 GB
--       Total bytes billed:    10.5 GB
--       Estimated cost:        $0.065

-- 执行后的代价 (Query Profile):
-- Slot-time consumed: 152.3 seconds
-- Total shuffle bytes: 2.1 GB
-- Stages: 7 (含 Parse/Plan/Execute)

-- 优化器视角:
-- - 没有传统的 "seq_page_cost" 概念
-- - 以 "bytes scanned × slots × time" 为代价
-- - 用户不能调整代价常量, 只能通过分区/聚类减少扫描量
```

### Snowflake: Credits + Bytes Scanned

```
Snowflake 代价 = warehouse 大小 × 运行时间 + 数据存储 + 数据传输

Warehouse 档位 (Credits/hour):
  X-Small:  1
  Small:    2
  Medium:   4
  Large:    8
  X-Large: 16
  (以此类推, 每档翻倍)

优化器的"代价单位" = bytes scanned (micropartitions pruned)
  - 不暴露给用户
  - Query Profile 显示各阶段的 bytes scanned + time
  - 用户调优方向: 减少扫描字节 (分区裁剪, cluster key)

没有传统的 "cost constant" 概念.
所有优化决策由引擎自动完成, 用户不可干预代价模型.
```

### Athena / Presto 云版: Bytes Scanned

```sql
-- Athena 按扫描字节计费 ($5 / TB)
-- 优化器的隐式代价 = bytes scanned

-- 查询执行后可查看:
SELECT * FROM "information_schema"."query_runtime_statistics"
 WHERE query_id = 'abc123';
/*
bytes_scanned: 1073741824 (1 GB)
execution_time: 2.3 seconds
data_processed_bytes: 1073741824
*/

-- Athena 优化器的目标: 最小化 bytes scanned
-- 调优手段: 分区, ORC/Parquet 列裁剪, 谓词下推
```

## ClickHouse: 没有传统代价模型

### 向量化 + 规则驱动

```
ClickHouse 优化器不使用传统 CBO:
  - 不计算 "代价" 数字
  - 基于规则选择计划 (RBO)
  - 向量化执行 + SIMD 使得大多数操作同数量级快
  - 存储层负责数据裁剪 (primary key skip, partition prune, data skipping index)

设计理念: 与其花时间做复杂代价估算, 不如让执行器足够快 ("don't optimize, just execute").
```

### EXPLAIN 输出

```sql
-- ClickHouse 的 EXPLAIN 不输出 cost 数字
EXPLAIN SELECT count() FROM events WHERE event_date >= '2024-01-01';
/*
(Expression)
ExpressionTransform
  (Aggregating)
  AggregatingTransform
    (Expression)
    ExpressionTransform
      (ReadFromMergeTree)
      MergeTreeInOrder 0 -> 1
*/

-- 详细信息需要 EXPLAIN PIPELINE / EXPLAIN ESTIMATE
EXPLAIN ESTIMATE SELECT count() FROM events WHERE event_date >= '2024-01-01';
/*
database: default
table: events
parts: 12
rows: 45230000
marks: 5523
*/
-- 没有 "cost" 列, 只有估算的 parts/rows/marks 数量
```

### 何时引入代价模型

```
ClickHouse 社区讨论 (截至 2024):
  - JOIN 重排序需要 CBO (已有 allow_experimental_analyzer + optimize_read_in_order 等部分功能)
  - 复杂子查询需要 CBO
  - 但标准 SQL benchmark (TPC-H, TPC-DS) 上 ClickHouse 的规则优化器已经足够

趋势: 逐步引入轻量级代价估算, 但不会发展成 PG/Oracle 那样的完整 CBO.
```

## DuckDB: 行数为主的轻量代价

```
DuckDB 的优化器:
  - 主要基于行数估算做 JOIN 顺序优化
  - 无 "cost constant" 暴露
  - 向量化执行 + 内存为主, 大多数操作代价可忽略
  - EXPLAIN 不显示 cost, 只显示 cardinality 估计

EXPLAIN ANALYZE 显示实际执行时间, 但事前代价估算对用户不可见.
```

### EXPLAIN ANALYZE 输出示例

```sql
EXPLAIN ANALYZE SELECT count(*) FROM orders o JOIN lineitem l ON o.o_orderkey = l.l_orderkey;
/*
┌─────────────────────────────────────┐
│┌───────────────────────────────────┐│
││    Query Profiling Information    ││
│└───────────────────────────────────┘│
└─────────────────────────────────────┘
HASH_JOIN
  Join Type: INNER
  Condition: o_orderkey = l_orderkey
  Cardinality: 60000000
     │     ├──────────
     │     │        Time: 1.23s
     │     │        ...
*/
-- 没有 "cost", 只有 Cardinality 和实际 Time
```

## TiDB: 归一化代价与并行度感知

### 代价常量

```sql
-- TiDB 5.0+ 的代价常量 (session 变量)
SHOW VARIABLES LIKE 'tidb_opt_%_factor';
/*
| Variable_name                  | Value |
|--------------------------------|-------|
| tidb_opt_cpu_factor            | 3     |
| tidb_opt_copcpu_factor         | 3     |
| tidb_opt_network_factor        | 1     |
| tidb_opt_scan_factor           | 1.5   |
| tidb_opt_desc_factor           | 3     |
| tidb_opt_memory_factor         | 0.001 |
| tidb_opt_disk_factor           | 1.5   |
| tidb_opt_concurrency_factor    | 3     |
| tidb_opt_seek_factor           | 20    |
*/

-- 单位: scan_factor = 1.0 为基准 (扫描一行的代价)
-- network_factor = 1.0: 网络传输一行 = 扫描一行
-- seek_factor = 20: 一次随机定位 = 扫描 20 行
```

### 代价分解公式

```
TiDB 的代价 = TiDB Server 代价 + TiKV/TiFlash 代价 + 网络代价

TableScan cost  = rows * scan_factor
IndexScan cost  = rows * scan_factor + lookup_rows * seek_factor
JOIN cost       = build_rows * cpu_factor + probe_rows * cpu_factor + network_rows * network_factor

EXPLAIN ANALYZE 输出 estCost 和 actTime:
  id           | estRows | estCost  | actRows | actTime
  Projection   |  1.00   | 10.50    |    1    | 2.3ms
    HashJoin   |  1.00   | 10.40    |    1    | 2.1ms
      ...
```

## Spark SQL: CBO 可选 + AQE 自适应

### 代价参数

```sql
-- Spark SQL 的 CBO 默认关闭, 需要显式启用
SET spark.sql.cbo.enabled = true;
SET spark.sql.cbo.joinReorder.enabled = true;
SET spark.sql.statistics.histogram.enabled = true;

-- CBO 代价公式参数:
SET spark.sql.cbo.joinReorder.card.weight = 0.7;  -- 基数权重
-- 代价 = weight * cardinality + (1 - weight) * size
```

### EXPLAIN COST 输出

```sql
EXPLAIN COST
SELECT * FROM orders o JOIN customers c ON o.customer_id = c.id;
/*
== Optimized Logical Plan ==
Join Inner, (customer_id#1 = id#10), Statistics(sizeInBytes=1.5 GB, rowCount=5000000)
:- Filter isnotnull(customer_id#1), Statistics(sizeInBytes=800 MB, rowCount=5000000)
:  +- Relation[...] orders, Statistics(sizeInBytes=800 MB, rowCount=5000000)
+- Filter isnotnull(id#10), Statistics(sizeInBytes=100 MB, rowCount=1000000)
   +- Relation[...] customers, Statistics(sizeInBytes=100 MB, rowCount=1000000)
*/
-- Statistics 显示字节数 + 行数, 而非单一 cost
```

### AQE 覆盖静态代价

```
Spark 3.0+ 的 Adaptive Query Execution (AQE) 会在运行时:
  1. 收集 shuffle 后的真实数据量
  2. 动态切换 JOIN 策略 (Sort Merge -> Broadcast)
  3. 动态合并小 partition (coalesce)

这实际上让静态 CBO 代价模型的重要性降低.
AQE 的决策基于实际运行时统计, 而非事前代价估算.
```

## 关键发现

### 代价模型设计的共识与分歧

```
共识 (所有引擎都做):
  1. 基于统计信息估算输出行数 (cardinality estimation)
  2. 为不同操作分配不同"权重" (I/O 重还是 CPU 重)
  3. 选择总代价最低的计划

分歧 (单位、可调性、透明度):
  - PostgreSQL: 物理量建模 + 可调 + 透明 EXPLAIN
  - SQL Server: 抽象单位 + 不可调 + 相对比较
  - Oracle: 时间建模 + 间接可调 + EXPLAIN 带预估时间
  - 云数仓: 账单单位 + 不可调 + Query Profile 事后展示
  - ClickHouse: 无代价模型 + 规则驱动 + 向量化掩盖差异
```

### 代价常量的默认值是"平均硬件"的遗产

```
PostgreSQL 默认:
  seq_page_cost = 1.0, random_page_cost = 4.0
  -> 基于 2000 年代 HDD 的测量, 2026 年的 NVMe 上过时
  -> 但 PG 团队保持默认值不变, 让用户按硬件显式调整

SQL Server 硬编码:
  CostRandomPage = 0.003125 (来自 Pentium II + 320 IOPS HDD)
  -> 2026 年完全不符合实际硬件
  -> 但由于只做相对比较, 不影响计划选择

教训: 代价模型一旦发布就很难改. 大多数引擎选择"参数化"解决硬件演进, 而非修改默认值.
```

### EXPLAIN 代价可比性

```
同一查询在不同引擎的 cost 数字完全不可比:
  PG:   cost=1125.00 (≈ 1125 个顺序页 I/O)
  MySQL: query_cost=1015.00 (基于 engine_cost 表计算)
  Oracle: Cost=3 (≈ 3 次单块 I/O ≈ 30ms)
  SQL Server: EstimatedSubtreeCost=0.0033 (无单位)
  DB2: 7.84 timerons (内部混合单位)
  BigQuery: 1.5 GB bytes billed ($0.009)

用户跨引擎调优时必须重新学习代价单位, 无法直接复用经验.
```

### 可调性的权衡

```
开放所有代价常量 (PostgreSQL):
  优点: 专业 DBA 可精细调优, 硬件差异可补偿
  缺点: 80% 用户不会调, 少数调错的用户会抱怨引擎

完全不开放 (SQL Server):
  优点: 用户复杂度低, 出问题归因到 hints 即可
  缺点: 无法应对硬件演进, 用户在极端场景下束手无策

折中: 提供少量高层参数 (Oracle optimizer_index_cost_adj):
  优点: 一两个旋钮覆盖 80% 场景
  缺点: 调整粒度粗, 无法精确控制
```

### 代价模型的未来：自适应

```
传统 CBO 的局限:
  - 统计信息收集滞后
  - 复杂查询的基数估算误差极大 (JOIN 多层后可能偏差 1000 倍)
  - 硬件异构场景 (SSD+HDD 混合) 难以建模
  - 云环境下资源动态变化 (noisy neighbor)

自适应方向 (ABO, Adaptive Cost Model):
  - 运行时反馈: Oracle Cardinality Feedback, Spark AQE
  - 机器学习: 用历史执行时间训练代价模型 (Microsoft Learned Cost Model)
  - 主动重新优化: 执行中发现估算偏差大时重新生成计划
  - 从 "预测" 转向 "观察 + 修正"
```

### 对引擎开发者的建议

```
1. 若目标用户是 DBA/性能工程师: 选 PostgreSQL 模式
   - 暴露物理量代价常量
   - EXPLAIN 显示详细代价分解
   - 文档中说明每个常量的含义与调优方向

2. 若目标用户是应用开发者: 选 SQL Server 模式
   - 抽象代价, 不可调
   - 通过 Hints / Plan Guide 精确控制
   - 重点投入自动调优 (indexing advisor, plan forcing)

3. 若目标场景是云服务: 选账单挂钩模式
   - 代价 = bytes scanned × time × resource
   - 不暴露给用户, 而是通过 Query Profile 事后诊断
   - 优化方向: 让用户减少扫描 (分区/聚类) 即自动降低代价

4. 若目标场景是高吞吐分析: 考虑跳过代价模型
   - ClickHouse 证明了规则 + 向量化 + 数据裁剪足够应对大多数 OLAP
   - 省去 CBO 的统计收集和代价估算开销
   - 但 JOIN 重排序等复杂优化仍需代价模型

5. 代价常量的默认值:
   - 不要为"现代 SSD"设默认值, 因为总有用户在 HDD 上跑
   - 不要为"HDD"设默认值, 因为新系统都是 SSD
   - 最佳实践: 默认值保守 (偏向更大的代价常量), 文档引导调优
   - 或提供 "hardware profile" 预设 (SSD profile, NVMe profile)

6. EXPLAIN 的可读性:
   - 分 startup/total 两个数 (PG 风格) 让用户理解 "快出第一行 vs 快出全部"
   - 分 I/O + CPU + 网络三个数 (Oracle / Trino 风格) 让用户定位瓶颈
   - 附带 "relative to seq page cost" 的物理含义, 避免数字神秘化
```

## 参考资料

- PostgreSQL: [Planner Cost Constants](https://www.postgresql.org/docs/current/runtime-config-query.html#RUNTIME-CONFIG-QUERY-CONSTANTS)
- PostgreSQL Wiki: [Tuning Your PostgreSQL Server](https://wiki.postgresql.org/wiki/Tuning_Your_PostgreSQL_Server)
- MySQL: [The MySQL Optimizer Cost Model](https://dev.mysql.com/doc/refman/8.0/en/cost-model.html)
- MySQL: [mysql.server_cost / mysql.engine_cost 系统表](https://dev.mysql.com/doc/refman/8.0/en/optimizer-cost-model.html)
- Oracle: [Understanding Query Optimizer](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgsql/query-optimizer-concepts.html)
- Oracle: [System Statistics and the optimizer_index_cost_adj Parameter](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/OPTIMIZER_INDEX_COST_ADJ.html)
- SQL Server: [Query Processing Architecture Guide](https://learn.microsoft.com/en-us/sql/relational-databases/query-processing-architecture-guide)
- SQL Server: [Showplan Logical and Physical Operators Reference](https://learn.microsoft.com/en-us/sql/relational-databases/showplan-logical-and-physical-operators-reference)
- DB2: [Explain Tables and Timeron Units](https://www.ibm.com/docs/en/db2/11.5?topic=tuning-explain-facility)
- TiDB: [Cost Model](https://docs.pingcap.com/tidb/stable/cost-model)
- TiDB: [Optimizer Hints and System Variables](https://docs.pingcap.com/tidb/stable/system-variables)
- Spark SQL: [Cost-Based Optimizer in Apache Spark 2.2](https://databricks.com/blog/2017/08/31/cost-based-optimizer-in-apache-spark-2-2.html)
- Trino: [Cost-based optimizations](https://trino.io/docs/current/optimizer/cost-based-optimizations.html)
- BigQuery: [Query Pricing and Slots](https://cloud.google.com/bigquery/docs/query-pricing)
- Snowflake: [Credit Consumption](https://docs.snowflake.com/en/user-guide/cost-understanding-overall)
- ClickHouse: [EXPLAIN Statement](https://clickhouse.com/docs/en/sql-reference/statements/explain)
- Selinger, P. et al. "Access Path Selection in a Relational Database Management System" (1979), SIGMOD —— 代价模型的奠基论文
- Lohman, G. "Is Query Optimization a 'Solved' Problem?" (2014), SIGMOD Record —— 代价模型痛点的总结
- Leis, V. et al. "How Good Are Query Optimizers, Really?" (2015), VLDB —— 基数估算误差对代价模型的冲击
