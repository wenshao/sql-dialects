# 排他约束 (Exclusion Constraints)

排他约束是 PostgreSQL 在 9.0 版本（2010）首创的一种**广义 UNIQUE 约束**，其核心语义可概括为一句话: "任意两行在指定列组合上不能同时满足给定的运算符"。普通 UNIQUE 约束实质上是排他约束的特例——它要求"任意两行的对应列不能同时相等"（即运算符为 `=`）。而排他约束允许使用任意运算符——例如重叠（`&&`）、包含（`@>`）、距离小于阈值等——从而把"不可重叠的时间区间"、"不可相交的几何区域"、"同一资源最多一个活动锁"等过去需要触发器+串行化才能实现的业务规则，下沉到数据库内核以索引方式高效执行。

排他约束最经典的用法是**防止时间段重叠**: 酒店房间预订、会议室预约、医生排班、价格生效区间——这些场景在传统 SQL 中只能依赖应用层加锁或触发器序列化检查，存在竞态窗口；而 PostgreSQL 的 `EXCLUDE USING GIST (room_id WITH =, stay WITH &&)` 一行声明即可由 GiST 索引在写入路径上原子拒绝冲突。可惜的是，排他约束至今**未被任何 SQL 标准（SQL:2011/2016/2023）采纳**，也没有被其他主流引擎复刻为原生特性，绝大多数引擎只能依赖触发器、SERIALIZABLE 隔离级别、应用锁或 SQL:2011 PERIOD/`WITHOUT OVERLAPS`（仅 MariaDB 部分实现）来近似模拟。本篇梳理 45+ 引擎对排他约束及其等价方案的支持情况，并深入剖析 PostgreSQL 实现机制、典型使用模式与各种工程化等价方案。

## 没有 SQL 标准

截至 SQL:2023，**排他约束没有任何标准化定义**。SQL:2011 确实引入了"应用时间段表"（Application-Time Period Tables）和 `WITHOUT OVERLAPS` 子句，可视为针对"时间段不重叠"这一最常见场景的**狭义标准化尝试**，但它:

1. 仅适用于 PERIOD 类型（基于两列定义的应用时间段），不适用于通用范围类型
2. 仅支持单一运算符语义（重叠等价于不可同时满足）
3. 主流引擎仅 MariaDB 10.5+ 部分实现
4. 表达能力远弱于 PostgreSQL EXCLUDE WITH 任意运算符

因此，"广义排他约束"目前是 PostgreSQL 的**独有方言**——其他引擎要么不支持，要么通过触发器/索引/CHECK 约束的组合曲折模拟。

## 支持矩阵

### 排他约束原生支持（45+ 引擎）

| 引擎 | EXCLUDE WITH 语法 | 范围重叠 | 任意运算符 | 索引方法要求 | WITHOUT OVERLAPS | 版本 |
|------|------------------|---------|-----------|-------------|------------------|------|
| PostgreSQL | 是 | 是 | 是 | GiST/SP-GiST | -- | 9.0+ (2010) |
| MariaDB | -- | 是（PERIOD） | -- | -- | 是 | 10.5+ (2020) |
| MySQL | -- | -- | -- | -- | -- | 不支持 |
| SQLite | -- | -- | -- | -- | -- | 不支持 |
| Oracle | -- | -- | -- | -- | -- | 触发器模拟 |
| SQL Server | -- | -- | -- | -- | -- | 过滤索引模拟 |
| DB2 | -- | -- | -- | -- | -- | 触发器模拟 |
| Snowflake | -- | -- | -- | -- | -- | 不支持 |
| BigQuery | -- | -- | -- | -- | -- | 不支持 |
| Redshift | -- | -- | -- | -- | -- | 不支持 |
| DuckDB | -- | -- | -- | -- | -- | 不支持 |
| ClickHouse | -- | -- | -- | -- | -- | 不支持 |
| Trino | -- | -- | -- | -- | -- | 不支持 |
| Presto | -- | -- | -- | -- | -- | 不支持 |
| Spark SQL | -- | -- | -- | -- | -- | 不支持 |
| Hive | -- | -- | -- | -- | -- | 不支持 |
| Flink SQL | -- | -- | -- | -- | -- | 不支持（流处理） |
| Databricks | -- | -- | -- | -- | -- | 不支持 |
| Teradata | -- | PERIOD 操作 | -- | -- | -- | 触发器/SI 模拟 |
| Greenplum | 是 | 是 | 是 | GiST | -- | 6.0+（继承 PG） |
| CockroachDB | -- | -- | -- | -- | -- | 不支持 |
| TiDB | -- | -- | -- | -- | -- | 不支持 |
| OceanBase | -- | -- | -- | -- | -- | 不支持 |
| YugabyteDB | 是（部分） | 部分 | 部分 | LSM 限制 | -- | 2.6+（部分） |
| SingleStore | -- | -- | -- | -- | -- | 不支持 |
| Vertica | -- | -- | -- | -- | -- | 不支持 |
| Impala | -- | -- | -- | -- | -- | 不支持 |
| StarRocks | -- | -- | -- | -- | -- | 不支持 |
| Doris | -- | -- | -- | -- | -- | 不支持 |
| MonetDB | -- | -- | -- | -- | -- | 不支持 |
| CrateDB | -- | -- | -- | -- | -- | 不支持 |
| TimescaleDB | 是 | 是 | 是 | GiST | -- | 继承 PG |
| QuestDB | -- | -- | -- | -- | -- | 不支持 |
| Exasol | -- | -- | -- | -- | -- | 不支持 |
| SAP HANA | -- | -- | -- | -- | -- | 不支持 |
| Informix | -- | -- | -- | -- | -- | 不支持 |
| Firebird | -- | -- | -- | -- | -- | 不支持 |
| H2 | -- | -- | -- | -- | -- | 不支持 |
| HSQLDB | -- | -- | -- | -- | -- | 不支持 |
| Derby | -- | -- | -- | -- | -- | 不支持 |
| Amazon Athena | -- | -- | -- | -- | -- | 不支持 |
| Azure Synapse | -- | -- | -- | -- | -- | 不支持 |
| Google Spanner | -- | -- | -- | -- | -- | 不支持 |
| Materialize | -- | -- | -- | -- | -- | 不支持 |
| RisingWave | -- | -- | -- | -- | -- | 不支持 |
| InfluxDB | -- | -- | -- | -- | -- | 时序引擎 |
| DatabendDB | -- | -- | -- | -- | -- | 不支持 |
| Yellowbrick | -- | -- | -- | -- | -- | 不支持 |
| Firebolt | -- | -- | -- | -- | -- | 不支持 |

