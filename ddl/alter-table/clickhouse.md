# ClickHouse: ALTER TABLE

> 参考资料:
> - [1] ClickHouse SQL Reference - ALTER TABLE
>   https://clickhouse.com/docs/en/sql-reference/statements/alter
> - [2] ClickHouse - Mutations
>   https://clickhouse.com/docs/en/sql-reference/statements/alter/update
> - [3] ClickHouse - MergeTree Settings
>   https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree


## 1. 基本语法


添加列

```sql
ALTER TABLE users ADD COLUMN phone String DEFAULT '';
ALTER TABLE users ADD COLUMN age UInt8 AFTER username;  -- 支持 AFTER

```

删除列

```sql
ALTER TABLE users DROP COLUMN phone;

```

修改列类型（列存引擎需要重写整列数据）

```sql
ALTER TABLE users MODIFY COLUMN age UInt16;

```

修改默认值（不重写数据，仅修改元数据）

```sql
ALTER TABLE users MODIFY COLUMN age UInt16 DEFAULT 0;

```

重命名列（20.4+，仅修改元数据，零开销）

```sql
ALTER TABLE users RENAME COLUMN email TO email_address;

```

添加/删除注释

```sql
ALTER TABLE users COMMENT COLUMN username 'Login name';
ALTER TABLE users MODIFY COLUMN username String COMMENT 'Login name';

```

## 2. 列式存储对 ALTER TABLE 的影响（对引擎开发者）


### 2.1 列存 vs 行存 对 DDL 的影响

 ClickHouse 是列式存储: 每列数据独立存放在单独的文件中。
 这使得列级操作的性能特征与行存引擎截然不同:

   ADD COLUMN:    只需在元数据中注册新列，不触碰已有数据
                  新列的值在读取时用默认值填充（懒计算）
                  → 比 MySQL 的 ALGORITHM=INSTANT 更自然

   DROP COLUMN:   标记列为已删除，后台合并时物理清除
                  → 立即返回，实际清除是异步的

   MODIFY COLUMN: 需要重写该列的所有 data part 文件
   （类型变更）   → 这是一个 mutation，异步执行
                  → 表仍可读写，但旧 part 在合并前仍存在

 对比行存引擎:
   MySQL InnoDB:  ADD COLUMN 可能需要重建整个表（除非 INSTANT）
                  因为每行数据是连续存储的，新增列需要在每行末尾追加
   PostgreSQL:    ADD COLUMN + DEFAULT 11+ 不重写（在元组头中标记）

 对引擎开发者的启示:
   列存引擎的 DDL 天然更高效: 列独立存储意味着列级操作不影响其他列。
   但 MODIFY COLUMN（类型变更）仍需要重写，因为物理格式改变了。

### 2.2 Mutation 机制: ALTER 的异步执行模型

ClickHouse 中涉及数据重写的 ALTER 操作（MODIFY COLUMN 类型、UPDATE、DELETE）
都通过 mutation 机制实现:

提交 mutation → 立即返回 mutation_id → 后台逐个 part 重写

查看 mutation 进度:

```sql
SELECT mutation_id, command, is_done, parts_to_do
FROM system.mutations
WHERE table = 'users' AND database = currentDatabase();

```

等待 mutation 完成（同步等待）

```sql
ALTER TABLE users UPDATE age = 0 WHERE age < 0
SETTINGS mutations_sync = 1;   -- 0=异步(默认), 1=等当前副本, 2=等所有副本

```

 设计 trade-off:
   优点: DDL 不阻塞查询，适合 OLAP 场景（分析查询不应被 DDL 阻塞）
   缺点: 变更不是即时可见的，需要监控 mutation 进度
   对比 MySQL: Online DDL 也是异步的，但有明确的完成时间点
   对比 PostgreSQL: DDL 是事务性同步的，立即可见

## 3. 分区操作（ClickHouse 最强大的 DDL 能力）


分区操作是原子的，这是 ClickHouse 实现"伪事务"的主要手段

分离分区（从活跃数据中移除，但保留在磁盘上的 detached 目录）

```sql
ALTER TABLE orders DETACH PARTITION '2024-01';

```

重新挂载分区

```sql
ALTER TABLE orders ATTACH PARTITION '2024-01';

```

删除分区（物理删除，立即释放磁盘空间）

```sql
ALTER TABLE orders DROP PARTITION '2024-01';

```

从另一个表移动分区（原子操作，零拷贝）

```sql
ALTER TABLE orders REPLACE PARTITION '2024-01' FROM orders_staging;

```

原子交换两个表的分区

```sql
ALTER TABLE orders MOVE PARTITION '2024-01' TO TABLE orders_archive;

```

清空分区中指定列（比 DELETE WHERE 快得多）

```sql
ALTER TABLE orders CLEAR COLUMN amount IN PARTITION '2024-01';

```

