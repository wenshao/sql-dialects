# 可更新视图 (Updatable Views)

视图是 SQL 最古老的抽象工具之一，但"可更新视图"却是最被低估、最容易踩坑的特性——同样一句 `UPDATE v SET x = 1`，在 PostgreSQL 上是直接 DML，在 Oracle 上需要满足 key-preserved 规则，在 SQLite 上则必须先写一个 INSTEAD OF 触发器，而在 BigQuery 上根本没有这个概念。本文系统对比 49 个数据库引擎对可更新视图的支持差异。

## 为什么可更新视图重要

可更新视图的核心价值有三个层次：

1. **抽象（Abstraction）**：将复杂的多表 JOIN、列重命名、计算列封装成一个"虚拟表"，应用代码只需要操作视图，底层 schema 演进对应用透明。这是 1970 年代关系模型最初设计视图时的核心动机。
2. **安全（Security）**：通过视图实现行/列级别的权限控制——把 `salary` 列排除在视图之外，或在 `WHERE` 子句中加入 `tenant_id = current_user_tenant()`，再 `REVOKE` 基表权限只 `GRANT` 视图权限。这种"视图作为权限边界"的模式至今仍是企业级 DBMS 的主流方案。
3. **兼容（Compatibility）**：当基表 schema 演进（拆表、重命名列、改类型）时，可以通过创建视图保持旧应用的读写接口不变，实现"零停机迁移"。

但是——视图能不能被 `INSERT/UPDATE/DELETE`，并不是一个简单的"是/否"问题。它牵涉到 SQL 标准的可更新性规则、引擎的 INSTEAD OF 触发器机制、key-preserved 概念、安全屏障（security barrier）等多个维度。

## SQL 标准对可更新视图的演进

### SQL:1992 — "简单可更新视图"

SQL-92 标准（ISO/IEC 9075:1992，§7.9 `<query specification>`）首次正式规定了"简单可更新视图"（simply updatable view）必须同时满足的所有条件：

```sql
CREATE VIEW v AS
    SELECT col1, col2, col3
    FROM single_base_table
    WHERE predicate;
```

具体规则（标准原文要点）：

1. `FROM` 子句必须只引用**一个**基表（或另一个本身可更新的视图）。
2. 不能出现 `DISTINCT`。
3. 不能出现 `GROUP BY` 或 `HAVING`。
4. `SELECT` 列表中不能出现聚集函数（`SUM/COUNT/AVG/MIN/MAX` 等）。
5. `SELECT` 列表中的每一列必须是基表的一个简单列引用，不能是表达式或字面量（否则该列只读）。
6. 不能出现 `UNION/INTERSECT/EXCEPT`。
7. 子查询中不能引用视图本身的基表（避免读写冲突）。

满足以上规则的视图天然支持 `INSERT/UPDATE/DELETE`，并且行为等价于直接对底层基表进行操作。

SQL:1992 还引入了 `WITH CHECK OPTION`：通过视图插入或更新的行必须满足视图的 `WHERE` 谓词，否则报错。这是为了防止"插入了一个视图查询不到的行"这类反直觉的情况。

### SQL:1999 — 扩展规则

SQL:1999 放宽了一些限制，引入"潜在可更新"（potentially updatable）的概念：

- 允许 `SELECT` 列表中出现派生列，但派生列在 `INSERT/UPDATE` 中是只读的。
- 允许部分 `JOIN` 视图可更新（条件是 JOIN 中只有一侧的列被修改，且另一侧能够"key-preserve"——这个概念后被 Oracle 标准化为产品规则）。
- 引入 `WITH LOCAL CHECK OPTION` 和 `WITH CASCADED CHECK OPTION` 的区分。

### SQL:2003 — INSTEAD OF 触发器（终极方案）

SQL:1999 引入了触发器（trigger），SQL:2003 进一步规范了 `INSTEAD OF` 触发器：对任何视图（无论多复杂）定义 `INSTEAD OF INSERT/UPDATE/DELETE` 触发器后，视图就"可更新"了——引擎不再尝试推导 DML 应该如何映射到基表，而是把这个责任交给触发器作者。

```sql
CREATE TRIGGER v_insert INSTEAD OF INSERT ON v
    REFERENCING NEW ROW AS n
    FOR EACH ROW
    BEGIN ATOMIC
        INSERT INTO base_table_a (...) VALUES (n....);
        INSERT INTO base_table_b (...) VALUES (n....);
    END;
```

这套机制最早由 Oracle 8（1997）和 Microsoft SQL Server 2000 引入，后被 SQL:2003 标准化。它本质上把"可更新视图"从"引擎自动推导"模式切换到"用户显式编程"模式，从而支持任意复杂度的视图。

## 支持矩阵（49 个引擎）

下表统计了主流数据库引擎对各种可更新视图能力的支持。表头说明：

