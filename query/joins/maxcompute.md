# MaxCompute (ODPS): JOIN

> 参考资料:
> - [1] MaxCompute SQL - JOIN
>   https://help.aliyun.com/zh/maxcompute/user-guide/join
> - [2] MaxCompute SQL - MAPJOIN Hint
>   https://help.aliyun.com/zh/maxcompute/user-guide/mapjoin-hint


## 1. 标准 JOIN 类型


INNER JOIN

```sql
SELECT u.username, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id;

```

LEFT JOIN / RIGHT JOIN / FULL OUTER JOIN

```sql
SELECT u.username, o.amount
FROM users u
LEFT JOIN orders o ON u.id = o.user_id;

SELECT u.username, o.amount
FROM users u
FULL OUTER JOIN orders o ON u.id = o.user_id;

```

CROSS JOIN（笛卡尔积，需显式声明或设置 flag）
SET odps.sql.allow.cartesian = true;  -- 非 CROSS JOIN 时需开启

```sql
SELECT u.username, r.role_name
FROM users u CROSS JOIN roles r;

```

自连接

```sql
SELECT e.username AS employee, m.username AS manager
FROM employees e LEFT JOIN employees m ON e.manager_id = m.id;

```

多表 JOIN

```sql
SELECT u.username, o.amount, p.product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id;

```

## 2. SEMI JOIN / ANTI JOIN —— MaxCompute/Hive 特色语法


LEFT SEMI JOIN: 等价于 IN/EXISTS 子查询，但通常更高效

```sql
SELECT u.*
FROM users u
LEFT SEMI JOIN orders o ON u.id = o.user_id;
```

等价于: SELECT * FROM users WHERE id IN (SELECT user_id FROM orders)

LEFT ANTI JOIN: 等价于 NOT IN/NOT EXISTS

```sql
SELECT u.*
FROM users u
LEFT ANTI JOIN orders o ON u.id = o.user_id;
```

 等价于: SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM orders)

 设计分析: 为什么 MaxCompute 引入专门的 SEMI/ANTI JOIN 语法?
   IN/EXISTS 子查询需要优化器自动转换为 SEMI JOIN — 早期优化器做不好
   显式的 LEFT SEMI/ANTI JOIN 语法让用户直接指定执行策略
   对比:
     Hive:        LEFT SEMI JOIN 语法（相同，MaxCompute 继承自 Hive）
     PostgreSQL:  无专门语法（优化器自动将 EXISTS 转为 semi join）
     Spark SQL:   支持 LEFT SEMI/ANTI JOIN
     BigQuery:    无专门语法（用 EXISTS/NOT EXISTS）
     MySQL:       无专门语法

## 3. MAPJOIN —— 小表广播优化（MaxCompute 最重要的 JOIN 优化）


```sql
SELECT /*+ MAPJOIN(r) */ u.username, r.role_name
FROM users u
JOIN roles r ON u.role_id = r.id;

```

 MAPJOIN 的实现机制:
1. 将小表（roles）完整加载到每个 Map 任务的内存中

2. Map 阶段直接在内存中做 Hash JOIN（无需 Shuffle/Reduce）

3. 避免了大表的网络传输（Shuffle 是分布式 JOIN 的主要开销）


限制:
小表大小限制: 默认 512MB（可通过 SET odps.sql.mapjoin.memory.max 调整）
只支持 INNER/LEFT/RIGHT/SEMI JOIN（不支持 FULL OUTER JOIN）
小表必须放在 JOIN 的右侧（或用 hint 指定）

多表 MAPJOIN:

```sql
SELECT /*+ MAPJOIN(r, c) */ u.username, r.role_name, c.city_name
FROM users u
JOIN roles r ON u.role_id = r.id
JOIN cities c ON u.city_id = c.id;

```

 设计分析: MAPJOIN 的设计权衡
   Hive 的 MapJoin: 完全相同的语法和实现
   Spark 的 Broadcast Join: 同样的思路，但自动检测小表（无需 hint）
   BigQuery 的 Broadcast Join: 全自动（优化器决定）
   Snowflake: 全自动（微分区 + 自适应 JOIN 策略）

   MaxCompute 的 HBO 优化器: 基于历史执行统计自动选择 JOIN 策略
     如果历史显示某个表一直很小 → 自动 Broadcast
     如果数据量波动大 → 运行时动态切换（Adaptive Join）
     用户仍可通过 /*+ MAPJOIN */ hint 显式指定

