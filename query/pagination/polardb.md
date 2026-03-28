# PolarDB / PolarDB-X: 分页 (Pagination)

> 参考资料:
> - [PolarDB MySQL 版 - SQL 参考](https://help.aliyun.com/zh/polardb/polardb-for-mysql/developer-reference/sql-reference)
> - [PolarDB-X SQL 参考 - SELECT](https://help.aliyun.com/zh/polardb/polardb-for-xscale/developer-reference/select)
> - [PolarDB-X 分布式查询优化](https://help.aliyun.com/zh/polardb/polardb-for-xscale/developer-reference/optimization)
> - ============================================================
> - 1. LIMIT / OFFSET（MySQL 兼容语法）
> - ============================================================
> - LIMIT count OFFSET offset（推荐写法，语义清晰）

```sql
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;
```

## 简写: LIMIT offset, count（注意: offset 在前、count 在后）

```sql
SELECT * FROM users ORDER BY id LIMIT 20, 10;
```

## 仅限制行数

```sql
SELECT * FROM users ORDER BY id LIMIT 10;
```

## 带总行数的分页查询（使用窗口函数避免额外 COUNT 查询）

```sql
SELECT *, COUNT(*) OVER() AS total_count
FROM users
ORDER BY id
LIMIT 10 OFFSET 20;
```

## SQL_CALC_FOUND_ROWS（已废弃，不推荐）


MySQL 8.0.17+ 已废弃 SQL_CALC_FOUND_ROWS，PolarDB 也建议避免使用:
SELECT SQL_CALC_FOUND_ROWS * FROM users ORDER BY id LIMIT 10 OFFSET 20;
SELECT FOUND_ROWS();
替代方案: 使用 COUNT(*) OVER() 或单独的 COUNT 查询

## OFFSET 的性能问题（特别是分布式环境）


单机 PolarDB MySQL: 与 MySQL 行为一致
OFFSET 100000 需要扫描 100010 行然后丢弃前 100000 行
时间复杂度: O(offset + limit)
分布式 PolarDB-X: 问题更严重
假设 8 个分片，LIMIT 10 OFFSET 100000:
每个分片返回 100010 行到协调节点
协调节点全局排序后取第 100001~100010 行
网络传输量: 8 * 100010 行（而非 10 行）

## 延迟关联优化（Deferred JOIN）


## 原理: 先在索引上快速定位 ID，再用 ID 回表取完整数据

```sql
SELECT u.* FROM users u
JOIN (
    SELECT id FROM users ORDER BY created_at DESC LIMIT 10 OFFSET 100000
) AS t ON u.id = t.id;
```

## 前提条件: 需要覆盖排序列和主键的索引

CREATE INDEX idx_created_id ON users (created_at DESC, id);

## 键集分页（Keyset Pagination）: 高性能替代方案


## 第一页

```sql
SELECT * FROM users ORDER BY id LIMIT 10;
```

## 后续页（已知上一页最后一条 id = 100）

```sql
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;
```

## 多列排序的键集分页（created_at DESC, id DESC）

```sql
SELECT * FROM users
WHERE (created_at, id) < ('2025-01-15', 42)
ORDER BY created_at DESC, id DESC
LIMIT 10;
```

## 窗口函数辅助分页


## ROW_NUMBER 分页

```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;
```

## 分组后 Top-N

```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t WHERE rn <= 3;
```

## PolarDB 特有说明


PolarDB MySQL 版（单机兼容）:
完全兼容 MySQL 分页语法
支持 MySQL 8.0 的窗口函数、降序索引等特性
共享存储架构: 只读节点可直接读取最新数据，无需复制延迟
PolarDB-X（分布式）:
分页查询需跨分片收集数据后全局排序
推荐使用分片键作为排序键，可利用 Bounded JOIN 优化
Pushdown 优化: 尽量将 LIMIT 下推到分片执行
如果排序键是分片键，排序可以在各分片内完成（避免全局排序）
索引建议:
分页排序列必须有索引（避免全表扫描 + filesort）
复合排序: CREATE INDEX idx ON table (sort_col1, sort_col2, id)
降序分页: CREATE INDEX idx ON table (created_at DESC, id DESC)

## 版本演进

PolarDB MySQL 5.6 兼容版:  LIMIT / OFFSET 基本分页
PolarDB MySQL 8.0 兼容版:  窗口函数、降序索引、行构造器比较
PolarDB-X 2.0:             分布式查询优化、LIMIT 下推、Bounded JOIN

## 横向对比: 分页语法差异


语法对比:
PolarDB:     LIMIT n OFFSET m / LIMIT m, n（MySQL 兼容）
MySQL:       LIMIT n OFFSET m / LIMIT m, n（PolarDB 的上游）
TDSQL:       LIMIT n OFFSET m（MySQL 兼容，分布式）
PostgreSQL:  LIMIT n OFFSET m + FETCH FIRST（不支持 LIMIT m, n）
分布式分页对比:
PolarDB-X:  协调节点全局排序，支持 LIMIT 下推优化
TDSQL:      shardkey 路由可减少跨分片查询
TiDB:       类似架构，全局排序后取 LIMIT
CockroachDB: 使用全局排序 + LIMIT，支持分布式游标