- **简单可更新**：单基表、无聚集、无 DISTINCT 的视图自动可写
- **多表/JOIN 可更新**：JOIN 视图自动可写（通常需 key-preserved）
- **WITH CHECK OPTION**：是否支持，以及是否支持 LOCAL/CASCADED 选项
- **INSTEAD OF 触发器**：是否可对视图定义 INSTEAD OF 触发器
- **物化视图可写**：物化视图本身能否直接 DML

| 引擎 | 简单可更新 | 多表 JOIN 可更新 | WITH CHECK OPTION | INSTEAD OF 触发器 | 物化视图可写 |
|------|-----------|-----------------|-------------------|-------------------|-------------|
| PostgreSQL | 是 (9.3+) | 否（需 RULE/触发器） | LOCAL + CASCADED | 是 | 否 |
| MySQL | 是 (MERGE 算法) | 是（key-preserved） | LOCAL + CASCADED | 否 | -- (无原生 MV) |
| MariaDB | 是 (MERGE 算法) | 是 | LOCAL + CASCADED | 否 | -- |
| SQLite | 否 | 否 | 否 | 是（唯一手段） | -- |
| Oracle | 是 | 是（key-preserved） | 是 (CHECK OPTION) | 是 | 否 (默认)，可 ON PREBUILT TABLE |
| SQL Server | 是 | 是（受限） | 是 (CHECK OPTION) | 是 (2000+) | 索引视图：可（间接） |
| DB2 (LUW) | 是 | 是（key-preserved） | LOCAL + CASCADED | 是 | MQT：否 |
| Snowflake | 否 | 否 | 否 | 否 | 否 |
| BigQuery | 否 | 否 | 否 | 否 | 否（自动维护） |
| Redshift | 否 | 否 | 否 | 否 | 否 |
| DuckDB | 否 | 否 | 否 | 否 | -- |
| ClickHouse | 否 | 否 | 否 | 否 | 物化视图 INSERT 触发，不可直接写 |
| Trino | 否 | 否 | 否 | 否 | 否 |
| Presto | 否 | 否 | 否 | 否 | 否 |
| Spark SQL | 否 | 否 | 否 | 否 | 否 |
| Hive | 否 | 否 | 否 | 否 | 否 |
| Flink SQL | 否 | 否 | 否 | 否 | -- (动态表自动维护) |
| Databricks | 否 | 否 | 否 | 否 | 否 |
| Teradata | 是 | 受限 | 是 | 否 (有 row trigger) | Join Index：否 |
| Greenplum | 是（继承 PG） | 否 | LOCAL + CASCADED | 是 | 否 |
| CockroachDB | 否 | 否 | 否 | 否 | -- |
| TiDB | 是（兼容 MySQL） | 是 | LOCAL + CASCADED | 否 | -- |
| OceanBase | 是（兼容 MySQL/Oracle 模式） | 是（Oracle 模式） | 是 | Oracle 模式：是 | 否 |
| YugabyteDB | 是（继承 PG） | 否 | LOCAL + CASCADED | 是 | 否 |
| SingleStore | 否 | 否 | 否 | 否 | -- |
| Vertica | 否 | 否 | 否 | 否 | 否 |
| Impala | 否 | 否 | 否 | 否 | 否 |
| StarRocks | 否 | 否 | 否 | 否 | 异步 MV：否 |
| Doris | 否 | 否 | 否 | 否 | 同步 MV：否 |
| MonetDB | 否 | 否 | 否 | 否 | -- |
| CrateDB | 否 | 否 | 否 | 否 | -- |
| TimescaleDB | 是（继承 PG） | 否 | LOCAL + CASCADED | 是 | 连续聚合：否 |
| QuestDB | 否 | 否 | 否 | 否 | -- |
| Exasol | 否 | 否 | 否 | 否 | -- |
| SAP HANA | 是 | 受限 | 是 | 是 | 否 |
| Informix | 是 | 否 | 是 | 是 | -- |
| Firebird | 是 | 否 | 是 | 是 (BEFORE/AFTER) | -- |
| H2 | 是 | 否 | 否 | 是（INSTEAD OF） | -- |
| HSQLDB | 是 | 否 | LOCAL + CASCADED | 是 | -- |
| Derby | 否 | 否 | 否 | 否 | -- |
| Amazon Athena | 否 | 否 | 否 | 否 | 否 |
| Azure Synapse | 否 | 否 | 否 | 否 | 物化视图：否 |
| Google Spanner | 否 | 否 | 否 | 否 | -- |
| Materialize | 否 | 否 | 否 | 否 | 否（增量自动维护） |
| RisingWave | 否 | 否 | 否 | 否 | 否 |
| InfluxDB (SQL) | 否 | 否 | 否 | 否 | -- |
| Databend | 否 | 否 | 否 | 否 | 否 |
| Yellowbrick | 否 | 否 | 否 | 否 | -- |
| Firebolt | 否 | 否 | 否 | 否 | 否 |

> 统计：在 49 个引擎中，约 18 个支持某种形式的"简单可更新视图"，约 12 个支持"INSTEAD OF 触发器"作为可更新性的兜底机制；约 31 个完全不支持视图 DML（主要是 OLAP / 云数仓 / 流处理引擎）。

