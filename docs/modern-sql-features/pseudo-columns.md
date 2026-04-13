# 伪列 (Pseudo-Columns)

伪列是数据库引擎暴露给 SQL 用户的"虚拟列"——它们不是表定义的一部分，却可以在 SELECT 列表、WHERE 子句中被引用。它们在 SQL 的集合论模型与数据库引擎的物理存储之间架起了一座必要的桥梁：通过 ROWID 暴露页号和槽位，通过 ROWNUM 暴露查询时序号，通过 CURRVAL 暴露序列状态，通过 LEVEL 暴露递归查询的深度。每一个伪列都泄露了一点引擎内部的实现细节，而正是这些细节让 SQL 从纯关系代数演化成可用的工程系统。

伪列的存在本身就是 SQL 标准的失败：标准刻意避免任何与物理存储相关的概念，而每一个真实的数据库都不得不发明自己的伪列来满足开发者的需求。这导致了今天的局面——同一个 `ROWID` 在 Oracle、SQLite、DuckDB、PostgreSQL 中的语义截然不同，而 `ROWNUM` 和 `ROW_NUMBER()` 看似等价却有着致命的执行顺序差异。本文系统梳理 45+ 数据库的伪列支持现状，剖析那些被反复踩中的语义陷阱。

## 没有 SQL 标准

与 `TABLESAMPLE` (SQL:2003)、窗口函数 (SQL:2003)、`MERGE` (SQL:2003) 不同，**伪列没有任何 SQL 标准定义**。ISO/IEC 9075 系列从未提及 ROWID、ROWNUM、CTID 这类概念。原因是显而易见的：

1. **关系模型禁止行的隐式标识**：Codd 的关系代数中，行没有"位置"或"地址"，集合是无序的，重复行需要显式去重。
2. **物理存储抽象**：标准刻意把页、块、文件偏移这些细节留给实现，避免把 SQL 绑定到任何特定存储结构。
3. **可移植性优先**：标准化伪列意味着所有引擎必须实现同一种物理寻址，这与 LSM-Tree、列存、分布式存储等现代架构格格不入。

但实践把伪列推到了几乎所有引擎中。Oracle 在 1980 年代就有了 `ROWID` 和 `ROWNUM`；PostgreSQL 有 `ctid` 和 `oid`；SQLite 把 `rowid` 做成了表的核心；ClickHouse 暴露 `_part`/`_part_index`。SQL 标准委员会唯一的让步是 SQL:2003 的窗口函数 `ROW_NUMBER()`——这是一个明确定义在查询结果集上的"逻辑序号"，与 Oracle 的 `ROWNUM` 在执行顺序上有本质不同。

正因为没有标准，伪列成为 SQL 方言差异最严重的领域之一。下面的支持矩阵覆盖 45+ 引擎，以方便对比迁移。

## 支持矩阵

### ROWID / 物理行标识符

