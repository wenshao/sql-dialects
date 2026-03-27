# 近似计算函数

用 2% 的误差换 100 倍的速度——大数据时代的务实选择，将概率数据结构从论文带入 SQL 函数库。

## 支持矩阵

### APPROX_COUNT_DISTINCT（近似去重计数）

| 引擎 | 函数名 | 算法 | 版本 | 误差率 |
|------|--------|------|------|--------|
| BigQuery | `APPROX_COUNT_DISTINCT` | HyperLogLog++ | GA | ~1% |
| Oracle | `APPROX_COUNT_DISTINCT` | HLL | 12c+ | ~2% |
| Redshift | `APPROXIMATE COUNT(DISTINCT ...)` | HLL | GA | ~2% |
| ClickHouse | `uniq` | 自适应 | 早期版本 | ~1.5% |
| ClickHouse | `uniqHLL12` | HyperLogLog | 早期版本 | ~1.6% |
| ClickHouse | `uniqExact` | 精确 hash | 早期版本 | 0%（精确） |
| Snowflake | `APPROX_COUNT_DISTINCT` / `HLL` | HLL | GA | ~1.6% |
| PostgreSQL | `hll_cardinality` (扩展) | HLL | pg_hll 扩展 | ~2% |
| Spark SQL | `approx_count_distinct` | HLL | 1.6+ | 可配置 |
| Trino | `approx_distinct` | HLL | 早期版本 | 可配置 |
| DuckDB | `approx_count_distinct` | HLL | 0.8+ | ~2% |
| MySQL | 不支持 | - | - | - |
| SQL Server | 不支持 | - | - | - |

### APPROX_PERCENTILE（近似分位数）

| 引擎 | 函数名 | 算法 | 备注 |
|------|--------|------|------|
| BigQuery | `APPROX_QUANTILES` | GK 算法 | 返回分位数数组 |
| ClickHouse | `quantile` | t-digest | 默认近似 |
| ClickHouse | `quantileExact` | 排序 | 精确但慢 |
| Hive | `percentile_approx` | GK 算法 | - |
| Spark SQL | `percentile_approx` | GK 算法 | - |
| Trino | `approx_percentile` | qdigest | 可配置精度 |
| Snowflake | `APPROX_PERCENTILE` | t-digest | - |
| DuckDB | `approx_quantile` | t-digest | - |
| PostgreSQL | `percentile_cont` | 精确排序 | 无近似版本 |
| Oracle | `APPROX_MEDIAN` / `APPROX_PERCENTILE` | t-digest | 19c+ |

### 其他近似函数

| 函数 | 引擎 | 说明 |
|------|------|------|
| `APPROX_TOP_COUNT` | BigQuery | 近似 Top-N 频次 |
| `topK` | ClickHouse | 近似 Top-K（Space-Saving 算法） |
| `approx_most_frequent` | Trino | 近似最频繁值 |
| `APPROX_SET` | Trino | HLL 草图对象（可合并） |
| `uniqCombined` | ClickHouse | 自适应精度（小集合精确，大集合近似） |

## 设计动机: 精确计算的代价

### 问题规模

```
场景: 统计过去 30 天的独立用户数
数据量: 100 亿行日志
用户数: 5 亿

COUNT(DISTINCT user_id):
- 需要全局去重: 5 亿个 user_id 的 hash set ≈ 4-8 GB 内存
- 分布式环境: 所有节点的数据必须 shuffle 到一起
- 执行时间: 分钟级

APPROX_COUNT_DISTINCT(user_id):
- HyperLogLog 占用: 约 12 KB 固定内存
- 可分布式合并: 各节点独立计算后合并 sketch
- 执行时间: 秒级
- 误差: ±2%（5 亿 ± 1000 万）
```

在多数业务场景中，"5.02 亿" 和 "5 亿" 的差异完全可以接受。

## 核心算法

### 1. HyperLogLog (HLL) —— 去重计数

