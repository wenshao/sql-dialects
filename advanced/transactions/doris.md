# Apache Doris: 事务

 Apache Doris: 事务

 参考资料:
   [1] Doris Documentation - Transaction
       https://doris.apache.org/docs/data-operate/transaction

## 1. 事务模型: Import 事务而非 OLTP 事务

 Doris 的事务语义与传统 RDBMS 完全不同:
   传统 RDBMS: BEGIN → 多条 DML → COMMIT/ROLLBACK
   Doris:      每个导入任务是一个原子操作(Import Transaction)

 设计理由:
   OLAP 引擎的写入是"批量追加"——一次导入可能写入数百万行。
   为每行维护事务状态(行锁、undo log)代价过高。
   Import 事务: 整个导入要么全部成功，要么全部回滚。

 对比:
   StarRocks: 相同的 Import 事务模型(同源)
   ClickHouse: 类似——每个 INSERT 是原子的，无多语句事务
   BigQuery:  每个 DML 是原子的，支持多语句事务(Preview)
   MySQL:     完整 ACID 事务(BEGIN/COMMIT/ROLLBACK/SAVEPOINT)
   PostgreSQL: 最完整的事务支持(嵌套事务/SAVEPOINT)

## 2. Label 机制 (幂等导入)

```sql
INSERT INTO users WITH LABEL insert_20240115
(username, email, age) VALUES ('alice', 'alice@example.com', 25);

```

 相同 Label 的导入不会重复执行——这是幂等性保证。
 Stream Load 也支持 Label: curl -H "label:txn_20240115" ...
 设计启示: Label 机制解决了"at-least-once 到 exactly-once"的转化。

## 3. BEGIN/COMMIT (2.1+，多语句写事务)

```sql
BEGIN;
INSERT INTO users (id, username, email) VALUES (1, 'alice', 'a@e.com');
INSERT INTO users (id, username, email) VALUES (2, 'bob', 'b@e.com');
COMMIT;

BEGIN;
INSERT INTO users (id, username, email) VALUES (3, 'charlie', 'c@e.com');
ROLLBACK;

```

带 Label 的事务

```sql
BEGIN WITH LABEL txn_20240115;
INSERT INTO users (id, username, email) VALUES (1, 'alice', 'a@e.com');
INSERT INTO orders (id, user_id, amount) VALUES (1, 1, 100.00);
COMMIT;

```

 设计分析:
   Doris 2.1+ 支持多语句写事务——这是向 HTAP 演进的信号。
   但仍不支持 SAVEPOINT、嵌套事务、读事务(SELECT 不在事务内)。

## 4. Two-Phase Commit (Stream Load)

 Stream Load 支持 2PC:
### 1. Prepare: curl -H "two_phase_commit:true" ...

### 2. Commit:  curl -X PUT .../api/db/_commit?txnId=xxx


## 5. 隔离级别

 默认 Read Committed: 导入 COMMIT 后对新查询可见。
 不支持 Repeatable Read / Serializable。

## 6. MVCC

查询看到查询开始时的一致性快照，不受并发导入影响。


```sql
SHOW TRANSACTION WHERE label = 'txn_20240115';
SHOW LOAD WHERE label = 'insert_20240115';

```

对引擎开发者的启示:
Label 幂等机制是分布式数据导入的关键设计:
客户端重试不会导致数据重复
简化了 at-least-once 消息系统(Kafka)与数据库的集成

