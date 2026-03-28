# BigQuery: DELETE

> 参考资料:
> - [1] BigQuery SQL Reference - DELETE
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/dml-syntax#delete_statement
> - [2] BigQuery Documentation - DML Quotas
>   https://cloud.google.com/bigquery/quotas#dml
> - [3] BigQuery Documentation - Managing Partitioned Tables
>   https://cloud.google.com/bigquery/docs/managing-partitioned-tables


## 1. 基本语法


基本删除（WHERE 是必须的!）

```sql
DELETE FROM myproject.mydataset.users WHERE username = 'alice';

```

删除所有行（必须显式 WHERE true）

```sql
DELETE FROM myproject.mydataset.users WHERE true;

```

子查询删除

```sql
DELETE FROM myproject.mydataset.users
WHERE id IN (SELECT user_id FROM myproject.mydataset.blacklist);

```

EXISTS 删除

```sql
DELETE FROM myproject.mydataset.users u
WHERE EXISTS (
    SELECT 1 FROM myproject.mydataset.blacklist b WHERE b.email = u.email
);

```

CTE + DELETE

```sql
WITH inactive AS (
    SELECT id FROM myproject.mydataset.users
    WHERE last_login < TIMESTAMP '2023-01-01'
)
DELETE FROM myproject.mydataset.users WHERE id IN (SELECT id FROM inactive);

```

## 2. DELETE 的内部机制（对引擎开发者）


 BigQuery 的 DELETE 是 Copy-on-Write:
   (1) 读取包含待删除行的存储文件
   (2) 在内存中过滤掉待删除行
   (3) 将剩余行写入新的存储文件
   (4) 更新元数据指向新文件

 关键: DELETE 1 行可能需要重写整个分区的存储文件。
 这与 MySQL 的"标记删除"（在页中标记 delete flag）截然不同。

 DML 配额的影响:
   每个表每天最多 1500 次 DML
   高频 DELETE 会迅速耗尽配额
   推荐: 批量删除 > 逐行删除

## 3. 分区删除的优化策略


按分区条件删除（最佳实践）

```sql
DELETE FROM myproject.mydataset.events
WHERE event_date = '2024-01-15';
```

只重写 2024-01-15 分区的文件

按时间范围删除

```sql
DELETE FROM myproject.mydataset.events
WHERE event_date BETWEEN '2024-01-01' AND '2024-01-31';

```

更高效的替代方案: 分区过期
ALTER TABLE myproject.mydataset.events
SET OPTIONS (partition_expiration_days = 90);
超过 90 天的分区自动删除，不消耗 DML 配额!

TRUNCATE: 清空表（不受 DML 配额限制!）

```sql
TRUNCATE TABLE myproject.mydataset.users;
```

 TRUNCATE 是元数据操作（删除所有存储文件引用），极快。
 对比 DELETE WHERE true: 需要读写所有数据，消耗配额。

## 4. 不支持的 DELETE 特性


 不支持: JOIN DELETE（DELETE FROM ... JOIN ...）
 不支持: ORDER BY / LIMIT
 不支持: RETURNING
 必须有: WHERE 子句（防止误操作）

 对比:
   MySQL:      支持 JOIN DELETE, LIMIT, ORDER BY
   PostgreSQL: 支持 USING (JOIN), RETURNING
   SQLite:     支持 RETURNING（3.35.0+），LIMIT 需编译选项
   ClickHouse: 两种 DELETE + DROP PARTITION + TTL

## 5. 数据生命周期管理（替代 DELETE 的推荐方案）


 BigQuery 不推荐用 DELETE 管理数据生命周期，推荐:

 (a) 分区过期（最推荐）:
 ALTER TABLE logs SET OPTIONS (partition_expiration_days = 90);
 → 自动删除 90 天前的分区，零运维，不消耗配额

 (b) 表过期:
 ALTER TABLE tmp SET OPTIONS (expiration_timestamp = TIMESTAMP '2026-06-30');
 → 到期后自动删除整个表

 (c) 时间旅行恢复:
 误删数据后可以通过时间旅行恢复（7 天内）:
 SELECT * FROM myproject.mydataset.users
 FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR);

## 6. 对比与引擎开发者启示

BigQuery DELETE 的设计:
(1) COW 机制 → DELETE 成本与分区大小成正比
(2) DML 配额 → 不适合高频 DELETE
(3) TRUNCATE → 元数据操作，不受配额限制
(4) 分区过期 → 最推荐的数据清理方式
(5) 时间旅行 → 误删保护（7 天窗口）

对引擎开发者的启示:
云数仓应该将数据生命周期管理内置到引擎中:
分区过期、表过期比手动 DELETE 更高效、更可靠。
时间旅行（快照保留）是删除安全的重要保障。
ClickHouse 的 TTL 和 BigQuery 的 partition_expiration 是同一思路，
只是实现层不同（存储引擎 vs 元数据服务）。

