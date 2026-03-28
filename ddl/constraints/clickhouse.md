# ClickHouse: 约束（Constraints）

> 参考资料:
> - [1] ClickHouse SQL Reference - CREATE TABLE
>   https://clickhouse.com/docs/en/sql-reference/statements/create/table
> - [2] ClickHouse - ALTER CONSTRAINT
>   https://clickhouse.com/docs/en/sql-reference/statements/alter/constraint
> - [3] ClickHouse - ReplacingMergeTree
>   https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replacingmergetree


## 1. ClickHouse 的约束哲学: 最小化写入路径开销


 ClickHouse 的约束模型与 OLTP 数据库截然不同:
   - PRIMARY KEY 不保证唯一性（仅用于稀疏索引）
   - 没有 UNIQUE 约束
   - 没有 FOREIGN KEY
   - 默认 NOT NULL（Nullable 需要 opt-in）
   - CHECK 约束是唯一的数据验证手段（19.14+）

 为什么如此极简? 分析型引擎的核心矛盾:
   写入吞吐量（百万行/秒）vs 约束检查开销
   每行检查 UNIQUE → 需要查询已有数据 → 写入速度下降数个数量级
   检查 FOREIGN KEY → 需要跨表查询 → 分布式环境下代价极高

 设计决策: 在写入路径上做最少的检查，数据质量交给 ETL 管道保证。

## 2. PRIMARY KEY: 排序键而非唯一约束


PRIMARY KEY 定义稀疏索引的范围，不保证唯一性

```sql
CREATE TABLE users (
    id         UInt64,
    username   String,
    email      String
)
ENGINE = MergeTree()
ORDER BY id;              -- ORDER BY 默认即 PRIMARY KEY

```

可以插入重复主键!
INSERT INTO users VALUES (1, 'alice', 'a@e.com');
INSERT INTO users VALUES (1, 'bob',   'b@e.com');  -- 成功!

PRIMARY KEY 可以与 ORDER BY 不同（PRIMARY KEY 必须是 ORDER BY 的前缀）

```sql
CREATE TABLE orders (
    user_id    UInt64,
    order_date Date,
    amount     Decimal(10,2)
)
ENGINE = MergeTree()
ORDER BY (user_id, order_date)    -- 排序键: 决定物理排列顺序
PRIMARY KEY user_id;              -- 主键: 稀疏索引的粒度

```

 设计分析:
   ClickHouse 的 PRIMARY KEY 本质是"索引提示"而非"完整性约束"。
   稀疏索引每 index_granularity 行（默认 8192）记录一个索引条目。
   这意味着索引不是逐行的，无法用于唯一性验证。

 对比:
   MySQL InnoDB:  PRIMARY KEY = 聚集索引 + 唯一约束（两个作用合一）
   PostgreSQL:    PRIMARY KEY = btree 索引 + 唯一约束
   BigQuery:      PRIMARY KEY NOT ENFORCED（信息性，不检查唯一性）
   ClickHouse:    PRIMARY KEY = 稀疏索引（不检查唯一性）

## 3. NOT NULL: 为什么默认不可空


ClickHouse 默认所有列 NOT NULL（与几乎所有其他数据库相反）

```sql
CREATE TABLE events (
    id       UInt64,              -- 不能为 NULL
    name     String,              -- 不能为 NULL
    value    Nullable(Float64),   -- 需要显式 Nullable() 包装
    tag      Nullable(String)     -- 需要显式 Nullable() 包装
)
ENGINE = MergeTree()
ORDER BY id;

```

 为什么默认 NOT NULL?
 (a) 性能: Nullable 列需要额外的 null bitmap 文件（每列多一个文件）
     → 增加 I/O 和存储开销
 (b) 向量化: 非空列可以直接做 SIMD 运算，Nullable 需要分支判断
 (c) 列存压缩: 非空列压缩率更高（没有 NULL 标记）
 (d) 设计哲学: 分析场景通常用默认值（0, ''）代替 NULL

 Nullable 的性能影响:
   存储: +1 字节/行（null bitmap）
   查询: Nullable(UInt64) 比 UInt64 慢约 5-10%（额外分支判断）
   聚合: NULL 值需要特殊处理（SUM/COUNT 跳过 NULL）

 对比:
   SQL 标准:   默认允许 NULL（需要 NOT NULL 显式禁止）
   MySQL:      默认允许 NULL
   PostgreSQL: 默认允许 NULL
   BigQuery:   默认允许 NULL

