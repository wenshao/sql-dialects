# Spark SQL: 事务 (Transactions)

> 参考资料:
> - [1] Delta Lake - ACID Transactions
>   https://docs.delta.io/latest/concurrency-control.html
> - [2] Apache Iceberg - Reliability
>   https://iceberg.apache.org/docs/latest/reliability/
> - [3] Spark SQL Reference
>   https://spark.apache.org/docs/latest/sql-ref.html


## 1. 核心设计: 原生 Spark SQL 没有事务


 标准 Spark SQL（Parquet/ORC/CSV 表）不支持 ACID 事务:
   无 BEGIN / COMMIT / ROLLBACK
   每个 SQL 语句是独立操作，失败可能留下部分写入的文件
   没有隔离级别——并发写入可能导致数据损坏

 这是批处理引擎的通病: 数据以文件形式存储，文件系统不提供事务语义。
 Delta Lake 和 Iceberg 通过"事务日志"在文件系统之上构建了 ACID 事务层。

 对比:
   MySQL InnoDB:   完整 ACID（redo log + undo log + MVCC）
   PostgreSQL:     完整 ACID（WAL + MVCC，DDL 也是事务性的！）
   Oracle:         完整 ACID（redo log + undo tablespace + read consistency）
   Hive:           Hive 3.0+ ACID（基于 Delta 文件，性能差，限制多）
   Flink SQL:      两阶段提交（sink 端 exactly-once）
   ClickHouse:     无 ACID（最终一致性，MergeTree 合并保证数据一致）
   BigQuery:       DML 语句级事务 + 多语句事务（preview）
   Snowflake:      完整 ACID（每个 DML 是隐式事务）

## 2. Delta Lake: 每个 DML 都是原子事务


Delta Lake 的每个 INSERT/UPDATE/DELETE/MERGE 自动构成一个原子事务

```sql
INSERT INTO delta_users VALUES (1, 'alice', 'alice@example.com');
```

这是一个完整的 ACID 事务: 要么完全成功，要么完全回滚


```sql
UPDATE delta_users SET email = 'new@example.com' WHERE username = 'alice';
DELETE FROM delta_users WHERE status = 'deleted';

```

MERGE: 复杂操作也是单个原子事务

```sql
MERGE INTO users AS t
USING updates AS s
ON t.id = s.id
WHEN MATCHED AND s.delete_flag THEN DELETE
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *;

```

 Delta Lake 事务的实现机制:
1. 每次写入创建新的 Parquet 数据文件（不修改已有文件）

2. 在 _delta_log/ 目录下写入一个 JSON 提交文件（原子操作）

3. 提交文件记录: 添加了哪些文件、删除了哪些文件、Schema 变更等

4. 读取时根据事务日志确定哪些文件构成表的"当前版本"


 这类似于数据库的 WAL（Write-Ahead Log），但操作粒度是文件而非行。

## 3. Time Travel: 访问历史版本


按版本号访问

```sql
SELECT * FROM users VERSION AS OF 5;

```

按时间戳访问

```sql
SELECT * FROM users TIMESTAMP AS OF '2024-01-15 10:00:00';

```

Databricks 简写语法
SELECT * FROM users@v5;

查看表的完整事务历史

```sql
DESCRIBE HISTORY users;
DESCRIBE HISTORY users LIMIT 10;

```

回退到历史版本

```sql
RESTORE TABLE users TO VERSION AS OF 5;
RESTORE TABLE users TO TIMESTAMP AS OF '2024-01-15 10:00:00';

```

 Time Travel 的设计价值:
1. 数据审计: 查看表在任意时间点的状态

2. 错误恢复: 误操作后 RESTORE 回到正确版本（类似数据库 PITR）

3. 可重现性: 机器学习训练可以引用固定版本的数据集

4. 零成本读取: 不需要锁——直接读取历史快照


 对比:
   Oracle:     Flashback Query（AS OF TIMESTAMP/SCN）——最相似的设计
   PostgreSQL: 无内建 Time Travel（需要 temporal tables 扩展）
   SQL Server: 时态表（Temporal Tables）——自动记录行级历史
   BigQuery:   Time Travel（7 天保留，与 Delta Lake 类似）
   Snowflake:  Time Travel（1-90 天保留，按版本收费）

## 4. VACUUM: 清理过期数据文件


```sql
VACUUM users;                                    -- 删除超过 7 天的旧文件
VACUUM users RETAIN 168 HOURS;                   -- 显式指定保留期限

```

 VACUUM 之后，超过保留期的历史版本将不可访问（Time Travel 失效）
 这是存储成本和历史可追溯性之间的 trade-off

## 5. 隔离级别


Delta Lake 支持两种隔离级别:
WriteSerializable（默认）: 写操作串行化，读操作快照隔离

```sql
ALTER TABLE users SET TBLPROPERTIES ('delta.isolationLevel' = 'WriteSerializable');

```

Serializable: 更严格，读写都检查冲突

```sql
ALTER TABLE users SET TBLPROPERTIES ('delta.isolationLevel' = 'Serializable');

```

## 6. 多语句事务（Databricks，Preview）


 Databricks 正在开发多语句事务支持:
 BEGIN TRANSACTION;
 UPDATE accounts SET balance = balance - 100 WHERE id = 1;
 UPDATE accounts SET balance = balance + 100 WHERE id = 2;
 COMMIT;

 这将使 Spark SQL 具备传统数据库的事务能力，但实现复杂度极高:
 需要在分布式环境中协调多个表的读写集（read set / write set）

## 7. Iceberg 的事务模型


 Iceberg 也提供 ACID 事务，实现机制与 Delta Lake 不同:
   Delta Lake: 事务日志是 JSON 文件序列，通过文件系统原子重命名保证一致性
   Iceberg:    元数据通过 Catalog 的 CAS（Compare-And-Swap）操作保证一致性

 Iceberg 的 Snapshot 隔离:
 SELECT * FROM catalog.db.users.snapshots;
 SELECT * FROM catalog.db.users.history;
 CALL catalog.system.rollback_to_snapshot('db.users', 123456);

## 8. Savepoint 模拟（Delta Lake）


1. 记录当前版本号

 DESCRIBE HISTORY users LIMIT 1;  -> version = 10
2. 执行一系列操作

 UPDATE users SET ...;  -- version = 11
 DELETE FROM users ...;  -- version = 12
3. 如果需要回退: RESTORE TABLE users TO VERSION AS OF 10;


## 9. 版本演进

- **Spark 2.0**: 无事务支持
- **Delta 0.1**: 单表 ACID 事务（乐观并发控制）
- **Delta 1.0**: Time Travel, RESTORE, 隔离级别
- **Delta 2.0**: Deletion Vectors（行级删除优化）
- **Iceberg 1.0**: 快照隔离, WAP 模式
- **Databricks**: 多语句事务（Preview）

> **限制**: 
原生 Spark SQL（Parquet/ORC）无任何事务保证
Delta Lake / Iceberg 仅提供单表原子事务（无跨表事务）
多语句事务仅 Databricks Preview
并发写入冲突需要应用层重试
VACUUM 后历史版本不可恢复
