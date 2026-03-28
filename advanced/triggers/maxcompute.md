# MaxCompute (ODPS): 触发器

> 参考资料:
> - [1] MaxCompute SQL Overview
>   https://help.aliyun.com/zh/maxcompute/user-guide/sql-overview
> - [2] DataWorks 调度
>   https://help.aliyun.com/zh/dataworks/user-guide/overview-of-scheduling


## 1. MaxCompute 不支持触发器 —— 设计决策


 为什么批处理引擎不需要触发器?
   触发器的核心价值: 行级事件驱动（BEFORE/AFTER INSERT/UPDATE/DELETE）
   MaxCompute 的操作粒度: 分区级/表级（不是行级）
     INSERT OVERWRITE: 替换整个分区（不是逐行 INSERT）
     每次 INSERT 是一个分布式作业（秒级延迟启动）
     在每行上触发逻辑 → 每行启动一个作业 → 荒谬

   对比:
     MySQL:      BEFORE/AFTER INSERT/UPDATE/DELETE 触发器
     PostgreSQL: BEFORE/AFTER + INSTEAD OF + 行级/语句级触发器
     Oracle:     最丰富（COMPOUND 触发器、FOLLOWS/PRECEDES 排序）
     BigQuery:   不支持（同为批处理引擎）
     Snowflake:  不支持（但有 STREAMS + TASKS 替代）
     Hive:       不支持

## 2. 替代方案 1: DataWorks 调度（最主要的方案）


 DataWorks 是 MaxCompute 的调度平台
 通过 DAG 依赖关系实现"当上游完成时触发下游"

 示例调度任务:
 任务 A: 每天凌晨处理前一天订单
 INSERT OVERWRITE TABLE daily_summary PARTITION (dt = '${bizdate}')
 SELECT user_id, COUNT(*) AS cnt, SUM(amount) AS total
 FROM orders WHERE dt = '${bizdate}'
 GROUP BY user_id;

 任务 B: 依赖任务 A 完成后执行
 INSERT OVERWRITE TABLE monthly_summary PARTITION (month = '${month}')
 SELECT user_id, SUM(total) AS monthly_total
 FROM daily_summary WHERE dt LIKE '${month}%'
 GROUP BY user_id;

 DataWorks 调度 vs 触发器:
   触发器: 行级事件驱动，同步执行
   调度:   任务级事件驱动，异步执行
   调度更适合批处理: 粒度匹配（任务→任务，而非行→行）

## 3. 替代方案 2: 分区事件监听


 通过事件驱动模型，监听分区提交事件
 配置方式: DataWorks 中设置事件触发器
   事件类型: PARTITION_COMMIT
   触发条件: 指定表的分区提交
   动作: 启动下游任务

 这是最接近"触发器"语义的替代方案:
   当 orders 表有新分区写入 → 自动触发 daily_summary 计算

## 4. 替代方案 3: 数据质量监控


 DataWorks 数据质量模块可以在数据变更后自动检查
 类似 BEFORE INSERT 触发器的验证功能

 规则示例:
   表行数波动不超过 20%
   关键列空值率不超过 1%
   唯一性检查（重复记录数 = 0）
   值域检查（amount > 0 的比例 > 99%）

 与触发器的对比:
   触发器: 逐行验证，阻止不合规数据写入
   质量监控: 写入后批量验证，发现不合规数据后告警
   批处理场景下后者更合理: 先写入，后验证，不合规则回退

## 5. 替代方案 4: ETL 管道中嵌入逻辑


在 INSERT 操作前后添加验证和审计逻辑

验证（类似 BEFORE INSERT 触发器）

```sql
SELECT COUNT(*) AS invalid_count
FROM staging_data WHERE amount < 0;
```

DataWorks 中: 如果 invalid_count > 0，终止后续节点

过滤写入（类似触发器中的数据清洗）

```sql
INSERT OVERWRITE TABLE orders PARTITION (dt = '20240115')
SELECT id, user_id, amount, order_time
FROM staging_data
WHERE amount >= 0;                          -- 过滤无效数据

```

审计记录（类似 AFTER INSERT 触发器）

```sql
INSERT INTO audit_log PARTITION (dt = '20240115')
SELECT 'orders' AS table_name,
       'INSERT' AS operation,
       COUNT(*) AS row_count,
       GETDATE() AS operation_time
FROM orders WHERE dt = '20240115';

```

## 6. 替代方案 5: 物化视图


物化视图可以自动维护汇总数据（类似 AFTER INSERT 触发器更新汇总表）

```sql
CREATE MATERIALIZED VIEW mv_order_summary
LIFECYCLE 365
AS
SELECT user_id, COUNT(*) AS cnt, SUM(amount) AS total
FROM orders
GROUP BY user_id;

```

REBUILD 刷新:

```sql
ALTER MATERIALIZED VIEW mv_order_summary REBUILD;

```

## 7. 替代方案 6: 实时处理（Flink）


 对需要实时触发器效果的场景:
   使用 Flink on MaxCompute 或 阿里云实时计算 Flink 版
   通过 CDC（Change Data Capture）捕获数据变更
   实时处理后写回 MaxCompute 或 Hologres

 架构:
   数据源 → Flink（实时处理/过滤/聚合）→ MaxCompute（存储/分析）
   这是"流批一体"架构的标准模式

## 8. 横向对比: 触发器替代方案


 数据到达触发:
MaxCompute: DataWorks 事件监听      | Snowflake: STREAMS + TASKS
BigQuery:   不支持（Pub/Sub 外部）  | Hive: 不支持

 定时触发:
MaxCompute: DataWorks cron 调度     | Snowflake: TASKS（cron 支持）
BigQuery:   Scheduled Queries       | Hive: Oozie/Airflow

 实时触发:
MaxCompute: Flink CDC               | Snowflake: Snowpipe
BigQuery:   Dataflow                | Databricks: Spark Streaming

## 9. 对引擎开发者的启示


### 1. 批处理引擎不需要行级触发器 — 分区级/任务级事件驱动更合理

### 2. Snowflake 的 STREAMS + TASKS 是优雅的替代: 变更捕获 + 定时任务

### 3. 数据质量监控（写入后验证）比触发器验证（写入时验证）更适合批处理

### 4. 物化视图的自动维护是聚合触发器的最佳替代

### 5. 流批一体（Flink + MaxCompute）处理实时触发需求

### 6. DataWorks 类调度平台是批处理引擎的"触发器基础设施"

