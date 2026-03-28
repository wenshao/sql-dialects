# MySQL: 触发器

> 参考资料:
> - [MySQL 8.0 Reference Manual - CREATE TRIGGER](https://dev.mysql.com/doc/refman/8.0/en/create-trigger.html)
> - [MySQL 8.0 Reference Manual - Trigger Syntax and Examples](https://dev.mysql.com/doc/refman/8.0/en/trigger-syntax.html)
> - [MySQL 8.0 Reference Manual - Trigger Restrictions](https://dev.mysql.com/doc/refman/8.0/en/stored-program-restrictions.html)

## 基本语法

BEFORE INSERT: 数据规范化
```sql
DELIMITER //
CREATE TRIGGER trg_users_before_insert
BEFORE INSERT ON users
FOR EACH ROW
BEGIN
    SET NEW.created_at = NOW();
    SET NEW.updated_at = NOW();
    SET NEW.username = LOWER(NEW.username);
END //
DELIMITER ;
```

AFTER INSERT: 审计日志
```sql
DELIMITER //
CREATE TRIGGER trg_users_after_insert
AFTER INSERT ON users
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, action, record_id, created_at)
    VALUES ('users', 'INSERT', NEW.id, NOW());
END //
DELIMITER ;
```

BEFORE UPDATE: 自动更新时间戳
```sql
DELIMITER //
CREATE TRIGGER trg_users_before_update
BEFORE UPDATE ON users
FOR EACH ROW
BEGIN
    SET NEW.updated_at = NOW();
END //
DELIMITER ;
```

AFTER DELETE: 删除审计
```sql
DELIMITER //
CREATE TRIGGER trg_users_after_delete
AFTER DELETE ON users
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, action, record_id, old_data, created_at)
    VALUES ('users', 'DELETE', OLD.id, JSON_OBJECT('username', OLD.username), NOW());
END //
DELIMITER ;
```

5.7.2+: 同一表同一事件可以有多个触发器，使用 FOLLOWS/PRECEDES 控制顺序
```sql
DELIMITER //
CREATE TRIGGER trg_audit_extra AFTER INSERT ON users
FOR EACH ROW FOLLOWS trg_users_after_insert   -- 在 trg_users_after_insert 之后执行
BEGIN
    -- 额外的审计逻辑
END //
DELIMITER ;
```

删除触发器
```sql
DROP TRIGGER IF EXISTS trg_users_before_insert;
```

查看触发器
```sql
SHOW TRIGGERS;
SELECT * FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = DATABASE();
```

## 触发器的执行时机和锁影响（对 SQL 引擎开发者）

### 执行语义

MySQL 触发器是行级触发器（FOR EACH ROW），不支持语句级触发器
执行在同一事务中: INSERT 一行 -> BEFORE 触发器 -> 写入行 -> AFTER 触发器
如果触发器失败（SIGNAL/错误），整个 DML 语句回滚

关键行为:
  a. BEFORE 触发器可以修改 NEW 值（数据规范化的唯一手段，因为 MySQL 没有 Generated Column + 函数）
  b. AFTER 触发器不能修改 NEW（行已经写入）
  c. 触发器不能使用事务控制语句（COMMIT/ROLLBACK/SAVEPOINT）
  d. 触发器中的 DML 可以再次触发其他表的触发器（级联触发），但不能触发自身表的触发器

### 锁影响

触发器在 DML 语句的锁范围内执行:
  INSERT 持有行锁（或间隙锁）-> 触发器在此锁范围内运行
  如果触发器内部执行了其他表的 DML，会获取额外的行锁
  这意味着:
    a. 触发器延长了锁的持有时间（增加锁竞争和死锁概率）
    b. 一个简单的 INSERT 可能因为触发器而锁住多张表
    c. 死锁排查困难: SHOW ENGINE INNODB STATUS 的死锁日志不会显示触发器上下文

性能影响量化:
  每行触发器的开销 = 触发器体的执行时间 + 额外锁获取
  批量 INSERT 1 万行，如果触发器做一次 INSERT 到审计表:
    无触发器: 1 万次行写入
    有触发器: 1 万次行写入 + 1 万次审计写入 + 1 万次额外加锁

### MySQL 触发器的限制（对比其他引擎）

  a. 不支持 INSTEAD OF 触发器:
     SQL Server/PostgreSQL 支持 INSTEAD OF: 替换原始 DML 操作（常用于可更新视图）
     MySQL: 没有 INSTEAD OF，视图的可更新性只能靠 MERGE 算法
  b. 不支持语句级触发器:
     PostgreSQL/Oracle: FOR EACH STATEMENT 触发器，每个 DML 语句只触发一次
     MySQL: 只有 FOR EACH ROW，批量操作时触发器执行次数 = 行数
  c. 不支持 DDL 触发器:
     SQL Server: DDL 触发器（CREATE/ALTER/DROP 事件），可以用于审计 schema 变更
     PostgreSQL: 事件触发器（Event Trigger），可以拦截 DDL 操作
     MySQL: 无 DDL 触发器，只能用 audit plugin 或 general log 监控 DDL
  d. 不支持数据库级/服务器级触发器:
     SQL Server: 有服务器级（Server-level）和数据库级（Database-level）触发器
     MySQL: 触发器只能绑定到具体的表

## 为什么分布式引擎多不支持触发器（对 SQL 引擎开发者）

### 技术困难

  a. 触发器在事务中同步执行 -> 分布式事务的延迟被进一步放大
  b. 触发器可能修改其他表的数据 -> 跨分片/跨节点的级联写入
  c. 触发器的执行顺序依赖全局协调 -> 分布式环境难以保证 FOLLOWS/PRECEDES 语义
  d. 触发器逻辑在哪个节点执行？ 数据所在节点 vs 协调节点？
     如果在数据节点: 每个节点需要一份触发器代码，版本同步是问题
     如果在协调节点: 数据需要传输到协调节点执行触发器，延迟巨大

### 各分布式引擎的状态:

  TiDB:         不支持触发器
  CockroachDB:  不支持触发器（文档明确说明）
  Vitess:       不支持（MySQL 触发器在 vttablet 层无法正确路由）
  Spanner:      不支持
  BigQuery:     不支持（无事务性 DML 触发的概念）
  YugabyteDB:   支持（PG 兼容模式下支持 PG 触发器语法）
  CockroachDB:  24.2+ 开始添加触发器支持（PG 兼容需求驱动）

## 横向对比: 触发器 vs CDC vs 物化视图（事件驱动方案）

### 触发器方案

  优点: 同步执行，强一致性，数据变更后立即可见
  缺点: 增加事务延迟，引入锁竞争，调试困难，分布式不适用
  适用: 简单的数据规范化（BEFORE 触发器）、小规模审计

### CDC（Change Data Capture）方案

  原理: 从 binlog（MySQL）/ WAL（PostgreSQL）/ redo log 中异步捕获数据变更
  工具链:
    MySQL:      Debezium + Kafka, Maxwell, Canal（阿里巴巴开源）
    PostgreSQL: Debezium + WAL, pgoutput, wal2json
    SQL Server: 内置 CDC 功能（sys.sp_cdc_enable_table）
    Oracle:     Oracle GoldenGate, LogMiner
  优点:
    a. 异步处理，不影响主事务性能
    b. 解耦: 数据库不需要知道下游消费者
    c. 可扩展: 多个消费者独立消费同一变更流
    d. 分布式友好: 天然适合微服务架构
  缺点:
    a. 最终一致性（有延迟）
    b. 需要额外的基础设施（消息队列、连接器）
    c. 需要处理 exactly-once 语义
  适用: 数据同步、搜索索引更新、事件驱动架构、跨服务数据传播

### 物化视图方案

  原理: 预计算查询结果并存储，数据变更时自动或手动刷新
  引擎支持:
    PostgreSQL: CREATE MATERIALIZED VIEW ... WITH DATA
                REFRESH MATERIALIZED VIEW CONCURRENTLY（增量刷新，需唯一索引）
    Oracle:     最成熟的实现: ON COMMIT / ON DEMAND 刷新、FAST（增量）/ COMPLETE（全量）
                物化视图日志（MV Log）记录增量变更
    SQL Server: Indexed View（类似物化视图，自动同步维护，有严格限制）
    MySQL:      不支持原生物化视图！只能用 表 + EVENT 定时刷新 或 触发器手动维护
    ClickHouse: Materialized View 本质上是 INSERT 触发器: 新数据插入时自动转换并写入目标表
                不是传统的 "查询快照"，而是实时的 ETL 管道
  优点: 查询性能极高（预计算），适合读多写少的聚合场景
  缺点: 写入开销增加，刷新策略需要权衡（同步 vs 异步，全量 vs 增量）
  适用: 报表/仪表盘、聚合查询加速、OLAP 场景

### 方案选择决策矩阵:

  数据规范化（字段转换）         -> BEFORE 触发器（简单、同步）
  同表审计（INSERT/UPDATE/DELETE）-> AFTER 触发器（小规模）或 CDC（大规模）
  跨服务数据同步                 -> CDC + 消息队列（解耦、异步、可扩展）
  聚合查询加速                   -> 物化视图（如果引擎支持）
  搜索引擎同步（ES/Solr）        -> CDC（Debezium 是事实标准）
  缓存失效                       -> CDC 或 AFTER 触发器（取决于延迟容忍度）

对引擎开发者的总结:
  1) 触发器是单机 OLTP 的遗留特性，分布式引擎应优先投资 CDC 能力
  2) 物化视图对 OLAP 引擎极其重要，ClickHouse 的 "触发器式物化视图" 是创新设计
  3) 如果要兼容 MySQL/PG，行级触发器是必须的（大量遗留应用依赖）
  4) 语句级触发器和 INSTEAD OF 触发器的实现成本较高，优先级可以较低
  5) 无论选择哪种方案，事件的可观察性（哪些触发器在执行、延迟多少）对运维至关重要
