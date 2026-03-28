# Flink SQL: 错误处理

> 参考资料:
> - [Apache Flink Documentation - SQL Reference](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/)
> - [Apache Flink Documentation - Fault Tolerance](https://nightlies.apache.org/flink/flink-docs-stable/docs/ops/state/fault_tolerance/)
> - [Apache Flink Documentation - Restart Strategies](https://nightlies.apache.org/flink/flink-docs-stable/docs/ops/state/task_failure_recovery/)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

## Flink SQL 错误处理概述

Flink SQL 是流处理引擎的 SQL 接口，没有存储过程或 SQL 级异常处理。
Flink 的错误处理有两个层面:
  (a) 流作业容错: 通过 Checkpoint + 重启策略实现自动恢复
  (b) 数据处理错误: 通过 SQL 容错函数 (TRY_CAST 等) 避免
  (c) 应用层: Java/Scala/Python API 的 try/catch

## 应用层错误捕获


Java/Scala 示例: Table API 错误处理
import org.apache.flink.table.api.TableException;
import org.apache.flink.table.api.ValidationException;
try {
    tEnv.executeSql("INSERT INTO output_table SELECT * FROM input_table");
} catch (ValidationException e) {
    // SQL 验证错误 (表不存在、列不匹配等)
    System.out.println("Validation error: " + e.getMessage());
} catch (TableException e) {
    // 运行时 Table API 错误
    System.out.println("Table error: " + e.getMessage());
} catch (Exception e) {
    // 通用异常
    System.out.println("General error: " + e.getMessage());
}

PyFlink 示例:
from pyflink.table import TableException
try:
    t_env.execute_sql("INSERT INTO output SELECT * FROM input")
except TableException as e:
    print(f"Flink Table error: {e}")
except Exception as e:
    print(f"General error: {e}")

## Flink 流作业容错机制 (核心)


Flink 的容错通过 Checkpoint 机制实现 (Chandy-Lamport 算法)
当 Task 失败时，从最近成功的 Checkpoint 恢复

配置 Checkpoint
env.enableCheckpointing(60000);                    -- 每 60s 一次 Checkpoint
env.getCheckpointConfig().setCheckpointingMode(CheckpointingMode.EXACTLY_ONCE);
env.getCheckpointConfig().setMinPauseBetweenCheckpoints(30000);
env.getCheckpointConfig().setCheckpointTimeout(600000);
env.getCheckpointConfig().setMaxConcurrentCheckpoints(1);

SQL 方式配置 Checkpoint (Flink SQL Gateway / SQL Client)
SET 'execution.checkpointing.interval' = '60s';
SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';
SET 'execution.checkpointing.timeout' = '10min';

## 重启策略配置


固定延迟重启策略
```sql
SET 'restart-strategy' = 'fixed-delay';
SET 'restart-strategy.fixed-delay.attempts' = '3';
SET 'restart-strategy.fixed-delay.delay' = '10s';

```

失败率重启策略
```sql
SET 'restart-strategy' = 'failure-rate';
SET 'restart-strategy.failure-rate.max-failures-per-interval' = '3';
SET 'restart-strategy.failure-rate.failure-rate-interval' = '5min';
SET 'restart-strategy.failure-rate.delay' = '10s';

```

无重启策略 (调试用)
```sql
SET 'restart-strategy' = 'no-restart';

```

指数延迟重启策略                                  -- Flink 1.15+
```sql
SET 'restart-strategy' = 'exponential-delay';
SET 'restart-strategy.exponential-delay.initial-backoff' = '1s';
SET 'restart-strategy.exponential-delay.max-backoff' = '60s';

```

## SQL 层面的数据处理容错


TRY_CAST: 转换失败返回 NULL                          -- Flink 1.15+
```sql
SELECT TRY_CAST('abc' AS INT);              -- NULL
SELECT TRY_CAST('123' AS INT);              -- 123

```

使用 COALESCE + TRY_CAST 处理脏数据
```sql
SELECT
    id,
    COALESCE(TRY_CAST(age_str AS INT), -1) AS age,
    COALESCE(TRY_CAST(amount_str AS DECIMAL(10,2)), 0.00) AS amount
FROM raw_stream;

```

使用 IF / CASE WHEN 避免运行时错误
```sql
SELECT
    id,
    CASE
        WHEN denom = 0 THEN NULL
        ELSE numer / denom
    END AS ratio
FROM metrics;

```

使用 IF NOT EXISTS 建表
```sql
CREATE TABLE IF NOT EXISTS output_table (
    id   INT,
    name STRING
) WITH (
    'connector' = 'kafka',
    'topic' = 'output-topic',
    'properties.bootstrap.servers' = 'localhost:9092',
    'format' = 'json'
);

```

## Flink 特有错误场景与处理


场景 1: 反压 (Backpressure) 导致 Checkpoint 超时
错误: Checkpoint expired before completing
解决: 增加 Checkpoint 超时时间，或优化算子性能
  SET 'execution.checkpointing.timeout' = '30min';

场景 2: 数据类型不匹配
错误: Type mismatch: cannot convert STRING to INT
解决: 使用 TRY_CAST 或在 DDL 中使用宽松类型

场景 3: Source/Sink 连接失败
错误: Failed to connect to Kafka broker
解决: 配置 connector 重试参数
  'properties.retries' = '3'
  'properties.retry.backoff.ms' = '1000'

场景 4: 状态后端错误
错误: State backend error / RocksDB error
解决: 检查磁盘空间，调整状态 TTL
  SET 'table.exec.state.ttl' = '1h';

## 诊断: 监控与日志


Flink Web UI: http://jobmanager:8081
  - Overview: 作业运行状态、失败次数
  - Task Managers: 查看 Task 日志 (Stdout / Stderr)
  - Checkpoints: Checkpoint 历史、大小、耗时
  - Backpressure: 反压监控

Flink 日志配置:
  log4j.properties: 调整日志级别
  logger.flink.name = org.apache.flink
  logger.flink.level = INFO

REST API 查询作业异常:
GET http://jobmanager:8081/jobs/:jobid/exceptions

查看当前作业配置
GET http://jobmanager:8081/jobs/:jobid/config

## 版本说明

Flink 1.11:   SQL Client 支持 SET 配置
Flink 1.13:   增强 Checkpoint 监控
Flink 1.15:   TRY_CAST 支持, 指数延迟重启策略
Flink 1.16:   改进错误消息，增强 SQL 诊断
Flink 1.17:   新增 SQL Gateway 错误处理
Flink 1.18+:  增强流式 SQL 容错能力
**注意:** 无 TRY/CATCH, EXCEPTION WHEN, DECLARE HANDLER 语法
**注意:** Checkpoint + 重启策略是 Flink 错误恢复的核心机制
**注意:** 流处理中"错误处理"更偏向容错而非异常捕获
**限制:** 不支持存储过程、触发器
