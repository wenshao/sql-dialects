# 时区处理 (Timezone Handling)

凌晨 3 点的告警、跨年的报表对不上、夏令时切换那一晚的订单凭空消失——时区是 SQL 数据库领域最常被低估、也最容易在生产环境引发故障的一类问题。同一个 `TIMESTAMP` 字面量，在 PostgreSQL、MySQL、Oracle、Snowflake 中可能代表完全不同的瞬间；同一段 `CURRENT_TIMESTAMP` 代码，在客户机器和服务器机器上跑出来可能差 8 个小时。本文系统对比 45+ 数据库引擎对时区的存储模型、转换语义、夏令时处理与时区数据更新机制，帮助引擎使用者和实现者绕开这些"隐形的坑"。

> 本文聚焦于**时区语义**本身。一般日期/时间函数的命名差异（`DATE_TRUNC` / `DATE_FORMAT` / `DATEADD` 等）请参见配套文章 [`datetime-functions-mapping.md`](./datetime-functions-mapping.md)。

## SQL 标准对时区的定义

### SQL:1992 — 引入 WITH TIME ZONE

SQL:1992 (ISO/IEC 9075:1992) 在 6.1 `<data type>` 中正式引入两个带时区的类型：

```sql
TIME [ ( <time precision> ) ] WITH TIME ZONE
TIMESTAMP [ ( <timestamp precision> ) ] WITH TIME ZONE
```

标准的核心规定：

1. **存储模型**：值由"日期 + 时间 + 时区偏移量 (interval hour to minute)"三部分组成，偏移范围 `-12:59` 到 `+14:00`
2. **比较语义**：两个 `TIMESTAMP WITH TIME ZONE` 比较时先归一化到 UTC 再比较，因此 `'2026-01-01 12:00:00+08:00' = '2026-01-01 04:00:00+00:00'` 为真
3. **AT TIME ZONE**：标准的 `<datetime value expression> AT TIME ZONE <interval>` 操作符，用于把一个时间转换到指定偏移
4. **CURRENT_TIMESTAMP**：标准要求返回 `TIMESTAMP WITH TIME ZONE`

注意：SQL:1992 标准只规定**存储 UTC 偏移量**（`-12:59` ~ `+14:00`），并没有要求存储 IANA 时区名（如 `Asia/Shanghai`）。这是 Oracle 后来扩展的方向。

### SQL:1999 — 引入 WITH LOCAL TIME ZONE

SQL:1999 增加了 Oracle 风格的 `WITH LOCAL TIME ZONE`：

```sql
TIMESTAMP [ ( <timestamp precision> ) ] WITH LOCAL TIME ZONE
```

语义：值在数据库中**始终以 UTC 存储**，但读取时**自动转换为会话当前时区**显示。它与 `WITH TIME ZONE` 的核心差异在于"是否记住原始的偏移量"：

| 类型 | 物理存储 | 读取展示 | 记住原始偏移量 |
|------|---------|---------|-------------|
| `TIMESTAMP WITHOUT TIME ZONE` | 字面值 | 字面值 | -- |
| `TIMESTAMP WITH TIME ZONE` | UTC + 原始偏移 | 原始偏移 | 是 |
| `TIMESTAMP WITH LOCAL TIME ZONE` | UTC | 会话时区 | 否 |

这三种类型构成了现代 SQL 时区设计的三大流派。下文的 45+ 引擎对比，本质上都是这三种语义的不同组合与命名。

## 支持矩阵（综合）

### 1. 类型系统：三种 TIMESTAMP 变体支持情况

