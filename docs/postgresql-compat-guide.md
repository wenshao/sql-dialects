# PostgreSQL 兼容引擎开发指南

如果你在开发一个 PostgreSQL 兼容引擎（如 CockroachDB、YugabyteDB、Greenplum、Redshift、openGauss、Hologres、TimescaleDB、Materialize、DuckDB、Neon、Supabase），本文档帮助你了解 PostgreSQL 语法中最关键的设计决策和最容易踩的坑。

## 兼容性分级

不是所有 PostgreSQL 特性都值得兼容。按优先级分三级：

### P0: 必须兼容（用户最常用、不兼容会报错）

| 特性 | 关键文件 | 陷阱 |
|------|---------|------|
| CREATE TABLE + 数据类型 | [ddl/create-table/postgres.sql](../ddl/create-table/postgres.sql) | SERIAL 创建隐式 SEQUENCE、IF NOT EXISTS |
| INSERT/UPDATE/DELETE + RETURNING | [dml/insert/postgres.sql](../dml/insert/postgres.sql) | RETURNING 子句是 PG 用户的强依赖 |
| SELECT + JOIN + WHERE | [query/joins/postgres.sql](../query/joins/postgres.sql) | 支持 FULL OUTER JOIN、LATERAL JOIN |
| ON CONFLICT (UPSERT) | [dml/upsert/postgres.sql](../dml/upsert/postgres.sql) | ON CONFLICT DO NOTHING / DO UPDATE、冲突目标 |
| 事务 + 隔离级别 | [advanced/transactions/postgres.sql](../advanced/transactions/postgres.sql) | 默认 RC（不是 RR）、DDL 可回滚、SAVEPOINT |
| :: 类型转换 | [functions/type-conversion/postgres.sql](../functions/type-conversion/postgres.sql) | `value::type` 语法需 parser 特殊处理 |
| SERIAL / IDENTITY | [ddl/sequences/postgres.sql](../ddl/sequences/postgres.sql) | SERIAL 创建隐式 sequence + 默认值，IDENTITY 是 SQL 标准 |
| 索引（B-Tree/GIN/GiST） | [ddl/indexes/postgres.sql](../ddl/indexes/postgres.sql) | 部分索引、表达式索引、INCLUDE 列 |
| 约束 | [ddl/constraints/postgres.sql](../ddl/constraints/postgres.sql) | EXCLUSION 约束是 PG 独有，CHECK 始终执行 |

### P1: 应该兼容（常用但有替代方案）

| 特性 | 关键文件 | 陷阱 |
|------|---------|------|
| 窗口函数 | [query/window-functions/postgres.sql](../query/window-functions/postgres.sql) | FILTER 子句、命名窗口 WINDOW 子句 |
| CTE（含递归） | [query/cte/postgres.sql](../query/cte/postgres.sql) | PG12+ CTE 可内联（MATERIALIZED/NOT MATERIALIZED）|
| JSON/JSONB | [types/json/postgres.sql](../types/json/postgres.sql) | JSONB 运算符（->、->>、@>、?）、jsonb_path_query |
| ARRAY 类型 | [types/array-map-struct/postgres.sql](../types/array-map-struct/postgres.sql) | ANY/ALL 配合数组、数组运算符（&&、@>） |
| 存储过程/函数 | [advanced/stored-procedures/postgres.sql](../advanced/stored-procedures/postgres.sql) | PL/pgSQL、$$ dollar quoting、RETURNS TABLE |
| EXPLAIN ANALYZE | [advanced/explain/postgres.sql](../advanced/explain/postgres.sql) | FORMAT JSON/YAML/XML、BUFFERS、TIMING |
| 分区表 | [advanced/partitioning/postgres.sql](../advanced/partitioning/postgres.sql) | 声明式分区（PG10+）、分区裁剪 |
| 全文搜索 | [query/full-text-search/postgres.sql](../query/full-text-search/postgres.sql) | tsvector/tsquery、GIN 索引、分词配置 |
| 物化视图 | [ddl/views/postgres.sql](../ddl/views/postgres.sql) | REFRESH MATERIALIZED VIEW CONCURRENTLY |

### P2: 可以不兼容（低频或有更好的替代）

