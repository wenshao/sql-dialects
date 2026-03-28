# Apache Doris: JOIN

 Apache Doris: JOIN

 参考资料:
   [1] Doris Documentation - JOIN
       https://doris.apache.org/docs/sql-manual/sql-statements/

## 1. 标准 JOIN 类型

```sql
SELECT u.username, o.amount FROM users u INNER JOIN orders o ON u.id = o.user_id;
SELECT u.username, o.amount FROM users u LEFT JOIN orders o ON u.id = o.user_id;
SELECT u.username, o.amount FROM users u RIGHT JOIN orders o ON u.id = o.user_id;
SELECT u.username, o.amount FROM users u FULL OUTER JOIN orders o ON u.id = o.user_id;
SELECT u.username, r.role_name FROM users u CROSS JOIN roles r;

```

SEMI JOIN / ANTI JOIN (Doris/StarRocks 独有语法)

```sql
SELECT u.* FROM users u LEFT SEMI JOIN orders o ON u.id = o.user_id;
SELECT u.* FROM users u LEFT ANTI JOIN orders o ON u.id = o.user_id;

```

## 2. 分布式 JOIN 策略 (核心设计决策)

BROADCAST: 小表广播到所有 BE 节点

```sql
SELECT u.username, o.amount FROM users u
JOIN [broadcast] orders o ON u.id = o.user_id;

```

SHUFFLE: 按 JOIN 键重分布两表

```sql
SELECT u.username, o.amount FROM users u
JOIN [shuffle] orders o ON u.id = o.user_id;

```

BUCKET SHUFFLE: 利用分桶信息(2.0+)

```sql
SELECT u.username, o.amount FROM users u
JOIN [bucket] orders o ON u.id = o.user_id;

```

 Colocate JOIN: 同组表本地 JOIN(零网络开销)
 前提: 两表属于同一 Colocate Group 且按 JOIN 列分桶
 建表时: PROPERTIES ("colocate_with" = "group_name")

 设计分析:
   分布式 JOIN 的网络开销:
     Broadcast: O(小表 × 节点数) — 小表 < 100MB 时最优
     Shuffle:   O(两表数据量) — 大表 JOIN 大表
     Colocate:  O(0) — 数据已按 JOIN 键共置

## 3. Runtime Filter

 Doris 自动生成 Runtime Filter(Bloom Filter / IN 谓词)。
 在 Build 侧构建 Filter → 推送到 Probe 侧扫描 → 减少 JOIN 数据量。
 SET runtime_filter_type = 'IN_OR_BLOOM_FILTER';
 SET runtime_filter_wait_time_ms = 1000;

 对比:
   StarRocks: Global Runtime Filter(跨 Fragment 广播，更强)
   ClickHouse: 无 Runtime Filter
   BigQuery:  自动 Filter 推送(用户无感知)

## 4. 限制

不支持 NATURAL JOIN
不支持 ASOF JOIN(StarRocks 4.0+ 支持)
不支持 LATERAL JOIN(部分支持 LATERAL VIEW)

