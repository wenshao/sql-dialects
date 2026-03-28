# Apache Doris: 锁机制与并发控制

 Apache Doris: 锁机制与并发控制

 参考资料:
   [1] Doris Documentation - Data Model / Transaction
       https://doris.apache.org/docs/data-table/data-model

## 1. 并发模型: OLAP 引擎不需要行级锁

 Doris 不支持传统的行级锁(FOR UPDATE/FOR SHARE)、表锁(LOCK TABLE)、
 咨询锁(Advisory Lock)。

 设计理由:
   OLAP 引擎的写入模式是"批量追加"而非"行级修改"。
   每个导入任务是一个原子操作，不需要事务级别的并发控制。
   读写并发通过 MVCC(多版本)实现——查询看到的是导入完成的快照。

 对比:
   StarRocks:  同样无行级锁(同源)
   ClickHouse: 同样无行级锁(分析引擎不需要)
   MySQL:      行级锁(InnoDB) + 表级锁(MyISAM)
   PostgreSQL: 行级锁 + MVCC + 咨询锁
   BigQuery:   无锁概念(每个 DML 是原子操作)

## 2. MVCC 快照读

 查询看到的是查询开始时的一致性快照，不受并发导入影响。
 导入完成(COMMIT)后，新查询才能看到新数据。

## 3. 表级元数据锁

Schema Change(ALTER TABLE)获取表级排他锁。
导入操作与 Schema Change 互斥。
多个导入操作可以并发执行。


```sql
ALTER TABLE orders ADD COLUMN new_col INT;  -- 获取表锁

```

## 4. 乐观锁 (应用层实现)

Unique Key 模型: 通过 version 列实现应用层乐观锁

```sql
CREATE TABLE orders (
    id      BIGINT,
    status  VARCHAR(50),
    amount  DECIMAL(10,2),
    version INT
) UNIQUE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 8
PROPERTIES ("enable_unique_key_merge_on_write" = "true");

```

新插入相同 Key 的行覆盖旧行

```sql
INSERT INTO orders VALUES (100, 'shipped', 99.99, 6);

```

## 5. 监控与诊断

```sql
SHOW LOAD;                              -- 运行中的导入
SHOW PROC '/current_queries';           -- 运行中的查询
CANCEL LOAD WHERE LABEL = 'load_label'; -- 取消导入
KILL query_id;                          -- 取消查询

```

## 6. 对引擎开发者的启示

OLAP 引擎的并发控制比 OLTP 简单得多:
写入: 批量导入(Label 幂等) → 无需行级锁
读取: MVCC 快照 → 无需读锁
DDL:  表级元数据锁 → 简单排他

挑战在于 Unique/Primary Key 模型的并发更新:
多个导入同时更新同一个 Key → 需要 Last Write Wins 或 Sequence 列
Doris: function_column.sequence_col 解决多源更新冲突
StarRocks: 按写入顺序覆盖(后写入的为准)

