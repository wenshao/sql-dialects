# Flink SQL: 执行计划

> 参考资料:
> - [Flink Documentation - EXPLAIN](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/explain/)
> - [Flink Documentation - Performance Tuning](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/tuning/)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

## EXPLAIN 基本用法


```sql
EXPLAIN SELECT * FROM users WHERE age > 25;

```

输出包含：
## Abstract Syntax Tree（AST）

## Optimized Physical Plan

## Optimized Execution Plan


## EXPLAIN 详细选项（1.14+）


估算成本
```sql
EXPLAIN ESTIMATED_COST SELECT * FROM users WHERE age > 25;

```

变更日志模式
```sql
EXPLAIN CHANGELOG_MODE SELECT * FROM users WHERE age > 25;

```

JSON 输出格式（1.16+）
```sql
EXPLAIN JSON_EXECUTION_PLAN SELECT * FROM users WHERE age > 25;

```

所有详细信息
```sql
EXPLAIN ESTIMATED_COST, CHANGELOG_MODE, JSON_EXECUTION_PLAN
SELECT * FROM users WHERE age > 25;

```

## 执行计划关键操作


TableSourceScan     表源扫描
Calc                计算（过滤 + 投影）
Join                连接
HashJoin            哈希连接
NestedLoopJoin      嵌套循环连接
GroupAggregate       分组聚合
WindowAggregate     窗口聚合
Sort                排序
Rank                排名
Exchange            数据交换
Sink                输出目标
LookupJoin          维表查找连接
Deduplicate         去重

变更日志模式：
+I  INSERT
-U  UPDATE 前的旧值
+U  UPDATE 后的新值
-D  DELETE

## Flink Web UI


Flink Web UI（默认端口 8081）提供：
## 作业 DAG 图形化展示

## 各算子的吞吐量和延迟

## Checkpoint 信息

## 反压（Backpressure）状态

## 水位线（Watermark）


## 性能指标（Metrics）


通过 REST API 查看指标：
GET /jobs/{job-id}/vertices/{vertex-id}/metrics

关键指标：
numRecordsIn / numRecordsOut    输入/输出记录数
numRecordsInPerSecond           每秒输入记录数
currentInputWatermark           当前水位线
busyTimeMsPerSecond             忙碌时间（反压指标）

## 查询 Hint


连接 Hint（1.15+）
```sql
SELECT /*+ BROADCAST(u) */ u.*, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;

SELECT /*+ SHUFFLE_HASH(o) */ u.*, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;

SELECT /*+ NEST_LOOP(u) */ u.*, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;

```

状态保留时间
```sql
SET 'table.exec.state.ttl' = '1h';

```

## Mini-batch 优化


启用 Mini-batch（减少状态访问）
```sql
SET 'table.exec.mini-batch.enabled' = 'true';
SET 'table.exec.mini-batch.allow-latency' = '5s';
SET 'table.exec.mini-batch.size' = '5000';

```

**注意:** Flink EXPLAIN 显示流式执行计划
**注意:** 变更日志模式（Changelog Mode）是 Flink 流处理的关键概念
**注意:** Web UI 的反压（Backpressure）指示性能瓶颈
**注意:** 1.14+ 版本支持 ESTIMATED_COST 和 CHANGELOG_MODE 选项
**注意:** Flink 的执行计划面向连续流处理，与批处理引擎不同
**注意:** Mini-batch 优化可以显著减少状态操作开销
