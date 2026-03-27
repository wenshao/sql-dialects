# Oracle 兼容引擎开发指南

如果你在开发一个 Oracle 兼容引擎（如达梦 DamengDB、人大金仓 KingbaseES、OceanBase Oracle 模式、GaussDB Oracle 模式），本文档帮助你了解 Oracle 语法中最关键的设计决策和最容易踩的坑。

## 兼容性分级

不是所有 Oracle 特性都值得兼容。按优先级分三级：

### P0: 必须兼容（用户最常用、不兼容会报错）

| 特性 | 关键文件 | 陷阱 |
|------|---------|------|
| CREATE TABLE + 数据类型 | [ddl/create-table/oracle.sql](../ddl/create-table/oracle.sql) | NUMBER/VARCHAR2/DATE 语义必须完全一致 |
| INSERT/UPDATE/DELETE | [dml/insert/oracle.sql](../dml/insert/oracle.sql) | INSERT ALL、多表 INSERT |
| SELECT + JOIN + WHERE | [query/joins/oracle.sql](../query/joins/oracle.sql) | (+) 旧式外连接语法需支持 |
| '' = NULL | [types/string/oracle.sql](../types/string/oracle.sql) | 空字符串等于 NULL，影响所有字符串操作 |
| DUAL 表 | [ddl/create-table/oracle.sql](../ddl/create-table/oracle.sql) | SELECT 常量必须 FROM DUAL |
| 序列 SEQUENCE | [ddl/sequences/oracle.sql](../ddl/sequences/oracle.sql) | seq.NEXTVAL / seq.CURRVAL 语法 |
| 事务模型 | [advanced/transactions/oracle.sql](../advanced/transactions/oracle.sql) | 默认不自动提交，读一致性快照 |
| PL/SQL 基础 | [advanced/stored-procedures/oracle.sql](../advanced/stored-procedures/oracle.sql) | BEGIN...END 块、游标、异常处理 |
| 约束 | [ddl/constraints/oracle.sql](../ddl/constraints/oracle.sql) | ENABLE/DISABLE/VALIDATE/NOVALIDATE 状态 |

### P1: 应该兼容（常用但有替代方案）

| 特性 | 关键文件 | 陷阱 |
|------|---------|------|
| 窗口函数 | [query/window-functions/oracle.sql](../query/window-functions/oracle.sql) | Oracle 是窗口函数的先驱，语法最完整 |
| CONNECT BY 层次查询 | [scenarios/hierarchical-query/oracle.sql](../scenarios/hierarchical-query/oracle.sql) | PRIOR、LEVEL、SYS_CONNECT_BY_PATH |
| MERGE 语句 | [dml/upsert/oracle.sql](../dml/upsert/oracle.sql) | MATCHED / NOT MATCHED / 条件操作 |
| 分区表 | [advanced/partitioning/oracle.sql](../advanced/partitioning/oracle.sql) | RANGE/LIST/HASH/COMPOSITE 分区 |
| 物化视图 | [ddl/views/oracle.sql](../ddl/views/oracle.sql) | REFRESH FAST/COMPLETE、查询重写 |
| DECODE 函数 | [functions/conditional/oracle.sql](../functions/conditional/oracle.sql) | NULL 安全比较语义 |
| NVL/NVL2 | [functions/conditional/oracle.sql](../functions/conditional/oracle.sql) | NVL2 是三值函数 |
| 日期函数 | [functions/date-functions/oracle.sql](../functions/date-functions/oracle.sql) | ADD_MONTHS、MONTHS_BETWEEN、TRUNC |
| PIVOT/UNPIVOT | [query/pivot-unpivot/oracle.sql](../query/pivot-unpivot/oracle.sql) | Oracle 11g+ 原生支持 |
| DBMS_* 包 | [advanced/stored-procedures/oracle.sql](../advanced/stored-procedures/oracle.sql) | DBMS_OUTPUT、DBMS_LOB 等内置包 |

### P2: 可以不兼容（低频或有更好的替代）

