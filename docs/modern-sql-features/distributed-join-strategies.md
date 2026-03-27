# 分布式 JOIN 策略

在分布式数据库中，JOIN 操作涉及跨网络的数据移动，是性能的关键瓶颈。选择正确的 JOIN 策略可以将查询时间从小时级降到秒级。

## 核心挑战

```
单机 JOIN: 数据在同一台机器的内存/磁盘中
分布式 JOIN: 数据分布在不同的物理节点上

关键问题: 如何让需要 JOIN 的数据"见面"?

方案:
  1. 小表广播到所有节点 (Broadcast JOIN)
  2. 两表按 JOIN key 重新洗牌到相同节点 (Shuffle JOIN)
  3. 数据本来就在同一节点 (Colocated JOIN)
  4. 查询外部系统获取数据 (Lookup JOIN)
```

## Broadcast JOIN (广播 JOIN)

### 工作原理

```
场景: 大表 A (10亿行, 分布在100个节点) JOIN 小表 B (1万行)

策略: 将小表 B 的完整副本发送到每个节点

执行过程:
  1. Coordinator 收集小表 B 的全量数据
  2. 将 B 的完整副本广播到 100 个节点
  3. 每个节点用本地的 A 分片与完整的 B 做本地 JOIN
  4. 无需移动大表 A 的数据

网络开销: |B| * N (B 的大小 * 节点数)
适用条件: |B| << 可用内存
```

### 各引擎语法

```sql
-- Spark SQL: 显式 hint
SELECT /*+ BROADCAST(b) */ a.*, b.name
FROM orders a JOIN products b ON a.product_id = b.id;

-- 或使用旧语法
SELECT /*+ MAPJOIN(b) */ a.*, b.name
FROM orders a JOIN products b ON a.product_id = b.id;

-- Spark 自动广播阈值 (默认 10MB)
SET spark.sql.autoBroadcastJoinThreshold = 10485760;

-- Apache Doris: hint 语法
SELECT a.*, b.name
FROM orders a JOIN [broadcast] products b ON a.product_id = b.id;

-- StarRocks: hint 语法
SELECT a.*, b.name
FROM orders a JOIN products b ON a.product_id = b.id;
-- StarRocks 基于 CBO 自动选择, 也支持 session 变量:
SET broadcast_row_limit = 15000000;

-- Trino: 自动选择, 通过配置控制
-- join-distribution-type = BROADCAST / PARTITIONED / AUTOMATIC

-- Flink SQL: hint 语法
SELECT /*+ BROADCAST(b) */ a.*, b.name
FROM orders a JOIN products b ON a.product_id = b.id;

-- BigQuery: 自动选择, 无用户 hint
-- 内部使用 Broadcast JOIN 处理小表

-- Hive: MapJoin
SELECT /*+ MAPJOIN(b) */ a.*, b.name
FROM orders a JOIN products b ON a.product_id = b.id;
-- 自动触发:
SET hive.auto.convert.join = true;  -- 默认 true
SET hive.mapjoin.smalltable.filesize = 25000000;  -- 25MB 阈值
```

### 优缺点

```
优点:
  - 大表数据不移动，网络开销取决于小表大小
  - 无需按 JOIN key 重新分区
  - 支持任意 JOIN 条件 (不限于等值)
  - 非等值 JOIN (如 a.ts BETWEEN b.start AND b.end) 的唯一实用方案

缺点:
  - 小表必须能放入每个节点的内存
  - 节点数越多，广播开销越大
  - 如果"小表"估算错误 (统计信息过时)，可能导致 OOM

阈值建议:
  - Spark 默认: 10MB
  - 生产实践: 通常 100MB~1GB 以内的表可以广播
  - 超过阈值: 切换到 Shuffle JOIN
```

## Shuffle JOIN (Hash Redistribute JOIN)

### 工作原理

