# Apache Impala: 锁机制 (Locking)

> 参考资料:
> - [Apache Impala Documentation - Impala Locking](https://impala.apache.org/docs/build/html/topics/impala_locking.html)
> - [Apache Impala Documentation - SQL Statements](https://impala.apache.org/docs/build/html/topics/impala_langref.html)


## Impala 并发模型概述

Impala 是 MPP SQL 查询引擎（基于 HDFS/Kudu/HBase）:
1. 不支持传统的行级锁或事务
2. 对 Kudu 表支持有限的 DML (INSERT/UPDATE/DELETE)
3. 使用 Hive Metastore 的元数据锁
4. HDFS 表是 append-only

## Kudu 表（支持 DML）


Kudu 表支持 INSERT/UPDATE/DELETE
```sql
CREATE TABLE orders (
    id      BIGINT,
    status  STRING,
    amount  DECIMAL(10,2)
)
PRIMARY KEY (id)
STORED AS KUDU;
```


Kudu 使用 MVCC 和行级锁
```sql
INSERT INTO orders VALUES (1, 'new', 100.00);
UPDATE orders SET status = 'shipped' WHERE id = 1;
DELETE FROM orders WHERE id = 1;
```


Kudu 的写操作获取行级锁
并发修改同一行可能导致冲突

## HDFS/Parquet 表（不支持行级操作）


HDFS 表只支持 INSERT（append）
```sql
CREATE TABLE logs (
    ts     TIMESTAMP,
    msg    STRING
)
STORED AS PARQUET;

INSERT INTO logs VALUES (NOW(), 'test message');
```


不支持 UPDATE/DELETE

## 元数据锁（Hive Metastore）


DDL 操作获取 Hive Metastore 的元数据锁
COMPUTE STATS 获取排他锁
```sql
COMPUTE STATS orders;
```


## 乐观锁（Kudu 表）


```sql
ALTER TABLE orders ADD COLUMNS (version INT DEFAULT 1);
```


Kudu UPSERT 操作
```sql
UPSERT INTO orders VALUES (100, 'shipped', 99.99, 6);
```


## 注意事项


1. 不支持 SELECT FOR UPDATE / FOR SHARE
2. 不支持 LOCK TABLE
3. 不支持多语句事务
4. Kudu 表支持行级 DML
5. HDFS 表只支持 INSERT
6. 元数据锁通过 Hive Metastore 管理