> 统计: 在 45+ 主流 SQL 引擎中，**仅 PostgreSQL 及其衍生品（Greenplum/TimescaleDB/YugabyteDB 部分）原生支持广义 EXCLUDE 约束**。MariaDB 通过 `WITHOUT OVERLAPS` 部分实现了 SQL:2011 PERIOD 的窄场景；其余 40+ 引擎完全不支持，需通过触发器、SERIALIZABLE 事务或应用层加锁等方式模拟。

### 范围/重叠运算符支持（用于 EXCLUDE 的前置条件）

| 引擎 | 范围类型 | && 重叠运算符 | 几何 OVERLAPS | 时间段 OVERLAPS | EXCLUDE 联动 |
|------|---------|--------------|--------------|----------------|-------------|
| PostgreSQL | int4/8/num/date/ts/tstz/range | 是 | 是 | 是 | 是 |
| Greenplum | 同 PG | 是 | 是 | 是 | 是 |
| TimescaleDB | 同 PG | 是 | 是 | 是 | 是 |
| YugabyteDB | 同 PG | 是 | 是 | 是 | 部分 |
| Teradata | PERIOD | -- | -- | OVERLAPS | -- |
| MariaDB | PERIOD（应用时间段） | -- | -- | -- | WITHOUT OVERLAPS |
| Oracle | -- | -- | -- | OVERLAPS（仅时间） | -- |
| SQL Server | -- | -- | 是（geometry/geography） | -- | -- |
| DB2 | -- | -- | -- | OVERLAPS（仅时间） | -- |
| 其他引擎 | -- | -- | -- | -- | -- |

### 索引方法要求（GiST/SP-GiST 等）

| 引擎 | GiST | SP-GiST | btree_gist | 是否需要扩展 | 备注 |
|------|------|---------|------------|------------|------|
| PostgreSQL | 内置 | 内置 | contrib | 整数+范围混合需 btree_gist | 9.0+ |
| Greenplum | 内置 | 部分 | contrib | 同 PG | 继承 |
| TimescaleDB | 内置 | 内置 | 自动 | 同 PG | 继承 |
| YugabyteDB | LSM 适配 | 部分 | -- | 限制较多 | 部分支持 |
| 其他主流引擎 | -- | -- | -- | -- | 无 GiST 框架 |

> GiST（Generalized Search Tree）是 PostgreSQL 7.x（约 2000 年）引入的扩展索引框架，是排他约束的物理基础——它支持任意可定义"重叠/包含"语义的数据类型（范围、几何、IP、文本等）。其他引擎缺乏类似框架是排他约束难以推广的核心技术原因之一。

### 排他约束等价方案对比

| 模拟方案 | 一致性强度 | 性能 | 实现复杂度 | 典型引擎 |
|---------|-----------|------|----------|---------|
| 触发器 + SELECT FOR UPDATE | 中（取决于隔离级别） | 中 | 高 | Oracle/DB2/MySQL |
| SERIALIZABLE 事务 + CHECK | 高（依赖串行化） | 低 | 低 | SQL Server/CockroachDB |
| 过滤索引 + 唯一索引（仅特定模式） | 高（仅离散场景） | 高 | 中 | SQL Server/PG |
| 应用层 advisory lock | 中 | 中 | 中 | Oracle/MySQL |
| 物化表 + 唯一约束（离散化） | 中 | 中 | 高 | 通用 |
| MariaDB WITHOUT OVERLAPS | 高（标准） | 高 | 低 | MariaDB |
| Optimistic + 重试 | 弱 | 高 | 中 | 通用 |

## PostgreSQL EXCLUDE 约束: 唯一原生实现

PostgreSQL 9.0（2010 年 9 月）引入了 EXCLUDE 约束，作为对 UNIQUE 约束的广义化扩展。其核心思想由 Jeff Davis 在 2009 年的 PGCon 演讲中正式提出。

### EXCLUDE 约束完整语法

```sql
-- 完整 BNF 语法
[ CONSTRAINT 约束名 ]
EXCLUDE [ USING 索引方法 ] (
    表达式 WITH 运算符
    [ , ... ]
) [ INCLUDE ( 列名 [ , ... ] ) ]
  [ WITH ( 存储参数 = 值 [ , ... ] ) ]
  [ USING INDEX TABLESPACE 表空间 ]
  [ WHERE ( 谓词 ) ]
  [ DEFERRABLE | NOT DEFERRABLE ]
  [ INITIALLY IMMEDIATE | INITIALLY DEFERRED ]
```

各部分语义:

- **USING 索引方法**: 默认 GiST，可选 SP-GiST/btree/hash（需运算符可索引）
- **表达式 WITH 运算符**: 核心——任意两行在该表达式上**满足**该运算符即冲突
- **INCLUDE**: PG 11+ 支持包含列（仅在索引项中存储，不参与排他判断）
- **WHERE 谓词**: 部分排他约束，仅对满足谓词的行强制
- **DEFERRABLE**: 与 PRIMARY KEY/UNIQUE 一样支持延迟到事务结束才检查

### 最简单的例子: 等价于 UNIQUE

```sql
-- 这两种约束在语义上完全等价:
CREATE TABLE users1 (
    id BIGINT PRIMARY KEY,
    email TEXT,
    UNIQUE (email)
);

CREATE TABLE users2 (
    id BIGINT PRIMARY KEY,
    email TEXT,
    EXCLUDE USING btree (email WITH =)   -- "任意两行 email 不能 = "
);

-- UNIQUE 约束本质上就是 EXCLUDE WITH = 约束的语法糖
-- 二者在违反时报告的错误信息略有不同:
INSERT INTO users1 VALUES (1, 'a@example.com');
INSERT INTO users1 VALUES (2, 'a@example.com');
-- ERROR: duplicate key value violates unique constraint "users1_email_key"

INSERT INTO users2 VALUES (1, 'a@example.com');
INSERT INTO users2 VALUES (2, 'a@example.com');
-- ERROR: conflicting key value violates exclusion constraint "users2_email_excl"
-- DETAIL: Key (email)=(a@example.com) conflicts with existing key (email)=(a@example.com).
```

