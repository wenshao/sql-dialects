# MaxCompute (ODPS): 事务

> 参考资料:
> - [1] MaxCompute Transactional Tables
>   https://help.aliyun.com/zh/maxcompute/user-guide/transactional-tables
> - [2] MaxCompute Time Travel
>   https://help.aliyun.com/zh/maxcompute/user-guide/time-travel


## 1. 两种截然不同的事务模型


 模型 A: 普通表 —— 文件级原子性（非 ACID 事务）
 模型 B: 事务表 —— 行级 ACID 事务（2.0+）

 设计决策: 为什么有两种模型?
   Hive 族引擎的历史: 最初只有不可变文件（INSERT OVERWRITE 原子替换）
   行级事务需求出现: 维度表更新、CDC 增量合并等场景
   解决方案: 在不可变文件之上叠加事务层（delta file + compaction）
   结果: 两种表共存，行为差异大

## 2. 普通表的原子性保证


INSERT OVERWRITE 是原子的: 成功则全部替换，失败则保留原数据

```sql
INSERT OVERWRITE TABLE orders PARTITION (dt = '20240115')
SELECT * FROM staging_orders WHERE dt = '20240115';

```

 底层实现:
1. 写入新的 AliORC 文件到临时目录

2. 所有文件写完后，原子性地替换旧目录（元数据操作）

3. 如果任何步骤失败: 临时目录被清理，旧数据不受影响

这不是传统 ACID 事务，而是文件系统级别的原子替换

INSERT INTO 追加也是原子的（要么全部写入，要么全部回滚）

```sql
INSERT INTO orders PARTITION (dt = '20240115')
VALUES (1, 100, 50.00, GETDATE());

```

幂等性: INSERT OVERWRITE 天然幂等
重复执行结果相同（这是 ETL 管道最重要的属性）

```sql
INSERT OVERWRITE TABLE daily_summary PARTITION (dt = '20240115')
SELECT user_id, COUNT(*), SUM(amount)
FROM orders WHERE dt = '20240115'
GROUP BY user_id;

```

## 3. 事务表的 ACID 特性


```sql
CREATE TABLE users (
    id       BIGINT,
    username STRING,
    email    STRING,
    PRIMARY KEY (id)
) TBLPROPERTIES ('transactional' = 'true');

```

ACID 语义:
原子性（Atomicity）: 单个 SQL 语句是原子的
一致性（Consistency）: 通过 PK 保证数据一致性
隔离性（Isolation）: 快照隔离（Snapshot Isolation）
持久性（Durability）: 数据持久化到盘古分布式存储

支持的事务操作:

```sql
UPDATE users SET email = 'new@example.com' WHERE id = 1;
DELETE FROM users WHERE id = 1;

MERGE INTO users AS target
USING staging_users AS source
ON target.id = source.id
WHEN MATCHED THEN
    UPDATE SET username = source.username, email = source.email
WHEN NOT MATCHED THEN
    INSERT VALUES (source.id, source.username, source.email);

```

 底层实现: delta file + compaction
   INSERT: 写入新的 base file
   UPDATE: 写入 update delta file（标记旧行删除 + 新行数据）
   DELETE: 写入 delete delta file（标记删除行）
   读取: base file + delta files 合并（读时合并）
   compaction: 定期将 base + delta 合并为新的 base file

## 4. 并发控制


 MaxCompute 使用乐观并发控制（Optimistic Concurrency Control）

 分区级别的并发规则:
   同一分区: 同时只能有一个写入操作（串行）
   不同分区: 可以并行写入
   多个读取: 始终可以并行（快照隔离）

 并发冲突场景:
   作业 A: INSERT OVERWRITE TABLE t PARTITION (dt='20240115') ...
   作业 B: INSERT OVERWRITE TABLE t PARTITION (dt='20240115') ...
   结果: 后提交的作业会等待或失败（取决于超时设置）

 对比:
   MySQL InnoDB: 行级锁 + MVCC（悲观为主）
   PostgreSQL:   行级锁 + MVCC（悲观为主）
   BigQuery:     表级锁（DML 语句级别的乐观并发）
   Snowflake:    微分区级别的乐观并发
   Delta Lake:   Optimistic Concurrency（文件级别冲突检测）

## 5. Time Travel（事务表 2.0+）


按时间点查询历史数据（只对事务表有效）

```sql
SELECT * FROM users TIMESTAMP AS OF DATETIME '2024-01-15 10:00:00';

```

 Time Travel 的实现:
   事务表的 compaction 不会立即删除旧版本文件
   保留期内可以查询任意历史时间点的快照
   超过保留期: 旧版本文件被清理，Time Travel 失效

 对比:
   Delta Lake:  默认 30 天 Time Travel
   Iceberg:     通过 snapshot ID 访问历史版本
   BigQuery:    7 天 Time Travel（所有表，免费）
   Snowflake:   1-90 天 Time Travel（按版本收费，标准版最多 1 天）
   Oracle:      FLASHBACK QUERY（基于 undo 日志）

 Time Travel 的使用场景:
   数据恢复: 误删后查询删除前的快照
   审计: 查看某个时间点的数据状态
   调试: 对比两个时间点的数据差异

## 6. 数据质量保证模式（替代事务验证）


批处理引擎的数据质量保证是管道级别的（不是事务级别）

步骤 1: 写入临时表

```sql
INSERT OVERWRITE TABLE staging_data PARTITION (dt = '20240115')
SELECT * FROM raw_data;

```

步骤 2: 验证数据

```sql
SELECT COUNT(*) FROM staging_data WHERE dt = '20240115' AND amount < 0;
```

如果返回 > 0，则终止管道（在 DataWorks 调度中配置）

步骤 3: 写入目标表

```sql
INSERT OVERWRITE TABLE final_data PARTITION (dt = '20240115')
SELECT * FROM staging_data WHERE dt = '20240115';

```

 这是 staging → validate → publish 的经典模式
 对比 OLTP: 在 BEGIN/COMMIT 事务中做验证和写入

## 7. 横向对比: 事务能力


 事务模型:
   MaxCompute: 文件级原子性 + 事务表 ACID
   Hive:       文件级原子性 + ACID 表（0.14+）
   BigQuery:   表级 DML 事务（单语句原子）
   Snowflake:  多语句事务（BEGIN/COMMIT/ROLLBACK）
   Delta Lake: 行级 ACID（所有表默认事务）
   Iceberg:    行级 ACID（所有表默认事务）

 多语句事务:
   MaxCompute: 不支持 BEGIN/COMMIT/ROLLBACK
   Snowflake:  支持（多语句事务块）
   PostgreSQL: 支持（完整事务控制）
   BigQuery:   支持（多语句事务块）

 快照隔离:
MaxCompute: 事务表支持        | Delta Lake: 支持
Snowflake:  支持              | PostgreSQL: 支持（SERIALIZABLE 更强）

## 8. 对引擎开发者的启示


1. INSERT OVERWRITE 的原子性是批处理引擎最重要的事务保证

2. 在不可变文件上叠加事务（delta + compaction）是通用模式

3. 所有表默认支持事务比后期追加更好（Delta Lake/Iceberg 的做法）

4. compaction 策略决定读取性能: minor(合并 delta) vs major(重写 base)

5. Time Travel 的存储成本与历史可追溯性需要权衡

6. 分区级并发是大数据引擎的最佳并发粒度（行级锁在批处理中无意义）

