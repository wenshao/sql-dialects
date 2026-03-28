# MaxCompute (ODPS): CTE（公共表表达式）

> 参考资料:
> - [1] MaxCompute SQL - CTE
>   https://help.aliyun.com/zh/maxcompute/user-guide/cte
> - [2] MaxCompute SQL - SELECT
>   https://help.aliyun.com/zh/maxcompute/user-guide/select


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

CTE 引用前面的 CTE（链式引用）

```sql
WITH
base AS (SELECT * FROM users WHERE status = 1),
enriched AS (
    SELECT b.*, COUNT(o.id) AS order_count
    FROM base b LEFT JOIN orders o ON b.id = o.user_id
    GROUP BY b.id, b.username, b.email, b.status, b.age
)
SELECT * FROM enriched WHERE order_count > 5;

```

## 2. CTE + INSERT（ETL 管道中的常见模式）


```sql
WITH inactive AS (
    SELECT * FROM users WHERE last_login < DATETIME '2023-01-01 00:00:00'
)
INSERT INTO TABLE users_archive
SELECT * FROM inactive;

```

CTE + INSERT OVERWRITE + 分区

```sql
WITH daily_agg AS (
    SELECT user_id, SUM(amount) AS total, COUNT(*) AS cnt
    FROM orders WHERE dt = '20240115'
    GROUP BY user_id
)
INSERT OVERWRITE TABLE user_daily_summary PARTITION (dt = '20240115')
SELECT user_id, total, cnt FROM daily_agg;

```

## 3. CTE + MAPJOIN hint


```sql
WITH small_table AS (
    SELECT * FROM roles WHERE active = 1
)
SELECT /*+ MAPJOIN(s) */ u.username, s.role_name
FROM users u
JOIN small_table s ON u.role_id = s.id;

```

CTE + LATERAL VIEW

```sql
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT u.username, tag
FROM active_users u
LATERAL VIEW EXPLODE(u.tags) t AS tag;

```

## 4. 递归 CTE —— MaxCompute 的限制


 MaxCompute 不支持递归 CTE（WITH RECURSIVE）
 这是 MaxCompute 与标准 SQL 的重要偏离

 为什么不支持?
   递归 CTE 在分布式环境下实现复杂:
     每次迭代需要全局同步（检查终止条件）
     迭代次数不确定 → 无法预估资源
     批处理引擎的 DAG 执行模型不适合迭代计算

   对比:
     Hive:        不支持递归 CTE（相同原因）
     Spark SQL:   不支持递归 CTE（相同原因）
     BigQuery:    支持递归 CTE（有最大迭代次数限制）
     PostgreSQL:  完整支持递归 CTE
     MySQL 8.0+:  支持递归 CTE
     Snowflake:   支持递归 CTE

   替代方案: 见 scenarios/hierarchical-query:
     多层自连接（固定深度）
     路径枚举模型（path LIKE '1/2/%'）
     闭包表模型（ancestor/descendant/depth）

## 5. CTE 的执行策略: 内联 vs 物化


MaxCompute 优化器决定 CTE 是内联展开还是物化:
内联: 将 CTE 的 SQL 替换到引用位置（多次引用 = 多次计算）
物化: 先计算 CTE 结果存为临时数据，后续引用读取临时数据

用户无法通过 hint 直接控制（不同于某些引擎）
优化器的决策基于:
CTE 被引用的次数（多次引用倾向于物化）
CTE 的计算代价（高代价倾向于物化）
HBO 的历史执行信息

对比:
PostgreSQL 12+: CTE 默认内联（12 之前强制物化，这是性能陷阱）
SQL Server:     CTE 总是内联
BigQuery:       CTE 内联（多次引用可能多次计算）
Snowflake:      CTE 优化器自动决定

如果需要强制物化: 使用临时表

```sql
CREATE TABLE temp_active_users LIFECYCLE 1 AS
SELECT * FROM users WHERE status = 1;
```

 后续多次引用 temp_active_users 避免重复计算

## 6. CTE 的嵌套限制


 MaxCompute CTE 嵌套层数有限制（通常 64 层）
 超过限制会报错: ODPS-0123091

 最佳实践: 避免过深嵌套
 如果 CTE 链过长，考虑拆分为多个 INSERT OVERWRITE 语句
 每个语句的结果写入中间表，下个语句从中间表读取

## 7. 横向对比: CTE 能力


 基本 CTE:
MaxCompute: 支持     | 所有现代引擎均支持

 递归 CTE:
MaxCompute: 不支持   | Hive/Spark: 不支持
BigQuery: 支持       | PostgreSQL/MySQL 8.0: 支持
Snowflake: 支持      | SQL Server: 支持

 CTE 物化控制:
MaxCompute: 优化器自动  | PostgreSQL 12+: MATERIALIZED/NOT MATERIALIZED hint
SQL Server: 总是内联    | BigQuery: 总是内联

 CTE + DML:
MaxCompute: CTE + INSERT INTO/OVERWRITE | PostgreSQL: CTE + INSERT/UPDATE/DELETE
   BigQuery: CTE + INSERT/UPDATE/DELETE/MERGE

## 8. 对引擎开发者的启示


1. CTE 是 SQL 可读性的核心工具 — 必须支持

2. 递归 CTE 在分布式引擎中实现困难，但用户需求强烈

    BigQuery 的有限递归（最大迭代次数）是可参考的折中方案
3. CTE 的内联/物化策略对性能影响巨大:

    多次引用的高代价 CTE 应物化，单次引用的应内联
4. PostgreSQL 12 之前的"CTE 强制物化"是性能陷阱的典型案例

5. CTE + INSERT 是 ETL 管道中最常用的模式 — 优先支持

6. CTE 嵌套限制应有清晰的错误信息和文档指引