### 经典例子: tstzrange 时间段重叠防止

```sql
-- 1. 准备扩展: 整数+范围混合需要 btree_gist
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- 2. 会议室预订表
CREATE TABLE meeting_reservations (
    id BIGSERIAL PRIMARY KEY,
    room_id INTEGER NOT NULL,
    booker TEXT NOT NULL,
    period TSTZRANGE NOT NULL,
    -- 关键约束: 同一房间，时间段不可重叠
    EXCLUDE USING gist (
        room_id WITH =,                  -- 同一房间
        period WITH &&                    -- 时间段重叠
    )
);

-- 3. 测试无冲突写入
INSERT INTO meeting_reservations (room_id, booker, period) VALUES
    (101, 'Alice', '[2026-04-29 09:00+08, 2026-04-29 10:00+08)'),
    (101, 'Bob',   '[2026-04-29 10:00+08, 2026-04-29 11:00+08)'),  -- 紧接，不重叠
    (102, 'Alice', '[2026-04-29 09:00+08, 2026-04-29 10:00+08)');  -- 不同房间，OK

-- 4. 测试冲突: 与 Alice 在 101 室的预订重叠
INSERT INTO meeting_reservations (room_id, booker, period) VALUES
    (101, 'Carol', '[2026-04-29 09:30+08, 2026-04-29 10:30+08)');
-- ERROR: conflicting key value violates exclusion constraint
-- DETAIL: Key (room_id, period)=(101, ["2026-04-29 09:30+08","2026-04-29 10:30+08"))
--         conflicts with existing key (room_id, period)=(101, ["2026-04-29 09:00+08","2026-04-29 10:00+08")).
```

### EXCLUDE 与运算符的丰富组合

```sql
-- 例 1: 价格生效区间不可包含同一商品的另一个生效区间
CREATE TABLE product_prices (
    product_id BIGINT NOT NULL,
    price NUMERIC NOT NULL,
    valid_during DATERANGE NOT NULL,
    EXCLUDE USING gist (
        product_id WITH =,
        valid_during WITH @>     -- 任一区间不能包含另一区间
    )
);

-- 例 2: 二维点不可在指定半径内（避免地图上"过近"）
CREATE EXTENSION IF NOT EXISTS cube;
CREATE EXTENSION IF NOT EXISTS earthdistance;

CREATE TABLE cell_towers (
    id BIGSERIAL PRIMARY KEY,
    location POINT NOT NULL,
    -- 任两个基站不能在 100 米以内: 用距离运算符
    EXCLUDE USING gist (
        location WITH <-> AND distance < 100   -- 概念示意, 实际语法略复杂
    )
);

-- 例 3: 多个员工同时担任 manager 不允许，但 staff 可以多人
-- 用 WHERE 子句限定
CREATE TABLE department_managers (
    dept_id INTEGER NOT NULL,
    employee_id BIGINT NOT NULL,
    role TEXT NOT NULL,
    EXCLUDE (
        dept_id WITH =,
        role    WITH =
    ) WHERE (role = 'manager')   -- 仅对 manager 强制唯一
);

INSERT INTO department_managers VALUES
    (1, 100, 'manager'),
    (1, 101, 'staff'),
    (1, 102, 'staff');           -- OK (staff 不受约束)
INSERT INTO department_managers VALUES
    (1, 103, 'manager');          -- ERROR (dept 1 已有 manager)
```

### EXCLUDE 与 INSERT ... ON CONFLICT 的交互

PostgreSQL 9.5 引入的 `INSERT ... ON CONFLICT` 不直接支持 EXCLUDE 约束。

```sql
-- 这种语法对 EXCLUDE 约束**不工作**:
INSERT INTO meeting_reservations (room_id, booker, period) VALUES (...)
ON CONFLICT (room_id, period) DO NOTHING;
-- ERROR: there is no unique or exclusion constraint matching the ON CONFLICT specification

-- 必须显式指定约束名:
INSERT INTO meeting_reservations (room_id, booker, period) VALUES (...)
ON CONFLICT ON CONSTRAINT meeting_reservations_room_id_period_excl DO NOTHING;
-- 可工作（PG 11+），但不能使用 DO UPDATE
-- DO UPDATE 仅对 UNIQUE/PK 约束有效，对 EXCLUDE 不可用
```

### EXCLUDE 的延迟检查

```sql
-- 与 PK/UNIQUE 一样，EXCLUDE 支持 DEFERRABLE
CREATE TABLE periods (
    id INT,
    period TSTZRANGE,
    EXCLUDE USING gist (period WITH &&)
        DEFERRABLE INITIALLY DEFERRED
);

BEGIN;
INSERT INTO periods VALUES (1, '[2026-04-01, 2026-05-01)');
INSERT INTO periods VALUES (2, '[2026-04-15, 2026-05-15)');
-- 不立即报错，事务内可继续操作

UPDATE periods SET period = '[2026-06-01, 2026-07-01)' WHERE id = 2;
COMMIT;   -- 事务结束时检查，发现 id=2 已不重叠，提交成功

-- 反例: 提交时仍重叠
BEGIN;
INSERT INTO periods VALUES (3, '[2026-06-15, 2026-07-15)');  -- 与 id=2 重叠
COMMIT;
-- ERROR: conflicting key value violates exclusion constraint "periods_period_excl"
```

## EXCLUDE 的物理实现: GiST 索引

### GiST 索引框架的角色

PostgreSQL 的 GiST（Generalized Search Tree）是一个**可扩展的平衡树索引框架**，由 Hellerstein, Naughton 和 Pfeffer 在 1995 年的 SIGMOD 论文 "Generalized Search Trees for Database Systems" 中提出，PostgreSQL 7.x（约 2000 年）开始集成。

GiST 的核心抽象: 用户为自定义数据类型实现 7 个支持函数:

```
1. consistent(p, q, strategy) - 谓词 p 与查询 q 在策略 strategy 下是否一致
2. union(P)                    - 多个谓词的最小覆盖
3. compress(p)                 - 谓词压缩存储
4. decompress(p)               - 谓词解压
5. penalty(p1, p2)             - 将 p2 加入 p1 子树的代价
6. picksplit(P)                - 节点分裂策略
7. equal(p1, p2)               - 谓词相等判断
```

