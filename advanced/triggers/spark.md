# Spark SQL: 触发器 (Triggers)

> 参考资料:
> - [1] Delta Lake - Change Data Feed
>   https://docs.delta.io/latest/delta-change-data-feed.html
> - [2] Spark Structured Streaming
>   https://spark.apache.org/docs/latest/structured-streaming-programming-guide.html


## 1. 核心设计: Spark SQL 不支持触发器


 Spark SQL 没有 CREATE TRIGGER 语法。
 批处理引擎不适合事件驱动（trigger-on-row-change）模型:
   触发器: 每行变更时同步执行逻辑（适合 OLTP 的行级操作）
   Spark:  每次操作涉及百万/亿行，逐行触发器会导致灾难性性能问题

 对比:
   MySQL:      BEFORE/AFTER + INSERT/UPDATE/DELETE 触发器
   PostgreSQL: 触发器 + 触发器函数（PL/pgSQL），最灵活的实现
   Oracle:     行级/语句级触发器 + INSTEAD OF 触发器 + 复合触发器
   SQL Server: AFTER/INSTEAD OF 触发器 + DDL 触发器 + LOGON 触发器
   Hive:       无触发器
   Flink SQL:  无触发器（通过 Changelog 流处理实现类似效果）
   BigQuery:   无触发器（通过 Pub/Sub + Cloud Functions 实现）
   ClickHouse: 无触发器（通过 Materialized View 实现类似效果）

 对引擎开发者的启示:
   触发器在 OLTP 引擎中是必要的（数据完整性、审计、级联操作）。
   但在 OLAP/批处理引擎中，触发器的 row-by-row 执行模型与批量处理矛盾。
   替代方案: Change Data Feed（CDC）、流处理、ETL 管道中的 pre/post hooks。

## 2. 替代方案一: Delta Lake Change Data Feed (CDF)


 启用 CDF（变更数据捕获）
 ALTER TABLE users SET TBLPROPERTIES (delta.enableChangeDataFeed = true);

 读取变更记录（类似触发器的 :OLD 和 :NEW 伪行）
 SELECT * FROM table_changes('users', 2);
 SELECT * FROM table_changes('users', '2024-01-01', '2024-01-31');

 CDF 输出包含:
   _change_type:  'insert', 'update_preimage', 'update_postimage', 'delete'
   _commit_version: 变更的事务版本号
   _commit_timestamp: 变更时间

 CDF vs 触发器:
   触发器: 同步执行（在 DML 事务中）、逐行处理
   CDF:    异步读取（在 DML 事务之后）、批量处理
   CDF 更适合数据湖场景: 先写入，后异步处理变更

## 3. 替代方案二: Structured Streaming（实时处理）


 最接近触发器的实时处理方案:
 df = spark.readStream.format("delta").table("users")
 df.writeStream \
   .foreachBatch(lambda batch_df, batch_id: process_changes(batch_df)) \
   .trigger(processingTime='10 seconds') \
   .start()

 foreachBatch 中可以实现任意逻辑:
   审计日志: 将变更写入审计表
   数据验证: 检查新数据的质量
   级联更新: 更新相关表的汇总数据
   通知: 发送告警或消息

 Structured Streaming vs 触发器:
   触发器: 同步、事务内、逐行、强一致
   Streaming: 异步（秒级延迟）、批量、最终一致
   对于大数据场景，Streaming 的吞吐量远超触发器

## 4. 替代方案三: Delta Lake CHECK 约束（替代验证触发器）


 传统数据库用 BEFORE INSERT 触发器做数据验证
 Delta Lake 用 CHECK 约束替代:
 ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);
 ALTER TABLE users ADD CONSTRAINT chk_email CHECK (email LIKE '%@%');

 CHECK 约束在写入时自动检查，无需手动编写验证逻辑

## 5. 替代方案四: 视图（替代计算列触发器）


传统数据库用 BEFORE INSERT 触发器计算衍生列
Spark 用视图或 DataFrame 变换替代:

```sql
CREATE OR REPLACE VIEW users_enriched AS
SELECT *,
    CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END AS age_group,
    CURRENT_TIMESTAMP() AS computed_at
FROM users;

```

## 6. 替代方案五: MERGE INTO（替代更新触发器）


传统数据库用 AFTER UPDATE 触发器维护 updated_at 列
Spark 用 MERGE INTO 显式处理:

```sql
MERGE INTO users AS t
USING updates AS s
ON t.id = s.id
WHEN MATCHED THEN
    UPDATE SET
        t.email = s.email,
        t.updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN
    INSERT (id, username, email, created_at, updated_at)
    VALUES (s.id, s.username, s.email, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP());

```

## 7. 替代方案六: ETL 管道 Hooks（应用层）


 PySpark ETL 管道中的 pre/post 处理:
 # Pre-processing (替代 BEFORE INSERT 触发器)
 df = df.filter("age >= 0").withColumn("updated_at", current_timestamp())
 # Write
 df.write.mode("overwrite").saveAsTable("users")
 # Post-processing (替代 AFTER INSERT 触发器)
 audit_df = spark.createDataFrame([("users", "INSERT", datetime.now())])
 audit_df.write.mode("append").saveAsTable("audit_log")

## 8. Databricks Auto Loader（文件到达触发器）


 Auto Loader 监控云存储目录，新文件到达时自动触发处理:
 df = spark.readStream.format("cloudFiles") \
   .option("cloudFiles.format", "json") \
   .load("/data/incoming/")
 df.writeStream.option("checkpointLocation", "/cp/").toTable("processed_data")

## 9. 版本演进

Spark 2.0: Structured Streaming（流式处理替代触发器）
Delta 1.0: Change Data Feed（变更数据捕获）
Delta 2.0: CDF 性能优化
Databricks: Auto Loader（文件到达触发器）、SQL Alerts（监控告警）

限制:
不支持 CREATE TRIGGER / DROP TRIGGER / ALTER TRIGGER
不支持同步、事务内的行级触发逻辑
所有替代方案都是异步或批量的
Structured Streaming 需要长期运行的 Spark 应用（资源成本）
CDF 需要 Delta Lake 表且必须显式启用