```
原理（极简版）:
1. 对每个值计算 hash
2. 观察 hash 值的前导零个数
3. 前导零越多，说明见过的不同值越多
4. 用 m 个桶分别记录最大前导零数，取调和平均

空间: O(m) = 典型 2^12 = 4096 个桶 × 6 bit = 3 KB
误差: 1.04 / sqrt(m) ≈ 1.6%（m = 4096 时）
```

HyperLogLog 的精妙之处在于空间复杂度与数据量无关——无论 1 万还是 100 亿个不同值，都只需要几 KB。

**HyperLogLog++ (HLL++)**

Google 改进版，BigQuery 使用：
- 小基数时使用线性计数（更精确）
- 大基数时使用稀疏表示（节省空间）
- 偏差修正更精确

### 2. t-digest —— 分位数估计

```
原理:
1. 维护一组"质心"（centroid），每个质心有均值和权重
2. 新数据点合并到最近的质心
3. 靠近 0% 和 100% 分位的质心更精细（压缩率低）
4. 中间部分的质心更粗糙（压缩率高）

空间: O(compression_factor) ≈ 数百字节到数 KB
误差: 两端精确（p=0.01, p=0.99），中间较粗
```

t-digest 的设计巧妙之处在于在人们最关心的极端分位数（P99, P999）上最精确。

### 3. Count-Min Sketch —— 频次估计

```
原理:
1. 一个 d × w 的计数器矩阵
2. 每个元素经 d 个 hash 函数映射到矩阵的 d 行
3. 查询时取 d 行中的最小值

空间: O(d × w)
误差: 可能高估（从不低估），误差随 w 增大而减小
用途: Top-K、频次查询
```

### 4. KLL Sketch —— 分位数估计（更新的算法）

```
原理:
1. 多层压缩器（compactor），低层保留更多样本
2. 当一层满时，随机丢弃一半样本并传入上一层
3. 查询时合并所有层的样本

空间: O(1/epsilon * log(1/delta)) 其中 epsilon=误差, delta=失败概率
优势: 比 t-digest 有更好的理论误差保证
```

## 语法对比

### BigQuery

```sql
-- 近似去重计数
SELECT
    DATE(event_time) AS dt,
    APPROX_COUNT_DISTINCT(user_id) AS approx_uv,
    COUNT(DISTINCT user_id) AS exact_uv  -- 对比
FROM events
GROUP BY 1;

-- 近似分位数（返回 N+1 个分位点的数组）
SELECT
    APPROX_QUANTILES(response_time_ms, 100) AS percentiles,
    -- percentiles[OFFSET(50)] = P50
    -- percentiles[OFFSET(95)] = P95
    -- percentiles[OFFSET(99)] = P99
FROM api_logs;

-- APPROX_TOP_COUNT: 近似 Top-N
SELECT APPROX_TOP_COUNT(search_query, 10) AS top_searches
FROM search_logs;
-- 结果: [{value: "ChatGPT", count: 15000}, {value: "SQL", count: 12000}, ...]
```

### ClickHouse

```sql
-- uniq: ClickHouse 默认的近似去重（自适应算法）
SELECT uniq(user_id) FROM events;

-- uniqExact: 精确去重（当需要精确值时）
SELECT uniqExact(user_id) FROM events;

-- uniqHLL12: 指定使用 HyperLogLog
SELECT uniqHLL12(user_id) FROM events;

-- uniqCombined: 小集合精确 + 大集合近似（自动切换）
SELECT uniqCombined(user_id) FROM events;

-- quantile: 近似分位数（默认 t-digest）
SELECT
    quantile(0.5)(response_time)  AS p50,
    quantile(0.95)(response_time) AS p95,
    quantile(0.99)(response_time) AS p99
FROM api_logs;

-- quantiles: 一次计算多个分位数
SELECT quantiles(0.5, 0.9, 0.95, 0.99)(response_time)
FROM api_logs;

-- topK: 近似 Top-K
SELECT topK(10)(search_query) FROM search_logs;

-- 组合使用 -State / -Merge 实现增量聚合
-- 先存储中间状态
INSERT INTO agg_table
SELECT date, uniqState(user_id) AS uv_state FROM events GROUP BY date;

-- 后续合并
SELECT uniqMerge(uv_state) FROM agg_table WHERE date BETWEEN '2024-01-01' AND '2024-01-31';
```

