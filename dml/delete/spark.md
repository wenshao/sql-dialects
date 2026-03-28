# Spark SQL: DELETE (删除)

> 参考资料:
> - [1] Delta Lake - DELETE
>   https://docs.delta.io/latest/delta-update.html#delete-from-a-table
> - [2] Apache Iceberg - DELETE
>   https://iceberg.apache.org/docs/latest/spark-writes/#delete


## 1. 核心设计: 原生 Spark SQL 不支持行级 DELETE


 DELETE 需要 Delta Lake、Iceberg 或 Hudi 等支持行级操作的表格式。
 原生 Parquet/ORC 表不支持 DELETE——只能通过 INSERT OVERWRITE 重写整张表。

 根本原因: Parquet/ORC 是不可变文件格式，没有"删除一行"的概念。
 要删除一行，必须读取整个文件、过滤掉目标行、重写整个文件。
 Delta Lake 通过 Deletion Vectors（2.0+）或 Copy-on-Write 实现行级删除。

 对比:
   MySQL:      DELETE FROM t WHERE ... + RETURNING（8.0 无 RETURNING）
   PostgreSQL: DELETE FROM t WHERE ... RETURNING * + 可在事务中回滚
   Oracle:     DELETE FROM t WHERE ... + RETURNING INTO 变量
   Hive:       Hive 3.0+ ACID 表支持 DELETE（但性能差）
   Flink SQL:  DELETE 仅在特定 Connector 上支持（如 JDBC Sink）
   ClickHouse: ALTER TABLE DELETE（异步合并，不是即时删除）
   BigQuery:   DELETE + DML 配额限制
   Trino:      DELETE 取决于 Connector 支持

## 2. Delta Lake: DELETE 语法


基本 DELETE

```sql
DELETE FROM users WHERE username = 'alice';

```

复合条件

```sql
DELETE FROM users WHERE age < 18 OR status = 0;

```

子查询 DELETE

```sql
DELETE FROM users WHERE id IN (
    SELECT user_id FROM blacklist
);

```

EXISTS 子查询

```sql
DELETE FROM users
WHERE EXISTS (
    SELECT 1 FROM blacklist WHERE blacklist.email = users.email
);

```

DELETE 全部行

```sql
DELETE FROM users;

```

TRUNCATE（更高效的全量删除）

```sql
TRUNCATE TABLE users;

```

## 3. DELETE 的实现机制（Delta Lake）


 Copy-on-Write（传统方式）:
1. 找到包含目标行的 Parquet 文件

2. 读取文件，过滤掉目标行

3. 写入新的 Parquet 文件

4. 在事务日志中记录: 删除旧文件，添加新文件

   成本: 即使只删一行，也要重写整个文件

 Deletion Vectors（Delta Lake 2.0+）:
1. 找到包含目标行的 Parquet 文件

2. 创建一个位图（Deletion Vector），标记被删除行的位置

3. 读取时跳过被标记的行（不重写文件）

4. 后续 OPTIMIZE 时合并 Deletion Vectors 并重写文件

   成本: DELETE 速度大幅提升，但读取时有额外的位图检查开销

 对比:
   MySQL InnoDB:   标记删除 + purge 线程异步清理（MVCC undo log）
   PostgreSQL:     标记删除 + VACUUM 清理（与 Delta 的理念最相似）
   ClickHouse:     ALTER TABLE DELETE 是异步操作，后台 mutation 执行

## 4. MERGE 实现 DELETE（基于 JOIN 的条件删除）


当需要基于另一个表的条件删除时，MERGE 比子查询更高效:

```sql
MERGE INTO users
USING blacklist ON users.email = blacklist.email
WHEN MATCHED THEN DELETE;

```

## 5. 原生 Spark 表的替代方案


方案 1: INSERT OVERWRITE（过滤保留需要的行）

```sql
INSERT OVERWRITE TABLE users
SELECT * FROM users WHERE username != 'alice';

```

方案 2: CTAS 重建（大规模清理）

```sql
CREATE TABLE users_clean AS
SELECT * FROM users WHERE status != 0;
DROP TABLE users;
ALTER TABLE users_clean RENAME TO users;

```

## 6. Time Travel 恢复误删数据（Delta Lake）


 误删后恢复:
 DESCRIBE HISTORY users;                      -- 找到删除前的版本
 RESTORE TABLE users TO VERSION AS OF 5;      -- 回退

 物理清理已删除数据的文件:
 VACUUM users RETAIN 168 HOURS;               -- 删除 7 天前的旧文件

## 7. 版本演进

Spark 2.0: 无 DELETE（只能 INSERT OVERWRITE）
Delta 0.3: DELETE 支持（Copy-on-Write）
Delta 2.0: Deletion Vectors（行级标记删除，避免文件重写）
Iceberg 0.12: DELETE 支持
Spark 3.4: TRUNCATE TABLE 改进

限制:
原生 Parquet/ORC 表不支持 DELETE
无 RETURNING 子句（不能返回被删除的行）
无 USING 子句（不能直接 JOIN 其他表做删除，需用 MERGE 或子查询）
VACUUM 后 Time Travel 失效（被清理的版本不可恢复）
大规模 DELETE 涉及大量文件重写，建议在低峰期执行

