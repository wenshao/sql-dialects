# 选择性估计 (Selectivity Estimation)

优化器会把 JOIN 顺序、索引选择、并行度统统押注在一个数字上：`WHERE` 子句的选择性。这个数字错一个数量级，执行计划就可能慢三个数量级——选择性估计算法因此成为整个 CBO 最脆弱、争议最多、也最容易被忽视的核心环节。

## 为什么选择性估计是优化器的最薄弱环节

选择性（selectivity）是一个介于 `0` 到 `1` 之间的数，表示某个谓词过滤后保留的比例：

```
selectivity(P) = |rows satisfying P| / |total rows|
```

基于这个数，优化器推导出行数估计：

```
rows_out = rows_in × selectivity(P)
```

行数估计驱动了优化器的 7 个关键决策：

1. **访问路径选择**：走索引还是全表扫描？
2. **JOIN 顺序**：先 JOIN 哪两张表？
3. **JOIN 算法**：Hash Join、Nested Loop 还是 Merge Join？
4. **JOIN 的 build 侧**：哪一边放到哈希表里？
5. **并行度**：是否启用并行，启多少线程？
6. **内存分配**：Hash Table、Sort、Aggregation 的内存预分配？
7. **分布式 shuffle**：Broadcast 还是 Shuffle-Hash？

所有现代优化器的研究都一致指出：**在相对误差意义下，选择性估计仍然是 CBO 最大的误差来源**。Leis 等 2015 年 VLDB 论文《How Good Are Query Optimizers, Really?》以 JOB（Join Order Benchmark）系统化复现了这一结论——当查询里链接四到八张大表时，主流商业数据库的中间结果行数估计最大偏差可达 10^4 倍。Neumann 在后续工作中也指出，只要估计误差在 JOIN 之间累积，整个计划选择就可能失控。

### 为什么这么难

1. **谓词空间是指数级的**：任意列组合 × 任意值 × 任意操作符，不可能完全枚举
2. **数据分布是未知且变化的**：冷启动 / 写入 / 删除都会扰动统计信息
3. **列之间不独立**：`city` 和 `zipcode`、`country` 和 `language`、`user_id` 和 `email` 都强相关
4. **直方图有固定的桶数上限**：SQL Server 201 桶、Oracle 默认 254 桶、PostgreSQL 默认 100 桶
5. **字符串谓词无法直方图化**：`LIKE '%xyz%'` 不可能用数值桶表达
6. **参数化查询缺乏具体值**：`PreparedStatement` 只能用启发式估计
7. **执行反馈闭环缺失**：大多数优化器不读取历史执行的实际行数

### 错误代价的非对称性

选择性估计错 2 倍和错 100 倍，对执行计划的影响并不成比例：

```
场景 A: 估计 100 行 vs 实际 200 行
  -> 选择 Nested Loop, 实际执行 200 次探测, 影响有限

场景 B: 估计 100 行 vs 实际 1000 万行
  -> 选择 Nested Loop + 索引, 实际要回表 1000 万次
  -> 本应 Hash Join 20 秒, 变成 Nested Loop 3 小时
```

这是为什么优化器研究的重点从来不是"让估计更准"，而是"让估计错误时不要产生灾难性计划"（robust query optimization）。

## 没有 SQL 标准

ISO/IEC 9075 从未定义过选择性估计，不同引擎的算法是完全私有且互不兼容的：

- **PostgreSQL** 的算法位于 `src/backend/utils/adt/selfuncs.c`，约 5000 行 C 代码
- **MySQL 8.0** 的实现分散在 `sql/range_optimizer/` 和 `sql/histograms/`
- **Oracle** 的 CBO 选择性代码从不公开
- **SQL Server** 的 CardinalityEstimator 2014 做过一次重大重写
- **DB2** 的 `db2expln` 输出选择性，但算法不公开

引擎之间的差异远大于它们的共性。甚至同一引擎的不同版本之间，选择性估计算法也可能大幅改动——SQL Server 2014、Oracle 12c、TiDB v5.1 都是明显的分水岭。

## 支持矩阵

### 单列等值选择性估计方法

| 引擎 | MCV 命中 | NDV 回退 | 默认公式 | 参数化查询处理 |
|------|---------|---------|---------|--------------|
| PostgreSQL | 查 `most_common_vals` | `1 / n_distinct` | `eqsel()` | 扣除 MCV 后均匀 |
| MySQL 8.0.3+ | 查 singleton 直方图 | `1 / index_cardinality` | range optimizer | 索引统计 + 直方图 |
| MariaDB | 直方图 bucket | `1 / index_cardinality` | EITS | histogram_type |
| SQLite | -- | `1 / sqlite_stat1` | stat1 | 固定估计 |
| Oracle | frequency / hybrid | `density` | `DENSITY` | 用 `DENSITY` 或固定 5% |
| SQL Server | `EQ_ROWS` | `1 / DENSITY` | DBCC SHOW_STATISTICS | 本地变量 30% 固定 |
| DB2 | 查 frequency 列表 | `1 / COLCARD` | runstats | cardinality feedback |
| Snowflake | 内部 | 内部 | 不公开 | 内部 |
| BigQuery | 内部 | 内部 | 不公开 | 内部 |
| Redshift | 直方图 | NDV | 继承 PG | 继承 PG |
| DuckDB | 有限 | NDV | 基础 | 运行时反馈 |
| ClickHouse | -- | -- | 索引粒度 | 不适用 |
| Trino | -- | NDV | min/max + NDV | 固定估计 |
| Spark SQL | 直方图 | NDV | 3.0+ 等深 | 固定估计 |
| Hive | -- | NDV | 仅 NDV | 固定 |
| Databricks | 直方图 | NDV | Delta 统计 | 固定 |
| Teradata | biased values | NDV | 等深 | 自适应样本 |
| Greenplum | MCV | NDV | 继承 PG | 继承 PG |
| CockroachDB | 直方图 | NDV | `1 / n_distinct` | 固定估计 |
| TiDB | Top-N | NDV | Top-N + histogram | 默认 0.8 或固定 |
| OceanBase | frequency / hybrid | density | 多种自动 | 兼容 Oracle 风格 |
| YugabyteDB | MCV | NDV | 继承 PG | 继承 PG |
| SingleStore | 直方图 | NDV | 等深 | 固定估计 |
| Vertica | 直方图 | NDV | 等深 | 固定估计 |
| Impala | -- | NDV | 仅 NDV | 固定 |
| StarRocks | MCV | NDV | 等深 + MCV | 固定估计 |
| Doris | MCV | NDV | 等深 + MCV | 固定估计 |
| MonetDB | -- | NDV | min/max | 固定 |
| CrateDB | 直方图 | NDV | Lucene | 固定 |
| TimescaleDB | MCV | NDV | 继承 PG | 继承 PG |
| QuestDB | -- | -- | 时序索引 | 不适用 |
| Exasol | 内部 | 内部 | 不公开 | 内部 |
| SAP HANA | 数据统计对象 | NDV | 多种类型 | 自适应 |
| Informix | 分布统计 | NDV | 等深 | 固定 |
| Firebird | -- | 选择性 | `SET STATISTICS` | 索引选择性 |
| H2 | -- | NDV | 仅基础 | 固定 |
| HSQLDB | -- | -- | -- | -- |
| Derby | -- | NDV | 基础 | 固定 |
| Amazon Athena | -- | NDV | 继承 Trino | 固定 |
| Azure Synapse | 直方图 | NDV | 继承 SQL Server | 固定 |
| Google Spanner | 内部 | 内部 | 不公开 | 内部 |
| Materialize | -- | -- | 不适用 | 不适用 |
| RisingWave | -- | -- | 不适用 | 不适用 |
| InfluxDB (SQL) | -- | -- | 不适用 | 不适用 |
| DatabendDB | NDV | NDV | 基础 | 固定 |
| Yellowbrick | MCV | NDV | 继承 PG | 继承 PG |
| Firebolt | 内部 | 内部 | 不公开 | 内部 |

> 统计：约 35 个引擎有某种形式的等值选择性估计算法。托管云服务（Snowflake、BigQuery、Firebolt）完全不公开内部实现。流式系统（Materialize、RisingWave、InfluxDB）不适用传统选择性估计。

### 范围选择性估计方法