| 引擎 | TIMESTAMP WITH TZ | TIMESTAMP WITH LOCAL TZ | TIMESTAMP WITHOUT TZ | 默认 TIMESTAMP 含义 |
|------|-------------------|------------------------|---------------------|-------------------|
| PostgreSQL | `TIMESTAMPTZ` | -- (LOCAL 即默认行为) | `TIMESTAMP` | WITHOUT TIME ZONE |
| MySQL | `TIMESTAMP`(隐式) | -- | `DATETIME` | 隐式 LOCAL（按 time_zone 转换） |
| MariaDB | `TIMESTAMP` | -- | `DATETIME` | 同 MySQL |
| SQLite | -- (无原生类型) | -- | TEXT/INTEGER | 仅字符串 |
| Oracle | `TIMESTAMP WITH TIME ZONE` | `TIMESTAMP WITH LOCAL TIME ZONE` | `TIMESTAMP` | WITHOUT TIME ZONE |
| SQL Server | `DATETIMEOFFSET` | -- | `DATETIME2` / `DATETIME` | WITHOUT TIME ZONE |
| DB2 | `TIMESTAMP WITH TIME ZONE` (10.1+) | -- | `TIMESTAMP` | WITHOUT TIME ZONE |
| Snowflake | `TIMESTAMP_TZ` | `TIMESTAMP_LTZ` | `TIMESTAMP_NTZ` | 由 TIMESTAMP_TYPE_MAPPING 决定 |
| BigQuery | `TIMESTAMP` (始终 UTC) | -- | `DATETIME` | TIMESTAMP 即 UTC |
| Redshift | `TIMESTAMPTZ` | -- | `TIMESTAMP` | WITHOUT TIME ZONE |
| DuckDB | `TIMESTAMPTZ` | -- | `TIMESTAMP` | WITHOUT TIME ZONE |
| ClickHouse | `DateTime('TZ')` | -- | `DateTime` | 按列定义 |
| Trino | `TIMESTAMP WITH TIME ZONE` | -- | `TIMESTAMP` | WITHOUT TIME ZONE |
| Presto | `TIMESTAMP WITH TIME ZONE` | -- | `TIMESTAMP` | WITHOUT TIME ZONE |
| Spark SQL | `TIMESTAMP` (LTZ 语义) | 隐式 | `TIMESTAMP_NTZ` (3.4+) | 历史上为 LTZ |
| Hive | `TIMESTAMP WITH LOCAL TIME ZONE` (3.1+) | 是 | `TIMESTAMP` | WITHOUT TIME ZONE |
| Flink SQL | `TIMESTAMP_LTZ` | 是 | `TIMESTAMP` | WITHOUT TIME ZONE |
| Databricks | `TIMESTAMP` (LTZ) | 是 | `TIMESTAMP_NTZ` | LTZ |
| Teradata | `TIMESTAMP WITH TIME ZONE` | -- | `TIMESTAMP` | WITHOUT TIME ZONE |
| Greenplum | `TIMESTAMPTZ` | -- | `TIMESTAMP` | WITHOUT TIME ZONE |
| CockroachDB | `TIMESTAMPTZ` | -- | `TIMESTAMP` | WITHOUT TIME ZONE |
| TiDB | `TIMESTAMP` (兼容 MySQL) | -- | `DATETIME` | 隐式 LOCAL |
| OceanBase | `TIMESTAMP WITH TIME ZONE` (Oracle 模式) | `WITH LOCAL TIME ZONE` (Oracle 模式) | `TIMESTAMP` | 模式相关 |
| YugabyteDB | `TIMESTAMPTZ` | -- | `TIMESTAMP` | 继承 PG |
| SingleStore | -- | -- | `DATETIME` / `TIMESTAMP` | 类似 MySQL |
| Vertica | `TIMESTAMPTZ` | -- | `TIMESTAMP` | WITHOUT TIME ZONE |
| Impala | `TIMESTAMP` (UTC 存储) | -- | `TIMESTAMP` | 受 use_local_tz_for_unix_timestamp_conversions 影响 |
| StarRocks | -- | -- | `DATETIME` | WITHOUT TIME ZONE |
| Doris | -- | -- | `DATETIME` | WITHOUT TIME ZONE |
| MonetDB | `TIMESTAMP WITH TIME ZONE` | -- | `TIMESTAMP` | WITHOUT TIME ZONE |
| CrateDB | -- | -- | `TIMESTAMP WITH/WITHOUT TZ` | WITHOUT (始终存毫秒数) |
| TimescaleDB | `TIMESTAMPTZ` | -- | `TIMESTAMP` | 继承 PG |
| QuestDB | -- | -- | `TIMESTAMP` (微秒 epoch) | UTC epoch |
| Exasol | -- | -- | `TIMESTAMP` / `TIMESTAMP WITH LOCAL TIME ZONE` | LOCAL 可选 |
| SAP HANA | -- | -- | `TIMESTAMP` / `SECONDDATE` | WITHOUT |
| Informix | -- | -- | `DATETIME YEAR TO FRACTION` | WITHOUT |
| Firebird | -- | `TIMESTAMP WITH TIME ZONE` (4.0+) | `TIMESTAMP` | WITHOUT |
| H2 | `TIMESTAMP WITH TIME ZONE` | -- | `TIMESTAMP` | WITHOUT |
| HSQLDB | `TIMESTAMP WITH TIME ZONE` | -- | `TIMESTAMP` | WITHOUT |
| Derby | -- | -- | `TIMESTAMP` | WITHOUT (无时区类型) |
| Amazon Athena | `TIMESTAMP WITH TIME ZONE` | -- | `TIMESTAMP` | 继承 Trino |
| Azure Synapse | `DATETIMEOFFSET` | -- | `DATETIME2` | WITHOUT |
| Google Spanner | `TIMESTAMP` (UTC) | -- | -- | 始终 UTC |
| Materialize | `TIMESTAMPTZ` | -- | `TIMESTAMP` | WITHOUT (继承 PG) |
| RisingWave | `TIMESTAMPTZ` | -- | `TIMESTAMP` | WITHOUT (继承 PG) |
| InfluxDB (SQL) | -- | -- | `TIMESTAMP` (UTC ns) | 始终 UTC |
| Databend | `TIMESTAMP` (UTC) | -- | -- | 始终 UTC，按会话显示 |
| Yellowbrick | `TIMESTAMPTZ` | -- | `TIMESTAMP` | 继承 PG |
| Firebolt | -- | -- | `TIMESTAMPNTZ` / `TIMESTAMPTZ` | NTZ |

> 统计：约 30 个引擎提供原生 `WITH TIME ZONE`，约 8 个提供 `WITH LOCAL TIME ZONE`，约 6 个 `TIMESTAMP` 始终意味着 UTC，约 8 个根本没有"带时区"的概念。

### 2. AT TIME ZONE 操作符与转换函数

| 引擎 | AT TIME ZONE | CONVERT_TZ | FROM_TZ | 自定义函数 |
|------|--------------|-----------|---------|----------|
| PostgreSQL | 是 | -- | -- | -- |
| MySQL | -- | `CONVERT_TZ(dt, from, to)` | -- | -- |
| MariaDB | -- | `CONVERT_TZ` | -- | -- |
| Oracle | 是 | -- | `FROM_TZ(ts, tz)` | `NEW_TIME` (旧) |
| SQL Server | 2016+ | -- | -- | `SWITCHOFFSET`, `TODATETIMEOFFSET` |
| DB2 | -- | -- | -- | -- |
| Snowflake | -- | `CONVERT_TIMEZONE(src, tgt, ts)` | -- | -- |
| BigQuery | -- | -- | -- | `TIMESTAMP(datetime, tz)`、`DATETIME(ts, tz)` |
| Redshift | 是 | `CONVERT_TIMEZONE` | -- | -- |
| DuckDB | 是 | -- | -- | `timezone(tz, ts)` |
| ClickHouse | -- | -- | -- | `toTimeZone(dt, 'tz')` |
| Trino | 是 | -- | -- | `with_timezone` |
| Presto | 是 | -- | -- | `with_timezone` |
| Spark SQL | -- | -- | -- | `from_utc_timestamp` / `to_utc_timestamp` |
| Hive | -- | -- | -- | `from_utc_timestamp` / `to_utc_timestamp` |
| Flink SQL | -- | -- | -- | `CONVERT_TZ(s, from, to)` |
| Databricks | -- | -- | -- | `from_utc_timestamp` / `to_utc_timestamp` |
| Teradata | 是 | -- | -- | -- |
| Greenplum | 是 | -- | -- | -- |
| CockroachDB | 是 | -- | -- | `timezone(tz, ts)` |
| TiDB | -- | `CONVERT_TZ` | -- | -- |
| OceanBase | 是 (Oracle 模式) | `CONVERT_TZ` (MySQL 模式) | `FROM_TZ` (Oracle) | -- |
| YugabyteDB | 是 | -- | -- | -- |
| Vertica | 是 | -- | -- | -- |
| Impala | -- | -- | -- | `from_utc_timestamp` / `to_utc_timestamp` |
| StarRocks | -- | `CONVERT_TZ` | -- | -- |
| Doris | -- | `CONVERT_TZ` | -- | -- |
| SAP HANA | -- | -- | -- | `UTCTOLOCAL`, `LOCALTOUTC` |
| Firebird | 是 (4.0+) | -- | -- | -- |
| H2 | -- | -- | -- | -- |
| HSQLDB | -- | -- | -- | -- |
| Derby | -- | -- | -- | -- |
| Athena | 是 | -- | -- | `with_timezone` |
| Azure Synapse | 2016+ | -- | -- | `SWITCHOFFSET` |
| Spanner | -- | -- | -- | `TIMESTAMP(d, tz)` 等 |
| Materialize | 是 | -- | -- | -- |
| RisingWave | 是 | -- | -- | -- |
| InfluxDB | -- | -- | -- | -- |
| Databend | -- | -- | -- | `to_timezone(ts, tz)` |
| Yellowbrick | 是 | -- | -- | -- |
| Firebolt | 是 | -- | -- | -- |

