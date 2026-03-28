# TDSQL (腾讯云): 执行计划与查询分析

> 参考资料:
> - [TDSQL Documentation](https://cloud.tencent.com/document/product/557)
> - [TDSQL for MySQL - SQL 优化](https://cloud.tencent.com/document/product/557/10637)


## EXPLAIN 基本用法（兼容 MySQL）


```sql
EXPLAIN SELECT * FROM users WHERE username = 'alice';
```

## EXPLAIN 格式


```sql
EXPLAIN FORMAT=TRADITIONAL SELECT * FROM users WHERE age > 25;
EXPLAIN FORMAT=JSON SELECT * FROM users WHERE age > 25;
EXPLAIN FORMAT=TREE SELECT * FROM users WHERE age > 25;
```

## EXPLAIN ANALYZE


```sql
EXPLAIN ANALYZE SELECT * FROM users WHERE age > 25;
```

## TDSQL 分布式特有功能


查看分布式查询路由
EXPLAIN 输出中包含分片（shard）信息
TDSQL 分布式版：
查看 SQL 路由到哪些分片

```sql
EXPLAIN SELECT * FROM users WHERE shard_key = 'value';
```

## 全表扫描（需要路由到所有分片）

```sql
EXPLAIN SELECT * FROM users WHERE age > 25;
```

## 执行计划关键指标（同 MySQL）


## type 列：system > const > eq_ref > ref > range > index > ALL

Extra 列：Using index, Using where, Using temporary, Using filesort

## 性能诊断


## 查看慢查询

```sql
SHOW SLOW_LOG;
```

## 查看进程列表

```sql
SHOW PROCESSLIST;
```

## 查看状态变量

```sql
SHOW STATUS LIKE 'Slow_queries';
```

## 统计信息


```sql
ANALYZE TABLE users;
```

注意：TDSQL 兼容 MySQL 语法，EXPLAIN 用法相同
注意：分布式版本的 EXPLAIN 显示 SQL 路由和分片信息
注意：没有分片键条件的查询会路由到所有分片（性能较差）
注意：腾讯云控制台提供 SQL 透视和性能分析工具