| 引擎 | 直方图桶内插值 | 跨桶线性累加 | 开放区间外推 | 列相关性考虑 |
|------|---------------|--------------|-------------|-------------|
| PostgreSQL | 线性插值 | 是 | 边界桶外推 | 部分 |
| MySQL 8.0 | 线性插值 | 是 | clamp 到 min/max | 否 |
| MariaDB | 线性插值 | 是 | clamp | 否 |
| Oracle | 线性插值 + 端点频率 | 是 | 端点频率修正 | 扩展统计 |
| SQL Server | `RANGE_ROWS` + `DISTINCT_RANGE_ROWS` | 是 | 外推（2014 CE 起改进） | 否（独立假设） |
| DB2 | 分位数 + 插值 | 是 | 边界外推 | 扩展统计 |
| TiDB | 等深桶插值 | 是 | Top-N 扣除 | 否 |
| CockroachDB | 等深桶插值 | 是 | clamp | 否 |
| Trino | min/max 线性 | 是 | clamp | 否 |
| Spark SQL | 等深桶插值 | 是 | clamp | 否 |
| ClickHouse | 稀疏索引粒度 | 部分 | 不适用 | 主键前缀 |
| StarRocks | 等深插值 | 是 | clamp | 否 |
| Doris | 等深插值 | 是 | clamp | 否 |

### LIKE 模式选择性估计方法

| 引擎 | 前缀 LIKE (`'abc%'`) | 后缀 LIKE (`'%abc'`) | 中缀 LIKE (`'%abc%'`) | 算法 |
|------|---------------------|----------------------|------------------------|------|
| PostgreSQL | 字符串直方图边界分析 | 固定估计 | 固定估计 + 长度启发 | `text_sel` |
| MySQL | 前缀长度启发 | 固定估计 | 固定估计 | range optimizer |
| MariaDB | histogram 前缀范围 | 固定估计 | 固定估计 | EITS |
| Oracle | 密度 + 前缀 | 固定 5% | 固定 5% | 密度 |
| SQL Server | 直方图前缀 + 估计 | 固定 9% | 固定 9% | 新 CE 2014 调整 |
| DB2 | 前缀 + 分位数 | 固定 | 固定 | runstats |
| TiDB | 前缀 + 直方图 | 固定估计 | 固定估计 | 选择性启发 |
| Trino | min/max 前缀 | 固定 | 固定 | 统计不足 |
| Spark SQL | 前缀统计 | 固定 | 固定 | 基础启发 |
| CockroachDB | 直方图前缀 | 固定 | 固定 | 字符串直方图 |

### BETWEEN / IN 选择性估计方法

| 引擎 | `BETWEEN a AND b` | `IN (v1, ..., vn)` | `<>`/`!=` | IS NULL |
|------|---------------------|---------------------|------------|---------|
| PostgreSQL | 直方图累加 | 各值 `eqsel` 之和 | `1 - eqsel` | `null_frac` |
| MySQL 8.0 | 直方图累加 | 各值之和 | `1 - eqsel` | `NULL_FRAC` |
| Oracle | 直方图累加 | 各值之和 | `1 - density` | 列统计 `NULL_CNT` |
| SQL Server | 直方图累加 | 各值之和（限额） | `1 - eqsel` | 直方图 |
| DB2 | 分位数累加 | 各值之和 | `1 - eqsel` | runstats |
| TiDB | 直方图累加 | 各值之和 | `1 - eqsel` | 列统计 |
| CockroachDB | 直方图累加 | 各值之和 | `1 - eqsel` | 列统计 |
| Trino | min/max 线性 | `min(n, NDV)/NDV` | `1 - 1/NDV` | min/max/NDV |
| Spark SQL | 直方图累加 | 各值之和 | `1 - eqsel` | 列统计 |

### 多谓词组合（AND / OR）

| 引擎 | AND 独立假设 | AND 相关修正 | OR 容斥原理 | 扩展统计 |
|------|-----------------|--------------|-------------|----------|
| PostgreSQL | 是（默认） | `CREATE STATISTICS` (10+) | `S1 + S2 - S1*S2` | 依赖度 / NDV / MCV |
| MySQL 8.0 | 是 | -- | `S1 + S2 - S1*S2` | -- |
| MariaDB | 是 | -- | `S1 + S2 - S1*S2` | -- |
| Oracle | 是 | 扩展统计 | `S1 + S2 - S1*S2` | 多列 + 表达式 |
| SQL Server LegacyCE | 是（纯独立） | -- | `S1 + S2 - S1*S2` | 多列统计 |
| SQL Server NewCE 2014 | 指数退避 | 多列统计 | 改进的 OR | 多列 |
| DB2 | 是 | column group stats | 标准 | RUNSTATS ON COLUMN GROUP |
| Teradata | 是 | 多列 COLLECT | 标准 | `COLLECT STATISTICS ON (a,b)` |
| CockroachDB | 是 | 多列统计 | 标准 | `CREATE STATISTICS ... ON (a,b)` |
| OceanBase | 是 | Oracle 兼容 | 标准 | DBMS_STATS 扩展 |
| TiDB | 是 | -- | 标准 | -- |
| SAP HANA | 是 | 数据统计对象 | 标准 | data statistics object |
| Trino | 是 | -- | 标准 | -- |
| Spark SQL | 是 | -- | 标准 | -- |

> 所有主流引擎默认使用**列独立性假设**计算 AND，即 `sel(A AND B) = sel(A) × sel(B)`。独立性假设是 CBO 选择性估计最大的系统性误差来源。仅 PostgreSQL、Oracle、SQL Server NewCE、DB2、CockroachDB 提供了部分修正机制。

## 各引擎核心算法深度解析

### PostgreSQL：MCV + 直方图 + `eqsel` / `scalarineqsel`

PostgreSQL 的选择性估计集中在 `src/backend/utils/adt/selfuncs.c`，是开源引擎中最清晰的实现。

#### 等值选择性：`var_eq_const`

```
算法 (单列等值 WHERE col = 'X'):

1. 在 pg_stats 的 most_common_vals 数组中查找 'X':
   - 找到: selectivity = most_common_freqs[i]
   - 未找到: 走步骤 2

2. 从 pg_stats 读取 n_distinct:
   - 如果 n_distinct > 0: 绝对 distinct 数
   - 如果 n_distinct < 0: -n_distinct * row_count = distinct 数

3. 计算剩余 distinct 数:
   other_distinct = n_distinct - len(most_common_vals)
   sum_mcv_freq = sum(most_common_freqs)

4. 剩余概率均匀分配:
   selectivity = (1 - sum_mcv_freq - null_frac) / other_distinct

5. 最终 selectivity 经过 clamp 到 [MIN_SELECTIVITY, 1]
```

关键细节：

```sql
-- 查看 pg_stats
SELECT attname, n_distinct, null_frac,
       most_common_vals, most_common_freqs,
       histogram_bounds, correlation
FROM pg_stats
WHERE tablename = 'orders' AND attname = 'status';

-- 例子:
-- n_distinct = 5
-- null_frac = 0.0
-- most_common_vals = {paid, pending, cancelled}
-- most_common_freqs = {0.7, 0.15, 0.08}

-- WHERE status = 'paid'   -> 0.7 (直接查 MCV)
-- WHERE status = 'refunded' (未在 MCV):
--   sum_mcv = 0.93
--   other_distinct = 5 - 3 = 2
--   selectivity = (1 - 0.93 - 0) / 2 = 0.035

-- WHERE status = '不存在的值':
--   走相同公式, 结果 0.035, 严重高估
--   (PostgreSQL 不假设未知值频率为 0)
```

#### 范围选择性：`scalarineqsel` 与直方图桶插值

```
算法 (WHERE col < 'X' 或 col BETWEEN a AND b):

1. histogram_bounds 是等深直方图的 101 个边界点
   每两个相邻边界之间包含大致相同数量的行
   默认 100 个桶

2. 对 col < X:
   - 找到 X 落在第 k 个桶
   - 前 k-1 个桶对应的比例 = (k-1) / bucket_count
   - 在第 k 个桶内线性插值:
     frac_in_bucket = (X - bound[k-1]) / (bound[k] - bound[k-1])
   - 累加: sel = (k - 1 + frac_in_bucket) / bucket_count

3. 扣除 MCV 贡献: 在桶内属于 MCV 的部分要减掉
   （因为 MCV 已经单独计算过）

4. 开放区间外推: 如果 X < bound[0]:
   使用边界桶的密度外推，限制在 [DEFAULT_INEQ_SEL, 1]
```

