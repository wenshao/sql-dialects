# Hive: 事务 (ACID, Hive 0.14+, 3.0+ 默认)

> 参考资料:
> - [1] Apache Hive - Hive Transactions
>   https://cwiki.apache.org/confluence/display/Hive/Hive+Transactions
> - [2] Apache Hive Language Manual - DML
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DML


## 1. ACID 表的演进

 Hive ACID 是大数据引擎支持行级操作的首次尝试。

 演进历程:
 0.14: 首次引入 ACID（实验性），要求 ORC + 分桶
 2.0:  LLAP 提升 ACID 表查询性能
 2.2:  MERGE 语句支持
 3.0:  默认所有托管表为 ACID 表，不再强制分桶

 设计动机:
 原始 Hive 只有 INSERT OVERWRITE（全分区覆盖），不支持行级修改。
 这限制了 Hive 在缓慢变化维(SCD)、数据修正等场景的使用。
 ACID 表引入了 UPDATE/DELETE/MERGE 能力，代价是读写放大。

## 2. ACID 表创建与配置

ACID 配置（hive-site.xml）:
hive.support.concurrency = true
hive.txn.manager = org.apache.hadoop.hive.ql.lockmgr.DbTxnManager
hive.compactor.initiator.on = true
hive.compactor.worker.threads = 4

创建 ACID 表

```sql
CREATE TABLE users (
    id       BIGINT,
    username STRING,
    email    STRING
)
STORED AS ORC
TBLPROPERTIES ('transactional' = 'true');

```

 Hive 3.0+ 默认所有托管(Managed)表都是 ACID 表
 不想要 ACID → 使用 EXTERNAL TABLE

## 3. 事务操作: INSERT / UPDATE / DELETE

INSERT

```sql
INSERT INTO users VALUES (1, 'alice', 'alice@example.com');
INSERT INTO users VALUES
    (2, 'bob', 'bob@example.com'),
    (3, 'carol', 'carol@example.com');

```

UPDATE（仅 ACID 表）

```sql
UPDATE users SET email = 'new@example.com' WHERE id = 1;

```

DELETE（仅 ACID 表）

```sql
DELETE FROM users WHERE id = 1;

```

## 4. MERGE (Hive 2.2+, 仅 ACID 表)

```sql
MERGE INTO users AS target
USING staging_users AS source
ON target.id = source.id
WHEN MATCHED AND source.action = 'update' THEN
    UPDATE SET username = source.username, email = source.email
WHEN MATCHED AND source.action = 'delete' THEN
    DELETE
WHEN NOT MATCHED THEN
    INSERT VALUES (source.id, source.username, source.email);

```

 MERGE 的实现: 本质上是一个 FULL OUTER JOIN + 条件路由
 匹配的行 → UPDATE/DELETE（写入 delete delta + insert delta）
 不匹配的行 → INSERT（写入 insert delta）

## 5. INSERT OVERWRITE: 非事务表的"原子操作"

```sql
INSERT OVERWRITE TABLE orders PARTITION (dt='2024-01-15')
SELECT * FROM staging_orders WHERE dt='2024-01-15';

```

 INSERT OVERWRITE 的原子性机制:
1. 将数据写入临时目录

2. 原子地将临时目录 rename 为目标分区目录

3. 删除旧的分区目录


关键特性: 幂等性
无论执行多少次 INSERT OVERWRITE，结果都是一样的。
这使得 INSERT OVERWRITE 天然适合批处理 ETL（失败重试不产生重复数据）。

动态分区 + INSERT OVERWRITE

```sql
SET hive.exec.dynamic.partition.mode = nonstrict;
INSERT OVERWRITE TABLE orders PARTITION (dt)
SELECT id, user_id, amount, dt FROM staging_orders;

```

## 6. ACID 内部实现: Base + Delta 文件

 ACID 表的存储结构:
 /warehouse/users/
   base_0000001/          ← 基础数据文件
     bucket_00000.orc
   delta_0000002_0000002/ ← INSERT delta
     bucket_00000.orc
   delta_0000003_0000003/ ← UPDATE delta
     bucket_00000.orc
   delete_delta_0000004/  ← DELETE delta
     bucket_00000.orc

 读取时: 合并 base + 所有 delta → 得到最新视图
 写入时: 只追加新的 delta 文件，不修改已有文件
 这是 Copy-on-Write 的变体（更准确地说是 Merge-on-Read）

## 7. Compaction: 性能维护

Delta 文件越多 → 读取时需要合并的文件越多 → 性能越差
Compaction 是合并文件以恢复读取性能的过程


```sql
ALTER TABLE users COMPACT 'minor';  -- 合并 delta 文件
ALTER TABLE users COMPACT 'major';  -- 重写 base + 所有 delta
ALTER TABLE users PARTITION (dt='2024-01-01') COMPACT 'major';

SHOW COMPACTIONS;

```

## 8. 隔离级别: Snapshot Isolation

 Hive ACID 使用快照隔离:
 读取不阻塞写入，写入不阻塞读取
 每个查询看到事务开始时的一致性快照
 不支持修改隔离级别（只有 Snapshot Isolation）

 关键限制: 不支持 BEGIN/COMMIT/ROLLBACK
 每个 SQL 语句是一个独立的隐式事务
 这与 RDBMS 的显式事务控制完全不同

## 9. 跨引擎对比: 事务模型

 引擎          事务模型              隔离级别        显式事务控制
 MySQL(InnoDB) MVCC + Undo Log       RC/RR/Serial    BEGIN/COMMIT
 PostgreSQL    MVCC + Tuple Version  RC/RR/Serial    BEGIN/COMMIT
 Hive ACID     Base + Delta Files    Snapshot        不支持(隐式)
 Delta Lake    Write-Ahead Log       Serializable    不支持(隐式)
 Iceberg       Snapshot + Manifest   Snapshot        不支持(隐式)
 BigQuery      快照隔离(自动)        Snapshot        不支持
 Flink SQL     Exactly-Once(CP)      N/A             Checkpoint

 共同趋势: 大数据引擎都采用隐式事务（每条语句一个事务），
 不支持 BEGIN/COMMIT 多语句事务。
 原因: 分布式环境中跨多条语句的事务协调代价极高。

## 10. 已知限制

1. 仅 ORC 格式支持 ACID（Parquet 不支持）

2. 仅托管(Managed)表支持 ACID（外部表不支持）

3. 无显式事务控制（每条语句是一个事务）

4. ACID 表读取性能开销: 需要合并 base + delta 文件

5. Compaction 开销: Major compaction 需要重写整个表/分区

6. DDL 不在事务范围内

7. 并发写入冲突: 两个 UPDATE 修改同一行时，后者可能失败


## 11. 对引擎开发者的启示

1. Base + Delta 是大数据 ACID 的标准范式:

    Hive/Delta Lake/Iceberg/Hudi 都采用了类似的机制
2. Compaction 是 ACID 的运维代价:

    任何基于不可变文件的 ACID 实现都需要 compaction
3. INSERT OVERWRITE 比 ACID 更高效:

    对于批处理 ETL，INSERT OVERWRITE 的幂等性 > ACID 的行级操作
4. 隐式事务是分布式引擎的务实选择:

不支持 BEGIN/COMMIT 简化了实现，且覆盖了 99% 的大数据使用场景

