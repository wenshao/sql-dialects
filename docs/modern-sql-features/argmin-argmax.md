# ARG_MIN / ARG_MAX / MIN_BY / MAX_BY

"取最大/最小值对应行的另一列"——极高频需求的专用聚合函数。

## 支持矩阵

| 引擎 | 函数名 | 版本 | 备注 |
|------|--------|------|------|
| ClickHouse | `argMin(val, key)` / `argMax(val, key)` | 早期版本 | **最早推广者** |
| DuckDB | `arg_min(val, key)` / `arg_max(val, key)` | 0.3.0+ | 也支持 `min_by` / `max_by` |
| Snowflake | `MIN_BY(val, key)` / `MAX_BY(val, key)` | GA | 还支持 N 参数: `MIN_BY(val, key, N)` |
| Databricks | `min_by(val, key)` / `max_by(val, key)` | Runtime 7.0+ | Spark 3.0 引入 |
| Presto/Trino | `min_by(val, key)` / `max_by(val, key)` | 早期版本 | 支持 `min_by(val, key, N)` 返回数组 |
| StarRocks | `min_by(val, key)` / `max_by(val, key)` | 2.5+ | - |
| BigQuery | 不支持 | - | 用 `ARRAY_AGG` 模拟 |
| PostgreSQL | 不支持 | - | 需子查询或扩展 |
| MySQL | 不支持 | - | 需子查询 |
| Oracle | 不支持 | - | 用 `KEEP (DENSE_RANK FIRST/LAST)` |
| SQL Server | 不支持 | - | 需子查询 |

## 设计动机: 为什么需要这个函数

### 最典型的问题

"每个用户最近一次登录的 IP 地址是什么？"

```sql
-- 想要的语义: 找到 login_time 最大的那一行，取它的 ip_address
SELECT user_id, ???(ip_address, login_time) FROM logins GROUP BY user_id;
```

SQL 标准中没有直接表达这个语义的函数。`MAX(login_time)` 返回最大时间，但无法同时取出对应行的 `ip_address`。

### 传统方案的代价

```sql
-- 方案 1: ROW_NUMBER + 子查询（最常见但冗长）
SELECT user_id, ip_address FROM (
    SELECT user_id, ip_address,
           ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY login_time DESC) AS rn
    FROM logins
) t WHERE rn = 1;

-- 方案 2: 相关子查询（性能差）
SELECT l.user_id, l.ip_address
FROM logins l
WHERE l.login_time = (
    SELECT MAX(l2.login_time) FROM logins l2 WHERE l2.user_id = l.user_id
);

-- 方案 3: ROW_NUMBER + QUALIFY（仅支持 QUALIFY 的引擎）
SELECT user_id, ip_address
FROM logins
QUALIFY ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY login_time DESC) = 1;
```

以上方案要么语法冗长，要么性能不佳（窗口函数需要排序），要么引擎不支持。

### ARG_MAX 的解决方案

```sql
-- 一行搞定
SELECT user_id, arg_max(ip_address, login_time) AS last_ip
FROM logins
GROUP BY user_id;
```

语义清晰，且可以在聚合框架中实现，不需要窗口函数的排序开销。

## 语法对比

### ClickHouse

```sql
-- argMin(返回值, 排序键): 返回排序键最小时对应的返回值
SELECT
    user_id,
    argMax(ip_address, login_time) AS last_ip,
    argMin(ip_address, login_time) AS first_ip,
    max(login_time) AS last_login_time
FROM logins
GROUP BY user_id;

-- argMin/argMax 可以在 -If 组合子中使用（ClickHouse 特色）
SELECT argMaxIf(ip_address, login_time, status = 'success') AS last_success_ip
FROM logins;
```

### DuckDB

```sql
-- arg_min / arg_max（下划线风格）
SELECT
    user_id,
    arg_max(ip_address, login_time) AS last_ip,
    arg_min(ip_address, login_time) AS first_ip
FROM logins
GROUP BY user_id;

-- 也支持 min_by / max_by 别名
SELECT user_id, max_by(ip_address, login_time) AS last_ip
FROM logins GROUP BY user_id;
```

### Snowflake

```sql
-- MIN_BY / MAX_BY
SELECT
    user_id,
    MAX_BY(ip_address, login_time) AS last_ip,
    MIN_BY(ip_address, login_time) AS first_ip
FROM logins
GROUP BY user_id;

-- 支持第三个参数 N: 返回 Top-N 的数组
SELECT user_id, MAX_BY(ip_address, login_time, 3) AS last_3_ips
FROM logins
GROUP BY user_id;
```

### Presto / Trino

```sql
-- min_by / max_by
SELECT user_id, max_by(ip_address, login_time) AS last_ip
FROM logins GROUP BY user_id;

-- 支持 N 参数，返回数组
SELECT user_id, max_by(ip_address, login_time, 5) AS last_5_ips
FROM logins GROUP BY user_id;
```

### Oracle（KEEP DENSE_RANK —— 等效但语法复杂）