实现这 7 个函数后，GiST 自动支持: 基于谓词的搜索、范围/重叠/包含查询、KNN 邻近搜索、以及——**排他约束**。

### EXCLUDE 在 GiST 上的执行流程

```
插入新行 R 的流程:
1. 取出 EXCLUDE 表达式列的值 V
2. 对 GiST 索引执行扫描: 查找所有满足 (V WITH operator existing_V) 的行
3. 如果扫描结果**非空** → 违反约束，回滚
4. 如果扫描结果**为空** → 将 V 插入 GiST 索引
5. 通过 SnapshotDirty 处理并发: 还能看到未提交事务的行，等待其结束
```

关键性能特性:

- **写入路径**: 每次 INSERT/UPDATE 须执行一次 GiST 范围扫描，复杂度 O(log N + k)，k 为冲突候选数
- **MVCC 兼容**: 通过 snapshot dirty 读 + 等待并发事务，保证强一致
- **空间换时间**: GiST 索引比同样列的 B-tree 索引大 2-5 倍

### btree_gist 扩展: 整数+范围混合的关键

PostgreSQL 默认 GiST 不支持基础类型（int/text 等）的等值索引，因为这些类型的常规索引选择是 B-tree。但排他约束经常需要"`int_col WITH =` AND `range_col WITH &&`"这种混合语义。`btree_gist` 扩展（PG contrib 包）正好填补这一空缺:

```sql
-- 不安装 btree_gist 时:
CREATE TABLE rooms (
    room_id INTEGER,
    period  TSTZRANGE,
    EXCLUDE USING gist (room_id WITH =, period WITH &&)
);
-- ERROR: data type integer has no default operator class for access method "gist"
-- HINT: You must specify an operator class for the index or define a default operator class

-- 安装 btree_gist 后:
CREATE EXTENSION btree_gist;
CREATE TABLE rooms (
    room_id INTEGER,
    period  TSTZRANGE,
    EXCLUDE USING gist (room_id WITH =, period WITH &&)   -- OK
);
```

`btree_gist` 为 int2/int4/int8/float4/float8/numeric/text/bpchar/varchar/bytea/timestamp/timestamptz/date/time/timetz/interval/uuid/cidr/inet/bool/oid/money/macaddr/bit/varbit 等基础类型提供 GiST 默认运算符类，这是 EXCLUDE 实战中**几乎必装**的扩展。

### SP-GiST 作为替代方案

PostgreSQL 9.2 引入 SP-GiST（Space-Partitioned GiST）作为非平衡分区树的索引框架，对某些类型（点、IP、范围）更高效:

```sql
-- 9.3 起 range_ops 在 SP-GiST 上可用
CREATE INDEX ON reservations USING spgist (period range_ops);

-- 但 EXCLUDE 约束目前**不支持** USING spgist (PG 16 起开始支持，仍部分受限)
-- 在大多数生产环境，EXCLUDE 仍以 USING gist 为主
```

## 各引擎对比

### PostgreSQL: 唯一原生实现

```sql
-- 完整示例: 课表系统避免老师时间冲突
CREATE EXTENSION btree_gist;
CREATE TABLE teaching_schedule (
    id BIGSERIAL PRIMARY KEY,
    teacher_id INT NOT NULL,
    classroom TEXT NOT NULL,
    course_period TSTZRANGE NOT NULL,
    -- 老师同一时间不能同时在多个地方
    EXCLUDE USING gist (
        teacher_id WITH =,
        course_period WITH &&
    ),
    -- 教室同一时间不能两个班
    EXCLUDE USING gist (
        classroom WITH =,
        course_period WITH &&
    )
);

-- 状态: 完全工作；GiST 索引自动维护
```

### Greenplum: 完全继承

Greenplum（基于 PG 8.x-12.x 演化）完全保留了 EXCLUDE 约束，但有两点限制:

```sql
-- 1. 分布式表的排他约束需要包含分布键
CREATE TABLE rooms (
    room_id INT,
    period TSTZRANGE,
    EXCLUDE USING gist (room_id WITH =, period WITH &&)
)
DISTRIBUTED BY (room_id);    -- 分布键必须出现在 EXCLUDE 中且为 WITH =

-- 2. AOCS（追加优化列存储）表不支持 EXCLUDE
-- 只能在 heap 表上使用
```

### TimescaleDB: 完全兼容

TimescaleDB 在标准 PostgreSQL 上构建，EXCLUDE 完全可用，且 hypertable（自动分块表）也支持:

```sql
CREATE EXTENSION btree_gist;
CREATE EXTENSION timescaledb;

CREATE TABLE sensor_calibrations (
    sensor_id INT NOT NULL,
    valid_during TSTZRANGE NOT NULL,
    calibration JSON NOT NULL,
    EXCLUDE USING gist (sensor_id WITH =, valid_during WITH &&)
);

SELECT create_hypertable('sensor_calibrations', by_range('valid_during'));
-- EXCLUDE 在每个 chunk 内部独立强制
```

### YugabyteDB: 部分支持，存在限制

YugabyteDB 是 PG 兼容的分布式数据库，但底层是 LSM 存储引擎，EXCLUDE 实现有限制:

```sql
-- YB 2.6+ 开始支持 EXCLUDE，但要求:
-- 1. 必须包含表分片键 (HASH/RANGE)
-- 2. 仅支持 = WITH，范围重叠 WITH && 在 v2.21 前不可用
-- 3. GiST 索引在 LSM 上效率低于原生 PG

CREATE TABLE rooms (
    room_id INT,
    period TSTZRANGE,
    PRIMARY KEY (room_id, period)
)
SPLIT INTO 16 TABLETS;

-- 简单等值排他可用
ALTER TABLE rooms
ADD CONSTRAINT room_unique
    EXCLUDE USING btree (room_id WITH =);   -- 等价于 UNIQUE，可用

-- 范围重叠 EXCLUDE 在新版本 (2.21+) 才完整支持
```

### MariaDB: WITHOUT OVERLAPS（窄场景标准化）

MariaDB 10.5（2020）实现了 SQL:2011 应用时间段表的 `WITHOUT OVERLAPS` 子句，这是排他约束在标准侧的**狭义实现**:

