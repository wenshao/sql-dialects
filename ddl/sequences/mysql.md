# MySQL: 序列

> 参考资料:
> - [MySQL 8.0 Reference Manual - AUTO_INCREMENT Handling in InnoDB](https://dev.mysql.com/doc/refman/8.0/en/innodb-auto-increment-handling.html)
> - [MySQL 8.0 Reference Manual - AUTO_INCREMENT](https://dev.mysql.com/doc/refman/8.0/en/example-auto-increment.html)
> - [MySQL 8.0 Reference Manual - UUID Functions](https://dev.mysql.com/doc/refman/8.0/en/miscellaneous-functions.html#function_uuid)

## AUTO_INCREMENT 基本语法

```sql
CREATE TABLE users (
    id       BIGINT NOT NULL AUTO_INCREMENT,
    username VARCHAR(64) NOT NULL,
    email    VARCHAR(255) NOT NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB;
```

获取最后生成的值
```sql
SELECT LAST_INSERT_ID();
```

设置起始值
```sql
ALTER TABLE users AUTO_INCREMENT = 1000;
```

全局设置自增步长（主从复制场景: 双主架构时奇偶分配）
```sql
SET @@auto_increment_increment = 2;   -- 步长
SET @@auto_increment_offset = 1;      -- 起始偏移（主 1 用 1, 主 2 用 2）

-- AUTO_INCREMENT 的约束:
--   每表最多一个 AUTO_INCREMENT 列
--   该列必须是索引的一部分（通常是主键，但不要求必须是主键）
--   不支持 INCREMENT BY 语法（步长只能通过系统变量全局设置）
```

## AUTO_INCREMENT 的实现细节和锁模式（对 SQL 引擎开发者）

### 自增锁模式: innodb_autoinc_lock_mode

这是 InnoDB 中最被忽视但影响最大的配置之一

lock_mode = 0: "traditional"（传统模式）
  所有 INSERT 语句获取表级 AUTO-INC 锁，语句结束后释放（不是事务结束）
  保证: 同一语句内分配的 ID 连续
  代价: 严重的表级锁竞争，高并发 INSERT 性能差

lock_mode = 1: "consecutive"（连续模式，5.1~7.x 默认）
  简单 INSERT（行数确定）: 使用轻量级互斥锁，分配后立即释放
  批量 INSERT（行数不确定，如 INSERT ... SELECT, LOAD DATA）: 使用表级 AUTO-INC 锁
  保证: 简单 INSERT 的 ID 连续，批量 INSERT 的 ID 连续
  适用: 基于 STATEMENT 的复制（SBR）

lock_mode = 2: "interleaved"（交错模式，8.0+ 默认）
  所有 INSERT 都使用轻量级互斥锁，不使用表级 AUTO-INC 锁
  结果: 并发 INSERT 的 ID 可能交错（不保证连续性）
  优势: 最高并发性能
  要求: 必须使用 ROW 格式 binlog（STATEMENT 格式下 ID 交错会导致主从不一致）
  这也是 MySQL 8.0 将 binlog_format 默认改为 ROW 的原因之一

### 自增持久化: 5.7 vs 8.0 的行为差异

MySQL 5.7 及之前:
  自增计数器存储在内存中，不持久化
  重启后: InnoDB 执行 SELECT MAX(id) FROM table 重新初始化计数器
> **问题**: 如果删除了 id=100（当前最大值）后重启，下一个分配的 ID 仍是 100
         导致 ID 复用，可能破坏依赖 "ID 永不复用" 假设的应用逻辑

MySQL 8.0+:
  自增计数器持久化到 redo log
  重启后: 从 redo log 恢复上次的自增值，不会回退
  即使 DELETE 了最后几行再重启，自增值也不会倒退

对引擎开发者的启示:
  自增持久化看似简单，但涉及:
  a. 何时写入持久化存储？（每次分配 vs 批量写入 vs checkpoint 时写入）
  b. 崩溃恢复时如何保证不分配重复 ID？
  c. MySQL 8.0 选择写入 redo log，避免额外的磁盘写入（redo log 本身就要写）

## 为什么 MySQL 没有 SEQUENCE 对象（对 SQL 引擎开发者）

AUTO_INCREMENT 和 SEQUENCE 的本质区别:
  AUTO_INCREMENT: 绑定到表的列，生命周期随表
  SEQUENCE:       独立的数据库对象，可以跨表共享，有自己的 DDL

MySQL 没有 SEQUENCE 的可能原因:
  a. 历史路径依赖: MySQL 从一开始就用 AUTO_INCREMENT，社区习惯已形成
  b. AUTO_INCREMENT 够用: 单表自增覆盖了 80% 的场景
  c. 实现复杂度: SEQUENCE 需要独立的 DDL/DML 支持、持久化、并发控制
  d. MariaDB 在 10.3 添加了 CREATE SEQUENCE，但 MySQL 官方至今未跟进

模拟 SEQUENCE 的方法:
方法 1: 单行表 + LAST_INSERT_ID 技巧
```sql
CREATE TABLE my_sequence (
    seq_name      VARCHAR(64) PRIMARY KEY,
    current_value BIGINT NOT NULL DEFAULT 0
) ENGINE=InnoDB;

INSERT INTO my_sequence VALUES ('order_id', 0);
```

原子获取下一个值（利用 LAST_INSERT_ID 的 "设置并返回" 特性）
```sql
UPDATE my_sequence SET current_value = LAST_INSERT_ID(current_value + 1)
WHERE seq_name = 'order_id';
SELECT LAST_INSERT_ID();  -- 返回刚设置的值
```

> **问题**: 行级锁竞争（高并发下该行成为热点）
优化: 批量预分配（每次 +100，应用内存分发），但增加复杂度

方法 2: UUID（全局唯一，无需协调）
```sql
SELECT UUID();                          -- 标准 UUID v1（基于时间+MAC）
SELECT UUID_TO_BIN(UUID(), 1);          -- 8.0+: 转二进制 + 时间排序（swap time-low/time-high）
SELECT BIN_TO_UUID(id) FROM sessions;   -- 读取时转回字符串

CREATE TABLE sessions (
    id         BINARY(16) DEFAULT (UUID_TO_BIN(UUID(), 1)),   -- 8.0.13+ 表达式默认值
    user_id    BIGINT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

UUID 的存储选择:
  CHAR(36): 36 字节，可读但浪费空间且索引效率低（字符串比较）
  BINARY(16): 16 字节，紧凑且索引效率高（二进制比较）
  UUID_TO_BIN(uuid, 1): 将时间部分前移，使 UUID 具有时间有序性（减少 B+树页分裂）

## 横向对比: AUTO_INCREMENT vs SERIAL vs IDENTITY vs SEQUENCE

### MySQL AUTO_INCREMENT:

  语法:      id BIGINT AUTO_INCREMENT
  特点:      表级绑定，每表一个，步长全局设置
  持久化:    8.0+ 持久化到 redo log
  分布式:    单机语义，分布式需要额外协调

### PostgreSQL SERIAL / IDENTITY:

  SERIAL（旧方式，PG 所有版本）:
    语法糖: id SERIAL = id INTEGER NOT NULL DEFAULT nextval('table_id_seq')
    自动创建一个 SEQUENCE 对象
> **问题**: DROP TABLE 不自动删除 SEQUENCE（可能泄漏），权限管理不直观
  IDENTITY（PG 10+，推荐）:
    语法: id INTEGER GENERATED ALWAYS AS IDENTITY
    SQL 标准，无 SEQUENCE 泄漏问题
    ALWAYS vs BY DEFAULT: ALWAYS 禁止手动指定值，BY DEFAULT 允许

### Oracle SEQUENCE / IDENTITY:

  SEQUENCE（传统方式，最早的实现，8i+）:
```sql
    CREATE SEQUENCE order_seq START WITH 1 INCREMENT BY 1 CACHE 20;
    SELECT order_seq.NEXTVAL FROM DUAL;
```

    CACHE: 每次预分配 N 个值到内存（减少 redo log 写入），崩溃后可能留下间隔
    NO ORDER: RAC 环境下不保证跨实例有序（ORDER 强制有序但性能差）
  IDENTITY（12c+）:
    id NUMBER GENERATED ALWAYS AS IDENTITY
    内部仍然使用 SEQUENCE 实现

### SQL Server IDENTITY / SEQUENCE:

  IDENTITY（传统，所有版本）:
    id INT IDENTITY(1, 1)    -- (seed, increment)
    SET IDENTITY_INSERT table ON 才能手动指定值（默认禁止）
    DBCC CHECKIDENT 重置计数器
  SEQUENCE（2012+）:
```sql
    CREATE SEQUENCE order_seq AS INT START WITH 1 INCREMENT BY 1;
    SELECT NEXT VALUE FOR order_seq;
```

    可以跨表共享，用于 DEFAULT 约束

### 分布式引擎的自增策略:

  TiDB:       AUTO_INCREMENT（段分配: 每个 TiDB 节点预分配一段 ID，节点间不连续）
              AUTO_RANDOM（推荐: 高位随机化，避免写入热点）
  CockroachDB: SERIAL = unique_rowid()（基于时间戳+节点ID，全局唯一但不连续）
              GENERATED ALWAYS AS IDENTITY（23.1+，基于 SEQUENCE）
  Spanner:    无自增（设计哲学: 全局自增与分布式水平扩展矛盾）
              推荐 UUIDv4 或 bit-reversed sequence
  BigQuery:   无自增（分析引擎，批量写入场景不需要逐行自增）
              GENERATE_UUID() 函数
  Snowflake:  AUTOINCREMENT / IDENTITY（值不保证连续，内部基于序列）

### 设计选择总结:

  单机 OLTP:    AUTO_INCREMENT / IDENTITY（简单高效）
  分布式 OLTP:  UUID / AUTO_RANDOM / Snowflake ID（避免全局协调热点）
  分析引擎:     通常不需要自增（数据是批量加载的）

对引擎开发者的核心决策:
  1) 是否需要兼容 AUTO_INCREMENT 语法？（MySQL 兼容层通常需要）
  2) 自增值是否保证连续？（放弃连续性可以大幅提升并发性能）
  3) 自增值是否保证单调递增？（分布式环境中全局单调成本极高）
  4) 崩溃后是否允许间隔？（Oracle CACHE、MySQL lock_mode=2 都可能产生间隔）
  5) 分布式环境: 段分配（TiDB）vs 时间戳方案（CockroachDB）vs 放弃自增（Spanner）