### Trino

```sql
-- approx_distinct: 近似去重
SELECT approx_distinct(user_id) FROM events;

-- 指定精度（标准误差）
SELECT approx_distinct(user_id, 0.01) FROM events;  -- 1% 误差

-- approx_percentile: 近似分位数
SELECT
    approx_percentile(response_time, 0.5) AS p50,
    approx_percentile(response_time, 0.99) AS p99,
    approx_percentile(response_time, ARRAY[0.5, 0.9, 0.95, 0.99]) AS percentiles
FROM api_logs;

-- approx_percentile 带权重
SELECT approx_percentile(amount, weight, 0.5) AS weighted_median
FROM sales;

-- APPROX_SET: 返回 HLL 对象（可存储、可合并）
SELECT APPROX_SET(user_id) AS hll_sketch FROM events;
```

### Oracle 19c+

```sql
-- APPROX_COUNT_DISTINCT
SELECT
    region,
    APPROX_COUNT_DISTINCT(customer_id) AS approx_customers,
    APPROX_COUNT_DISTINCT(customer_id, 'MAX_REL_ERROR=0.01') AS precise_approx
FROM orders
GROUP BY region;

-- APPROX_MEDIAN
SELECT APPROX_MEDIAN(salary) FROM employees;

-- APPROX_PERCENTILE
SELECT
    dept,
    APPROX_PERCENTILE(0.9) WITHIN GROUP (ORDER BY salary) AS p90_salary
FROM employees
GROUP BY dept;

-- APPROX_RANK: 返回值的近似排名
SELECT APPROX_RANK(100000 WITHIN GROUP (ORDER BY salary)) FROM employees;
```

### Snowflake

```sql
-- APPROX_COUNT_DISTINCT (HLL)
SELECT APPROX_COUNT_DISTINCT(user_id) FROM events;

-- HLL: 返回 HLL 对象
SELECT HLL(user_id) FROM events;

-- HLL_ACCUMULATE + HLL_COMBINE + HLL_ESTIMATE
-- 分步操作，适用于增量计算
INSERT INTO daily_sketches
SELECT date, HLL_ACCUMULATE(user_id) AS sketch FROM events GROUP BY date;

SELECT HLL_ESTIMATE(HLL_COMBINE(sketch)) AS monthly_uv
FROM daily_sketches
WHERE date BETWEEN '2024-01-01' AND '2024-01-31';

-- APPROX_PERCENTILE
SELECT APPROX_PERCENTILE(response_time, 0.95) FROM api_logs;
```

## 关键特性: 可合并性

近似计算函数的杀手级特性是**可合并性（mergeability）**——多个中间结果可以合并为一个最终结果，且不损失精度。

```
精确 COUNT(DISTINCT):
  节点1: {A, B, C} → 3
  节点2: {B, C, D} → 3
  合并: 3 + 3 = 6 ← 错误！（B, C 被重复计算）
  正确合并需要: 传输完整的值集合

HyperLogLog:
  节点1: sketch_1 (12 KB)
  节点2: sketch_2 (12 KB)
  合并: merge(sketch_1, sketch_2) → final_sketch (12 KB)
  估计: estimate(final_sketch) → 4 ← 正确！

合并操作: 对应桶取 MAX
空间固定: 无论合并多少个 sketch，结果大小不变
```

这使得近似函数在以下场景中极为强大：

| 场景 | 精确计算 | 近似计算 |
|------|---------|---------|
| 分布式聚合 | shuffle 全量数据 | 合并 sketch（KB 级） |
| 增量计算 | 重新扫描全量 | 合并新旧 sketch |
| 多维上卷 | 无法从细粒度推导 | sketch 可上卷 |
| 预聚合存储 | 存储原始值集合 | 存储 sketch（固定大小） |

## 对引擎开发者的实现建议

### 1. 注册为聚合函数

近似函数在引擎框架中是标准的聚合函数，需要实现：