| 特性 | 关键文件 | 说明 |
|------|---------|------|
| Oracle Forms/Reports | N/A | 前端工具，不涉及 SQL 引擎 |
| Database Link | [ddl/create-table/oracle.sql](../ddl/create-table/oracle.sql) | 跨库查询，可用其他方案替代 |
| Oracle Scheduler (DBMS_SCHEDULER) | [advanced/stored-procedures/oracle.sql](../advanced/stored-procedures/oracle.sql) | 可用外部调度系统替代 |
| Flashback 查询 | [advanced/transactions/oracle.sql](../advanced/transactions/oracle.sql) | AS OF TIMESTAMP，实现复杂 |
| Oracle Text | [query/full-text-search/oracle.sql](../query/full-text-search/oracle.sql) | CONTAINS 语法，可用 ES 替代 |
| XMLType | [types/json/oracle.sql](../types/json/oracle.sql) | XML 处理已逐步被 JSON 替代 |
| Autonomous Transaction | [advanced/transactions/oracle.sql](../advanced/transactions/oracle.sql) | PRAGMA AUTONOMOUS_TRANSACTION，实现极复杂 |

## Oracle 最大的 10 个坑

按"兼容引擎最容易忽略"排序：

### 1. '' = NULL（最大最著名的坑，影响所有字符串操作）

详见 [types/string/oracle.sql](../types/string/oracle.sql)、[functions/conditional/oracle.sql](../functions/conditional/oracle.sql)

- Oracle 中空字符串 `''` 等同于 `NULL`，这违反了 SQL 标准
- `SELECT LENGTH('')` 返回 `NULL`（不是 0）
- `SELECT '' || 'abc'` 返回 `'abc'`（不是 `'abc'`，因为 `NULL || 'abc' = 'abc'` 在 Oracle 中）
- `WHERE name = ''` 永远没有匹配（等价于 `WHERE name = NULL`）
- `WHERE name IS NULL` 会匹配空字符串插入的行
- **所有字符串比较、拼接、长度计算逻辑都受影响**
- 这是 Oracle 最根本的特异行为，兼容引擎必须在存储层和计算层同时处理
- **兼容建议**: 在字符串类型内部将空字符串映射为 NULL，但需考虑 `INSERT INTO t(c) VALUES ('')` 后 `SELECT c IS NULL FROM t` 应返回 true

### 2. DUAL 表要求（SELECT 常量必须 FROM DUAL）

详见 [ddl/create-table/oracle.sql](../ddl/create-table/oracle.sql)

- `SELECT 1` 在 Oracle 中语法错误，必须写 `SELECT 1 FROM DUAL`
- DUAL 是一个只有一行一列的虚拟表
- 所有不涉及用户表的 SELECT 都需要 FROM DUAL
- 常见用法：`SELECT SYSDATE FROM DUAL`、`SELECT seq.NEXTVAL FROM DUAL`
- PL/SQL 中的 `SELECT INTO` 也需要 FROM DUAL
- **兼容建议**: 在系统初始化时自动创建 DUAL 表，或在 parser 中将 `FROM DUAL` 视为无表查询

### 3. PL/SQL Package（过程语言的模块化单元 — 实现极复杂）

详见 [advanced/stored-procedures/oracle.sql](../advanced/stored-procedures/oracle.sql)

- Package = 包规范（Specification）+ 包体（Body）
- 包规范定义公共接口，包体定义实现——类似 C 的 .h + .c
- Package 变量在会话内有状态（session-level state），会话结束才释放
- Package 初始化块在首次调用时执行
- 重载：同一 Package 内可有同名但参数不同的过程/函数
- DBMS_OUTPUT、DBMS_LOB、UTL_FILE 等系统包是用户代码的强依赖
- **实现复杂度极高**: 需要 session 级变量管理、编译单元依赖跟踪、规范与体分离
- **兼容建议**: 优先实现最常用的 DBMS_OUTPUT，Package 可以简化为命名空间 + 过程集合

### 4. CONNECT BY（非标准层次查询 — 实现比递归 CTE 复杂）

详见 [scenarios/hierarchical-query/oracle.sql](../scenarios/hierarchical-query/oracle.sql)

