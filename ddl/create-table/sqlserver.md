# SQL Server: CREATE TABLE

> 参考资料:
> - [SQL Server T-SQL - CREATE TABLE](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-table-transact-sql)
> - [SQL Server T-SQL - Data Types](https://learn.microsoft.com/en-us/sql/t-sql/data-types/data-types-transact-sql)
> - [SQL Server - Temporal Tables](https://learn.microsoft.com/en-us/sql/relational-databases/tables/temporal-tables)

## 基本建表

```sql
CREATE TABLE users (
    id         BIGINT        NOT NULL IDENTITY(1,1),
    username   NVARCHAR(64)  NOT NULL,
    email      NVARCHAR(255) NOT NULL,
    age        INT,
    balance    DECIMAL(10,2) DEFAULT 0.00,
    bio        NVARCHAR(MAX),
    created_at DATETIME2     NOT NULL DEFAULT GETDATE(),
    updated_at DATETIME2     NOT NULL DEFAULT GETDATE(),
    CONSTRAINT pk_users PRIMARY KEY CLUSTERED (id),  -- 显式指定 CLUSTERED
    CONSTRAINT uk_users_username UNIQUE (username),
    CONSTRAINT uk_users_email UNIQUE (email)
);
```

SQL Server 没有 ON UPDATE CURRENT_TIMESTAMP，需要触发器
```sql
CREATE TRIGGER trg_users_updated_at
ON users
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;  -- 避免额外的 "rows affected" 消息干扰客户端
    UPDATE users
    SET updated_at = GETDATE()
    FROM users u
    INNER JOIN inserted i ON u.id = i.id;
END;
```

设计要点:
  1. IDENTITY(1,1): 起始值 1，步长 1。简单场景的首选
  2. PRIMARY KEY CLUSTERED: 明确指定聚簇索引，见下文详解
  3. DATETIME2 而非 DATETIME: 精度更高(100ns vs 3.33ms)，范围更大，推荐 2008+
  4. NVARCHAR(MAX): 最大 2GB，替代已废弃的 NTEXT
  5. SET NOCOUNT ON: 触发器中必须加，否则某些 ORM/驱动会把 affected rows 搞混

## NVARCHAR vs VARCHAR: UTF-8 collation 改变了游戏规则

传统选择:
  VARCHAR(n):  非 Unicode，1 字节/字符，最大 8000
  NVARCHAR(n): Unicode UCS-2/UTF-16，2 字节/字符，最大 4000
  经验法则: "需要存多语言就用 NVARCHAR，否则用 VARCHAR 省空间"

2019+ 的变化: UTF-8 排序规则 (如 Latin1_General_100_CI_AS_SC_UTF8)
  VARCHAR + UTF-8 collation = 用 VARCHAR 存 UTF-8 编码的 Unicode 数据
  英文仍然 1 字节，中文 3 字节，emoji 4 字节
  对于以英文/数字为主的列，比 NVARCHAR (固定 2 字节) 省空间

什么时候用什么:
  纯英文数据 + 2019+  → VARCHAR + UTF-8 collation（最省空间）
  多语言数据 + 2019+  → VARCHAR + UTF-8 collation（通常更好）
  多语言数据 + <2019  → NVARCHAR（唯一正确选择）
  已有系统不想改 collation → 继续用 NVARCHAR（风险最低）

> **注意**: 更改数据库 collation 影响面巨大（所有字符串比较、临时表、变量）
      不要在生产环境轻率切换

## Clustered vs Nonclustered 主键: 性能影响

SQL Server 默认 PRIMARY KEY 是 CLUSTERED
这意味着表的物理行按主键顺序排列（每个表只能有一个聚簇索引）

> **问题**: 如果主键是 UNIQUEIDENTIFIER (GUID)，聚簇索引 = 灾难
  GUID 是随机的 → 随机页插入 → 页分裂 → 碎片化 → 性能暴跌

解决方案 1: NEWSEQUENTIALID() (2005+)
```sql
CREATE TABLE sessions (
    id         UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    user_id    BIGINT NOT NULL,
    created_at DATETIME2 NOT NULL DEFAULT GETDATE(),
    CONSTRAINT pk_sessions PRIMARY KEY CLUSTERED (id)
);
```

NEWSEQUENTIALID() 生成递增的 GUID，解决页分裂问题
但它只能用在 DEFAULT 约束中，不能在 INSERT 中直接调用

解决方案 2: 分离聚簇索引和主键
```sql
CREATE TABLE events (
    id         UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
    event_type NVARCHAR(50) NOT NULL,
    created_at DATETIME2 NOT NULL DEFAULT GETDATE(),
    CONSTRAINT pk_events PRIMARY KEY NONCLUSTERED (id)
);
CREATE CLUSTERED INDEX cix_events_created ON events(created_at);
```

按时间顺序物理排列，范围查询效率高
但主键查找需要额外的 bookmark lookup

## IDENTITY vs SEQUENCE: 实际差异

IDENTITY: 绑定到表的列，简单直观
> **问题**: 无法在 INSERT 之前获取下一个值
       无法多表共享同一序列
       批量插入时的间隙不可控

SEQUENCE (2012+): 独立对象，更灵活
```sql
CREATE SEQUENCE seq_order_id
    AS BIGINT
    START WITH 1
    INCREMENT BY 1
    CACHE 1000           -- 预分配 1000 个值到内存，高并发必须
    NO CYCLE;

CREATE TABLE orders (
    id         BIGINT NOT NULL DEFAULT NEXT VALUE FOR seq_order_id,
    order_no   NVARCHAR(32) NOT NULL,
    amount     DECIMAL(12,2) NOT NULL,
    created_at DATETIME2 NOT NULL DEFAULT GETDATE(),
    CONSTRAINT pk_orders PRIMARY KEY CLUSTERED (id)
);
```

SEQUENCE 优势:
  1. 先获取 ID 再 INSERT: SET @id = NEXT VALUE FOR seq_order_id;
  2. 批量预分配: sp_sequence_get_range 一次取一批，性能极好
  3. 多表共享: 全局唯一 ID
  4. 在 MERGE / 复杂逻辑中比 IDENTITY 更可控

IDENTITY 优势:
  1. 语法简单，EF Core / ORM 默认支持
  2. SCOPE_IDENTITY() / @@IDENTITY 获取刚插入的值
  3. 不需要额外的对象管理

## FILEGROUP 分组: 大表物理布局

默认所有表在 PRIMARY 文件组，生产环境应该分离

先创建文件组和文件（DDL，通常由 DBA 执行）:
```sql
ALTER DATABASE mydb ADD FILEGROUP fg_data;
ALTER DATABASE mydb ADD FILE (NAME='data1', FILENAME='D:\data\data1.ndf') TO FILEGROUP fg_data;
ALTER DATABASE mydb ADD FILEGROUP fg_index;
ALTER DATABASE mydb ADD FILE (NAME='idx1', FILENAME='E:\index\idx1.ndf') TO FILEGROUP fg_index;
```

```sql
CREATE TABLE large_transactions (
    id         BIGINT NOT NULL IDENTITY(1,1),
    account_id BIGINT NOT NULL,
    amount     DECIMAL(18,4) NOT NULL,
    memo       NVARCHAR(500),
    created_at DATETIME2 NOT NULL DEFAULT GETDATE(),
    CONSTRAINT pk_large_txn PRIMARY KEY CLUSTERED (id)
        ON fg_index,                       -- 聚簇索引放 fg_index
    INDEX ix_account (account_id)
        ON fg_index                        -- 非聚簇索引也放 fg_index
) ON fg_data;                              -- 堆数据/聚簇叶子放 fg_data

-- 文件组用途:
--   1. I/O 分离: 数据和索引放不同磁盘
--   2. 部分备份/恢复: 可以只备份/恢复特定文件组
--   3. 只读文件组: 历史数据设为 READONLY 后不再备份
--   4. 内存优化文件组: In-Memory OLTP 必须的专用文件组
```

## 临时表 (Temporal Tables, 2016+)

系统版本的临时表，自动记录每行的完整修改历史
```sql
CREATE TABLE employees (
    id         INT NOT NULL IDENTITY(1,1),
    name       NVARCHAR(100) NOT NULL,
    department NVARCHAR(50) NOT NULL,
    salary     DECIMAL(10,2) NOT NULL,
    -- 系统时间列: SQL Server 自动维护
    valid_from DATETIME2 GENERATED ALWAYS AS ROW START NOT NULL,
    valid_to   DATETIME2 GENERATED ALWAYS AS ROW END NOT NULL,
    PERIOD FOR SYSTEM_TIME (valid_from, valid_to),
    CONSTRAINT pk_employees PRIMARY KEY CLUSTERED (id)
) WITH (SYSTEM_VERSIONING = ON (
    HISTORY_TABLE = dbo.employees_history   -- 历史表名称
));
```

时态查询:
SELECT * FROM employees FOR SYSTEM_TIME AS OF '2024-06-01';  -- 某时刻的快照
```sql
SELECT * FROM employees FOR SYSTEM_TIME BETWEEN '2024-01-01' AND '2024-06-01';
```

SELECT * FROM employees FOR SYSTEM_TIME ALL;  -- 所有历史版本

用途: 审计、数据恢复、缓慢变化维度
> **注意**: 历史表会持续增长，需要定期归档或设置保留策略
2017+: ALTER TABLE employees SET (SYSTEM_VERSIONING = ON (HISTORY_RETENTION_PERIOD = 1 YEAR));

## 内存优化表 (In-Memory OLTP, 2014+)

全内存存储 + 无锁乐观并发，OLTP 场景可提升 10-30 倍性能

前提: 需要创建内存优化文件组
```sql
ALTER DATABASE mydb ADD FILEGROUP fg_inmem CONTAINS MEMORY_OPTIMIZED_DATA;
ALTER DATABASE mydb ADD FILE (NAME='inmem1', FILENAME='F:\inmem\inmem1')
```

    TO FILEGROUP fg_inmem;

```sql
CREATE TABLE hot_counters (
    id      INT NOT NULL,
    counter BIGINT NOT NULL DEFAULT 0,
    CONSTRAINT pk_hot_counters PRIMARY KEY NONCLUSTERED HASH (id)
        WITH (BUCKET_COUNT = 1024),        -- 哈希桶数，约等于预期行数
    INDEX ix_id NONCLUSTERED (id)          -- 还可以加范围索引
) WITH (MEMORY_OPTIMIZED = ON,
        DURABILITY = SCHEMA_AND_DATA);     -- 持久化到磁盘
-- DURABILITY = SCHEMA_ONLY: 只保存结构，数据重启后丢失（适合临时/缓存表）

-- In-Memory OLTP 限制 (2014-2016，后续版本逐步放开):
--   不支持: FOREIGN KEY, CHECK 约束 (2014), TRUNCATE, ALTER TABLE (部分)
--   不支持: LOB 类型 (2014), IDENTITY 种子非1 (2014)
--   2016+ 放开: ALTER TABLE, FOREIGN KEY, CHECK, SP_RENAME 等
--   2017+ 放开: LOB (VARCHAR(MAX), NVARCHAR(MAX))
--
-- 最佳场景: 高并发低延迟的 key-value 操作、会话状态、购物车
```

## 压缩 (ROW / PAGE / COLUMNSTORE)

ROW 压缩: 变长存储定长类型（INT 4字节 → 实际值字节数）
```sql
CREATE TABLE log_entries (
    id         BIGINT NOT NULL IDENTITY(1,1),
    log_level  TINYINT NOT NULL,           -- TINYINT: 1 字节，状态值首选
    message    NVARCHAR(2000),
    created_at DATETIME2 NOT NULL DEFAULT GETDATE(),
    CONSTRAINT pk_log_entries PRIMARY KEY CLUSTERED (id)
) WITH (DATA_COMPRESSION = ROW);           -- 约省 15-25% 空间，CPU 开销极小

-- PAGE 压缩: 行压缩 + 前缀压缩 + 字典压缩
-- 约省 50-70% 空间，CPU 开销中等，适合读多写少的表
-- ALTER TABLE log_entries REBUILD WITH (DATA_COMPRESSION = PAGE);

-- 列存储索引 (2012+): 数据仓库分析场景的大杀器
CREATE TABLE fact_sales (
    sale_id    BIGINT NOT NULL IDENTITY(1,1),
    product_id INT NOT NULL,
    store_id   INT NOT NULL,
    sale_date  DATE NOT NULL,
    quantity   INT NOT NULL,
    amount     DECIMAL(12,2) NOT NULL
);
CREATE CLUSTERED COLUMNSTORE INDEX ccix_fact_sales ON fact_sales;
```

聚簇列存储: 整个表列式存储，压缩比极高 (通常 10:1)
分析查询 (SUM, AVG, GROUP BY) 性能提升 10-100 倍
2016+: 可以和 B-Tree 非聚簇索引共存（Operational Analytics）

## 计算列

```sql
CREATE TABLE products (
    id           INT NOT NULL IDENTITY(1,1) PRIMARY KEY,
    name         NVARCHAR(200) NOT NULL,
    price        DECIMAL(10,2) NOT NULL,
    tax_rate     DECIMAL(5,4) DEFAULT 0.08,
    -- 计算列: 持久化后可以建索引
    total_price AS (price * (1 + tax_rate)) PERSISTED,
    -- 非持久化计算列: 每次查询时计算
    display_name AS (name + N' ($' + CAST(price AS NVARCHAR(20)) + N')'),
    CHECK (price >= 0)
);
CREATE INDEX ix_products_total ON products(total_price);
```

## CREATE TABLE ... SELECT / 临时表

SELECT INTO: SQL Server 的 CTAS，自动创建新表
```sql
SELECT id, username, email, created_at
INTO active_users                          -- 新的永久表
FROM users
WHERE age >= 18;
```

> **注意**: 不复制索引、约束、触发器，只复制列定义和数据
比 INSERT INTO ... SELECT 快，因为可以最小化日志

临时表
```sql
SELECT id, SUM(amount) AS total
INTO #user_totals                          -- # 前缀 = 本地临时表
FROM orders
GROUP BY id;
```

#table:  本地临时表，当前会话可见
##table: 全局临时表，所有会话可见

表变量（小数据集首选）
```sql
DECLARE @results TABLE (
    id    INT,
    score DECIMAL(5,2)
);
```

表变量 vs 临时表:
  表变量: 内存优先，无统计信息，<1000行性能好，不受事务回滚影响
  临时表: 有统计信息，有索引，大数据集性能好，受事务回滚影响

## 版本演进总结

SQL Server 2008:  DATE/TIME/DATETIME2, MERGE, 稀疏列
SQL Server 2012:  SEQUENCE, THROW, 窗口函数增强, AlwaysOn AG
SQL Server 2014:  In-Memory OLTP, 列存储索引增强, 延迟持久性
SQL Server 2016:  临时表(Temporal), JSON, 行级安全, 动态数据掩码,
                  R 集成, 列存储+B-Tree 共存
SQL Server 2017:  图数据库, Linux 支持, 自动调优, Python 集成
SQL Server 2019:  UTF-8 排序规则, 智能查询处理, 加速数据库恢复(ADR),
                  大数据集群
SQL Server 2022:  Ledger 表, JSON 函数增强, 参数敏感计划优化(PSP),
                  GREATEST/LEAST, GENERATE_SERIES, WINDOW 子句,
                  Azure Synapse Link, 包含可用性组(Contained AG)
