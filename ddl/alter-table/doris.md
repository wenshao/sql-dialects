# Apache Doris: ALTER TABLE

 Apache Doris: ALTER TABLE

 参考资料:
   [1] Doris SQL Manual - ALTER TABLE
       https://doris.apache.org/docs/sql-manual/sql-statements/

## 1. Light Schema Change (1.2+): Doris 的核心 DDL 创新

 Doris 1.2 引入 Light Schema Change，部分 DDL 操作秒级完成，无需数据重写。

 原理: 仅修改 FE 元数据 + BE 文件 Footer，不触发数据文件重写。
 支持的操作: 添加/删除 Value 列、VARCHAR 扩容、修改默认值。
 不支持: 修改 Key 列、修改列类型(需兼容)、修改分桶列。

 对比:
   StarRocks:  Fast Schema Evolution(3.0+)，毫秒级完成，更激进的优化
   MySQL:      ALGORITHM=INSTANT(8.0.12+)，仅支持 ADD COLUMN 到末尾
   PostgreSQL: ADD COLUMN + DEFAULT 在 11+ 是即时的
   ClickHouse: ADD/DROP COLUMN 是即时的(修改元数据)，列存天然优势
   BigQuery:   ADD COLUMN 即时，但不支持 DROP COLUMN(需重建表)

 对引擎开发者的启示:
   列存引擎的 DDL 天然更轻量(每列独立存储)，关键挑战是:
### 1. 新增列的默认值如何与历史文件兼容(需要 Footer 记录默认值)

### 2. 删除列的空间回收(延迟到 Compaction)


## 2. 列操作


添加列(Light Schema Change: 秒级)

```sql
ALTER TABLE users ADD COLUMN phone VARCHAR(20);
ALTER TABLE users ADD COLUMN phone VARCHAR(20) AFTER email;

```

添加多列

```sql
ALTER TABLE users ADD COLUMN (
    city    VARCHAR(64),
    country VARCHAR(64)
);

```

删除列(Light Schema Change: 秒级)

```sql
ALTER TABLE users DROP COLUMN phone;

```

修改列类型(仅允许兼容变更，需要数据重写)

```sql
ALTER TABLE users MODIFY COLUMN phone VARCHAR(32);
```

允许: INT -> BIGINT, VARCHAR(N) -> VARCHAR(M) 其中 M > N
不允许: BIGINT -> INT(可能溢出), VARCHAR -> INT

修改列默认值(Light Schema Change)

```sql
ALTER TABLE users MODIFY COLUMN status INT DEFAULT 0;

```

修改列顺序(需要数据重写)

```sql
ALTER TABLE users ORDER BY (id, username, email, age);

```

重命名列(2.0+)
ALTER TABLE t RENAME COLUMN old TO new;

修改注释

```sql
ALTER TABLE users MODIFY COLUMN username COMMENT 'Login name';

```

## 3. 分区管理


添加分区

```sql
ALTER TABLE orders ADD PARTITION p2024_04 VALUES LESS THAN ('2024-05-01');
ALTER TABLE orders ADD PARTITION p2024_04 VALUES [('2024-04-01'), ('2024-05-01'));

```

批量添加分区(2.1+，Doris 独有便捷语法)

```sql
ALTER TABLE orders ADD PARTITIONS FROM ('2024-01-01') TO ('2024-12-01') INTERVAL 1 MONTH;

```

删除分区

```sql
ALTER TABLE orders DROP PARTITION p2024_01;

```

修改分区属性(热冷数据分层)

```sql
ALTER TABLE orders MODIFY PARTITION p2024_01 SET (
    "storage_medium" = "HDD",
    "storage_cooldown_time" = "2025-01-01 00:00:00"
);

```

 对比热冷分层:
   StarRocks: 相同的 storage_medium + storage_cooldown_time
   ClickHouse: TTL 表达式(更灵活): TTL created_at + INTERVAL 30 DAY TO VOLUME 'cold'
   BigQuery:  自动冷热(Long-term Storage 90天后价格降低50%)
   MySQL:     无原生冷热分层

## 4. Rollup 管理(预聚合物化索引)


```sql
ALTER TABLE daily_stats ADD ROLLUP rollup_by_date (date, clicks)
    PROPERTIES ("replication_num" = "1");
ALTER TABLE daily_stats DROP ROLLUP rollup_by_date;

```

 设计分析:
   ROLLUP 是 Doris/StarRocks 特有的预聚合机制。
   它在基表上创建物化的子表，包含指定维度+度量的聚合结果。
   优化器自动路由: 查询如果命中 ROLLUP 的列子集，自动读 ROLLUP 而非基表。
   对比物化视图: ROLLUP 限于单表聚合，物化视图可跨表 JOIN。

## 5. 表级操作


重命名表

```sql
ALTER TABLE users RENAME members;

```

修改表属性

```sql
ALTER TABLE users SET ("replication_num" = "1");
ALTER TABLE users SET ("in_memory" = "true");
ALTER TABLE users SET ("storage_medium" = "SSD");

```

Replace Table(原子替换)

```sql
ALTER TABLE users REPLACE WITH TABLE users_new;

```

修改分桶数(2.0+)

```sql
ALTER TABLE users MODIFY DISTRIBUTION DISTRIBUTED BY HASH(id) BUCKETS 32;

```

修改注释

```sql
ALTER TABLE users MODIFY COMMENT 'User information table';

```

## 6. 查看 ALTER 任务进度

```sql
SHOW ALTER TABLE COLUMN;
SHOW ALTER TABLE ROLLUP;

```

## 7. 关键限制与对比

不能修改/删除 Key 列(排序键/分桶键/分区键)
不能在 Key 列中添加新列(Key 列必须在建表时确定)
Aggregate Key 模型的 Value 列聚合方式不能修改

Doris vs StarRocks ALTER TABLE 差异:
- **Doris 2.0+**: 支持 RENAME COLUMN
- **StarRocks**: 不支持 RENAME COLUMN(需重建表)
- **Doris**: REPLACE WITH TABLE
- **StarRocks**: SWAP WITH (语法不同，功能相同)
- **Doris 2.1+**: 批量 ADD PARTITIONS ... INTERVAL
- **StarRocks 3.1**: Expression Partition(自动分区更优)

对引擎开发者的启示:
列存引擎的 DDL 核心挑战是 Key 列变更——因为 Key 列决定物理排序。
修改排序键 = 全表数据重写 + 索引重建，代价极高。
StarRocks 的 Fast Schema Evolution 通过延迟物化(Lazy Materialization)
进一步减少 DDL 对在线查询的影响。
