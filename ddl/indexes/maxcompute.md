# MaxCompute (ODPS): 索引

> 参考资料:
> - [1] MaxCompute SQL Overview
>   https://help.aliyun.com/zh/maxcompute/user-guide/sql-overview
> - [2] MaxCompute 存储架构
>   https://help.aliyun.com/zh/maxcompute/product-overview/storage-architecture


## 1. MaxCompute 不支持传统索引 —— 这是设计决策而非缺陷


 为什么批处理引擎不需要 B-tree/Hash 索引?
   OLTP 索引的核心价值: 将 O(N) 全表扫描降为 O(log N) 或 O(1) 点查
   MaxCompute 的场景: 查询通常扫描 GB~TB 级数据，不做单行点查
   全表扫描在列式存储中并不昂贵:
     AliORC 列式格式 + 列裁剪: 只读需要的列（10 列表只读 2 列 = 80% I/O 节省）
     谓词下推到 Stripe 级别: 利用 min/max 统计信息跳过整个 Stripe
     向量化读取: 批量处理数据，CPU 效率远高于逐行处理
   维护索引的代价在大数据场景中不可接受:
     每次 INSERT OVERWRITE 需要重建整个分区的索引
     索引本身需要存储空间（对 TB 级表，索引可能也是 TB 级）
     分布式环境下维护全局索引的一致性极其复杂

## 2. 分区裁剪 —— MaxCompute 的"一级索引"


分区是目录级别的数据隔离，裁剪在文件系统层面完成

```sql
CREATE TABLE orders (
    id       BIGINT,
    user_id  BIGINT,
    amount   DECIMAL(10,2)
)
PARTITIONED BY (dt STRING);

```

分区裁剪: 只读 /orders/dt=20240115/ 目录下的文件

```sql
SELECT * FROM orders WHERE dt = '20240115';

```

多级分区: 进一步缩小扫描范围

```sql
CREATE TABLE logs (
    id      BIGINT,
    message STRING,
    level   STRING
)
PARTITIONED BY (dt STRING, region STRING, hour STRING);

```

裁剪到 /logs/dt=20240115/region=cn/hour=10/ 目录

```sql
SELECT * FROM logs WHERE dt = '20240115' AND region = 'cn' AND hour = '10';

```

查看分区信息

```sql
SHOW PARTITIONS orders;

```

 设计分析: 分区裁剪 vs B-tree 索引
   分区裁剪: O(1) 目录定位，粒度粗（天/小时/地区）
   B-tree 索引: O(log N) 精确定位，粒度细（单行）
   分区裁剪在大数据场景中更实用:
     ETL 查询几乎都带日期条件（WHERE dt = '...'）
     一个分区通常包含百万~亿行，内部再用列式存储优化
     分区数量通常在千~万级，元数据管理开销可控

## 3. 聚集（Clustering）—— MaxCompute 的"二级索引"


Hash Clustering: 按 user_id 哈希分桶

```sql
CREATE TABLE orders_hash (
    id       BIGINT,
    user_id  BIGINT,
    amount   DECIMAL(10,2)
)
PARTITIONED BY (dt STRING)
CLUSTERED BY (user_id) SORTED BY (id) INTO 1024 BUCKETS;

```

Range Clustering: 按 user_id 范围分桶

```sql
CREATE TABLE orders_range (
    id       BIGINT,
    user_id  BIGINT,
    amount   DECIMAL(10,2)
)
PARTITIONED BY (dt STRING)
RANGE CLUSTERED BY (user_id) SORTED BY (id) INTO 1024 BUCKETS;

```

 Clustering 的优化效果:
   Hash Clustering:
     等值 JOIN 优化: 两表按相同 key 分桶，可做 Bucket Map JOIN（无 shuffle）
     等值过滤: WHERE user_id = 123 只读取对应的桶
   Range Clustering:
     范围查询: WHERE user_id BETWEEN 100 AND 200 只读取对应范围的桶
     桶内有序: 支持 Sort-Merge JOIN，避免排序开销

   对比:
     Hive:        CLUSTERED BY ... SORTED BY ... INTO N BUCKETS（语法相同）
     Spark 3.0:   CLUSTER BY（V2 数据源）
     BigQuery:    CLUSTER BY（自动管理桶数量，无需指定 INTO N BUCKETS）
     ClickHouse:  ORDER BY（定义表的排序键，类似 Range Clustering）