#### LIKE 模式选择性：`text_sel` / `prefix_selectivity`

```
算法 (WHERE col LIKE 'prefix%'):

1. 检测是否纯前缀模式（%只在末尾，且没有 _）
2. 如果是前缀模式: 转换为范围查询
   WHERE col >= 'prefix' AND col < 'prefix' + next_char_increment
3. 转化后调用 scalarineqsel 两次（ge 和 lt）

算法 (WHERE col LIKE '%suffix' 或 '%infix%'):

1. 不能转换为范围
2. 使用保守估计:
   - likelihood_of_match = DEFAULT_MATCH_SEL = 0.005
   - 根据模式的固定部分长度做微小调整
   - 最终 selectivity 基本固定在 0.005 ~ 0.02
```

PostgreSQL 的 LIKE 估计非常保守。对 `col LIKE '%foo%'` 永远返回接近固定值，实际选择性可能是 0.001 或 0.8，误差几百倍是常态。

#### 关键源码位置

- `eqsel`、`eqjoinsel`: 等值与等值 JOIN
- `scalarineqsel`: 标量不等式（<、<=、>=、>）
- `boolvarsel`: 布尔变量
- `prefix_selectivity`: LIKE 前缀
- `like_selectivity`: LIKE 通用
- `regex_selectivity`: 正则表达式
- `areajoinsel`: 几何类型 JOIN

### Oracle：DENSITY、CBO 常量与自适应采样

Oracle 的选择性估计算法以保守和可调见长，用户可通过大量参数微调。

#### DENSITY：不命中 MCV 时的回退

```sql
-- Oracle 的核心概念:
-- DENSITY = 1 / NDV 的加权平均, 并考虑非均匀分布

SELECT column_name, num_distinct, density, num_nulls, num_buckets, histogram
FROM user_tab_col_statistics
WHERE table_name = 'EMPLOYEES' AND column_name = 'DEPT_ID';

-- density 取值:
--   无直方图: 1 / num_distinct
--   frequency 直方图: 取非频繁值的平均密度
--   hybrid 直方图 (12c+): 端点外的低频值密度

-- WHERE dept_id = 10:
--   1. 查 frequency 直方图, 10 是否是端点:
--      是 -> selectivity = endpoint_value * endpoint_number / total
--      否 -> selectivity = density
```

#### CBO 常量表

Oracle 内置一组默认选择性常量（当统计信息缺失或不可用时使用）：

```
Oracle CBO 默认选择性常量:

  col = literal                 -> 0.01 (即 1%)
  col = bind_variable           -> 0.05 (即 5%) 若无直方图
  col > literal 或 col < literal  -> 0.05
  col BETWEEN a AND b             -> 0.05
  col LIKE 'prefix%'              -> 0.05
  col LIKE '%infix%'              -> 0.05
  col IN (v1, v2, ..., vn)        -> n * col_eqsel, 上限 0.5
```

这些"魔法常量"是 Oracle DBA 社区最熟悉的调优障碍——不论直方图多精确，参数绑定窥探（bind peeking）关闭时仍会退化到常量。

#### DBMS_STATS.AUTO_SAMPLE_SIZE 与自适应采样

Oracle 11g 引入 `AUTO_SAMPLE_SIZE`，采样策略从固定 `ESTIMATE_PERCENT` 转为自适应：

```sql
-- Oracle 11g 前: 固定百分比采样
EXEC DBMS_STATS.GATHER_TABLE_STATS('HR', 'EMPLOYEES',
    estimate_percent => 10);  -- 采样 10%

-- Oracle 11g+: 自适应采样 (推荐)
EXEC DBMS_STATS.GATHER_TABLE_STATS('HR', 'EMPLOYEES',
    estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE);
-- 内部算法:
--   1. 对 NDV 使用 hash-based algorithm, 100% 扫描但仅读部分列
--   2. 对直方图使用小比例采样
--   3. 总耗时约等于 10% 固定采样, 但 NDV 精度接近 100% 扫描
```

Oracle 12c 进一步引入**自适应统计收集**（Dynamic Sampling Level 11），在 SQL 执行时即时收集缺失的统计信息。

#### 混合直方图（Hybrid Histogram）

Oracle 12c 引入 Hybrid Histogram，专门解决 height-balanced 直方图在桶边界处对高频值低估的问题：

```
Height-balanced 直方图缺陷:
  - 高频值可能横跨多个桶
  - 查询该值时只计一个桶的贡献, 导致低估

Hybrid Histogram 改进:
  - 每个桶额外记录端点值的频率 (endpoint_value × endpoint_number)
  - 对端点值做精确计算, 非端点值才走等深插值
```

### SQL Server：CardinalityEstimator 2014 重写

SQL Server 2014 重写了查询优化器的基数估计模块，称为 **NewCE**（新基数估计器），老版本称为 **LegacyCE**。这是关系型数据库历史上最激进的一次 CE 重写。

#### LegacyCE vs NewCE 关键假设

```
LegacyCE (SQL Server 2000 ~ 2012):
  1. 独立性假设: sel(A AND B) = sel(A) × sel(B)
  2. 均匀性假设: 直方图桶内数据均匀分布
  3. 封闭性假设: 查询值一定在数据范围内
  4. 简单 JOIN 假设: JOIN 的选择性 = min(|A|, |B|) / max(NDV(A), NDV(B))

NewCE (SQL Server 2014+):
  1. 指数退避 (Exponential Backoff) 替代独立性:
     sel(P1 AND P2 AND P3) = sel(P1) × sqrt(sel(P2)) × sqrt(sqrt(sel(P3)))
     按选择性降序, 后续谓词权重指数衰减
  2. 放宽封闭性假设: 允许查询值在数据范围外
  3. 改进 JOIN 估计: 考虑多列关联
  4. 新的直方图重采样 (ascending key 场景)
```

#### 启用与禁用新 CE

```sql
-- SQL Server 2014 兼容级别 120+ 自动使用 NewCE
ALTER DATABASE MyDB SET COMPATIBILITY_LEVEL = 120;

-- 在查询级别回退到 LegacyCE
SELECT * FROM orders WHERE ...
OPTION (USE HINT('FORCE_LEGACY_CARDINALITY_ESTIMATION'));

-- 查询查看当前使用的 CE 版本:
SET STATISTICS XML ON;
-- 在 XML 中查找 CardinalityEstimationModelVersion 属性
-- 70 = LegacyCE, 120+ = NewCE
```

NewCE 的**指数退避**是关键创新。传统独立性假设对 3 个以上谓词会严重低估：

```
场景: 3 个谓词, 每个 sel = 0.1

LegacyCE (独立性):
  sel = 0.1 × 0.1 × 0.1 = 0.001 = 0.1%

NewCE (指数退避, 按 sel 降序):
  sel = 0.1 × sqrt(0.1) × sqrt(sqrt(0.1))
      = 0.1 × 0.316 × 0.562 = 0.0178 ≈ 1.78%

实际数据往往存在相关性, NewCE 更接近真实值
```

#### SQL Server 特殊场景

```sql
-- 1. 本地变量 (local variable) 固定估计
DECLARE @status VARCHAR(20) = 'PAID';
SELECT * FROM Orders WHERE Status = @status;
-- 优化器不知道 @status 的具体值
-- LegacyCE: selectivity = 1/NDV
-- NewCE:    selectivity = 30% (对应等值比较，不同于直方图可用时)
-- 即使知道 Status='PAID' 仅占 0.1%, 估计仍为 30%

-- 2. 参数嗅探 (Parameter Sniffing)
-- 编译 SP 时用第一次调用的参数值做优化
-- 后续调用复用该计划, 即使参数值变化
CREATE PROC GetOrders @status VARCHAR(20) AS
    SELECT * FROM Orders WHERE Status = @status;
GO
EXEC GetOrders 'PAID';      -- 99% 选择性, 优化为全表扫描
EXEC GetOrders 'REFUNDED';  -- 0.1% 选择性, 仍走全表扫描, 慢 100 倍

-- 解决: OPTION (RECOMPILE) 或 OPTIMIZE FOR UNKNOWN
```

### MySQL：Range Optimizer + 8.0.3 直方图