### WITH CHECK OPTION 的 LOCAL vs CASCADED

`WITH CHECK OPTION` 有两种模式，二者在多层嵌套视图时行为不同：

- **LOCAL**：插入/更新只需满足**当前视图**的 `WHERE` 谓词，不要求满足底层视图（链）的谓词。
- **CASCADED**（默认）：必须满足**当前视图及其所有底层视图**的 `WHERE` 谓词。

```sql
CREATE VIEW v1 AS SELECT * FROM t WHERE a > 0;
CREATE VIEW v2 AS SELECT * FROM v1 WHERE b > 0 WITH LOCAL CHECK OPTION;
CREATE VIEW v3 AS SELECT * FROM v1 WHERE b > 0 WITH CASCADED CHECK OPTION;

INSERT INTO v2 VALUES (-1, 1);   -- 成功（仅检查 b>0）
INSERT INTO v3 VALUES (-1, 1);   -- 失败（要求 a>0 AND b>0）
```

| 引擎 | LOCAL | CASCADED | 默认 |
|------|-------|----------|------|
| PostgreSQL | 是 (9.4+) | 是 (9.4+) | CASCADED |
| MySQL | 是 | 是 | CASCADED |
| MariaDB | 是 | 是 | CASCADED |
| Oracle | 仅 `WITH CHECK OPTION`（无 LOCAL/CASCADED 关键字，行为接近 LOCAL） | -- | LOCAL（默认且唯一） |
| SQL Server | 仅 `WITH CHECK OPTION`（无 LOCAL/CASCADED 关键字，行为接近 LOCAL） | -- | LOCAL（默认且唯一） |
| DB2 LUW | 是 | 是 | CASCADED |
| HSQLDB | 是 | 是 | CASCADED |
| Greenplum/YugabyteDB/TimescaleDB | 是 | 是 | CASCADED（继承 PG） |
| TiDB | 是 | 是 | CASCADED |

### 物化视图与可更新性

绝大多数引擎的物化视图（Materialized View）是只读的：你只能 `REFRESH` 它，而不能直接 `INSERT/UPDATE/DELETE`。这是因为物化视图被定义为某个查询的快照，写入的语义是模糊的——是改快照还是改基表？例外情况：

- **Oracle**：默认物化视图只读；通过 `ON PREBUILT TABLE` 子句创建的物化视图实际上就是普通表，可写。`UPDATABLE` 关键字配合 Materialized View Replication 可以让 MV 接受写入并通过 refresh 同步回主站。
- **DB2 MQT (Materialized Query Table)**：默认 SYSTEM-MAINTAINED 不可写；`USER-MAINTAINED` 可写但需要用户负责正确性。
- **ClickHouse**：物化视图本质是一个"INSERT 触发器 + 目标表"，可以向源表 INSERT 来间接驱动；目标表本身可以直接写入，但绕过了视图的语义。
- **Materialize / RisingWave / Flink Dynamic Table**：基于增量计算引擎，物化视图严格自动维护，禁止外部写入。

## 各引擎深度解析

### PostgreSQL

PostgreSQL 的可更新视图支持是开源数据库中最丰富的，三种机制并存：

#### 1. 自动可更新视图（9.3+, 2013）

PostgreSQL 9.3 引入"auto-updatable view"特性，对满足以下条件的视图自动支持 `INSERT/UPDATE/DELETE`：

- `FROM` 子句只有一个基表（或另一个 auto-updatable 视图）
- 没有 `WITH`、`DISTINCT`、`GROUP BY`、`HAVING`、`LIMIT`、`OFFSET`、`FETCH`
- `SELECT` 列表只有简单列引用（无表达式、无聚集、无窗口函数）
- 没有集合操作
- 列没有重复

```sql
CREATE TABLE employees (id SERIAL PRIMARY KEY, name TEXT, dept_id INT, salary NUMERIC);
CREATE VIEW v_emp_public AS
    SELECT id, name, dept_id FROM employees WHERE dept_id IS NOT NULL;

INSERT INTO v_emp_public (name, dept_id) VALUES ('Alice', 10);
UPDATE v_emp_public SET dept_id = 20 WHERE name = 'Alice';
DELETE FROM v_emp_public WHERE id = 1;
```

注意：`salary` 列被视图排除，因此通过视图无法访问/修改它，这就是"列级安全"的实现。

#### 2. INSTEAD OF 触发器（适用于任意复杂度视图）

```sql
CREATE VIEW v_emp_full AS
    SELECT e.id, e.name, d.dept_name, e.salary
    FROM employees e JOIN departments d ON e.dept_id = d.id;

CREATE FUNCTION v_emp_full_insert() RETURNS trigger AS $$
DECLARE
    v_dept_id INT;
BEGIN
    SELECT id INTO v_dept_id FROM departments WHERE dept_name = NEW.dept_name;
    INSERT INTO employees (name, dept_id, salary)
        VALUES (NEW.name, v_dept_id, NEW.salary)
        RETURNING id INTO NEW.id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER v_emp_full_insert_trg
    INSTEAD OF INSERT ON v_emp_full
    FOR EACH ROW EXECUTE FUNCTION v_emp_full_insert();
```