| 特性 | 关键文件 | 说明 |
|------|---------|------|
| 触发器 | [advanced/triggers/postgres.sql](../advanced/triggers/postgres.sql) | 事件触发器、INSTEAD OF 触发器 |
| LISTEN/NOTIFY | [advanced/stored-procedures/postgres.sql](../advanced/stored-procedures/postgres.sql) | 实时通知需连接管理，分布式引擎难实现 |
| 外部数据包装器（FDW） | [ddl/create-table/postgres.sql](../ddl/create-table/postgres.sql) | postgres_fdw、file_fdw 等 |
| RULE 系统 | [ddl/views/postgres.sql](../ddl/views/postgres.sql) | 已被触发器替代，不推荐新代码使用 |
| 自定义类型/域 | [types/numeric/postgres.sql](../types/numeric/postgres.sql) | CREATE TYPE / CREATE DOMAIN |
| 继承表 | [ddl/create-table/postgres.sql](../ddl/create-table/postgres.sql) | 已被分区表替代 |
| Advisory Lock | [advanced/locking/postgres.sql](../advanced/locking/postgres.sql) | 应用层分布式锁，用法特殊 |

## PostgreSQL 最大的 10 个坑

按"兼容引擎最容易忽略"排序：

1. :: 类型转换运算符（parser 需要特殊处理）

详见 [functions/type-conversion/postgres.sql](../functions/type-conversion/postgres.sql)

- `value::type` 是 PostgreSQL 最常用的类型转换语法，等价于 `CAST(value AS type)`
- `::` 不是 SQL 标准运算符，parser 需要在词法分析阶段特殊处理
- 可链式调用：`'2024-01-01'::timestamp::date`
- 用户代码中出现频率极高，不支持等于放弃大量存量 SQL
- 部分引擎选择在 parser 层将 `::` 重写为 `CAST()`，实现相对简单
- 还需处理 `::type[]` 数组类型转换（如 `'{1,2,3}'::int[]`）

2. $$ dollar quoting（函数体边界）

详见 [advanced/stored-procedures/postgres.sql](../advanced/stored-procedures/postgres.sql)

- `$$ ... $$` 用于包裹函数体、字符串常量，避免内部引号转义
- 支持带标签的 dollar quoting：`$func$ ... $func$`、`$body$ ... $body$`
- Parser 需要识别 dollar quoting 边界，不对内部内容进行语法解析
- 嵌套 dollar quoting 在动态 SQL 中常见（函数体内生成 SQL 再用不同标签）
- 不支持 dollar quoting 的引擎需要提供替代的函数体定界方案

3. SERIAL vs IDENTITY（SERIAL 创建隐式 SEQUENCE）

详见 [ddl/sequences/postgres.sql](../ddl/sequences/postgres.sql)

- `SERIAL` 不是真正的数据类型，是 `CREATE SEQUENCE` + `DEFAULT nextval()` 的语法糖
- DROP TABLE 不一定自动删除关联的 SEQUENCE（需 CASCADE 或 OWNED BY）
- `GENERATED ALWAYS AS IDENTITY` 是 SQL 标准（PG10+），推荐替代 SERIAL
- SERIAL 的权限管理复杂——表和序列的权限分别管理
- 迁移工具（pg_dump）导出 SERIAL 列时，序列的 owner 和 current value 要正确处理
- **兼容建议**: 优先支持 IDENTITY，SERIAL 作为兼容层，内部转换为 IDENTITY

4. DDL 是事务性的（可回滚 CREATE TABLE — 实现复杂度高）

详见 [advanced/transactions/postgres.sql](../advanced/transactions/postgres.sql)

- PostgreSQL 的所有 DDL 都在事务中执行，失败可回滚
- `BEGIN; CREATE TABLE t1 (...); CREATE TABLE t2 (...); ROLLBACK;` -- 两张表都不会创建
- 这是 PostgreSQL 相对于 MySQL 的重大优势，迁移用户强依赖此行为
- 实现事务性 DDL 需要 catalog 版本化，复杂度极高
- 分布式引擎（CockroachDB、YugabyteDB）通过分布式事务实现，但有限制
- **注意**: 部分 DDL 不能在事务中执行（CREATE DATABASE、CREATE/DROP TABLESPACE）

