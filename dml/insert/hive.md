# Hive: INSERT (Hive 的核心写入操作)

> 参考资料:
> - [1] Apache Hive Language Manual - DML
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DML
> - [2] Apache Hive - Dynamic Partitions
>   https://cwiki.apache.org/confluence/display/Hive/DynamicPartitions


## 1. INSERT OVERWRITE: Hive 最核心的写入模式

INSERT OVERWRITE 是 Hive 的标志性操作——覆盖写入整个表或分区。
这不是 SQL 标准操作，是 Hive 为 HDFS 不可变文件系统设计的。

```sql
INSERT OVERWRITE TABLE users_archive
SELECT username, email, age FROM users WHERE age > 60;

```

覆盖特定分区

```sql
INSERT OVERWRITE TABLE events PARTITION (dt='2024-01-15')
SELECT user_id, event_name, event_time FROM staging_events;

```

 设计分析: 为什么 INSERT OVERWRITE 是 Hive 的核心?
1. 幂等性: 无论执行多少次，结果相同。ETL 管道失败重试不会产生重复数据。

2. HDFS 适配: HDFS 不支持文件修改，只能整体替换（rename 是原子操作）

3. 原子性: 写入临时目录 → 原子 rename → 删除旧目录。读者始终看到完整数据。

4. 简单高效: 不需要事务管理器、锁、delta 文件合并等复杂机制


 对比:
   RDBMS:    INSERT INTO 是逐行/批量追加，不覆盖
   BigQuery: 有 WRITE_TRUNCATE 选项，类似 INSERT OVERWRITE
   Spark:    继承了 INSERT OVERWRITE 语义
   Flink:    流处理中无 INSERT OVERWRITE（用 changelog 替代）

## 2. INSERT INTO: 追加写入

```sql
INSERT INTO TABLE users
SELECT 'alice', 'alice@example.com', 25;

```

VALUES 子句（0.14+ ACID 表，3.0+ 所有托管表）

```sql
INSERT INTO TABLE users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30);

```

 注意: INSERT INTO VALUES 在 Hive 中的代价很高
 每条 INSERT INTO VALUES 都会启动一个 MapReduce/Tez 作业
 对比 MySQL: INSERT INTO VALUES 是微秒级操作
 这就是为什么 Hive 更适合批量写入（INSERT ... SELECT）而非逐行插入

## 3. 静态分区插入

```sql
INSERT INTO TABLE events PARTITION (dt='2024-01-15')
SELECT user_id, event_name, event_time FROM staging_events;

```

 静态分区: 分区值在 SQL 中硬编码
 适用场景: 已知目标分区（如每日 ETL 处理固定日期的数据）

## 4. 动态分区插入

```sql
SET hive.exec.dynamic.partition = true;
SET hive.exec.dynamic.partition.mode = nonstrict;

INSERT OVERWRITE TABLE events PARTITION (dt)
SELECT user_id, event_name, event_time, dt FROM staging_events;
```

注意: 分区列必须是 SELECT 结果的最后一列

混合分区（静态 + 动态）

```sql
INSERT OVERWRITE TABLE events PARTITION (year='2024', month)
SELECT user_id, event_name, month_col FROM staging_events;
```

year 是静态指定的，month 根据数据动态确定

动态分区安全限制:

```sql
SET hive.exec.max.dynamic.partitions = 1000;
SET hive.exec.max.dynamic.partitions.pernode = 100;
SET hive.exec.max.created.files = 100000;

```

 设计分析: strict vs nonstrict 模式
 strict (默认): 至少需要一个静态分区列，防止用户意外创建海量分区
 nonstrict: 允许全动态分区（所有分区列都从数据推导）
 strict 模式是安全防护: 想象一个 10 亿行数据的 INSERT，如果每行有不同的分区值...

## 5. 多路输出 (Multi-Insert): Hive 独有特性

```sql
FROM staging_events
INSERT OVERWRITE TABLE events_web PARTITION (dt='2024-01-15')
    SELECT user_id, event_name WHERE source = 'web'
INSERT OVERWRITE TABLE events_app PARTITION (dt='2024-01-15')
    SELECT user_id, event_name WHERE source = 'app';

```

 设计价值: 一次扫描源表，同时写入多个目标表/分区
 减少了 I/O（源表只扫描一次而非 N 次）
 这在 MapReduce 模型中特别有价值（避免多次启动 MR 作业）

## 6. LOAD DATA: 直接加载文件

从本地文件系统加载（复制到 HDFS）

```sql
LOAD DATA LOCAL INPATH '/tmp/users.txt' INTO TABLE users;

```

从 HDFS 加载（移动文件，不是复制！）

```sql
LOAD DATA INPATH '/data/users.txt' INTO TABLE users;

```

OVERWRITE 模式

```sql
LOAD DATA INPATH '/data/users.txt' OVERWRITE INTO TABLE users;

```

 LOAD DATA 的本质: 不是 INSERT，而是文件移动
 不触发 MapReduce 作业，不做数据转换，只是将文件放到表目录下
 因此文件格式必须与表定义的 SerDe 兼容

## 7. CTE + INSERT

```sql
WITH new_users AS (
    SELECT 'alice' AS username, 'alice@example.com' AS email
)
INSERT INTO TABLE users (username, email)
SELECT username, email FROM new_users;

```

CTAS: 建表并写入

```sql
CREATE TABLE users_backup AS SELECT * FROM users WHERE age > 18;

```

## 8. 跨引擎对比: 写入模型

 引擎          核心写入模式            幂等写入         多路输出
 Hive          INSERT OVERWRITE        天然幂等         FROM ... INSERT x N
 MySQL         INSERT INTO             非幂等           不支持
 PostgreSQL    INSERT INTO             非幂等           不支持
 Spark SQL     INSERT OVERWRITE        天然幂等         继承 Hive
 BigQuery      INSERT/WRITE_TRUNCATE   WRITE_TRUNCATE   不支持
 ClickHouse    INSERT INTO             非幂等           不支持
 Flink SQL     INSERT INTO (流式)      Exactly-Once     支持(多汇)
 MaxCompute    INSERT OVERWRITE        天然幂等         支持(类 Hive)

## 9. 对引擎开发者的启示

1. INSERT OVERWRITE 是批处理引擎的最佳写入模式:

    幂等性 + 原子性 + 简单性，适合 ETL 管道
2. 多路输出是源表扫描优化的关键:

    大数据引擎应该支持一次扫描多次写入（减少 I/O）
3. LOAD DATA 是零转换文件移动:

    这个设计绕过了查询引擎，直接操作存储层——快但不安全
4. 逐行 INSERT 在大数据引擎中是反模式:

Hive 每条 INSERT VALUES 启动一个作业，说明引擎不是为逐行操作设计的

