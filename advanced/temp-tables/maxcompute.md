# MaxCompute (ODPS): 临时表

> 参考资料:
> - [1] MaxCompute Documentation
>   https://help.aliyun.com/zh/maxcompute/user-guide/table-operations


## 1. MaxCompute 的临时表方案


 MaxCompute 早期不支持 CREATE TEMPORARY TABLE
 但提供了多种替代方案，每种适合不同场景

## 2. 方案 1: LIFECYCLE 短表（最常用）


LIFECYCLE 1 = 1 天后自动删除（等效于临时表）

```sql
CREATE TABLE temp_results LIFECYCLE 1 AS
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

```

使用临时表

```sql
SELECT u.username, t.total
FROM users u JOIN temp_results t ON u.id = t.user_id;

```

手动删除（如果不想等自动回收）

```sql
DROP TABLE IF EXISTS temp_results;

```

 设计分析: LIFECYCLE 短表 vs TEMPORARY TABLE
   LIFECYCLE 短表:
     优点: 其他会话也可以访问（可用于跨作业共享中间结果）
     优点: 数据持久化（作业失败后中间结果仍在）
     缺点: 需要唯一表名（并发作业可能冲突）
     缺点: 不自动清理（需等 LIFECYCLE 到期）
   TEMPORARY TABLE:
     优点: 会话隔离（无命名冲突）
     优点: 会话结束自动删除
     缺点: 其他会话看不到
     缺点: 数据不持久化

## 3. 方案 2: CTE（最推荐，无副作用）


```sql
WITH stats AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
)
SELECT u.username, s.total
FROM users u JOIN stats s ON u.id = s.user_id;

```

 CTE 的优势:
   无副作用: 不创建任何表对象
   无命名冲突: 只在查询范围内有效
   无清理: 执行完自动消失

 CTE 的局限:
   不能跨语句引用（每个 SQL 语句内有效）
   多次引用可能被内联（重复计算）

## 4. 方案 3: INSERT OVERWRITE 覆盖中间表


预创建中间表，每次覆盖写入

```sql
CREATE TABLE IF NOT EXISTS staging_results (
    user_id BIGINT,
    total   DECIMAL(10,2)
) LIFECYCLE 7;

INSERT OVERWRITE TABLE staging_results
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

```

使用中间表

```sql
SELECT u.username, s.total
FROM users u JOIN staging_results s ON u.id = s.user_id;

```

 这是 ETL 管道中最常用的模式:
   staging 表是"永久的临时表"
   每次 ETL 用 INSERT OVERWRITE 刷新
   LIFECYCLE 控制过期自动清理

## 5. 方案 4: VOLATILE TABLE（会话级临时表）


 部分版本支持 VOLATILE TABLE（类似传统临时表）
 CREATE VOLATILE TABLE temp_result AS SELECT ...;
 会话结束后自动删除

 注意: VOLATILE TABLE 支持取决于 MaxCompute 版本
 不是所有项目都启用了此功能

## 6. 临时表命名的并发问题


 多个 DataWorks 调度作业并发执行时，LIFECYCLE 短表可能冲突:
   作业 A: CREATE TABLE temp_orders LIFECYCLE 1 AS ...
   作业 B: CREATE TABLE temp_orders LIFECYCLE 1 AS ...
   解决: 在表名中加入唯一标识
     temp_orders_${bizdate}_${task_id}
     DataWorks 调度变量确保唯一性

## 7. 横向对比: 临时表


 会话级临时表:
MaxCompute: VOLATILE TABLE（有限支持）  | PostgreSQL: CREATE TEMP TABLE
MySQL:      CREATE TEMPORARY TABLE      | SQL Server: #temp_table
BigQuery:   CREATE TEMP TABLE           | Snowflake: CREATE TEMP TABLE
Hive:       不支持                      | Oracle: GLOBAL TEMPORARY TABLE

 事务级临时表:
MaxCompute: 不支持                      | PostgreSQL: ON COMMIT DROP
Oracle:     ON COMMIT DELETE ROWS       | SQL Server: 支持

 匿名临时存储:
MaxCompute: CTE                         | 所有引擎均支持 CTE
BigQuery:   TEMP TABLE + Scripting      | Snowflake: 同上

 TTL 表（自动过期）:
MaxCompute: LIFECYCLE（核心特色）       | ClickHouse: TTL
BigQuery:   partition_expiration_days   | Snowflake: 不支持

## 8. 对引擎开发者的启示


### 1. LIFECYCLE 短表是批处理引擎的务实方案 — 比临时表更灵活

### 2. CTE 是最安全的"临时存储"— 无副作用，应优先推荐

### 3. 临时表的命名冲突问题在并发调度环境中很严重 — 需要设计解决方案

### 4. 会话级临时表在批处理引擎中价值有限（每个 SQL 是独立作业）

### 5. ETL 管道中的 staging 表 = "永久的临时表" — 这是数据仓库的标准模式

### 6. LIFECYCLE 自动清理避免了"忘记 DROP TEMP TABLE"的运维问题