冻结分区（创建硬链接快照，用于备份）

```sql
ALTER TABLE orders FREEZE PARTITION '2024-01';

```

 设计分析:
   ClickHouse 的分区操作本质上是文件系统级别的目录操作（rename/link）。
   这使得分区操作极快且原子，是 ClickHouse 缺乏事务支持的主要补偿机制。
   数据管道的推荐模式: 写入临时表 → REPLACE PARTITION → 原子切换

 对比:
   MySQL:      ALTER TABLE ... EXCHANGE PARTITION（类似但限制更多）
   PostgreSQL: ALTER TABLE ... ATTACH/DETACH PARTITION（10+，声明式分区）
   Hive:       ALTER TABLE ... ADD/DROP PARTITION（分区即目录）

## 4. TTL（数据生命周期管理）


添加列级 TTL（到期后清零该列的值）

```sql
ALTER TABLE users MODIFY COLUMN bio String TTL created_at + INTERVAL 1 YEAR;

```

添加表级 TTL（到期后删除整行）

```sql
ALTER TABLE logs MODIFY TTL created_at + INTERVAL 90 DAY;

```

TTL 触发移动到冷存储（分层存储）

```sql
ALTER TABLE logs MODIFY TTL
    created_at + INTERVAL 30 DAY TO VOLUME 'cold',
    created_at + INTERVAL 365 DAY DELETE;

```

 设计分析:
   TTL 是 ClickHouse 独有的 DDL 特性，反映了分析型引擎的核心需求:
   日志/事件数据有明确的生命周期，自动过期比手动 DELETE 高效得多。
   TTL 在后台 merge 时执行，不增加写入开销。

 对比:
   MySQL:      无 TTL，需要定时任务 + DELETE（或分区 + DROP PARTITION）
   PostgreSQL: 无 TTL，同上
   BigQuery:   分区过期: 设置 partition_expiration_days
   Cassandra:  TTL 是列级特性（与 ClickHouse 最接近）

## 5. 索引与投影操作


添加二级索引（跳数索引，不是 B+Tree）

```sql
ALTER TABLE users ADD INDEX idx_email email TYPE bloom_filter GRANULARITY 4;

```

删除索引

```sql
ALTER TABLE users DROP INDEX idx_email;

```

物化索引到已有数据

```sql
ALTER TABLE users MATERIALIZE INDEX idx_email;

```

添加投影（预聚合视图，存储在同一张表内）

```sql
ALTER TABLE orders ADD PROJECTION proj_by_user (
    SELECT user_id, sum(amount), count()
    GROUP BY user_id
);
ALTER TABLE orders MATERIALIZE PROJECTION proj_by_user;

```

 设计分析:
   ClickHouse 的"索引"与传统数据库完全不同:
   - 主键索引: 稀疏索引（每 8192 行一个索引条目），不是 B+Tree
   - 二级索引: 跳数索引（bloom_filter/minmax/set），用于跳过无关 granule
   - 投影: 类似物化视图但存储在同一表中，查询自动路由

   传统数据库索引定位单行，ClickHouse 索引定位数据块。
   这是列存 + OLAP 的根本设计差异。

## 6. 表级设置修改


修改 MergeTree 设置

```sql
ALTER TABLE users MODIFY SETTING index_granularity = 4096;
ALTER TABLE users MODIFY SETTING merge_with_ttl_timeout = 3600;

```

修改排序键（需要重写全表数据，谨慎使用）

```sql
ALTER TABLE users MODIFY ORDER BY (id, username);

```

修改存储策略

```sql
ALTER TABLE logs MODIFY SETTING storage_policy = 'tiered';

```

重置为默认值

```sql
ALTER TABLE users RESET SETTING index_granularity;

```

重命名表（不通过 ALTER TABLE，用独立语法）

```sql
RENAME TABLE users TO members;

```

## 7. 版本演进与设计启示

19.x:  基本 ALTER TABLE（ADD/DROP/MODIFY COLUMN, 分区操作）
20.4:  RENAME COLUMN（元数据操作，零开销）
20.x:  TTL 分层存储（TO VOLUME / TO DISK）
21.x:  Projection（投影，预聚合加速）
22.x:  轻量级 DELETE（实验性，不通过 mutation）

对引擎开发者的启示:
ClickHouse 的 ALTER TABLE 设计体现了列存 OLAP 引擎的核心哲学:
(1) 列独立存储 → 列级 DDL 天然高效
(2) 数据不可变（append-only + merge）→ 修改通过 mutation 异步执行
(3) 分区是原子操作单位 → 分区操作替代事务
(4) TTL 内置 → 分析数据有生命周期
传统 OLTP 引擎的 ALTER TABLE 优化方向（Online DDL / INSTANT）
在列存引擎中是自然而然的，但 mutation 的异步性质增加了运维复杂度。

