# ClickHouse: CREATE TABLE

> 参考资料:
> - [1] ClickHouse SQL Reference - CREATE TABLE
>   https://clickhouse.com/docs/en/sql-reference/statements/create/table
> - [2] ClickHouse - Table Engines
>   https://clickhouse.com/docs/en/engines/table-engines
> - [3] ClickHouse - MergeTree Family
>   https://clickhouse.com/docs/en/engines/table-engines/mergetree-family
> - [4] ClickHouse - Data Compression Codecs
>   https://clickhouse.com/docs/en/sql-reference/statements/create/table#column_compression_codec


## 基本建表（必须指定引擎!）

ClickHouse 不是通用数据库。它是列式 OLAP 引擎。
每一个建表决策都直接影响查询性能，不像行式数据库那样有通用的"好实践"。

```sql
CREATE TABLE users (
    id         UInt64,
    username   String,
    email      String,
    age        Nullable(UInt8),              -- 默认不可 NULL! 必须显式 Nullable
    balance    Decimal(10,2),
    bio        Nullable(String),
    tags       Array(String),                -- 原生数组，一等公民
    properties Map(String, String),          -- 原生 Map (21.1+)
    created_at DateTime DEFAULT now(),
    updated_at DateTime DEFAULT now()
)
ENGINE = MergeTree()
ORDER BY id;

```

 设计要点:
1. Nullable 有代价: 内部额外维护一列 UInt8 标记 null/non-null，查询时多一次 check

      如果业务允许，用默认值代替 Nullable (空字符串、0、'1970-01-01' 等)
2. String 没有长度限制 (不是 VARCHAR)，内部存储为 length + bytes

3. LowCardinality(String) 比 String 快 2-10x (当基数 < 10000 时)，见下文

4. 没有主键约束、唯一约束、外键 — ClickHouse 不是用来做 OLTP 的


## MergeTree 引擎家族: 决策树

 MergeTree 是 ClickHouse 的核心。选错引擎 = 性能灾难或数据语义错误。

 问自己这些问题:

 Q: 需要去重吗?
 ├─ 否 → MergeTree (最简单、最快)
 └─ 是
    ├─ 需要精确去重 + 完整行替换? → ReplacingMergeTree
    ├─ 需要"取消"旧行 + 插入新行? → CollapsingMergeTree
    ├─ 数据可能乱序到达? → VersionedCollapsingMergeTree
    └─ 需要预聚合?
       ├─ 简单求和? → SummingMergeTree
       └─ 复杂聚合 (uniq, quantile 等)? → AggregatingMergeTree

 注意: 所有 MergeTree 系列的"合并"都是后台异步的!
 查询时可能看到未合并的数据 (重复行、未折叠的行)
 解决: 用 FINAL 关键字强制合并读取 (有性能代价)
 或在 SELECT 中用 GROUP BY + argMax 手动去重 (推荐大数据量场景)

## ORDER BY: 不只是排序 — 它决定数据物理布局

 这是从传统数据库转过来最容易误解的概念:
 ORDER BY 在 MergeTree 中不是"查询时排序"，而是"数据在磁盘上的物理排列方式"
 相当于 MySQL 的聚簇索引 + PostgreSQL 的 CLUSTER

 选择 ORDER BY 的原则:
1. 把查询中最常出现在 WHERE/GROUP BY 的列放进来

2. 低基数列在前，高基数列在后（和 MySQL 索引相反!）

      原因: ClickHouse 用稀疏索引，低基数列在前可以跳过更多 granule
3. 不要放太多列 (3-5 个为宜)，每多一列增加 INSERT 时排序开销

4. 列顺序 = 索引列顺序，决定哪些查询能利用索引


```sql
CREATE TABLE events (
    event_date Date,
    user_id    UInt64,
    event_type LowCardinality(String),       -- 枚举类的值用 LowCardinality
    event_id   UInt64,
    payload    String
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (event_type, user_id, event_date);  -- 低基数 → 高基数

```

 WHERE event_type = 'click' → 极快 (第一列精确匹配)
 WHERE event_type = 'click' AND user_id = 12345 → 快 (前两列匹配)
 WHERE user_id = 12345 → 慢! (跳过了第一列，和 MySQL 联合索引一样的最左前缀问题)
 对于必须跳列的查询，用数据 Skipping Index 或 Projection (见下文)

## PRIMARY KEY vs ORDER BY: 什么时候应该不同

默认 PRIMARY KEY = ORDER BY，但可以显式指定 PRIMARY KEY 为 ORDER BY 的前缀

