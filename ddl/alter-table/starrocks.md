# StarRocks: ALTER TABLE

> 参考资料:
> - [1] StarRocks - ALTER TABLE
>   https://docs.starrocks.io/docs/sql-reference/sql-statements/table_bucket_part_index/ALTER_TABLE/


## 1. Fast Schema Evolution (3.0+): StarRocks 的 DDL 核心优势

 StarRocks 3.0 引入 Fast Schema Evolution，列的增删改毫秒级完成。
 默认开启: SET GLOBAL enable_fast_schema_evolution = true;

 原理: 与 Doris Light Schema Change 类似(修改元数据不重写数据)，
   但 StarRocks 更激进——支持更多操作类型且默认启用。

 对比:
   Doris:      Light Schema Change(1.2+)，秒级，需手动识别
   MySQL:      ALGORITHM=INSTANT(8.0.12+)，仅 ADD COLUMN 到末尾
   PostgreSQL: ADD COLUMN + DEFAULT 在 11+ 即时
   ClickHouse: 列操作即时(列存天然优势)

 对引擎开发者的启示:
   Fast Schema Evolution 的关键是"文件格式的前向兼容"——
   旧文件不包含新列时，读取时自动填充默认值。
   这要求文件 Footer 包含完整的 schema 版本信息。

## 2. 列操作


添加列(Fast Schema Evolution: 毫秒级)

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

删除列

```sql
ALTER TABLE users DROP COLUMN phone;

```

修改列类型(兼容变更)

```sql
ALTER TABLE users MODIFY COLUMN phone VARCHAR(32);
```

允许: INT -> BIGINT, VARCHAR(N) -> VARCHAR(M) 其中 M > N

修改列默认值

```sql
ALTER TABLE users MODIFY COLUMN status INT DEFAULT 0;

```

修改列顺序

```sql
ALTER TABLE users ORDER BY (id, username, email, age);

```

修改注释

```sql
ALTER TABLE users MODIFY COMMENT 'User information table';

```

## 3. 分区管理


添加/删除分区

```sql
ALTER TABLE orders ADD PARTITION p2024_04 VALUES LESS THAN ('2024-05-01');
ALTER TABLE orders ADD PARTITION p2024_04 VALUES [('2024-04-01'), ('2024-05-01'));
ALTER TABLE orders DROP PARTITION p2024_01;

```

修改分区 TTL(热冷分层)

```sql
ALTER TABLE orders MODIFY PARTITION (*) SET (
    "storage_medium" = "HDD",
    "storage_cooldown_time" = "2025-01-01 00:00:00"
);

```

 Expression Partition (3.1+): 自动分区管理
 建表时: PARTITION BY date_trunc('month', order_date)
 数据写入时自动创建对应分区，无需手动 ADD PARTITION。

 对比:
   Doris:     动态分区(需配置 PROPERTIES)，不如 Expression Partition 灵活
   Oracle:    INTERVAL Partition(最早的自动分区)
   ClickHouse: PARTITION BY toYYYYMM(date)(表达式分区，最灵活)

## 4. Rollup 管理


```sql
ALTER TABLE daily_stats ADD ROLLUP rollup_by_date (date, SUM(clicks))
    PROPERTIES ("replication_num" = "1");
ALTER TABLE daily_stats DROP ROLLUP rollup_by_date;

```

 设计分析:
   StarRocks 3.0+ 推荐用物化视图替代 ROLLUP。
   物化视图更灵活: 支持多表 JOIN、CBO 自动改写。
   ROLLUP 仅限单表聚合，但维护成本更低(与基表同步更新)。

## 5. 表级操作


重命名表

```sql
ALTER TABLE users RENAME members;

```

SWAP 表(原子替换——与 Doris 的 REPLACE WITH TABLE 语法不同)

```sql
ALTER TABLE users SWAP WITH users_new;

```

修改表属性

```sql
ALTER TABLE users SET ("replication_num" = "1");
ALTER TABLE users SET ("in_memory" = "true");
ALTER TABLE users SET ("storage_medium" = "SSD");
ALTER TABLE users SET ("default_replication_num" = "1");

```

## 6. 查看 ALTER 任务进度

```sql
SHOW ALTER TABLE COLUMN;
SHOW ALTER TABLE ROLLUP;

```

## 7. 关键限制

 不支持 RENAME COLUMN(需重建表)——Doris 2.0+ 支持
 不能删除 Key 列(排序键/分桶键/分区键)
 不能在 Key 列中添加新列
 Aggregate Key 模型 Value 列聚合方式不能修改
 Primary Key 模型: 不能修改主键列

## 8. StarRocks vs Doris ALTER TABLE 差异总结

Schema 变更速度:
StarRocks 3.0+: Fast Schema Evolution(毫秒级，默认启用)
Doris 1.2+:     Light Schema Change(秒级)

语法差异:
StarRocks: ALTER TABLE t SWAP WITH t_new;
Doris:     ALTER TABLE t REPLACE WITH TABLE t_new;

StarRocks: 不支持 RENAME COLUMN
Doris 2.0+: 支持 ALTER TABLE t RENAME COLUMN old TO new

分区管理:
StarRocks 3.1+: Expression Partition(最优方案)
Doris 2.1+:     ADD PARTITIONS ... INTERVAL(批量便捷)

对引擎开发者的启示:
SWAP/REPLACE 原子替换是分析型引擎的核心 DDL 操作——
用于数据修复、全量刷新场景。实现依赖 FE 元数据的原子切换。
比 MySQL 的 RENAME TABLE old TO bak, new TO old 更安全。

