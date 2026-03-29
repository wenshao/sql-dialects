# 事务隔离级别实际行为：各 SQL 方言全对比

> 参考资料:
> - [MySQL 8.0 - Transaction Isolation Levels](https://dev.mysql.com/doc/refman/8.0/en/innodb-transaction-isolation-levels.html)
> - [PostgreSQL - Transaction Isolation](https://www.postgresql.org/docs/current/transaction-iso.html)
> - [SQL Server - Transaction Isolation Levels](https://learn.microsoft.com/en-us/sql/t-sql/statements/set-transaction-isolation-level-transact-sql)
> - [A Critique of ANSI SQL Isolation Levels (Berenson et al., 1995)](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/tr-95-51.pdf)

SQL 标准定义了四个隔离级别，但几乎没有一个引擎完全按标准实现。有的引擎将 SERIALIZABLE 映射到 Snapshot Isolation，有的引擎的 REPEATABLE READ 实际上比标准更强或更弱。本文逐引擎梳理真实行为，重点标注那些"名字相同、语义不同"的陷阱。

## SQL 标准定义回顾

```
SQL:1992 四个隔离级别 (由低到高):

  READ UNCOMMITTED (RU)
    允许脏读: 能看到其他事务未提交的修改
    极少使用, 仅用于特殊监控场景

  READ COMMITTED (RC)
    禁止脏读: 只能看到已提交的数据
    但同一事务中两次读可能结果不同 (Non-Repeatable Read)

  REPEATABLE READ (RR)
    禁止脏读 + 不可重复读
    但可能出现幻读 (Phantom Read): 新插入的行在第二次查询中出现

  SERIALIZABLE
    最高级别: 事务结果等价于某种串行执行顺序
    禁止所有异常, 包括幻读

注意: SQL 标准只定义了"禁止哪些异常",
      没有规定实现方式 (锁 / MVCC / SSI 都可以)
```

## 支持的隔离级别矩阵

```
引擎               RU    RC    RR    SERIALIZABLE  默认级别       备注
─────────────────  ────  ────  ────  ────────────  ───────────  ─────────────────────────────
MySQL (InnoDB)     ✓     ✓     ✓     ✓             RR           RR 含 gap lock, 比标准更强
PostgreSQL         ✓(1)  ✓     ✓(2)  ✓             RC           9.1+ SSI 真正可串行化
Oracle             ✗     ✓     ✗     ✓(3)          RC           SERIALIZABLE 实际是 SI
SQL Server         ✓     ✓     ✓     ✓             RC           可选 RCSI / SI (需数据库选项)
SQLite             ✗     ✗     ✗     ✓             SERIALIZABLE WAL 模式下有 RC 语义
MariaDB            ✓     ✓     ✓     ✓             RR           与 MySQL 行为基本一致

TiDB               ✗     ✓(4)  ✓(5)  ✗(6)          RR (SI)      RR = SI, 无 gap lock
CockroachDB        ✗     ✓(7)  ✗     ✓             SERIALIZABLE SSI 实现, RC 自 v23.1 可选
OceanBase          ✓     ✓     ✓     ✓             RC           两种模式默认均为 RC（与原生 MySQL 的 RR 不同！）
YugabyteDB         ✗     ✓     ✓(8)  ✓             RR (SI)      SERIALIZABLE = SSI

Snowflake          ✗     ✓     ✗     ✗             RC           SI 实现; 无用户可选隔离级别
BigQuery           ✗     ✗     ✗     ✓(9)          SERIALIZABLE 每个查询/DML 自动快照隔离
Redshift           ✗     ✗     ✗     ✓             SERIALIZABLE 真正可串行化 (SSI)
DuckDB             ✗     ✗     ✗     ✗             SNAPSHOT     单写者模型, 无冲突
ClickHouse         ✗     ✗     ✗     ✗             N/A          无传统事务; 单语句原子性
Hive               ✗     ✗     ✗     ✗             N/A          ACID 仅 transactional 表, 仅 SI
Spark SQL          ✗     ✗     ✗     ✗             N/A          依赖 Delta Lake / Iceberg

注:
(1) PG 的 RU 行为等同于 RC, 不会真正脏读
(2) PG 的 RR 实际是 Snapshot Isolation
(3) Oracle 的 SERIALIZABLE 实际是 Snapshot Isolation, 不防止 write skew
(4) TiDB RC 使用 Percolator 模型, 行为接近标准 RC
(5) TiDB RR = Snapshot Isolation, 与 MySQL RR (gap lock) 语义不同
(6) TiDB 接受 SET TRANSACTION ISOLATION LEVEL SERIALIZABLE 但映射到 RR (SI)
(7) CockroachDB RC 自 v23.1 起可选, 需 SET default_transaction_isolation
(8) YugabyteDB RR 基于 Snapshot Isolation
(9) BigQuery 多语句事务使用 snapshot isolation + 提交时冲突检测
```

## 异常防护矩阵

### 异常类型定义

```
脏读 (Dirty Read):
  T1 修改了行 R, T2 在 T1 提交前读到了该修改
  T1 随后回滚 -> T2 读到了从未存在的数据

不可重复读 (Non-Repeatable Read):
  T1 读取行 R, T2 修改并提交行 R, T1 再次读取行 R -> 结果不同

幻读 (Phantom Read):
  T1 按条件查询得到 N 行, T2 插入满足条件的新行并提交
  T1 再次相同条件查询 -> 得到 N+1 行

丢失更新 (Lost Update):
  T1 和 T2 都读取行 R, 然后各自基于读到的值更新 R
  后提交的覆盖先提交的 -> 一个更新丢失

写偏斜 (Write Skew):
  T1 读 X,Y 并基于 X+Y 的约束修改 X
  T2 读 X,Y 并基于 X+Y 的约束修改 Y
  两个事务各自不违反约束, 合在一起违反了

  经典例子: 值班表要求至少 1 人在岗
    T1: 看到 A=在岗, B=在岗 -> 把 A 改为离岗 (还有 B)
    T2: 看到 A=在岗, B=在岗 -> 把 B 改为离岗 (还有 A)
    结果: A=离岗, B=离岗, 无人在岗
```

### 各引擎 READ COMMITTED 异常防护

```
引擎               脏读    不可重复读  幻读    丢失更新  写偏斜
─────────────────  ──────  ──────────  ──────  ────────  ──────
MySQL (InnoDB)     防止    ✗ 不防止   ✗       ✗         ✗
PostgreSQL         防止    ✗ 不防止   ✗       ✗         ✗
Oracle             防止    ✗ 不防止   ✗       ✗         ✗
SQL Server (锁RC)  防止    ✗ 不防止   ✗       ✗         ✗
SQL Server (RCSI)  防止    ✗ 不防止   ✗       防止(1)   ✗
TiDB               防止    ✗ 不防止   ✗       ✗         ✗
CockroachDB        防止    ✗ 不防止   ✗       ✗         ✗
OceanBase          防止    ✗ 不防止   ✗       ✗         ✗

注:
(1) SQL Server RCSI 在 UPDATE 时使用"更新冲突检测",
    如果读到的版本已被其他事务修改, 则重新读取最新版本
    这在某些场景下可避免丢失更新
```

### 各引擎 REPEATABLE READ / Snapshot Isolation 异常防护

```
引擎               脏读    不可重复读  幻读      丢失更新    写偏斜
─────────────────  ──────  ──────────  ────────  ──────────  ──────────
MySQL (InnoDB)     防止    防止        防止(1)   ✗ 不防止(2) ✗ 不防止
PostgreSQL RR      防止    防止        防止(3)   防止(3)     ✗ 不防止
Oracle             (无 RR 级别, 见下方 SERIALIZABLE)
SQL Server SI      防止    防止        防止(4)   防止(4)     ✗ 不防止
TiDB RR            防止    防止        防止(5)   防止(5)     ✗ 不防止
OceanBase RR       防止    防止        防止      防止        ✗ 不防止
YugabyteDB RR      防止    防止        防止      防止        ✗ 不防止
MariaDB RR         防止    防止        防止(1)   ✗ 不防止(2) ✗ 不防止

注:
(1) MySQL/MariaDB 的 RR 通过 gap lock 防止幻读:
    SELECT 时通过 MVCC 快照读不见新插入行 (快照级别防护)
    UPDATE/DELETE/SELECT FOR UPDATE 时加 gap lock 阻止插入 (锁级别防护)
    这比标准 RR 更强, 但 gap lock 有死锁风险

(2) MySQL/MariaDB 的 RR 默认（快照读）**不防止**丢失更新:
    普通 SELECT 后并发 UPDATE, 后执行者覆盖前者的修改 (read-modify-write 丢失)
    只有显式 SELECT ... FOR UPDATE 加排他锁才能防止
    对比 PostgreSQL RR: 自动检测并发更新并报错回滚 (首个更新者胜出)
    这是 DDIA 中强调的经典差异, 也是 MySQL → PG 迁移的重要陷阱

(3) PostgreSQL 的 RR (Snapshot Isolation):
    通过"首个更新者胜出"规则防止丢失更新:
    如果 T2 要更新的行已被 T1 修改并提交, T2 会收到序列化错误并回滚
    幻读在快照级别自动防止 (读的是一致快照)

(4) SQL Server 的 SI (需启用 ALLOW_SNAPSHOT_ISOLATION):
    行为类似 PostgreSQL 的 RR, 使用行版本控制
    冲突时报错: "Snapshot isolation transaction aborted due to update conflict"

(5) TiDB 的 RR 就是 Snapshot Isolation:
    使用 Percolator 分布式事务模型
    冲突检测: 写写冲突时后提交者报错回滚
    但无 gap lock -> 与 MySQL RR 行为不同

    关键差异:
    MySQL RR: SELECT ... FOR UPDATE 加 gap lock, 阻止其他事务在范围内插入
    TiDB RR: 无 gap lock, SELECT ... FOR UPDATE 只锁定已存在的行
    -> 依赖 gap lock 防止幻读的应用迁移到 TiDB 时可能出错
```

### 各引擎 SERIALIZABLE 异常防护

```
引擎               脏读  不可重复读  幻读  丢失更新  写偏斜     实际机制
─────────────────  ────  ──────────  ────  ────────  ─────────  ──────────────────
MySQL (InnoDB)     防止  防止        防止  防止      防止       所有 SELECT 自动加 LOCK IN SHARE MODE
                                                               通过锁实现, 并发度极低
PostgreSQL 9.1+    防止  防止        防止  防止      防止       SSI (Serializable Snapshot Isolation)
                                                               乐观并发, 提交时检测冲突
SQL Server         防止  防止        防止  防止      防止       范围锁 (range lock)
                                                               锁定键范围防止幻读
Oracle ⚠️          防止  防止        防止  防止      ✗ 不防止   Snapshot Isolation, 不是真 SERIALIZABLE
                                                               write skew 不会被检测到
CockroachDB        防止  防止        防止  防止      防止       SSI 实现, 真正可串行化
                                                               分布式时钟 + 冲突检测
Redshift           防止  防止        防止  防止      防止       SSI, 串行化快照隔离
SQLite             防止  防止        防止  防止      防止       单写者锁, 天然串行化
YugabyteDB         防止  防止        防止  防止      防止       SSI, 基于 Raft 的分布式实现

TiDB ⚠️            (SERIALIZABLE 语法接受但映射到 RR/SI)
                   防止  防止        防止  防止      ✗ 不防止   实际运行 Snapshot Isolation
                                                               SET TRANSACTION ISOLATION LEVEL SERIALIZABLE
                                                               不报错但不提供 SERIALIZABLE 语义
```

### 五大关键陷阱

```
陷阱 1: TiDB RR ≠ MySQL RR
────────────────────────────
  MySQL RR: gap lock 防止幻读 (当前读场景)
  TiDB RR: Snapshot Isolation, 无 gap lock
  影响: 依赖 SELECT ... FOR UPDATE 锁定范围来防止插入的应用
        在 TiDB 上会出现幻读

  示例:
    -- MySQL: 下面的 FOR UPDATE 锁定 account_id=1 的索引范围
    SELECT * FROM orders WHERE account_id = 1 FOR UPDATE;
    -- 其他事务无法插入 account_id = 1 的新行 (被 gap lock 阻塞)

    -- TiDB: 只锁定已存在的行, 不阻止新插入
    SELECT * FROM orders WHERE account_id = 1 FOR UPDATE;
    -- 其他事务可以插入 account_id = 1 的新行 (无 gap lock)

陷阱 2: Oracle SERIALIZABLE ≠ 真正 SERIALIZABLE
─────────────────────────────────────────────────
  Oracle 的 SERIALIZABLE 实际是 Snapshot Isolation
  不检测 write skew 异常
  应用如果依赖 SERIALIZABLE 防止 write skew, 在 Oracle 上会出错

  示例 (值班表):
    -- T1: 看到 doctor_a=on_call, doctor_b=on_call
    UPDATE schedule SET status='off_call' WHERE doctor='A';
    -- T2: 也看到 doctor_a=on_call, doctor_b=on_call
    UPDATE schedule SET status='off_call' WHERE doctor='B';
    -- 两个事务都提交成功
    -- 结果: 无人值班 -> 违反业务约束
    -- 在 PostgreSQL SSI 下: T2 会被回滚

陷阱 3: SQL Server 默认 RC 使用锁, 不是 MVCC
──────────────────────────────────────────────
  SQL Server 的 READ COMMITTED 默认使用共享锁:
    SELECT 时加共享锁, 读完释放 -> 阻塞写操作
    与 PostgreSQL/Oracle 的 RC (基于 MVCC, 读不阻塞写) 行为不同

  启用 RCSI (Read Committed Snapshot Isolation):
    ALTER DATABASE mydb SET READ_COMMITTED_SNAPSHOT ON;
    此后 RC 使用行版本控制 (row versioning), 读不阻塞写
    Azure SQL Database 默认已启用 RCSI

  影响:
    从 PostgreSQL/Oracle 迁移到 SQL Server 但未启用 RCSI
    -> 并发性能大幅下降 (读写互相阻塞)
    -> 更多死锁

陷阱 4: CockroachDB SERIALIZABLE 是真正可串行化
────────────────────────────────────────────────
  CockroachDB 只支持 SERIALIZABLE (v23.1 前)
  使用 SSI (Serializable Snapshot Isolation)
  分布式环境下的真正可串行化, 代价是:
    - 读写冲突时事务自动重试 (客户端需正确处理)
    - 高争用场景下重试频率可能很高
    - 需要幂等的事务逻辑

  v23.1+ 引入 RC 级别:
    SET default_transaction_isolation = 'read committed';
    适用于可以接受较弱隔离的高吞吐场景

陷阱 5: PostgreSQL SSI 是真正可串行化的黄金标准
───────────────────────────────────────────────
  PostgreSQL 9.1+ 的 SERIALIZABLE 使用 SSI 算法
  乐观并发控制: 不加额外锁, 事务正常执行
  提交时检测是否存在"危险结构" (rw-antidependency cycle)
  如果检测到, 回滚其中一个事务

  优点: 读不阻塞写, 并发度高
  代价: 可能有 false positive (不必要的回滚)
  要求: 应用必须正确重试被回滚的事务
```

## MVCC 实现对比表

```
引擎              版本存储方式         GC 机制                读时开销           写时开销
────────────────  ──────────────────  ────────────────────  ─────────────────  ──────────────────
MySQL (InnoDB)    Undo log (回滚段)   Purge 线程异步清理    沿 undo 链回溯     写 undo log
                  数据页只存最新版本   长事务阻塞 purge      长链路慢            + 修改数据页

PostgreSQL        元组版本 (堆内)     VACUUM 进程回收       直接读取可见版本   插入新元组
                  旧版本在同一个表中   Autovacuum 自动触发   索引可能指旧版本   + 标记旧版本死亡
                  HOT update 优化     不 vacuum -> 表膨胀   HOT 减少索引更新

Oracle            Undo 表空间         自动 Undo 管理        沿 undo 链回溯     写 undo
                  数据块只存最新版本   UNDO_RETENTION 参数   ORA-01555 风险     + 修改数据块
                  一致读重建旧版本     undo 空间不足->快照   (undo 被覆盖时)
                                      太老报错

SQL Server        tempdb 版本存储     自动清理              读版本存储中的      写版本到 tempdb
(SI/RCSI 启用时)   行版本链在 tempdb   最短活跃事务决定      对应版本           + 修改数据页
                  数据页存最新版本     清理边界              tempdb 可能成为     ADR(加速恢复)
                                                            性能瓶颈            可改用持久化版本存储

TiDB              Percolator 模型     GC worker             根据 start_ts      写入 TiKV
                  数据存 TiKV          GC safe point         读取对应版本       Prewrite + Commit
                  多版本按 timestamp   默认 10 分钟          分布式读可能       两阶段提交
                  存储在 RocksDB       gc_life_time 可配置   涉及多个 Region

CockroachDB       MVCC in Pebble      GC TTL (默认 25h)     时间戳比较确定     MVCC put
                  KV 层多版本存储      保护区配置 GC 策略     可见版本           + 写意图 (intent)
                  按时间戳排序         zone config 设 TTL    不确定读 (读锁)    intent 解析

Snowflake         微分区 (文件)        Time Travel 保留      读取对应时间点      写入新微分区
                  每次写生成新文件      1-90 天可配置         的微分区文件        (Copy-on-Write)
                  不可变存储            Fail-safe 额外 7 天   文件级粒度          无行级版本

Hive (ACID)       Delta 文件           Compaction            合并 base +         追加 delta 文件
                  base + delta 结构    Minor: 合并 delta     delta 文件          Minor/Major
                  ORC 事务表           Major: 合并到 base    读放大问题          Compaction

DuckDB            内存行组版本         自动                  单写者模型          WAL + 检查点
                  WAL + 检查点         检查点时合并          读快照一致          单个写事务
```

## Autocommit 与 DDL 行为

### Autocommit 默认行为

```
引擎               默认 Autocommit    说明
─────────────────  ────────────────  ──────────────────────────────────
MySQL              ON                每条语句自动提交; START TRANSACTION 开启显式事务
PostgreSQL         ON                同 MySQL; 也支持 BEGIN 开启事务
Oracle             OFF               每条 DML 不自动提交, 需显式 COMMIT
                                     但 DDL 会隐式提交
SQL Server         ON                每条语句自动提交; BEGIN TRANSACTION 开启显式事务
                                     IMPLICIT_TRANSACTIONS ON 可改为 Oracle 行为
SQLite             ON                每条语句自动提交

TiDB               ON                与 MySQL 一致
CockroachDB        ON                与 PostgreSQL 一致
OceanBase          ON (MySQL模式)     MySQL 模式同 MySQL; Oracle 模式同 Oracle
                   OFF (Oracle模式)

Snowflake          ON                每条语句自动提交; BEGIN 开启多语句事务
BigQuery           ON                每条语句自动提交; 多语句事务需 BEGIN TRANSACTION
Redshift           ON                与 PostgreSQL 一致
DuckDB             ON                每条语句自动提交
ClickHouse         ON                无传统事务, 每条语句原子
Hive               N/A               无交互式事务控制
Spark SQL          N/A               无交互式事务控制
```

### DDL 隐式提交与事务回滚

```
引擎               DDL 隐式提交?      DDL 可回滚?     说明
─────────────────  ────────────────  ──────────────  ─────────────────────────────
MySQL              ✓ 是              ✗ 不可回滚     CREATE/ALTER/DROP 前后隐式 COMMIT
                                                     正在进行的事务被强制提交
MariaDB            ✓ 是              ✗ 不可回滚     同 MySQL
Oracle             ✓ 是              ✗ 不可回滚     DDL 前后隐式 COMMIT
                                                     ALTER TABLE 失败也会提交之前的 DML
TiDB               ✓ 是              ✗ 不可回滚     与 MySQL 保持一致

PostgreSQL         ✗ 否              ✓ 可回滚       事务 DDL: DDL 在事务中可以回滚
                                                     CREATE TABLE + INSERT 可以一起回滚
                                                     极少数例外: CREATE DATABASE, CREATE TABLESPACE
SQL Server         ✗ 否              ✓ 可回滚       事务 DDL: DDL 在事务中可以回滚
                                                     部分 DDL 例外 (ALTER DATABASE 等)
CockroachDB        ✗ 否              ✓ 可回滚       事务 DDL: 同 PostgreSQL
SQLite             ✗ 否              ✓ 可回滚       事务 DDL: DDL 在事务中可以回滚

Redshift           ✗ 否              ✓ 可回滚       事务 DDL: 同 PostgreSQL
DuckDB             ✗ 否              ✓ 可回滚       事务 DDL: DDL 在事务中可以回滚

OceanBase          ✓ (两种模式)      ✗ 不可回滚     MySQL 模式: 隐式 COMMIT; Oracle 模式: 隐式 COMMIT

Snowflake          ✓ 是              ✗ 不可回滚     DDL 自动提交, 不参与多语句事务
BigQuery           N/A               N/A             DDL 不参与事务
ClickHouse         N/A               N/A             无事务 DDL
Hive               N/A               N/A             DDL 独立于 ACID 事务
Spark SQL          N/A               N/A             DDL 独立执行

支持事务 DDL 的引擎 (可在事务中回滚 DDL):
  PostgreSQL, SQL Server, CockroachDB, SQLite, Redshift, DuckDB

不支持事务 DDL 的引擎 (DDL 隐式提交):
  MySQL, MariaDB, Oracle, TiDB, OceanBase, Snowflake
```

### 事务 DDL 的实际应用

```sql
-- PostgreSQL: 安全的 schema 迁移
BEGIN;
  CREATE TABLE orders_new (LIKE orders INCLUDING ALL);
  ALTER TABLE orders_new ADD COLUMN region TEXT;
  INSERT INTO orders_new SELECT *, 'unknown' FROM orders;
  ALTER TABLE orders RENAME TO orders_old;
  ALTER TABLE orders_new RENAME TO orders;
  -- 如果任何步骤出错, 整个迁移回滚
COMMIT;

-- MySQL: 无法这样做, 每个 DDL 隐式提交
-- 需要额外的迁移工具 (pt-online-schema-change, gh-ost)

-- SQL Server: 类似 PostgreSQL
BEGIN TRANSACTION;
  CREATE TABLE orders_new (...);
  -- ... 数据迁移 ...
  EXEC sp_rename 'orders', 'orders_old';
  EXEC sp_rename 'orders_new', 'orders';
COMMIT;
```

## SELECT FOR UPDATE 支持

### 语法对比

```
引擎               FOR UPDATE   FOR SHARE     NOWAIT        SKIP LOCKED    特殊语法
─────────────────  ──────────   ──────────    ────────────  ─────────────  ─────────────────────
MySQL (InnoDB)     ✓            ✓(1)          ✓ (8.0+)     ✓ (8.0+)       FOR UPDATE OF tbl (8.0+)
PostgreSQL         ✓            ✓             ✓            ✓              FOR KEY SHARE
                                                                           FOR NO KEY UPDATE
Oracle             ✓            ✗             ✓            ✓ (11g+)       FOR UPDATE OF column
SQL Server         ✗(2)         ✗(2)          ✗(2)         ✗(2)           WITH (UPDLOCK, ROWLOCK)
                                                                           WITH (HOLDLOCK)
                                                                           WITH (READPAST)(3)
MariaDB            ✓            ✓             ✓ (10.3+)    ✓ (10.6+)
SQLite             ✗            ✗             ✗            ✗              无行级锁

TiDB               ✓            ✓             ✓            ✓ (6.6+)       FOR UPDATE 悲观锁
CockroachDB        ✓            ✓             ✓            ✗              FOR UPDATE 获取排他锁
OceanBase          ✓            ✓             ✓            ✓
YugabyteDB         ✓            ✓             ✓            ✓

Snowflake          ✗            ✗             ✗            ✗              无行级锁
BigQuery           ✗            ✗             ✗            ✗              无行级锁
Redshift           ✗            ✗             ✗            ✗              无行级锁
DuckDB             ✗            ✗             ✗            ✗              无行级锁
ClickHouse         ✗            ✗             ✗            ✗              无行级锁
Hive               ✗            ✗             ✗            ✗              无行级锁

注:
(1) MySQL 8.0 前使用 LOCK IN SHARE MODE, 8.0+ 改为 FOR SHARE (兼容旧语法)
(2) SQL Server 使用表提示 (table hint) 代替 FOR UPDATE 语法
(3) SQL Server WITH (READPAST) 等价于 SKIP LOCKED
(4) TiDB 悲观模式下支持 NOWAIT；SKIP LOCKED 自 v6.6.0 起支持
```

### SQL Server 锁提示对照

```sql
-- 其他引擎                          -- SQL Server 等价写法
SELECT * FROM orders               SELECT * FROM orders
  WHERE id = 1                       WITH (UPDLOCK, ROWLOCK)
  FOR UPDATE;                        WHERE id = 1;

SELECT * FROM orders               SELECT * FROM orders
  WHERE id = 1                       WITH (HOLDLOCK, ROWLOCK)
  FOR SHARE;                         WHERE id = 1;

SELECT * FROM orders               SELECT * FROM orders
  WHERE id = 1                       WITH (UPDLOCK, ROWLOCK, NOWAIT)
  FOR UPDATE NOWAIT;                 WHERE id = 1;
                                     -- 实际上 SQL Server 没有精确的 NOWAIT
                                     -- 需设 SET LOCK_TIMEOUT 0

SELECT * FROM orders               SELECT * FROM orders
  WHERE status = 'pending'           WITH (UPDLOCK, ROWLOCK, READPAST)
  FOR UPDATE SKIP LOCKED             WHERE status = 'pending';
  LIMIT 1;
```

### SKIP LOCKED 典型应用: 任务队列

```sql
-- PostgreSQL / MySQL 8.0+ / Oracle 11g+
-- 多个 worker 并发获取任务, 互不阻塞

BEGIN;
SELECT id, payload
  FROM task_queue
  WHERE status = 'pending'
  ORDER BY created_at
  FOR UPDATE SKIP LOCKED
  LIMIT 1;

-- 处理任务...
UPDATE task_queue SET status = 'processing' WHERE id = :id;
COMMIT;

-- SQL Server 等价
BEGIN TRANSACTION;
SELECT TOP 1 id, payload
  FROM task_queue WITH (UPDLOCK, ROWLOCK, READPAST)
  WHERE status = 'pending'
  ORDER BY created_at;

UPDATE task_queue SET status = 'processing' WHERE id = @id;
COMMIT;

-- 不支持 SKIP LOCKED 的引擎 (如 Snowflake, BigQuery):
-- 使用应用层队列 (SQS, Kafka, Pub/Sub) 代替数据库队列
```

## 隔离级别设置语法

```sql
-- 标准语法 (MySQL, PostgreSQL, SQL Server, Oracle)
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- MySQL / TiDB: 会话级别
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
-- MySQL 8.0+:
SET @@transaction_isolation = 'REPEATABLE-READ';

-- PostgreSQL: 事务级别 (只在事务开始后有效)
BEGIN;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- 或: BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- SQL Server: 启用 Snapshot Isolation (数据库级别)
ALTER DATABASE mydb SET ALLOW_SNAPSHOT_ISOLATION ON;
-- 然后在事务中使用:
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;

-- SQL Server: 启用 RCSI (数据库级别, 影响所有 RC 事务)
ALTER DATABASE mydb SET READ_COMMITTED_SNAPSHOT ON;

-- Oracle: 只有 RC 和 SERIALIZABLE
ALTER SESSION SET ISOLATION_LEVEL = SERIALIZABLE;

-- CockroachDB
SET default_transaction_isolation = 'serializable';  -- 默认且唯一 (v23.1 前)
SET default_transaction_isolation = 'read committed'; -- v23.1+

-- Snowflake: 无法更改, 固定为 RC (SI 实现)
```

## 选型建议

```
场景                           推荐隔离级别        推荐引擎特性
───────────────────────────  ─────────────────  ─────────────────────────
金融交易 (强一致性)            SERIALIZABLE       PG SSI / CockroachDB SSI
  需要防止 write skew          ⚠️ 不要用 Oracle    必须正确处理重试
  需要所有异常都被防止          SERIALIZABLE

高并发 OLTP (读多写少)        READ COMMITTED     PG RC / SQL Server RCSI
  可接受不可重复读              + 应用层防护        MVCC 避免读写阻塞
  对性能要求高

高并发 OLTP (需快照一致)      REPEATABLE READ    MySQL RR / PG RR
  报表查询需要一致快照          或 Snapshot         SQL Server SI
  单个事务内多次读要一致        Isolation

分布式 NewSQL                 取决于引擎          CockroachDB: SERIALIZABLE 默认
  跨节点事务                                       TiDB: RR (SI), 注意与 MySQL 差异
  需要水平扩展                                     YugabyteDB: RR (SI) 或 SERIALIZABLE

分析型查询                    引擎默认即可         Snowflake: 自动 SI
  长时间运行的查询                                  BigQuery: 自动快照
  无并发写入争用                                    Redshift: 自动 SERIALIZABLE

嵌入式 / 单机                 SERIALIZABLE       SQLite: 天然串行化
  单个应用独占数据库                                DuckDB: 单写者快照
```