```
场景: 大表 A (10亿行) JOIN 大表 B (5亿行), 都分布在100个节点

策略: 按 JOIN key 对两表重新分区, 相同 key 的数据发送到同一节点

执行过程:
  1. 对 A 和 B 的每一行, 计算 hash(join_key) % N (N = 节点数)
  2. 按 hash 值将数据发送到对应的节点
  3. 每个节点上, 本地的 A 分片和 B 分片做本地 Hash JOIN
  4. 汇总所有节点的结果

网络开销: |A| + |B| (两表都要移动)
适用条件: 两表都很大, 无法广播
```

### 各引擎语法

```sql
-- Spark SQL: 显式指定 Shuffle JOIN
SELECT /*+ SHUFFLE_HASH(a, b) */ a.*, b.*
FROM orders a JOIN customers b ON a.customer_id = b.id;

-- 或 Sort-Merge JOIN (适合两表都很大且已排序)
SELECT /*+ MERGE(a, b) */ a.*, b.*
FROM orders a JOIN customers b ON a.customer_id = b.id;

-- Doris: Shuffle JOIN
SELECT a.*, b.*
FROM orders a JOIN [shuffle] customers b ON a.customer_id = b.id;

-- Trino: Partitioned JOIN (= Shuffle JOIN)
SET join_distribution_type = 'PARTITIONED';

-- Flink SQL: 没有显式 hint, 自动选择
-- 可以通过 table.optimizer.join.broadcast-threshold 控制广播阈值
-- 超过阈值自动使用 Shuffle JOIN

-- ClickHouse: Distributed JOIN
-- 默认将右表发送到左表的节点 (类似 Broadcast)
-- 使用 GLOBAL JOIN 触发 Shuffle 行为:
SELECT a.*, b.*
FROM distributed_orders a
GLOBAL JOIN distributed_customers b ON a.customer_id = b.id;
```

### Shuffle 的变体

```
1. Hash Shuffle:
   - hash(key) % N 决定目标节点
   - 最常用, 负载可能不均匀 (数据倾斜)

2. Range Shuffle:
   - 按 key 的范围划分到不同节点
   - 适合需要有序输出的场景 (如 Sort-Merge JOIN)
   - 需要先采样确定范围边界

3. Partial Shuffle (部分洗牌):
   - 如果一表已按 JOIN key 分区, 只需洗牌另一表
   - 例: A 按 customer_id 分区, B 未分区
   - 只需对 B 按 hash(customer_id) 重新分布
```

## Colocated JOIN (本地化 JOIN)

### 工作原理

```
场景: 两表在建表时就按 JOIN key 分布到相同节点

前提: A 和 B 都按 customer_id 分区, 相同 customer_id 在同一节点
效果: JOIN 不需要任何网络数据移动!

这是分布式 JOIN 的理想情况, 性能接近单机 JOIN。
```

### 各引擎的 Colocated 设计

```sql
-- Google Spanner: Interleaved Tables
CREATE TABLE customers (
    customer_id INT64 NOT NULL
) PRIMARY KEY (customer_id);

CREATE TABLE orders (
    customer_id INT64 NOT NULL,
    order_id INT64 NOT NULL
) PRIMARY KEY (customer_id, order_id),
  INTERLEAVE IN PARENT customers ON DELETE CASCADE;
-- orders 的数据物理上与 customers 的数据交错存储
-- JOIN 不需要网络传输

-- CockroachDB: 相同分区策略
-- 如果两表都按相同列做 HASH 分区, 自动 Colocated JOIN

-- TiDB: 无显式 Colocated 语法
-- 但如果两表的 Region 恰好包含相同的 key range, 可以本地 JOIN

-- StarRocks: Colocate Join Group
CREATE TABLE orders (
    order_id BIGINT,
    customer_id BIGINT
)
DISTRIBUTED BY HASH(customer_id) BUCKETS 32
PROPERTIES ("colocate_with" = "group1");

CREATE TABLE customers (
    customer_id BIGINT,
    name VARCHAR(100)
)
DISTRIBUTED BY HASH(customer_id) BUCKETS 32
PROPERTIES ("colocate_with" = "group1");
-- 同一 group 中, 相同 hash 值的数据保证在同一节点

-- Doris: 类似 StarRocks 的 Colocate Join
CREATE TABLE orders (...)
DISTRIBUTED BY HASH(customer_id) BUCKETS 32
PROPERTIES ("colocate_with" = "group1");

-- Greenplum: Distribution Key
CREATE TABLE orders (...)
DISTRIBUTED BY (customer_id);
CREATE TABLE customers (...)
DISTRIBUTED BY (customer_id);
-- 相同 distribution key 的表自动 Colocated JOIN
```

