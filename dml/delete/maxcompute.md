# MaxCompute (ODPS): DELETE

> 参考资料:
> - [1] MaxCompute SQL - DELETE
>   https://help.aliyun.com/zh/maxcompute/user-guide/delete-1
> - [2] MaxCompute Transactional Tables
>   https://help.aliyun.com/zh/maxcompute/user-guide/transactional-tables


## 1. 核心概念: DELETE 仅事务表支持


与 UPDATE 相同: 普通表不支持 DELETE
只有事务表（TBLPROPERTIES 'transactional'='true'）支持 DELETE


```sql
CREATE TABLE users (
    id       BIGINT,
    username STRING,
    email    STRING,
    status   STRING,
    last_login DATETIME,
    PRIMARY KEY (id)
) TBLPROPERTIES ('transactional' = 'true');

```

## 2. 事务表 DELETE 语法


条件删除

```sql
DELETE FROM users WHERE username = 'alice';
DELETE FROM users WHERE status = 'inactive' AND last_login < DATETIME '2023-01-01 00:00:00';

```

子查询删除

```sql
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

```

EXISTS 子查询

```sql
DELETE FROM users
WHERE EXISTS (SELECT 1 FROM blacklist WHERE blacklist.email = users.email);

```

删除所有行（等价于 TRUNCATE，但走事务日志）

```sql
DELETE FROM users;

```

 底层实现: delete delta 文件
   DELETE 不是物理删除 AliORC 文件中的行
   而是写入一个 delete delta 文件（记录被删除行的标识）
   读取时: 基础文件 - delete delta = 最终可见数据
   compaction 时: 将删除标记应用到基础文件，生成新的紧凑文件

   对比:
     MySQL InnoDB:  标记删除 + purge 线程清理
     PostgreSQL:    dead tuple + VACUUM 清理
     Hive ACID:     delete delta 文件（与 MaxCompute 相同）
     Delta Lake:    deletion vector 或 copy-on-write（重写整个文件）
     Iceberg:       position delete file 或 equality delete file
     BigQuery:      内部重写受影响的存储块
     Snowflake:     重建受影响的微分区

## 3. 非事务表的删除替代方案


方案 1: INSERT OVERWRITE 保留不删除的行

```sql
INSERT OVERWRITE TABLE users
SELECT * FROM users WHERE username != 'alice';

```

方案 2: 分区级删除 — INSERT OVERWRITE 指定分区

```sql
INSERT OVERWRITE TABLE events PARTITION (dt = '20240115')
SELECT user_id, event_name, event_time
FROM events
WHERE dt = '20240115' AND event_name != 'spam';

```

方案 3: DROP PARTITION — 删除整个分区（最快，所有表都支持）

```sql
ALTER TABLE events DROP PARTITION (dt = '20240115');

```

批量删除分区

```sql
ALTER TABLE events DROP PARTITION (dt >= '20240101' AND dt <= '20240131');

```

方案 4: TRUNCATE — 清空表数据（DDL 操作，瞬间完成）

```sql
TRUNCATE TABLE users;

```

 设计分析: 为什么 DROP PARTITION 是最高效的"删除"?
   DROP PARTITION 是元数据操作 + 文件系统目录删除
   时间复杂度: O(1) 元数据 + O(文件数) 异步文件删除
   对比行级 DELETE: O(N) 扫描 + O(M) 写 delta 文件
   这就是为什么 MaxCompute 中分区设计如此重要:
     好的分区设计 → 按分区管理数据 → 删除=DROP PARTITION → 秒级完成
     无分区或分区粒度不对 → 只能 INSERT OVERWRITE 全表 → 耗时数小时

## 4. 数据保留策略: LIFECYCLE vs DELETE


LIFECYCLE 自动删除（声明式 TTL，最简洁）

```sql
CREATE TABLE logs (id BIGINT, message STRING)
PARTITIONED BY (dt STRING)
LIFECYCLE 90;                               -- 90 天后自动回收

```

 LIFECYCLE 的实现:
   MaxCompute 后台定时扫描分区的最后修改时间
   超过 LIFECYCLE 天数的分区被自动回收
   这是比 DELETE 更好的数据生命周期管理方案

 对比:
   ClickHouse:  TTL timestamp + INTERVAL 90 DAY DELETE（行级或分区级）
   BigQuery:    partition_expiration_days（分区级自动删除）
   Hive:        无内置 TTL（依赖外部调度删除旧分区）
   Snowflake:   DATA_RETENTION_TIME_IN_DAYS（Time Travel 保留期，非自动删除）
   Kafka:       retention.ms（消息保留期）

## 5. Time Travel 恢复（事务表 2.0+）


事务表支持按时间点查询历史数据

```sql
SELECT * FROM users TIMESTAMP AS OF DATETIME '2024-01-15 10:00:00';

```

 设计分析: Time Travel 依赖 delta 文件的保留
   事务表的 compaction 不会立即删除旧版本文件
   保留期内可以查询任意历史时间点的数据快照
   超过保留期后旧版本文件被清理，Time Travel 失效

   对比:
     Delta Lake:  默认 30 天 Time Travel
     Iceberg:     通过 snapshot 实现，可配置保留期
     Snowflake:   1-90 天 Time Travel（按版本收费）
     BigQuery:    7 天 Time Travel（免费）

## 6. 横向对比: DELETE 能力


 行级 DELETE:
MaxCompute: 仅事务表              | Hive: 仅 ACID 表
BigQuery:   全表支持（DML 配额）  | Snowflake: 全表支持
   ClickHouse: ALTER TABLE DELETE（异步执行，非事务）
   MySQL/PG:   完全支持

 TRUNCATE:
MaxCompute: 支持（DDL 操作）      | 所有引擎均支持

 DROP PARTITION:
   MaxCompute: 支持（最快的批量删除方式）
   Hive:       支持（相同语义）
   BigQuery:   支持（但分区列必须是 DATE/TIMESTAMP/INT）
   ClickHouse: ALTER TABLE DROP PARTITION（即时完成）

## 7. 对引擎开发者的启示


### 1. 不可变文件引擎的 DELETE = 标记删除 + 后台清理（与 MVCC 类似）

### 2. DROP PARTITION 是批处理引擎中最高效的删除手段 — 值得优化

### 3. LIFECYCLE/TTL 比手动 DELETE 更适合数据生命周期管理

### 4. Time Travel 依赖延迟清理旧文件 — 存储成本与历史可追溯性的权衡

### 5. 分区设计决定了删除效率: 好的分区 = 秒级 DROP，坏的分区 = 小时级重写

### 6. INSERT OVERWRITE 模拟删除虽然笨拙但在所有表上都可用 — 通用兜底方案

