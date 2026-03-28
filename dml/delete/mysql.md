# MySQL: DELETE

> 参考资料:
> - [MySQL 8.0 Reference Manual - DELETE](https://dev.mysql.com/doc/refman/8.0/en/delete.html)
> - [MySQL 8.0 Reference Manual - TRUNCATE TABLE](https://dev.mysql.com/doc/refman/8.0/en/truncate-table.html)
> - [MySQL 8.0 Reference Manual - InnoDB Multi-Versioning](https://dev.mysql.com/doc/refman/8.0/en/innodb-multi-versioning.html)

## 基本语法

基本删除
```sql
DELETE FROM users WHERE username = 'alice';
```

带 LIMIT / ORDER BY（MySQL 特有）
实用场景: 分批删除大表数据，避免长事务和锁等待
```sql
DELETE FROM users WHERE status = 0 ORDER BY created_at LIMIT 100;
```

多表删除（JOIN 语法）
```sql
DELETE u FROM users u
JOIN blacklist b ON u.email = b.email;
```

同时从多个表删除
```sql
DELETE u, o FROM users u
JOIN orders o ON u.id = o.user_id
WHERE u.status = 0;
```

子查询删除
```sql
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);
```

IGNORE（忽略外键约束错误）
```sql
DELETE IGNORE FROM users WHERE id = 1;
```

8.0+: WITH CTE
```sql
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE u FROM users u JOIN inactive i ON u.id = i.id;
```

## DELETE vs TRUNCATE: 内部机制深度对比

### DELETE FROM users; -- 删除所有行

执行过程:
  (1) 逐行扫描聚集索引（全表扫描）
  (2) 每行: 对索引记录加 X 锁（排他锁）
  (3) 每行: 在聚集索引中标记 delete-mark（不立即物理删除）
  (4) 每行: 二级索引记录也标记 delete-mark
  (5) 每行: 写 undo log（旧版本数据，用于回滚和 MVCC）
  (6) 每行: 写 redo log（WAL 保证持久性）
  (7) purge 线程后台清理 delete-marked 记录（物理删除）

结果:
  - 空间不释放给操作系统（表空间碎片，需要 OPTIMIZE TABLE 回收）
  - AUTO_INCREMENT 值不重置
  - 可以回滚（在事务内）
  - 触发 DELETE 触发器
  - binlog 记录每一行的删除（ROW 模式下）
  - 100 万行表: 可能需要几分钟

### TRUNCATE TABLE users;

执行过程:
  (1) 获取 MDL（Metadata Lock）排他锁
  (2) DROP 旧的表空间文件（.ibd）
  (3) 重新创建空的表空间文件
  (4) 重置 AUTO_INCREMENT 计数器

结果:
  - 空间立即释放给操作系统（因为是重建文件）
  - AUTO_INCREMENT 重置为 1
  - 不可回滚（DDL 操作，隐式提交）
  - 不触发 DELETE 触发器
  - binlog 只记录 TRUNCATE 语句（不记录行数据）
  - 100 万行表: 瞬间完成（毫秒级）

### 对比总结表

| 维度           | DELETE                | TRUNCATE              |
|----------------|----------------------|----------------------|
| 类型           | DML（数据操纵）        | DDL（数据定义）        |
| 锁粒度         | 行级锁（逐行加锁）     | 表级 MDL 排他锁       |
| 日志量         | undo + redo 每行      | 仅 DDL 操作日志       |
| 空间回收       | 不回收（碎片）         | 立即回收（重建文件）   |
| 自增重置       | 否                    | 是                    |
| 触发器         | 触发 DELETE 触发器     | 不触发                |
| 事务           | 可回滚                | 不可回滚（隐式提交）   |
| 外键           | 受外键约束检查         | 有外键引用时不允许     |
| WHERE 条件     | 支持                  | 不支持（只能全表清空）  |
| 性能           | O(n) 与行数线性相关   | O(1) 常数时间          |

## DELETE 的内部实现: 标记删除与 purge

### InnoDB 的标记删除机制

InnoDB 的 DELETE 不是物理删除，而是逻辑删除:
  (1) 在记录头的 delete_flag 位设置为 1（标记删除）
  (2) trx_id 更新为当前事务 ID
  (3) 旧版本通过 roll_pointer 链接到 undo log
  (4) 后台 purge 线程检查: 如果没有任何活跃事务需要看到该旧版本，则物理删除

purge 的时机:
  由 innodb_purge_threads 控制并发度（默认 4 个线程）
  purge 延迟会导致: undo log 膨胀、表空间碎片增加、MVCC 版本链变长（查询变慢）

监控 purge 延迟:
  SHOW ENGINE INNODB STATUS;  -- History list length 表示待 purge 的 undo log 页数

### 空间碎片问题

DELETE 大量数据后，表空间不会缩小:
  数据页中出现大量空洞（已删除的行占用的空间）
  后续 INSERT 可以复用这些空间，但无法还给操作系统

解决方案:
  OPTIMIZE TABLE users;   -- 重建表（5.6+ 使用 Online DDL，不完全锁表）
  ALTER TABLE users ENGINE=InnoDB;  -- 等价于 OPTIMIZE TABLE（重建聚集索引）
> **注意**: 重建表需要额外的磁盘空间（约原表大小），大表需要评估

## 大表删除的性能问题和解决方案

> **问题**: DELETE FROM big_table WHERE created_at < '2020-01-01';
假设匹配 5000 万行:
  (1) 持有行锁 5000 万个 → 锁管理内存膨胀
  (2) undo log 记录 5000 万行旧数据 → undo 表空间暴涨
  (3) binlog 生成 5000 万行删除事件 → 复制延迟
  (4) 长事务持有锁 → 阻塞其他 DML → 业务超时

解决方案 A: 分批删除（最常用）
每次删除一批，独立事务，给并发留窗口
REPEAT:
```sql
DELETE FROM big_table WHERE created_at < '2020-01-01' ORDER BY id LIMIT 10000;
```

直到 ROW_COUNT() = 0

解决方案 B: 分区表 + DROP PARTITION（最优方案）
如果表按时间分区:
```sql
ALTER TABLE big_table DROP PARTITION p2019;
```

瞬间完成（等同于 TRUNCATE），无 undo/redo 开销，无行锁
这是大表数据清理的最佳实践: 在表设计阶段就用时间分区

解决方案 C: RENAME + 新建（适用于删除大部分数据的场景）
当需要保留少量数据、删除大部分数据时:
(1) CREATE TABLE users_new LIKE users;
(2) INSERT INTO users_new SELECT * FROM users WHERE created_at >= '2020-01-01';
(3) RENAME TABLE users TO users_old, users_new TO users;
(4) DROP TABLE users_old;
优点: 避免大量 DELETE 的锁和日志开销
缺点: RENAME 期间有短暂的表不可用窗口

解决方案 D: pt-archiver（Percona 工具）
pt-archiver --source=h=localhost,D=mydb,t=big_table --where='created_at < "2020-01-01"'
            --limit=1000 --commit-each --progress=1000
自动分批删除，支持限速、进度显示、归档到另一张表

## 横向对比: 各引擎的 DELETE 实现策略

### 标记删除 + purge（MVCC 引擎的主流方案）

MySQL InnoDB:
  delete-mark + purge 线程异步清理
  旧版本在 undo log 中，purge 延迟影响查询性能
PostgreSQL:
  标记 dead tuple（xmax 字段）+ VACUUM 清理
  无 undo log（旧版本直接留在数据页中），VACUUM 不及时会导致表膨胀
  autovacuum 是 PG 运维的核心（参数调优: autovacuum_vacuum_threshold 等）
InnoDB vs PG 的关键区别:
  InnoDB: 旧版本在 undo log（独立空间），数据页保持紧凑
  PG:     旧版本在原页面中（in-page），数据页会膨胀
  PG 的方案更简单但需要 VACUUM；InnoDB 不需要 VACUUM 但 undo log 管理更复杂

### 不可变数据 + Compaction（LSM-Tree 和列式引擎）

ClickHouse:
  DELETE = ALTER TABLE ... DELETE WHERE ...（异步 mutation）
  实际过程: 读旧 part → 过滤掉被删除的行 → 写新 part → 删旧 part
  DELETE 不是"删除数据"而是"重写数据"，代价很高（整个 part 重写）
  8.0 的 lightweight delete: 只写删除掩码位图（_row_exists 列），查询时过滤
  适用: 偶尔删除（如 GDPR 合规），不适合频繁删除
RocksDB (MyRocks):
  DELETE = 写入一条 tombstone 记录（墓碑标记）
  读取时跳过有 tombstone 的 key，后台 Compaction 时物理清除
  tombstone 堆积会降低读取性能（range scan 要跳过大量墓碑）

### 段级操作（传统 RDBMS 的 TRUNCATE 方案）

Oracle:
  DELETE: 与 MySQL 类似的标记删除 + undo，由 SMON 进程清理
  TRUNCATE: 直接释放 segment 的 extent，HWM（High Water Mark）重置
  Oracle 独有: TRUNCATE ... REUSE STORAGE（释放数据但保留预分配空间）
SQL Server:
  DELETE: 标记删除 + ghost cleanup 后台线程清理
  TRUNCATE: 解除页分配（deallocation），不删除物理页

### Hive/Spark（不可变文件语义）

  传统 Hive: 不支持 DELETE（只能 INSERT OVERWRITE 重写分区）
  Hive ACID (3.0+): 支持 DELETE，实现为写 delta 文件（类似 tombstone）
  Delta Lake / Iceberg: DELETE 通过重写 Parquet 文件实现（Copy-on-Write）
                       或通过位图标记（Merge-on-Read）

## 对引擎开发者: DELETE 实现的设计决策

决策 1: 标记删除 vs 物理删除
  标记删除（推荐）: 对 MVCC 友好，支持事务回滚，但需要后台清理机制
  物理删除: 实现简单，但不支持 MVCC，不能回滚
  几乎所有现代引擎都选择标记删除 + 后台清理

决策 2: 旧版本存储位置
  undo log（独立空间）: InnoDB、Oracle → 数据页紧凑，undo 可独立管理
  原页面（in-place）:   PostgreSQL → 实现简单，但需要 VACUUM
  追加日志:             LSM-Tree 引擎 → 天然支持，tombstone 在 Compaction 时清理

决策 3: 空间回收时机
  即时回收: TRUNCATE 式操作（段级释放）
  后台回收: purge/VACUUM/Compaction（行级清理）
  手动回收: OPTIMIZE TABLE / pg_repack（重建表）
  引擎需要同时支持这三种方式，适应不同场景

决策 4: 大批量删除的优化
  如果引擎支持分区，DROP PARTITION 是最优方案（O(1) 操作）
  如果不支持分区，应提供分批删除的机制（如 MySQL 的 DELETE ... LIMIT）
  分析型引擎应考虑: 通过重写文件而非逐行删除来实现大批量清理

## 版本演进

MySQL 5.0:   多表 DELETE 语法（DELETE t1, t2 FROM t1 JOIN t2 ...）
MySQL 5.1:   分区表 TRUNCATE PARTITION（5.1 只支持 DROP PARTITION）
MySQL 5.6:   TRUNCATE PARTITION 正式支持
MySQL 8.0:   CTE + DELETE 支持（WITH ... DELETE）
MySQL 8.0:   原子 DDL 使 TRUNCATE 在 crash 时安全（不会出现半完成状态）
