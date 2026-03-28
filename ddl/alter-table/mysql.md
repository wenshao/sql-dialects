# MySQL: ALTER TABLE

> 参考资料:
> - [MySQL 8.0 Reference Manual - ALTER TABLE](https://dev.mysql.com/doc/refman/8.0/en/alter-table.html)
> - [MySQL 8.0 Reference Manual - Online DDL Operations](https://dev.mysql.com/doc/refman/8.0/en/innodb-online-ddl-operations.html)
> - [Percona pt-online-schema-change](https://docs.percona.com/percona-toolkit/pt-online-schema-change.html)
> - [GitHub gh-ost](https://github.com/github/gh-ost)

## 基本语法

添加列（AFTER / FIRST 是 MySQL 独有语法，控制列的物理顺序）
```sql
ALTER TABLE users ADD COLUMN phone VARCHAR(20) AFTER email;
ALTER TABLE users ADD COLUMN status TINYINT NOT NULL DEFAULT 1 FIRST;
```

支持一次添加多列（合并为单个 DDL 操作，只重建一次表）
```sql
ALTER TABLE users
    ADD COLUMN city VARCHAR(64),
    ADD COLUMN country VARCHAR(64);
```

修改列类型（MODIFY 不改名，CHANGE 可改名）
```sql
ALTER TABLE users MODIFY COLUMN phone VARCHAR(32) NOT NULL;
```

重命名列
5.7: 必须用 CHANGE，需要重新声明完整类型定义（极易出错）
```sql
ALTER TABLE users CHANGE COLUMN phone mobile VARCHAR(32);
-- 8.0+: RENAME COLUMN（SQL 标准语法，不需要重新声明类型）
ALTER TABLE users RENAME COLUMN mobile TO phone;
```

删除列
```sql
ALTER TABLE users DROP COLUMN phone;
```

修改默认值（仅修改元数据，不涉及行数据）
```sql
ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;
```

重命名表
```sql
ALTER TABLE users RENAME TO members;
RENAME TABLE users TO members;    -- 等价语法，可同时重命名多个表
```

修改表引擎 / 字符集
```sql
ALTER TABLE users ENGINE = InnoDB;
ALTER TABLE users CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

> **注意**: MySQL 不支持 ALTER TABLE ADD/DROP COLUMN IF [NOT] EXISTS
MariaDB 支持此语法，MySQL 中需要查询 information_schema 或使用存储过程绕行

## Online DDL 算法详解（对 SQL 引擎开发者）

### 三种算法: COPY / INPLACE / INSTANT

COPY（最早的实现，5.1 及之前唯一方式）:
  过程: 创建新表结构 -> 逐行拷贝数据 -> 交换表名 -> 删除旧表
  锁:   全程持有 EXCLUSIVE MDL 锁（阻塞所有读写）
  适用: 所有 DDL 操作都能 fallback 到 COPY
  开销: O(n) 时间 + O(n) 额外磁盘空间 + redo log 写入

INPLACE（5.6+ 引入 Online DDL）:
  过程: 直接在原表上修改（不一定真的 "in-place"，很多操作仍然重建）
  锁:   开始和结束时短暂获取 EXCLUSIVE MDL，中间阶段可以只持有 SHARED 或 NONE
  适用: 大部分索引操作、ADD COLUMN(5.6)、修改列类型(部分)
  关键: 修改期间的 DML 操作记录到 online log buffer，完成时重放

INSTANT（8.0.12+ 引入）:
  过程: 只修改数据字典（元数据），不触碰任何行数据
  锁:   仅需要极短暂的 MDL 锁
  适用: ADD COLUMN（仅追加到末尾, 8.0.12+; 任意位置, 8.0.29+）
        SET/DROP DEFAULT、RENAME TABLE、修改 ENUM/SET 扩展值
  限制: 不能用于 DROP COLUMN（8.0 中）、修改数据类型、添加索引
        INSTANT ADD COLUMN 后的行格式: 旧行保留旧结构，新行用新结构
        读取旧行时通过数据字典补全新列的默认值（类似 PostgreSQL 11+ 的做法）

```sql
ALTER TABLE users ADD COLUMN tag VARCHAR(32) DEFAULT 'none', ALGORITHM=INSTANT;
ALTER TABLE users ADD COLUMN score INT, ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE users ENGINE=InnoDB, ALGORITHM=COPY;  -- 强制全表重建（用于碎片整理）
```

### 锁级别: NONE / SHARED / EXCLUSIVE

LOCK=NONE:      允许并发 DML（读+写），最理想
LOCK=SHARED:    允许并发读，阻塞写
LOCK=EXCLUSIVE: 阻塞所有并发操作
LOCK=DEFAULT:   使用该操作允许的最低锁级别（推荐，生产环境默认不指定）

不同操作的最低锁级别:
  INSTANT 操作:       无需持续锁
  ADD INDEX:          NONE（INPLACE + online log）
  ADD COLUMN(INPLACE): NONE（但内部仍重建表）
  MODIFY 列类型:      EXCLUSIVE（必须重建，8.0 大部分类型变更仍如此）
  ADD FOREIGN KEY:    SHARED（需要检查一致性）

对引擎开发者的启示:
  锁级别设计的核心问题是: DDL 变更期间如何处理并发 DML？
  MySQL 的 online log 方案: 将 DDL 期间的 DML 增量记录到 buffer，DDL 完成时重放
  如果 DDL 时间太长，online log buffer 可能溢出（innodb_online_alter_log_max_size）
  替代方案: PostgreSQL 使用 HOT (Heap-Only Tuple) 和懒清理，很多 DDL 天然就是 online 的

## pt-online-schema-change 和 gh-ost（对引擎开发者）

### 为什么需要外部工具？

即使有 Online DDL，以下场景仍然有问题:
  a. INPLACE 算法仍可能内部重建整个表（持有 SHARED 锁的时间可能很长）
  b. DDL 过程中 redo log 写入量巨大，影响复制延迟
  c. 大表（数十 GB~TB 级）的 DDL 可能耗时数小时
  d. 5.6/5.7 环境没有 INSTANT 算法
  e. 需要可暂停/可回滚的 DDL 操作

### pt-online-schema-change 原理（Percona Toolkit）

  1) 创建与原表结构相同的影子表（shadow table），应用新的 DDL
  2) 在原表上创建 3 个触发器（AFTER INSERT/UPDATE/DELETE），将增量实时同步到影子表
  3) 分批复制（chunk）原表数据到影子表（可控速率，避免冲击线上负载）
  4) 复制完成后，RENAME TABLE 原子交换（极短暂锁）
  5) 删除旧表和触发器

  局限:
    - 依赖触发器，原表已有触发器时冲突（每事件最多一个在 5.7 之前）
    - 触发器在同一事务中执行，增加事务开销
    - 外键处理复杂（需要特殊的 rebuild 策略）

### gh-ost 原理（GitHub Online Schema Transmogrifier）

  与 pt-osc 的关键区别: 不使用触发器，而是读取 binlog 捕获增量
  1) 创建影子表并应用 DDL
  2) 连接到 MySQL 实例（或副本）读取 binlog stream
  3) 从 binlog 解析出对原表的 DML，应用到影子表
  4) 同时分批复制存量数据
  5) 数据追平后，短暂 lock 原表，cut-over 交换表名

  优势:
    - 无触发器依赖，不增加事务开销
    - 可暂停 / 限速 / 动态调整（通过 socket 文件交互）
    - 支持在副本上测试迁移
  局限:
    - 要求 ROW 格式 binlog（STATEMENT 格式不支持）
    - 外键支持有限

对引擎开发者的启示:
  MySQL 社区发展出 pt-osc / gh-ost 这类工具，本质上是因为引擎内置的 Online DDL 不够用。
  现代引擎设计应考虑:
    a. DDL 操作的可暂停性和可观察性（进度、预计剩余时间）
    b. DDL 对复制延迟的影响控制
    c. 分布式 DDL 协调（如 TiDB 使用 schema version 协议实现在线 DDL）
    d. CockroachDB 的做法: DDL 是后台的 schema change job，可查看进度、可取消

## 横向对比: 各引擎的 ALTER TABLE 实现

PostgreSQL:
- **ADD COLUMN + DEFAULT**: PG 11+ 即时完成（只修改 catalog，读取旧行时填充默认值）
- **PG 10 及之前**: 需要重写全表
- **ADD COLUMN NOT NULL + DEFAULT**: PG 11+ 同样即时（之前必须重写）
- **DROP COLUMN**: 标记为 dropped，不物理删除（VACUUM 时清理）
- **ADD INDEX**: CREATE INDEX CONCURRENTLY（不阻塞写，但耗时更长，需要两遍扫描）
- **ALTER TYPE**: 多数情况需要重写表（除非只是扩展长度如 VARCHAR(50) -> VARCHAR(100)）
- **优势**: DDL 是事务性的，ALTER TABLE 失败可以 ROLLBACK

Oracle:
- **ONLINE 关键字**: ALTER TABLE ... ADD (...) ONLINE

```
DBMS_REDEFINITION: 在线表重定义包，类似 pt-osc 的原理但内置于引擎
```
- **Edition-Based Redefinition (EBR)**: 通过 "版本" 实现不停机 DDL
- **ALTER TABLE ... ADD COLUMN**: 允许 NOT NULL + DEFAULT 即时添加（11g+，早于 PG）

SQL Server:
  - ONLINE = ON: 仅 Enterprise Edition 支持在线索引重建
  - Standard Edition 的 ALTER TABLE 操作更多地阻塞并发访问
- **ALTER TABLE ... ADD 列**: 带 DEFAULT 的 NOT NULL 列在 SQL Server 2012+ 即时完成
- **ALTER COLUMN 修改类型**: 通常需要表级锁

对引擎开发者的总结:
  - 1) "只改元数据" 是最优设计: ADD COLUMN + DEFAULT 只需修改 catalog（PG 11+, Oracle 11g+, MySQL INSTANT）
  - 2) 索引创建应支持 "不阻塞写" 模式（PG CONCURRENTLY, MySQL INPLACE LOCK=NONE）
  - 3) 大型表的 DDL 必须提供进度可观察性和可取消能力
  - 4) 分布式环境的 DDL 需要额外协调（schema version protocol, F1-style online DDL）