```sql
CREATE TABLE meeting_reservations (
    room_id INT NOT NULL,
    booker  VARCHAR(100) NOT NULL,
    start_time DATETIME NOT NULL,
    end_time   DATETIME NOT NULL,
    PERIOD FOR meeting_period (start_time, end_time),
    -- WITHOUT OVERLAPS: 同 room_id + 时间段不重叠
    PRIMARY KEY (room_id, meeting_period WITHOUT OVERLAPS)
);

INSERT INTO meeting_reservations VALUES
    (101, 'Alice', '2026-04-29 09:00:00', '2026-04-29 10:00:00'),
    (101, 'Bob',   '2026-04-29 09:30:00', '2026-04-29 10:30:00');
-- ERROR 1062 (23000): Duplicate entry '101' for key 'PRIMARY'
-- 类似 PG EXCLUDE 的语义，但只能用于 PRIMARY KEY/UNIQUE 上下文

-- 限制:
-- 1. 只能与 PERIOD 类型组合，不支持任意范围列
-- 2. 只能表达"重叠"语义，不支持任意运算符
-- 3. 不支持非时间类型（不能写"两点距离 < 100"）
-- 4. 仅 PRIMARY KEY/UNIQUE 可用，不能作为独立 EXCLUDE 约束
```

### Oracle: 触发器 + SELECT FOR UPDATE 模拟

Oracle 没有原生 EXCLUDE 约束。最常见的等价方案是**约束触发器**:

```sql
-- 表设计
CREATE TABLE meeting_reservations (
    id NUMBER PRIMARY KEY,
    room_id NUMBER NOT NULL,
    booker  VARCHAR2(100) NOT NULL,
    start_time TIMESTAMP NOT NULL,
    end_time   TIMESTAMP NOT NULL,
    CHECK (start_time < end_time)
);

-- 索引 (用于触发器内查询加速)
CREATE INDEX idx_room_time ON meeting_reservations (room_id, start_time, end_time);

-- 触发器: 检查重叠
CREATE OR REPLACE TRIGGER meeting_overlap_check
BEFORE INSERT OR UPDATE ON meeting_reservations
FOR EACH ROW
DECLARE
    cnt NUMBER;
BEGIN
    -- 关键: 用 SELECT FOR UPDATE 锁住可能冲突的行，防并发竞态
    SELECT COUNT(*) INTO cnt
    FROM meeting_reservations
    WHERE room_id = :NEW.room_id
      AND id <> NVL(:NEW.id, -1)
      AND start_time < :NEW.end_time
      AND end_time   > :NEW.start_time
    FOR UPDATE;

    IF cnt > 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'Reservation overlaps with existing booking');
    END IF;
END;
/

-- 风险:
-- 1. 行级触发器在并发插入时仍可能错过新插入的行（PHANTOM）
-- 2. 即使加 FOR UPDATE，也只锁现有行，不阻止其他事务插入新冲突行
-- 3. 真正可靠的方案: 配合 SERIALIZABLE 隔离级别
-- 4. 或者用包级触发器 + materialized view + UNIQUE 索引
```

### Oracle: 物化视图 + UNIQUE 模式

更强一致性的 Oracle 方案是物化视图技巧:

```sql
-- 思路: 将每分钟离散化为一行，对 (room_id, minute) 加 UNIQUE 索引
-- 适用于"会议室按分钟粒度"等离散场景

CREATE MATERIALIZED VIEW LOG ON meeting_reservations WITH ROWID, SEQUENCE
INCLUDING NEW VALUES;

CREATE MATERIALIZED VIEW mv_room_minute_occupied
BUILD IMMEDIATE
REFRESH FAST ON COMMIT
AS
SELECT m.room_id,
       m.start_time + LEVEL/1440 - 1/1440 AS minute_slot
FROM meeting_reservations m
CONNECT BY LEVEL <= (m.end_time - m.start_time) * 1440
       AND PRIOR id = id
       AND PRIOR DBMS_RANDOM.VALUE IS NOT NULL;

CREATE UNIQUE INDEX uk_room_minute ON mv_room_minute_occupied (room_id, minute_slot);
-- 任何造成重叠的 INSERT 都会在 COMMIT 时因唯一索引违反而回滚
-- 缺点: 仅对离散粒度场景适用，连续时间无法精确表达
```

### SQL Server: 过滤索引 + CHECK 约束

SQL Server 没有 EXCLUDE 约束，但**过滤索引**（filtered index）+ 计算列可以处理某些等值排他场景:

```sql
-- 场景: 一个用户最多一个 'active' 会话
CREATE TABLE user_sessions (
    id BIGINT IDENTITY PRIMARY KEY,
    user_id BIGINT NOT NULL,
    status  VARCHAR(20) NOT NULL,
    started_at DATETIME2 NOT NULL,
    ended_at   DATETIME2 NULL
);

-- 过滤唯一索引: 只对 status='active' 的行强制 user_id 唯一
CREATE UNIQUE INDEX uk_one_active_per_user
ON user_sessions (user_id)
WHERE status = 'active';

INSERT INTO user_sessions (user_id, status, started_at) VALUES (1, 'active', GETDATE());
INSERT INTO user_sessions (user_id, status, started_at) VALUES (1, 'active', GETDATE());
-- ERROR: Cannot insert duplicate key row in object 'user_sessions'
INSERT INTO user_sessions (user_id, status, started_at) VALUES (1, 'closed', GETDATE());
-- OK (closed 不参与索引)
```

但**时间段重叠**这类 EXCLUDE 在 SQL Server 上没有索引级方案，只能用触发器:

```sql
CREATE TRIGGER trg_no_overlap
ON meeting_reservations
INSTEAD OF INSERT, UPDATE
AS
BEGIN
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    BEGIN TRANSACTION;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN meeting_reservations r WITH (HOLDLOCK, UPDLOCK)
            ON r.room_id = i.room_id
        WHERE r.id <> i.id
          AND r.start_time < i.end_time
          AND r.end_time   > i.start_time
    )
    BEGIN
        ROLLBACK TRANSACTION;
        RAISERROR('Reservation overlaps', 16, 1);
        RETURN;
    END;

    -- 实际写入
    INSERT INTO meeting_reservations (room_id, booker, start_time, end_time)
    SELECT room_id, booker, start_time, end_time FROM inserted;

    COMMIT TRANSACTION;
END;
-- 注: HOLDLOCK + SERIALIZABLE 是关键，否则有 phantom 风险
```