MySQL 8.0 前的选择性估计几乎完全依赖 B 树索引统计（`index_cardinality`），是主流引擎中最粗糙的。

#### 8.0 前的算法

```
MySQL 5.7 选择性估计:
  1. 有索引:
     selectivity = 1 / index_cardinality
     (index_cardinality 是每个索引前缀的 NDV)
  2. 无索引:
     selectivity = 固定 10% (cost_model 的 io_block_read_cost 启发式)
  3. 等值范围: records_in_range() 直接扫描 B 树统计叶子页数
     精度高但只适用于索引列

问题:
  - 非索引列无选择性信息
  - 复合谓词假设完全独立
  - 没有列值频率信息 (MCV)
```

#### 8.0.3 直方图引入

```sql
-- MySQL 8.0.3 起支持 ANALYZE ... UPDATE HISTOGRAM
ANALYZE TABLE orders UPDATE HISTOGRAM ON status WITH 100 BUCKETS;
ANALYZE TABLE orders UPDATE HISTOGRAM ON customer_id WITH 1024 BUCKETS;

-- 两种直方图:
--   NDV ≤ bucket_count: SINGLETON (每个 distinct 值一个桶，即频率直方图)
--   NDV > bucket_count: EQUI-HEIGHT (等高/等深)

-- 查看:
SELECT * FROM information_schema.column_statistics
WHERE schema_name = 'db' AND table_name = 'orders';
-- 返回 JSON:
-- {"buckets": [[...], ...], "data-type": "enum",
--  "histogram-type": "singleton", "sampling-rate": 1.0}

-- 直方图限制:
-- 1. MySQL 直方图不会自动更新, 需要显式 UPDATE HISTOGRAM
-- 2. 优化器优先使用索引统计; 未建索引的列才走直方图
-- 3. 不支持多列直方图
```

#### range optimizer 的代价估算

MySQL 8.0 的 `range optimizer` 是其选择性估计的核心，位于 `sql/range_optimizer/`：

```
对 WHERE col BETWEEN a AND b:
  1. 如果 col 有索引:
     调用 ha_innobase::records_in_range(index, key_range)
     InnoDB 读取 B+ 树叶子页, 按采样估计范围内行数
     精度高, 代价中等
  2. 如果 col 有直方图:
     累加直方图桶的贡献
  3. 都没有:
     固定 25% (OPEN_RANGE_SELECTIVITY 常量)
```

MySQL 的 `records_in_range` 是独特设计——它**直接读取 InnoDB B+ 树**做采样，而不是依赖预先收集的统计信息。这使得 MySQL 在索引列上的范围估计非常准确，但代价是每次优化都要额外 I/O。

### DB2：RUNSTATS 与 column group 扩展统计

DB2 的选择性估计建立在 `RUNSTATS` 收集的统计信息上，支持单列和多列（column group）：

```sql
-- 基础统计
RUNSTATS ON TABLE schema.orders;

-- 详细统计（含分位数和频率）
RUNSTATS ON TABLE schema.orders WITH DISTRIBUTION;

-- 指定列的频率和分位数数量
RUNSTATS ON TABLE schema.orders
    WITH DISTRIBUTION ON COLUMNS (status, customer_id NUM_FREQVALUES 50 NUM_QUANTILES 200);

-- 多列统计（column group）
RUNSTATS ON TABLE schema.orders
    ON COLUMNS ((city, zipcode)) WITH DISTRIBUTION;

-- 查看统计
SELECT * FROM SYSCAT.COLUMNS WHERE TABNAME = 'ORDERS';
SELECT * FROM SYSCAT.COLDIST WHERE TABNAME = 'ORDERS';
SELECT * FROM SYSCAT.COLGROUPS WHERE TABNAME = 'ORDERS';
```

DB2 的选择性估计特点：

- **频率 + 分位数分离**：频繁值单独记录（类似 MCV），其余值走分位数
- **column group**：多列联合 NDV 和频繁值，修正相关列低估
- **cardinality feedback**：运行时可收集实际行数，反馈给下次优化（DB2 v9.7+）

### Teradata：biased values 与 COLLECT STATISTICS ON column group

Teradata 的 CBO 历史悠久，是 MPP 数据库选择性估计的先驱：

```sql
-- 基础统计
COLLECT STATISTICS ON orders COLUMN status;

-- 使用采样（大表常见）
COLLECT STATISTICS USING SAMPLE 10 PERCENT ON orders COLUMN customer_id;

-- 多列统计
COLLECT STATISTICS ON orders COLUMN (city, zipcode);

-- 查看统计
SHOW STATISTICS ON orders;
HELP STATISTICS orders;
```

Teradata 的 **biased values** 是其独特概念：直方图外额外维护 top-K biased values（类似 MCV），估计公式按"biased vs non-biased"分层。

### TiDB：等深 + Top-N + CMSketch 演进

TiDB 的统计信息系统经过三个重要版本：

```
TiDB 统计信息演进:

v1.0 - v3.0: equi-depth histogram + CMSketch (Count-Min Sketch)
  CMSketch 用于估计点查频率, 但精度有限
  典型问题: 高频值低估、长尾错误

v4.0 (analyze_version=1): 引入 Top-N
  与 PostgreSQL 的 MCV 类似, 将高频值单独存储
  CMSketch 保留用于非 Top-N 值

v5.1+ (analyze_version=2, 默认):
  - 完全移除 CMSketch
  - 改用 Top-N + 等深直方图
  - 改进 NDV 估计 (HLL++)
  - 支持更大的 Top-N 和 bucket count
```

```sql
-- TiDB 的选择性查看
SHOW STATS_HISTOGRAMS WHERE table_name = 'orders';
SHOW STATS_TOPN WHERE table_name = 'orders';

-- 手动指定 bucket 数和 Top-N 数
ANALYZE TABLE orders WITH 1024 BUCKETS, 1024 TOPN;

-- v5.3+ 增量自动 analyze
SET GLOBAL tidb_enable_auto_analyze = ON;
SET GLOBAL tidb_auto_analyze_ratio = 0.5;
```

### CockroachDB：原生多列统计

CockroachDB 20.1+ 提供原生多列统计支持：

```sql
-- 创建多列统计
CREATE STATISTICS stats_cc ON (city, country) FROM users;

-- 后台自动收集
SET CLUSTER SETTING sql.stats.automatic_collection.enabled = true;

-- 查看
SHOW STATISTICS FOR TABLE users;
```

## LIKE 模式选择性估计深度解析

LIKE 是选择性估计最薄弱的环节。PostgreSQL、Oracle、SQL Server 对非前缀 LIKE 几乎都使用固定估计。

### 前缀 LIKE（可转化为范围）

```
对 col LIKE 'abc%':
  等价于 col >= 'abc' AND col < 'abd'  ('abd' 是 'abc' 的"下一个字符串")
  可以用范围估计（直方图累加）, 精度较高

PostgreSQL 实现:
  prefix_selectivity() 调用 scalarineqsel() 两次
  然后相减得到前缀范围

精度:
  - 直方图足够精细时, 前缀 LIKE 的选择性非常接近真实值
  - 对 UTF-8 多字节字符, 需要特殊处理 byte 序列边界
```

### 中缀 / 后缀 LIKE（无法转化）

```
对 col LIKE '%xyz' 或 '%xyz%':
  - 无法转换为范围查询
  - 主流引擎退化到固定估计

PostgreSQL:
  DEFAULT_MATCH_SEL = 0.005
  对固定部分长度的微调: 长度每增加一位, 选择性略降

SQL Server NewCE:
  固定 9% (相对保守)

Oracle:
  固定 5%

MySQL:
  当列无直方图: 固定 10%
  有直方图时: 仍然固定 (直方图不能高效处理中缀匹配)
```

### 字符串直方图的局限

几乎所有引擎的直方图都按**字符串字典序**建桶。这意味着：

- 前缀 LIKE 可用（落在相邻桶）
- 中缀 LIKE 完全不可用（匹配可能散落在所有桶）
- 正则表达式几乎完全退化到固定估计

**改进方向**：

1. **n-gram 直方图**：对字符串拆分为 n-gram 统计频率（PostgreSQL 的 `pg_trgm` 扩展、Elasticsearch）
2. **基于采样的运行时估计**：查询时对小样本评估 LIKE，外推到全表（SparkSQL AQE 方向）
3. **机器学习模型**：离线训练模型，预测字符串模式的选择性（VLDB 近年热门方向）

