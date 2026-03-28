# MaxCompute (ODPS): UPDATE

> 参考资料:
> - [1] MaxCompute SQL - UPDATE
>   https://help.aliyun.com/zh/maxcompute/user-guide/update
> - [2] MaxCompute Transactional Tables
>   https://help.aliyun.com/zh/maxcompute/user-guide/transactional-tables


## 1. 核心概念: UPDATE 仅事务表支持


MaxCompute 有两类表，UPDATE 支持完全不同:
普通表: 不支持 UPDATE（Hive 族引擎的传统限制）
事务表: 支持 UPDATE（2.0+ 引入，需显式声明）

创建事务表

```sql
CREATE TABLE users (
    id       BIGINT,
    username STRING,
    email    STRING,
    age      BIGINT,
    status   STRING,
    PRIMARY KEY (id)
) TBLPROPERTIES ('transactional' = 'true');

```

## 2. 事务表 UPDATE 语法


基本更新

```sql
UPDATE users SET age = 26 WHERE username = 'alice';

```

多列更新

```sql
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

```

自引用更新

```sql
UPDATE users SET age = age + 1;

```

CASE 表达式

```sql
UPDATE users SET status = CASE
    WHEN age < 18 THEN 'minor'
    WHEN age >= 65 THEN 'senior'
    ELSE 'adult'
END;

```

子查询更新

```sql
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;

```

 设计决策: 事务表 UPDATE 的底层实现
   不是原地修改数据（AliORC 文件不可变）
   而是写入 delta 文件:
1. 读取匹配 WHERE 条件的行

2. 计算新值

3. 写入 delta 文件（包含更新后的行和行标识）

4. 读取时合并: base 文件 + delta 文件 → 最终结果

   定期 compaction: 将 base + delta 合并为新的 base 文件

   对比其他引擎的 UPDATE 实现:
     MySQL InnoDB: 原地更新 + undo log（MVCC）
     PostgreSQL:   新版本行 + 旧版本标记删除（HOT 优化避免索引更新）
     Hive ACID:    delta 文件 + compaction（与 MaxCompute 相同）
     Delta Lake:   Parquet 重写（copy-on-write）或 deletion vector
     Iceberg:      position delete file 或 copy-on-write
     BigQuery:     内部重写受影响的存储块
     Snowflake:    重建受影响的微分区

## 3. 非事务表的替代方案: INSERT OVERWRITE


这是 MaxCompute/Hive 的核心"更新"模式
不是真正的行级更新，而是重写整个表/分区

模拟单行更新: 重写整个表

```sql
INSERT OVERWRITE TABLE users
SELECT
    username,
    CASE WHEN username = 'alice' THEN 'new@example.com' ELSE email END AS email,
    CASE WHEN username = 'alice' THEN 26 ELSE age END AS age
FROM users;

```

模拟分区级更新: 只重写受影响分区（性能更好）

```sql
INSERT OVERWRITE TABLE events PARTITION (dt = '20240115')
SELECT
    user_id,
    CASE WHEN event_name = 'login' THEN 'user_login' ELSE event_name END AS event_name,
    event_time
FROM events
WHERE dt = '20240115';

```

 INSERT OVERWRITE "更新"的设计分析:
   优点:
1. 无需事务表声明（所有表都可以）

2. 幂等（重跑结果相同）

3. 无碎片（每次生成完整的 AliORC 文件）

   缺点:
1. 必须读写全量数据（即使只改一行）

2. SQL 写起来复杂（CASE WHEN 逻辑嵌在 SELECT 中）

3. 大表性能差（TB 级表重写耗时数小时）

4. 并发风险: 两个 INSERT OVERWRITE 同时执行，后完成的覆盖先完成的


## 4. UPDATE vs INSERT OVERWRITE 的选择


 使用事务表 UPDATE:
   场景: 维度表（千万级以下）、需要频繁行级更新
   优势: 语法简洁、性能好（只写 delta，不重写全量）
   劣势: 需要事务表声明、compaction 运维、读取时有合并开销

 使用 INSERT OVERWRITE:
   场景: 事实表（亿级以上）、ETL 管道中的分区级数据清洗
   优势: 所有表都支持、幂等、无碎片
   劣势: 大表重写代价高、SQL 复杂

 实际生产中: 绝大多数 MaxCompute 表仍使用 INSERT OVERWRITE
   事务表主要用于维度表（行数少、更新频繁）
   事实表（日志、交易记录）仍然是普通表 + INSERT OVERWRITE

## 5. 横向对比: UPDATE 能力


 行级 UPDATE 支持:
MaxCompute: 仅事务表（2.0+）     | Hive: 仅 ACID 表（0.14+）
BigQuery:   全表支持              | Snowflake: 全表支持
   ClickHouse: ALTER TABLE UPDATE（异步，非事务）
Spark SQL:  Delta Lake 表支持     | Databricks: Delta 表支持

 UPDATE ... FROM / JOIN:
   MaxCompute: 不支持 UPDATE ... FROM 语法
   PostgreSQL: UPDATE t SET ... FROM s WHERE t.id = s.id（标准做法）
   SQL Server: UPDATE t SET ... FROM t JOIN s ON ...
   MySQL:      UPDATE t JOIN s ON ... SET t.col = s.col
   MaxCompute 替代: 使用 MERGE INTO（见 upsert 文件）

 UPDATE 实现模型:
   原地更新: MySQL InnoDB（undo log + 原地写入）
   新版本: PostgreSQL（写新元组，标记旧元组删除）
   文件重写: BigQuery/Snowflake（重写受影响的数据块）
   Delta 文件: MaxCompute/Hive ACID/Delta Lake（写入增量文件）

## 6. 对引擎开发者的启示


1. 不可变文件上的 UPDATE = delta 文件 + 读时合并 + compaction

2. INSERT OVERWRITE 虽然原始但在 ETL 场景中极其实用（幂等性）

3. 事务表的读取性能因 delta 合并而降低 — compaction 策略至关重要

4. Delta Lake/Iceberg 的教训: 默认所有表支持事务比后期追加更好

5. UPDATE ... FROM 语法虽非标准，但用户需求强烈，应考虑支持

6. 异步 UPDATE（如 ClickHouse 的 ALTER TABLE UPDATE）是有趣的折中