### MySQL: 不支持，仅 SERIALIZABLE 等价

MySQL 截至 8.x 完全不支持 EXCLUDE 类约束，也不支持 PERIOD 类型:

```sql
-- 唯一可靠的方案: 应用层在 SERIALIZABLE 隔离级别下重叠检查
SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE;

START TRANSACTION;

-- 1. 检查冲突 (在 SERIALIZABLE 下，这次 SELECT 会加范围锁)
SELECT id FROM meeting_reservations
WHERE room_id = 101
  AND start_time < '2026-04-29 11:00:00'
  AND end_time   > '2026-04-29 09:00:00';

-- 2. 若空则插入
INSERT INTO meeting_reservations (room_id, booker, start_time, end_time)
VALUES (101, 'Alice', '2026-04-29 09:00:00', '2026-04-29 10:00:00');

COMMIT;

-- 缺点:
-- 1. SERIALIZABLE 性能差，写并发严重退化
-- 2. 应用层逻辑承担一致性责任
-- 3. 触发器不能用 SET TRANSACTION ISOLATION (MySQL 限制)
```

MySQL 的应用层加锁惯用方案是 `GET_LOCK()`:

```sql
-- 用应用锁串行化对同一资源的并发写
SELECT GET_LOCK(CONCAT('room:', 101), 5);   -- 获取 room 101 的应用锁，超时 5s
-- ... 检查 + 插入 ...
SELECT RELEASE_LOCK(CONCAT('room:', 101));
-- 缺点: 锁是会话级，跨连接不强制；网络分区可能丢锁
```

### DB2: 触发器 + RR 隔离级别

DB2 的方案与 Oracle 类似，使用触发器 + Repeatable Read:

```sql
CREATE TRIGGER overlap_check
BEFORE INSERT ON meeting_reservations
REFERENCING NEW AS n
FOR EACH ROW
WHEN (
    EXISTS (
        SELECT 1 FROM meeting_reservations r
        WHERE r.room_id = n.room_id
          AND r.id <> n.id
          AND (r.start_time, r.end_time) OVERLAPS (n.start_time, n.end_time)
    )
)
SIGNAL SQLSTATE '75000' SET MESSAGE_TEXT = 'Overlap detected';

-- DB2 支持 OVERLAPS 谓词（SQL:1992 时间段比较），可读性好
-- 但仍需事务隔离级别配合保证并发安全
```

### CockroachDB: SERIALIZABLE 默认 + 应用层 CHECK

CockroachDB 默认 SERIALIZABLE 隔离级别（v22.2+ 之前），但**不支持 EXCLUDE 约束**:

```sql
-- CockroachDB 没有 EXCLUDE，但因默认 SERIALIZABLE，应用层重叠检查可靠
BEGIN;
SELECT count(*) FROM meeting_reservations
WHERE room_id = 101
  AND start_time < '2026-04-29 11:00:00'
  AND end_time   > '2026-04-29 09:00:00';
-- 若 count = 0 则:
INSERT INTO meeting_reservations VALUES (...);
COMMIT;

-- CockroachDB SERIALIZABLE + 范围扫描 = 可串行化的重叠检测
-- 但相比 PG EXCLUDE 多了一次额外扫描和 SSI 验证开销
```

### SQLite/H2/Firebird: 完全不支持

这些嵌入式/轻量引擎完全不支持 EXCLUDE 类约束，也无 PERIOD/范围类型:

```sql
-- 唯一方案: 应用层串行写 + CHECK
-- SQLite 单写者特性使得简单 SELECT-then-INSERT 在串行写下天然无冲突

BEGIN IMMEDIATE;   -- SQLite 立即获取 RESERVED 锁
SELECT count(*) FROM meeting_reservations WHERE ...;
-- 若 0 则 INSERT
COMMIT;
-- SQLite 单写者保证: 任意时刻仅一个事务能写
```

### Snowflake/BigQuery/Redshift: 完全不支持

云数仓引擎普遍不支持 EXCLUDE，也通常不强制 PRIMARY KEY/UNIQUE。重叠检查只能在应用层:

```sql
-- Snowflake: 借助 MERGE 语义做"插入前确认无冲突"
MERGE INTO meeting_reservations t
USING (SELECT 101 AS room_id, '...'::TIMESTAMP AS s, '...'::TIMESTAMP AS e) s
ON t.room_id = s.room_id
   AND t.start_time < s.e
   AND t.end_time   > s.s
WHEN NOT MATCHED THEN INSERT (room_id, start_time, end_time)
  VALUES (s.room_id, s.s, s.e);
-- 单条 MERGE 是原子的，但跨多个 MERGE 的并发仍可能竞态（OLAP 引擎并发模型有限）
```

### ClickHouse/Doris/StarRocks: 列存引擎，无约束

OLAP 列存引擎完全不支持任何约束（包括 PK/UNIQUE/CHECK/EXCLUDE）:

```sql
-- ClickHouse: ENGINE 决定语义，无运行时约束
-- ReplacingMergeTree 提供"最后写入获胜"的去重，不是 EXCLUDE 等价物
-- 排他约束的使用场景在 OLAP 模型中通常不适用
```

## EXCLUDE 经典使用模式

### 模式 1: 单一活动状态约束

"任意时刻每个用户最多一个活动会话":

```sql
CREATE EXTENSION btree_gist;
CREATE TABLE user_sessions (
    user_id BIGINT NOT NULL,
    session_id UUID NOT NULL,
    valid_period TSTZRANGE NOT NULL,
    EXCLUDE USING gist (
        user_id WITH =,
        valid_period WITH &&
    )
);

-- 等价问题陈述: 不存在两行 r1, r2 使得 r1.user_id = r2.user_id AND r1.period && r2.period
-- 该约束在写入路径上自动强制，无竞态
```

### 模式 2: 资源不可超额预订

"机房带宽总额不能超过 100 Gbps":

```sql
-- 这种"加和约束"实际上 EXCLUDE 不能直接表达
-- EXCLUDE 是"集合排他"语义，不能做"求和 < N"约束
-- 需用 statement-level trigger 或 deferred trigger 配合
-- 这是 EXCLUDE 的能力边界
```

### 模式 3: WHERE 子句下的部分排他

"已激活的促销码全局唯一，未激活的可重复":