### Colocated JOIN 的限制

```
1. 分区键限制:
   - 只有按 JOIN key 分区时才能 Colocated
   - 如果 A 按 customer_id 分区, 但 JOIN 条件是 order_date, 无法 Colocated

2. 分区数必须一致:
   - A 32 个桶, B 也必须 32 个桶
   - 桶数不同时即使分区键相同, 也无法 Colocated

3. 多表 JOIN 的局限:
   - A JOIN B ON a.x = b.x JOIN C ON b.y = c.y
   - A/B 可以 Colocated (按 x), 但 B/C (按 y) 可能不行
   - 至少有一个 JOIN 需要 Shuffle

4. 数据倾斜:
   - 热点 key 导致某些节点数据量远大于其他节点
   - Colocated JOIN 无法通过重新洗牌来平衡负载
```

## Lookup JOIN (探测 JOIN)

### 工作原理

```
场景: 流处理或实时查询中, 需要关联外部维表

策略: 对主表的每一行, 去外部系统查询匹配的数据

典型用例:
  - Flink 流处理: 流数据 JOIN Redis/MySQL/HBase 中的维表
  - 实时查询: 主表在分析引擎, 维表在 OLTP 数据库
```

### Flink SQL 的 Lookup JOIN

```sql
-- Flink SQL: Lookup Join 是一等公民
-- 基于 LATERAL TABLE 或 FOR SYSTEM_TIME AS OF 语法

-- 定义外部维表
CREATE TABLE products (
    id BIGINT,
    name STRING,
    price DECIMAL(10,2),
    PRIMARY KEY (id) NOT ENFORCED
) WITH (
    'connector' = 'jdbc',
    'url' = 'jdbc:mysql://localhost:3306/db',
    'table-name' = 'products',
    'lookup.cache.max-rows' = '10000',
    'lookup.cache.ttl' = '1h'
);

-- Lookup Join: 流表关联维表
SELECT o.order_id, o.product_id, p.name, p.price
FROM orders o
JOIN products FOR SYSTEM_TIME AS OF o.proc_time AS p
ON o.product_id = p.id;

-- 关键参数:
-- lookup.cache.max-rows: 本地缓存的最大行数
-- lookup.cache.ttl: 缓存过期时间
-- lookup.max-retries: 查询失败重试次数
-- lookup.async: 是否异步查询 (提高吞吐量)
```

### Lookup JOIN 的优化

```
1. 本地缓存:
   - LRU Cache 缓存最近查询的结果
   - 减少外部系统的压力
   - TTL 控制缓存新鲜度

2. 批量查询:
   - 收集多行的查询条件, 合并为一次批量查询
   - 例: WHERE id IN (1, 2, 3, ...) 代替逐行查询
   - 显著减少网络往返次数

3. 异步 I/O:
   - 不等待上一行的查询结果, 继续处理后续行
   - 利用异步客户端并发查询
   - Flink: AsyncDataStream API

4. 预加载:
   - 启动时全量加载维表到本地
   - 定期刷新或监听变更日志
   - 适合小维表 (< 可用内存)
```

## Semi JOIN 与 Anti JOIN 的分布式优化

### Semi JOIN 下推