- `SELECT ... START WITH ... CONNECT BY PRIOR parent_id = id`
- 特有伪列：`LEVEL`（层级深度）、`CONNECT_BY_ISLEAF`（是否叶节点）
- 特有函数：`SYS_CONNECT_BY_PATH(col, '/')`（路径拼接）
- `CONNECT_BY_ROOT col`（根节点值）
- `NOCYCLE` 处理循环引用
- `ORDER SIBLINGS BY` 保持同级排序
- Oracle 用户大量使用 CONNECT BY，存量 SQL 中占比高
- SQL 标准替代方案是递归 CTE（`WITH RECURSIVE`），但语义不完全等价
- **兼容建议**: 可以在 parser 层将 CONNECT BY 重写为递归 CTE，但 LEVEL/SYS_CONNECT_BY_PATH 需要特殊处理

### 5. NUMBER 万能类型（无 INT/BIGINT — 性能代价）

详见 [types/numeric/oracle.sql](../types/numeric/oracle.sql)

- Oracle 只有 `NUMBER(p, s)` 一种数值类型
- `INTEGER` / `INT` / `SMALLINT` 都是 NUMBER 的别名
- `NUMBER` 无参数等于 NUMBER(38)，精度高但性能差
- `NUMBER(10)` = `NUMBER(10, 0)` 表示整数
- 存储是变长的（1-22 字节），不像固定长度的 INT(4字节)/BIGINT(8字节)
- 算术运算在 NUMBER 上比原生整数类型慢
- **兼容建议**: 接受 NUMBER 语法，内部映射到合适的原生类型（NUMBER(10,0) -> INT、NUMBER(19,0) -> BIGINT、NUMBER(p,s) -> DECIMAL）

### 6. VARCHAR2 默认字节语义（不是字符语义 — 截断陷阱）

详见 [types/string/oracle.sql](../types/string/oracle.sql)

- `VARCHAR2(100)` 默认表示 100 字节，不是 100 个字符
- 中文字符在 UTF-8 下占 3 字节，`VARCHAR2(100)` 只能存约 33 个中文字符
- 可以显式指定：`VARCHAR2(100 CHAR)` 表示 100 个字符
- `NLS_LENGTH_SEMANTICS` 参数控制默认行为（BYTE/CHAR）
- VARCHAR2 最大长度：SQL 层 4000 字节（12c 扩展到 32767）、PL/SQL 层 32767 字节
- **兼容建议**: 需要同时支持 BYTE 和 CHAR 语义，建议默认 CHAR 语义（更符合直觉），但提供参数控制

### 7. DATE 包含时间（Oracle DATE 不等于 SQL 标准 DATE）

详见 [types/datetime/oracle.sql](../types/datetime/oracle.sql)

- Oracle 的 `DATE` 包含日期和时间（精确到秒）
- SQL 标准和其他数据库的 `DATE` 只包含日期
- `SYSDATE` 返回 DATE 类型（含时间），`SYSTIMESTAMP` 返回 TIMESTAMP（含微秒+时区）
- `TRUNC(SYSDATE)` 截断时间部分——Oracle 独有用法
- `SELECT * FROM t WHERE create_date = DATE '2024-01-01'` 只匹配零点整
- 实际应该用 `WHERE create_date >= DATE '2024-01-01' AND create_date < DATE '2024-01-02'`
- **兼容建议**: 将 Oracle 的 DATE 映射为 TIMESTAMP(0)（秒精度），但需要确保所有日期函数的行为一致

### 8. DECODE 函数（NULL 比较语义与 CASE WHEN 不同）

详见 [functions/conditional/oracle.sql](../functions/conditional/oracle.sql)

- `DECODE(expr, search1, result1, search2, result2, ..., default)`
- DECODE 的核心特异性：**把 NULL 视为可比较的值**
- `DECODE(NULL, NULL, 'match', 'no match')` 返回 `'match'`
- 等价的 `CASE WHEN NULL = NULL THEN 'match' ELSE 'no match' END` 返回 `'no match'`
- DECODE 可嵌套：`DECODE(a, 1, DECODE(b, 2, 'x', 'y'), 'z')`
- 返回类型由第一个 result 参数决定
- SQL 标准替代方案：CASE WHEN（但需对 NULL 比较特殊处理）
- **兼容建议**: 实现 DECODE 函数，内部展开为带 NULL 安全比较的 CASE WHEN