#### 3. RULE 系统（PostgreSQL 历史遗产）

PostgreSQL 早在 1990 年代就引入了 RULE 系统，本质是查询重写：当对视图执行某个 DML 时，引擎根据 RULE 把它重写为针对基表的 DML。Auto-updatable view 实际上就是引擎自动生成 RULE。用户也可以手动写 RULE：

```sql
CREATE RULE v_emp_insert AS
    ON INSERT TO v_emp_full
    DO INSTEAD INSERT INTO employees (name, dept_id) VALUES (NEW.name, ...);
```

RULE 与 INSTEAD OF 触发器的核心区别：RULE 在查询重写阶段生效（早），可以处理整个语句一次性的批量改写；触发器在执行阶段对每行触发（晚），灵活但开销略高。PostgreSQL 官方文档现在推荐使用 INSTEAD OF 触发器，RULE 主要保留兼容性。

#### 4. security_barrier 视图

PostgreSQL 9.2 引入 `security_barrier` 视图属性，用于解决 leaky 谓词攻击：

```sql
CREATE VIEW v_my_orders WITH (security_barrier) AS
    SELECT * FROM orders WHERE user_id = current_user_id();
```

普通视图被规划器优化时，可能把外层的 `WHERE` 谓词下推到视图内部，导致一个恶意函数（如 `RAISE NOTICE`）可以"看到"本不该可见的行。`security_barrier` 强制视图谓词先于外层谓词执行，避免下推泄漏。代价是部分查询无法被优化器下推，性能可能下降。

PostgreSQL 9.4 进一步增强：security_barrier 视图也可以是 auto-updatable 的，前提是函数被标记为 `LEAKPROOF`。

### Oracle

Oracle 是最早支持可更新视图（包括 JOIN 视图）的商业 DBMS 之一。其核心规则是 **key-preserved table（保留键的表）**：

> 在一个 JOIN 视图中，如果一个表 T 的每一行最多只对应视图结果中的一行（即 T 的主键在 JOIN 后仍是视图的"超键"），那么 T 就是 key-preserved 的，对该表列的更新是允许的。

```sql
CREATE TABLE departments (dept_id NUMBER PRIMARY KEY, dept_name VARCHAR2(50));
CREATE TABLE employees (
    emp_id NUMBER PRIMARY KEY,
    name VARCHAR2(50),
    dept_id NUMBER REFERENCES departments(dept_id)
);

CREATE VIEW v_emp_dept AS
    SELECT e.emp_id, e.name, e.dept_id, d.dept_name
    FROM employees e JOIN departments d ON e.dept_id = d.dept_id;

-- 合法：employees 是 key-preserved 的（emp_id 在视图中唯一）
UPDATE v_emp_dept SET name = 'Bob' WHERE emp_id = 1;

-- 不合法：departments 不是 key-preserved 的（一个部门对应多个员工，dept_id 不唯一）
UPDATE v_emp_dept SET dept_name = 'X' WHERE emp_id = 1;
-- ORA-01779: cannot modify a column which maps to a non key-preserved table
```

Oracle 用 `USER_UPDATABLE_COLUMNS` 数据字典视图告诉用户哪些列可更新：

```sql
SELECT column_name, updatable, insertable, deletable
FROM user_updatable_columns WHERE table_name = 'V_EMP_DEPT';
```

Oracle 也支持 `INSTEAD OF` 触发器，对任意复杂的视图都能实现可写：

```sql
CREATE OR REPLACE TRIGGER v_emp_dept_iud
    INSTEAD OF INSERT OR UPDATE OR DELETE ON v_emp_dept
    FOR EACH ROW
BEGIN
    IF INSERTING THEN
        INSERT INTO employees (emp_id, name, dept_id) VALUES (:NEW.emp_id, :NEW.name, :NEW.dept_id);
    ELSIF UPDATING THEN
        UPDATE employees SET name = :NEW.name WHERE emp_id = :OLD.emp_id;
    ELSIF DELETING THEN
        DELETE FROM employees WHERE emp_id = :OLD.emp_id;
    END IF;
END;
```

### SQL Server

SQL Server 的可更新视图规则与 Oracle 类似但更严格：

1. 单表视图：满足简单规则即可自动可写。
2. 多表 JOIN 视图：自动可写，但 `INSERT/UPDATE/DELETE` **每个语句只能影响一个基表**——你不能在一个 `UPDATE` 中同时改两个表的列。
3. 任意视图 + INSTEAD OF 触发器：SQL Server 2000 引入 INSTEAD OF 触发器，是商业 DBMS 中最早的实现之一。

