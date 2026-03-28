# Hive: 表分区策略 (Hive 最核心的优化机制)

> 参考资料:
> - [1] Apache Hive Documentation - Partitioned Tables
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL#LanguageManualDDL-PartitionedTables
> - [2] Apache Hive Documentation - Dynamic Partitions
>   https://cwiki.apache.org/confluence/display/Hive/DynamicPartitions


## 1. 分区 = HDFS 目录 (Hive 分区模型的核心)

```sql
CREATE TABLE orders (
    id         BIGINT,
    user_id    BIGINT,
    amount     DECIMAL(10,2),
    order_time TIMESTAMP
)
PARTITIONED BY (dt STRING)
STORED AS ORC;

```

 分区列 dt 不存储在数据文件中，而是编码在目录路径里:
 /warehouse/orders/dt=2024-01-01/000000_0.orc
 /warehouse/orders/dt=2024-01-02/000000_0.orc
 /warehouse/orders/dt=2024-01-03/000000_0.orc

 WHERE dt = '2024-01-01' → 只读 /warehouse/orders/dt=2024-01-01/
 这就是分区裁剪(partition pruning): 在文件系统层面跳过不相关的数据

 为什么用 STRING 而不是 DATE 作为分区列?
 实践原因: 分区值直接成为目录名，STRING 格式更灵活（dt=20240101 vs dt=2024-01-01）
 历史原因: 早期 Hive 的 DATE 类型功能不完善

## 2. 多级分区

```sql
CREATE TABLE logs (
    id      BIGINT,
    level   STRING,
    message STRING
)
PARTITIONED BY (year INT, month INT, day INT)
STORED AS ORC;

```

目录结构:
/warehouse/logs/year=2024/month=1/day=15/000000_0.orc
/warehouse/logs/year=2024/month=1/day=16/000000_0.orc


```sql
ALTER TABLE logs ADD PARTITION (year=2024, month=6, day=15);

```

 多级分区的设计 trade-off:
 优点: 更精细的分区裁剪（WHERE year=2024 AND month=1 只读 1 月的数据）
 缺点: 分区数量指数级增长 → 小文件问题（每个分区至少 1 个文件）
 建议: 最多 2-3 级分区; 超过 3 级通常得不偿失

## 3. 静态分区插入

明确指定分区值

```sql
INSERT INTO orders PARTITION (dt='2024-01-15')
SELECT id, user_id, amount, order_time FROM staging_orders;

INSERT OVERWRITE TABLE orders PARTITION (dt='2024-01-15')
SELECT id, user_id, amount, order_time FROM staging_orders;

```

## 4. 动态分区插入

```sql
SET hive.exec.dynamic.partition = true;
SET hive.exec.dynamic.partition.mode = nonstrict;  -- 允许全动态分区

```

动态分区: 根据 SELECT 最后一列的值自动创建分区

```sql
INSERT OVERWRITE TABLE orders PARTITION (dt)
SELECT id, user_id, amount, order_time, dt FROM staging_orders;
```

注意: 分区列必须是 SELECT 的最后一列

混合分区（静态 + 动态）
INSERT OVERWRITE TABLE events PARTITION (year=2024, month)
SELECT id, name, month_col FROM staging;

动态分区安全限制:

```sql
SET hive.exec.max.dynamic.partitions = 1000;        -- 总分区数上限
SET hive.exec.max.dynamic.partitions.pernode = 100;  -- 每节点上限

```

 设计分析: 为什么需要 nonstrict 模式?
 strict 模式要求至少一个静态分区，防止用户意外创建过多分区。
 nonstrict 允许全动态分区，但风险是数据中的分区值不可控时可能创建海量分区。

## 5. 分区管理

查看分区

```sql
SHOW PARTITIONS orders;
SHOW PARTITIONS orders PARTITION (dt > '2024-01-01');

```

添加分区（可以指定 HDFS 位置）

```sql
ALTER TABLE orders ADD PARTITION (dt='2024-01-15')
    LOCATION '/data/orders/2024-01-15';

ALTER TABLE orders ADD IF NOT EXISTS
    PARTITION (dt='2024-02-01')
    PARTITION (dt='2024-02-02');

```

删除分区（删除元数据 + 数据文件）

```sql
ALTER TABLE orders DROP PARTITION (dt='2023-01-01');
ALTER TABLE orders DROP IF EXISTS PARTITION (dt < '2023-01-01');

```

修改分区位置

```sql
ALTER TABLE orders PARTITION (dt='2024-01-01')
    SET LOCATION '/new/path/2024-01-01';

```

重命名分区

```sql
ALTER TABLE orders PARTITION (dt='20240115')
    RENAME TO PARTITION (dt='2024-01-15');

```

## 6. MSCK REPAIR TABLE: 元数据同步

```sql
MSCK REPAIR TABLE orders;

```

 MSCK REPAIR TABLE 扫描表目录，将文件系统上存在但 Metastore 中缺失的分区注册。
 使用场景:
1. Spark/MR 作业直接写入 HDFS（绕过 Hive）后

2. HDFS 上手动创建分区目录后

3. 从另一个集群同步数据后


 局限性:
1. 分区数量大时极慢（数万分区可能需要几十分钟）

2. 只发现新增分区，不清理已删除的分区

3. 目录名必须严格遵循 key=value 格式


## 7. 分区最佳实践与反模式

 好的分区设计:
1. 按日期分区: 最常见，自然对齐 ETL 批次

2. 每个分区包含合理的数据量: 建议 128MB-1GB 的文件大小

3. 分区键是查询 WHERE 条件中的高频过滤列


 反模式:
1. 过多分区（>10000）: Metastore 压力大，小文件问题

2. 分区键基数过高（如用户 ID）: 每个用户一个目录，文件极小

3. 分区键不在查询条件中: 分区裁剪无法生效，白白增加文件数


## 8. 跨引擎对比: 分区设计

 引擎           分区模型                分区键位置    裁剪机制
 Hive           目录分区               目录路径      目录级别跳过
 Spark SQL      继承 Hive 目录模型     目录路径      同 Hive
 MySQL          RANGE/LIST/HASH        数据中        内部分区管理
 PostgreSQL     声明式分区(10+)        数据中        约束排除
 BigQuery       按列自动分区           数据中        列统计
 ClickHouse     PARTITION BY 表达式    数据中        part 级别跳过
 Iceberg        Hidden Partitioning    manifest文件  manifest 过滤
 Delta Lake     目录分区(类 Hive)      目录路径      文件级别统计

 Iceberg 的 Hidden Partitioning 是对 Hive 模型的改进:
 Hive: PARTITIONED BY (dt STRING) → 用户必须用 dt='2024-01-01' 查询
 Iceberg: partition by days(event_time) → 用户用 event_time > '2024-01-01' 查询
 Iceberg 自动将时间戳映射到分区，用户不需要知道分区列的存在

## 9. 对引擎开发者的启示

1. 分区 = 目录的映射简单但有效: 这个设计被整个大数据生态采纳

    透明性（用户可以直接 ls HDFS 目录查看分区）是巨大的调试优势
2. 小文件问题是目录分区模型的固有缺陷: 每个分区至少一个文件，

    分区过多 → 小文件过多 → NameNode 压力大 → 读取性能差
3. Metastore 与文件系统的一致性是持久的运维痛点:

    MSCK REPAIR TABLE 是一个补丁而非解决方案;
    Iceberg/Delta 通过事务日志/manifest 文件从根本上解决了这个问题
4. Hidden Partitioning 是更好的用户体验:

不要求用户理解分区的物理结构，是 Iceberg 对 Hive 模型的核心改进

