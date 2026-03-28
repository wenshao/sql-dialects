# BigQuery: JOIN

> 参考资料:
> - [1] BigQuery SQL Reference - JOIN
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#join_types
> - [2] BigQuery - Join Optimization
>   https://cloud.google.com/bigquery/docs/best-practices-performance-compute


## 1. 标准 JOIN 类型（全部支持）


```sql
SELECT u.username, o.amount FROM users u INNER JOIN orders o ON u.id = o.user_id;
SELECT u.username, o.amount FROM users u LEFT JOIN orders o ON u.id = o.user_id;
SELECT u.username, o.amount FROM users u RIGHT JOIN orders o ON u.id = o.user_id;
SELECT u.username, o.amount FROM users u FULL OUTER JOIN orders o ON u.id = o.user_id;
SELECT u.username, r.role_name FROM users u CROSS JOIN roles r;
SELECT * FROM users JOIN orders USING (user_id);

```

## 2. UNNEST: BigQuery 独有的数组 JOIN


UNNEST 将 ARRAY 列展开为行，然后 JOIN:

```sql
SELECT u.username, tag
FROM users u CROSS JOIN UNNEST(u.tags) AS tag;

```

LEFT JOIN UNNEST（保留没有标签的用户）

```sql
SELECT u.username, tag
FROM users u LEFT JOIN UNNEST(u.tags) AS tag ON TRUE;

```

UNNEST WITH OFFSET（获取数组位置）

```sql
SELECT u.username, tag, pos
FROM users u CROSS JOIN UNNEST(u.tags) AS tag WITH OFFSET AS pos;

```

 设计分析:
   UNNEST 是 BigQuery 嵌套类型设计的核心操作。
   传统数据库需要子表 + JOIN 实现一对多关系。
   BigQuery 用 ARRAY 列 + UNNEST 替代，避免了 JOIN 的开销。
   这是"宽表设计"（denormalization）的语言层支持。

## 3. JOIN 优化（对引擎开发者）


BigQuery 的 JOIN 策略（Dremel 引擎自动选择）:
(a) Broadcast Join: 小表广播到所有节点
适用: 一方表很小（<几百 MB）
→ 大表不移动，小表复制到每个 slot
(b) Shuffle Join: 两表按 JOIN 键 hash 分布到相同节点
适用: 两方都很大
→ 数据 shuffle（网络传输），然后本地 JOIN

优化建议:
(a) 小表放在 JOIN 的右侧（优化器可能自动选择 broadcast）
(b) 使用分区和聚集列作为 JOIN 键（减少 shuffle）
(c) 避免 CROSS JOIN + UNNEST 在大数组上（膨胀行数）

不支持: NATURAL JOIN（BigQuery 明确不支持）

TABLESAMPLE（抽样连接，减少扫描量）

```sql
SELECT u.username, o.amount
FROM users u TABLESAMPLE SYSTEM (10 PERCENT)
JOIN orders o ON u.id = o.user_id;

```

## 4. 对比与引擎开发者启示

BigQuery JOIN 的设计:
(1) Broadcast + Shuffle → 分布式 JOIN 双策略
(2) UNNEST → 数组展开 JOIN（替代子表）
(3) 无 NATURAL JOIN → 明确禁止（易出错的语法）
(4) TABLESAMPLE → 抽样 JOIN（成本控制）

对引擎开发者的启示:
分布式引擎的 JOIN 需要 broadcast 和 shuffle 两种策略。
UNNEST 是嵌套类型引擎的必备操作。
禁止 NATURAL JOIN 是合理的设计选择（减少意外行为）。

