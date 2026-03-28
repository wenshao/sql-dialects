# Spark SQL: JOIN (连接查询)

> 参考资料:
> - [1] Spark SQL - JOIN
>   https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-join.html
> - [2] Spark SQL - Performance Tuning (Broadcast Hints)
>   https://spark.apache.org/docs/latest/sql-performance-tuning.html


## 1. 标准 JOIN 类型

```sql
SELECT u.username, o.amount FROM users u INNER JOIN orders o ON u.id = o.user_id;
SELECT u.username, o.amount FROM users u LEFT JOIN orders o ON u.id = o.user_id;
SELECT u.username, o.amount FROM users u RIGHT JOIN orders o ON u.id = o.user_id;
SELECT u.username, o.amount FROM users u FULL OUTER JOIN orders o ON u.id = o.user_id;
SELECT u.username, r.role_name FROM users u CROSS JOIN roles r;
SELECT * FROM users JOIN orders USING (user_id);
SELECT * FROM users NATURAL JOIN orders;

```

自连接

```sql
SELECT e.username AS employee, m.username AS manager
FROM users e LEFT JOIN users m ON e.manager_id = m.id;

```

## 2. SEMI JOIN / ANTI JOIN: Spark 独特的 SQL 语法


LEFT SEMI JOIN: 返回左表中有匹配的行（等价于 EXISTS 子查询）

```sql
SELECT * FROM users u LEFT SEMI JOIN orders o ON u.id = o.user_id;

```

LEFT ANTI JOIN: 返回左表中没有匹配的行（等价于 NOT EXISTS 子查询）

```sql
SELECT * FROM users u LEFT ANTI JOIN orders o ON u.id = o.user_id;

```

 设计分析:
   SEMI/ANTI JOIN 作为 SQL 关键字是 Spark/Hive 特色——大多数数据库只支持 EXISTS 子查询。
   Spark 选择将其提升为一等语法，原因:
1. 语义更清晰: LEFT SEMI JOIN 比 WHERE EXISTS (...) 更直观

2. 优化更直接: 优化器不需要将 EXISTS 子查询解关联（de-correlate）

3. 与 DataFrame API 对齐: df.join(other, "id", "left_semi") 有直接对应


 对比:
   PostgreSQL: 只能通过 EXISTS/NOT EXISTS 实现（优化器内部转换为 Semi/Anti Join）
   MySQL:      同 PostgreSQL
   Oracle:     同 PostgreSQL（但 Oracle 的优化器更擅长 Semi/Anti 识别）
   Trino:      支持 LEFT SEMI JOIN 语法

## 3. LATERAL VIEW: 展开数组/Map 的 JOIN


EXPLODE: 将数组展开为多行

```sql
SELECT u.username, tag
FROM users u LATERAL VIEW EXPLODE(u.tags) t AS tag;

```

LATERAL VIEW OUTER: 保留空数组的行（类似 LEFT JOIN）

```sql
SELECT u.username, tag
FROM users u LATERAL VIEW OUTER EXPLODE(u.tags) t AS tag;

```

POSEXPLODE: 展开并包含位置索引

```sql
SELECT u.username, pos, tag
FROM users u LATERAL VIEW POSEXPLODE(u.tags) t AS pos, tag;

```

EXPLODE Map

```sql
SELECT u.username, key, value
FROM users u LATERAL VIEW EXPLODE(u.properties) t AS key, value;

```

多重 LATERAL VIEW

```sql
SELECT u.username, tag, score
FROM users u
LATERAL VIEW EXPLODE(u.tags) t1 AS tag
LATERAL VIEW EXPLODE(u.scores) t2 AS score;

```

 设计分析:
   LATERAL VIEW + EXPLODE 是 Spark/Hive 处理半结构化数据的核心模式。
   等价于 PostgreSQL 的 UNNEST 或 SQL 标准的 LATERAL JOIN。
   Spark 3.4+ 也支持 SQL 标准的 LATERAL 子查询。

## 4. JOIN 策略与 Hint


Broadcast JOIN: 将小表广播到所有 Executor（避免 Shuffle）

```sql
SELECT /*+ BROADCAST(r) */ u.username, r.role_name
FROM users u JOIN roles r ON u.role_id = r.id;

```

Shuffle Hash JOIN

```sql
SELECT /*+ SHUFFLE_HASH(o) */ u.username, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;

```

Sort Merge JOIN

```sql
SELECT /*+ MERGE(u, o) */ u.username, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;

```

数据倾斜 Hint（Spark 3.0+）

```sql
SELECT /*+ SKEW('users') */ u.username, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;

```

 JOIN 策略选择（Catalyst 优化器自动选择，也可通过 Hint 覆盖）:
   BroadcastHashJoin:  小表 < spark.sql.autoBroadcastJoinThreshold (10MB)
                       优点: 无 Shuffle，最快   缺点: 小表必须放入内存
   SortMergeJoin:      大表 JOIN 大表（默认策略）
                       优点: 通用，支持所有 JOIN 类型   缺点: 需要双表排序 + Shuffle
   ShuffledHashJoin:   一方较小但超过广播阈值
                       优点: 不需要排序   缺点: 需要 Shuffle，Hash 表占内存
   BroadcastNestedLoopJoin: 非等值 JOIN 条件
                       优点: 支持任意 JOIN 条件   缺点: O(n*m) 复杂度

 AQE（自适应查询执行）在运行时可以动态切换 JOIN 策略:
   如果 Sort-Merge JOIN 的一侧在 Shuffle 后发现数据量小于阈值，
   自动转换为 Broadcast Hash JOIN

## 5. 范围 JOIN（不等值 JOIN）


```sql
SELECT e.event_name, p.period_name
FROM events e
JOIN periods p ON e.event_time >= p.start_time AND e.event_time < p.end_time;

```

 范围 JOIN 通常使用 BroadcastNestedLoopJoin，性能较差
 优化方法: 将较小的表广播（/*+ BROADCAST(p) */）

## 6. LATERAL 子查询（Spark 3.4+）


```sql
SELECT u.username, t.total
FROM users u,
LATERAL (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;

```

## 7. Bucket JOIN（分桶优化）


 两表按相同列和桶数分桶时，JOIN 可以避免 Shuffle
 前提: 两表都 CLUSTERED BY (user_id) INTO N BUCKETS
 Spark 自动识别并使用 Bucket Join

## 8. 版本演进

Spark 2.0: 标准 JOIN, SEMI/ANTI JOIN, LATERAL VIEW, Broadcast Hint
Spark 3.0: SHUFFLE_HASH/MERGE Hint, SKEW Hint, AQE 动态 JOIN 切换
Spark 3.4: LATERAL 子查询

限制:
无 ASOF JOIN（时序场景需用窗口函数 + 范围条件模拟）
无 QUALIFY（JOIN 后过滤窗口函数结果需要子查询）
LATERAL VIEW 是 Hive 语法——Spark 3.4+ 也支持 SQL 标准 LATERAL
CROSS JOIN 没有 ON 条件——大表 CROSS JOIN 可能产生爆炸性数据量
Exchange（Shuffle）是 JOIN 的主要性能瓶颈——Broadcast 是最重要的优化手段