## 4. DEFAULT / MATERIALIZED / ALIAS: 三种默认值语义


```sql
CREATE TABLE events (
    timestamp  DateTime,
    -- DEFAULT: 可以手动 INSERT 覆盖
    status     UInt8 DEFAULT 1,
    -- MATERIALIZED: 自动计算且存储，不能手动插入
    event_date Date MATERIALIZED toDate(timestamp),
    hour       UInt8 MATERIALIZED toHour(timestamp),
    -- ALIAS: 查询时实时计算，不存储在磁盘上
    full_info  String ALIAS concat(toString(status), '-', toString(timestamp))
)
ENGINE = MergeTree()
ORDER BY timestamp;

```

 MATERIALIZED vs ALIAS 的选择:
   MATERIALIZED: 计算一次存储 → 查询快但占存储 → 适合高频查询的派生列
   ALIAS:        每次查询计算 → 不占存储但查询慢 → 适合偶尔使用的派生列

 设计启示:
   这三种默认值语义比传统 SQL 的 DEFAULT + 生成列更灵活。
   MATERIALIZED 类似 PostgreSQL 的 STORED 生成列，
   ALIAS 类似 PostgreSQL 的 VIRTUAL 生成列（但 PG 不支持 VIRTUAL）。
   MySQL 8.0 支持 STORED 和 VIRTUAL 生成列，语义最接近 ClickHouse。

## 5. CHECK 约束（19.14+）


```sql
CREATE TABLE users (
    id   UInt64,
    age  UInt8,
    CONSTRAINT chk_age CHECK age > 0 AND age < 200
)
ENGINE = MergeTree()
ORDER BY id;

```

动态添加/删除 CHECK

```sql
ALTER TABLE users ADD CONSTRAINT chk_status CHECK status IN (0, 1, 2);
ALTER TABLE users DROP CONSTRAINT chk_status;

```

 CHECK 在 INSERT 时同步检查（阻塞式）。
 这是 ClickHouse 写入路径上唯一的数据验证点。
 由于 CHECK 每行检查，复杂的 CHECK 表达式会显著降低写入吞吐量。
 建议: 只用简单的范围/枚举检查，复杂验证放在 ETL 层。

## 6. 去重替代方案: ReplacingMergeTree


由于没有 UNIQUE 约束，ClickHouse 通过特殊引擎实现"最终一致"的去重


```sql
CREATE TABLE users (
    id         UInt64,
    username   String,
    version    UInt64           -- 版本号，ReplacingMergeTree 保留最大版本
)
ENGINE = ReplacingMergeTree(version)
ORDER BY id;

```

可以插入重复 id:
INSERT INTO users VALUES (1, 'alice', 1);
INSERT INTO users VALUES (1, 'alice_v2', 2);

后台 merge 时去重（保留 version 最大的行）
查询时获取去重结果:

```sql
SELECT * FROM users FINAL WHERE id = 1;
```

FINAL 关键字: 在查询时执行合并逻辑，保证结果正确但性能较差
强制立即合并:

```sql
OPTIMIZE TABLE users FINAL;

```

 设计分析:
   ReplacingMergeTree 是"最终一致性"而非"强一致性":
   - INSERT 时不检查重复（写入路径无开销）
   - 后台 merge 时去重（异步，不确定何时完成）
   - FINAL 查询时去重（同步但性能差）

   这是 ClickHouse 的核心设计取舍:
   写入吞吐量 > 即时一致性 > 查询便利性

## 7. 对比与引擎开发者启示

ClickHouse 的约束模型总结:
支持: NOT NULL(默认), CHECK(19.14+), DEFAULT/MATERIALIZED/ALIAS
不支持: UNIQUE, FOREIGN KEY, EXCLUDE
"支持但不强制": PRIMARY KEY（稀疏索引，不保证唯一）

对引擎开发者的启示:
(1) OLAP 引擎的约束设计应优先保护写入吞吐量
(2) Nullable opt-in 比 opt-out 更适合分析场景（减少 null 处理开销）
(3) 去重可以通过引擎层面（merge 时去重）而非约束层面（写入时检查）实现
(4) 三种默认值语义（DEFAULT/MATERIALIZED/ALIAS）比单一 DEFAULT 更实用
(5) 如果支持 CHECK，需要评估对写入性能的影响