## 多列相关性：独立性假设失效

多数引擎的 AND 选择性计算基于**列独立性假设**：

```
sel(A AND B) = sel(A) × sel(B)

前提: A 和 B 在统计上独立
实际: 真实数据几乎总是相关的
```

### 经典失效场景

```sql
-- 场景 1: 函数依赖 (city 决定 country)
SELECT * FROM addresses
WHERE country = 'US' AND state = 'CA';
-- country='US' sel = 0.3
-- state='CA'   sel = 0.1
-- 独立假设: 0.03
-- 实际: state='CA' 必然 country='US', sel = 0.1 (严重低估 3 倍以上)

-- 场景 2: 冗余关联 (category 和 subcategory)
SELECT * FROM products
WHERE category = 'Electronics' AND subcategory = 'Laptops';
-- category='Electronics'   sel = 0.2
-- subcategory='Laptops'    sel = 0.05
-- 独立假设: 0.01
-- 实际: Laptops 只出现在 Electronics 下, sel = 0.05

-- 场景 3: 时间序列相关
SELECT * FROM events
WHERE year = 2024 AND month = 12;
-- 独立假设: 两个列独立
-- 实际: 两者都是时间维度, 高度相关
```

### 各引擎的修正机制

#### PostgreSQL：CREATE STATISTICS（10+）

```sql
-- 函数依赖统计
CREATE STATISTICS stats_country_state (dependencies)
    ON country, state FROM addresses;
ANALYZE addresses;

-- 查看
SELECT * FROM pg_statistic_ext_data WHERE ...;

-- 多列 NDV
CREATE STATISTICS stats_ndv (ndistinct) ON a, b, c FROM t;

-- 多列 MCV (PG 12+)
CREATE STATISTICS stats_mcv (mcv) ON a, b FROM t;

-- 表达式统计 (PG 14+)
CREATE STATISTICS stats_lower (mcv) ON lower(email) FROM users;
```

PostgreSQL 的 `pg_statistic_ext` 提供三种扩展统计：

1. **dependencies**：函数依赖度，`sel(B | A)` ≠ `sel(B)`
2. **ndistinct**：多列组合的 NDV，用于 GROUP BY 估计
3. **mcv**：多列 MCV，处理多列高频组合

#### SQL Server NewCE：指数退避（Exponential Backoff）

SQL Server 2014 的 NewCE 引入了**指数退避**策略：

```
sel(P1 AND P2 AND P3 AND P4) =
  按 sel 降序排序 sel(P1) ≥ sel(P2) ≥ ...
  = sel(P1) × sqrt(sel(P2)) × sqrt(sqrt(sel(P3))) × sqrt(sqrt(sqrt(sel(P4))))
  = sel(P1)^1 × sel(P2)^(1/2) × sel(P3)^(1/4) × sel(P4)^(1/8)

直觉:
  - 相关性: 后续谓词在前面谓词过滤后更容易命中
  - 指数退避对"松散相关"场景有良好近似
  - 但对"强函数依赖"仍然会高估
```

#### Oracle：Extended Statistics

```sql
-- 多列扩展统计
SELECT DBMS_STATS.CREATE_EXTENDED_STATS(
    'SCOTT', 'ADDRESSES', '(country, state)') FROM DUAL;

-- 表达式扩展统计
SELECT DBMS_STATS.CREATE_EXTENDED_STATS(
    'SCOTT', 'USERS', '(LOWER(email))') FROM DUAL;

-- 再次 ANALYZE 使其生效
EXEC DBMS_STATS.GATHER_TABLE_STATS('SCOTT', 'ADDRESSES');
```

Oracle 的扩展统计实际上是创建一个**虚拟列**，内部用 `SYS_STUZF*` 函数存储，优化器像普通列一样使用其 NDV 和直方图。

#### DB2：Column Group

```sql
-- DB2 的 column group 语法
RUNSTATS ON TABLE schema.addresses
    ON COLUMNS ((country, state)) WITH DISTRIBUTION;

-- 查看
SELECT * FROM SYSCAT.COLGROUPS WHERE TABNAME = 'ADDRESSES';
```

### 相关性检测与维护困难

扩展统计最大的问题不是创建，而是**何时创建**：

1. **用户不知道哪些列相关**：需要 DBA 手动分析查询模式
2. **创建所有组合代价巨大**：n 列有 O(2^n) 种组合
3. **维护成本**：每次 ANALYZE 都要重新计算
4. **DBA 遗漏**：绝大多数生产系统只在发现问题后才补充

Oracle 11g+ 的 SQL Plan Directive 尝试自动检测"估计错误"并推荐创建扩展统计，但效果有限。PostgreSQL、MySQL 均无类似机制。

## Top-N 与小域问题

### Top-N 问题：高频值支配的分布

当列分布高度倾斜（极少数值占比 99%+，大量低频值占 1%），传统等深直方图无法精确描述：

```
场景: user_events 表, event_type 列分布:
  page_view:  70%
  click:      20%
  scroll:     8%
  search:     1%
  (其他 1000+ 种低频事件): 1%

等深直方图 (100 桶):
  桶 1-70:   page_view  (一个值横跨 70 桶!)
  桶 71-90:  click
  桶 91-98:  scroll
  桶 99:     search
  桶 100:    (其他所有低频事件混在一起)

查询 event_type = 'rare_event' 的选择性:
  被桶 100 覆盖, 估计为 1/100 = 1%
  实际: 可能是 0.001%, 误差 1000 倍
```

### Top-N 直方图的改进

多个引擎的改进方案：

```
PostgreSQL: MCV + 等深直方图
  - most_common_vals[] 单独存储高频值及频率
  - histogram_bounds[] 存储剩余值的等深直方图

Oracle: Top-Frequency Histogram
  - Oracle 12c 引入
  - 保留 top-N 值, 其余合并为 "others"
  - 端点外的低频值走 density

TiDB: Top-N + Histogram
  - 与 PG MCV 类似
  - Top-N 数量可配置 (默认 1024)

Teradata: biased values
  - 同等深直方图一起维护
  - biased values 的频率精确存储

MySQL 8.0: SINGLETON histogram
  - NDV ≤ bucket_count 时退化为频率直方图
  - 不是严格的 Top-N, 但达到类似效果
```

### 小域问题：NDV 小于桶数

当列的 NDV 小于桶数时，最优解是**频率直方图**（每个 distinct 值一个桶）：

```
场景: status 列 NDV = 5, 桶数 = 100
  等深直方图: 浪费 95 个桶, 或合并 distinct 值导致精度损失
  频率直方图: 5 个桶, 每个桶精确记录一个值的频率
```

所有现代引擎都有"小域检测"：NDV 较小时自动切换到频率直方图。

- **Oracle**：NDV ≤ 254 走 Frequency
- **MySQL 8.0**：NDV ≤ bucket_count 走 SINGLETON
- **PostgreSQL**：统一用 MCV 列表，列表长度 ≤ default_statistics_target

### Top-N 的维护成本

Top-N 需要在统计收集时做**全量排序 + 计数**：

```
算法:
  1. 扫描全表 (或采样)
  2. HashMap<value, count> 统计频率
  3. 排序取前 N
  4. 存储到系统表

代价:
  - 内存: O(NDV)
  - CPU: O(N log N) 排序
  - I/O: 全表或采样扫描
```

大表上 Top-N 的收集是 `ANALYZE` 的主要时间开销。Oracle 和 PostgreSQL 都用**采样 + 估计**降低代价，代价是 top-N 的相对精度下降。

## 参数化查询与 bind peeking

### 参数化查询的困境

```sql
PREPARE stmt (VARCHAR) AS
    SELECT * FROM orders WHERE status = $1;

-- 编译时: $1 未知
-- 优化器如何估计 sel(status = $1)?
```

主流引擎的策略：

| 引擎 | 策略 |
|------|------|
| PostgreSQL | 首次执行用实际值优化（custom plan），5 次后切到 generic plan（使用 avg selectivity） |
| Oracle | Bind peeking: 首次窥探参数值 + 9i 起自适应游标共享（ACS） |
| SQL Server | Parameter sniffing: 首次编译用窥探值 |
| MySQL | 固定估计（无 bind peeking） |
| DB2 | REOPT ONCE / ALWAYS 参数控制 |

### Parameter Sniffing 问题