5. MVCC 元组版本化（vs undo log — VACUUM 需求）

详见 [advanced/transactions/postgres.sql](../advanced/transactions/postgres.sql)、[advanced/locking/postgres.sql](../advanced/locking/postgres.sql)

- PostgreSQL 使用追加式 MVCC：UPDATE 创建新版本，旧版本原地保留
- 需要 VACUUM 回收死元组，否则表膨胀（bloat）
- 与 MySQL/Oracle 的 undo log 方式截然不同
- `autovacuum` 配置直接影响性能——这是 DBA 最常调优的参数
- 兼容引擎不需要复制此架构，但需要理解用户对 VACUUM 相关参数的配置预期
- 相关系统列（ctid、xmin、xmax）与 MVCC 实现紧耦合

6. RETURNING 子句在所有 DML 上（INSERT/UPDATE/DELETE/MERGE）

详见 [dml/insert/postgres.sql](../dml/insert/postgres.sql)、[dml/update/postgres.sql](../dml/update/postgres.sql)、[dml/delete/postgres.sql](../dml/delete/postgres.sql)

- INSERT ... RETURNING *、UPDATE ... RETURNING *、DELETE ... RETURNING *
- PG15+ 的 MERGE 也支持 RETURNING
- 用户习惯用 `INSERT ... RETURNING id` 获取自增 ID，而不是 `lastval()` / `currval()`
- ORM（如 SQLAlchemy、ActiveRecord）默认生成带 RETURNING 的 INSERT
- 不支持 RETURNING 会导致 ORM 退化为两次查询（INSERT + SELECT），性能下降
- **兼容建议**: 至少在 INSERT 上支持 RETURNING，这是最高频的使用场景

7. 类型严格（不允许隐式转换 — 从 MySQL 迁移的用户会不适应）

详见 [types/numeric/postgres.sql](../types/numeric/postgres.sql)、[types/string/postgres.sql](../types/string/postgres.sql)

- `SELECT 1 + '2'` 在 MySQL 返回 3，在 PostgreSQL 报错
- 函数参数类型必须精确匹配，需要显式 `CAST()` 或 `::`
- `WHERE id = '123'` 在 PG 中可以工作（有限的字符串到整数隐式转换），但 `WHERE text_col = 123` 会报错
- 类型严格是 PG 的设计哲学，兼容引擎应保持这一行为
- 从 MySQL 迁移的用户最常遇到的问题，迁移文档中需要重点说明
- **注意**: PG 的运算符重载依赖类型严格性，放松类型检查可能导致歧义

8. OID / system columns（ctid, xmin, xmax — 内部实现暴露）

详见 [ddl/create-table/postgres.sql](../ddl/create-table/postgres.sql)

- 每行有隐藏的系统列：`ctid`（物理位置）、`xmin`（插入事务 ID）、`xmax`（删除事务 ID）
- `ctid` 常被用作"穷人的 ROWID"进行去重：`DELETE FROM t WHERE ctid NOT IN (SELECT MIN(ctid) ...)`
- `xmin`/`xmax` 用于乐观并发控制（应用层检测行是否被修改）
- PG12 起默认表不再有 OID 列，但系统目录表仍然有
- 兼容引擎需要决定是否暴露这些列——不暴露可能破坏部分 SQL 和工具
- **兼容建议**: `ctid` 影响面最大，建议至少提供语义等价物（如内部 rowid）

9. NOTIFY/LISTEN（pub-sub — 需要连接管理）

详见 [advanced/stored-procedures/postgres.sql](../advanced/stored-procedures/postgres.sql)

- `LISTEN channel_name` + `NOTIFY channel_name, 'payload'` 实现进程间通信
- 许多应用框架依赖此特性做缓存失效、实时推送
- 通知绑定在连接上——连接断开则丢失所有 LISTEN 注册
- 连接池（PgBouncer）在 transaction mode 下无法使用 LISTEN/NOTIFY
- 分布式引擎实现跨节点通知复杂度高
- **兼容建议**: 大多数兼容引擎选择不实现，但需要在文档中说明替代方案

10. search_path（schema 解析顺序 — 安全风险 + 功能）