```
ApproxCountDistinct Accumulator {
    hll: HyperLogLog

    fn init():
        hll = new HyperLogLog(precision=12)

    fn update(value):
        if value is not null:
            hll.add(hash(value))

    fn merge(other: ApproxCountDistinct):
        hll.merge(other.hll)

    fn result() -> INT64:
        return hll.estimate()
}
```

### 2. 序列化支持

为了支持分布式聚合和预聚合存储，sketch 需要高效的序列化/反序列化：

```
HLL 序列化格式（ClickHouse 风格）:
[1 byte: 版本] [1 byte: precision] [m bytes: 桶数据]

t-digest 序列化格式:
[4 bytes: centroid 数量] [每个 centroid: 8 bytes mean + 4 bytes weight]
```

### 3. 精度参数

建议提供用户可调的精度参数：

```sql
-- Trino 风格: 标准误差参数
SELECT approx_distinct(user_id, 0.01) FROM events;  -- 1% 误差
SELECT approx_distinct(user_id, 0.05) FROM events;  -- 5% 误差（更快）

-- 内部: 精度映射到 HLL 的桶数
-- 0.01 → precision=14 (16384 桶, 约 12 KB)
-- 0.05 → precision=10 (1024 桶, 约 768 B)
```

### 4. 小基数优化

HyperLogLog 在小基数（< 数千）时误差较大。推荐实现自适应策略：

```
小基数（< 阈值）: 使用精确 hash set
大基数（>= 阈值）: 切换到 HLL

ClickHouse 的 uniqCombined 就是这个策略:
  基数 < 65536: 使用 hash set（精确）
  基数 >= 65536: 转换为 HLL（近似）
```

### 5. 与精确函数的兼容

建议引擎在查询计划层提供自动替换选项：

```sql
-- 用户设置: 允许优化器在大数据量时自动使用近似函数
SET approximate_distinct_count = true;

-- 优化器自动将 COUNT(DISTINCT x) 替换为 APPROX_COUNT_DISTINCT(x)
-- 当估计输入行数 > 阈值时触发
```

## 精度 vs 性能: 实测参考

| 函数 | 数据量 | 精确时间 | 近似时间 | 加速比 | 误差 |
|------|--------|---------|---------|--------|------|
| COUNT DISTINCT | 1 亿行, 1000 万基数 | 45s | 3s (HLL) | 15x | 1.2% |
| COUNT DISTINCT | 100 亿行, 5 亿基数 | 超时 | 15s (HLL) | - | 1.5% |
| PERCENTILE | 1 亿行 | 120s (排序) | 5s (t-digest) | 24x | P99 误差 <0.5% |
| TOP-K (K=10) | 10 亿行 | 300s (排序) | 8s (Space-Saving) | 37x | Top-5 通常精确 |

## 设计讨论

### 什么时候不该用近似函数？

1. **财务报表**: 金额统计必须精确，不接受误差
2. **小数据量**: 数据量不大时精确计算已经很快，近似无意义
3. **需要精确排序**: 近似 Top-K 可能遗漏真实的 Top 元素
4. **合规审计**: 某些合规场景要求精确数字

### 近似函数应该默认启用吗？

ClickHouse 的 `quantile` 默认就是近似的，`quantileExact` 才是精确的。这个设计选择体现了 ClickHouse "速度优先"的哲学。但对传统数据库用户可能造成困惑——他们期望函数返回精确结果。

推荐做法: 近似函数使用明确的名称（如 `APPROX_` 前缀），不要在标准函数名上默认使用近似算法。

## 参考资料

- Flajolet, P. et al. "HyperLogLog: the analysis of a near-optimal cardinality estimation algorithm" (2007)
- Dunning, T. "The t-digest: Efficient estimates of distributions" (2019)
- Karnin, Z. et al. "Optimal Quantile Approximation in Streams" (KLL, 2016)
- BigQuery: [Approximate Aggregate Functions](https://cloud.google.com/bigquery/docs/reference/standard-sql/approximate_aggregate_functions)
- ClickHouse: [Approximate Functions](https://clickhouse.com/docs/en/sql-reference/aggregate-functions/reference/uniq)
- Trino: [Approximate Functions](https://trino.io/docs/current/functions/aggregate.html#approximate-aggregate-functions)