### 3. 会话/服务器时区设置

| 引擎 | 会话时区设置 | 服务器默认 | tzdata 来源 | 接受命名时区 (IANA) | 接受 ±HH:MM |
|------|-------------|----------|------------|-------------------|------------|
| PostgreSQL | `SET TIME ZONE 'Asia/Shanghai'` | `timezone` (postgresql.conf) | OS tzdata | 是 | 是 |
| MySQL | `SET time_zone = '+08:00'` | `default-time-zone` | OS 或 mysql.time_zone* 表 | 加载后 | 是 |
| MariaDB | `SET time_zone = ...` | 同 MySQL | 同 MySQL | 加载后 | 是 |
| SQLite | -- | -- (无时区) | -- | -- | 仅字符串 |
| Oracle | `ALTER SESSION SET TIME_ZONE` | DBTIMEZONE | 内置 tz 文件 | 是 | 是 |
| SQL Server | -- (无会话时区) | OS 时区 | Windows 注册表 | 仅 Windows 名 | 仅 DATETIMEOFFSET 字面量 |
| DB2 | `CURRENT TIMEZONE` 特殊寄存器 | 实例参数 | OS | 部分 | 是 |
| Snowflake | `ALTER SESSION SET TIMEZONE` | 账号级 `TIMEZONE` 参数 | 内置 | 是 | 是 |
| BigQuery | -- (查询级 `@@time_zone`) | UTC | 内置 | 是 | 是 |
| Redshift | `SET TIMEZONE` | 集群级 | OS | 是 | 是 |
| DuckDB | `SET TimeZone='...'` | 启动时 OS | ICU 扩展 | 是（需 ICU） | 是 |
| ClickHouse | `SET timezone=...` | server config `<timezone>` | 内置 IANA | 是 | -- |
| Trino | `SET TIME ZONE` (会话属性) | JVM | JVM tzdata | 是 | 是 |
| Spark SQL | `spark.sql.session.timeZone` | JVM | JVM tzdata | 是 | 是 |
| Hive | `hive.local.time.zone` | 同 | JVM | 是 | 是 |
| Flink SQL | `SET 'table.local-time-zone'` | UTC | JVM | 是 | 是 |
| Databricks | `spark.sql.session.timeZone` | UTC | JVM | 是 | 是 |
| Teradata | `SET TIME ZONE` | 系统设置 | 内置 | 是 | 是 |
| Greenplum | `SET TIME ZONE` | 集群 | OS | 是 | 是 |
| CockroachDB | `SET TIME ZONE` | UTC | Go zoneinfo | 是 | 是 |
| TiDB | `SET time_zone = ...` | UTC | 兼容 MySQL | 是 | 是 |
| OceanBase | `SET TIME ZONE` / `time_zone` | 集群 | 内置 | 是 | 是 |
| YugabyteDB | `SET TIME ZONE` | 集群 | OS | 是 | 是 |
| Vertica | `SET TIME ZONE` | 集群 | OS | 是 | 是 |
| Impala | `SET TIME_ZONE` | 启动参数 | OS | 是 | 是 |
| StarRocks | `SET time_zone` | FE 参数 | JVM | 是 | 是 |
| Doris | `SET time_zone` | FE 参数 | JVM | 是 | 是 |
| SAP HANA | `SET 'TIMEZONE' ='...'` | 实例配置 | OS | 是 | 是 |
| Firebird | `SET TIME ZONE` (4.0+) | `DefaultTimeZone` | ICU | 是 | 是 |
| H2 | `SET TIME ZONE` | JVM | JVM | 是 | 是 |
| HSQLDB | `SET TIME ZONE` | JVM | JVM | 是 | 是 |
| Athena | -- | UTC | -- | 只在表达式 | 是 |
| Synapse | -- | OS | Windows | 仅 Windows | 是 |
| Spanner | -- | UTC | -- | 函数参数 | 是 |
| Materialize | `SET TIME ZONE` | UTC | -- | 是 | 是 |
| RisingWave | `SET TIME ZONE` | UTC | -- | 是 | 是 |
| Databend | `SET timezone='...'` | UTC | 内置 | 是 | 是 |
| Yellowbrick | `SET TIME ZONE` | OS | OS | 是 | 是 |
| Firebolt | `SET time_zone` | UTC | -- | 是 | 是 |

### 4. tzdata 更新与 DST、命名规范

| 引擎 | DST 自动处理 | tzdata 更新机制 | IANA 时区名 | Windows 时区名 |
|------|------------|---------------|------------|--------------|
| PostgreSQL | 是 | 跟随 OS（或自带 `--with-system-tzdata`） | 是 | -- |
| MySQL | 是（加载 mysql.time_zone* 后） | `mysql_tzinfo_to_sql /usr/share/zoneinfo` | 是 | -- |
| MariaDB | 是 | 同 MySQL | 是 | -- |
| Oracle | 是 | DSTv# 补丁包，内置 `$ORACLE_HOME/oracore/zoneinfo` | 是 | -- |
| SQL Server | 是 | Windows Update 注册表 | -- | 是（如 `China Standard Time`） |
| DB2 | 是 | 操作系统 | 是 | -- |
| Snowflake | 是 | 平台维护 | 是 | -- |
| BigQuery | 是 | 平台维护 | 是 | -- |
| Redshift | 是 | 平台维护 | 是 | -- |
| DuckDB | 是 (ICU) | 内嵌于 ICU 扩展，随版本更新 | 是 | -- |
| ClickHouse | 是 | 内嵌 IANA 数据，跟随版本 | 是 | -- |
| Trino/Presto | 是 | JVM tzdata（或 `tzupdater`） | 是 | -- |
| Spark SQL | 是 | JVM tzdata | 是 | -- |
| Hive | 是 | JVM tzdata | 是 | -- |
| Flink | 是 | JVM tzdata | 是 | -- |
| Databricks | 是 | JVM tzdata | 是 | -- |
| Teradata | 是 | TZ Update 工具 | 是 | -- |
| CockroachDB | 是 | Go embed zoneinfo | 是 | -- |
| TiDB | 是 | 同 MySQL（mysql.tz 表） | 是 | -- |
| OceanBase | 是 | 内置 + 升级补丁 | 是 | -- |
| Impala | 是 | OS | 是 | -- |
| StarRocks/Doris | 是 | JVM | 是 | -- |
| SAP HANA | 是 | OS | 是 | -- |
| Firebird | 是 (4.0+) | ICU | 是 | -- |
| H2/HSQLDB | 是 | JVM | 是 | -- |
| Synapse | 是 | Windows Update | -- | 是 |
| Materialize/RisingWave | 是 | 内置 | 是 | -- |
| Databend/Firebolt | 是 | 平台维护 | 是 | -- |