```sql
-- SQL Server 经典问题
CREATE PROCEDURE GetOrders @status VARCHAR(20)
AS SELECT * FROM orders WHERE status = @status;

-- 第一次调用: @status = 'PAID' (99% 数据)
EXEC GetOrders 'PAID';
-- 优化器选择: 全表扫描 (高选择性)

-- 第二次调用: @status = 'REFUNDED' (0.1% 数据)  
EXEC GetOrders 'REFUNDED';
-- 复用第一次的计划 (全表扫描)
-- 但对这个参数值应该走索引!
-- 结果: 慢 100 倍
```

### 解决方案

```sql
-- SQL Server:
-- 1. 每次重新编译
SELECT * FROM orders WHERE status = @status
OPTION (RECOMPILE);

-- 2. 忽略参数值, 使用"平均"估计
SELECT * FROM orders WHERE status = @status
OPTION (OPTIMIZE FOR UNKNOWN);

-- 3. 固定某个参数值
SELECT * FROM orders WHERE status = @status
OPTION (OPTIMIZE FOR (@status = 'PAID'));

-- PostgreSQL:
-- 强制每次都用 custom plan (每次都优化)
SET plan_cache_mode = force_custom_plan;

-- 强制每次都用 generic plan
SET plan_cache_mode = force_generic_plan;

-- Oracle:
-- 自适应游标共享 (ACS) 自动处理, 无需干预
-- 但可以用 SQL Baseline 固定计划
```

## JOIN 选择性估计

JOIN 选择性本质上是一个多列 MCV / NDV 问题，但因涉及两张表的分布，独立处理：

### 基本算法

```
内连接 JOIN (A INNER JOIN B ON A.x = B.y):

  默认假设 (W.B. Ganguly 公式):
  |A ⋈ B| = |A| × |B| / max(NDV(A.x), NDV(B.y))

  原理: 
    - 假设两边均为等值 JOIN
    - 较小的 NDV 决定了最多能匹配多少 distinct 值
    - 每个 distinct 值的重复次数由较大表补齐

  注意:
    - 这是"桥接"公式, 忽略了 JOIN 两边的值域重叠
    - 更精确的版本考虑 min(max(A.x), max(B.y)) - max(min(A.x), min(B.y))
```

### 带直方图的改进

```
PostgreSQL: eqjoinsel
  1. 读取两表的 MCV 列表
  2. 对每个 A.MCV 值查 B.MCV 中是否存在
     - 存在: 贡献 = freq_A × freq_B
     - 不存在: 按 B 非 MCV 均匀估计
  3. 剩余非 MCV 部分走 NDV 公式
  
Oracle:
  对高频值 (直方图端点) 单独计算匹配频率
  低频值走 DENSITY

SQL Server NewCE:
  直方图对齐 (histogram alignment): 
  将两表直方图的桶边界对齐, 逐桶累加 JOIN 贡献
```

### 多表 JOIN 基数累积误差

```
场景: 5 表 JOIN, 每个 JOIN 有 10% 低估误差

阶段 1: sel_est / sel_actual = 0.9
阶段 2: 0.9² = 0.81  (累积误差)
阶段 3: 0.9³ = 0.729
阶段 4: 0.9⁴ = 0.656
阶段 5: 0.9⁵ = 0.59   <- 整体低估 41%

对 8 表 JOIN, 每级 20% 误差:
  累积 0.8⁸ ≈ 0.17, 即低估 83%!

这就是 JOB benchmark 揭示的问题:
  单步误差 ≤ 1.2x, 但 4-5 表 JOIN 后累积误差可达 10⁴ 倍
```

### 优化器对累积误差的缓解

```
1. 选择 Hash Join 而非 Nested Loop:
   Hash Join 对基数误差不敏感 (代价与基数线性)
   Nested Loop 代价平方级, 误差致命

2. Plan guards / SQL Baselines:
   记住有效的执行计划, 即使估计变化也不重新选择

3. Adaptive execution:
   运行时收集实际行数, 动态切换算法 (Spark AQE, Oracle 12c)

4. Robust optimization:
   选择在参数误差下仍然较好的计划 (MSR 2012 论文)
```

## 运行时反馈闭环（Cardinality Feedback）

### 传统 CBO 的短板

传统 CBO 是**单向决策**：

```
查询 -> 估计选择性 -> 生成计划 -> 执行 -> 返回结果
                                    ^
                              (实际行数被丢弃)
```

估计错误永远不会修正，除非手动 `ANALYZE`。

### 反馈闭环的引擎

```
DB2 (最早, 2003+):
  LEO (Learning Optimizer): 运行时收集实际行数
  下一次同样查询时, 自适应调整选择性估计

Oracle (12c+):
  Adaptive Statistics: 执行时检测估计误差
  SQL Plan Directives: 为查询模式记录"需要额外统计"

SQL Server (2017+):
  Automatic Tuning + Query Store:
  记录每个查询的执行历史
  检测计划回归 (plan regression), 自动回退

Spark SQL (3.0+) AQE:
  Adaptive Query Execution:
  shuffle 阶段后读取实际行数
  动态调整后续 JOIN 策略和分区数

TiDB (5.0+):
  Plan Cache + 统计自适应
  定期根据执行历史修正统计

PostgreSQL:
  目前无原生闭环; 
  pg_qualstats 等扩展提供有限能力
```

### AQE 的工作机制（Spark）

```
阶段 1: 生成初始计划 (基于静态统计)
         -> Stage 1 (全表扫描 + filter)
         -> Stage 2 (Hash Join)

阶段 2: Stage 1 执行完成
         实际行数 = 1M (估计 10K, 误差 100x!)
         
阶段 3: AQE 触发重优化
         -> 将 Stage 2 从 Broadcast JOIN 改为 Shuffle JOIN
         -> 动态调整分区数 (coalesce)

阶段 4: 继续执行 Stage 2 新计划
```

AQE 是流批引擎的标配，但对 OLTP 场景不适用（单次查询延迟敏感）。

## 对引擎开发者的实现建议

### 1. MCV 查找与回退

```
查询: WHERE col = 'X'

步骤:
  1. 在 most_common_vals 数组中二分查找 'X'
     - 找到索引 i: selectivity = most_common_freqs[i]
     - 未找到: 走步骤 2

  2. 读取 column 统计:
     - n_distinct: distinct 值数
     - null_frac: NULL 比例
     - sum_mcv_freq: MCV 频率总和

  3. 计算非 MCV 的选择性:
     non_mcv_distinct = n_distinct - len(MCV)
     non_mcv_frac = 1 - null_frac - sum_mcv_freq
     selectivity = non_mcv_frac / non_mcv_distinct

  4. Clamp 到 [DEFAULT_SEL_LOWER, 1.0]
     避免极端值 (MySQL 有 0.001% 下限, PostgreSQL 类似)
```

关键要点：

- **二分查找**：MCV 列表按频率排序，但按值做查找需要二级索引或线性扫描
- **字符串比较**：locale-aware 比较对选择性估计很重要
- **NULL 特殊处理**：`IS NULL` 走 `null_frac`，不走 MCV

### 2. 直方图桶内插值

```
算法 (范围估计 col < X):

  1. 如果 X <= min (边界桶外):
     selectivity = min_bucket_density × (X - histmin) / (histmin - ...)
     通常 clamp 到 DEFAULT_RANGE_SELECTIVITY
  
  2. 如果 X >= max:
     selectivity = 1 - min_bucket_density × ...
     类似外推

  3. X 在范围内, 二分查找桶:
     bucket_k: bound[k-1] <= X < bound[k]
     
  4. 累加前 k-1 个桶:
     pre_sel = (k - 1) / bucket_count

  5. 桶 k 内插值:
     fraction = (X - bound[k-1]) / (bound[k] - bound[k-1])
     sel_in_bucket = fraction / bucket_count
     
  6. 合计:
     selectivity = pre_sel + sel_in_bucket
```

#### 插值的数据类型挑战

```
数值类型 (int/float):
  线性插值直接适用

日期类型:
  转 epoch seconds 线性插值

字符串类型:
  - ASCII: 按字典序可线性插值
  - UTF-8: 需处理多字节字符, 边界定义不唯一
  - locale-sensitive: 排序规则影响插值
  
枚举 / 有限集合:
  不适合直方图, 应走频率估计
```

### 3. 多谓词组合的实现选择