详见 [ddl/users-databases/postgres.sql](../ddl/users-databases/postgres.sql)

- `search_path` 决定未限定表名的 schema 解析顺序，默认 `"$user", public`
- 类似 Unix 的 `$PATH`——错误配置可能导致找到错误的对象
- 安全风险：恶意用户可在 `public` schema 创建同名函数"劫持"调用
- 扩展（extension）通常安装到指定 schema，需要加入 search_path
- `pg_catalog` 始终隐式在 search_path 中（除非显式排除）
- 兼容引擎需要实现完整的 schema 解析逻辑，不能简化为单 schema

## 兼容族引擎对比表

| 维度 | PostgreSQL | CockroachDB | YugabyteDB | Greenplum | Redshift | openGauss | Hologres | TimescaleDB | DuckDB | Materialize |
|------|-----------|-------------|------------|-----------|----------|-----------|----------|-------------|--------|-------------|
| **架构** | 单机 + 流复制 | 分布式 KV | 分布式 DocDB | MPP 分析 | 云数仓 MPP | 单机/分布式 | 实时分析 | PG 扩展 | 嵌入式 OLAP | 流处理 |
| **PG 协议** | 原生 | 兼容 | 兼容 | 兼容 | 部分兼容 | 兼容 | 部分兼容 | 原生 | 兼容 | 兼容 |
| **PG 版本基线** | 最新 | 自研 (PG语法) | PG 11 fork | PG 14 fork | PG 8.x 衍生 | PG 9.2 fork | 自研 | PG 扩展 | 自研 | 自研 |
| **:: 转换** | 原生 | 支持 | 支持 | 支持 | 支持 | 支持 | 部分支持 | 原生 | 支持 | 支持 |
| **RETURNING** | 完整 | 完整 | 完整 | 部分 | 不支持 | 部分 | 不支持 | 原生 | 支持 | 支持 |
| **事务性 DDL** | 完整 | 部分 | 部分 | 完整 | 不支持 | 部分 | 不支持 | 原生 | 支持 | N/A |
| **JSONB** | 完整 | 完整 | 完整 | 部分 | 不支持 | 完整 | 部分 | 原生 | 支持 | 支持 |
| **ARRAY** | 完整 | 完整 | 完整 | 完整 | 部分 | 完整 | 不支持 | 原生 | 支持 | 支持 |
| **PL/pgSQL** | 完整 | 部分 | 完整 | 完整 | 不支持 | 完整 | 不支持 | 原生 | 不支持 | 不支持 |
| **全文搜索** | 完整 | 部分 | 完整 | 完整 | 不支持 | 完整 | 不支持 | 原生 | 不支持 | 不支持 |
| **GIN/GiST 索引** | 完整 | 部分(GIN) | 完整 | 完整 | 不支持 | 完整 | 不支持 | 原生 | N/A | N/A |
| **LISTEN/NOTIFY** | 完整 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 原生 | 不支持 | 不支持 |
| **参考文件** | [postgres.md](../dialects/postgres.md) | [cockroachdb.md](../dialects/cockroachdb.md) | [yugabytedb.md](../dialects/yugabytedb.md) | [greenplum.md](../dialects/greenplum.md) | [redshift.md](../dialects/redshift.md) | [opengauss.md](../dialects/opengauss.md) | [hologres.md](../dialects/hologres.md) | [timescaledb.md](../dialects/timescaledb.md) | [duckdb.md](../dialects/duckdb.md) | [materialize.md](../dialects/materialize.md) |

### 关键对比说明

- **TimescaleDB** 是 PG 扩展而非 fork，天然拥有 PG 的全部能力，但增加了时序特有语法（`CREATE MATERIALIZED VIEW ... WITH (timescaledb.continuous)`）
- **CockroachDB / YugabyteDB** 在分布式场景下对 PG 语法兼容度最高，但部分特性（全文搜索、触发器）有限制
- **Redshift** 虽然历史上基于 PG 8.x，但已大幅偏离，很多 PG 特性不支持
- **DuckDB / Materialize** 是自研引擎选择兼容 PG 协议/语法，兼容度按需实现

## 从 PostgreSQL 迁移到其他引擎的注意事项

### 迁移到 MySQL 族

