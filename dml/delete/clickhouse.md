# ClickHouse: DELETE

> 参考资料:
> - [1] ClickHouse SQL Reference - ALTER DELETE
>   https://clickhouse.com/docs/en/sql-reference/statements/alter/delete
> - [2] ClickHouse - Lightweight Delete
>   https://clickhouse.com/docs/en/sql-reference/statements/delete
> - [3] ClickHouse - TTL
>   https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree#table_engine-mergetree-ttl


## 1. 为什么 ClickHouse 的 DELETE 如此特殊


 ClickHouse 的数据存储模型天然不适合删除:
   data part = 不可变的列式文件集合（每列一个文件，经过压缩）
   删除一行 = 修改所有列文件 = 解压 → 删除 → 重压 → 写入新 part

 ClickHouse 提供两种删除机制:
   (a) ALTER TABLE DELETE: 传统 mutation（重写 data part）
   (b) DELETE FROM: 轻量级删除（标记删除，23.3+）
   (c) DROP PARTITION: 直接删除分区目录（最快）
   (d) TTL 自动过期: 后台 merge 时自动删除过期数据

## 2. ALTER TABLE DELETE（传统 mutation）


基本删除

```sql
ALTER TABLE users DELETE WHERE username = 'alice';

```

条件删除

```sql
ALTER TABLE users DELETE WHERE status = 0 AND last_login < '2023-01-01';

```

子查询删除

```sql
ALTER TABLE users DELETE WHERE id IN (SELECT user_id FROM blacklist);

```

WHERE 子句是必须的（不能无条件删除）

异步执行: mutation 立即返回，后台处理
查看进度:

```sql
SELECT mutation_id, command, is_done, parts_to_do
FROM system.mutations WHERE table = 'users' AND is_done = 0;

```

同步等待

```sql
ALTER TABLE users DELETE WHERE status = 0
SETTINGS mutations_sync = 1;

```

取消 mutation

```sql
KILL MUTATION WHERE mutation_id = 'xxx';

```

## 3. 轻量级 DELETE（23.3+，推荐）


标准 SQL 语法（不是 ALTER TABLE）

```sql
DELETE FROM users WHERE username = 'alice';

```

 工作原理:
   (1) 不重写 data part（不解压/重压缩）
   (2) 在 data part 中创建一个 _row_exists 掩码文件
   (3) 查询时自动过滤 _row_exists = 0 的行
   (4) 后台 merge 时物理删除被标记的行

 性能对比:
   ALTER TABLE DELETE: 重写 data part（秒级到分钟级）
   DELETE FROM:        写入掩码文件（毫秒级）

 限制:
   仅 MergeTree 系列引擎
   23.3-23.7 是实验性（SET allow_experimental_lightweight_delete = 1）
   23.8+ 默认可用

## 4. DROP PARTITION: 最高效的"删除"


直接删除整个分区目录（文件系统 rm 操作）

```sql
ALTER TABLE events DROP PARTITION '2024-01-15';

```

 性能: 与数据量无关，毫秒级完成
 原因: 分区是独立的目录，DROP = 删除目录

 这是 ClickHouse 中最常用的数据清理方式:
 按时间分区 → 定期 DROP 过期分区
 比 DELETE WHERE event_date < '2024-01-01' 快几个数量级

## 5. TTL 自动过期: 零运维的数据删除


 表级 TTL: 到期后自动删除整行
 CREATE TABLE logs (
     timestamp DateTime,
     message String
 ) ENGINE = MergeTree()
 ORDER BY timestamp
 TTL timestamp + INTERVAL 90 DAY DELETE;

 后台 merge 时自动删除过期数据，不需要手动操作。
 对比:
   MySQL:      需要定时任务 + DELETE
   PostgreSQL: 需要 pg_cron + DELETE
   BigQuery:   partition_expiration_days（类似但只能按分区）

## 6. TRUNCATE: 清空整个表


```sql
TRUNCATE TABLE users;
```

 立即删除所有 data part，重新开始
 比 ALTER TABLE DELETE WHERE 1=1 快得多

## 7. 对比与引擎开发者启示

ClickHouse DELETE 的 4 个层级（从慢到快）:
ALTER TABLE DELETE → 重写 part（最慢，最灵活）
DELETE FROM        → 标记删除（快，23.3+）
DROP PARTITION     → 删除目录（极快，但只能按分区）
TTL               → 自动过期（零运维）

对引擎开发者的启示:
列存引擎应该提供多种删除粒度:
- 行级删除（mutation 或标记删除）
- 分区级删除（目录操作）
- 自动过期（TTL，最重要的分析场景需求）
轻量级删除（标记 + 延迟物理删除）是列存引擎的最佳折中:
写入掩码 O(1) → 查询时过滤 O(n) → merge 时物理删除。

