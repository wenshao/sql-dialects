# ksqlDB: 事务

ksqlDB 不支持传统事务
基于 Kafka 的 exactly-once 语义提供一致性保证
============================================================
Kafka 事务语义
============================================================
ksqlDB 支持 Kafka 的 exactly-once 语义
配置 processing.guarantee
ksql.streams.processing.guarantee = exactly_once_v2
这保证了：
1. 持久查询的输入/输出原子性
2. 不会产生重复数据
3. 状态存储与输出一致
============================================================
一致性模型
============================================================
Push Query：最终一致（eventually consistent）

```sql
SELECT * FROM user_totals EMIT CHANGES;
```

## Pull Query：强一致（读取最新状态）

```sql
SELECT * FROM user_totals WHERE user_id = 'user_123';
```

## 不支持的事务操作


不支持 BEGIN / COMMIT / ROLLBACK
不支持 SAVEPOINT
不支持事务隔离级别
不支持 SELECT ... FOR UPDATE
不支持多语句事务

## 容错和恢复


查询失败自动恢复
ksqlDB 使用 Kafka 的 consumer group 和 changelog 实现状态恢复
查看查询状态

```sql
SHOW QUERIES;
```

注意：ksqlDB 基于 Kafka 事务语义
注意：exactly-once 保证处理不丢不重
注意：不支持传统的 BEGIN/COMMIT/ROLLBACK
注意：Pull Query 提供强一致读取
