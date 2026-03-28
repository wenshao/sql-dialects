# 人大金仓 (KingbaseES): 执行计划与查询分析

> 参考资料:
> - [KingbaseES Documentation](https://help.kingbase.com.cn/)
> - KingbaseES 基于 PostgreSQL，EXPLAIN 语法兼容


## EXPLAIN 基本用法（兼容 PostgreSQL）


```sql
EXPLAIN SELECT * FROM users WHERE username = 'alice';
```

## EXPLAIN ANALYZE


```sql
EXPLAIN ANALYZE SELECT * FROM users WHERE age > 25;
```

## 输出格式


```sql
EXPLAIN (FORMAT TEXT) SELECT * FROM users WHERE age > 25;
EXPLAIN (FORMAT JSON) SELECT * FROM users WHERE age > 25;
EXPLAIN (FORMAT YAML) SELECT * FROM users WHERE age > 25;
EXPLAIN (FORMAT XML) SELECT * FROM users WHERE age > 25;
```

## 完整选项


```sql
EXPLAIN (ANALYZE, BUFFERS, COSTS, TIMING, VERBOSE)
SELECT u.*, COUNT(o.id)
FROM users u LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.id;
```

## 执行计划操作（同 PostgreSQL）


Seq Scan              顺序扫描
Index Scan            索引扫描
Index Only Scan       仅索引扫描
Bitmap Heap Scan      位图堆扫描
Hash Join             哈希连接
Nested Loop           嵌套循环
Merge Join            合并连接
Sort                  排序
HashAggregate         哈希聚合

## 统计信息


```sql
ANALYZE users;
```

## 查看统计信息

```sql
SELECT relname, reltuples, relpages
FROM pg_class WHERE relname = 'users';
```

## 性能视图


## 查看活跃查询

```sql
SELECT * FROM pg_stat_activity WHERE state = 'active';
```

## 查看表统计

```sql
SELECT * FROM pg_stat_user_tables WHERE relname = 'users';
```

注意：KingbaseES 基于 PostgreSQL，EXPLAIN 语法完全兼容
注意：所有 PostgreSQL 的执行计划分析方法都适用
注意：支持 ANALYZE, BUFFERS, COSTS, TIMING, VERBOSE 选项
注意：统计信息管理方式与 PostgreSQL 相同