## 4. JOIN 执行策略（伏羲调度视角）


 Shuffle Hash JOIN（默认）:
   两个大表按 JOIN key 做 hash 分发（shuffle），相同 key 的数据到同一个 Reducer
   Reducer 内做 Hash JOIN
   适用: 两个大表的等值 JOIN

 Sort-Merge JOIN:
   两表按 JOIN key 排序后合并
   适用: 两表已经按 JOIN key 排序（CLUSTERED BY ... SORTED BY ...）
   优势: 内存占用小（流式合并），适合超大表

 Broadcast JOIN（MAPJOIN）:
   小表广播到所有计算节点
   适用: 一大一小表的 JOIN

 对引擎开发者: JOIN 策略选择是查询优化器最关键的决策之一
   CBO 需要准确的统计信息（行数、大小、基数）
   HBO 利用历史执行信息补充 CBO 的不足
   Adaptive Join: 运行时根据实际数据量动态切换策略

## 5. LATERAL VIEW —— Hive 风格的数组/Map 展开


EXPLODE: 数组展开为多行

```sql
SELECT u.username, tag
FROM users u
LATERAL VIEW EXPLODE(u.tags) t AS tag;

```

OUTER EXPLODE: 保留空数组的行（生成 NULL）

```sql
SELECT u.username, tag
FROM users u
LATERAL VIEW OUTER EXPLODE(u.tags) t AS tag;

```

POSEXPLODE: 带位置索引

```sql
SELECT u.username, pos, tag
FROM users u
LATERAL VIEW POSEXPLODE(u.tags) t AS pos, tag;

```

MAP 展开

```sql
SELECT u.username, k, v
FROM users u
LATERAL VIEW EXPLODE(u.properties) t AS k, v;

```

 设计分析: LATERAL VIEW vs 标准 SQL LATERAL
   LATERAL VIEW 是 Hive 引入的语法，专用于 UDTF（表生成函数）
   标准 SQL 的 LATERAL 更通用（支持任意相关子查询）
   MaxCompute 不支持标准 LATERAL（只支持 LATERAL VIEW）
   对比:
     PostgreSQL: LATERAL + UNNEST(array_col)
     BigQuery:   UNNEST(array_col)（语法最简洁）
     Spark SQL:  LATERAL VIEW EXPLODE 或 LATERAL
     Presto:     CROSS JOIN UNNEST(array_col)

## 6. JOIN 限制与注意事项


 限制:
   不支持 NATURAL JOIN（Hive 也不支持）
   不支持 USING 子句（需要显式 ON）
   不支持标准 LATERAL 子查询
   非等值 JOIN 需要设置: SET odps.sql.allow.cartesian = true;
   JOIN 条件必须包含等值条件（优化器依赖等值条件选择 JOIN 策略）

 性能注意:
   避免无分区过滤的大表 JOIN（全表扫描 + 全量 Shuffle）
   分区表 JOIN 时在 WHERE 中加分区条件: WHERE a.dt = '20240115'
   数据倾斜: 某个 JOIN key 的数据量远大于其他 key
     解决: SKEWJOIN hint 或手动拆分热点 key

## 7. 横向对比: JOIN 优化


 Broadcast JOIN 自动化程度:
MaxCompute: hint + HBO 半自动     | Hive: hint 手动
Spark:      全自动（阈值配置）    | BigQuery: 全自动
Snowflake:  全自动                | ClickHouse: 自动（小表自动 broadcast）

 数据倾斜处理:
MaxCompute: SKEWJOIN hint          | Hive: MAPJOIN + 手动拆分
   Spark:      AQE（Adaptive Query Execution）自动处理
   BigQuery:   自动处理（内部分片）
   Snowflake:  自动处理

## 8. 对引擎开发者的启示


1. JOIN 策略选择（Broadcast vs Shuffle vs Sort-Merge）是优化器的核心

2. SEMI/ANTI JOIN 作为一等语法简化了用户和优化器的工作

3. HBO 利用历史执行信息优化 JOIN 策略 — 在 ETL 场景中效果显著

4. Adaptive JOIN（运行时动态切换策略）是现代查询引擎的标配

5. LATERAL VIEW 是 Hive 遗产，标准 LATERAL 更通用 — 新引擎应支持后者

6. 数据倾斜是分布式 JOIN 的最大性能杀手 — 自动化处理值得投资