> 关键差异：**SQL Server 和 Azure Synapse 使用 Windows 时区名称**（如 `China Standard Time`、`Pacific Standard Time`），而其他几乎所有引擎都使用 IANA 时区名（如 `Asia/Shanghai`、`America/Los_Angeles`）。这是跨数据库迁移的最大坑之一。

## 各引擎语法详解

### PostgreSQL — 三类型并存的"教科书实现"

PostgreSQL 同时实现 `TIMESTAMP`（无时区）和 `TIMESTAMPTZ`（带时区），且 `TIMESTAMPTZ` 的存储和显示有"分裂人格"——这是后文要重点剖析的。

```sql
-- 物理类型
CREATE TABLE events (
    id          bigserial PRIMARY KEY,
    occurred_at timestamptz NOT NULL,   -- 推荐：所有事件时间
    wall_clock  timestamp                -- 仅用于"业务挂钟时间"
);

-- 会话时区
SET TIME ZONE 'Asia/Shanghai';
SELECT now();                       -- 显示北京时间
SELECT now() AT TIME ZONE 'UTC';    -- 显示 UTC 墙钟（注意：返回类型是 TIMESTAMP！）
SELECT now() AT TIME ZONE 'America/Los_Angeles';

-- 文本输入：带偏移会被尊重，无偏移按会话时区解析
INSERT INTO events VALUES (1, '2026-04-13 10:00:00+00');
INSERT INTO events VALUES (2, '2026-04-13 10:00:00');  -- 解析为 Asia/Shanghai 10:00
```

**关键点**：

1. `TIMESTAMPTZ` **物理上存储 8 字节 UTC 微秒数**（自 2000-01-01 起），不存原始偏移
2. 显示时再按会话 `TimeZone` 参数转换为本地时间字符串
3. `AT TIME ZONE` 是**双向操作符**：
   - 作用于 `TIMESTAMPTZ`：返回 `TIMESTAMP`（指定时区下的墙钟）
   - 作用于 `TIMESTAMP`：把无时区时间"解释为该时区的本地时间"，返回 `TIMESTAMPTZ`
4. tzdata 默认跟随系统 `/usr/share/zoneinfo`，编译期可选 `--with-system-tzdata=PATH`

### MySQL / MariaDB — DATETIME vs TIMESTAMP 双轨

MySQL 的设计带有强烈的"业务向"色彩：`DATETIME` 是字面量（不含时区，存储输入即输出），`TIMESTAMP` 则在写入时按会话 `time_zone` 转换为 UTC，读取时再转回。

```sql
CREATE TABLE events (
    id          bigint PRIMARY KEY,
    biz_time    DATETIME,    -- 仅存字面值，不做转换
    sys_time    TIMESTAMP    -- 写入转 UTC，读取转回会话 tz
);

SET time_zone = '+08:00';
INSERT INTO events VALUES (1, '2026-04-13 10:00:00', '2026-04-13 10:00:00');

SET time_zone = '+00:00';
SELECT * FROM events;
-- biz_time 仍然是 '2026-04-13 10:00:00'
-- sys_time 变成 '2026-04-13 02:00:00'

-- 显式转换
SELECT CONVERT_TZ('2026-04-13 10:00:00', '+00:00', 'Asia/Shanghai');
```

**关键点**：

1. `time_zone` 接受偏移（`'+08:00'`）或命名（`'Asia/Shanghai'`），但**命名时区必须先加载 mysql.time_zone\* 系统表**：
   ```bash
   mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql -u root mysql
   ```
2. `TIMESTAMP` 范围只到 2038-01-19（32 位 epoch），`DATETIME` 到 9999 年
3. `DATETIME` 列上的 `NOW()` 仍然按当前 `time_zone` 计算，因此**不同会话写入的"挂钟时间"实际不可比**
4. 8.0+ 引入 `TIMESTAMP(6)` 微秒精度

### Oracle — 三类型 + 命名时区原生支持

Oracle 是少数同时实现 SQL:1992 和 SQL:1999 全部三种类型，并且**真正存储时区名称**（不仅是偏移量）的引擎。

```sql
CREATE TABLE events (
    id            NUMBER PRIMARY KEY,
    naive_ts      TIMESTAMP,                      -- 无时区
    abs_ts        TIMESTAMP WITH TIME ZONE,       -- 存 UTC + 偏移/区域名
    local_ts      TIMESTAMP WITH LOCAL TIME ZONE  -- 存 UTC，按 SESSIONTIMEZONE 显示
);

ALTER SESSION SET TIME_ZONE = 'Asia/Shanghai';

INSERT INTO events VALUES (
    1,
    TIMESTAMP '2026-04-13 10:00:00',
    FROM_TZ(TIMESTAMP '2026-04-13 10:00:00', 'Asia/Shanghai'),
    TIMESTAMP '2026-04-13 10:00:00'
);

SELECT abs_ts AT TIME ZONE 'America/New_York' FROM events;
-- 仍然知道原始时区是 Asia/Shanghai

-- 旧的 NEW_TIME（仅支持北美简写如 'PST', 'EST'）
SELECT NEW_TIME(SYSDATE, 'GMT', 'PST') FROM dual;
```

**关键点**：

1. `TIMESTAMP WITH TIME ZONE` 内部 13 字节，包括 7 字节 datetime + 2 字节时区信息（区域 ID 或偏移）
2. 同样的 `2026-03-09 02:30:00 America/New_York` 在 `WITH TIME ZONE` 中**会保留"区域 ID"**，因此夏令时变更后即使偏移变了，业务语义仍正确
3. tzdata 通过 Oracle "DST patches" (DSTv45 等) 升级，与数据库版本解耦
4. `WITH LOCAL TIME ZONE` 内部存 UTC，丢失原始偏移