```sql
CREATE TABLE orders (
    order_date Date,
    user_id    UInt64,
    product_id UInt64,
    amount     Decimal(10,2),
    quantity   UInt32
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(order_date)
ORDER BY (user_id, product_id, order_date)   -- 磁盘上的物理排序
PRIMARY KEY (user_id, product_id)            -- 稀疏索引只索引前两列
SETTINGS index_granularity = 8192;

```

 为什么要分开?
   PRIMARY KEY 决定稀疏索引大小 (存在内存中)
   ORDER BY 决定磁盘排列 (影响压缩率和范围查询)
   如果 ORDER BY 有 5 列，但查询通常只过滤前 2 列，
   PRIMARY KEY 设为前 2 列可以减小内存中的索引大小

 index_granularity = 8192 (默认):
   每 8192 行创建一个索引条目 (稀疏索引)
   减小 → 索引更精确但占更多内存
   增大 → 索引更小但扫描范围更大
   99% 的场景用默认值

## 分区 (PARTITION BY): 常见的过度分区陷阱

分区是数据管理单位 (删除、移动、备份)，不是查询优化手段!
ORDER BY 才是查询优化手段。

好的分区:

```sql
PARTITION BY toYYYYMM(event_date)            -- 按月: 一年 12 个分区
```

 PARTITION BY toYear(event_date)           -- 按年: 分区更少
 PARTITION BY toMonday(event_date)         -- 按周: 52 个/年

 坏的分区 (过度分区):
 PARTITION BY event_date                   -- 按天: 365 个/年，3 年就 1000+ 分区
 PARTITION BY (toYYYYMM(date), region)     -- 月 × 地区: 分区数爆炸

 过度分区的危害:
1. 每个分区至少一个 data part → 文件数暴增 → 文件系统压力

2. INSERT 时每个分区生成一个 part → 小文件合并风暴

3. SELECT 时打开大量文件描述符 → 慢

4. 官方建议: 分区数不超过 1000，理想情况下 < 100


 经验法则: PARTITION BY toYYYYMM() 是大多数场景的最佳选择
 如果表只有几百万行，不分区也完全没问题

## TTL: 数据生命周期管理

```sql
CREATE TABLE logs (
    timestamp DateTime,
    level     LowCardinality(String),
    message   String,
    trace     Nullable(String)
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (level, timestamp)
TTL timestamp + INTERVAL 90 DAY                -- 90 天后删除整行
SETTINGS merge_with_ttl_timeout = 86400;       -- 每 24 小时检查一次 TTL

```

列级 TTL: 只删除某些列的数据（节省空间但保留摘要）

```sql
CREATE TABLE metrics_with_ttl (
    ts      DateTime,
    host    LowCardinality(String),
    cpu     Float32,
    detail  String TTL ts + INTERVAL 7 DAY,    -- 7 天后 detail 列清空
    trace   String TTL ts + INTERVAL 1 DAY     -- 1 天后 trace 列清空
)
ENGINE = MergeTree()
ORDER BY (host, ts)
TTL ts + INTERVAL 365 DAY;                     -- 1 年后整行删除

```

 多级 TTL: 数据在不同存储层之间迁移
 TTL ts + INTERVAL 7 DAY TO VOLUME 'cold',   -- 7 天后移到冷存储
     ts + INTERVAL 90 DAY TO VOLUME 'archive', -- 90 天后移到归档
     ts + INTERVAL 365 DAY DELETE              -- 1 年后删除

 TTL 执行时机:
   后台合并时检查 → 不是精确到秒的删除
   merge_with_ttl_timeout 控制最小间隔
   手动触发: ALTER TABLE logs MATERIALIZE TTL

## 压缩编码 (Codecs): 选对编码 = 节省 50-90% 存储

ClickHouse 的列式存储天然适合压缩，但选对编码可以进一步优化