| PostgreSQL 语法 | MySQL 等价物 | 注意事项 |
|----------------|-------------|---------|
| `value::int` | `CAST(value AS SIGNED)` | MySQL 的 CAST 类型更有限 |
| `INSERT ... RETURNING id` | `INSERT ...; SELECT LAST_INSERT_ID()` | 需要两次交互 |
| `BOOLEAN` 类型 | `TINYINT(1)` | MySQL 无真正布尔类型 |
| `||` 字符串拼接 | `CONCAT()` | MySQL 中 `\|\|` 是 OR |
| `ILIKE` | `LIKE`（默认不区分大小写） | 取决于 collation |
| `generate_series()` | 递归 CTE 或辅助表 | MySQL 8.0+ 可用递归 CTE |
| `EXTRACT(epoch FROM ts)` | `UNIX_TIMESTAMP(ts)` | 函数名不同 |
| `INTERVAL '1 day'` | `INTERVAL 1 DAY` | 语法略有差异 |
| `ARRAY[1,2,3]` | `JSON_ARRAY(1,2,3)` | MySQL 无原生数组类型 |
| `string_agg()` | `GROUP_CONCAT()` | 注意 GROUP_CONCAT 默认截断 |

详见 [docs/mysql-to-postgresql.md](mysql-to-postgresql.md)、[scenarios/migration-cheatsheet/postgres.sql](../scenarios/migration-cheatsheet/postgres.sql)

### 迁移到分析型引擎（BigQuery / Snowflake / ClickHouse）

| 关注点 | 说明 |
|-------|------|
| 事务模型 | 分析型引擎通常不支持完整事务，UPDATE/DELETE 能力有限 |
| 数据类型 | `SERIAL`/`IDENTITY` 无意义（无自增主键概念）、ARRAY 语法差异 |
| 分页 | `LIMIT/OFFSET` 多数引擎支持，但深分页性能差 |
| 存储过程 | BigQuery 用 JavaScript UDF，Snowflake 支持多语言 |
| 索引 | 分析型引擎通常不使用传统索引（排序键、分区替代） |

### 迁移到 Oracle

| PostgreSQL 语法 | Oracle 等价物 | 注意事项 |
|----------------|-------------|---------|
| `''`（空字符串） | `NULL` | Oracle 中空字符串等于 NULL，需检查所有字符串处理逻辑 |
| `LIMIT 10` | `FETCH FIRST 10 ROWS ONLY` (12c+) 或 `ROWNUM` | ROWNUM 在 ORDER BY 前分配 |
| `BOOLEAN` | 无原生布尔（用 NUMBER(1)） | PL/SQL 有 BOOLEAN 但 SQL 层面无 |
| `NOW()` / `CURRENT_TIMESTAMP` | `SYSDATE` / `SYSTIMESTAMP` | Oracle DATE 包含时间 |
| `string_agg()` | `LISTAGG()` | 语法和溢出处理不同 |

## 从其他引擎迁移到 PostgreSQL 的注意事项

### 从 MySQL 迁移到 PostgreSQL

| 关注点 | MySQL 行为 | PostgreSQL 行为 | 迁移建议 |
|-------|-----------|----------------|---------|
| **类型转换** | 隐式宽松转换 | 严格类型检查 | 添加显式 CAST / :: |
| **引号** | 反引号 `` ` `` 包裹标识符 | 双引号 `"` 包裹标识符 | 全局替换，注意大小写 |
| **自增** | `AUTO_INCREMENT` | `SERIAL` 或 `IDENTITY` | 推荐用 IDENTITY |
| **UPSERT** | `ON DUPLICATE KEY UPDATE` | `ON CONFLICT DO UPDATE` | 语法差异大，需重写 |
| **GROUP BY** | 非严格模式允许选择非聚合列 | 严格 GROUP BY | 添加聚合函数或加入 GROUP BY |
| **字符串拼接** | `CONCAT()` | `\|\|` 或 `CONCAT()` | 两种都支持 |
| **DDL** | 隐式提交 | 事务性（可回滚） | 注意事务边界 |
| **零日期** | `'0000-00-00'` 合法 | 不合法 | 转换为 NULL |

详见 [docs/mysql-to-postgresql.md](mysql-to-postgresql.md)