### SQL Server — DATETIMEOFFSET 偏移量模型

SQL Server 没有"时区名"的概念，只有偏移量。`DATETIMEOFFSET` 存储 datetime + 偏移量 (int16 分钟)。

```sql
CREATE TABLE events (
    id            bigint PRIMARY KEY,
    occurred_at   DATETIMEOFFSET(7) NOT NULL
);

-- 字面量带偏移
INSERT INTO events VALUES (1, '2026-04-13 10:00:00 +08:00');

-- AT TIME ZONE（2016+，使用 Windows 时区名）
SELECT occurred_at AT TIME ZONE 'Pacific Standard Time' FROM events;

-- TODATETIMEOFFSET：把无时区 datetime 标记上偏移
SELECT TODATETIMEOFFSET(GETDATE(), '+08:00');

-- SWITCHOFFSET：保持瞬间不变，只改偏移显示
SELECT SWITCHOFFSET(occurred_at, '+00:00') FROM events;

-- sys.time_zone_info（2016+）：Windows 时区注册表的视图
SELECT * FROM sys.time_zone_info;
```

**关键点**：

1. `DATETIMEOFFSET` 是 **"timestamp with offset"**，**不是 "timestamp with zone name"**——它不知道 `+08:00` 是 Asia/Shanghai 还是 Asia/Singapore
2. `AT TIME ZONE` 在 SQL Server 2016 才加入，且**只接受 Windows 时区名**（`'China Standard Time'`），从 IANA 名称迁移困难
3. 没有"会话时区"概念，所有未带偏移的字面量都按服务器时区或 UTC 解释
4. `GETDATE()` 返回服务器本地时间，`SYSDATETIMEOFFSET()` 才返回带偏移的当前时间

### ClickHouse — 列级时区元数据

ClickHouse 的设计独树一帜：`DateTime` 类型可以**在列定义时绑定一个固定时区**，影响的仅仅是字符串解析与显示，物理存储始终是 32 位（或 `DateTime64` 64 位）UTC epoch。

```sql
CREATE TABLE events (
    id UInt64,
    ts_utc      DateTime('UTC'),
    ts_shanghai DateTime('Asia/Shanghai'),
    ts_default  DateTime               -- 服务器时区
) ENGINE = MergeTree ORDER BY id;

INSERT INTO events VALUES
    (1, '2026-04-13 10:00:00', '2026-04-13 10:00:00', '2026-04-13 10:00:00');

SELECT ts_utc, ts_shanghai, ts_utc = ts_shanghai FROM events;
-- 三个字段物理存储不同的 UTC 秒数（解析时按各自 tz）
-- ts_utc=2026-04-13 10:00:00, ts_shanghai 显示也是该字面量，但底层 UTC = 02:00:00

SELECT toTimeZone(ts_utc, 'America/Los_Angeles') FROM events;
```

**关键点**：

1. 时区是**类型的一部分**（`DateTime('Asia/Shanghai')` 与 `DateTime('UTC')` 不同类型）
2. tzdata 内嵌于二进制，与 ClickHouse 版本同步
3. `toDateTime('2026-04-13 10:00:00', 'Asia/Shanghai')` 显式指定解析时区
4. 没有 `AT TIME ZONE` 操作符，统一用函数 `toTimeZone`

### BigQuery — TIMESTAMP 始终 UTC

BigQuery 的类型设计干净利落：`TIMESTAMP` 永远是 UTC 瞬间，`DATETIME` 是无时区的"墙钟"，`DATE`、`TIME` 各自独立。

```sql
-- TIMESTAMP 字面量必须能确定瞬间
SELECT TIMESTAMP '2026-04-13 10:00:00 Asia/Shanghai';
SELECT TIMESTAMP '2026-04-13 10:00:00+08:00';

-- DATETIME 永远不带 tz
SELECT DATETIME '2026-04-13 10:00:00';

-- 互转
SELECT DATETIME(TIMESTAMP '2026-04-13 10:00:00+00', 'Asia/Shanghai');
SELECT TIMESTAMP(DATETIME '2026-04-13 10:00:00', 'Asia/Shanghai');

-- 格式化
SELECT FORMAT_TIMESTAMP('%F %T %Z', CURRENT_TIMESTAMP(), 'Asia/Shanghai');
```

**关键点**：

1. 没有 `TIMESTAMP_LTZ` 概念——`TIMESTAMP` 就是 UTC 瞬间
2. 几乎所有时间函数都有可选的 `tz` 参数（如 `EXTRACT(HOUR FROM ts AT TIME ZONE 'Asia/Shanghai')`）
3. 不支持会话时区设置，必须在每个表达式中显式指定
4. 这种设计被广泛认为是"最不容易出错"的方案

### Snowflake — 三个独立类型

Snowflake 完整实现了三种 TIMESTAMP 变体，并通过 `TIMESTAMP_TYPE_MAPPING` 参数决定 `TIMESTAMP` 关键字的默认含义。

```sql
ALTER SESSION SET TIMESTAMP_TYPE_MAPPING = TIMESTAMP_NTZ;
ALTER SESSION SET TIMEZONE = 'Asia/Shanghai';

CREATE TABLE events (
    id        NUMBER,
    ts_ntz    TIMESTAMP_NTZ,   -- 墙钟，无 tz
    ts_ltz    TIMESTAMP_LTZ,   -- UTC 存储，按会话 tz 显示
    ts_tz     TIMESTAMP_TZ     -- 存 UTC + 偏移
);

INSERT INTO events VALUES
    (1,
     '2026-04-13 10:00:00',
     '2026-04-13 10:00:00 +08:00',
     '2026-04-13 10:00:00 +08:00');

SELECT CONVERT_TIMEZONE('UTC', 'America/Los_Angeles', ts_ltz) FROM events;
SELECT CONVERT_TIMEZONE('America/Los_Angeles', ts_ntz) FROM events; -- 双参版本
```

详细的三变体对比见后文专章。

## PostgreSQL TIMESTAMPTZ vs TIMESTAMP 深度剖析

PostgreSQL 是初学者最常踩坑的引擎，原因是它的两种类型**名字几乎相同但语义截然不同**，加上 `AT TIME ZONE` 的"双向操作符"行为。

### 误解 1：TIMESTAMPTZ 存的是"时间 + 时区"