### 9. ROWNUM 在 ORDER BY 之前分配（分页陷阱）

详见 [query/pagination/oracle.sql](../query/pagination/oracle.sql)

- `ROWNUM` 是在结果集返回时分配的伪列，**在 ORDER BY 之前**
- `SELECT * FROM t WHERE ROWNUM <= 10 ORDER BY name` 先取 10 行再排序——不是 Top 10！
- 正确写法：`SELECT * FROM (SELECT * FROM t ORDER BY name) WHERE ROWNUM <= 10`
- 12c+ 支持 SQL 标准的 `FETCH FIRST 10 ROWS ONLY`
- `ROWNUM` 不能用 `>`（`WHERE ROWNUM > 5` 永远为空——因为第一行的 ROWNUM 是 1，不满足 >5，被排除后下一行的 ROWNUM 又是 1）
- 分页需要嵌套子查询：`SELECT * FROM (SELECT t.*, ROWNUM rn FROM (SELECT * FROM t ORDER BY id) t WHERE ROWNUM <= 20) WHERE rn > 10`
- **兼容建议**: 支持 ROWNUM 伪列，但强烈推荐用户使用 `FETCH FIRST ... ROWS ONLY` 或 `ROW_NUMBER()`

### 10. NLS 参数影响隐式转换（NLS_DATE_FORMAT 等 — 非确定性行为）

详见 [types/datetime/oracle.sql](../types/datetime/oracle.sql)、[functions/type-conversion/oracle.sql](../functions/type-conversion/oracle.sql)

- `NLS_DATE_FORMAT` 控制 DATE 的默认显示和隐式转换格式
- 默认 `'DD-MON-RR'`，但经常被修改为 `'YYYY-MM-DD HH24:MI:SS'`
- `SELECT TO_DATE('2024-01-01')` 的结果取决于 NLS_DATE_FORMAT——**同一 SQL 在不同 session 可能失败**
- `NLS_NUMERIC_CHARACTERS` 影响小数点和千位分隔符
- `NLS_SORT` / `NLS_COMP` 影响字符串排序和比较
- `ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD'` 只影响当前会话
- **这是 Oracle 应用最常见的"环境相关 bug"来源**
- **兼容建议**: 实现 session 级 NLS 参数，但建议设定合理的默认值（如 `'YYYY-MM-DD HH24:MI:SS'`）

## 兼容族引擎对比表

| 维度 | Oracle | 达梦 DamengDB | 人大金仓 KingbaseES | OceanBase (Oracle) | GaussDB (Oracle) |
|------|--------|--------------|--------------------|--------------------|------------------|
| **架构** | 单机/RAC 集群 | 单机/集群 | 单机/集群 | 分布式 | 分布式 |
| **兼容基线** | 原生 | Oracle 高度兼容 | Oracle + PG 双模 | Oracle 模式 | Oracle 模式 |
| **'' = NULL** | 是 | 是 | 可配置 | 是(Oracle模式) | 是(Oracle模式) |
| **DUAL** | 必需 | 必需 | 可选 | 必需(Oracle模式) | 必需(Oracle模式) |
| **PL/SQL** | 完整 PL/SQL | DMSQL（高度兼容） | PL/SQL 兼容层 | PL（部分兼容） | PL/pgSQL + 兼容 |
| **Package** | 完整 | 完整 | 部分 | 部分 | 部分 |
| **CONNECT BY** | 完整 | 完整 | 完整 | 完整 | 完整 |
| **NUMBER** | 原生 | 兼容 | 兼容 | 兼容 | 兼容 |
| **VARCHAR2 (BYTE/CHAR)** | 完整 | 完整 | 部分 | 完整 | 完整 |
| **DECODE** | 原生 | 兼容 | 兼容 | 兼容 | 兼容 |
| **ROWNUM** | 原生 | 兼容 | 兼容 | 兼容 | 兼容 |
| **NLS 参数** | 完整 | 部分 | 部分 | 部分 | 部分 |
| **MERGE** | 完整 | 完整 | 完整 | 完整 | 完整 |
| **DBMS_* 包** | 完整（数百个） | 高频包支持 | 高频包支持 | 部分 | 部分 |
| **Data Guard / 高可用** | Data Guard | 守护集群 | 流复制 | Paxos | Paxos |
| **参考文件** | [oracle.md](../dialects/oracle.md) | [dameng.md](../dialects/dameng.md) | [kingbase.md](../dialects/kingbase.md) | [oceanbase.md](../dialects/oceanbase.md) | N/A |