## 4. AliORC 内置优化 —— 存储层的"隐式索引"


 AliORC 文件内部包含多层统计信息，起到类似索引的作用:
   File Footer: 整个文件的 min/max/count/sum 统计
   Stripe Footer: 每个 Stripe（~256MB）的列级统计
   Row Index: 每 10000 行的 min/max 统计

 谓词下推流程:
   WHERE amount > 1000
1. 检查 File Footer: 如果 max(amount) < 1000，跳过整个文件

2. 检查 Stripe Footer: 跳过 max(amount) < 1000 的 Stripe

3. 检查 Row Index: 跳过 max(amount) < 1000 的行组

4. 向量化读取: 批量解码 + SIMD 过滤


对比:
Parquet: 类似的 Row Group 级别统计 + 页级别统计
ORC:     AliORC 的基础，统计信息相同，但 AliORC 优化了编码和 I/O
BigQuery Capacitor: 自研格式，更激进的编码优化

小文件合并: 优化读取性能

```sql
ALTER TABLE orders PARTITION (dt = '20240115') MERGE SMALLFILES;

```

## 5. 物化视图 —— 预计算"索引"


```sql
CREATE MATERIALIZED VIEW mv_daily_sales
LIFECYCLE 30
AS
SELECT dt, SUM(amount) AS total, COUNT(*) AS cnt
FROM orders
GROUP BY dt;

```

 物化视图自动查询改写: 优化器将匹配的查询重写为读取物化视图
 对比:
   Oracle:     物化视图 + 查询改写（最成熟的实现）
   BigQuery:   物化视图 + 自动改写
   ClickHouse: 物化视图（INSERT 触发更新，非查询改写）

## 6. 横向对比: 索引 vs 无索引引擎


 有传统索引的引擎:
   MySQL/PostgreSQL: B-tree/Hash/GiST/GIN（OLTP 必需）
   SQL Server:       B-tree + 列存索引（混合负载）
   Oracle:           B-tree/Bitmap/函数索引（最丰富）

 无传统索引的引擎:
   MaxCompute:  分区裁剪 + Clustering + AliORC 统计
   BigQuery:    分区 + Clustering + 搜索索引（2021+，有限场景）
   Snowflake:   微分区 + 自动 Clustering + 搜索优化（Enterprise+）
   ClickHouse:  主键排序 + 跳数索引（minmax/set/bloom_filter）
   Hive:        分区 + Bucketing + ORC 统计
   Spark:       分区 + Bucketing + Data Skipping

 ClickHouse 的跳数索引是介于传统索引和无索引之间的设计:
   不维护精确的行定位信息，只维护数据块的摘要信息
   可以跳过不包含目标数据的数据块
   维护成本远低于 B-tree，但过滤效果也弱于 B-tree

## 7. 对引擎开发者的启示


1. OLAP 引擎不需要传统索引 —— 分区裁剪 + 列式统计信息是更好的选择

2. 分区是最有效的"索引": 设计时应让分区裁剪尽可能高效

3. Clustering 是第二层优化: 数据物理排列直接影响 JOIN 和范围查询性能

4. 列式存储的内置统计信息（min/max）提供了免维护的过滤能力

5. 物化视图是预计算的"索引": 适合固定查询模式的加速

6. BigQuery/Snowflake 的搜索索引表明 OLAP 引擎开始补充有限的精确索引