**错**。PostgreSQL `TIMESTAMPTZ` 物理上是 8 字节有符号整数（自 2000-01-01 UTC 起的微秒数），**完全不存原始时区**。

```sql
SET TIME ZONE 'UTC';
CREATE TEMP TABLE t (ts timestamptz);
INSERT INTO t VALUES ('2026-04-13 10:00:00+08:00');

SELECT * FROM t;          -- '2026-04-13 02:00:00+00'
SET TIME ZONE 'Asia/Shanghai';
SELECT * FROM t;          -- '2026-04-13 10:00:00+08'  (同一行，不同显示!)
```

也就是说，**插入时的"+08:00"信息在写入瞬间就被丢弃了**，只剩下 UTC 瞬间。换会话时区后看到的就是不同的字符串。

### 误解 2：TIMESTAMP 会按会话时区解析输入

**错**。`TIMESTAMP WITHOUT TIME ZONE` 会**忽略**输入字面量中的偏移信息，直接当作墙钟存。

```sql
SET TIME ZONE 'Asia/Shanghai';
CREATE TEMP TABLE t (ts timestamp);
INSERT INTO t VALUES ('2026-04-13 10:00:00+00:00');
SELECT * FROM t;          -- '2026-04-13 10:00:00'  (而不是 18:00:00!)
```

因此把 `TIMESTAMP` 用作"事件时间"列几乎总是 bug。

### AT TIME ZONE 的双向语义

```sql
-- TIMESTAMPTZ AT TIME ZONE 'tz' → TIMESTAMP（"在 tz 时区看到的墙钟"）
SELECT '2026-04-13 02:00:00+00'::timestamptz AT TIME ZONE 'Asia/Shanghai';
-- 2026-04-13 10:00:00  (timestamp without time zone)

-- TIMESTAMP AT TIME ZONE 'tz' → TIMESTAMPTZ（"把这个墙钟解释为 tz 的本地时间"）
SELECT '2026-04-13 10:00:00'::timestamp AT TIME ZONE 'Asia/Shanghai';
-- 2026-04-13 02:00:00+00  (在 UTC 会话下显示)
```

记忆窍门：**`AT TIME ZONE` 总是切换"含 / 不含" tz 状态**——`TIMESTAMPTZ` 进 → `TIMESTAMP` 出；`TIMESTAMP` 进 → `TIMESTAMPTZ` 出。

### 最佳实践

1. **业务模型层**：所有"事件发生时刻"使用 `TIMESTAMPTZ`
2. **本地业务时间**：如"2026 春节晚会 20:00 开始"使用 `TIMESTAMP` + 单独 `text` 时区列
3. **应用代码**：服务端 `SET TIME ZONE 'UTC'`，转换在显示层做
4. **JDBC/驱动**：注意客户端 JVM 时区与服务端会话时区都会影响 `Timestamp` 与 `TIMESTAMPTZ` 的解析

## Snowflake 三变体（LTZ / NTZ / TZ）深度剖析

Snowflake 是少数提供三种独立类型的引擎，其语义最接近"教科书"。

### TIMESTAMP_NTZ — wall clock，零转换

```sql
INSERT INTO t (ntz) VALUES ('2026-04-13 10:00:00');
-- 无论 TIMEZONE 如何设置，存的就是 2026-04-13 10:00:00
```

适合：业务挂钟时间、调度任务的"每天上午 9 点"、用户输入的本地约会时间。

### TIMESTAMP_LTZ — 存 UTC，按会话显示

```sql
ALTER SESSION SET TIMEZONE = 'Asia/Shanghai';
INSERT INTO t (ltz) VALUES ('2026-04-13 10:00:00');  -- 解释为 Asia/Shanghai
-- 物理存：2026-04-13 02:00:00 UTC
ALTER SESSION SET TIMEZONE = 'America/Los_Angeles';
SELECT ltz FROM t;  -- 显示：2026-04-12 19:00:00 PDT
```

适合：和 PostgreSQL `TIMESTAMPTZ` 等价，"记录全球事件，本地化显示"。

### TIMESTAMP_TZ — 存 UTC + 原始偏移

```sql
INSERT INTO t (tz) VALUES ('2026-04-13 10:00:00 +08:00');
-- 物理存：UTC ts + offset(+08:00)
SELECT tz FROM t;
-- 始终显示 2026-04-13 10:00:00 +08:00 (不受会话 TIMEZONE 影响)
```

适合：审计、订单时区追溯、"用户在哪个时区下下的单"。

### 关键差异表

| 维度 | NTZ | LTZ | TZ |
|------|-----|-----|----|
| 物理存储 | 字面值 | UTC | UTC + offset |
| 输入转换 | 不转 | 按 SESSION TIMEZONE | 必须带 offset 或按 TIMEZONE |
| 显示 | 字面值 | 按 SESSION TIMEZONE | 原始 offset |
| 比较语义 | 字面比 | 瞬间比 | 瞬间比（忽略 offset） |
| 适用场景 | 业务挂钟 | 全局事件 | 多时区审计 |

> 注意：`TIMESTAMP_TZ` 比较时**仅比较 UTC 瞬间**，因此 `'2026-04-13 10:00:00 +08:00' = '2026-04-13 02:00:00 +00:00'` 为真，但显示仍各自带原偏移。

## 夏令时 (DST) 转换的边缘情况

DST 是时区处理中最棘手的部分。每年 3 月和 11 月的两个周日，无数生产系统会因为下面这些场景出问题。

### 1. 不存在的时间（spring forward）

2026-03-08 02:00 PST，纽约时间直接跳到 03:00 EDT，因此 `02:30:00 America/New_York` **根本不存在**。

```sql
-- PostgreSQL：自动调整为 03:30:00 EDT (前移)
SELECT '2026-03-08 02:30:00'::timestamp AT TIME ZONE 'America/New_York';

-- Oracle：抛出 ORA-01878 "specified field not found in datetime or interval"
SELECT FROM_TZ(TIMESTAMP '2026-03-08 02:30:00', 'America/New_York') FROM dual;

-- MySQL CONVERT_TZ：返回 NULL
SELECT CONVERT_TZ('2026-03-08 02:30:00','America/New_York','UTC');

-- SQL Server AT TIME ZONE：抛错或自动调整，行为依版本
```

各引擎对"不存在的时间"的处理策略**完全不一致**，这是跨引擎迁移最大的隐患之一。

### 2. 重复的时间（fall back）