### 关键对比说明

- **达梦 DamengDB** 对 Oracle 兼容度最高，目标是"平迁"Oracle 应用，DMSQL 过程语言与 PL/SQL 高度一致
- **人大金仓 KingbaseES** 同时兼容 Oracle 和 PostgreSQL，可通过 `db_mode` 参数切换模式
- **OceanBase Oracle 模式** 是 OceanBase 的双引擎之一，与 MySQL 模式共享存储层但 SQL 层独立
- **GaussDB Oracle 模式** 基于 openGauss（PostgreSQL fork），在 PG 基础上增加 Oracle 兼容层

## 从 Oracle 迁移的语法对照

### 函数映射表

| Oracle 函数 | SQL 标准等价 | PostgreSQL 等价 | MySQL 等价 | 说明 |
|------------|-------------|----------------|-----------|------|
| `NVL(a, b)` | `COALESCE(a, b)` | `COALESCE(a, b)` | `IFNULL(a, b)` | COALESCE 支持多参数 |
| `NVL2(a, b, c)` | `CASE WHEN a IS NOT NULL THEN b ELSE c END` | 同左 | `IF(a IS NOT NULL, b, c)` | 无标准函数 |
| `DECODE(a,b,c,d)` | `CASE a WHEN b THEN c ELSE d END` | 同左 | 同左 | DECODE 的 NULL 语义需特殊处理 |
| `TO_CHAR(date, fmt)` | N/A | `TO_CHAR(date, fmt)` | `DATE_FORMAT(date, fmt)` | PG 兼容 Oracle 格式符 |
| `TO_DATE(str, fmt)` | N/A | `TO_DATE(str, fmt)` | `STR_TO_DATE(str, fmt)` | 格式符不同 |
| `TO_NUMBER(str)` | `CAST(str AS NUMERIC)` | `str::numeric` | `CAST(str AS DECIMAL)` | |
| `SYSDATE` | `CURRENT_DATE` | `NOW()::date` | `CURDATE()` | Oracle SYSDATE 含时间 |
| `SYSTIMESTAMP` | `CURRENT_TIMESTAMP` | `CURRENT_TIMESTAMP` | `NOW()` | |
| `ADD_MONTHS(d, n)` | N/A | `d + INTERVAL 'n months'` | `DATE_ADD(d, INTERVAL n MONTH)` | |
| `MONTHS_BETWEEN(d1, d2)` | N/A | `EXTRACT(YEAR FROM age(d1,d2))*12 + EXTRACT(MONTH FROM age(d1,d2))` | `TIMESTAMPDIFF(MONTH, d2, d1)` | |
| `TRUNC(date)` | `CAST(date AS DATE)` | `DATE_TRUNC('day', ts)` | `DATE(ts)` | Oracle 截断时间部分 |
| `SUBSTR(s, pos, len)` | `SUBSTRING(s FROM pos FOR len)` | `SUBSTR(s, pos, len)` | `SUBSTR(s, pos, len)` | Oracle pos 从 1 开始 |
| `INSTR(s, sub)` | `POSITION(sub IN s)` | `POSITION(sub IN s)` | `LOCATE(sub, s)` | Oracle 版支持起始位置和第 N 次 |
| `LENGTH(s)` | `CHAR_LENGTH(s)` | `LENGTH(s)` | `CHAR_LENGTH(s)` | Oracle: LENGTH(NULL) = NULL，LENGTH('') = NULL |
| `LISTAGG(col, ',')` | N/A | `STRING_AGG(col, ',')` | `GROUP_CONCAT(col)` | PG 无 LISTAGG |
| `ROWNUM` | N/A | `ROW_NUMBER() OVER ()` | `LIMIT` | 语义不同 |
| `CONNECT BY` | `WITH RECURSIVE` | `WITH RECURSIVE` | `WITH RECURSIVE (8.0+)` | 需重写 |

