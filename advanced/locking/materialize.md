# Materialize: 锁机制 (Locking)

> 参考资料:
> - [Materialize Documentation - Transactions](https://materialize.com/docs/sql/begin/)
> - [Materialize Documentation - Architecture](https://materialize.com/docs/overview/architecture/)


## Materialize 并发模型概述

Materialize 是流式数据库（Streaming Database）:
1. 专注于增量计算和物化视图
2. 使用严格可序列化隔离
3. 不支持传统的行级锁或表级锁
4. 写入通过 CDC/sources 进行，不通过传统 DML

## 事务（有限支持）


## 只读事务

```sql
BEGIN;
    SELECT * FROM orders;
    SELECT * FROM customers;
COMMIT;
```

## Materialize 使用 Timely Dataflow 引擎

所有读取在同一时间点一致

## 严格可序列化隔离


Materialize 默认提供严格可序列化 (Strict Serializable) 隔离
无需额外配置
所有查询看到一致的时间点数据

## 注意事项


## 不支持 SELECT FOR UPDATE / FOR SHARE

## 不支持 LOCK TABLE

## 不支持 advisory locks

## 写入通过 Sources 和 Sinks 进行

## 不支持 INSERT/UPDATE/DELETE（传统 DML）

## 物化视图自动增量更新，无需锁定

## 适合实时分析和流处理场景