```sql
CREATE TABLE metrics (
    ts         DateTime     CODEC(DoubleDelta, LZ4),  -- 时间戳: 递增序列
    host_id    UInt32       CODEC(T64, LZ4),           -- ID: 有界整数
    cpu        Float32      CODEC(Gorilla, LZ4),       -- 浮点: 相邻值接近
    memory_pct Float32      CODEC(Gorilla, LZ4),
    disk_bytes UInt64       CODEC(Delta, ZSTD),        -- 字节数: 缓慢变化
    status     LowCardinality(String) CODEC(ZSTD(3)),  -- 字符串: 通用压缩
    message    String       CODEC(ZSTD(1))             -- 大文本: 低压缩级别换速度
)
ENGINE = MergeTree()
ORDER BY (host_id, ts);

```

 Codec 选择指南:
   LZ4 (默认):    最快的压缩/解压，压缩率中等。大多数场景的好选择
   ZSTD(level):   压缩率比 LZ4 高 30-50%，但慢 3-5x。level 1-22，推荐 1-3
   Delta:         存储相邻值的差。适合单调递增的整数 (如自增 ID、字节计数器)
   DoubleDelta:   存储差的差。适合时间戳（因为时间戳的差通常相似）
   Gorilla:       XOR 编码。专为浮点设计，当相邻值接近时压缩率极高
   T64:           块内取最小/最大值，只存必要的位数。适合范围小的整数
   FPC:           浮点专用，某些场景比 Gorilla 好

 组合使用: 先用特化编码预处理，再用通用编码压缩
   CODEC(DoubleDelta, LZ4)  — 时间戳的最佳组合
   CODEC(Gorilla, LZ4)      — 浮点的最佳组合
   CODEC(Delta, ZSTD(1))    — 缓慢变化整数的最佳组合

 如何验证: SELECT column, formatReadableSize(data_compressed_bytes) AS compressed,
           formatReadableSize(data_uncompressed_bytes) AS uncompressed
           FROM system.columns WHERE table = 'metrics';

## 物化列和 Projection

物化列: 由其他列计算得出，存储在磁盘上（不像 DEFAULT 那样每次计算）

```sql
CREATE TABLE events_enriched (
    ts          DateTime,
    user_id     UInt64,
    event_type  LowCardinality(String),
    url         String,
    -- 物化列: INSERT 时自动计算并存储
    event_date  Date         MATERIALIZED toDate(ts),
    url_domain  String       MATERIALIZED domain(url),
    hour        UInt8        MATERIALIZED toHour(ts)
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(ts)
ORDER BY (event_type, user_id, ts);
```

注意: 物化列不能在 INSERT 中指定值，SELECT * 不包含它们
需要显式 SELECT event_date, url_domain FROM events_enriched

Projection (21.6+): 同一份数据的不同物理排列，类似物化视图但内嵌在表中

```sql
ALTER TABLE events_enriched ADD PROJECTION proj_by_user (
    SELECT * ORDER BY (user_id, ts)          -- 按 user_id 排序的副本
);
ALTER TABLE events_enriched MATERIALIZE PROJECTION proj_by_user;
```

 现在 WHERE user_id = 12345 的查询会自动使用 projection，不需要改 SQL
 代价: 存储空间翻倍，INSERT 速度下降 (需要维护多份排列)

## ReplacingMergeTree: 去重引擎

```sql
CREATE TABLE user_profiles (
    user_id    UInt64,
    username   String,
    email      String,
    updated_at DateTime
)
ENGINE = ReplacingMergeTree(updated_at)      -- 按 updated_at 保留最新行
ORDER BY user_id;                            -- 按 ORDER BY 键判断"同一行"

```

 关键理解:
1. 去重是"最终一致"的: 后台合并时才去重，查询时可能看到重复

2. FINAL 关键字: SELECT * FROM user_profiles FINAL 强制去重

      代价: 单线程执行 + 额外 CPU，大表上可能慢 2-10x
      23.2+: do_not_merge_across_partitions_select_final=1 优化了跨分区 FINAL
3. 只在同一分区内去重! 不同分区的相同 ORDER BY 键不会合并

4. 替代方案: 查询时用 GROUP BY + argMax 手动去重，可以利用多线程

      SELECT user_id, argMax(username, updated_at), argMax(email, updated_at)
      FROM user_profiles GROUP BY user_id

## ReplicatedMergeTree: 高可用

生产环境必用。通过 ZooKeeper/ClickHouse Keeper 协调副本

```sql
CREATE TABLE events_replicated (
    event_date Date,
    user_id    UInt64,
    event_type String,
    payload    String
)
ENGINE = ReplicatedMergeTree(
    '/clickhouse/tables/{shard}/events',     -- ZooKeeper 路径
    '{replica}'                              -- 副本标识
)
PARTITION BY toYYYYMM(event_date)
ORDER BY (user_id, event_date);

```

 宏变量 {shard} 和 {replica} 在 config.xml 中定义
 每个 MergeTree 引擎都有 Replicated 版本:
   ReplicatedMergeTree
   ReplicatedReplacingMergeTree
   ReplicatedSummingMergeTree
   ReplicatedAggregatingMergeTree
   ReplicatedCollapsingMergeTree
   ReplicatedVersionedCollapsingMergeTree

 22.3+: 可以用 default_replica_path/default_replica_name 宏简化
 直接写 ENGINE = MergeTree() 即可，自动变成 ReplicatedMergeTree