2026-11-01 01:30 在 America/New_York 出现两次（一次 EDT，一次 EST）。

```sql
-- 几乎所有引擎默认选择"较早的那次"（EDT, -04:00）
SELECT '2026-11-01 01:30:00'::timestamp AT TIME ZONE 'America/New_York';

-- 想要明确指定哪次？必须用 +offset 字面量
SELECT '2026-11-01 01:30:00-05:00'::timestamptz;  -- EST (后)
SELECT '2026-11-01 01:30:00-04:00'::timestamptz;  -- EDT (前)
```

### 3. 历史 DST 规则的回溯

许多国家在历史上多次改变 DST 规则。例如俄罗斯 2011 年取消 DST，2014 年又调整时区。**tzdata 更新**会使同一个历史时间戳的本地表示发生变化。

```sql
-- 1990 年 7 月的 Asia/Yekaterinburg
SELECT '1990-07-01 12:00:00 UTC'::timestamptz AT TIME ZONE 'Asia/Yekaterinburg';
-- 结果取决于 tzdata 版本中关于 1990 年的 DST 规则
```

引擎实现者必须确保 tzdata 升级是**透明且向后兼容**的，否则历史数据的展示会"变脸"。

### 4. DATE_TRUNC 的陷阱

```sql
SET TIME ZONE 'America/New_York';
SELECT DATE_TRUNC('day', '2026-03-08 14:00:00-05'::timestamptz);
-- 期望：2026-03-08 00:00:00-05 (EST)
-- 实际：PostgreSQL 返回 2026-03-08 00:00:00-05，但跨过 02→03 后这一"天"实际只有 23 小时
SELECT DATE_TRUNC('day', '2026-03-08 14:00:00-05'::timestamptz)
       + INTERVAL '1 day';
-- 加 1 天究竟是加 86400 秒还是加"日历一天"？INTERVAL 类型不同结果不同
```

PostgreSQL 区分 `INTERVAL '1 day'` 和 `INTERVAL '24 hours'`：前者跨 DST 时**保持墙钟**，后者保持秒数。其他引擎大多没有这个区分，是 bug 的温床。

### 5. CRON 调度的 DST 噩梦

`0 2 * * *`（每天凌晨 2 点）在 spring forward 当天**根本不会触发**（凌晨 2 点不存在），而在 fall back 当天会**触发两次**（如果调度器幼稚地按本地时间）。引擎层面如 Snowflake Tasks、BigQuery Scheduled Queries 默认使用 UTC 调度来规避此问题。

## 关键发现 / Key Findings

1. **三种语义流派**：所有 45+ 引擎本质上都是 SQL 标准三种类型（无 tz / 带 tz / 本地 tz）的不同实现与命名变体。理解这三种语义差异比记忆每个引擎的语法更重要。

2. **PostgreSQL TIMESTAMPTZ 不存原始时区**：物理上只是一个 UTC 瞬间。所谓"带时区"只是**输入时按会话 tz 解释、输出时按会话 tz 显示**——而**输入时的偏移信息在写入瞬间就被丢弃**。这是初学者最大的认知误区。

3. **Oracle 是唯一原生存储"时区名"的主流引擎**：`TIMESTAMP WITH TIME ZONE` 内部保留 IANA 区域 ID，因此即使将来 DST 规则变更，"该时区下的本地时间"语义仍然正确。其他引擎要么只存偏移，要么直接转 UTC。

4. **SQL Server / Azure Synapse 与世界格格不入**：使用 Windows 时区名（`China Standard Time`），不是 IANA 名（`Asia/Shanghai`）。从其他引擎迁移过来必须建立映射表，且 IANA 比 Windows 名更细粒度，存在多对一映射。

5. **MySQL DATETIME vs TIMESTAMP 是"业务向"设计**：DATETIME 永不转换、TIMESTAMP 自动 UTC 化。但 `TIMESTAMP` 受限于 2038 问题，且必须显式 `mysql_tzinfo_to_sql` 才能使用命名时区，是"看起来便利、用起来踩坑"的典型。

6. **BigQuery 的 TIMESTAMP=UTC 设计最不易出错**：没有"本地时区显示"的隐式行为，所有时区转换都必须显式调用函数。代价是开发者必须养成"永远在表达式中写 tz"的习惯。

7. **Snowflake 三类型最完整**：LTZ / NTZ / TZ 三种语义在同一引擎中并存，且通过 `TIMESTAMP_TYPE_MAPPING` 让 `TIMESTAMP` 关键字的默认含义可配置——既兼容性最强，也最容易在 Schema 设计时混乱。建议**显式写出 `TIMESTAMP_NTZ` / `TIMESTAMP_TZ`**，永远不用裸 `TIMESTAMP`。

8. **ClickHouse 列级时区元数据**：时区是**类型的一部分**（`DateTime('Asia/Shanghai')` 与 `DateTime('UTC')` 是不同类型），物理仍然是 UTC epoch，元数据只影响解析与显示。这种设计在 OLAP 场景下有独特优势：列内时区固定，避免逐行存储偏移。

9. **DST 边缘情况处理无标准**：spring forward 的"不存在时间"在 PostgreSQL 自动前移、Oracle 抛错、MySQL 返回 NULL；fall back 的"重复时间"各引擎默认选择不同。涉及夏令时区域的应用必须用 UTC 字面量或带偏移字面量来规避歧义。

10. **tzdata 来源决定升级路径**：
    - 跟随 OS 的（PostgreSQL、MySQL、Greenplum、Vertica）：管理员负责升级 OS 包
    - 跟随 JVM 的（Trino、Spark、Hive、Flink、Databricks）：需要 `tzupdater` 工具
    - 内嵌发行的（ClickHouse、CockroachDB、Oracle DSTv 补丁、DuckDB ICU、Firebird）：跟随引擎升级
    - 平台维护的（BigQuery、Snowflake、Redshift、Athena、Databend）：用户无需关心

11. **AT TIME ZONE 是 SQL 标准但实现差异巨大**：PostgreSQL/Trino/Vertica 实现"双向"（TZ ↔ 无 TZ），SQL Server 仅 2016+ 且只接受 Windows 名，DuckDB/CockroachDB 等价的是 `timezone(tz, ts)` 函数。MySQL/Spark/Hive 干脆没有这个操作符，只有 `from_utc_timestamp`/`to_utc_timestamp`。

