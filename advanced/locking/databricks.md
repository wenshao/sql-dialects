# Databricks: 锁机制 (Locking)

> 参考资料:
> - [Databricks Documentation - Isolation Levels and Write Conflicts on Databricks](https://docs.databricks.com/en/optimizations/isolation-level.html)
> - [Databricks Documentation - Delta Lake Transaction Log](https://docs.databricks.com/en/delta/history.html)
> - [Delta Lake Documentation - Concurrency Control](https://docs.delta.io/latest/concurrency-control.html)


## Databricks 并发模型概述

Databricks 基于 Delta Lake，使用乐观并发控制:
1. Delta Lake 提供 ACID 事务
2. 使用乐观并发控制处理写入冲突
3. 读操作使用快照隔离
4. 不支持 SELECT FOR UPDATE / FOR SHARE
5. Unity Catalog 提供元数据级别的访问控制

## Delta Lake 事务


所有 Delta 表操作都是 ACID 事务
```sql
INSERT INTO orders VALUES (1, 'new', 100.00);

UPDATE orders SET status = 'shipped' WHERE id = 1;

DELETE FROM orders WHERE status = 'cancelled';

MERGE INTO orders t
USING updates s ON t.id = s.id
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *;
```


## 隔离级别


WriteSerializable（默认）: 写入可序列化，允许某些并发优化
```sql
ALTER TABLE orders SET TBLPROPERTIES (
    'delta.isolationLevel' = 'WriteSerializable'
);
```


Serializable: 更严格，表读取也参与冲突检测
```sql
ALTER TABLE orders SET TBLPROPERTIES (
    'delta.isolationLevel' = 'Serializable'
);
```


## 写入冲突规则


WriteSerializable 模式下的冲突矩阵:
INSERT 与 INSERT: 不冲突（追加不同文件）
INSERT 与 DELETE/UPDATE: 不冲突（不修改相同文件）
DELETE/UPDATE 与 DELETE/UPDATE: 冲突（修改相同文件）
OPTIMIZE 与写入: 不冲突（Databricks 特有优化）

Serializable 模式下:
更严格，INSERT 可能与 DELETE/UPDATE 冲突（如果读取了相同数据）

## 行级并发（Delta Lake Row-Level Concurrency）


Databricks Runtime 14.2+ 支持行级并发
允许并发 UPDATE/DELETE/MERGE 操作修改同一表的不同行
自动启用（Deletion Vectors + Row-Level Concurrency）

```sql
ALTER TABLE orders SET TBLPROPERTIES (
    'delta.enableDeletionVectors' = true
);
```


## Time Travel


```sql
SELECT * FROM orders VERSION AS OF 5;
SELECT * FROM orders TIMESTAMP AS OF '2024-01-15 10:00:00';

DESCRIBE HISTORY orders;
```


恢复到历史版本
```sql
RESTORE TABLE orders TO VERSION AS OF 5;
```


## 乐观锁（应用层）


使用版本号列
```sql
UPDATE orders SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;
```


## 注意事项


1. 基于 Delta Lake 的乐观并发控制
2. 不支持 SELECT FOR UPDATE / FOR SHARE
3. 不支持 LOCK TABLE / advisory locks
4. 写入冲突需要应用层重试
5. Row-Level Concurrency (14.2+) 减少写入冲突
6. OPTIMIZE 和 Z-ORDER 操作不与写入冲突
