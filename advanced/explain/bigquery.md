# BigQuery: 执行计划与查询分析

> 参考资料:
> - [1] Google Cloud - Understanding query execution
>   https://cloud.google.com/bigquery/docs/query-plan-explanation
> - [2] Google Cloud - INFORMATION_SCHEMA.JOBS
>   https://cloud.google.com/bigquery/docs/information-schema-jobs


 BigQuery 没有 EXPLAIN 语句
 执行计划在查询完成后通过 Web UI 或 API 获取

## Web UI 查看执行计划


1. 在 BigQuery Console 中执行查询

2. 点击 "Execution details" 选项卡

3. 查看执行阶段图


 执行计划显示：
 - 阶段（Stage）及其依赖关系
 - 每个阶段的步骤（读取、计算、写入）
 - 数据 Shuffle（重新分布）
 - Slot 使用情况
 - 输入/输出行数和大小

## 通过 INFORMATION_SCHEMA 查看作业信息


查看最近的查询作业

```sql
SELECT
    job_id,
    creation_time,
    total_bytes_processed,
    total_slot_ms,
    query
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_USER
WHERE job_type = 'QUERY'
ORDER BY creation_time DESC
LIMIT 10;

```

查看查询阶段详情

```sql
SELECT
    job_id,
    creation_time,
    total_bytes_processed / 1024 / 1024 AS mb_processed,
    total_slot_ms / 1000 AS slot_seconds,
    total_bytes_billed / 1024 / 1024 AS mb_billed
FROM `region-us`.INFORMATION_SCHEMA.JOBS
WHERE job_type = 'QUERY'
  AND state = 'DONE'
ORDER BY total_bytes_processed DESC
LIMIT 10;

```

## 查询执行计划字段说明


 每个阶段包含：
 name:              阶段名（S00, S01, ...）
 status:            状态（COMPLETE, RUNNING）
 inputStages:       依赖的上游阶段
 startMs / endMs:   开始/结束时间
 slotMs:            消耗的 Slot 毫秒数
 recordsRead:       读取的记录数
 recordsWritten:    写入的记录数
 shuffleOutputBytes: Shuffle 输出字节数

 步骤类型：
 READ     从表或上游阶段读取
 COMPUTE  计算（过滤、表达式求值）
 AGGREGATE 聚合
 WRITE    写入结果或 Shuffle
 JOIN     连接操作

## 干运行（Dry Run，估算成本）


 bq CLI
 bq query --dry_run --use_legacy_sql=false 'SELECT * FROM dataset.users WHERE age > 25'

 API 中设置 dryRun=true
 返回 totalBytesProcessed（估算扫描字节数）

 在 Web UI：查询编辑器右上角显示扫描量估算

## 查询性能优化分析


查看查询的详细统计

```sql
SELECT
    job_id,
    query,
    total_bytes_processed,
    total_slot_ms,
    cache_hit,
    TIMESTAMP_DIFF(end_time, start_time, MILLISECOND) AS duration_ms
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE job_type = 'QUERY'
  AND creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
ORDER BY total_slot_ms DESC
LIMIT 10;

```

分析 Slot 使用时间线

```sql
SELECT
    period_start,
    period_slot_ms,
    job_id
FROM `region-us`.INFORMATION_SCHEMA.JOBS_TIMELINE_BY_PROJECT
WHERE job_type = 'QUERY'
  AND creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
ORDER BY period_start;

```

## 关键优化指标


1. total_bytes_processed: 扫描的数据量（直接影响费用）

    优化：分区裁剪、列裁剪、聚簇表

2. total_slot_ms: Slot 使用量

    优化：减少 Shuffle、避免数据倾斜

3. cache_hit: 是否命中缓存

    24 小时内相同查询可命中缓存

4. shuffle_output_bytes: 各阶段间数据传输量

优化：提前过滤、减少 JOIN 数据量

关键优化策略：
使用分区表减少扫描量

```sql
SELECT * FROM `project.dataset.orders`
WHERE DATE(order_date) = '2024-01-01';  -- 分区裁剪

```

只选择需要的列

```sql
SELECT user_id, amount FROM `project.dataset.orders`;  -- 列式存储优势

```

避免 SELECT *（扫描所有列）

注意：BigQuery 没有 EXPLAIN 语句
注意：执行计划在查询完成后通过 UI / API 查看
注意：Dry Run 可以在不执行的情况下估算扫描量和费用
注意：INFORMATION_SCHEMA.JOBS 提供历史查询性能数据
注意：BigQuery 按扫描数据量计费，优化计划的核心是减少扫描量
注意：缓存命中的查询不收费（24 小时内相同查询）