12. **会话时区 vs 服务器时区的可移植性陷阱**：MySQL 客户端连接默认继承服务器 `time_zone`，PostgreSQL 客户端默认 `PGTZ` 环境变量，Snowflake 默认账号级 `TIMEZONE` 参数——同一段 SQL 在不同客户端运行时，**`NOW()`、`CURRENT_TIMESTAMP` 的字符串展现可以完全不同**。生产代码应避免依赖会话时区，时区必须显式传入。

13. **最少惊讶原则的工程建议**：
    - 库表设计：选择 `TIMESTAMPTZ` / `TIMESTAMP_LTZ` / `TIMESTAMP WITH TIME ZONE`，永不用 `TIMESTAMP WITHOUT TIME ZONE` 存事件
    - 服务端会话：固定 `SET TIME ZONE 'UTC'`，让转换在显示层完成
    - 字面量：始终带偏移或 IANA 名（`'2026-04-13 10:00:00+08:00'`）
    - 跨引擎迁移：先建立 IANA ↔ Windows 时区映射，准备 DST 边缘单测

## 总结对比矩阵

### 时区能力总览

| 能力 | PostgreSQL | MySQL | Oracle | SQL Server | ClickHouse | BigQuery | Snowflake | Spark | DuckDB |
|------|-----------|-------|--------|-----------|------------|----------|-----------|-------|--------|
| WITH TIME ZONE | TIMESTAMPTZ | TIMESTAMP | 是 | DATETIMEOFFSET | DateTime('tz') | TIMESTAMP=UTC | TIMESTAMP_TZ | LTZ | TIMESTAMPTZ |
| WITH LOCAL TZ | -- | -- | 是 | -- | -- | -- | TIMESTAMP_LTZ | LTZ 默认 | -- |
| WITHOUT TZ | TIMESTAMP | DATETIME | TIMESTAMP | DATETIME2 | -- | DATETIME | TIMESTAMP_NTZ | TIMESTAMP_NTZ | TIMESTAMP |
| 原生时区名存储 | -- | -- | 是 | -- | -- | -- | -- | -- | -- |
| AT TIME ZONE 操作符 | 是 | -- | 是 | 2016+ | -- | -- | -- | -- | 是 |
| 会话时区 | 是 | 是 | 是 | -- | 是 | -- | 是 | 是 | 是 |
| IANA 名支持 | 是 | 加载后 | 是 | -- | 是 | 是 | 是 | 是 | ICU |
| Windows 名 | -- | -- | -- | 是 | -- | -- | -- | -- | -- |
| DST 自动 | 是 | 加载后 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |

### 引擎选型建议

| 场景 | 推荐引擎/类型 | 原因 |
|------|-------------|------|
| 全球事件时间存储 | PG `TIMESTAMPTZ` / Snowflake `TIMESTAMP_LTZ` | UTC 存储 + 本地化显示 |
| 多时区审计追溯 | Oracle `TIMESTAMP WITH TIME ZONE` / Snowflake `TIMESTAMP_TZ` | 保留原始时区/偏移 |
| 业务挂钟（约会、调度） | PG `TIMESTAMP` / Snowflake `TIMESTAMP_NTZ` | 永不转换 |
| 不易出错的极简模型 | BigQuery `TIMESTAMP`/`DATETIME` | 强制显式时区 |
| OLAP 大宽表多时区列 | ClickHouse `DateTime('tz')` | 列级元数据零开销 |
| Windows 生态 BI | SQL Server `DATETIMEOFFSET` | 与 .NET DateTimeOffset 对齐 |
| 跨引擎数据湖 | 始终用 UTC 字面量 + IANA 名 | 最大可移植性 |

## 参考资料

- SQL:1992 标准: ISO/IEC 9075:1992, 6.1 `<data type>` (TIME / TIMESTAMP WITH TIME ZONE)
- SQL:1999 标准: ISO/IEC 9075-2:1999, 6.1 (TIMESTAMP WITH LOCAL TIME ZONE)
- IANA Time Zone Database: [https://www.iana.org/time-zones](https://www.iana.org/time-zones)
- PostgreSQL: [Date/Time Types](https://www.postgresql.org/docs/current/datatype-datetime.html)
- PostgreSQL: [AT TIME ZONE](https://www.postgresql.org/docs/current/functions-datetime.html#FUNCTIONS-DATETIME-ZONECONVERT)
- MySQL: [The DATE, DATETIME, and TIMESTAMP Types](https://dev.mysql.com/doc/refman/8.0/en/datetime.html)
- MySQL: [MySQL Server Time Zone Support](https://dev.mysql.com/doc/refman/8.0/en/time-zone-support.html)
- Oracle: [Datetime and Interval Data Types](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Data-Types.html)
- Oracle: [Choosing a Time Zone File](https://docs.oracle.com/en/database/oracle/oracle-database/19/nlspg/datetime-data-types-and-time-zone-support.html)
- SQL Server: [DATETIMEOFFSET](https://learn.microsoft.com/en-us/sql/t-sql/data-types/datetimeoffset-transact-sql)
- SQL Server: [AT TIME ZONE](https://learn.microsoft.com/en-us/sql/t-sql/queries/at-time-zone-transact-sql)
- Snowflake: [Date & Time Data Types](https://docs.snowflake.com/en/sql-reference/data-types-datetime)
- Snowflake: [TIMESTAMP_TYPE_MAPPING](https://docs.snowflake.com/en/sql-reference/parameters#timestamp-type-mapping)
- BigQuery: [Date and time types](https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types#timestamp_type)
- ClickHouse: [DateTime](https://clickhouse.com/docs/en/sql-reference/data-types/datetime)
- DuckDB: [Timestamp with Time Zone](https://duckdb.org/docs/sql/data_types/timestamp)
- Trino: [Date and time](https://trino.io/docs/current/language/types.html#date-and-time)
- Spark SQL: [SPARK-35573 TIMESTAMP_NTZ type](https://issues.apache.org/jira/browse/SPARK-35573)
- Hive: [Timestamp with local time zone](https://cwiki.apache.org/confluence/display/Hive/Different+TIMESTAMP+types)
- Flink SQL: [Time Attributes & TIMESTAMP_LTZ](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/concepts/time_attributes/)
- CockroachDB: [TIMESTAMP / TIMESTAMPTZ](https://www.cockroachlabs.com/docs/stable/timestamp.html)
- Firebird 4.0: [Time Zone Support](https://firebirdsql.org/file/documentation/release_notes/html/en/4_0/rnfb40-dml-timezone.html)
- Olson, A.D. "Sources for Time Zone and Daylight Saving Time Data" — IANA tz database history