```sql
-- Semi JOIN: 只检查存在性, 不返回右表数据
SELECT * FROM orders o
WHERE EXISTS (SELECT 1 FROM vip_customers v WHERE v.id = o.customer_id);

-- 分布式优化: Bloom Filter 下推
-- 1. 先在 vip_customers 上构建 Bloom Filter
-- 2. 将 Bloom Filter (很小, 几KB) 广播到所有节点
-- 3. 每个节点用 Bloom Filter 预过滤 orders
-- 4. 大幅减少需要 Shuffle 的数据量

-- Spark SQL:
SET spark.sql.optimizer.dynamicPartitionPruning.enabled = true;
-- 自动使用 Runtime Filter / Bloom Filter

-- Trino:
SET enable_dynamic_filtering = true;
-- 动态过滤: 构建阶段收集 JOIN key 的范围/Bloom Filter

-- StarRocks:
-- Runtime Filter 自动开启, 支持:
-- IN Filter: 精确的值集合 (小基数)
-- Bloom Filter: 概率过滤 (大基数)
-- Min-Max Filter: 范围过滤
```

### Anti JOIN 优化

```sql
-- Anti JOIN: 找不存在的行
SELECT * FROM orders o
WHERE NOT EXISTS (SELECT 1 FROM cancelled c WHERE c.order_id = o.order_id);

-- 分布式策略:
-- 1. 如果 cancelled 表很小: Broadcast + 本地 Anti JOIN
-- 2. 如果 cancelled 表很大: Shuffle + 本地 Anti JOIN
-- 3. Bloom Filter 不适用于 Anti JOIN (假阳性会导致错误排除)

-- NOT IN 的分布式陷阱:
SELECT * FROM orders WHERE order_id NOT IN (SELECT order_id FROM cancelled);
-- 如果 cancelled 中有 NULL:
-- 1. 必须先检查是否存在 NULL
-- 2. 如果存在 NULL, 结果为空集
-- 3. 这个检查需要全局聚合, 增加一轮网络通信
-- 建议: 分布式环境中始终用 NOT EXISTS 代替 NOT IN
```

## 数据倾斜处理

### 问题

```
场景: 订单表按 customer_id 做 Shuffle JOIN
大客户 customer_id = 12345 有 1000 万订单
其他客户平均 100 订单

结果: 处理 12345 的节点需要处理的数据量是其他节点的 10 万倍
     其他节点早已完成, 整个查询被一个节点拖慢
```

### 解决方案

```sql
-- Spark SQL: Adaptive Query Execution (AQE)
SET spark.sql.adaptive.enabled = true;
SET spark.sql.adaptive.skewJoin.enabled = true;
SET spark.sql.adaptive.skewJoin.skewedPartitionThresholdInBytes = 256MB;
-- AQE 在运行时检测倾斜分区, 自动拆分为多个子任务

-- Hive: Skew JOIN 优化
SET hive.optimize.skewjoin = true;
SET hive.skewjoin.key = 100000;  -- 超过此行数视为倾斜
-- 倾斜的 key 使用 Broadcast JOIN, 其他 key 使用 Shuffle JOIN

-- 手动处理: 拆分查询
-- 步骤 1: 倾斜 key 单独处理 (Broadcast JOIN)
SELECT /*+ BROADCAST(b) */ a.*, b.*
FROM orders a JOIN customers b ON a.customer_id = b.id
WHERE a.customer_id IN (12345, 67890);  -- 已知的热点 key

UNION ALL

-- 步骤 2: 非倾斜 key 正常 Shuffle JOIN
SELECT a.*, b.*
FROM orders a JOIN customers b ON a.customer_id = b.id
WHERE a.customer_id NOT IN (12345, 67890);

-- 手动处理: 加盐 (Salt)
-- 对倾斜 key 加随机后缀, 分散到多个节点
-- 右表对应地复制多份
SELECT a.*, b.*
FROM (
    SELECT *, CONCAT(customer_id, '_', FLOOR(RAND() * 10)) AS salted_key
    FROM orders
) a
JOIN (
    SELECT c.*, CONCAT(c.id, '_', s.salt) AS salted_key
    FROM customers c
    CROSS JOIN (SELECT 0 AS salt UNION ALL SELECT 1 UNION ALL ... SELECT 9) s
) b
ON a.salted_key = b.salted_key;
```