```
方案 A: 朴素独立性
  sel = sel(P1) × sel(P2) × ... × sel(Pn)
  实现简单, 误差大

方案 B: 指数退避 (SQL Server NewCE):
  按 sel 降序排序
  sel = sel(P1) × sel(P2)^0.5 × sel(P3)^0.25 × ...
  平衡简单性与精度

方案 C: 多列统计 (PostgreSQL / Oracle / DB2):
  读取扩展统计的多列 MCV, NDV, 依赖度
  实现复杂, 但精度最高
  
方案 D: 机器学习模型 (研究方向):
  离线训练 deep learning 模型
  输入: 列统计 + 谓词特征
  输出: selectivity 估计
  VLDB 2019+ 多篇论文, 未落地主流引擎
```

### 4. 选择性估计的单元测试

```
基础测试:
  1. 单列等值: 查 MCV 命中 / 未命中
  2. 单列范围: 跨桶 / 单桶 / 开放区间
  3. LIKE: 前缀 / 后缀 / 中缀
  4. IN 列表: 短列表 / 长列表
  5. NULL: IS NULL / IS NOT NULL

复合测试:
  1. AND 两谓词: 独立 / 相关
  2. OR 两谓词: 重叠 / 不重叠
  3. NOT 取反

边界测试:
  1. 列无统计信息 (应走默认常量)
  2. 空表 (sel 应收敛到 0 或 NaN 保护)
  3. 单值表 (NDV = 1)
  4. 超高基数 (NDV = row_count, 唯一键)

退化测试:
  1. 直方图桶数 = 1 (退化为 min/max)
  2. MCV 列表为空
  3. 采样比例极低 (< 0.1%)

回归测试:
  使用 JOB benchmark 或类似复杂 JOIN 查询
  记录 q-error = max(est/actual, actual/est)
  跟踪版本间变化
```

### 5. 默认常量的选择

当统计信息缺失时，引擎必须退回到默认常量。不同引擎的选择：

```
引擎            等值    不等     范围     LIKE    IN(N)
PostgreSQL      0.005   0.3      0.3      0.005   各 × 0.005
MySQL           0.1     0.25     0.25     0.1     各 × 0.1
Oracle          0.01    0.05     0.05     0.05    各 × 0.01
SQL Server NCE  固定    0.3      0.3      0.09    各 × 等值
DB2             0.04    0.333    0.333    0.04    ...
```

选择默认值的哲学：

- **悲观策略**（大值）：优先保证不选错计划，但代价可能过高
- **乐观策略**（小值）：追求最优计划，但错误代价高
- 行业共识：**中位数附近**（0.05 左右），兼顾两端

### 6. 采样与精度权衡

```
ANALYZE 的采样策略:

完全扫描:
  最精确, 但 O(N) I/O, 大表不可行

固定百分比采样 (老 Oracle, MySQL):
  简单, 但 N 很大时采样仍然很大 (如 1% of 1B = 10M)
  
自适应采样 (Oracle 11g+ AUTO_SAMPLE_SIZE):
  小表全扫, 大表按启发式采样大小
  NDV 估计用 hash-based algorithm 接近 100% 精度
  
增量统计 (Oracle incremental, DB2 incremental):
  仅重新分析变化的分区, 合并到全局统计
  
在线统计 (SingleStore, CockroachDB):
  后台持续收集, 无需显式 ANALYZE
```

### 7. 向量化选择性评估

现代引擎在执行时大量使用向量化批处理。选择性评估可在执行前预估 batch 命中率：

```
场景: WHERE status = 'PAID' AND amount > 100

预估:
  sel(status='PAID') = 0.7
  sel(amount > 100) = 0.3
  联合 sel (独立) = 0.21

实现:
  对每个 batch (1024 行):
    1. 评估 status='PAID', 生成 bitmap (理论 ~717 行命中)
    2. 对命中的 717 行评估 amount > 100 (理论 ~215 行命中)
    3. 最终输出 bitmap

性能优化:
  - 如果第一个谓词选择性极低 (< 1%), 先向量化评估整个 batch
  - 如果第一个谓词选择性极高 (> 99%), 跳过 bitmap 合并
  - 谓词重排序: 把选择性低的谓词放前面
```

谓词顺序对向量化性能至关重要，但很多引擎的执行计划不做动态重排。

## 设计争议

### 准确性 vs 稳定性

```
估计准确意味着"在真实数据下接近真实值"
稳定意味着"在数据小幅变化时估计值也小幅变化"

二者不等价:
  例 1: 直方图桶边界刚好切在高频值上
    - 估计可能很准, 但加一行新数据就可能错 10 倍
    - 不稳定

  例 2: 固定常量 0.05
    - 估计不准, 但永远不会突变
    - 极稳定

引擎的取舍:
  PostgreSQL: 偏准确 (高 default_statistics_target)
  Oracle: 偏稳定 (DENSITY + 保守默认值)
  SQL Server: 折中 (201 桶 + 常量回退)
```

### 独立性假设：已知错误但无法放弃

没有引擎使用完全非独立的估计，原因：

```
1. 实现复杂度:
   n 列 AND 有 O(2^n) 种谓词组合
   不可能为每种组合预存联合分布

2. 统计成本:
   多列 MCV / 依赖度需要大规模统计
   维护成本远高于单列

3. 用户负担:
   用户必须手动 CREATE STATISTICS 指定相关列
   绝大多数 DBA 不会主动这样做

4. 误差不对称:
   独立假设倾向于低估 (相关列)
   低估 -> Hash Join 改 Nested Loop -> 灾难
   但低估在大多数 OLTP 场景并不致命
```

独立性假设是 CBO 的**有意妥协**，而非技术缺陷。

### 是否应该使用机器学习？

VLDB 和 SIGMOD 近年有大量论文尝试用深度学习替代传统选择性估计：

- **MSCN** (VLDB 2019)：multi-set convolutional network, 训练 JOIN 选择性估计
- **DeepDB** (PVLDB 2020)：基于 SPN (Sum-Product Network) 建模联合分布
- **NeuroCard** (VLDB 2021)：用 neural network 学习 cardinality 估计

主流引擎**几乎都没有集成**，原因：

1. 训练数据需求：数据分布变化需要重训练
2. 不可解释性：DBA 无法理解 ML 模型输出
3. 推理延迟：每次优化要运行模型
4. 边界情况不可靠：ML 模型对罕见查询容易出错

工业界的折中：在**特定高价值场景**（如数仓的热点 JOIN 模式）使用 ML，通用场景仍然传统算法。

### 优化器是否应该暴露选择性？

```sql
-- PostgreSQL / MySQL / Oracle 的 EXPLAIN 都显示估计行数
-- 但行数 / 表行数 = selectivity 需要用户自己算

EXPLAIN (ANALYZE) SELECT * FROM orders WHERE status = 'PAID';
-- Seq Scan on orders  (cost=0.00..18334.00 rows=700000 width=20)
--   Filter: (status = 'PAID')
-- rows=700000 / total=1000000 => selectivity = 0.7

-- SQL Server:
SET STATISTICS XML ON;
-- XML 中包含 EstimatedSelectivity 字段

-- Oracle:
SELECT * FROM V$SQL_PLAN WHERE ...;
-- 含 card (行数) 和 cost 字段

争议:
  暴露 selectivity: DBA 易诊断, 但可能被误用做绕过优化器
  隐藏 selectivity: 保持优化器"黑盒", 但调试困难
```

## 总结对比矩阵

### 核心算法与能力

| 能力 | PostgreSQL | Oracle | SQL Server NewCE | MySQL 8.0 | DB2 | Trino | Spark |
|------|-----------|--------|------------------|-----------|-----|-------|-------|
| MCV 列表 | 是 | 是（Frequency） | 直方图 RANGE_HI_KEY | SINGLETON | 频率列表 | -- | -- |
| 等深直方图 | 是 | 是（多种） | 201 step | EQUI-HEIGHT | 分位数 | -- | 是 |
| 多列统计 | 是 | 是 | 是 | -- | 是 | -- | -- |
| 函数依赖度 | 是 | 扩展 | -- | -- | -- | -- | -- |
| 指数退避 | -- | -- | 是 | -- | -- | -- | -- |
| LIKE 前缀 | 是 | 部分 | 是 | 部分 | 是 | -- | 部分 |
| LIKE 中缀 | 固定 | 固定 | 固定 | 固定 | 固定 | 固定 | 固定 |
| 运行时反馈 | -- | 12c+ | 2017+ | -- | 是 | -- | AQE |
| Bind peeking | Custom plan | 是（ACS） | 是 | -- | REOPT | -- | -- |