```sql
CREATE VIEW v_emp_full AS
    SELECT e.id, e.name, d.name AS dept_name
    FROM employees e JOIN departments d ON e.dept_id = d.id;

CREATE TRIGGER trg_v_emp_insert ON v_emp_full
INSTEAD OF INSERT
AS
BEGIN
    INSERT INTO departments (id, name)
    SELECT DISTINCT NULL, dept_name FROM inserted i
        WHERE NOT EXISTS (SELECT 1 FROM departments d WHERE d.name = i.dept_name);
    INSERT INTO employees (name, dept_id)
    SELECT i.name, d.id FROM inserted i JOIN departments d ON d.name = i.dept_name;
END;
```

SQL Server 还支持 `WITH CHECK OPTION`（LOCAL-like 语义，无 LOCAL/CASCADED 关键字区分）和 `SCHEMABINDING` 选项（绑定视图与基表 schema，防止基表被改）。索引视图（indexed view）是 SQL Server 的物化视图实现，不能直接 DML，但优化器可以自动用它替代基表查询。

### MySQL / MariaDB

MySQL 的视图有两种执行算法：

- **MERGE**：把视图定义内联到查询里，等价于宏展开。MERGE 算法的视图天然可更新（在 SQL:1992 简单规则下）。
- **TEMPTABLE**：先把视图执行成临时表，然后查询临时表。TEMPTABLE 视图**永远不可更新**——因为临时表与基表已经"切断"。
- **UNDEFINED**（默认）：让优化器自动选择，如果视图允许 MERGE 就用 MERGE，否则降级到 TEMPTABLE。

```sql
CREATE ALGORITHM = MERGE VIEW v_active_users AS
    SELECT id, name, email FROM users WHERE status = 'active'
    WITH CASCADED CHECK OPTION;

INSERT INTO v_active_users (name, email) VALUES ('Alice', 'a@x.com');
-- 自动设 status = NULL（基表默认），但 CASCADED CHECK OPTION 会拒绝
-- 因为新行不满足 status = 'active'
```

MySQL 不支持 `INSTEAD OF` 触发器（虽然支持 `BEFORE/AFTER` 触发器，但这些触发器不能定义在视图上）。这是 MySQL 与几乎所有其它 DBMS 的一个重大差异：复杂视图只能通过应用层 DML 改写来实现"可写"。

MySQL 多表 JOIN 视图的可更新规则（与 Oracle 类似但更宽松）：在 `INSERT` 时一次只能影响一个基表；在 `UPDATE` 时可以同时更新多个基表的列（如果 JOIN 是 1:1 等价的）；在 `DELETE` 时单语句只能从一个基表删除。

MariaDB 与 MySQL 行为基本一致，差异主要在 SQL 模式和某些细节。

### DB2 (LUW)

DB2 对可更新视图的支持非常完整，紧跟 SQL 标准：

- 简单可更新视图：符合 SQL:1992 规则的视图自动可写。
- JOIN 可更新视图：DB2 支持 key-preserved JOIN 视图（与 Oracle 概念相同），通过引用约束（referential constraint）来推导 key-preserved 关系。
- INSTEAD OF 触发器：完全支持，且比许多引擎更早实现。
- WITH CHECK OPTION：支持 LOCAL 和 CASCADED 两种模式。

```sql
CREATE VIEW v_high_salary AS
    SELECT id, name, salary FROM employees WHERE salary > 100000
    WITH CASCADED CHECK OPTION;

-- DB2 引擎会确保 INSERT/UPDATE 后的行仍然满足 salary > 100000
INSERT INTO v_high_salary (name, salary) VALUES ('Alice', 50000);
-- SQL0161N: The INSERT or UPDATE is not allowed because a resulting row
--           does not satisfy the view definition.
```

DB2 还有 `MATERIALIZED QUERY TABLE (MQT)` —— 物化查询表，是物化视图的标准化命名。MQT 默认 `SYSTEM MAINTAINED` 不可写，可改为 `USER MAINTAINED` 让用户负责数据正确性。

### SQLite

SQLite 的处理方式最为独特：**所有视图默认完全只读**，无论多简单。要让视图支持 DML，唯一的方法是定义 `INSTEAD OF` 触发器：

```sql
CREATE VIEW v_emp_simple AS SELECT id, name FROM employees;

-- 直接 INSERT 会失败
INSERT INTO v_emp_simple VALUES (1, 'Alice');
-- Error: cannot modify v_emp_simple because it is a view

CREATE TRIGGER trg_v_emp_insert
    INSTEAD OF INSERT ON v_emp_simple
    FOR EACH ROW
BEGIN
    INSERT INTO employees (id, name) VALUES (NEW.id, NEW.name);
END;

-- 现在可以了
INSERT INTO v_emp_simple VALUES (1, 'Alice');
```

这种"全显式"设计哲学符合 SQLite 一贯的极简主义：引擎不做隐式推导，所有行为都由用户显式声明。优点是没有意外，缺点是即使最简单的视图也要写一堆 trigger boilerplate。

### 其它引擎要点

