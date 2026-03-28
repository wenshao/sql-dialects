# Hive: DELETE

> 参考资料:
> - [1] Apache Hive Language Manual - DML
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DML
> - [2] Apache Hive - Hive Transactions
>   https://cwiki.apache.org/confluence/display/Hive/Hive+Transactions


## 1. Hive DELETE 的两个世界

 Hive 的数据删除存在两种完全不同的机制:
### 1. ACID 表: 行级 DELETE（0.14+），通过 delete delta 文件实现

### 2. 非 ACID 表: 无行级 DELETE，只能 DROP PARTITION 或 INSERT OVERWRITE 过滤


 这一分裂源于 Hive 的存储设计:
 HDFS 不支持文件修改（只能追加或重写），因此:
 - ACID 表的 DELETE 实际上是"写入一条删除标记"（delete delta）
 - 非 ACID 表只能整体重写（INSERT OVERWRITE 保留不删除的行）

## 2. ACID 表的 DELETE

前提: 表必须是 ORC 格式 + transactional=true
CREATE TABLE users (...) STORED AS ORC TBLPROPERTIES ('transactional'='true');

基本删除

```sql
DELETE FROM users WHERE username = 'alice';

```

条件删除

```sql
DELETE FROM users WHERE status = 0 AND last_login < '2023-01-01';

```

子查询删除

```sql
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

```

删除所有行

```sql
DELETE FROM users;

```

 ACID DELETE 的内部实现:
 DELETE FROM users WHERE id = 1 不会修改原始 ORC 文件，
 而是创建一个 delete_delta_XXXXX 目录，写入包含 {originalTransactionId, bucket, rowId}
 的删除标记。读取时，合并 base + delta + delete_delta 得到最终结果。

 性能影响:
 每次 DELETE 增加一个 delete delta 文件 → 读取时需要更多合并操作
 需要定期 Major Compaction 来清理 delete delta

## 3. 非 ACID 表的替代方案

方案 A: INSERT OVERWRITE 过滤（最常用）

```sql
INSERT OVERWRITE TABLE users
SELECT * FROM users WHERE username != 'alice';

```

方案 B: INSERT OVERWRITE 分区级（更高效）

```sql
INSERT OVERWRITE TABLE events PARTITION (dt='2024-01-15')
SELECT user_id, event_name, event_time
FROM events
WHERE dt = '2024-01-15' AND event_name != 'spam';

```

方案 C: DROP PARTITION（删除整个分区）

```sql
ALTER TABLE events DROP PARTITION (dt='2024-01-15');
ALTER TABLE events DROP IF EXISTS PARTITION (dt >= '2024-01-01', dt <= '2024-01-31');

```

方案 D: TRUNCATE（清空表/分区）

```sql
TRUNCATE TABLE users;
TRUNCATE TABLE events PARTITION (dt='2024-01-15');

```

 设计分析: INSERT OVERWRITE 模拟 DELETE 的代价
 需要读取整个表/分区 → 过滤 → 写回
 对于 TB 级表，即使只删除一行也需要全量重写
 这就是为什么 ACID 表（行级 DELETE）被引入的原因

## 4. 已知限制

### 1. DELETE 仅限 ACID 表（ORC + transactional=true）

### 2. 不支持多表 JOIN 删除: DELETE FROM a JOIN b ON ... 不可用

### 3. 不支持 ORDER BY / LIMIT: 不能 DELETE ... ORDER BY id LIMIT 10

### 4. 分区列不能作为 DELETE 条件: 分区是目录，用 DROP PARTITION 删除

### 5. 外部表不能 DELETE: 外部表不支持 ACID

### 6. 不支持 RETURNING 子句: 不能返回被删除的行


## 5. 跨引擎对比: 删除设计

 引擎           DELETE 能力              非 ACID 替代方案
 MySQL(InnoDB)  行级 DELETE (标准)       N/A (所有表都支持)
 PostgreSQL     行级 DELETE + RETURNING  N/A
 Hive           ACID 行级 / 非ACID无     INSERT OVERWRITE / DROP PARTITION
 Spark SQL      Delta Lake DELETE        INSERT OVERWRITE
 BigQuery       DELETE (DML 配额限制)    无
 ClickHouse     ALTER TABLE DELETE       轻量级 DELETE (mutation)
 Trino          Connector 依赖           INSERT OVERWRITE
 Flink SQL      不支持 DELETE            Changelog 流

 ClickHouse 的 DELETE 设计独特:
 ALTER TABLE DELETE WHERE ... 是异步 mutation，后台重写数据 part。
 轻量级 DELETE（DELETE FROM）在 22.8+ 引入，通过位图标记实现。

## 6. 对引擎开发者的启示

### 1. 不可变存储 + 删除标记是大数据 DELETE 的标准范式:

    Hive/Delta/Iceberg 都用 delete delta/delete files 实现 DELETE
### 2. DROP PARTITION 是最高效的"删除": 只删目录和元数据，零 I/O

### 3. GDPR/数据合规驱动了大数据引擎的 DELETE 需求:

    行级 DELETE 的需求来自"被遗忘权"等法规要求
### 4. DELETE 的写入放大问题: 行级 DELETE 需要读取原始数据来确定要删除的行，

然后写入删除标记——这在 TB 级表上代价很大