```sql
CREATE TABLE promo_codes (
    code TEXT,
    status TEXT,
    EXCLUDE (code WITH =) WHERE (status = 'active')
);

INSERT INTO promo_codes VALUES ('SAVE10', 'inactive');
INSERT INTO promo_codes VALUES ('SAVE10', 'inactive');   -- OK
INSERT INTO promo_codes VALUES ('SAVE10', 'active');
INSERT INTO promo_codes VALUES ('SAVE10', 'active');     -- ERROR
-- 等价于 SQL Server 的过滤唯一索引，但语法在 SQL 标准内更自然
```

### 模式 4: 连续区间不重叠

"价格历史不应有时间空洞或重叠":

```sql
CREATE TABLE product_prices (
    product_id INT NOT NULL,
    price NUMERIC NOT NULL,
    valid_during TSTZRANGE NOT NULL,
    EXCLUDE USING gist (product_id WITH =, valid_during WITH &&)
);

-- EXCLUDE 防止重叠，但不防止"空洞" (gap)
-- 防止空洞需要应用层或额外触发器逻辑
```

### 模式 5: 范围+其他列混合

```sql
-- 同一航线，同一航班号，时间段不重叠
CREATE TABLE flights (
    airline TEXT NOT NULL,
    flight_num INT NOT NULL,
    schedule TSTZRANGE NOT NULL,
    EXCLUDE USING gist (
        airline    WITH =,
        flight_num WITH =,
        schedule   WITH &&
    )
);
```

### 模式 6: 与 INCLUDE 的组合（PG 11+）

```sql
-- INCLUDE 列不参与排他判断，但存储在索引中以支持索引覆盖扫描
CREATE TABLE meeting_reservations (
    room_id INT NOT NULL,
    period TSTZRANGE NOT NULL,
    booker TEXT NOT NULL,
    notes  TEXT,
    EXCLUDE USING gist (
        room_id WITH =,
        period  WITH &&
    ) INCLUDE (booker)   -- booker 仅存储, 不影响约束
);

-- 后续查询 SELECT booker FROM meeting_reservations WHERE room_id = 101 AND ...
-- 可以仅扫描索引（index-only scan）
```

## 等价方案深入: 触发器、SERIALIZABLE 与 advisory lock

### 触发器方案的并发陷阱

触发器内的 SELECT-then-INSERT 在非 SERIALIZABLE 下**不安全**:

```
事务 A: BEGIN;
事务 B: BEGIN;
事务 A: SELECT count(*) FROM rooms WHERE room_id=101 AND overlap(...);   -- 0
事务 B: SELECT count(*) FROM rooms WHERE room_id=101 AND overlap(...);   -- 0
事务 A: INSERT INTO rooms VALUES (101, ...);
事务 B: INSERT INTO rooms VALUES (101, ...);   -- 与 A 重叠但 A 未提交
事务 A: COMMIT;
事务 B: COMMIT;   -- 两条重叠记录都成功
```

修复方案:

1. **SERIALIZABLE 隔离级别**: 数据库自动处理 phantom，性能差
2. **HOLDLOCK + 范围锁**（SQL Server）: 显式锁住范围，防新插入
3. **SELECT FOR UPDATE 整个目标分组**: 锁住一个父表行（如 rooms.room_id）
4. **应用 advisory lock**: 同 room_id 串行化

### Advisory Lock 方案（PG/MySQL 通用）

```sql
-- PostgreSQL:
BEGIN;
SELECT pg_advisory_xact_lock(101);   -- 对 room_id=101 加事务级锁，提交时自动释放
-- 此时其他对 101 的事务被阻塞
SELECT count(*) FROM meetings WHERE room_id=101 AND overlap(...);
INSERT INTO meetings VALUES (...);
COMMIT;

-- MySQL:
SELECT GET_LOCK(CONCAT('room:', 101), 10);
-- ... 检查 + 插入 ...
SELECT RELEASE_LOCK(CONCAT('room:', 101));
```

特点:
- 锁粒度**应用自定义**（room_id 级别），并发性优于全表锁
- 但**绕过 EXCLUDE 的索引扫描效率**: 每个事务都要 advisory lock + 完整扫描
- 应用层须严格遵守加锁协议，错误一处全盘崩溃

### MERGE/UPSERT 不能替代 EXCLUDE

```sql
-- MERGE 语义检查"键是否存在"，不能检查"是否重叠"
MERGE INTO meeting_reservations t
USING (...) s ON t.room_id = s.room_id   -- 等值匹配
WHEN ...;

-- MERGE 无法表达"任两行不能有 OVERLAPS 关系"
-- 跨多个 MERGE 的并发仍需事务隔离
```

### 物化"占位"表 + UNIQUE

某些离散场景可用此模式:

```sql
-- 思路: 将"占用"展开为离散的 (resource, time_unit) 二元组，加 UNIQUE
CREATE TABLE room_minute_occupancy (
    room_id INT,
    minute_ts TIMESTAMP,
    UNIQUE (room_id, minute_ts)
);

-- 插入会议时，应用展开成 N 行 (一行一分钟)，UNIQUE 索引保证不重复
INSERT INTO room_minute_occupancy
SELECT 101, generate_series(
    '2026-04-29 09:00'::timestamp,
    '2026-04-29 09:59'::timestamp,
    '1 minute'
);
-- 任何重叠会因 UNIQUE 违反而失败

-- 优点: 任何引擎都能用
-- 缺点: 1) 只对离散粒度有效 2) 行膨胀严重 3) 删除/更新麻烦
```

## 与 SQL:2011 PERIOD 的关系

SQL:2011 引入应用时间段表 + WITHOUT OVERLAPS，可视为 EXCLUDE 在标准侧的窄场景实现:

```sql
-- SQL:2011 标准（MariaDB 实现）:
CREATE TABLE rooms (
    room_id INT NOT NULL,
    booker  TEXT NOT NULL,
    s_time  TIMESTAMP,
    e_time  TIMESTAMP,
    PERIOD FOR active_period (s_time, e_time),
    PRIMARY KEY (room_id, active_period WITHOUT OVERLAPS)
);

-- PG 等价:
CREATE TABLE rooms (
    room_id INT NOT NULL,
    booker  TEXT NOT NULL,
    period  TSTZRANGE NOT NULL,
    EXCLUDE USING gist (room_id WITH =, period WITH &&)
);

-- 比较:
-- SQL:2011: 仅限 PERIOD + 重叠语义；语法在 PRIMARY KEY/UNIQUE 子句内
-- PostgreSQL: 任意类型 + 任意运算符；独立 EXCLUDE 子句，更通用
```

