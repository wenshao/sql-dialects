# Hive: CTE (公共表表达式, 0.13+)

> 参考资料:
> - [1] Apache Hive Language Manual - CTE
>   https://cwiki.apache.org/confluence/display/Hive/Common+Table+Expression
> - [2] Apache Hive Language Manual - SELECT
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Select


## 1. 基本 CTE

```sql
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users WHERE age > 25;

```

多个 CTE

```sql
WITH
active_users AS (
    SELECT * FROM users WHERE status = 1
),
user_orders AS (
    SELECT user_id, COUNT(*) AS cnt, SUM(amount) AS total
    FROM orders GROUP BY user_id
)
SELECT u.username, o.cnt, o.total
FROM active_users u
JOIN user_orders o ON u.id = o.user_id;

```

CTE 引用前面的 CTE

```sql
WITH
base AS (SELECT * FROM users WHERE status = 1),
enriched AS (
    SELECT b.*, COUNT(o.id) AS order_count
    FROM base b LEFT JOIN orders o ON b.id = o.user_id
    GROUP BY b.id, b.username, b.status, b.age, b.city
)
SELECT * FROM enriched WHERE order_count > 5;

```

## 2. CTE + Hive 特有功能

CTE + LATERAL VIEW

```sql
WITH active_users AS (SELECT * FROM users WHERE status = 1)
SELECT u.username, tag
FROM active_users u
LATERAL VIEW EXPLODE(u.tags) t AS tag;

```

CTE + INSERT（Hive 的 CTE 可以配合 INSERT 使用）

```sql
WITH source AS (SELECT * FROM users WHERE status = 1)
INSERT INTO TABLE active_users_backup
SELECT * FROM source;

```

CTE + MAPJOIN hint

```sql
WITH small_table AS (SELECT * FROM roles WHERE active = 1)
SELECT /*+ MAPJOIN(s) */ u.username, s.role_name
FROM users u JOIN small_table s ON u.role_id = s.id;

```

## 3. CTE 的执行语义: 非物化展开

 Hive 的 CTE 不是物化的——每次引用 CTE 名称时，查询会被展开为子查询。
 这意味着如果一个 CTE 被引用多次，它的查询会被执行多次。

 示例: 下面的 stats CTE 被引用两次 → 执行两次
 WITH stats AS (SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id)
 SELECT * FROM stats WHERE total > 1000
 UNION ALL
 SELECT * FROM stats WHERE total < 100;

 优化: 如果 CTE 被多次引用且计算代价高，使用临时表替代
 CREATE TEMPORARY TABLE stats AS SELECT ... FROM orders GROUP BY ...;

 设计对比:
   PostgreSQL: CTE 在 12+ 默认也是展开的（之前版本是物化的优化屏障）
   SQL Server: CTE 总是展开的
   BigQuery:   CTE 可能被物化（优化器决定）
   Spark SQL:  CTE 展开行为与 Hive 一致

## 4. 递归 CTE: 不支持

 Hive 不支持 WITH RECURSIVE。
 hive.md 中记录 3.1+ 支持递归 CTE，但实际上支持非常有限，
 大多数 Hive 部署不使用递归 CTE。

 替代方案:
1. 多次自连接（固定层级深度）

2. 外部程序（Python/Spark）处理递归逻辑

3. 预计算层级数据写入宽表


## 5. 跨引擎对比: CTE 能力

 引擎          CTE 支持    递归 CTE   物化 CTE    版本
 MySQL         支持        支持       不物化       8.0+
 PostgreSQL    支持        支持       可选(12+)    8.4+
 Oracle        支持        支持       不物化       9i+
 Hive          支持        有限       不物化       0.13+
 Spark SQL     支持        不支持     不物化       支持
 BigQuery      支持        支持       优化器决定   支持
 Trino         支持        不支持     不物化       支持
 Flink SQL     支持        不支持     不物化       支持

## 6. 已知限制

1. 不支持递归 CTE（WITH RECURSIVE）

2. CTE 不物化: 多次引用 = 多次执行

3. CTE 不能用于 UPDATE/DELETE 语句

4. CTE 中不能使用 INSERT OVERWRITE

### 5. 0.13 之前不支持 CTE（需用子查询替代）


## 7. 对引擎开发者的启示

1. CTE 物化是一个优化机会: 如果 CTE 被多次引用，物化可以避免重复计算

    但物化增加了中间存储开销，需要优化器做代价权衡
2. 递归 CTE 在大数据引擎中不实用:

    递归的迭代次数不确定，与 MapReduce/Tez 的固定 DAG 模型冲突
3. CTE + INSERT 是 Hive 的有用扩展:

SQL 标准的 CTE 只用于 SELECT，Hive 扩展到 DML 是实用的设计