**Teradata**：可更新视图的规则与 SQL 标准接近，支持简单可更新和受限的 JOIN 可更新。Teradata 没有 `INSTEAD OF` 触发器，但有完整的 `BEFORE/AFTER` 行级触发器（不能用在视图上）。

**Greenplum / TimescaleDB / YugabyteDB**：完全继承 PostgreSQL 的可更新视图机制，包括 auto-updatable、INSTEAD OF 触发器、RULE 系统和 security_barrier。这是 PostgreSQL 生态的一致性优势。

**TiDB**：MySQL 兼容层，支持 MERGE 算法可更新视图和 WITH CHECK OPTION，行为与 MySQL 一致。

**OceanBase**：双模式数据库，MySQL 模式下行为类似 MySQL，Oracle 模式下行为类似 Oracle（包括 key-preserved 和 INSTEAD OF 触发器）。

**SAP HANA**：支持自动可更新视图（含部分 JOIN 视图）和 INSTEAD OF 触发器，规则在商业 DBMS 中算比较完整。

**H2 / HSQLDB / Firebird / Informix**：嵌入式/中型数据库，普遍支持简单可更新视图 + INSTEAD OF 触发器。HSQLDB 甚至完整支持 LOCAL/CASCADED CHECK OPTION，是兼容 SQL 标准最严格的开源引擎之一。

**Derby**：Apache Derby 在视图可更新方面非常受限——视图被视为完全只读，且不支持 INSTEAD OF 触发器，应用必须直接对基表写入。

**OLAP 列存引擎**（ClickHouse / DuckDB / MonetDB / Vertica / StarRocks / Doris / Impala / Greenplum (列存表)）：几乎全部不支持视图 DML。这背后有两个原因：(1) OLAP 引擎的 DML 本身非常受限（很多只支持 batch INSERT，不支持单行 UPDATE/DELETE 或代价极高），(2) OLAP 视图的主要用例是预聚合和报表，没有人通过视图做 DML。

**云数仓**（Snowflake / BigQuery / Redshift / Azure Synapse / Athena / Firebolt / Databend / Yellowbrick）：全部不支持可更新视图。这是产品定位决定的——这些引擎的核心场景是"读多写少"的数据仓库分析，写入路径走 COPY/INSERT/MERGE 直接对表操作。

**流处理引擎**（Flink / Materialize / RisingWave）：物化视图由增量计算自动维护，写入路径与视图概念正交，"视图可更新"在这里没有意义。

## "Key-preserved" 概念深度解读

Key-preserved 是理解 Oracle/DB2 多表可更新视图的核心概念。形式化定义：

> 给定一个视图 `V = T1 JOIN T2 ON ...`，如果对于 T1 的任何主键值 k，最多有一行 V 的结果包含 k，那么 T1 就是 V 中的 key-preserved table。

这等价于：T1 的主键在视图结果上仍然是一个**唯一标识符**。换句话说，从 V 的一行可以反向唯一确定 T1 中的一行。这是 DML 语义清晰的必要条件——如果 V 的一行对应 T1 的多行（或不对应），那么对 V 的更新无法明确映射到 T1。

### 具体例子

```sql
CREATE TABLE departments (dept_id PRIMARY KEY, dept_name);
CREATE TABLE employees (emp_id PRIMARY KEY, name, dept_id REFERENCES departments);

CREATE VIEW v AS
    SELECT e.emp_id, e.name, d.dept_id, d.dept_name
    FROM employees e JOIN departments d ON e.dept_id = d.dept_id;
```

- `employees` 是 key-preserved：每个 `emp_id` 在 v 中最多对应一行（因为一个员工只属于一个部门）。
- `departments` **不是** key-preserved：一个 `dept_id` 在 v 中可能对应多行（一个部门有多个员工）。

因此 `UPDATE v SET name = 'X' WHERE emp_id = 1` 合法（修改 employees 的 key-preserved 列），而 `UPDATE v SET dept_name = 'Y' WHERE emp_id = 1` 不合法（修改 departments 的非 key-preserved 列——这个修改会"波及"该部门的所有员工，语义不明确）。

### 引擎如何推导 key-preserved

引擎需要根据约束信息自动推导 key-preserved 关系：

1. 检查 JOIN 条件：`e.dept_id = d.dept_id`，其中 `d.dept_id` 是 `departments` 的主键。
2. 由于 JOIN 右侧是 PK 等值，`departments` 的每一行最多匹配一次 → 不会让 `employees` 的行被复制。
3. 因此 `employees` 的 PK 在结果中仍唯一 → key-preserved。
4. 反过来不成立：JOIN 左侧 `e.dept_id` 不是 UNIQUE，`departments` 的同一行可能匹配多个 `employees` 行 → `departments` 不是 key-preserved。

DB2 称这种推导依赖"referential integrity"，Oracle 称之为"unique key + foreign key chain"。如果 schema 上没有这些约束（如未声明的外键），引擎会保守地拒绝 UPDATE。这就是为什么数据建模时声明完整约束不仅是数据正确性问题，也直接影响视图的可写性。

