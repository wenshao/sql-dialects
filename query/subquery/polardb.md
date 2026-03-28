# PolarDB / PolarDB-X: 子查询 (Subqueries)

PolarDB MySQL is MySQL-compatible with cloud-native storage;
PolarDB-X is a distributed version with sharding support.

> 参考资料:
> - [PolarDB-X SQL Reference - Subqueries](https://help.aliyun.com/zh/polardb/polardb-for-xscale/sql-reference/)
> - [PolarDB MySQL Documentation - SQL Syntax](https://help.aliyun.com/zh/polardb/polardb-for-mysql/)
> - [PolarDB-X Optimizer Architecture](https://help.aliyun.com/zh/polardb/polardb-for-xscale/optimizer/)


## 标量子查询


示例数据:
users(id, username, age, city)
orders(id, user_id, amount, status, dbpartition_key)

```sql
SELECT username,
    (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;
```

标量子查询必须返回 0 或 1 行，否则运行时报错
PolarDB MySQL: 继承 MySQL 8.0 优化器，可能将标量子查询缓存
PolarDB-X: 标量子查询如果涉及不同分片会在代理层合并

```sql
SELECT username,
    (SELECT SUM(amount) FROM orders WHERE user_id = users.id) AS total_amount
FROM users
WHERE city = 'Beijing';
```

## WHERE 子查询 (IN / NOT IN)


```sql
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blacklist);
```

NOT IN 的 NULL 陷阱:
如果子查询返回任何 NULL，NOT IN 的结果为 UNKNOWN（空集）。
因为: x NOT IN (1, NULL) = x<>1 AND x<>NULL = ? AND UNKNOWN = UNKNOWN
解决: 使用 NOT EXISTS 替代 NOT IN
PolarDB-X 分布式优化:
当子查询中包含分片键 (dbpartition_key) 条件时，
PolarDB-X 可以将 IN 子查询下推到对应分片执行。

## EXISTS / NOT EXISTS


```sql
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
```

EXISTS 在分布式环境下的优化:
PolarDB-X 优化器将 EXISTS 转为 Semi Join 并尽可能下推到分片。
如果关联条件涉及分片键，可以避免跨分片扫描。
NOT EXISTS 转换为 Anti Join。

## 比较运算符 + ALL / ANY / SOME


```sql
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);
SELECT * FROM users WHERE age >= ALL (SELECT age FROM users WHERE city = 'Beijing');
SELECT * FROM users WHERE age > ANY (SELECT age FROM users WHERE city = 'Beijing');
```

## FROM 子查询（派生表 / Derived Table）


```sql
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;
```

MySQL 8.0+ / PolarDB: 派生表合并优化（Derived Merge）
派生条件下推（Derived Condition Pushdown, MySQL 8.0+）
LATERAL 派生表（MySQL 8.0.14+ 兼容）

```sql
SELECT u.username, t.total
FROM users u,
LATERAL (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;
```

## CTE (WITH 子句)


## 简单 CTE（MySQL 8.0+ 兼容）

```sql
WITH city_stats AS (
    SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
    FROM users GROUP BY city
)
SELECT * FROM city_stats WHERE cnt > 10;
```

## 递归 CTE

```sql
WITH RECURSIVE org_tree AS (
    SELECT id, name, manager_id, 1 AS level
    FROM employees WHERE manager_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.manager_id, t.level + 1
    FROM employees e, org_tree t WHERE e.manager_id = t.id
)
SELECT * FROM org_tree ORDER BY level;
```

## PolarDB-X 分布式子查询优化


PolarDB-X 架构:
Compute Node (CN) 负责查询解析、优化和协调
Data Node (DN) 负责分片内数据存储和执行
子查询的性能取决于能否下推到 DN 执行
分片键优化:
当子查询引用的表与外表的分片键一致时，可完全下推:
users 按 id 分片, orders 按 user_id 分片 (id = user_id):

```sql
SELECT * FROM users WHERE id IN (
    SELECT user_id FROM orders WHERE amount > 100
);
```

跨分片子查询:
当分片键不一致时，PolarDB-X 生成分布式执行计划:
(a) Pull Union: 从各分片收集子查询结果，在 CN 层做 Semi Join
(b) Broadcast Join: 将子查询结果广播到所有分片
(c) Shuffle Join: 按关联键重新分布数据
使用 EXPLAIN 查看分布式执行计划:

```sql
EXPLAIN SELECT * FROM users WHERE id IN (
    SELECT user_id FROM orders WHERE amount > 100
);
```

优化建议:
(a) 确保子查询中关联列的分片策略一致
(b) 用 JOIN 替代 IN 子查询，给优化器更多分布式方案选择
(c) 对大结果集的子查询先物化到临时表

## 子查询优化: MySQL 8.0 优化器 + PolarDB-X 增强


MySQL 8.0 子查询优化策略（PolarDB 继承）:
IN (subquery)       → Semi Join (FirstMatch, LooseScan, Materialization, DuplicateWeedout)
EXISTS (subquery)   → Semi Join
标量子查询           → Subquery Cache
派生表              → Derived Merge + Derived Condition Pushdown
PolarDB-X 额外优化:
(a) 分布式 Semi Join: 下推 Semi Join 到数据节点
(b) 子查询结果缓存: 在 CN 层缓存子查询结果避免重复执行
(c) 智能路由: 根据分片键条件将子查询路由到最少的分片
EXPLAIN ANALYZE 查看实际执行统计:

```sql
EXPLAIN ANALYZE SELECT * FROM users
WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
```

## 横向对比: PolarDB vs 其他分布式数据库


## 分布式子查询优化:

PolarDB-X:  CN/DN 架构 + 下推优化 + Shuffle/Broadcast
TDSQL:      shardkey 路由优化
TiDB:       Coprocessor 下推 + Hash Join
CockroachDB: DistSQL 分布式执行
GaussDB:    分布式执行计划 + 数据重分布
2. MySQL 兼容性:
PolarDB MySQL:  完全兼容 MySQL 8.0 子查询语法
PolarDB-X:      兼容 MySQL，部分复杂子查询有分布式限制
TDSQL:          MySQL 兼容，shardkey 约束
3. LATERAL 支持:
PolarDB MySQL: 完全支持 (MySQL 8.0.14+)
PolarDB-X:     支持，但分布式模式下性能受限
TDSQL:         MySQL 8.0.14+ LATERAL（分布式限制）

## 对引擎开发者的启示


(1) PolarDB-X 的 CN/DN 架构对子查询的影响:
子查询优化的核心是"下推"——尽量在 DN 层完成 Semi Join。
CN 层的汇总操作是分布式子查询的性能瓶颈。
(2) 分片键设计决定子查询性能:
关联列的分片策略是否一致直接决定查询是本地执行还是分布式执行。
设计表结构时应充分考虑常用子查询的关联路径。
(3) MySQL 8.0 优化器是 PolarDB 的基础:
Semi Join 的多种策略（Materialization, FirstMatch, LooseScan）
已经非常成熟。PolarDB-X 在此基础上增加了分布式下推能力。

## 版本演进

MySQL 5.6:  子查询优化引入（Semi Join, Materialization）
MySQL 8.0:  LATERAL 派生表 (8.0.14), CTE, 窗口函数
PolarDB MySQL 5.6/8.0:  继承 MySQL 子查询优化 + 云原生存储优化
PolarDB-X 2.0:  分布式子查询优化，智能路由，下推增强
PolarDB-X 5.4:  自适应分布式执行计划，增强的 Semi Join 下推策略
