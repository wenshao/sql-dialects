# Hive: 序列与自增 (无原生支持)

> 参考资料:
> - [1] Apache Hive Language Manual - Built-in Functions
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF
> - [2] Apache Hive - Window Functions
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+WindowingAndAnalytics


## 1. Hive 没有 SEQUENCE / AUTO_INCREMENT

 这是有意的设计选择，不是遗漏。

 为什么 Hive 不需要自增?
1. 批处理写入: Hive 的写入单位是分区级别的（INSERT OVERWRITE 重写整个分区），

    不是逐行 INSERT。批量写入场景中，全局递增 ID 没有意义。
2. 分布式并行: 多个 Mapper/Reducer 并行写入，全局递增需要集中协调点（瓶颈）

3. 分析场景: OLAP 查询关注聚合结果，不关注单行 ID

4. HDFS 不可变: 文件一旦写入 HDFS 就不可修改，无法"分配下一个 ID"


## 2. 替代方案: ROW_NUMBER() 窗口函数

最常用方案: 查询时动态生成序号

```sql
SELECT
    ROW_NUMBER() OVER (ORDER BY created_at) AS id,
    username, email
FROM users;

```

分区内序号

```sql
SELECT
    ROW_NUMBER() OVER (PARTITION BY region ORDER BY amount DESC) AS region_rank,
    region, username, amount
FROM users;

```

CTAS 生成带序号的表

```sql
CREATE TABLE users_with_id AS
SELECT
    ROW_NUMBER() OVER (ORDER BY created_at) AS id,
    username, email, created_at
FROM users;

```

 局限性:
 ROW_NUMBER() 不保证幂等: 同一查询在不同执行中可能生成不同序号
 原因: ORDER BY 列有重复值时，行的顺序不确定（non-deterministic）

## 3. 替代方案: UUID

通用方法（所有版本）

```sql
SELECT reflect('java.util.UUID', 'randomUUID') AS uuid;

```

在 CTAS 中使用

```sql
CREATE TABLE events_with_uuid AS
SELECT
    reflect('java.util.UUID', 'randomUUID') AS event_id,
    user_id, event_name, event_time
FROM raw_events;

```

Hive 3.0+ 内置 UUID() 函数

```sql
SELECT UUID() AS event_id, user_id FROM raw_events;

```

 UUID 的优缺点:
   优点: 无需协调，并行生成不冲突，全局唯一
   缺点: 128-bit 存储开销大，无序（不利于范围查询），人类不可读

## 4. 替代方案: 组合 ID

方案 A: 基于分区 + ROW_NUMBER

```sql
CREATE TABLE events_with_id AS
SELECT
    CONCAT(dt, LPAD(CAST(ROW_NUMBER() OVER (PARTITION BY dt ORDER BY event_time)
        AS STRING), 10, '0')) AS event_id,
    user_id, event_name, dt
FROM raw_events;

```

 方案 B: 自定义 UDF (Java)
 public class SequenceUDF extends UDF {
     private static AtomicLong counter = new AtomicLong(0);
     public long evaluate() { return counter.incrementAndGet(); }
 }
 ADD JAR /path/to/sequence-udf.jar;
 CREATE TEMPORARY FUNCTION next_id AS 'com.example.SequenceUDF';
 SELECT next_id() AS id, username FROM users;

 方案 C: SURROGATE_KEY()（部分发行版支持）
 SELECT SURROGATE_KEY() AS id, * FROM source_table;

## 5. 替代方案: 利用虚拟列

Hive 提供虚拟列来识别数据来源

```sql
SELECT
    INPUT__FILE__NAME   AS source_file,
    BLOCK__OFFSET__INSIDE__FILE AS file_offset,
    username
FROM users;

```

组合虚拟列可以生成伪唯一 ID（同一文件中的偏移量是唯一的）

```sql
SELECT
    CONCAT(INPUT__FILE__NAME, '_', CAST(BLOCK__OFFSET__INSIDE__FILE AS STRING)) AS row_id,
    username
FROM users;

```

## 6. 跨引擎对比: 唯一 ID 生成

 引擎           自增方案                    设计理由
 MySQL          AUTO_INCREMENT              OLTP 逐行插入，需要自增主键
 PostgreSQL     SERIAL / IDENTITY           同上
 Oracle         SEQUENCE / IDENTITY(12c+)   独立序列对象，灵活
 Hive           无（ROW_NUMBER/UUID 替代）  批量写入不需要行级自增
 Spark SQL      monotonically_increasing_id 分布式环境下每分区内递增
 BigQuery       GENERATE_UUID()             分布式系统推荐 UUID
 Snowflake      AUTOINCREMENT               兼容传统SQL，但值不保证连续
 ClickHouse     无自增                      分析引擎批量写入，不需要
 TiDB           AUTO_INCREMENT/AUTO_RANDOM  AUTO_RANDOM 避免热点写入
 MaxCompute     无自增                      类似 Hive，批处理不需要
 Flink SQL      无自增                      流处理中 ID 由上游生成

## 7. 对引擎开发者的启示

1. OLTP vs OLAP 的根本差异: OLTP 需要自增主键（逐行插入 + 索引组织表），

    OLAP 不需要（批量写入 + 全表扫描）
2. 分布式自增的代价: 全局递增需要中心协调点（如 TiDB 的 PD），

    这在 Hive 的 MapReduce 执行模型中不可行
3. UUID vs 自增的权衡: UUID 简单但 128-bit 存储开销大且无序;

    自增简单有序但分布式环境下难实现
4. Snowflake ID（Twitter）: 时间戳 + 机器 ID + 序列号的组合方案，

在分布式环境下提供有序 + 唯一 + 无协调的 ID 生成，
适合需要有序 ID 的大数据引擎