| 引擎 | 关键字 | 类型 | 稳定性 | 备注 |
|------|--------|------|--------|------|
| Oracle | `ROWID` | base64 编码 (file#, block#, row#) | 行不移动则稳定 | 最快的访问路径 |
| PostgreSQL | `ctid` | `(block, offset)` 元组 | UPDATE/VACUUM FULL 后变化 | MVCC 物理位置 |
| MySQL (InnoDB) | -- | 内部 6 字节 row_id | -- | 不暴露给 SQL |
| MariaDB | -- | -- | -- | 同 MySQL |
| SQLite | `rowid` / `ROWID` / `_rowid_` / `oid` | 64 位整数 | 表的实际 b-tree 键 | WITHOUT ROWID 表无此列 |
| SQL Server | `%%physloc%%` (未文档化) / `$ROWGUID` | binary(8) / uniqueidentifier | 移动后变化 | 推荐 ROWVERSION |
| DB2 | `ROWID` (列类型) | VARCHAR(40) FOR BIT DATA | 是 | 必须显式声明 ROWID 列 |
| Snowflake | -- | -- | -- | 微分区架构无此概念 |
| BigQuery | -- | -- | -- | 列存无行标识 |
| Redshift | -- | -- | -- | -- |
| DuckDB | `rowid` | BIGINT | 同一查询内稳定 | 不保证持久 |
| ClickHouse | `_part`, `_part_index`, `_part_offset` | String / UInt64 / UInt64 | part 级稳定 | 暴露 MergeTree 内部 |
| Trino | `$row_id` (部分连接器) | 连接器相关 | 连接器相关 | Iceberg/Delta 用于 MERGE |
| Presto | `$row_id` (部分连接器) | 连接器相关 | -- | 同 Trino |
| Spark SQL | `monotonically_increasing_id()` (函数) | BIGINT | 单 partition 稳定 | 非真正 ROWID |
| Hive | `INPUT__FILE__NAME`, `BLOCK__OFFSET__INSIDE__FILE`, `ROW__OFFSET__INSIDE__BLOCK` | 字符串/BIGINT | 文件不变则稳定 | ACID 表用 ROW__ID |
| Hive (ACID) | `ROW__ID` | struct<originalTransaction, bucket, rowId> | 是 | 用于 UPDATE/DELETE |
| Flink SQL | -- | -- | -- | 流处理无物理行 |
| Databricks | `_metadata.row_index` (Delta) | BIGINT | 文件级 | Delta Lake 2.3+ |
| Teradata | -- | -- | -- | RowID 是行哈希内部概念 |
| Greenplum | `ctid`, `gp_segment_id` | -- | 同 PG | 加分片号 |
| CockroachDB | `rowid` (隐式列) | INT8 | 是 | 无 PK 时自动添加 |
| TiDB | `_tidb_rowid` | BIGINT | 是 | 无 PK 或非聚簇 PK 时可见 |
| OceanBase | `ROWID` | VARCHAR | 是 | Oracle 兼容模式 |
| YugabyteDB | `ctid` | 类 PG | 较弱 | YSQL 模拟 |
| SingleStore | -- | -- | -- | -- |
| Vertica | -- | -- | -- | -- |
| Impala | -- | -- | -- | -- |
| StarRocks | -- | -- | -- | -- |
| Doris | -- | -- | -- | -- |
| MonetDB | -- | -- | -- | -- |
| CrateDB | `_id` | TEXT | 是 | 文档式主键 |
| TimescaleDB | `ctid` | 同 PG | -- | 继承 |
| QuestDB | -- | -- | -- | -- |
| Exasol | `ROWID` | DECIMAL(36) | 是 | 兼容 Oracle |
| SAP HANA | `$rowid$` | BIGINT | 是 | 列存内部行号 |
| Informix | `ROWID` | INTEGER | 是 | 分片表用 `_ROWID` |
| Firebird | `RDB$DB_KEY` / `DB_KEY` | binary(8) | 事务内稳定 | 双下划线前缀 |
| H2 | `_ROWID_` | BIGINT | 是 | 无 PK 时使用 |
| HSQLDB | `ROWNUM()` (函数) | -- | -- | 无真正 ROWID |
| Derby | -- | -- | -- | -- |
| Amazon Athena | `$path`, `$file_modified_time` | -- | 文件级 | 继承 Trino |
| Azure Synapse | -- | -- | -- | -- |
| Google Spanner | -- | -- | -- | -- |
| Materialize | -- | -- | -- | -- |
| RisingWave | -- | -- | -- | -- |
| InfluxDB (SQL) | -- | -- | -- | -- |
| DatabendDB | `_row_id` | UInt64 | 是 | -- |
| Yellowbrick | `rowid` | -- | -- | 继承 PG |
| Firebolt | -- | -- | -- | -- |

### ROWNUM (Oracle 风格的查询时行号)

| 引擎 | 语法 | 时机 | 备注 |
|------|------|------|------|
| Oracle | `ROWNUM` | WHERE 后, ORDER BY 前 | 经典 top-N 陷阱 |
| DB2 | `ROWNUM` | 查询时 | 11.5+ Oracle 兼容 |
| OceanBase | `ROWNUM` | 同 Oracle | Oracle 模式 |
| Exasol | `ROWNUM` | 同 Oracle | -- |
| SAP HANA | `ROWNUM` | 同 Oracle | -- |
| Informix | `ROWNUM` | 同 Oracle | 12.10+ |
| H2 | `ROWNUM()` | 函数形式 | -- |
| HSQLDB | `ROWNUM()` | 函数形式 | -- |
| Firebird | `ROW_NUMBER() OVER ()` | -- | 无 ROWNUM |
| PostgreSQL | -- | -- | 用 `ROW_NUMBER()` 或 `LIMIT` |
| MySQL | -- | -- | 8.0+ 用 `ROW_NUMBER()` |
| SQL Server | -- | -- | 用 `ROW_NUMBER()` 或 `TOP N` |
| SQLite | -- | -- | 用 `ROW_NUMBER()` 3.25+ |
| Snowflake | -- | -- | 用 `ROW_NUMBER()` |
| BigQuery | -- | -- | 用 `ROW_NUMBER()` |
| ClickHouse | -- | -- | `rowNumberInAllBlocks()` |
| DuckDB | -- | -- | 用 `ROW_NUMBER()` |
| Trino/Presto | -- | -- | 用 `ROW_NUMBER()` |
| Spark SQL | -- | -- | 用 `ROW_NUMBER()` |
| Hive | -- | -- | 用 `ROW_NUMBER()` |
| Vertica | -- | -- | 用 `ROW_NUMBER()` |
| Teradata | -- | -- | 用 `ROW_NUMBER()` 或 `QUALIFY` |
| 其余 25+ 引擎 | -- | -- | 使用标准 `ROW_NUMBER()` |

### ROW_NUMBER() 窗口函数（标准等价物）

| 引擎 | 支持 | 版本 | 备注 |
|------|------|------|------|
| PostgreSQL | 是 | 8.4+ | 完整 |
| MySQL | 是 | 8.0+ | 之前需 `@var := @var + 1` |
| MariaDB | 是 | 10.2+ | -- |
| SQLite | 是 | 3.25+ | -- |
| Oracle | 是 | 8i+ | 与 ROWNUM 并存 |
| SQL Server | 是 | 2005+ | -- |
| DB2 | 是 | 9.5+ | -- |
| Snowflake | 是 | GA | -- |
| BigQuery | 是 | GA | -- |
| Redshift | 是 | GA | -- |
| DuckDB | 是 | 早期 | -- |
| ClickHouse | 是 | 21.3+ (实验), 21.10+ GA | 早期需 `arrayJoin` 模拟 |
| Trino/Presto | 是 | GA | 支持 `WINDOW` 子句 |
| Spark SQL | 是 | 1.4+ | -- |
| Hive | 是 | 0.11+ | -- |
| Flink SQL | 是 | 1.13+ | over window |
| Databricks | 是 | GA | -- |
| Teradata | 是 | V2R5+ | 配合 `QUALIFY` 子句 |
| Greenplum | 是 | 4.0+ | -- |
| CockroachDB | 是 | 19.2+ | -- |
| TiDB | 是 | 3.0+ | -- |
| OceanBase | 是 | GA | -- |
| YugabyteDB | 是 | GA | -- |
| SingleStore | 是 | 7.0+ | -- |
| Vertica | 是 | GA | -- |
| Impala | 是 | 2.0+ | -- |
| StarRocks | 是 | GA | -- |
| Doris | 是 | GA | -- |
| MonetDB | 是 | GA | -- |
| CrateDB | 是 | 4.6+ | -- |
| TimescaleDB | 是 | 继承 PG | -- |
| QuestDB | 是 | 7.0+ | 部分窗口 |
| Exasol | 是 | GA | -- |
| SAP HANA | 是 | GA | -- |
| Informix | 是 | 12.10+ | -- |
| Firebird | 是 | 3.0+ | -- |
| H2 | 是 | 1.4.198+ | -- |
| HSQLDB | 是 | 2.5+ | -- |
| Derby | -- | -- | 不支持窗口函数 |
| Athena | 是 | 继承 Trino | -- |
| Synapse | 是 | GA | -- |
| Spanner | 是 | GA | -- |
| Materialize | 是 | GA | -- |
| RisingWave | 是 | GA | -- |
| InfluxDB SQL | -- | -- | 不支持 |
| DatabendDB | 是 | GA | -- |
| Yellowbrick | 是 | GA | -- |
| Firebolt | 是 | GA | -- |

### LEVEL / 层次查询伪列

| 引擎 | LEVEL | CONNECT_BY_ROOT | SYS_CONNECT_BY_PATH | CONNECT_BY_ISLEAF | CONNECT_BY_ISCYCLE |
|------|-------|-----------------|---------------------|-------------------|--------------------|
| Oracle | 是 | 是 | 是 | 是 | 是 |
| DB2 | 是 (LUW 9.7+) | 是 | 是 | 是 | -- |
| OceanBase | 是 | 是 | 是 | 是 | 是 |
| Exasol | -- | -- | -- | -- | -- |
| Informix | -- | -- | -- | -- | -- |
| SAP HANA | -- | -- | -- | -- | -- |
| EnterpriseDB | 是 | 是 | 是 | 是 | 是 |
| 其余 | 用递归 CTE (SQL:1999) | -- | -- | -- | -- |

> 注: 除上述少数 Oracle 兼容引擎，绝大多数现代数据库使用 `WITH RECURSIVE`（SQL:1999）替代 `CONNECT BY`，递归 CTE 中使用计算列 `level + 1` 模拟 LEVEL 伪列。

### 序列伪列 (CURRVAL / NEXTVAL)

| 引擎 | 序列对象 | NEXTVAL | CURRVAL | 语法 |
|------|---------|---------|---------|------|
| Oracle | 是 | `seq.NEXTVAL` | `seq.CURRVAL` | 伪列形式 |
| PostgreSQL | 是 | `nextval('seq')` | `currval('seq')`, `lastval()` | 函数形式 |
| DB2 | 是 | `NEXT VALUE FOR seq` | `PREVIOUS VALUE FOR seq` | SQL 标准 |
| SQL Server | 是 (2012+) | `NEXT VALUE FOR seq` | `current_value` (元数据) | -- |
| MariaDB | 是 (10.3+) | `NEXTVAL(seq)` / `seq.nextval` | `LASTVAL(seq)` | 双语法 |
| MySQL | -- | -- | -- | 仅 AUTO_INCREMENT |
| H2 | 是 | `NEXT VALUE FOR seq` / `seq.nextval` | `CURRENT VALUE FOR seq` | -- |
| HSQLDB | 是 | `NEXT VALUE FOR seq` | `CURRENT VALUE FOR seq` | -- |
| Firebird | 是 | `NEXT VALUE FOR gen` / `GEN_ID(gen, 1)` | -- | "Generator" 历史名 |
| Derby | 是 | `NEXT VALUE FOR seq` | -- | -- |
| SAP HANA | 是 | `seq.NEXTVAL` | `seq.CURRVAL` | -- |
| Informix | 是 | `seq.NEXTVAL` | `seq.CURRVAL` | -- |
| Snowflake | 是 | `seq.NEXTVAL` | -- | 无 CURRVAL |
| BigQuery | -- | -- | -- | 仅 GENERATE_UUID |
| Redshift | -- | -- | -- | 用 IDENTITY |
| DuckDB | 是 (0.6+) | `nextval('seq')` | `currval('seq')` | -- |
| ClickHouse | -- | -- | -- | 无序列概念 |
| CockroachDB | 是 | `nextval('seq')` | `currval('seq')` | PG 兼容 |
| TiDB | 是 (4.0+) | `nextval(seq)` | `lastval(seq)` | -- |
| OceanBase | 是 | `seq.NEXTVAL` | `seq.CURRVAL` | -- |
| YugabyteDB | 是 | 同 PG | 同 PG | -- |
| Vertica | 是 | `seq.NEXTVAL` | `seq.CURRVAL` | -- |
| Greenplum | 是 | 同 PG | 同 PG | -- |
| Exasol | -- | -- | -- | -- |
| Spanner | 是 (2023+) | `GET_NEXT_SEQUENCE_VALUE(seq)` | -- | -- |
| 其余 | -- | -- | -- | -- |

### 系统时间伪列

| 引擎 | SYSDATE | SYSTIMESTAMP | CURRENT_TIMESTAMP | NOW() | LOCALTIMESTAMP |
|------|---------|--------------|-------------------|-------|----------------|
| Oracle | 是 (DATE) | 是 (TIMESTAMP WITH TZ) | 是 | -- | 是 |
| PostgreSQL | -- | -- | 是 | 是 | 是 |
| MySQL | `SYSDATE()` (函数) | -- | 是 | 是 | 是 |
| MariaDB | `SYSDATE()` | -- | 是 | 是 | 是 |
| SQLite | -- | -- | 是 | -- | -- |
| SQL Server | -- | `SYSDATETIME()` / `SYSDATETIMEOFFSET()` | 是 | -- | -- |
| DB2 | -- | -- | 是 | -- | -- |
| Snowflake | `SYSDATE()` | -- | 是 | -- | 是 |
| BigQuery | -- | -- | 是 | -- | -- |
| Redshift | `SYSDATE` (伪列) | `SYSTIMESTAMP` | 是 | 是 | -- |
| DuckDB | -- | -- | 是 | 是 | -- |
| ClickHouse | -- | -- | 是 | 是 | -- |
| Trino | -- | -- | 是 | -- | 是 |
| Presto | -- | -- | 是 | -- | 是 |
| Spark SQL | -- | -- | 是 | -- | -- |
| Hive | -- | -- | 是 | -- | -- |
| Flink SQL | -- | -- | 是 | -- | -- |
| Teradata | -- | -- | 是 | -- | -- |
| OceanBase | 是 | 是 | 是 | -- | -- |
| Exasol | `SYSDATE` | `SYSTIMESTAMP` | 是 | 是 | 是 |
| SAP HANA | -- | -- | 是 | 是 | 是 |
| Informix | -- | -- | 是 | -- | -- |
| Firebird | -- | -- | 是 | -- | 是 |
| H2 | -- | -- | 是 | 是 | 是 |
| HSQLDB | -- | -- | 是 | 是 | 是 |
| 其余引擎 | -- | -- | 是 | 大多数 | 部分 |

### 用户身份伪列

| 引擎 | USER | CURRENT_USER | SESSION_USER | SYSTEM_USER |
|------|------|--------------|--------------|-------------|
| Oracle | 是 | 是 | 是 | -- |
| PostgreSQL | 是 (= CURRENT_USER) | 是 | 是 | 是 |
| MySQL | `USER()` (函数) | `CURRENT_USER()` | -- | `SYSTEM_USER()` |
| MariaDB | `USER()` | `CURRENT_USER()` | `SESSION_USER()` | -- |
| SQLite | -- | -- | -- | -- |
| SQL Server | `USER` / `USER_NAME()` | `CURRENT_USER` | `SESSION_USER` | `SYSTEM_USER` |
| DB2 | `USER` | `CURRENT_USER` / `CURRENT USER` | `SESSION_USER` | `SYSTEM_USER` |
| Snowflake | -- | `CURRENT_USER()` | -- | -- |
| BigQuery | -- | `SESSION_USER()` | -- | -- |
| Redshift | `USER` / `CURRENT_USER` | 是 | `SESSION_USER` | -- |
| DuckDB | -- | `current_user` | -- | -- |
| ClickHouse | -- | `currentUser()` | -- | -- |
| Trino | -- | `CURRENT_USER` | -- | -- |
| Spark SQL | -- | `current_user()` | -- | -- |
| 其余 | 多数支持 `CURRENT_USER` (SQL 标准) | -- | -- | -- |

### IDENTITY / LAST_INSERT_ID 伪列

| 引擎 | 函数/伪列 | 范围 | 备注 |
|------|----------|------|------|
| SQL Server | `@@IDENTITY` | 会话内最后 INSERT (跨触发器) | 不安全 |
| SQL Server | `SCOPE_IDENTITY()` | 当前作用域 | 推荐 |
| SQL Server | `IDENT_CURRENT('table')` | 指定表 | 跨会话 |
| SQL Server | `@@ROWCOUNT` | 上一条语句影响行数 | -- |
| MySQL | `LAST_INSERT_ID()` | 当前连接 | -- |
| MariaDB | `LAST_INSERT_ID()` | 当前连接 | -- |
| PostgreSQL | `RETURNING id` / `lastval()` | 当前会话 | 用 RETURNING 更可靠 |
| Oracle | `RETURNING ... INTO` | 语句级 | 无全局函数 |
| DB2 | `IDENTITY_VAL_LOCAL()` | 当前会话 | -- |
| SQLite | `last_insert_rowid()` | 当前连接 | -- |
| Snowflake | -- | -- | 用 `RESULT_SCAN(LAST_QUERY_ID())` |
| BigQuery | -- | -- | -- |
| H2 | `IDENTITY()` / `SCOPE_IDENTITY()` | -- | 兼容 SQL Server |
| HSQLDB | `IDENTITY()` | 当前会话 | -- |
| Firebird | `RETURNING` | 语句级 | -- |
| Derby | `IDENTITY_VAL_LOCAL()` | 当前会话 | -- |
| TiDB | `LAST_INSERT_ID()` | -- | MySQL 兼容 |
| CockroachDB | `RETURNING` | 语句级 | -- |
| Spanner | `THEN RETURN` | 语句级 | -- |

### 隐藏列：系统时间 / 系统用户 / 行版本

| 引擎 | 系统时间 (SYSTEM_TIME) | 系统版本 (PERIOD) | 行版本号 |
|------|------------------------|------------------|----------|
| SQL Server | `PERIOD FOR SYSTEM_TIME` | 是 (2016+) | `ROWVERSION` / `TIMESTAMP` |
| DB2 | `BUSINESS_TIME` / `SYSTEM_TIME` | 是 (10.1+) | -- |
| Oracle | Flashback | 是 | `ORA_ROWSCN` (伪列) |
| MariaDB | `WITH SYSTEM VERSIONING` | 是 (10.3+) | `ROW_START` / `ROW_END` |
| PostgreSQL | -- | 扩展 | `xmin` / `xmax` (伪列) |
| MySQL | -- | -- | -- |
| SQLite | -- | -- | -- |
| Teradata | `PERIOD` 类型 | 是 | -- |
| Snowflake | Time Travel | 是 (UI 层) | -- |
| BigQuery | Time Travel | 是 (UI 层) | -- |

## 各引擎深入解析

### Oracle: 伪列的发源地

Oracle 是伪列概念的发明者，也是伪列种类最丰富的引擎。

#### ROWID: 物理地址的 base64 编码

```sql
-- ROWID 是 18 字符的字符串，编码 (object#, file#, block#, row#)
SELECT ROWID, employee_id FROM employees WHERE rownum <= 3;
-- AAAR0kAAEAAAAITAAA  100
-- AAAR0kAAEAAAAITAAB  101
-- AAAR0kAAEAAAAITAAC  102

-- 拆解 ROWID
SELECT
    DBMS_ROWID.ROWID_OBJECT(ROWID)         AS object_id,
    DBMS_ROWID.ROWID_RELATIVE_FNO(ROWID)   AS file_num,
    DBMS_ROWID.ROWID_BLOCK_NUMBER(ROWID)   AS block_num,
    DBMS_ROWID.ROWID_ROW_NUMBER(ROWID)     AS row_in_block
FROM employees WHERE employee_id = 100;

-- 用 ROWID 加速 UPDATE: 这是 Oracle 最快的访问路径
UPDATE employees SET salary = salary * 1.1
WHERE ROWID = 'AAAR0kAAEAAAAITAAA';
-- 不需要任何索引查找，直接定位到 (file, block, row)

-- ROWID 何时改变:
-- 1. 表导出导入 (EXP/IMP)
-- 2. ALTER TABLE MOVE
-- 3. SHRINK SPACE
-- 4. 行链接/迁移
-- 5. FLASHBACK TABLE
```

#### ROWNUM: 致命的执行顺序陷阱

```sql
-- ROWNUM 在 ORDER BY 之前赋值！这是 Oracle 最经典的陷阱
-- 错误：试图取薪水最高的 10 人
SELECT * FROM employees WHERE ROWNUM <= 10 ORDER BY salary DESC;
-- 实际：先取任意 10 行，再按薪水排序

-- 正确：必须用子查询
SELECT * FROM (
    SELECT * FROM employees ORDER BY salary DESC
) WHERE ROWNUM <= 10;

-- 12c+ 引入了标准的 FETCH FIRST 子句
SELECT * FROM employees ORDER BY salary DESC FETCH FIRST 10 ROWS ONLY;

-- 另一个陷阱: ROWNUM > N 永远返回空
SELECT * FROM employees WHERE ROWNUM > 5;  -- 返回 0 行
-- 原因: 第 1 行赋值 ROWNUM=1, 不满足 > 5, 被丢弃
--      第 2 行又被赋值 ROWNUM=1 (因为前一行被丢弃), 不满足 > 5
--      ... 永远没有行能让 ROWNUM > 5

-- 分页查询的标准 Oracle 写法 (12c 之前):
SELECT * FROM (
    SELECT a.*, ROWNUM rn FROM (
        SELECT * FROM employees ORDER BY hire_date
    ) a WHERE ROWNUM <= 30
) WHERE rn > 20;
-- 三层嵌套: 内层排序, 中层取前 30, 外层跳过前 20
```

#### LEVEL 和 CONNECT BY 家族

```sql
-- 经典员工层级查询
SELECT
    LEVEL,
    LPAD(' ', 2 * (LEVEL - 1)) || last_name AS hierarchy,
    CONNECT_BY_ROOT last_name              AS top_manager,
    SYS_CONNECT_BY_PATH(last_name, '/')    AS path,
    CONNECT_BY_ISLEAF                      AS is_leaf,
    CONNECT_BY_ISCYCLE                     AS is_cycle
FROM employees
START WITH manager_id IS NULL
CONNECT BY NOCYCLE PRIOR employee_id = manager_id
ORDER SIBLINGS BY last_name;

-- LEVEL 是层次查询专用伪列, 在普通 SELECT 中不可用
-- CONNECT_BY_ROOT 返回子树根节点的指定列值
-- SYS_CONNECT_BY_PATH 拼接从根到当前节点的路径
-- CONNECT_BY_ISLEAF: 当前行是否叶子节点 (1/0)
-- CONNECT_BY_ISCYCLE: 当前行是否触发循环 (NOCYCLE 时有效)

-- 用 LEVEL 生成数列 (Oracle 特有技巧)
SELECT LEVEL FROM DUAL CONNECT BY LEVEL <= 100;
```

#### 其他 Oracle 伪列

```sql
-- ORA_ROWSCN: 行最后修改的 SCN (System Change Number)
SELECT ORA_ROWSCN, SCN_TO_TIMESTAMP(ORA_ROWSCN), employee_id
FROM employees WHERE employee_id = 100;
-- 默认是块级精度, 需 ROWDEPENDENCIES 建表选项才能行级

-- VERSIONS_* 伪列 (Flashback Version Query)
SELECT VERSIONS_STARTSCN, VERSIONS_ENDSCN,
       VERSIONS_OPERATION, salary
FROM employees
VERSIONS BETWEEN SCN MINVALUE AND MAXVALUE
WHERE employee_id = 100;

-- CURRVAL / NEXTVAL on sequences
SELECT my_seq.NEXTVAL FROM DUAL;     -- 取下一个值
SELECT my_seq.CURRVAL FROM DUAL;     -- 取当前会话的最后一个 NEXTVAL
-- CURRVAL 必须先调用过 NEXTVAL 才能使用

-- USER, UID, SYS_CONTEXT
SELECT USER, UID,
       SYS_CONTEXT('USERENV', 'SESSION_USER'),
       SYS_CONTEXT('USERENV', 'IP_ADDRESS')
FROM DUAL;

-- SYSDATE / SYSTIMESTAMP
SELECT SYSDATE,             -- DATE 类型 (秒精度)
       SYSTIMESTAMP,        -- TIMESTAMP WITH TIME ZONE (纳秒)
       CURRENT_DATE,        -- 会话时区
       CURRENT_TIMESTAMP
FROM DUAL;
-- 注意: SYSDATE 是数据库服务器时区, CURRENT_DATE 是会话时区
```

### PostgreSQL: ctid 与 MVCC 痕迹

PostgreSQL 不提供 Oracle 风格的 `ROWID`，但暴露了 MVCC 实现的物理痕迹：

```sql
-- ctid: (block_number, item_pointer)
SELECT ctid, * FROM employees LIMIT 3;
-- (0,1)  | 100 | ...
-- (0,2)  | 101 | ...
-- (0,3)  | 102 | ...

-- ctid 在 UPDATE 后变化 (MVCC: UPDATE = DELETE + INSERT)
UPDATE employees SET salary = salary * 1.1 WHERE id = 100;
SELECT ctid FROM employees WHERE id = 100;
-- 之前: (0,1)
-- 之后: (0,4)  -- 新版本的物理位置
-- 或: (1,1) 如果原页已满

-- ctid 在 VACUUM FULL 后大幅变化 (重写整个表)

-- xmin / xmax: 创建/删除事务的事务 ID
SELECT xmin, xmax, cmin, cmax, ctid, * FROM employees;
-- xmin: 创建此版本的事务 ID
-- xmax: 删除/锁定此版本的事务 ID (0 表示活跃)
-- cmin/cmax: 同事务内的命令序号

-- tableoid: 当前行所属的表的 OID (继承表/分区表中很有用)
SELECT tableoid::regclass, * FROM partitioned_table;

-- oid: 历史伪列, PG 12 已移除 (除非 WITH OIDS 建表)

-- PostgreSQL 的 ROW_NUMBER() 是唯一的"逻辑序号"方式
SELECT ROW_NUMBER() OVER (ORDER BY salary DESC) AS rn, * FROM employees;

-- PG 没有 ROWNUM, 但可以用 ctid 加速 (危险, 不稳定)
-- 这是历史上 PostgreSQL DBA 用来"快速删除大表前 N 行"的技巧:
DELETE FROM big_table
WHERE ctid IN (SELECT ctid FROM big_table LIMIT 10000);
-- 比 DELETE ... WHERE id IN (SELECT id ...) 更快, 因为直接定位物理位置
```

### MySQL: 没有 ROWID, 但有 LAST_INSERT_ID

MySQL InnoDB 内部有一个 6 字节的 `DB_ROW_ID`（当表无显式主键时使用），但**不暴露给 SQL 层**。开发者只能用 `LAST_INSERT_ID()` 间接接触行标识：

```sql
-- LAST_INSERT_ID() 返回当前连接最近一次 AUTO_INCREMENT 插入的值
INSERT INTO orders (customer_id, total) VALUES (42, 99.99);
SELECT LAST_INSERT_ID();   -- 1234

-- 重要: 是当前连接的, 不会被其他连接干扰
-- 注意: 批量插入返回第一个 ID, 不是最后一个
INSERT INTO orders (customer_id, total) VALUES (1, 10), (2, 20), (3, 30);
SELECT LAST_INSERT_ID();   -- 返回第一行的 ID, 不是最后一行!

-- LAST_INSERT_ID(expr): 设置返回值, 用于自定义计数器模式
UPDATE counters SET value = LAST_INSERT_ID(value + 1) WHERE name = 'foo';
SELECT LAST_INSERT_ID();   -- 返回更新后的值

-- ROW_COUNT(): 上一条 DML 影响行数 (类似 SQL Server 的 @@ROWCOUNT)
DELETE FROM logs WHERE created_at < '2020-01-01';
SELECT ROW_COUNT();        -- 删除的行数

-- FOUND_ROWS(): 与 SQL_CALC_FOUND_ROWS 配合 (8.0.17+ 已废弃)

-- MySQL 8.0+ 的 ROW_NUMBER() 是标准方式
SELECT ROW_NUMBER() OVER (ORDER BY id) AS rn, * FROM users;

-- MySQL 没有 ROWID, 但可以伪造一个 (危险, 仅供调试)
SET @row_num = 0;
SELECT (@row_num := @row_num + 1) AS pseudo_rowid, * FROM users;
```

### SQL Server: IDENTITY 三剑客

```sql
-- @@IDENTITY: 当前会话最后一个 IDENTITY 值
-- 危险: 跨触发器, 可能取到触发器内插入的其他表的 ID
INSERT INTO orders (customer_id) VALUES (42);
SELECT @@IDENTITY;

-- SCOPE_IDENTITY(): 当前作用域 (推荐)
INSERT INTO orders (customer_id) VALUES (42);
SELECT SCOPE_IDENTITY();
-- 不会被触发器内的 INSERT 干扰

-- IDENT_CURRENT('table'): 指定表当前 IDENTITY 值 (跨会话)
SELECT IDENT_CURRENT('orders');

-- @@ROWCOUNT: 上一条语句影响行数
UPDATE orders SET status = 'shipped' WHERE created_at < '2024-01-01';
SELECT @@ROWCOUNT;

-- ROWVERSION (旧名 TIMESTAMP): 行版本列, 自动递增
CREATE TABLE products (
    id INT PRIMARY KEY,
    name NVARCHAR(100),
    rv ROWVERSION  -- 每次 UPDATE 自动变化
);
-- 用于乐观并发控制:
UPDATE products SET name = 'new' WHERE id = 1 AND rv = @old_rv;

-- $ROWGUID: 当被声明为 ROWGUIDCOL 的列, 可以用 $ROWGUID 引用
CREATE TABLE assets (
    asset_id UNIQUEIDENTIFIER ROWGUIDCOL DEFAULT NEWID(),
    name NVARCHAR(100)
);
SELECT $ROWGUID, name FROM assets;  -- 等价于 SELECT asset_id, name

-- %%physloc%%: 未文档化的物理位置 (file:page:slot)
SELECT %%physloc%% AS physloc,
       sys.fn_PhysLocFormatter(%%physloc%%) AS pretty,
       * FROM employees;
-- 类似 Oracle ROWID, 但官方不支持依赖
```

### ClickHouse: 暴露 MergeTree 的内部结构

ClickHouse 的伪列直接对应其 MergeTree 物理结构：

```sql
-- _part: 当前行所在的 part 名
-- _part_index: part 内的索引位置
-- _part_offset: part 内的物理偏移
-- _partition_id: 分区 ID
-- _partition_value: 分区表达式的值

SELECT
    _part,
    _part_index,
    _part_offset,
    _partition_id,
    event_id
FROM events
LIMIT 5;
-- 202401_1_10_2  | 0  | 0      | 202401 | 1
-- 202401_1_10_2  | 0  | 1      | 202401 | 2
-- 202401_1_10_2  | 0  | 2      | 202401 | 3

-- 用 _part 加速诊断: 找出某个 part 的所有行
SELECT count() FROM events WHERE _part = '202401_1_10_2';

-- _shard_num (分布式表): 当前行来自哪个分片
SELECT _shard_num, count() FROM distributed_events GROUP BY _shard_num;

-- _sample_factor: 与 SAMPLE 子句配合, 用于推算总数
SELECT count() * any(_sample_factor) AS estimated_total
FROM events SAMPLE 0.1;

-- 行号生成 (无 ROWNUM, 用函数)
SELECT rowNumberInAllBlocks(),         -- 全局行号 (跨 block)
       rowNumberInBlock(),              -- 当前 block 内行号
       blockNumber(),                   -- block 序号
       *
FROM events LIMIT 10;

-- 文件级伪列 (适用于文件引擎)
SELECT _file, _path, * FROM file('data/*.csv', CSV);
```

### DuckDB: 简洁的 rowid

```sql
-- DuckDB 暴露 rowid 作为隐式列
SELECT rowid, * FROM users LIMIT 3;
-- 0 | alice
-- 1 | bob
-- 2 | carol

-- rowid 是 BIGINT, 在同一查询内稳定, 但不保证持久
-- 对于持久化 DuckDB 数据库, 删除/更新会导致 rowid 重新分配
-- 不推荐作为外部引用

-- DuckDB 没有 Oracle 风格的 ROWNUM, 用 ROW_NUMBER():
SELECT ROW_NUMBER() OVER () AS rn, * FROM users;
-- 或更简洁的:
SELECT ROW_NUMBER() OVER () AS rn, * FROM users ORDER BY rn;

-- 序列伪列 (0.6+)
CREATE SEQUENCE my_seq START 100;
SELECT nextval('my_seq');   -- 100
SELECT currval('my_seq');   -- 100
SELECT nextval('my_seq');   -- 101
```

### SQLite: ROWID 即一切

SQLite 是唯一一个把 `rowid` 提升为表的核心标识符的引擎：

```sql
-- 默认所有表都有 rowid (除了 WITHOUT ROWID 表)
-- rowid 是 64 位整数, 是表的实际 b-tree 键
SELECT rowid, * FROM users;

-- 以下三个名字完全等价
SELECT rowid FROM users;
SELECT ROWID FROM users;
SELECT _rowid_ FROM users;
SELECT oid FROM users;        -- 历史兼容

-- INTEGER PRIMARY KEY 列是 rowid 的别名
CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);
INSERT INTO users (name) VALUES ('alice');
SELECT id, rowid FROM users;  -- id 和 rowid 完全相同

-- rowid 的特性:
-- 1. 自动分配 (除非显式指定)
-- 2. 删除行后, rowid 可能被复用
-- 3. AUTOINCREMENT 关键字防止复用 (有性能开销)

CREATE TABLE strict (id INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT);
-- 这种表的 rowid 单调递增, 永不复用 (使用 sqlite_sequence 表)

-- WITHOUT ROWID 表: 没有 rowid 列, 主键即为 b-tree 键
CREATE TABLE kv (
    key TEXT PRIMARY KEY,
    value BLOB
) WITHOUT ROWID;
SELECT rowid FROM kv;  -- 错误: no such column: rowid

-- last_insert_rowid(): 当前连接最后插入的 rowid
INSERT INTO users (name) VALUES ('bob');
SELECT last_insert_rowid();
```

### Hive: 文件系统级伪列

Hive 是少数把伪列直接绑定到底层文件系统的引擎：

```sql
-- 三个核心伪列 (注意: 双下划线分隔)
SELECT
    INPUT__FILE__NAME,                    -- 完整 HDFS 路径
    BLOCK__OFFSET__INSIDE__FILE,          -- 文件内偏移量
    ROW__OFFSET__INSIDE__BLOCK,           -- block 内行号
    *
FROM events
WHERE dt = '2024-01-01'
LIMIT 5;
-- hdfs://nn/warehouse/events/dt=2024-01-01/000000_0  0     0
-- hdfs://nn/warehouse/events/dt=2024-01-01/000000_0  1024  1
-- ...

-- ROW__OFFSET__INSIDE__BLOCK 默认禁用,
-- 需要 SET hive.exec.rowoffset=true;

-- ACID 表 (transactional table) 的 ROW__ID
-- 这是一个 struct, 包含三个字段
SELECT ROW__ID, * FROM transactional_table LIMIT 3;
-- {"originalTransaction":1,"bucket":536936448,"rowId":0}  ...
-- {"originalTransaction":1,"bucket":536936448,"rowId":1}  ...

-- ROW__ID 用于支持 ACID 的 UPDATE/DELETE
-- originalTransaction: 创建此行的事务 ID (write ID)
-- bucket: 桶编号 + 状态位编码
-- rowId: 桶内行号

-- 用 ROW__ID 排查 compaction 问题
SELECT ROW__ID.originalTransaction AS write_id,
       count(*) AS row_count
FROM transactional_table
GROUP BY ROW__ID.originalTransaction
ORDER BY write_id;
```

### Spark SQL: 没有真 ROWID, 但有 monotonically_increasing_id()

```sql
-- Spark 没有 ROWID, 提供两个相关函数:
SELECT
    monotonically_increasing_id() AS mid,
    spark_partition_id() AS pid,
    *
FROM events;

-- monotonically_increasing_id() 的"奇怪"特性:
-- 不连续: 高 31 位是 partition ID, 低 33 位是 partition 内序号
-- 例如: 0, 1, 2, ..., 8589934592, 8589934593, ...
-- 因此不能假设值连续, 只能保证单调递增 (在同一 partition 内)
-- 也不能跨多次查询保证一致

-- 正确的 row_number 应该用窗口函数:
SELECT ROW_NUMBER() OVER (ORDER BY ts) AS rn, * FROM events;
-- 但这会触发全局排序, 对大数据慢

-- Delta Lake 的 _metadata.row_index (Databricks 专有)
SELECT _metadata.row_index, _metadata.file_path, * FROM delta_table;
```

### Snowflake / BigQuery: 没有伪列

Snowflake 和 BigQuery 都是云数仓，刻意不暴露任何物理寻址：

```sql
-- Snowflake: 唯一接近的概念是 METADATA$ACTION, METADATA$ISUPDATE,
-- METADATA$ROW_ID (仅在 STREAM 上使用)
SELECT METADATA$ACTION, METADATA$ISUPDATE, METADATA$ROW_ID, *
FROM stream_on_table;
-- INSERT  | FALSE | abc...  | ...

-- 不是普通表上的 ROWID, 仅在 CDC 流上有效

-- BigQuery: 完全没有 ROWID 概念
-- 唯一相近的是 GENERATE_UUID() 用于在查询时生成唯一值
SELECT GENERATE_UUID(), * FROM dataset.table;

-- 这两个引擎都用 ROW_NUMBER() 作为唯一的"行号"机制
SELECT ROW_NUMBER() OVER (ORDER BY ts) AS rn, * FROM events;
```

### 其他 Oracle 兼容引擎

```sql
-- DB2 (从 9.5 起逐步引入 Oracle 兼容)
SELECT ROWID, ROWNUM, * FROM employees WHERE ROWNUM <= 10;
-- DB2 的 ROWID 是 VARCHAR(40) FOR BIT DATA, 必须显式声明列
-- 11.5+ 支持 LEVEL / CONNECT BY

-- OceanBase (双模式: MySQL 兼容 + Oracle 兼容)
-- Oracle 模式下完全支持 Oracle 伪列:
SELECT ROWID, ROWNUM, LEVEL, CONNECT_BY_ROOT name
FROM employees
START WITH manager_id IS NULL
CONNECT BY PRIOR id = manager_id;

-- Exasol
SELECT ROWID, ROWNUM, * FROM employees WHERE ROWNUM <= 10;

-- TiDB
SELECT _tidb_rowid, * FROM users;
-- 仅当表无聚簇主键时可见
-- 用于内部分布式调度

-- CockroachDB
-- 自动添加隐式 rowid 列 (当表无 PK 时)
CREATE TABLE no_pk (data TEXT);
INSERT INTO no_pk VALUES ('hello');
SELECT rowid, * FROM no_pk;  -- 自动 INT8
```

## ROWID 的语义分裂：物理 vs 逻辑

伪列最让人困惑的地方在于"ROWID"这个词在不同引擎中含义截然不同。可以归纳为四个语义层级：

### 层级 1: 物理地址 (Physical Address)

Oracle ROWID 是典型代表：

```
AAAR0kAAEAAAAITAAA
└─────┘└─┘└─────┘└─┘
 obj#  file# block# row#
```

特点：
- 直接编码物理存储位置
- 访问时不需要任何索引查找，O(1) 定位
- 行物理位置变化 (row migration, 表重组) 时失效
- 跨备份/导入不稳定

类似的还有：PostgreSQL `ctid`、SQL Server `%%physloc%%`、Hive `BLOCK__OFFSET__INSIDE__FILE`、ClickHouse `_part_offset`。

### 层级 2: 逻辑标识 (Logical Identifier)

SQLite rowid 是典型代表：

```
rowid = 表的 b-tree 主键 (64 位整数)
```

特点：
- 是表数据结构的一部分，而非物理地址
- 行物理位置变化（如 VACUUM）时**不**变
- 删除后可能被复用（除非 AUTOINCREMENT）
- 可以作为外部引用（小心复用）

类似的还有：CockroachDB 的隐式 `rowid` 列、TiDB `_tidb_rowid`、CrateDB `_id`。

### 层级 3: 部件级标识 (Part-Level Identifier)

ClickHouse `_part` + `_part_index` 是典型：

```
_part = "202401_1_10_2"  (分区_最小_最大_级别)
_part_index = 0           (在该 part 内的序号)
```

特点：
- 暴露列存的"段"结构
- 跨 part 不全局唯一，但 `(_part, _part_index)` 联合唯一
- merge / mutation 后值变化
- 对查询优化有意义（part pruning）

### 层级 4: 不存在 (No ROWID)

Snowflake、BigQuery、大多数云原生引擎完全不暴露行级标识。它们的设计哲学是：

- 数据是不可变的（micro-partition / immutable file）
- 更新通过文件重写完成
- 行没有"地址"，只有列值
- 唯一性由用户用 PK / UNIQUE 约束保证

这种设计与现代列存 + 对象存储的架构一致。代价是失去了"通过 ROWID 快速定位"的能力，但获得了无限横向扩展性。

### 对照表

| 语义层级 | 代表引擎 | 物理位置变化时 | 是否可作外部引用 |
|---------|---------|---------------|----------------|
| 物理地址 | Oracle ROWID, PG ctid | 失效 | 危险 (短期内可) |
| 逻辑 ID | SQLite rowid, TiDB | 不变 | 较安全 (注意复用) |
| 部件级 | ClickHouse _part | merge 后变 | 不可 |
| 无 ROWID | Snowflake, BigQuery | -- | -- |

## ROWNUM 与 ROW_NUMBER() 的根本差异

这是 Oracle 用户迁移到其他数据库时遇到的最大困惑。

### 执行时机不同

```sql
-- Oracle ROWNUM: 在 WHERE 之后, ORDER BY 之前赋值
SELECT * FROM employees WHERE ROWNUM <= 10 ORDER BY salary DESC;
-- 执行: 扫描 → WHERE → 赋 ROWNUM (1..10) → ORDER BY
-- 结果: 任意 10 行的薪水排序, 不是薪水最高的 10 人

-- 标准 ROW_NUMBER(): 是窗口函数, 在所有 WHERE/JOIN/GROUP BY 之后计算
SELECT * FROM (
    SELECT ROW_NUMBER() OVER (ORDER BY salary DESC) AS rn, * FROM employees
) t WHERE rn <= 10;
-- 执行: 扫描 → 排序 → 赋 row_number → 过滤
-- 结果: 薪水最高的 10 人
```

### 性能差异

```sql
-- ROWNUM 配合 ORDER BY 的 top-N 优化:
SELECT * FROM (
    SELECT * FROM events ORDER BY ts DESC
) WHERE ROWNUM <= 100;
-- Oracle 优化器识别此模式, 用 STOPKEY 提前终止排序
-- 不需要排序全表, 只维护一个 100 元素的堆

-- 标准 FETCH FIRST 子句 (SQL:2008) 是更好的写法:
SELECT * FROM events ORDER BY ts DESC FETCH FIRST 100 ROWS ONLY;
-- 几乎所有现代引擎都对 ORDER BY ... FETCH FIRST N 做 top-N 优化
-- ROW_NUMBER() OVER (ORDER BY ts DESC) 通常不会被优化到 top-N

-- ROW_NUMBER() 的优势: 支持 PARTITION BY (分组 top-N)
SELECT * FROM (
    SELECT ROW_NUMBER() OVER (PARTITION BY dept ORDER BY salary DESC) AS rn, *
    FROM employees
) WHERE rn <= 3;
-- 每个部门取薪水前 3 名 - ROWNUM 无法做到这一点
```

### 迁移建议

| 原 Oracle 写法 | 标准 SQL 等价 | 现代等价 (SQL:2008+) |
|---------------|--------------|---------------------|
| `WHERE ROWNUM = 1` | `WHERE rn = 1` (子查询) | `FETCH FIRST 1 ROW ONLY` |
| `WHERE ROWNUM <= N` | `WHERE rn <= N` (子查询) | `FETCH FIRST N ROWS ONLY` |
| 分页 (12c-) 三层嵌套 | -- | `OFFSET m FETCH NEXT n` |
| `LEVEL` 层次查询 | `WITH RECURSIVE` 中的计算列 | -- |
| `CONNECT_BY_ROOT` | 递归 CTE 中保留根值 | -- |
| `SYS_CONNECT_BY_PATH` | 递归 CTE 中字符串拼接 | -- |

## 序列伪列：CURRVAL / NEXTVAL 的方言地图

序列是 SQL 标准的一部分（SQL:2003 引入 `CREATE SEQUENCE`），但访问语法各家不同。

### 三大流派

```sql
-- Oracle / OceanBase / SAP HANA / Exasol / Vertica / Informix
-- 伪列形式 (附在序列对象后)
SELECT my_seq.NEXTVAL FROM DUAL;
SELECT my_seq.CURRVAL FROM DUAL;

-- DB2 / SQL Server / Derby / H2 / HSQLDB
-- SQL 标准形式
SELECT NEXT VALUE FOR my_seq;
SELECT PREVIOUS VALUE FOR my_seq;  -- DB2
-- SQL Server 没有 PREVIOUS VALUE FOR

-- PostgreSQL / DuckDB / CockroachDB / YugabyteDB / Greenplum
-- 函数形式
SELECT nextval('my_seq');
SELECT currval('my_seq');
SELECT lastval();             -- 任意最近 nextval 调用的结果
SELECT setval('my_seq', 1000); -- 重置

-- MariaDB (10.3+)
-- 双语法支持
SELECT NEXTVAL(my_seq);
SELECT my_seq.nextval;
SELECT NEXT VALUE FOR my_seq;
```

### CURRVAL 的会话语义陷阱

```sql
-- Oracle / PostgreSQL 都规定: CURRVAL 必须先在当前会话调用过 NEXTVAL
SELECT my_seq.CURRVAL FROM DUAL;
-- ORA-08002: sequence MY_SEQ.CURRVAL is not yet defined in this session

SELECT currval('my_seq');
-- ERROR: currval of sequence "my_seq" is not yet defined in this session

-- 这个限制保证了 CURRVAL 总是返回**当前会话**的最后值,
-- 而不是其他会话的值. 这避免了竞态条件.

-- PostgreSQL 的 lastval() 可以避开这个限制 (任意最近 nextval):
SELECT lastval();  -- 不需要指定序列名

-- Snowflake 完全没有 CURRVAL, 必须用 RETURNING 或 sql variable:
INSERT INTO orders (id) VALUES (my_seq.NEXTVAL);
SET last_id = (SELECT id FROM orders ORDER BY id DESC LIMIT 1);
```

## 系统函数与伪列的边界

许多"伪列"实际上是无参函数。两者的边界在不同引擎中划分不一：

```sql
-- Oracle: SYSDATE 是真伪列, 不需要括号
SELECT SYSDATE FROM DUAL;

-- MySQL: SYSDATE() 是函数, 必须带括号 (而且每次调用返回不同值, 与 NOW() 不同)
SELECT SYSDATE();         -- 函数
SELECT SYSDATE;           -- 错误: Unknown column 'SYSDATE'

-- 标准 SQL: CURRENT_TIMESTAMP / CURRENT_DATE / CURRENT_USER 是无参伪列, 不带括号
SELECT CURRENT_TIMESTAMP, CURRENT_USER, CURRENT_DATE;

-- 但 PostgreSQL 也接受函数形式:
SELECT current_timestamp(), current_user();  -- 也可以

-- USER 的方言:
-- Oracle:  USER       (伪列)
-- DB2:     USER       (伪列)
-- MySQL:   USER()     (函数)
-- SQL Server: USER    (= USER_NAME(), 兼容性)
-- 标准 SQL: CURRENT_USER (伪列)
```

### CURRENT_TIMESTAMP 的纳秒陷阱

```sql
-- 一个事务内多次调用 CURRENT_TIMESTAMP 返回相同值 (语句开始时刻)
-- 这是 SQL 标准的强制要求, 几乎所有引擎都遵守

BEGIN;
SELECT CURRENT_TIMESTAMP;  -- 2024-01-01 10:00:00.000
-- ... 等待 5 秒 ...
SELECT CURRENT_TIMESTAMP;  -- 还是 10:00:00.000
COMMIT;

-- 如果需要每次调用都是真实时刻, 用:
-- Oracle: SYSDATE / SYSTIMESTAMP (服务器实时)
-- PostgreSQL: clock_timestamp()
-- MySQL: SYSDATE() (注意: NOW() 等价于 CURRENT_TIMESTAMP, 是事务时刻)
-- SQL Server: SYSDATETIME()
-- DB2: 没有简单方法
```

## 关键发现

### 1. 没有标准化的伪列

ISO SQL 标准从未定义任何"伪列"概念。所有 ROWID / ROWNUM / ctid 都是厂商扩展。这导致迁移成本极高，也是 ORM 框架要做大量方言适配的根本原因。

### 2. ROWID 一词被严重过载

- **Oracle ROWID**: 物理地址，最快访问路径
- **SQLite rowid**: 表 b-tree 主键，逻辑标识
- **PostgreSQL ctid**: MVCC 物理位置，UPDATE 后变化
- **DB2 ROWID**: 必须显式声明的列类型，VARCHAR(40)
- **CockroachDB rowid**: 无 PK 时自动添加的隐式列
- **TiDB _tidb_rowid**: 类似 CockroachDB
- **CrateDB _id**: 文档 ID
- **ClickHouse _part_offset**: part 内偏移，不是表级 ID

迁移代码中遇到 "ROWID" 必须先弄清楚是哪种语义。

### 3. ROWNUM 是 Oracle 用户迁移的最大陷阱

`WHERE ROWNUM <= 10 ORDER BY x` 在 Oracle 中得到的是"任意 10 行的排序"，而不是 "x 最大的 10 行"。这个 bug 在迁移到 PostgreSQL / MySQL 时一定会被发现（因为这些引擎没有 ROWNUM），但迁移到 OceanBase / DB2 Oracle 兼容模式时会被静默继承。**唯一安全的做法**：从一开始就使用 `ROW_NUMBER() OVER (ORDER BY ...)` 或 SQL:2008 `FETCH FIRST N ROWS ONLY`。

### 4. ROW_NUMBER() 是真正的"标准 ROWNUM 替代"

SQL:2003 的窗口函数 `ROW_NUMBER()` 是迁移友好的解决方案。它有清晰的执行语义（在 WHERE/GROUP BY 之后、ORDER BY 也确定后赋值），支持 PARTITION BY 实现分组 top-N，几乎所有现代引擎都支持（Derby 和 InfluxDB SQL 是少数例外）。

### 5. 物理位置伪列正在消亡

云原生引擎（Snowflake / BigQuery / Athena / Spanner / Materialize / RisingWave / Firebolt）几乎全部不暴露任何行级伪列。原因是它们的存储模型是不可变文件（micro-partition / Parquet / Iceberg），更新通过重写完成，根本没有"物理地址"这个概念。这是设计哲学的演化，而不是功能缺失。

### 6. CONNECT BY 家族基本被 WITH RECURSIVE 取代

只有 Oracle、DB2、OceanBase、Exasol、SAP HANA 等少数引擎支持 `CONNECT BY` 系列。其他所有引擎都使用 SQL:1999 的 `WITH RECURSIVE`。LEVEL 在递归 CTE 中通常用 `level + 1` 显式计算，CONNECT_BY_ROOT 通过在递归 CTE 中保留根值实现，SYS_CONNECT_BY_PATH 通过字符串拼接实现。

### 7. 序列访问语法三大流派难以统一

- **Oracle 风格**: `seq.NEXTVAL` (Oracle, OceanBase, SAP HANA, Exasol, Vertica, Informix)
- **SQL 标准**: `NEXT VALUE FOR seq` (DB2, SQL Server, Derby, H2, HSQLDB)
- **函数风格**: `nextval('seq')` (PostgreSQL, DuckDB, CockroachDB, YugabyteDB)

MariaDB 三种语法都支持。MySQL 没有序列对象。

### 8. LAST_INSERT_ID 的批量插入陷阱

MySQL 的 `LAST_INSERT_ID()` 在批量插入时返回**第一行**的 ID，而不是最后一行。这违反直觉，是 ORM 实现的一个常见 bug 来源。SQL Server 的 `SCOPE_IDENTITY()` 返回最后一行（与直觉一致）。Oracle 用 `RETURNING ... INTO` 返回所有行。

### 9. ClickHouse 把 MergeTree 内部完全暴露

`_part`, `_part_index`, `_part_offset`, `_partition_id`, `_shard_num`, `_sample_factor` 这些伪列实际上是 ClickHouse 内部物理结构的"调试接口"，但被提升为公开 API。这在分布式查询调优、part 级数据修复、采样系数推算中非常有用。其他列存引擎都没有暴露到这个程度。

### 10. Hive ROW__ID 是 ACID 的隐式 PK

Hive 事务表的 `ROW__ID struct<originalTransaction, bucket, rowId>` 实质是 ACID 实现的伪 PK：UPDATE/DELETE 语句被翻译成 "找到 ROW__ID 然后写 delta 文件标记删除"。这是少数把事务日志的内部状态暴露为 SQL 可访问伪列的引擎。

### 11. SYSDATE vs CURRENT_TIMESTAMP 不是同义词

Oracle / Redshift 的 `SYSDATE` 和 SQL 标准 `CURRENT_TIMESTAMP` 在事务语义上不同：`CURRENT_TIMESTAMP` 在一个事务/语句内多次调用返回相同值（标准要求），而 `SYSDATE` 每次返回服务器实时时刻。MySQL 的 `SYSDATE()` 同理（与 `NOW()` 不同）。

### 12. 隐藏列是新一代"伪列"

SQL Server `ROWVERSION`、PostgreSQL `xmin`/`xmax`、MariaDB `ROW_START`/`ROW_END` 这些 MVCC / 系统版本控制相关的列正在成为伪列的新形态。它们不需要用户显式定义，但在 SELECT 中可以引用，提供了乐观并发控制和时态查询的基础。SQL:2011 的 `PERIOD FOR SYSTEM_TIME` 是少数被标准化的隐藏列概念。

## 总结对比矩阵

### 伪列能力总览

| 能力 | Oracle | PostgreSQL | MySQL | SQL Server | SQLite | DB2 | Snowflake | BigQuery | ClickHouse | DuckDB |
|------|--------|-----------|-------|-----------|--------|-----|-----------|----------|-----------|--------|
| ROWID (物理) | 是 | ctid | -- | %%physloc%% | -- | 是 | -- | -- | _part_offset | -- |
| ROWID (逻辑) | -- | -- | -- | -- | rowid | -- | -- | -- | -- | rowid |
| ROWNUM | 是 | -- | -- | -- | -- | 是 | -- | -- | -- | -- |
| ROW_NUMBER() | 是 | 是 | 8.0+ | 是 | 3.25+ | 是 | 是 | 是 | 是 | 是 |
| LEVEL / CONNECT BY | 是 | -- | -- | -- | -- | 是 | -- | -- | -- | -- |
| WITH RECURSIVE | 是 | 是 | 8.0+ | 是 | 是 | 是 | 是 | 是 | 实验 | 是 |
| 序列 NEXTVAL | 是 | 是 | -- | 2012+ | -- | 是 | 是 | -- | -- | 是 |
| LAST_INSERT_ID | -- | RETURNING | 是 | SCOPE_IDENTITY | last_insert_rowid | IDENTITY_VAL_LOCAL | -- | -- | -- | -- |
| 系统时间 PERIOD | Flashback | -- | -- | 是 | -- | 是 | Time Travel | Time Travel | -- | -- |
| 行版本 / xmin | ORA_ROWSCN | xmin/xmax | -- | ROWVERSION | -- | -- | -- | -- | -- | -- |
| 用户身份 | USER | CURRENT_USER | USER() | SYSTEM_USER | -- | USER | CURRENT_USER() | SESSION_USER() | currentUser() | current_user |

### 引擎选型建议

| 场景 | 推荐方法 | 原因 |
|------|---------|------|
| 跨引擎可移植代码 | `ROW_NUMBER() OVER (...)` + `FETCH FIRST N` | SQL 标准，几乎全支持 |
| Oracle 极速更新单行 | `WHERE ROWID = ?` | 直接物理寻址 |
| PG 删除大表前 N 行 | `WHERE ctid IN (... LIMIT N)` | 跳过索引查找 |
| SQLite 整数主键 | `INTEGER PRIMARY KEY` 即 rowid | 零开销 |
| 分组 top-N | `ROW_NUMBER() OVER (PARTITION BY ...)` | ROWNUM 无法做到 |
| 层次查询 (跨引擎) | `WITH RECURSIVE` | SQL:1999 标准 |
| 层次查询 (Oracle) | `CONNECT BY` + `LEVEL` | 语法更简洁 |
| ClickHouse 调优 | 查询 `_part` 分布 | 暴露物理结构 |
| ACID Hive UPDATE 排查 | `ROW__ID` 内省 | 唯一手段 |
| 乐观并发控制 | SQL Server `ROWVERSION` / MariaDB 系统版本 | 自动维护 |

## 参考资料

- Oracle: [Pseudocolumns](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Pseudocolumns.html)
- Oracle: [ROWID Datatype](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/ROWID-Pseudocolumn.html)
- Oracle: [Hierarchical Queries](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Hierarchical-Queries.html)
- PostgreSQL: [System Columns](https://www.postgresql.org/docs/current/ddl-system-columns.html)
- PostgreSQL: [Sequence Manipulation Functions](https://www.postgresql.org/docs/current/functions-sequence.html)
- MySQL: [Information Functions](https://dev.mysql.com/doc/refman/8.0/en/information-functions.html)
- SQL Server: [@@IDENTITY vs SCOPE_IDENTITY](https://learn.microsoft.com/en-us/sql/t-sql/functions/scope-identity-transact-sql)
- SQL Server: [ROWVERSION](https://learn.microsoft.com/en-us/sql/t-sql/data-types/rowversion-transact-sql)
- SQLite: [ROWIDs and the INTEGER PRIMARY KEY](https://www.sqlite.org/lang_createtable.html#rowid)
- DB2: [Pseudo-columns](https://www.ibm.com/docs/en/db2/11.5?topic=elements-pseudo-columns)
- Hive: [LanguageManual VirtualColumns](https://cwiki.apache.org/confluence/display/Hive/LanguageManual+VirtualColumns)
- Hive: [ACID and Transactions](https://cwiki.apache.org/confluence/display/Hive/Hive+Transactions)
- ClickHouse: [Virtual Columns](https://clickhouse.com/docs/en/engines/table-engines#table_engines-virtual-columns)
- ClickHouse: [MergeTree](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree)
- DuckDB: [rowid](https://duckdb.org/docs/sql/pragmas#rowid)
- Spark SQL: [Built-in Functions: monotonically_increasing_id](https://spark.apache.org/docs/latest/api/sql/index.html#monotonically_increasing_id)
- Snowflake: [Streams Metadata Columns](https://docs.snowflake.com/en/user-guide/streams-intro)
- SQL:2008 Standard: ISO/IEC 9075-2 Section 7.16 (FETCH FIRST clause)
- SQL:2011 Standard: ISO/IEC 9075-2 Section 4.15 (Tables with system-versioning)
- E. F. Codd, "A Relational Model of Data for Large Shared Data Banks", CACM 13(6), 1970
