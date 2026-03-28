# Hive: 临时表 (Temporary Tables, Hive 0.14+)

> 参考资料:
> - [1] Apache Hive Documentation - Temporary Tables
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL#LanguageManualDDL-TemporaryTables
> - [2] Apache Hive Language Manual - DDL
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL


## 1. CREATE TEMPORARY TABLE

```sql
CREATE TEMPORARY TABLE temp_users (
    id       BIGINT,
    username STRING,
    email    STRING
);

```

CTAS 创建临时表（最常用的方式）

```sql
CREATE TEMPORARY TABLE temp_active_users AS
SELECT user_id, SUM(amount) AS total
FROM orders
WHERE dt >= '2024-01-01'
GROUP BY user_id;

```

使用临时表

```sql
INSERT INTO temp_users
SELECT id, username, email FROM users WHERE status = 'active';

SELECT * FROM temp_users;
DROP TABLE IF EXISTS temp_users;

```

## 2. 临时表的设计特点

1. 会话级生命周期: 会话结束时自动删除（无需手动 DROP）

2. 仅当前会话可见: 其他会话无法访问

3. 命名冲突: 临时表名可以与永久表同名，临时表优先

4. 存储位置: HDFS 上的用户临时目录（非表仓库目录）

5. 不注册到 Metastore: 不影响其他引擎看到的元数据


 设计分析: 为什么临时表在 Hive 中使用频率较低?
1. CTAS + 永久表: 大多数 ETL 场景使用 CTAS 创建 staging 表，处理后 DROP

2. CTE (WITH): 对于中间计算，CTE 更简洁且不需要物理持久化

3. INSERT OVERWRITE: 覆盖写入模式下，中间表可以反复使用

4. 会话模型: Hive 的"会话"概念不如 RDBMS 明确（一个 Beeline 连接 = 一个会话）


## 3. 临时表的限制

1. 不支持分区: 临时表不能使用 PARTITIONED BY

2. 不支持索引: 临时表不能创建索引（虽然 3.0+ 索引也废弃了）

3. 不支持 ACID: 临时表不是事务表

4. 不持久化: 会话结束数据丢失（设计如此）

5. 不可被其他会话引用: 无法共享


## 4. 替代方案: CTE (WITH 子句)

```sql
WITH user_stats AS (
    SELECT user_id, SUM(amount) AS total
    FROM orders GROUP BY user_id
),
active_users AS (
    SELECT id, username FROM users WHERE status = 'active'
)
SELECT a.username, s.total
FROM active_users a
JOIN user_stats s ON a.id = s.user_id;

```

 CTE vs 临时表的选择:
 CTE:    适合单查询中的中间计算，不物理化（优化器可能展开为子查询）
 临时表: 适合跨多个查询复用中间结果（物理持久化到 HDFS）

## 5. 替代方案: Staging 表

在 ETL 中使用永久表作为中间存储（最常见的模式）

```sql
CREATE TABLE staging_orders STORED AS ORC AS
SELECT * FROM raw_orders WHERE dt = '2024-01-15';

```

处理 staging 数据

```sql
INSERT OVERWRITE TABLE clean_orders PARTITION (dt='2024-01-15')
SELECT id, user_id, amount FROM staging_orders
WHERE amount > 0;

```

清理 staging 表

```sql
DROP TABLE staging_orders;

```

 Staging 表 vs 临时表:
 Staging 表: 跨会话可见，可以被其他引擎访问，支持分区
 临时表:     会话隔离，自动清理，但功能受限

## 6. 跨引擎对比: 临时表设计

 引擎          临时表类型              生命周期      特殊能力
 MySQL         CREATE TEMPORARY TABLE  连接级        支持索引
 PostgreSQL    CREATE TEMP TABLE       事务/会话级   ON COMMIT 行为
 Oracle        GLOBAL TEMP TABLE       事务/会话级   结构持久数据临时
 SQL Server    #table / ##table        局部/全局     tempdb 存储
 Hive          CREATE TEMPORARY TABLE  会话级        不支持分区
 Spark SQL     createTempView          会话级        DataFrame 注册
 BigQuery      临时表(自动24h过期)     24h/脚本级    无需手动清理
 Trino         不支持                  N/A           使用 CTE/子查询
 Flink SQL     CREATE TEMPORARY TABLE  会话级        用于临时注册源/汇

 Oracle 的 GLOBAL TEMPORARY TABLE 设计独特:
 表结构是永久的（所有会话共享定义），但数据是会话/事务级临时的。
 这避免了每次创建临时表的 DDL 开销。Hive 没有这种设计。

## 7. 对引擎开发者的启示

1. 临时表在大数据引擎中的重要性低于 RDBMS:

    因为批处理工作流有明确的 staging 阶段，不需要会话级临时存储
2. CTE 是更好的中间计算方案: 不需要物理化，优化器可以合并到主查询中

3. Oracle 的 GLOBAL TEMPORARY TABLE 模式值得考虑:

    避免了每次创建临时表的 DDL 开销（对于高频使用的临时计算场景）
4. BigQuery 的 24h 自动过期是云原生的好设计:

用户不需要手动清理，系统自动管理临时数据的生命周期

