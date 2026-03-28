# Hive: 触发器 (无原生支持)

> 参考资料:
> - [1] Apache Hive Language Manual
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual
> - [2] Apache Hive - Hive Hooks
>   https://cwiki.apache.org/confluence/display/Hive/HiveHooks


## 1. Hive 不支持触发器

 这是架构层面的设计决策，不是遗漏:

 为什么 Hive 不需要触发器?
### 1. 批处理模型: 触发器假设逐行写入的执行模型（INSERT 一行 → 触发一次）

    Hive 的写入单位是分区级别的（INSERT OVERWRITE），不是逐行的
### 2. 性能代价: TB 级数据的 INSERT OVERWRITE 触发行级触发器会导致性能灾难

### 3. 分布式执行: 多个 Mapper/Reducer 并行写入，触发器的执行顺序和一致性无法保证

### 4. 外部编排: ETL 管道由 Airflow/Oozie 编排，"触发"逻辑在调度层实现


## 2. 替代方案: 调度工具编排 (最常用)

 Airflow DAG 实现"触发器"效果:
 task_validate >> task_load >> task_audit >> task_notify

 等价于:
 BEFORE INSERT 触发器 → task_validate (数据验证)
 INSERT 操作          → task_load (数据加载)
 AFTER INSERT 触发器  → task_audit (审计记录)
 后续通知             → task_notify (告警/邮件)

## 3. 替代方案: ETL 管道中的数据验证

步骤 1: BEFORE INSERT 等价 — 数据质量检查

```sql
SELECT COUNT(*) AS invalid_count
FROM staging_orders
WHERE amount < 0 OR user_id IS NULL;

```

步骤 2: INSERT 操作 — 只加载有效数据

```sql
INSERT OVERWRITE TABLE orders PARTITION (dt='2024-01-15')
SELECT id, user_id, amount, order_time
FROM staging_orders
WHERE amount >= 0 AND user_id IS NOT NULL;

```

步骤 3: AFTER INSERT 等价 — 记录被拒绝的数据

```sql
INSERT OVERWRITE TABLE rejected_orders PARTITION (dt='2024-01-15')
SELECT *, 'validation_failed' AS reason
FROM staging_orders
WHERE amount < 0 OR user_id IS NULL;

```

步骤 4: 审计记录

```sql
INSERT INTO audit_log
SELECT 'orders', 'INSERT', current_timestamp(), current_user();

```

## 4. 替代方案: 物化视图 (Hive 3.0+)

物化视图可以自动维护聚合结果，类似 AFTER INSERT 触发器的聚合更新功能

```sql
CREATE MATERIALIZED VIEW mv_daily_orders AS
SELECT dt, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders GROUP BY dt;

```

重建（源数据变更后）

```sql
ALTER MATERIALIZED VIEW mv_daily_orders REBUILD;

```

## 5. 替代方案: Hive Hooks (Java 插件)

 Hive 提供 Hook 机制，在查询执行的不同阶段插入自定义 Java 逻辑

 Hook 类型:
 hive.exec.pre.hooks:     查询执行前（类似 BEFORE 触发器）
 hive.exec.post.hooks:    查询执行后（类似 AFTER 触发器）
 hive.exec.failure.hooks: 查询失败时（类似 EXCEPTION 处理）

 配置示例 (hive-site.xml):
 <property>
   <name>hive.exec.post.hooks</name>
   <value>com.example.AuditHook</value>
 </property>

 AuditHook 可以:
### 1. 记录谁执行了什么查询

### 2. 记录查询影响了哪些表/分区

### 3. 发送告警通知

### 4. 触发下游数据管道


 设计分析: Hooks vs Triggers
 Hooks 的粒度是查询级别（每个 HiveQL 语句触发一次），不是行级别。
 这与 Hive 的执行模型一致: 一个 SQL = 一个作业 = 一次 Hook 调用。
 RDBMS 触发器是行级别的（每个受影响的行触发一次），这在 Hive 中不可行。

## 6. 替代方案: Metastore 事件监听

 Hive Metastore 在 DDL/DML 操作后发出事件通知:
 CREATE_TABLE, DROP_TABLE, ALTER_TABLE
 ADD_PARTITION, DROP_PARTITION
 INSERT (在 ACID 表上)

 配置: hive.metastore.event.listeners
 外部系统可以监听这些事件，实现触发器效果
 例如: 新分区创建后自动触发 Spark 作业处理新数据

## 7. 跨引擎对比: 触发器支持

 引擎          触发器支持          替代方案
 MySQL         BEFORE/AFTER ROW    完整触发器
 PostgreSQL    BEFORE/AFTER/INSTEAD 最强大的触发器(事件触发器)
 Oracle        BEFORE/AFTER/COMPOUND 完整触发器+系统事件触发器
 SQL Server    AFTER/INSTEAD OF    完整触发器
 Hive          不支持              Hooks/调度工具/物化视图
 Spark SQL     不支持              Structured Streaming 触发
 BigQuery      不支持              Scheduled Queries/Cloud Functions
 ClickHouse    不支持              物化视图(INSERT触发)
 Flink SQL     不支持              流处理本身就是"触发器"

 ClickHouse 的物化视图模式值得注意:
 INSERT 到源表时，ClickHouse 自动将变换后的数据写入目标表。
 本质上是一个 AFTER INSERT 触发器 + 目标表的组合。

## 8. 对引擎开发者的启示

### 1. 触发器是 OLTP 概念: 逐行处理模型中触发器有意义，

    批处理/分析引擎中触发器没有合理的语义
### 2. 查询级别的 Hook 比行级别的触发器更适合大数据:

    Hive 的 pre/post hooks 设计简单有效，是大数据引擎的最佳实践
### 3. 事件驱动架构替代触发器: Metastore 事件 + 外部监听

    比嵌入式触发器更灵活、更可扩展
### 4. ClickHouse 的物化视图触发是一个有趣的折中:

在批量写入模型中实现了"自动增量计算"，不需要完整的触发器语义

