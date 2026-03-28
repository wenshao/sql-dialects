# TDSQL: DELETE

TDSQL distributed MySQL-compatible syntax.

> 参考资料:
> - [TDSQL-C MySQL Documentation](https://cloud.tencent.com/document/product/1003)
> - [TDSQL MySQL Documentation](https://cloud.tencent.com/document/product/557)
> - [TDSQL Distributed Transaction Guide](https://cloud.tencent.com/document/product/557/10575)
> - ============================================================
> - 1. 基本 DELETE
> - ============================================================
> - 单行删除

```sql
DELETE FROM users WHERE username = 'alice';
```

## 多条件删除

```sql
DELETE FROM users WHERE status = 0 AND last_login < '2023-01-01';
```

## 删除所有行（逐行删除，产生 binlog，可回滚）

```sql
DELETE FROM users;
```

## 快速清空表（DDL 操作，清空所有分片数据）

```sql
TRUNCATE TABLE users;
```

## MySQL 风格的高级 DELETE


## 带 LIMIT / ORDER BY（按顺序限量删除）

```sql
DELETE FROM users WHERE status = 0 ORDER BY created_at LIMIT 100;
```

## 多表 DELETE（JOIN）

```sql
DELETE u FROM users u
JOIN blacklist b ON u.email = b.email;
```

## 同时从多个表删除

```sql
DELETE u, o FROM users u
JOIN orders o ON u.id = o.user_id
WHERE u.status = 0;
```

## 子查询删除

```sql
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);
```

## IGNORE（忽略外键约束错误等）

```sql
DELETE IGNORE FROM users WHERE id = 1;
```

## CTE + DELETE


```sql
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE u FROM users u JOIN inactive i ON u.id = i.id;
```

## 分布式 DELETE 与 shardkey 路由

TDSQL 是分布式数据库，数据按 shardkey 分布到不同分片。
DELETE 操作的路由行为取决于 WHERE 条件:
(1) WHERE 包含 shardkey（单分片路由，性能最优）:
假设 id 是 shardkey:

```sql
DELETE FROM users WHERE id = 42;
```

## (2) WHERE 包含 shardkey 范围:

```sql
DELETE FROM users WHERE id BETWEEN 100 AND 200;
```

## (3) WHERE 不包含 shardkey（全分片扫描，性能差）:

```sql
DELETE FROM users WHERE email = 'alice@example.com';
```

## 跨分片 DELETE 的分布式事务

当 DELETE 涉及多个分片时，TDSQL 使用分布式事务:
(1) 两阶段提交（2PC）:
Phase 1: Coordinator 向所有参与者发送 PREPARE
Phase 2: 所有参与者就绪后发送 COMMIT
如果任何参与者失败，发送 ROLLBACK
(2) 性能影响:
跨 N 个分片 = N 次网络 RTT（PREPARE）+ N 次网络 RTT（COMMIT）
延迟 = 2 * N * RTT（单分片延迟的 2N 倍）
(3) 大批量跨分片 DELETE:
分布式事务持有锁的时间长，可能阻塞其他操作
建议分批执行，每批控制在单个分片范围内

## 多表 DELETE 的分布式行为


## 如果 JOIN 的表在不同的分片:

```sql
DELETE u FROM users u
JOIN blacklist b ON u.email = b.email;
```

如果两表 shardkey 相同（推荐）:
同一分片上的 JOIN 可以在本地执行
不需要跨分片数据传输，性能接近单机 MySQL

## 广播表的 DELETE

广播表（小表广播）: 数据完整复制到每个分片节点
广播表的 DELETE 特点:
DELETE 同步发送到所有节点执行
使用分布式事务保证所有节点的一致性
适合维度表、配置表等小表的删除
示例:
DELETE FROM sys_config WHERE config_key = 'deprecated_feature';
所有分片同时执行此 DELETE

## 批量删除策略


策略 1: 按 shardkey 分批删除（推荐）
先查出需要删除的 shardkey 范围
按 shardkey 范围分批 DELETE（每批在单个分片内）
避免跨分片事务，性能最优
策略 2: TRUNCATE（清空所有分片数据）
TRUNCATE TABLE users;
清空所有分片上的数据，最快但不可回滚
策略 3: DROP TABLE + 重建
适合需要完全重建的场景
策略 4: 分区表 DROP PARTITION
如果表按时间分区，可以直接 DROP 旧分区
ALTER TABLE logs DROP PARTITION p2020;
TDSQL 在分布式环境下会自动协调各分片的分区操作

## 横向对比: TDSQL vs 单机 MySQL vs 其他分布式数据库

TDSQL:         DELETE 路由取决于 shardkey，跨分片使用 2PC
单机 MySQL:    DELETE 无路由概念，单机执行
TiDB:          DELETE 路由取决于主键/索引，使用 Percolator 事务模型
OceanBase:     DELETE 路由取决于分区键，使用 2PC + Paxos
CockroachDB:   DELETE 使用 Parallel Commits，range-based 分片
共同特点:
TDSQL 语法与 MySQL 完全兼容，迁移无需修改 DELETE 语句
但性能特征不同: 需要关注 shardkey 路由以获得最佳性能