## 各引擎 JOIN 策略对比

| 特性 | Spark | Trino | Flink | StarRocks | Doris | ClickHouse |
|------|-------|-------|-------|----------|-------|-----------|
| Broadcast JOIN | Y (hint) | Y (自动) | Y (hint) | Y (自动) | Y (hint) | Y (默认右表) |
| Shuffle JOIN | Y | Y | Y | Y | Y | GLOBAL JOIN |
| Colocated JOIN | Y (bucket) | N | N | Y (colocate_with) | Y (colocate_with) | N |
| Lookup JOIN | N | N | Y (原生) | N | N | N |
| Runtime Filter | Y (AQE) | Y (动态过滤) | N | Y (自动) | Y (自动) | N |
| 倾斜处理 | Y (AQE) | N | N | N | N | N |
| 自动选择 | Y (CBO) | Y (CBO) | 部分 | Y (CBO) | Y (CBO) | 有限 |

## 对引擎开发者的建议

### JOIN 策略选择器的实现

```
输入: 两表的统计信息 (行数, 大小, 分布)
输出: 最优的 JOIN 策略

算法:
  1. 如果两表 Colocated (相同分区键、相同桶数):
     -> Colocated JOIN (最优, 零网络开销)

  2. 如果一表 < 广播阈值:
     -> Broadcast JOIN (将小表广播)

  3. 如果两表都很大:
     -> Shuffle JOIN
     -> 进一步选择: Hash JOIN vs Sort-Merge JOIN
        - Hash JOIN: 右表能放入内存时首选
        - Sort-Merge JOIN: 两表都超大时使用, 可 spill to disk

  4. 运行时自适应 (AQE):
     -> 如果统计信息不准确, 在执行过程中切换策略
     -> 例: 预估的"小表"实际很大 -> 从 Broadcast 切换到 Shuffle
```

### 关键实现考量

```
1. 网络拓扑感知:
   - 同机架的数据移动代价 < 跨机架
   - Shuffle 时优先将数据发送到同机架节点
   - 考虑网络带宽和延迟

2. 内存管理:
   - Broadcast JOIN: 需要在每个节点缓存完整的小表
   - Hash JOIN: 需要在内存中构建 hash table
   - 超出内存时: 溢出到磁盘 (Grace Hash JOIN)

3. 流水线执行:
   - Shuffle 数据的发送和接收可以流水线化
   - 不需要等所有数据 Shuffle 完成才开始 JOIN
   - 减少端到端延迟

4. 故障恢复:
   - Shuffle 过程中节点故障: 需要重新 Shuffle
   - 中间结果物化: 可以从 checkpoint 恢复
   - Spark 的 RDD lineage 提供天然的故障恢复

5. 统计信息的准确性:
   - JOIN 策略依赖统计信息 (表大小、基数、倾斜度)
   - 统计信息不准确 = 错误的策略选择
   - 建议: 支持运行时自适应 (AQE 思路)
```

## 参考资料

- Google: [MapReduce: Simplified Data Processing on Large Clusters](https://research.google/pubs/pub62/)
- Spark: [Adaptive Query Execution](https://spark.apache.org/docs/latest/sql-performance-tuning.html#adaptive-query-execution)
- Trino: [Distributed Query Processing](https://trino.io/docs/current/overview/concepts.html)
- Flink: [Lookup Join](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/queries/joins/#lookup-join)
- StarRocks: [Colocate Join](https://docs.starrocks.io/docs/using_starrocks/Colocate_join/)
- CockroachDB: [Distributed SQL](https://www.cockroachlabs.com/docs/stable/architecture/sql-layer.html)
