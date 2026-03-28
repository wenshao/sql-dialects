# MaxCompute (ODPS): 执行计划与查询分析

> 参考资料:
> - [1] MaxCompute Documentation - EXPLAIN
>   https://help.aliyun.com/zh/maxcompute/user-guide/explain
> - [2] MaxCompute 性能优化
>   https://help.aliyun.com/zh/maxcompute/user-guide/sql-optimization


## 1. EXPLAIN —— 查看执行计划


```sql
EXPLAIN SELECT * FROM users WHERE age > 25;

```

 输出包含:
   Job DAG: 作业的执行阶段和依赖关系
   每个阶段的操作符: TableScan, Filter, Project, Join, Aggregate 等
   数据流向: Map → Reduce → Output

 设计分析: MaxCompute EXPLAIN 展示的是伏羲 DAG
   不同于 OLTP 引擎的"一棵树":
     MySQL EXPLAIN: 一行一个表的访问计划
     PostgreSQL EXPLAIN: 嵌套的算子树
   MaxCompute EXPLAIN: 多阶段 DAG（Directed Acyclic Graph）
     阶段 M1 (Map): 扫描 users 表 → 过滤 age > 25
     阶段 R1 (Reduce): 输出结果
     每个阶段有多个 Instance（并行执行单元）

## 2. COST SQL —— 估算资源消耗（不执行）


```sql
COST SQL SELECT * FROM users WHERE age > 25;

```

 输出:
   Input: xxx bytes（预计读取数据量）
   Output: xxx bytes（预计输出数据量）
   Complexity: xxx（计算复杂度）

 COST SQL 的实际用途:
   按量付费模式: 提交前估算费用（按扫描量计费）
   分区优化验证: 确认分区裁剪是否生效（Input 应大幅减少）

 对比:
   BigQuery:   DRY RUN（--dry_run 标志，返回预计扫描字节数）
   Snowflake:  无等价功能（按 Warehouse 时间计费，不按扫描量）
   PostgreSQL: EXPLAIN（不执行，但不显示预计数据量）

## 3. Logview —— 作业执行日志（最重要的诊断工具）


 提交 SQL 后，MaxCompute 返回 Logview URL
 通过 Logview 可以查看:
1. 作业 DAG: 各阶段依赖关系的可视化

2. 每个阶段的 Instance 数量（并行度）

3. 数据读写量（每个 Instance 读了多少数据）

4. 执行时间（每个 Instance 的 wall time）

5. 资源使用: CPU 时间、内存峰值

6. 数据倾斜检测: 各 Instance 的数据量差异


 设计分析: Logview 的架构
   每个 SQL 作业 = 一个伏羲 Job
   每个 Job = 多个 Stage（Map/Reduce/Join 阶段）
   每个 Stage = 多个 Instance（并行执行单元）
   Logview 提供每个层级的监控指标

## 4. INFORMATION_SCHEMA —— 历史作业和元数据查询


查看历史作业

```sql
SELECT task_name, task_type, status, create_time, end_time,
       input_bytes, output_bytes
FROM INFORMATION_SCHEMA.TASKS_HISTORY
WHERE task_type = 'SQL'
ORDER BY create_time DESC
LIMIT 10;

```

查看表的大小

```sql
SELECT table_name, data_length, table_rows
FROM INFORMATION_SCHEMA.TABLES
WHERE table_schema = 'default';

```

查看正在运行的作业

```sql
SHOW P;                                     -- 显示运行中和排队的作业

```

## 5. 性能优化要点（基于执行计划分析）


### 5.1 分区裁剪（最重要的优化）

好: WHERE 条件中使用分区列

```sql
SELECT * FROM orders WHERE dt = '20240115';

```

坏: 分区列被函数包裹（裁剪失效）
SELECT * FROM orders WHERE SUBSTR(dt, 1, 6) = '202401';  -- 全分区扫描!

验证分区裁剪:

```sql
COST SQL SELECT * FROM orders WHERE dt = '20240115';
```

 Input 应该只有一个分区的数据量

### 5.2 列裁剪（列式存储的天然优势）

好: 只选择需要的列

```sql
SELECT user_id, amount FROM orders;         -- 只读 2 列

```

 坏: SELECT *
 SELECT * FROM orders;                    -- 读取所有列

### 5.3 MAPJOIN（小表广播）

```sql
SELECT /*+ MAPJOIN(u) */ u.username, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;

```

### 5.4 数据倾斜处理

 现象: Logview 显示某些 Instance 处理数据量远大于其他
 原因: 某个 JOIN key 的数据量远大于平均值（热点 key）
 解决:
   方案 1: SKEWJOIN hint
   方案 2: 拆分热点 key 单独处理
   方案 3: 随机前缀打散（对聚合场景）

### 5.5 小文件合并

```sql
ALTER TABLE orders PARTITION (dt = '20240115') MERGE SMALLFILES;

```

## 6. 优化器的三层架构


 RBO（Rule-Based Optimization）: 基于规则的优化
   分区裁剪、列裁剪、谓词下推、常量折叠
   不依赖统计信息，总是应用

 CBO（Cost-Based Optimization）: 基于代价的优化
   JOIN 顺序选择、JOIN 策略选择（Broadcast vs Shuffle vs Sort-Merge）
   基于表的行数、大小、列基数等统计信息
   需要 ANALYZE TABLE 更新统计信息

 HBO（History-Based Optimization）: 基于历史的优化
   利用历史执行的 runtime statistics 优化后续查询
   对 ETL 场景特别有效（同一查询反复执行）
   这是 MaxCompute 超越传统 CBO 的创新

 对引擎开发者: HBO 的价值
   CBO 的统计信息可能过时（表数据变化但统计没更新）
   HBO 利用上一次执行的实际数据分布优化下一次执行
   在固定 ETL 管道中效果显著

## 7. 横向对比: 执行计划分析


 EXPLAIN 输出:
   MaxCompute: DAG（多阶段有向无环图）
   PostgreSQL: 嵌套算子树 + cost/rows/width 估计
   MySQL:      表格（一行一个表）
   BigQuery:   查询计划 + 各阶段统计
   Snowflake:  Query Profile（可视化 DAG）

 运行时分析:
   MaxCompute: Logview（事后分析）
   PostgreSQL: EXPLAIN ANALYZE（实际执行 + 统计）
   MySQL:      EXPLAIN ANALYZE（8.0.18+）
   BigQuery:   Query Execution Graph
   Snowflake:  Query Profile（实时+事后）

 费用预估:
   MaxCompute: COST SQL（扫描字节数）
   BigQuery:   DRY RUN（扫描字节数）
   其他引擎:   无等价功能（不按扫描量计费）

## 8. 对引擎开发者的启示


1. EXPLAIN 应展示分区裁剪效果（用户最关心的优化）

2. 费用预估（COST SQL/DRY RUN）是按量计费引擎的必备功能

3. HBO 在反复执行的 ETL 场景中效果显著 — 值得投资

4. 运行时统计（Logview/Query Profile）比静态 EXPLAIN 更有价值

5. 数据倾斜检测应内置到执行计划分析中（自动告警）

6. 三层优化器（RBO + CBO + HBO）是查询优化的最先进架构