### 从 Oracle 迁移到 PostgreSQL

| 关注点 | Oracle 行为 | PostgreSQL 行为 | 迁移建议 |
|-------|-----------|----------------|---------|
| **空字符串** | `'' = NULL` 为真 | `''` 和 `NULL` 不同 | 检查所有 NVL/COALESCE |
| **DUAL 表** | `SELECT 1 FROM DUAL` 必须 | `SELECT 1` 即可 | 移除 FROM DUAL |
| **CONNECT BY** | 层次查询 | 递归 CTE | 需要重写为 WITH RECURSIVE |
| **DECODE** | NULL 安全比较 | `CASE WHEN`（NULL 不安全） | DECODE(a, NULL, ...) 需特殊处理 |
| **ROWNUM** | 行号伪列 | `ROW_NUMBER()` 或 LIMIT | 语义不同需注意 |
| **包 (Package)** | PL/SQL Package | 无包概念 | 拆分为独立函数/过程 |
| **NUMBER** | 万能数值类型 | INT/BIGINT/NUMERIC 等 | 按精度映射到具体类型 |
| **DATE** | 含时间（秒精度） | 仅日期 | DATE 改为 TIMESTAMP |
| **VARCHAR2** | 默认字节语义 | 字符语义 | 注意多字节字符长度差异 |
| **NVL** | 非 NULL 替换 | `COALESCE` | 直接替换 |
| **SYSDATE** | 当前时间 | `NOW()` 或 `CURRENT_TIMESTAMP` | 注意时区差异 |

详见 [scenarios/migration-cheatsheet/postgres.sql](../scenarios/migration-cheatsheet/postgres.sql)

### 从 SQL Server 迁移到 PostgreSQL

| 关注点 | SQL Server 行为 | PostgreSQL 行为 | 迁移建议 |
|-------|----------------|----------------|---------|
| **TOP N** | `SELECT TOP 10` | `LIMIT 10` | 语法替换 |
| **标识符引号** | `[column_name]` | `"column_name"` | 全局替换 |
| **字符串拼接** | `+` | `\|\|` | 运算符替换 |
| **ISNULL** | `ISNULL(a, b)` | `COALESCE(a, b)` | COALESCE 支持多参数 |
| **GETDATE** | `GETDATE()` | `NOW()` | 函数替换 |
| **存储过程** | T-SQL | PL/pgSQL | 语法差异大，需重写 |
| **临时表** | `#temp` | `CREATE TEMP TABLE` | 不同的生命周期管理 |

## 扩展生态兼容

PostgreSQL 的生态优势在于扩展（Extension）。兼容引擎需要评估是否支持常用扩展的语法：

| 扩展 | 用途 | 兼容建议 |
|------|------|---------|
| `pg_stat_statements` | 慢查询统计 | 建议提供等价的监控接口 |
| `PostGIS` | 地理信息 | 按需支持，实现成本高 |
| `pg_trgm` | 模糊搜索 | GIN 索引加速 LIKE/ILIKE |
| `uuid-ossp` / `pgcrypto` | UUID 生成 | 建议内置 `gen_random_uuid()`（PG13+ 自带） |
| `hstore` | 键值对类型 | 已被 JSONB 替代，低优先级 |
| `citext` | 不区分大小写文本 | 可用 COLLATION 替代 |

## 版本演进关注点

| PG 版本 | 重要变更 | 兼容引擎影响 |
|--------|---------|------------|
| PG 10 | 声明式分区、IDENTITY 列、逻辑复制 | 分区语法需支持 |
| PG 11 | 存储过程（PROCEDURE）、分区索引 | CALL 语句 |
| PG 12 | CTE 内联优化、生成列 | MATERIALIZED 关键字 |
| PG 13 | 增量排序、并行 VACUUM | 性能优化特性 |
| PG 14 | 多范围类型、GROUP BY DISTINCT | 新语法 |
| PG 15 | MERGE 语句、JSON 日志 | SQL 标准 MERGE |
| PG 16 | SQL/PGQ 图查询（预览）、逻辑复制增强 | 未来方向 |
| PG 17 | JSON_TABLE、增量备份 | SQL 标准 JSON 处理 |
