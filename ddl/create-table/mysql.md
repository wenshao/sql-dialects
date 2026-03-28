# MySQL: CREATE TABLE

> 参考资料:
> - [MySQL 8.0 Reference Manual - CREATE TABLE](https://dev.mysql.com/doc/refman/8.0/en/create-table.html)
> - [MySQL 8.0 Reference Manual - Data Types](https://dev.mysql.com/doc/refman/8.0/en/data-types.html)
> - [MySQL 8.0 Reference Manual - AUTO_INCREMENT](https://dev.mysql.com/doc/refman/8.0/en/example-auto-increment.html)
> - [MySQL Internals - InnoDB Row Formats](https://dev.mysql.com/doc/refman/8.0/en/innodb-row-format.html)

## 基本语法

```sql
CREATE TABLE users (
    id         BIGINT       NOT NULL AUTO_INCREMENT,
    username   VARCHAR(64)  NOT NULL,
    email      VARCHAR(255) NOT NULL,
    age        INT,
    balance    DECIMAL(10,2) DEFAULT 0.00,
    bio        TEXT,
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_username (username),
    UNIQUE KEY uk_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

## 语法设计分析（对 SQL 引擎开发者）

### ENGINE 子句: 可插拔存储引擎架构

MySQL 的 CREATE TABLE 语法中最独特的设计是 ENGINE 子句。这源于 MySQL 的**可插拔存储引擎架构**（Pluggable Storage Engine）:

| 引擎 | 特点 | 适用场景 |
|------|------|---------|
| **InnoDB** | B+树聚集索引，MVCC，行级锁，事务，外键 | 5.5+ 默认，几乎所有场景 |
| **MyISAM** | 表级锁，无事务，全文索引先驱 | 已无正当使用理由（2024年） |
| **MEMORY** | 纯内存，Hash/B-tree 索引，重启丢失 | 临时结果集 |
| **NDB** | 分布式存储，MySQL Cluster 专用 | 电信级高可用 |

**设计 trade-off:**
- **优点**: 允许针对不同负载选择最优引擎，支持第三方引擎（RocksDB/TokuDB）
- **缺点**: 跨引擎 JOIN 无法利用各引擎的索引优势；引擎间行为不一致（MyISAM 不支持事务但 InnoDB 支持）

**横向对比:**

| 引擎 | 存储架构选择方式 |
|------|----------------|
| MySQL | `ENGINE=InnoDB`（最灵活，但 InnoDB 已"赢者通吃"） |
| PostgreSQL | 无 ENGINE 概念，统一 heap 存储 + MVCC |
| ClickHouse | `ENGINE=MergeTree()`（也是可插拔，且是必选项） |
| Hive | `STORED AS ORC/Parquet`（作用于文件格式而非引擎） |
| Oracle | `ORGANIZATION (HEAP/INDEX)`（有限选择） |

**对引擎开发者的启示:**
如果目标是 OLTP + OLAP 混合负载，可以考虑类似的可插拔架构。TiDB 通过 TiKV(行存) + TiFlash(列存) 实现了类似效果但不暴露 ENGINE 语法。StarRocks/Doris 通过不同的数据模型（Duplicate/Aggregate/Unique/PrimaryKey）实现类似目的。

### AUTO_INCREMENT: 自增主键设计

MySQL 使用 AUTO_INCREMENT 关键字实现自增，这是最早期的自增设计之一。

**语法特点:**
- 表级属性: `AUTO_INCREMENT = N` 可以指定起始值
- 每表最多一个 AUTO_INCREMENT 列，且必须是索引（不要求主键）
- 不支持 INCREMENT BY（步长需要通过 `auto_increment_increment` 系统变量设置）

**实现细节（对引擎开发者关键）:**

InnoDB 的自增锁由 `innodb_autoinc_lock_mode` 控制：

| 模式 | 行为 | 性能 |
|------|------|------|
| 0 (traditional) | 语句级锁 | 最安全但最慢 |
| 1 (consecutive) | 简单 INSERT 不锁，批量用表锁 | 平衡 |
| 2 (interleaved) | 完全无锁（8.0 默认） | 最快但 ID 可能不连续 |

**已知陷阱:**
- **5.7 重启回退**: 自增值存内存，重启后取 `MAX(id)+1`，可能复用已删除的 ID。**8.0 修复**——持久化到 redo log
- **ON DUPLICATE KEY UPDATE 消耗 ID**: 即使实际执行 UPDATE（没有新行），自增值也会 +1，导致 ID 跳跃

**横向对比:**

| 引擎 | 自增方案 | 特点 |
|------|---------|------|
| MySQL | AUTO_INCREMENT | 简单，但分布式不适用 |
| PostgreSQL | SERIAL → IDENTITY(10+) | IDENTITY 是 SQL 标准，推荐 |
| Oracle | SEQUENCE → IDENTITY(12c+) | SEQUENCE 独立于表，更灵活 |
| SQL Server | IDENTITY(seed, increment) | 支持步长 |
| SQLite | INTEGER PRIMARY KEY = rowid | 最简，AUTOINCREMENT 只防复用 |
| BigQuery | 无自增 | 设计哲学: 分布式不应依赖全局递增 |
| TiDB | AUTO_RANDOM | 分布式推荐，随机分配避免热点 |

### ON UPDATE CURRENT_TIMESTAMP: 自动更新时间戳

MySQL 独有的列级特性，其他数据库需要触发器实现。

```sql
updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
```

**设计分析:**
- **优点**: 简单易用，零开发成本
- **缺点**: 耦合在存储层，应用层无感知；批量 UPDATE 时所有行的 `updated_at` 变为同一时间（语句开始时间）

**其他数据库的等价实现:**
- PostgreSQL: 需要触发器函数 + CREATE TRIGGER
- Oracle: 需要 BEFORE UPDATE 触发器
- SQL Server: 需要 AFTER UPDATE 触发器

## 数据类型设计分析

### VARCHAR(n) 的 n: 字符数 vs 字节数

| 引擎 | VARCHAR(n) 的 n | 说明 |
|------|----------------|------|
| MySQL | **字符数** | utf8mb4 下一个字符最多 4 字节 |
| Oracle | **字节数**（默认！） | `VARCHAR2(n CHAR)` 才是字符数 |
| SQL Server | VARCHAR=字节数，NVARCHAR=字符数 | 双轨系统 |
| PostgreSQL | 字符数 | 推荐直接用 TEXT |

**存储开销:** VARCHAR 实际占用 = 实际字节数 + 1-2 字节长度前缀

**n 的选择影响:**
- **内存临时表**: 按 `n × max_bytes_per_char` 分配内存，过大的 n 浪费内存
- **索引长度限制**: InnoDB 单列索引最大 3072 字节。`VARCHAR(768) × 4字节 = 3072`，刚好是上限

### DATETIME vs TIMESTAMP

这是 MySQL 中最经典的类型选择问题：

| 特性 | DATETIME | TIMESTAMP |
|------|----------|-----------|
| 存储 | 5 字节（5.6.4+） | 4 字节 |
| 范围 | 1000-01-01 ~ 9999-12-31 | 1970-01-01 ~ **2038-01-19** |
| 时区 | 存什么就是什么 | 存储 UTC，读取时按 session 时区转换 |
| 适用 | 业务时间（订单时间、生日） | 系统时间（created_at） |

> **建议**: 如果不确定，用 DATETIME。TIMESTAMP 的 2038 年问题在长生命周期系统中是真实风险。

## CHECK 约束: 一个设计教训

| 版本 | 行为 |
|------|------|
| MySQL 5.7 及之前 | **解析 CHECK 语法但不执行！静默忽略** |
| MySQL 8.0.16+ | CHECK 约束真正执行 |

这是一个著名的设计失误——接受语法但不执行 → 用户误以为约束在工作 → 生产中出现脏数据。

**对引擎开发者**: 约束要么执行，要么不接受语法。**接受但不执行是最差的设计选择。**

## 版本演进

| 版本 | 关键特性 |
|------|---------|
| 5.5 | InnoDB 成为默认引擎 |
| 5.6 | Online DDL, InnoDB 全文索引 |
| 5.7 | JSON 类型, 虚拟生成列 |
| 8.0 | 窗口函数, CTE, 原子 DDL, CHECK 约束(8.0.16+), utf8mb4 默认 |
| 8.4 | LTS 版本（长期支持） |
| 9.0 | 向量数据类型 (VECTOR), JavaScript 存储过程 |

## 横向对比

| 维度 | MySQL | PostgreSQL | Oracle | SQL Server | BigQuery | ClickHouse |
|------|-------|-----------|--------|-----------|---------|-----------|
| 自增 | AUTO_INCREMENT | IDENTITY | SEQUENCE/IDENTITY | IDENTITY | 无 | 无 |
| DDL 可回滚 | 否 | **是** | 否 | **是** | 否 | 否 |
| '' = NULL | 否 | 否 | **是** | 否 | 否 | 否 |
| 类型严格度 | 宽松 | **严格** | 中等 | 中等 | 严格 | 严格 |
| 约束执行 | 8.0.16+ | 全执行 | 全执行 | 全执行 | **不执行** | **不执行** |
| 字符集 | utf8≠UTF-8! | UTF-8 | AL32UTF8 | NVARCHAR=UTF-16 | UTF-8 | UTF-8 |