```sql
-- Oracle 的 KEEP (DENSE_RANK FIRST/LAST) 可以实现类似语义
SELECT
    user_id,
    MAX(ip_address) KEEP (DENSE_RANK LAST ORDER BY login_time) AS last_ip,
    MAX(ip_address) KEEP (DENSE_RANK FIRST ORDER BY login_time) AS first_ip
FROM logins
GROUP BY user_id;
```

注意: KEEP DENSE_RANK 比 ARG_MAX 更灵活（可以处理并列情况），但语法复杂得多。

### 等价改写: 不支持的引擎

#### BigQuery（ARRAY_AGG 模拟）

```sql
-- 最推荐的 BigQuery 写法
SELECT
    user_id,
    ARRAY_AGG(ip_address ORDER BY login_time DESC LIMIT 1)[OFFSET(0)] AS last_ip
FROM logins
GROUP BY user_id;
```

#### PostgreSQL（DISTINCT ON 或子查询）

```sql
-- PostgreSQL 独有的 DISTINCT ON（最简洁）
SELECT DISTINCT ON (user_id) user_id, ip_address
FROM logins
ORDER BY user_id, login_time DESC;

-- 通用子查询方案
SELECT user_id, (
    SELECT ip_address FROM logins l2
    WHERE l2.user_id = l.user_id
    ORDER BY login_time DESC LIMIT 1
) AS last_ip
FROM (SELECT DISTINCT user_id FROM logins) l;
```

#### MySQL

```sql
-- 子查询方案
SELECT l.user_id, l.ip_address
FROM logins l
INNER JOIN (
    SELECT user_id, MAX(login_time) AS max_time
    FROM logins GROUP BY user_id
) m ON l.user_id = m.user_id AND l.login_time = m.max_time;
```

## 对引擎开发者的实现建议

### 1. 聚合框架中的 Accumulator

ARG_MIN/ARG_MAX 本质上是一种特殊的聚合函数，需要在聚合框架中新增一种 accumulator：

```
ArgMaxAccumulator<V, K> {
    current_value: V     // 要返回的值
    current_key: K       // 排序键的当前最大值
    has_value: bool      // 是否已有值

    fn update(value: V, key: K):
        if !has_value || key > current_key:
            current_value = value
            current_key = key
            has_value = true

    fn merge(other: ArgMaxAccumulator):
        if !other.has_value: return
        if !has_value || other.current_key > current_key:
            current_value = other.current_value
            current_key = other.current_key
            has_value = true

    fn result() -> V:
        return current_value
}
```

### 2. 类型系统

- 返回值类型 = 第一个参数的类型
- 排序键类型 = 第二个参数的类型（必须支持比较运算）
- NULL 处理: 当排序键为 NULL 时应跳过该行（与 MIN/MAX 忽略 NULL 的行为一致）

### 3. 分布式执行

在分布式环境中，ARG_MAX 可以正确地做两阶段聚合：

```
-- 第一阶段（每个节点局部聚合）
partial_result = (current_value, current_key)

-- 第二阶段（合并各节点结果）
merge: 比较各 partial 的 current_key，取最大者的 current_value
```

这比窗口函数方案高效得多——窗口函数需要 shuffle + 排序，而 ARG_MAX 只需要聚合。

### 4. N 参数扩展

Snowflake/Trino 支持 `MAX_BY(val, key, N)` 返回 Top-N，实现方式：

- 用大小为 N 的最小堆（min-heap）维护 Top-N 的 (key, value) 对
- merge 时合并两个堆，保留 Top-N
- 结果返回数组类型

### 5. 并列值处理

当多行的排序键相同时，返回哪一行的值？各引擎行为不同：

| 引擎 | 并列行为 |
|------|---------|
| ClickHouse | 不确定（取决于数据顺序） |
| Snowflake | 不确定 |
| Oracle KEEP | 需要额外 MAX/MIN 指定 |

建议: 文档中明确说明行为不确定，推荐用户添加 tiebreaker 列。

## 性能对比

| 方案 | 时间复杂度 | 内存 | 分布式友好 |
|------|-----------|------|-----------|
| ARG_MAX 聚合 | O(N) | O(groups) | 好（两阶段聚合） |
| ROW_NUMBER + 子查询 | O(N log N) | O(N) | 差（需排序 + shuffle） |
| 相关子查询 | O(N * M) | O(1) | 差 |
| DISTINCT ON (PG) | O(N log N) | O(N) | N/A |

ARG_MAX 的 O(N) 时间复杂度和 O(groups) 内存是其最大优势。

## 参考资料

- ClickHouse: [argMin / argMax](https://clickhouse.com/docs/en/sql-reference/aggregate-functions/reference/argmin)
- Snowflake: [MIN_BY / MAX_BY](https://docs.snowflake.com/en/sql-reference/functions/min_by)
- DuckDB: [arg_min / arg_max](https://duckdb.org/docs/sql/aggregates#arg_min-arg_max)
- Trino: [min_by / max_by](https://trino.io/docs/current/functions/aggregate.html#min_by)