### 类型映射表

| Oracle 类型 | SQL 标准等价 | PostgreSQL 等价 | MySQL 等价 | 说明 |
|------------|-------------|----------------|-----------|------|
| `NUMBER(p,s)` | `NUMERIC(p,s)` | `NUMERIC(p,s)` | `DECIMAL(p,s)` | |
| `NUMBER` (无参数) | `NUMERIC(38)` | `NUMERIC` | `DECIMAL(65,30)` | 建议指定精度 |
| `NUMBER(10)` | `INTEGER` | `INTEGER` / `BIGINT` | `INT` / `BIGINT` | 按范围映射 |
| `VARCHAR2(n)` | `VARCHAR(n)` | `VARCHAR(n)` | `VARCHAR(n)` | 注意字节/字符语义 |
| `NVARCHAR2(n)` | `NCHAR VARYING(n)` | `VARCHAR(n)` | `NVARCHAR(n)` | PG 不区分 N/非N |
| `CHAR(n)` | `CHAR(n)` | `CHAR(n)` | `CHAR(n)` | Oracle 自动补空格 |
| `DATE` | `TIMESTAMP(0)` | `TIMESTAMP(0)` | `DATETIME` | Oracle DATE 含时间！ |
| `TIMESTAMP` | `TIMESTAMP` | `TIMESTAMP` | `DATETIME(6)` | |
| `TIMESTAMP WITH TIME ZONE` | `TIMESTAMP WITH TIME ZONE` | `TIMESTAMPTZ` | N/A | MySQL 无此类型 |
| `CLOB` | `CLOB` | `TEXT` | `LONGTEXT` | |
| `BLOB` | `BLOB` | `BYTEA` | `LONGBLOB` | |
| `RAW(n)` | N/A | `BYTEA` | `VARBINARY(n)` | |
| `LONG` | N/A | `TEXT` | `LONGTEXT` | 已废弃，用 CLOB 替代 |
| `BINARY_FLOAT` | `FLOAT` | `REAL` | `FLOAT` | IEEE 754 单精度 |
| `BINARY_DOUBLE` | `DOUBLE PRECISION` | `DOUBLE PRECISION` | `DOUBLE` | IEEE 754 双精度 |
| `XMLTYPE` | `XML` | `XML` | N/A | MySQL 无原生 XML |
| `INTERVAL YEAR TO MONTH` | `INTERVAL` | `INTERVAL` | N/A | |
| `INTERVAL DAY TO SECOND` | `INTERVAL` | `INTERVAL` | N/A | |

### 语法差异对照

| 功能 | Oracle 语法 | SQL 标准语法 | 说明 |
|------|-----------|-------------|------|
| **外连接** | `WHERE a.id = b.id(+)` | `LEFT JOIN b ON a.id = b.id` | (+) 语法已废弃 |
| **分页** | `WHERE ROWNUM <= 10` | `FETCH FIRST 10 ROWS ONLY` | Oracle 12c+ 支持标准语法 |
| **字符串拼接** | `\|\|` | `\|\|` | 与标准一致 |
| **空值替换** | `NVL(a, b)` | `COALESCE(a, b)` | COALESCE 更通用 |
| **自增列** | `SEQUENCE + 触发器` 或 `IDENTITY (12c+)` | `GENERATED AS IDENTITY` | |
| **行号** | `ROWNUM` | `ROW_NUMBER() OVER()` | |
| **层次查询** | `CONNECT BY PRIOR` | `WITH RECURSIVE` | |
| **UPSERT** | `MERGE INTO` | `MERGE INTO` | Oracle 的 MERGE 最早实现 |
| **删除重复** | `WHERE ROWID NOT IN (...)` | `WITH cte AS (... ROW_NUMBER()) DELETE ...` | ROWID 是物理地址 |
| **条件聚合** | `DECODE(col, val, 1)` + `SUM` | `FILTER (WHERE ...)` 或 `CASE WHEN` | |
| **字符串截取** | `SUBSTR(s, start, len)` | `SUBSTRING(s FROM start FOR len)` | Oracle 版更简洁 |
| **当前时间** | `SYSDATE` / `SYSTIMESTAMP` | `CURRENT_DATE` / `CURRENT_TIMESTAMP` | SYSDATE 含时间 |
| **IF-ELSE 查询** | `DECODE()` | `CASE WHEN` | DECODE 的 NULL 行为不同 |