## 分布式表

分布式表不存储数据，只是查询路由层

```sql
CREATE TABLE events_dist AS events_replicated
ENGINE = Distributed(
    'my_cluster',                            -- 集群名 (config.xml 定义)
    'default',                               -- 数据库名
    'events_replicated',                     -- 本地表名
    rand()                                   -- 分片键 (决定数据写入哪个 shard)
);
```

 分片键选择:
   rand()     — 均匀分布，但同一用户的数据分散在各 shard (JOIN 需要全量 shuffle)
   user_id    — 同一用户数据在同一 shard (JOIN 快，但可能数据倾斜)
   sipHash64(user_id) — 哈希分布，兼顾均匀和 co-location

## 其他常用建表模式


SummingMergeTree: 合并时自动求和

```sql
CREATE TABLE daily_stats (
    date       Date,
    user_id    UInt64,
    clicks     UInt64,                       -- 合并时自动 sum
    revenue    Decimal(10,2)                 -- 合并时自动 sum
)
ENGINE = SummingMergeTree()                  -- 默认对所有非 ORDER BY 数字列求和
PARTITION BY toYYYYMM(date)
ORDER BY (date, user_id);

```

AggregatingMergeTree: 预聚合 (物化视图的后端)

```sql
CREATE TABLE stats_agg (
    date        Date,
    user_id     UInt64,
    click_count AggregateFunction(sum, UInt64),
    uniq_pages  AggregateFunction(uniq, String)
)
ENGINE = AggregatingMergeTree()
PARTITION BY toYYYYMM(date)
ORDER BY (date, user_id);
```

配合物化视图使用:

```sql
CREATE MATERIALIZED VIEW stats_mv TO stats_agg AS
SELECT toDate(ts) AS date, user_id,
       sumState(clicks) AS click_count,      -- 注意: sumState 不是 sum
       uniqState(page_url) AS uniq_pages
FROM events_enriched GROUP BY date, user_id;

```

CollapsingMergeTree: 行级更新 (用正/负行抵消)

```sql
CREATE TABLE user_balances (
    user_id  UInt64,
    balance  Decimal(10,2),
    sign     Int8                             -- +1: 有效行, -1: 取消行
)
ENGINE = CollapsingMergeTree(sign)
ORDER BY user_id;
```

 更新余额: INSERT 两行，一行 sign=-1 (抵消旧值)，一行 sign=+1 (新值)
 查询时: SELECT user_id, sum(balance * sign) / sum(sign) FROM user_balances GROUP BY user_id

## 数据类型速查

 整数: UInt8/16/32/64/128/256, Int8/16/32/64/128/256
 浮点: Float32/64 (有精度问题，金额用 Decimal)
 定点: Decimal(P,S) / Decimal32/64/128/256
 字符串: String (变长无限), FixedString(N) (定长，自动补 \0)
 日期: Date (天), Date32 (更大范围), DateTime (秒), DateTime64(precision) (亚秒)
 UUID: UUID (128 位)
 布尔: Bool (UInt8 的别名，22.12+)
 复合: Array(T), Tuple(T1,T2,...), Map(K,V), Nested(...)
 可空: Nullable(T) — 有性能代价，避免过度使用
 低基数: LowCardinality(T) — 字典编码，低基数列的性能神器
         适用: 状态码、国家、设备类型等 (基数 < 10000)
         不适用: UUID、邮箱等 (基数太高，字典反而是开销)
 IP: IPv4, IPv6 (紧凑存储 + 专用函数)
 枚举: Enum8('a'=1, 'b'=2), Enum16 — 类型安全但修改需 ALTER
 JSON: Object('json') (实验性) — 生产环境建议拆成具体列

## 版本演进关键特性

20.1:  物化视图支持 TO 语法
21.1:  Map 类型
21.6:  Projection
21.8:  物化视图可以查看自身
22.3:  轻量级 DELETE (实验性)
22.8:  SharedMergeTree (ClickHouse Cloud)
22.12: Bool 类型
23.1:  轻量级 DELETE 正式版
23.2:  FINAL 性能优化
23.3:  并行副本
23.8:  Refreshable Materialized View
24.1:  Variant/Dynamic 类型 (实验性)