PG 方案表达力更强，但 SQL:2011 方案语法更"标准"。可惜两者都未在主流 OLTP 引擎中广泛实现。

## 关键发现

1. **PostgreSQL 是唯一原生支持广义 EXCLUDE 约束的主流 SQL 引擎**——Greenplum/TimescaleDB/YugabyteDB 等均为继承 PG 代码而获得该能力，独立实现的引擎为零。

2. **没有 SQL 标准**: SQL:2011 仅以 `WITHOUT OVERLAPS` 标准化了"PERIOD 时间段重叠"这一窄场景，无法表达 PG EXCLUDE 的任意运算符语义。MariaDB 是少数实现 `WITHOUT OVERLAPS` 的引擎。

3. **GiST 索引框架是 EXCLUDE 的物理基石**——其他引擎缺乏类似的可扩展索引框架是难以推广 EXCLUDE 的根本技术原因；BTree 与 LSM 虽然主流但只能表达等值与范围，无法直接表达"重叠/包含/距离<阈值"这类丰富语义。

4. **混合等值+范围排他需要 btree_gist 扩展**——纯范围列默认 GiST 即可，但实战中"相同 room_id + 时间段不重叠"需要把整数也加进 GiST 索引项，必须安装 contrib 扩展。

5. **范围重叠（&& 运算符）+ tstzrange 是 EXCLUDE 最经典的使用场景**——会议预订、医生排班、价格历史、设备占用等场景都遵循该模式；这也是 PostgreSQL 在时间型业务系统中具有显著优势的特性之一。

6. **触发器模拟方案在非 SERIALIZABLE 隔离级别下天然不可靠**——并发 SELECT-then-INSERT 即使加 FOR UPDATE 也存在 phantom 风险，必须配合 SERIALIZABLE 或显式范围锁。这一点在 Oracle/DB2/MySQL 工程实践中常被忽略。

7. **SQL Server 的过滤唯一索引适合"等值排他+条件"，但无法处理时间段重叠**——`UNIQUE WHERE status='active'` 在等值场景优雅，重叠场景仍需触发器+HOLDLOCK。

8. **MySQL/SQLite 没有任何索引级排他能力**——MySQL 的 SERIALIZABLE 性能差，SQLite 的单写者特性虽然天然串行但仍是事后检查模型。生产环境中 MySQL 实现"会议室不重叠"通常是应用层 advisory lock + 检查。

9. **OLAP/数据湖引擎（Snowflake/BigQuery/Redshift/ClickHouse 等）几乎全部不支持 EXCLUDE 及任何强制约束**——这是分析型系统的设计取舍，写入侧优先吞吐，约束在 ETL 上游处理。

10. **CockroachDB 默认 SERIALIZABLE 隔离级别使得应用层重叠检查可靠**，但缺少索引级排他意味着每次插入都需要范围扫描 + SSI 验证，性能远低于 PG GiST 索引扫描。

11. **EXCLUDE 与 INSERT ... ON CONFLICT 的交互受限**——只能用 `ON CONFLICT ON CONSTRAINT 名` 形式表达，且不支持 DO UPDATE，这与 EXCLUDE 的非等值语义有关（不存在唯一可更新的"主行"）。

12. **EXCLUDE 不能表达加和/聚合约束**——"总和不超过 N"、"组内最大不超过 M" 等需 deferred trigger 或 statement-level 检查；EXCLUDE 仅能表达"任意两行的成对关系"。

13. **DEFERRABLE EXCLUDE 在事务内允许临时违反**，对于"两个行交换时间段"等场景至关重要，是 PG EXCLUDE 不可替代的优势。

14. **YugabyteDB 等基于 LSM 的 PG 兼容引擎对 EXCLUDE 支持不完整**——LSM 索引天然不适合 GiST，分布式分片要求约束键必须包含分布键，灵活性显著低于原生 PG。

15. **Materialize/RisingWave 等流式 SQL 引擎完全不支持 EXCLUDE**——增量计算模型与"任意两行排他"语义存在根本冲突，目前未见相关研究或实现。

16. **EXCLUDE 在跨引擎迁移中是高难点**——从 PG 迁出时几乎必须重写为应用层逻辑或触发器+SERIALIZABLE，是 PG → Oracle/MySQL 迁移的常见障碍。

## 参考资料

- PostgreSQL: [CREATE TABLE - EXCLUDE](https://www.postgresql.org/docs/current/sql-createtable.html#SQL-CREATETABLE-EXCLUDE-ELEMENT)
- PostgreSQL Wiki: [Exclusion Constraints](https://wiki.postgresql.org/wiki/Exclusion_Constraints)
- PostgreSQL: [btree_gist extension](https://www.postgresql.org/docs/current/btree-gist.html)
- PostgreSQL: [GiST Indexes](https://www.postgresql.org/docs/current/gist.html)
- Hellerstein, Naughton, Pfeffer. "Generalized Search Trees for Database Systems" (1995), SIGMOD
- Davis, Jeff. "Range Types and Exclusion Constraints" (2009), PGCon
- ISO/IEC 9075-2:2011, Section 4.15.10 (Application-time period tables)
- MariaDB: [Application-time periods](https://mariadb.com/kb/en/application-time-periods/)
- Oracle: [CREATE TRIGGER](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/CREATE-TRIGGER.html)
- SQL Server: [Filtered Indexes](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/create-filtered-indexes)
- Microsoft Research: "Snapshot Isolation" (Berenson et al, 1995)
- Greenplum: [Exclusion Constraints in MPP](https://docs.vmware.com/en/VMware-Greenplum/index.html)
- TimescaleDB: [Constraints in Hypertables](https://docs.timescale.com/use-timescale/latest/hypertables/)
- YugabyteDB: [Exclusion Constraints](https://docs.yugabyte.com/preview/api/ysql/the-sql-language/statements/ddl_create_table/)
- CockroachDB: [SERIALIZABLE Isolation](https://www.cockroachlabs.com/docs/stable/architecture/transaction-layer.html)