### 多于两表的 JOIN

key-preserved 概念可以推广到 N 表 JOIN：每个表的 PK 在视图结果中是否仍唯一。Oracle 的 `USER_UPDATABLE_COLUMNS` 数据字典会针对每个列给出 `UPDATABLE = YES/NO`，这个标志是对所有 key-preserved 推导的最终结果。

## INSTEAD OF 触发器与 RULE 系统的对比

PostgreSQL 同时拥有 RULE 和 INSTEAD OF trigger 两套机制，理解它们的差异有助于做出正确选择。

| 维度 | RULE | INSTEAD OF Trigger |
|------|------|-------------------|
| 触发时机 | 查询重写阶段（parse 之后，plan 之前） | 执行阶段（每行调用） |
| 粒度 | 整条语句一次重写 | 每行调用一次 |
| 实现复杂度 | 高（需要理解查询树） | 低（普通 PL/pgSQL 函数） |
| 性能开销 | 重写阶段一次性 | 每行一次函数调用 |
| 调试 | 困难（重写后查询不可见） | 容易（标准函数调试） |
| 与 RETURNING 的兼容性 | 良好 | 良好 |
| 与 COPY 的兼容性 | 不支持 INSTEAD COPY | 支持 |
| 推荐场景 | 历史代码兼容 | 新代码首选 |

RULE 系统是 PostgreSQL 最早期的特性之一（来自 Postgres 学术项目），曾被设想为表达力等价于"通用查询重写"的强大工具。但由于其复杂性和 corner case（如多语句、子查询、嵌套视图），社区现在推荐使用 INSTEAD OF trigger。

## 安全屏障视图（security_barrier）

可更新视图的一个常见用途是行级安全（RLS）：

```sql
CREATE VIEW v_my_orders AS
    SELECT * FROM orders WHERE user_id = current_user_id();
GRANT SELECT, INSERT, UPDATE, DELETE ON v_my_orders TO app_role;
REVOKE ALL ON orders FROM app_role;
```

但这种简单视图存在一个安全漏洞：查询优化器可能把外层查询的谓词下推到视图内部。如果攻击者写：

```sql
SELECT * FROM v_my_orders WHERE leaky_log_function(amount);
```

如果 `leaky_log_function` 是一个会输出参数的函数（甚至 `1/0` 也可能从错误信息泄漏），优化器把它下推到 `WHERE user_id = current_user_id()` 之前，那么攻击者就能读到所有用户的订单数据。

PostgreSQL 9.2 引入 `security_barrier` 视图属性来防止这种攻击：

```sql
CREATE VIEW v_my_orders WITH (security_barrier) AS
    SELECT * FROM orders WHERE user_id = current_user_id();
```

加上 `security_barrier` 后，引擎保证视图自身的谓词在外层任何"不可信函数"之前执行。代价是某些查询无法被优化器内联，性能可能下降。

PostgreSQL 9.4 进一步：security_barrier 视图也可以是 auto-updatable 的，前提是涉及的函数被标记为 `LEAKPROOF`（例如 `=`, `<` 等内置操作符）。这让"安全 + 可写"两全其美。

行级安全的更现代方案是 PostgreSQL 9.5+ 引入的 `ROW LEVEL SECURITY` 策略（详见 row-level-security.md），它直接在表上声明策略而无需创建视图，但 security_barrier 视图作为更通用的机制仍然有用。

## 与 INSTEAD OF 触发器、物化视图的关系

可更新视图涉及的几个相邻特性：

- **触发器（triggers.md）**：INSTEAD OF 触发器是可更新视图的"通用兜底"机制。不支持 INSTEAD OF 触发器的引擎（MySQL/MariaDB/Teradata）在复杂视图上的可写性受限。
- **物化视图（materialized-views.md）**：物化视图本质是查询结果的物理快照，几乎所有引擎都把它定义为只读，写入由 `REFRESH` 完成。
- **行级安全（row-level-security.md）**：现代引擎更倾向于直接在表上定义 RLS 策略，而不是用视图实现安全。但视图作为"可写的安全边界"仍是经典模式。
- **CREATE OR REPLACE VIEW（create-or-replace.md）**：可更新视图的演进往往依赖 CREATE OR REPLACE，PostgreSQL 等引擎要求新视图列与旧视图列前缀一致。

## 关键发现

1. **可更新视图是 OLTP 与 OLAP 的一道分水岭**：49 个引擎中支持可更新视图的几乎全是 OLTP / 通用型数据库（PostgreSQL、Oracle、SQL Server、MySQL、DB2 等），而 OLAP 列存引擎和云数据仓库几乎全部不支持。这反映了两类系统对"视图"角色的根本不同认知——OLTP 视为应用 API 抽象层，OLAP 视为查询便捷工具。