## 迁移检查清单

从 Oracle 迁移到其他引擎前，检查以下高风险项：

### 第一步: SQL 层面

- [ ] 搜索所有 `''`（空字符串），检查是否依赖 `'' = NULL` 语义
- [ ] 搜索所有 `FROM DUAL`，确认目标引擎是否需要
- [ ] 搜索所有 `DECODE`，确认 NULL 比较逻辑是否正确
- [ ] 搜索所有 `ROWNUM`，替换为 `ROW_NUMBER()` 或 `LIMIT`
- [ ] 搜索所有 `CONNECT BY`，重写为递归 CTE
- [ ] 搜索所有 `(+)` 外连接语法，替换为 `LEFT/RIGHT JOIN`
- [ ] 搜索所有 `DATE` 类型列，确认目标引擎是否含时间
- [ ] 检查 `NLS_DATE_FORMAT` 依赖，替换为显式 `TO_DATE(str, fmt)` 调用

### 第二步: PL/SQL 层面

- [ ] Package 拆分为独立的过程/函数
- [ ] Package 变量改为表存储或应用层管理
- [ ] DBMS_OUTPUT 替换为目标引擎的日志/输出机制
- [ ] 自治事务（PRAGMA AUTONOMOUS_TRANSACTION）替换为独立连接
- [ ] 游标 FOR 循环检查是否有等价实现
- [ ] 异常处理（WHEN OTHERS THEN）检查异常类型映射

### 第三步: 数据类型

- [ ] NUMBER 按精度映射为 INT/BIGINT/DECIMAL
- [ ] VARCHAR2 确认字节/字符语义
- [ ] DATE 确认是否需要改为 TIMESTAMP
- [ ] CLOB/BLOB 确认目标引擎的大对象处理
- [ ] RAW 类型映射为 BYTEA/VARBINARY

### 第四步: 工具和生态

- [ ] OCI 驱动替换为目标引擎驱动（JDBC/ODBC）
- [ ] SQL*Plus 脚本中的特殊命令（SET、SPOOL、COLUMN）
- [ ] 数据泵（expdp/impdp）替换为目标引擎的导入导出工具

## 版本演进关注点

| Oracle 版本 | 重要变更 | 兼容引擎影响 |
|------------|---------|------------|
| 11g R2 | PIVOT/UNPIVOT、LISTAGG、递归 WITH | 基线功能集 |
| 12c | IDENTITY 列、FETCH FIRST、JSON 支持、VARCHAR2 扩展至 32K | 现代化语法 |
| 18c | 多态表函数 | 高级特性 |
| 19c (长期支持) | SQL 宏、JSON_MERGEPATCH | 企业级标准版本 |
| 21c | JSON 数据类型（原生二进制）、区块链表 | 新特性方向 |
| 23ai (长期支持) | BOOLEAN 类型、FROM 子句可选、SQL 域、JSON 关系二元性 | **重大变更**：FROM DUAL 将可省略 |

> **Oracle 23ai 重要提示**: Oracle 23ai 引入了 `BOOLEAN` 数据类型和"可选 FROM 子句"（`SELECT 1` 无需 `FROM DUAL`）。这意味着 Oracle 自身正在向 SQL 标准靠拢。兼容引擎应关注这些变化，提前支持新语法，同时保持对旧语法的向后兼容。
