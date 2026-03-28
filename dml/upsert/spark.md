# Spark SQL: UPSERT / MERGE INTO

> 参考资料:
> - [1] Delta Lake - MERGE INTO
>   https://docs.delta.io/latest/delta-update.html#upsert-into-a-table-using-merge
> - [2] Apache Iceberg - MERGE INTO
>   https://iceberg.apache.org/docs/latest/spark-writes/#merge-into
> - [3] SQL:2003 Standard - MERGE Statement


## 1. 核心设计: MERGE INTO 是唯一的 UPSERT 方式


 Spark SQL 没有 INSERT ... ON CONFLICT 或 INSERT ... ON DUPLICATE KEY UPDATE。
 MERGE INTO 是 SQL:2003 标准语法，也是 Spark 唯一支持的 UPSERT 机制。
 需要 Delta Lake 或 Iceberg 表格式。

 对比各引擎的 UPSERT 方案:
   MySQL:      INSERT ... ON DUPLICATE KEY UPDATE（最常用）/ REPLACE INTO（删除+插入）
   PostgreSQL: INSERT ... ON CONFLICT DO UPDATE/NOTHING（9.5+）/ MERGE（15+）
   Oracle:     MERGE INTO（9i 开始，最早支持，最成熟）
   SQL Server: MERGE（有已知 Bug，多位 MVP 建议避免使用）
   BigQuery:   MERGE INTO（标准语法）
   Snowflake:  MERGE INTO（标准语法）
   Hive:       MERGE INTO（Hive 2.2+，需要 ACID 表）
   Flink SQL:  不支持 MERGE（通过 INSERT 的 Changelog 语义实现 Upsert）
   ClickHouse: ReplacingMergeTree 引擎自动去重（不是 SQL MERGE）

## 2. 基本 MERGE（Upsert）


```sql
MERGE INTO users AS t
USING new_users AS s
ON t.id = s.id
WHEN MATCHED THEN
    UPDATE SET t.email = s.email, t.age = s.age
WHEN NOT MATCHED THEN
    INSERT (id, username, email, age)
    VALUES (s.id, s.username, s.email, s.age);

```

## 3. 完整 MERGE: UPDATE + DELETE + INSERT


```sql
MERGE INTO users AS t
USING updates AS s
ON t.id = s.id
WHEN MATCHED AND s.delete_flag = true THEN
    DELETE
WHEN MATCHED THEN
    UPDATE SET *
WHEN NOT MATCHED THEN
    INSERT *;

```

 UPDATE SET * 和 INSERT * 使用所有列（Schema 必须匹配）
 这是 Delta Lake 的简写语法，大幅减少了大表的 MERGE 语句长度

## 4. 条件 MERGE


```sql
MERGE INTO users AS t
USING new_data AS s
ON t.username = s.username
WHEN MATCHED AND s.age > t.age THEN
    UPDATE SET t.email = s.email, t.age = s.age
WHEN MATCHED THEN
    UPDATE SET t.email = s.email                 -- 只更新 email，保留原有 age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

```

## 5. MERGE 从子查询或 VALUES


从子查询

```sql
MERGE INTO users AS t
USING (
    SELECT username, email, age
    FROM staging_users
    WHERE valid = true
) AS s
ON t.username = s.username
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *;

```

从 VALUES

```sql
MERGE INTO users AS t
USING (
    SELECT * FROM VALUES
        ('alice', 'alice_new@example.com', 26),
        ('dave', 'dave@example.com', 28)
    AS s(username, email, age)
) AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET t.email = s.email, t.age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

```

## 6. WHEN NOT MATCHED BY SOURCE（Spark 3.4+, Delta Lake）


删除目标表中源表没有的行（完全同步）

```sql
MERGE INTO users AS t
USING new_users AS s
ON t.id = s.id
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *
WHEN NOT MATCHED BY SOURCE THEN DELETE;

```

 这等价于"全量同步": 新增 + 更新 + 删除
 对比:
   Oracle:     MERGE ... WHEN NOT MATCHED BY TARGET（Oracle 10g+，最早支持）
   SQL Server: MERGE ... WHEN NOT MATCHED BY SOURCE（同名语法）
   PostgreSQL: 15+ MERGE 支持 WHEN NOT MATCHED BY SOURCE

## 7. MERGE 的实现机制（Delta Lake）


 MERGE 的执行过程:
### 1. 扫描源表和目标表，做 JOIN（ON 条件）

### 2. 对 JOIN 结果评估 WHEN 条件，确定每行是 UPDATE/DELETE/INSERT

### 3. 读取需要修改的目标文件

### 4. 写入新的文件（Copy-on-Write）

### 5. 更新事务日志


 性能优化关键:
   - ON 条件应能触发分区裁剪（避免全表扫描）
   - 源表应尽量小（或用子查询预过滤）
   - 大表 MERGE 时考虑按分区分批执行

## 8. 原生 Spark 表的 UPSERT 替代方案


无 Delta/Iceberg 时，通过 ANTI JOIN + UNION 模拟:

```sql
CREATE OR REPLACE TEMP VIEW merged_users AS
SELECT s.* FROM new_users s                      -- 所有新数据
UNION ALL
SELECT t.* FROM users t
LEFT ANTI JOIN new_users s ON t.id = s.id;       -- 旧表中未被新数据覆盖的行

INSERT OVERWRITE TABLE users
SELECT * FROM merged_users;

```

## 9. 版本演进

- **Spark 2.0**: 无 MERGE（只能用 ANTI JOIN + UNION 模拟）
- **Delta 0.3**: MERGE INTO 基本支持
- **Delta 1.0**: UPDATE SET * / INSERT * 简写
- **Spark 3.4**: WHEN NOT MATCHED BY SOURCE
- **Iceberg**: MERGE INTO 支持（Spark 3.0+）

> **限制**: 
MERGE INTO 需要 Delta Lake 或 Iceberg 表格式
无 INSERT ... ON CONFLICT 语法
无 RETURNING 子句
MERGE 的性能取决于 JOIN 效率——ON 条件必须高效
MERGE 不支持 self-merge（目标表和源表不能是同一张表）
源表中的 ON 条件匹配多行时会报错（一行不能被多次更新）
