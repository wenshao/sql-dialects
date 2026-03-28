# Spark SQL: UPDATE (更新)

> 参考资料:
> - [1] Delta Lake - UPDATE
>   https://docs.delta.io/latest/delta-update.html#update-a-table
> - [2] Apache Iceberg - UPDATE
>   https://iceberg.apache.org/docs/latest/spark-writes/#update


## 1. 核心设计: 原生 Spark SQL 不支持 UPDATE


 UPDATE 需要 Delta Lake、Iceberg 或 Hudi 等支持行级操作的表格式。
 原生 Parquet/ORC 是不可变文件——"更新一行"意味着重写整个文件。

 这是列式存储的固有限制:
   行存储（MySQL InnoDB）: 定位行 -> 原地修改 -> 写 redo log，O(1) 操作
   列存储（Parquet/ORC）:  定位行 -> 读整个列文件 -> 修改 -> 重写文件，O(n) 操作
   Delta Lake:             Copy-on-Write 或 Merge-on-Read 处理行级更新

 对比:
   MySQL:      UPDATE t SET ... WHERE ... + 行级锁 + MVCC
   PostgreSQL: UPDATE t SET ... WHERE ... + MVCC（旧行标记删除，新行插入）
   Oracle:     UPDATE + RETURNING INTO + FLASHBACK
   Hive:       Hive 3.0+ ACID 表支持 UPDATE（性能差）
   Flink SQL:  Changelog 语义的 UPDATE（UPDATE 变为 -U/+U 消息对）
   ClickHouse: ALTER TABLE UPDATE（异步 mutation，不适合频繁更新）
   BigQuery:   UPDATE 支持但有 DML 配额限制

## 2. Delta Lake: UPDATE 语法


基本更新

```sql
UPDATE users SET age = 26 WHERE username = 'alice';

```

多列更新

```sql
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

```

表达式更新

```sql
UPDATE orders SET
    total = quantity * unit_price,
    updated_at = current_timestamp()
WHERE total IS NULL;

```

CASE 表达式更新

```sql
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

```

## 3. 子查询 UPDATE


标量子查询

```sql
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;

```

IN 子查询

```sql
UPDATE users SET status = 2
WHERE id IN (
    SELECT user_id FROM orders
    GROUP BY user_id
    HAVING SUM(amount) > 10000
);

```

## 4. UPDATE 的实现机制（Delta Lake）


 Copy-on-Write:
### 1. 扫描文件，找到匹配 WHERE 条件的行所在的文件

### 2. 读取这些文件的全部数据

### 3. 修改匹配行，与未修改行合并

### 4. 写入新的 Parquet 文件，记录到事务日志


 Merge-on-Read（Deletion Vectors, Delta 2.0+）:
### 1. 创建 Deletion Vector 标记旧行

### 2. 写入新行到新的 Parquet 文件

### 3. 读取时合并 Deletion Vector 和新文件

### 4. 后续 OPTIMIZE 时物理合并


 对引擎开发者的启示:
   Copy-on-Write 适合读多写少的场景（写入慢但读取快）
   Merge-on-Read 适合写多读少的场景（写入快但读取有额外开销）
   Delta Lake 2.0+ 的 Deletion Vectors 是 Merge-on-Read 的实现
   Iceberg 的 Copy-on-Write vs Merge-on-Read 是可配置的（per-table）

## 5. Iceberg UPDATE


 Iceberg 从 0.12 开始支持 UPDATE（Spark 3.1+）
 UPDATE catalog.db.users SET age = 26 WHERE username = 'alice';

## 6. 原生 Spark 表的替代方案


方案 1: INSERT OVERWRITE + CASE 表达式

```sql
CREATE OR REPLACE TEMP VIEW updated_users AS
SELECT id, username,
    CASE WHEN username = 'alice' THEN 'new@example.com' ELSE email END AS email,
    CASE WHEN username = 'alice' THEN 26 ELSE age END AS age
FROM users;

INSERT OVERWRITE TABLE users
SELECT * FROM updated_users;

```

方案 2: CTAS 重建

```sql
CREATE TABLE users_new AS
SELECT id, username,
    CASE WHEN age IS NULL THEN 0 ELSE age END AS age,
    email
FROM users;
DROP TABLE users;
ALTER TABLE users_new RENAME TO users;

```

## 7. Time Travel 恢复误更新（Delta Lake）


 误更新后恢复:
 DESCRIBE HISTORY users;                     -- 找到更新前的版本
 RESTORE TABLE users TO VERSION AS OF 5;     -- 回退

## 8. 版本演进

- **Spark 2.0**: 无 UPDATE（只能 INSERT OVERWRITE）
- **Delta 0.3**: UPDATE 支持（Copy-on-Write）
- **Delta 2.0**: Deletion Vectors（Merge-on-Read，更新性能大幅提升）
- **Iceberg 0.12**: UPDATE 支持
- **Spark 3.4**: 子查询 UPDATE 改进

> **限制**: 
原生 Parquet/ORC 表不支持 UPDATE
无 RETURNING 子句
无 FROM 子句的多表 UPDATE（使用子查询或 MERGE 替代）
无 UPDATE ... JOIN 语法（使用 MERGE INTO 替代）
大规模 UPDATE 涉及大量文件重写，建议在低峰期执行
更新分区列可能导致数据在分区间移动（性能开销大）