### 各引擎选择性估计误差（经验）

| 查询类型 | PG | Oracle | SQL Server NCE | MySQL | TiDB |
|---------|----|----|-------|-------|------|
| 单列等值（MCV 命中） | <1.1x | <1.1x | <1.1x | <1.2x | <1.1x |
| 单列等值（MCV 未命中） | 1.5-5x | 2-5x | 2-5x | 2-10x | 1.5-5x |
| 范围（直方图内） | 1.2-2x | 1.2-2x | 1.2-3x | 1.5-3x | 1.2-2x |
| 范围（外推） | 5-100x | 5-50x | 5-20x | 10-100x | 5-50x |
| LIKE 前缀 | 1.5-5x | 2-5x | 1.5-5x | 2-10x | 2-5x |
| LIKE 中缀 | 10-1000x | 10-1000x | 10-1000x | 10-1000x | 10-1000x |
| 3 列 AND（相关） | 5-50x | 2-20x（扩展统计） | 2-10x（指数退避） | 10-100x | 5-50x |
| 5 表 JOIN | 10-100x | 5-50x | 5-50x | 10-1000x | 10-100x |

> 经验数据，实际误差取决于数据分布。来源：VLDB JOB benchmark 论文、各社区 benchmarking 报告。

### 选型与调优建议

| 场景 | 推荐引擎 | 关键配置 |
|------|---------|---------|
| 大规模数据仓库（倾斜严重） | Oracle + Hybrid Histogram | `method_opt 'FOR COLUMNS SIZE AUTO'` |
| 互联网 OLTP（中等规模） | PostgreSQL + MCV | `default_statistics_target = 500` |
| 多表 JOIN 复杂查询 | SQL Server NewCE | 兼容级别 >= 120 |
| 相关列多的业务 | PostgreSQL `CREATE STATISTICS` | 覆盖关键相关列组合 |
| 分布式 OLTP | TiDB v5.1+ | analyze_version = 2 |
| 分布式 MPP | CockroachDB 多列统计 | 自动收集开启 |
| 云原生 ETL | Spark SQL + AQE | `spark.sql.adaptive.enabled = true` |
| 实时分析 | Snowflake / BigQuery | 完全托管 |
| 新兴 OLAP | StarRocks / Doris + MCV | 启用自动 ANALYZE |

## 关键发现

1. **选择性估计是优化器最大的单一误差来源**。VLDB 2015 JOB 论文以来的研究一致证实，中间结果行数估计的相对误差在 4-5 表 JOIN 后可达 10^4 倍，而代价模型、JOIN 算法、索引等其他环节误差相对可控。

2. **没有 SQL 标准规定选择性算法**。ISO/IEC 9075 完全回避此话题，因此每个引擎的算法独立演进，差异巨大。跨引擎迁移查询性能无法简单"打平"。

3. **MCV + 直方图混合方案是行业共识**。PostgreSQL、Oracle 12c Hybrid、TiDB v5.1+、StarRocks、Doris 都采用"高频值单独存 + 低频值走直方图"的方案，精度和成本均衡。

4. **LIKE 模式估计是所有引擎的共同短板**。除前缀模式外，中缀 / 后缀 LIKE 几乎都退化为固定常量（0.005 ~ 0.09），实际误差可达千倍。n-gram 直方图、ML 模型是活跃研究方向。

5. **独立性假设是已知错误但必要的妥协**。所有引擎默认用 `sel(A × B) = sel(A) × sel(B)` 计算 AND，即使明知错误。仅 SQL Server NewCE 的指数退避、PostgreSQL/Oracle 的扩展统计提供部分修正。

6. **SQL Server 2014 NewCE 是最激进的 CE 重写**。NewCE 放弃了独立性和封闭性假设，引入指数退避和直方图对齐，是关系数据库优化器 20 年来最大一次重构。

7. **MySQL 在选择性估计上长期落后**。直到 8.0.3（2017）才有直方图，多列统计、扩展统计、指数退避、运行时反馈均未支持。依赖 InnoDB B+ 树的 `records_in_range` 弥补，但场景有限。

8. **Oracle 的 DENSITY 与 CBO 默认常量在绑定变量场景下仍在广泛使用**。9i 引入 bind peeking、12c 引入自适应游标共享（ACS），但参数绑定场景下固定常量（5%、10%）仍是兜底策略。

9. **参数化查询的选择性估计没有完美解**。PostgreSQL 5 次后切 generic plan、Oracle ACS、SQL Server `OPTIMIZE FOR UNKNOWN` 都是权宜之计。根本问题——"不知道参数值"——是信息论意义上的 fundamental limit。

10. **Top-N 与小域问题有成熟解法**。所有主流引擎都有"NDV 小于桶数自动切换频率直方图"的逻辑，但 Top-N 的桶数配置（PG 100、Oracle 254、MySQL 1024、TiDB 1024）差异巨大。

11. **运行时反馈正从 MPP 向 OLTP 渗透**。Spark AQE、Oracle Adaptive Plans、SQL Server Auto-Tuning 是代表，但 PostgreSQL 主线至今无原生闭环。

12. **JOB benchmark 是跨引擎选择性估计的事实标准**。Leis 等 2015 论文提出的 JOB 查询集已被广泛用于评测不同引擎的 CE 精度。CockroachDB、TiDB、DuckDB 等都用 JOB 回归测试自己的优化器演进。

13. **扩展统计的"何时创建"比"如何使用"更难**。PostgreSQL `CREATE STATISTICS`、Oracle `DBMS_STATS.CREATE_EXTENDED_STATS`、DB2 column group 在技术上已很成熟，但生产环境覆盖率普遍低于 5%。DBA 工具自动化这一步仍是开放问题。

14. **机器学习方向值得关注但尚未落地**。MSCN、DeepDB、NeuroCard 等学术方案展示了深度学习在选择性估计上的潜力，但训练成本、可解释性、边界情况三大问题使其仍未进入主流引擎。

15. **云原生托管服务的算法完全黑盒**。Snowflake、BigQuery、Firebolt、Spanner 不公开选择性估计实现。从公开行为猜测，它们大量依赖运行时反馈 + 自适应执行，而非静态统计。

## 参考资料

- Leis, V. et al. "How Good Are Query Optimizers, Really?" VLDB 2015.
- Selinger, P.G. et al. "Access Path Selection in a Relational Database Management System" SIGMOD 1979.
- Stillger, M. et al. "LEO - DB2's LEarning Optimizer" VLDB 2001.
- Ioannidis, Y.E., Christodoulakis, S. "On the Propagation of Errors in the Size of Join Results" SIGMOD 1991.
- PostgreSQL: [Row Estimation Examples](https://www.postgresql.org/docs/current/row-estimation-examples.html)
- PostgreSQL: [Extended Statistics](https://www.postgresql.org/docs/current/planner-stats.html#PLANNER-STATS-EXTENDED)
- Oracle: [Histograms and Cardinality Estimation](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgsql/histograms.html)
- Microsoft: [Cardinality Estimation (SQL Server 2014)](https://learn.microsoft.com/en-us/sql/relational-databases/performance/cardinality-estimation-sql-server)
- MySQL: [Optimizer Statistics](https://dev.mysql.com/doc/refman/8.0/en/optimizer-statistics.html)
- MySQL: [Histogram Statistics](https://dev.mysql.com/doc/refman/8.0/en/optimizer-statistics.html)
- DB2: [Cardinality Estimation and Statistics](https://www.ibm.com/docs/en/db2/11.5?topic=optimization-statistics)
- TiDB: [Introduction to Statistics](https://docs.pingcap.com/tidb/stable/statistics)
- CockroachDB: [Create Statistics](https://www.cockroachlabs.com/docs/stable/create-statistics.html)
- Kipf, A. et al. "Learned Cardinalities: Estimating Correlated Joins with Deep Learning" CIDR 2019.
- Hilprecht, B. et al. "DeepDB: Learn from Data, not from Queries" PVLDB 2020.
- Yang, Z. et al. "NeuroCard: One Cardinality Estimator for All Tables" VLDB 2021.