2. **INSTEAD OF 触发器是真正的"通用解决方案"**：单基表 + 简单规则的"自动可更新"覆盖了大约 60% 的业务场景，剩下 40%（多表 JOIN、聚集视图、UNION 视图）必须依赖 INSTEAD OF 触发器。不支持 INSTEAD OF 触发器的引擎（MySQL/MariaDB/Teradata/Derby）在复杂视图上的可写性是真正受限的。

3. **PostgreSQL 是开源数据库中可更新视图能力最强的**：自动可更新（9.3+）+ INSTEAD OF 触发器 + RULE 系统 + security_barrier 视图，四套机制并存，覆盖从最简单到最复杂的所有场景。Greenplum、YugabyteDB、TimescaleDB、CockroachDB（部分）都直接受益于这一生态。

4. **Key-preserved 概念是 Oracle/DB2 多表可更新视图的灵魂**：正确建模引用约束（PK + FK）是让 JOIN 视图可更新的前提。这也是为什么"约束建模"在企业 RDBMS 中比在 OLAP 中重要得多——前者的约束直接影响 SQL 表达力，后者的约束往往只是文档。

5. **MySQL 没有 INSTEAD OF 触发器是一个明显缺陷**：MySQL 支持 BEFORE/AFTER 行级触发器，但不能定义在视图上，导致复杂视图的可写性必须靠应用层重写。这是 MySQL 与其它主流商业 DBMS 的一个重大差距，TiDB / OceanBase 在这一点上也继承了限制。

6. **SQLite 的"全显式"哲学**：所有视图默认只读，只能通过 INSTEAD OF 触发器开启写入。这种设计避免了引擎隐式推导带来的意外行为，符合 SQLite 一贯的极简主义。

7. **WITH CHECK OPTION 的 LOCAL/CASCADED 区别在多层视图嵌套时才显现**：单层视图下二者等价。Oracle 和 SQL Server 只支持单一 CHECK OPTION（LOCAL-like 语义，无 LOCAL/CASCADED 关键字区分），PostgreSQL/MySQL/DB2/MariaDB 支持完整的 LOCAL/CASCADED 区分。

8. **物化视图普遍只读**：除 Oracle `ON PREBUILT TABLE` 和 DB2 `USER MAINTAINED MQT` 外，几乎所有引擎的物化视图都是只读快照。流处理引擎（Materialize / RisingWave / Flink）的物化视图更是严格自动维护，禁止外部 DML。

9. **云数仓为何放弃可更新视图**：Snowflake / BigQuery / Redshift 等云数仓的工程取舍很明确——为了简化语义和优化执行计划，主动放弃了可更新视图（以及很多其它"复杂 OLTP 特性"）。这是一种"做减法"的产品哲学，把不属于自己核心场景的特性彻底剥离。

10. **视图作为"安全边界"仍然有效**：尽管现代 RLS 已经普及，但"REVOKE 基表 + GRANT 视图"的模式在企业应用中依然广泛使用，特别是在跨 schema、跨数据库的访问控制场景。security_barrier 视图（PostgreSQL）是这种模式在现代引擎上的安全增强。

## 参考资料

- SQL:1992 标准: ISO/IEC 9075:1992, §7.9 `<query specification>`（updatable view rules）
- SQL:1999 标准: ISO/IEC 9075-2:1999, §11.22 `<view definition>`
- SQL:2003 标准: ISO/IEC 9075-2:2003, §11.39 `<trigger definition>` (INSTEAD OF)
- PostgreSQL: [Updatable Views](https://www.postgresql.org/docs/current/sql-createview.html#SQL-CREATEVIEW-UPDATABLE-VIEWS)
- PostgreSQL: [Rules on INSERT, UPDATE, and DELETE](https://www.postgresql.org/docs/current/rules-update.html)
- PostgreSQL: [Security Barrier Views](https://www.postgresql.org/docs/current/rules-privileges.html)
- Oracle: [Updatable Join Views](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/CREATE-VIEW.html)
- Oracle: [USER_UPDATABLE_COLUMNS](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/USER_UPDATABLE_COLUMNS.html)
- SQL Server: [CREATE VIEW (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-view-transact-sql)
- SQL Server: [INSTEAD OF Triggers](https://learn.microsoft.com/en-us/sql/relational-databases/triggers/dml-triggers)
- MySQL: [Updatable and Insertable Views](https://dev.mysql.com/doc/refman/8.0/en/view-updatability.html)
- MariaDB: [Updatable Views](https://mariadb.com/kb/en/updatable-and-insertable-views/)
- DB2 LUW: [Updatable views](https://www.ibm.com/docs/en/db2/11.5?topic=views-updatable)
- SQLite: [CREATE VIEW](https://www.sqlite.org/lang_createview.html) and [CREATE TRIGGER](https://www.sqlite.org/lang_createtrigger.html)
- HSQLDB: [Schema and Database Objects - Views](http://hsqldb.org/doc/2.0/guide/databaseobjects-chapt.html#dbc_view_creation)
- Date, C.J. "An Introduction to Database Systems" (8th Ed.), Chapter 10: Views
</content>
</invoke>