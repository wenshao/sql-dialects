# TDengine: 锁机制 (Locking)

> 参考资料:
> - [TDengine Documentation - Data Model](https://docs.tdengine.com/concept/)
> - [TDengine Documentation - SQL Reference](https://docs.tdengine.com/taos-sql/)


## TDengine 并发模型概述

TDengine 是时序数据库:
1. 不支持传统的行级锁或表级锁
2. 数据按时间线组织（每个设备/传感器一个子表）
3. 写入是追加式的，不支持 UPDATE（3.0 之前）
4. TDengine 3.0+ 支持有限的 UPDATE
5. 使用写前日志 (WAL) 保证数据持久性

## 写入并发


## 不同子表的写入可以完全并行

```sql
INSERT INTO d1001 VALUES (NOW, 10.3, 219, 0.31);
INSERT INTO d1002 VALUES (NOW, 12.6, 218, 0.33);
```

## 批量写入

```sql
INSERT INTO d1001 VALUES (NOW, 10.3, 219, 0.31)
                         (NOW + 1s, 10.4, 220, 0.32)
             d1002 VALUES (NOW, 12.6, 218, 0.33);
```

## 数据更新（TDengine 3.0+）


## 相同时间戳的数据会被覆盖（upsert 语义）

需要在创建数据库时允许更新

```sql
CREATE DATABASE mydb UPDATE 2;  -- 0=不允许, 1=允许部分列更新, 2=全列更新
```

## 注意事项


## 不支持 SELECT FOR UPDATE / FOR SHARE

## 不支持 LOCK TABLE

## 不支持事务 (BEGIN/COMMIT/ROLLBACK)

## 不支持 advisory locks

## 不支持 DELETE（3.0 之前）

## 数据按时间线分片，不同时间线可以并行写入

## 适合时序数据的高吞吐写入场景

## 数据不可变（或通过相同时间戳覆盖）
