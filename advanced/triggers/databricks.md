# Databricks SQL: 触发器

> 参考资料:
> - [Databricks SQL Language Reference](https://docs.databricks.com/en/sql/language-manual/index.html)
> - [Databricks SQL - Built-in Functions](https://docs.databricks.com/en/sql/language-manual/sql-ref-functions-builtin.html)
> - [Delta Lake Documentation](https://docs.delta.io/latest/index.html)


Databricks 不支持传统触发器
使用 Delta Lake 特性和替代方案实现类似功能

## 替代方案一：CHECK 约束（BEFORE INSERT 验证）


使用 CHECK 约束在写入时验证数据
```sql
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age > 0 AND age < 200);
ALTER TABLE users ADD CONSTRAINT chk_email CHECK (email LIKE '%@%.%');
```


违反约束的写入会失败（类似 BEFORE INSERT 触发器的验证功能）

## 替代方案二：Change Data Feed（CDC）


启用变更数据捕获
```sql
ALTER TABLE users SET TBLPROPERTIES ('delta.enableChangeDataFeed' = 'true');
```


查看变更记录（类似 AFTER 触发器的审计功能）
```sql
SELECT * FROM table_changes('users', 1)
WHERE _change_type IN ('insert', 'update_postimage', 'delete');
```


变更类型：
insert: 新插入的行
update_preimage: 更新前的行
update_postimage: 更新后的行
delete: 删除的行

使用 CDF 构建审计日志
```sql
CREATE OR REPLACE TABLE audit_log AS
SELECT
    'users' AS table_name,
    _change_type AS action,
    id,
    username,
    _commit_version AS version,
    _commit_timestamp AS change_time
FROM table_changes('users', 1);
```


## 替代方案三：Delta Live Tables（DLT）


DLT 提供声明式的数据质量规则（类似触发器的验证功能）

在 DLT Pipeline 中（Python 代码）：
@dlt.table
@dlt.expect_or_drop("valid_age", "age > 0 AND age < 200")
@dlt.expect_or_fail("has_email", "email IS NOT NULL")
def cleaned_users():
return spark.read.table("raw_users")

DLT 数据质量规则：
@dlt.expect: 记录警告但保留行
@dlt.expect_or_drop: 丢弃不满足条件的行
@dlt.expect_or_fail: 不满足条件时整个管道失败

## 替代方案四：Structured Streaming + 触发逻辑


使用 Structured Streaming 监听 Delta 表变更
在 PySpark Notebook 中：
(spark.readStream
.format("delta")
.option("readChangeFeed", "true")
.table("users")
.writeStream
.foreachBatch(process_changes)  # 自定义处理逻辑
.start())

## 替代方案五：GENERATED ALWAYS AS（计算列）


计算列可以替代某些触发器场景（自动计算）
```sql
CREATE TABLE orders (
    quantity   INT,
    unit_price DECIMAL(10, 2),
    total      DECIMAL(10, 2) GENERATED ALWAYS AS (quantity * unit_price),
    order_year INT GENERATED ALWAYS AS (YEAR(order_date)),
    order_date DATE
);
-- total 和 order_year 自动计算，无需触发器
```


## 替代方案六：Workflows 作业编排


使用 Databricks Workflows 在任务之间添加后处理逻辑：
Task 1: 加载数据到暂存表
Task 2: 验证数据质量
Task 3: 合并到目标表（MERGE INTO）
Task 4: 发送通知（通过 webhook 或邮件）

## Time Travel 替代审计触发器


查看表的变更历史
```sql
DESCRIBE HISTORY users;
```


查看特定版本的数据
```sql
SELECT * FROM users VERSION AS OF 5;
SELECT * FROM users TIMESTAMP AS OF '2024-01-15 10:00:00';
```


比较两个版本之间的差异
```sql
SELECT 'new' AS status, n.* FROM users n
LEFT ANTI JOIN users VERSION AS OF 5 o ON n.id = o.id
UNION ALL
SELECT 'deleted' AS status, o.* FROM users VERSION AS OF 5 o
LEFT ANTI JOIN users n ON o.id = n.id;
```


注意：Databricks 不支持传统触发器（BEFORE / AFTER / INSTEAD OF）
注意：CHECK 约束可以替代 BEFORE INSERT 的验证功能
注意：Change Data Feed 是最接近 AFTER 触发器的功能
注意：DLT 提供声明式数据质量规则
注意：GENERATED ALWAYS AS 替代计算列触发器
注意：Time Travel 提供完整的变更审计能力
