# Hive: 索引 (3.0 正式废弃)

> 参考资料:
> - [1] Apache Hive Language Manual - Indexes
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL#LanguageManualDDL-Indexes
> - [2] HIVE-18448: Drop Support for Indexes
>   https://issues.apache.org/jira/browse/HIVE-18448
> - [3] ORC File Format - Predicate Pushdown
>   https://orc.apache.org/specification/ORCv1/


## 1. 历史: Hive 索引的兴衰

 Hive 0.7 引入了索引功能，Hive 3.0 正式废弃。
 这是大数据 SQL 领域一个重要的设计教训：
 RDBMS 的索引思路（B-tree/Hash）不适用于大规模批处理分析引擎。

 旧语法（仅供历史参考，3.0+ 不可用）:
 CREATE INDEX idx_user_age ON TABLE users (age)
     AS 'COMPACT' WITH DEFERRED REBUILD;
 ALTER INDEX idx_user_age ON users REBUILD;
 DROP INDEX idx_user_age ON users;

## 2. 为什么索引在 Hive 中失败了？

 核心矛盾: 索引的收益 < 索引的维护成本

1. HDFS 无随机读: B-tree 索引的核心优势是避免全表扫描，但 HDFS 的随机读取性能极差

    HDFS 针对顺序扫描优化（128MB 块大小），定位到索引指向的具体行然后随机读取
    反而比直接全表扫描更慢

2. 索引维护代价: Hive 表动辄 TB/PB 级，INSERT OVERWRITE 会整体重写分区

    每次重写都需要重建索引 (REBUILD)，维护成本巨大
    且索引不会自动更新（需要手动 ALTER INDEX ... REBUILD）

3. 列式格式自带 "索引": ORC/Parquet 内置了 min/max 统计信息、bloom filter、

    字典编码等，在列存引擎中这些比传统索引更有效

4. 分区裁剪已满足大部分需求: Hive 的分区模型（partition pruning）通过目录级别

    过滤数据，对于常见的按时间/地区查询已经足够高效

 对比: 为什么 RDBMS 的索引有效？
   RDBMS (MySQL/PostgreSQL): 数据量小（GB 级），随机 I/O 高效（SSD），
     点查询多，索引是维护-查询比优的
   Hive: 数据量大（TB/PB 级），随机 I/O 无效（HDFS），
     全表扫描为主，索引维护-查询比极差

## 3. 替代方案: ORC/Parquet 内置过滤


### 3.1 ORC 格式的内置过滤机制

```sql
CREATE TABLE orders (
    id       BIGINT,
    user_id  BIGINT,
    amount   DECIMAL(10,2),
    status   STRING
)
STORED AS ORC
TBLPROPERTIES (
    'orc.bloom.filter.columns' = 'user_id,status',  -- bloom filter
    'orc.bloom.filter.fpp'     = '0.05',             -- 误判率 5%
    'orc.create.index'         = 'true'              -- min/max 统计（默认开启）
);

```

 ORC 的三层过滤:
   Level 1: Stripe 级 min/max 统计 → 跳过整个 stripe（通常 64MB）
   Level 2: Row Group 级 min/max → 跳过 row group（通常 10000 行）
   Level 3: Bloom Filter → 精确判断值是否存在于 stripe 中

 这比 B-tree 索引更适合分析场景:
   - 不需要额外存储（统计信息内嵌在 ORC 文件中）
   - 不需要手动维护（写入时自动生成）
   - 面向顺序扫描优化（跳过 stripe 而不是寻址到具体行）

### 3.2 Parquet 的内置过滤

```sql
CREATE TABLE orders_parquet (
    id       BIGINT,
    user_id  BIGINT,
    amount   DECIMAL(10,2)
)
STORED AS PARQUET
TBLPROPERTIES (
    'parquet.enable.dictionary' = 'true'       -- 字典编码（低基数列有效）
);

```

## 4. 替代方案: 分区裁剪

 分区是 Hive 中最有效的"索引"：
 WHERE dt = '2024-01-15' → 只读取 /warehouse/orders/dt=2024-01-15/ 目录

 好的分区策略 = 最有效的索引
 坏的分区策略（分区过多/过少）→ 小文件问题 / 无裁剪效果

## 5. 替代方案: 分桶 + 统计信息

```sql
CREATE TABLE users_bucketed (
    id       BIGINT,
    user_id  BIGINT,
    name     STRING
)
CLUSTERED BY (user_id) SORTED BY (user_id) INTO 64 BUCKETS
STORED AS ORC;

```

CBO 统计信息（Cost-Based Optimizer）

```sql
ANALYZE TABLE users COMPUTE STATISTICS;
ANALYZE TABLE users COMPUTE STATISTICS FOR COLUMNS username, email;

```

## 6. 替代方案: 物化视图 (Hive 3.0+)

```sql
CREATE MATERIALIZED VIEW mv_daily_sales AS
SELECT dt, SUM(amount) AS total FROM orders GROUP BY dt;

```

 物化视图作为索引替代: 用"预计算结果"替代"数据定位"

## 7. 跨引擎对比: 索引设计哲学

 引擎         索引方式              设计理念
 Hive         废弃索引              列存统计 + 分区裁剪替代
 MySQL        B+tree / Hash         OLTP 点查优化
 PostgreSQL   B-tree/GIN/GiST/BRIN  多种索引类型适配不同场景
 ClickHouse   Primary Key(稀疏索引) 按排序键粗粒度跳过 granule
 BigQuery     无索引                列存统计 + 集群列(CLUSTER BY)
 Spark SQL    无索引                继承 Hive 理念，依赖文件格式
 Trino        无索引                Connector pushdown + 文件统计
 Impala       无索引                共享 Hive 的 ORC/Parquet 过滤
 MaxCompute   无传统索引            CLUSTERED BY 排序键 + 文件统计

 规律: OLTP 引擎需要索引（点查为主），OLAP/批处理引擎不需要传统索引
       OLAP 引擎用排序键(sort key) + 列统计(min/max) + 分区裁剪替代

## 8. 对引擎开发者的启示

1. 不要照搬 RDBMS 的索引到分析引擎: Hive 的索引失败证明了此路不通

2. 文件格式内置统计信息是更好的方案: 维护成本低、无额外存储开销

3. 分区 + 排序键是分析引擎的"索引": 粗粒度跳过 > 细粒度定位

4. Bloom Filter 对高基数列的等值查询有效: 是分析引擎的最佳精确过滤手段

5. 物化视图比索引更适合分析场景: Hive 3.0+ 引入物化视图作为索引的替代

6. ClickHouse 的稀疏索引是好的中间方案: 不索引每行，而是每 8192 行建一个标记

