# CREATE OR REPLACE

幂等 DDL——简化部署脚本、避免 "already exists" 错误的关键语法。

## 支持矩阵

| 引擎 | 对象类型 | 语法 | 备注 |
|------|---------|------|------|
| PostgreSQL | VIEW, FUNCTION, TRIGGER, RULE | `CREATE OR REPLACE` | TABLE 不支持 |
| Oracle | VIEW, FUNCTION, PROCEDURE, PACKAGE, TYPE, TRIGGER | `CREATE OR REPLACE` | TABLE 不支持 |
| Snowflake | TABLE, VIEW, FUNCTION, PROCEDURE, STAGE, STREAM, TASK | `CREATE OR REPLACE` | **最广泛**，TABLE 也支持 |
| DuckDB | VIEW, TABLE, MACRO, FUNCTION, SEQUENCE | `CREATE OR REPLACE` | TABLE 支持 |
| MariaDB | VIEW, FUNCTION, PROCEDURE, TRIGGER | `CREATE OR REPLACE` | TABLE 不支持 |
| BigQuery | VIEW, TABLE, FUNCTION, PROCEDURE | `CREATE OR REPLACE` | TABLE 支持 |
| Databricks | VIEW, TABLE, FUNCTION | `CREATE OR REPLACE` | TABLE 支持 |
| MySQL | VIEW | `CREATE OR REPLACE` | **仅 VIEW**，其他不支持 |
| SQL Server | VIEW, FUNCTION, PROCEDURE, TRIGGER | `CREATE OR ALTER` | **注意: 不是 REPLACE** |
| SQLite | VIEW, TRIGGER | `CREATE ... IF NOT EXISTS` | 语义不同（不替换） |

## CREATE OR REPLACE vs IF NOT EXISTS vs CREATE OR ALTER

这三种语法容易混淆，语义完全不同：

| 语法 | 不存在时 | 已存在时 | 幂等？ |
|------|---------|---------|--------|
| `CREATE` | 创建 | **报错** | 否 |
| `CREATE IF NOT EXISTS` | 创建 | **静默跳过** | 是，但不更新 |
| `CREATE OR REPLACE` | 创建 | **删除旧的，创建新的** | 是，且更新 |
| `CREATE OR ALTER` (SQL Server) | 创建 | **原地修改** | 是，且更新 |

核心区别: `IF NOT EXISTS` 是"不存在才做"，`OR REPLACE` 是"不管存在不存在都做到最新"。

## 设计动机

1. 部署脚本的幂等性

CI/CD 流水线中，DDL 脚本经常需要重复执行：

```sql
-- 没有 OR REPLACE 时: 部署脚本很脆弱
CREATE VIEW v_active_users AS SELECT * FROM users WHERE status = 'active';
-- 第二次执行: ERROR: relation "v_active_users" already exists

-- 防御性写法: 先 DROP 再 CREATE
DROP VIEW IF EXISTS v_active_users;
CREATE VIEW v_active_users AS SELECT * FROM users WHERE status = 'active';
-- 问题: DROP + CREATE 不是原子操作，中间窗口期视图不可用

-- 最佳写法
CREATE OR REPLACE VIEW v_active_users AS SELECT * FROM users WHERE status = 'active';
-- 幂等、原子、安全
```

2. 函数/存储过程的迭代开发

```sql
-- PostgreSQL: 函数开发中频繁修改
CREATE OR REPLACE FUNCTION calculate_tax(amount NUMERIC)
RETURNS NUMERIC AS $$
BEGIN
    RETURN amount * 0.08;  -- 随时修改逻辑，不用先 DROP
END;
$$ LANGUAGE plpgsql;
```

3. 简化 Migration 工具

ORM 的 migration 工具（Flyway、Liquibase）需要生成幂等 SQL。有 `OR REPLACE` 时，视图和函数的 migration 变得简单——直接用完整定义覆盖。

## 语法对比

### PostgreSQL

```sql
-- VIEW: 支持 OR REPLACE
CREATE OR REPLACE VIEW v_employees AS
SELECT id, name, dept FROM employees WHERE active = true;

-- FUNCTION: 支持 OR REPLACE
CREATE OR REPLACE FUNCTION add_numbers(a INT, b INT) RETURNS INT AS $$
BEGIN RETURN a + b; END;
$$ LANGUAGE plpgsql;

-- TABLE: 不支持 OR REPLACE！
-- CREATE OR REPLACE TABLE t (...);  -- 语法错误
-- 替代方案:
DROP TABLE IF EXISTS t;
CREATE TABLE t (id INT, name TEXT);
```

### Oracle

```sql
-- VIEW
CREATE OR REPLACE VIEW v_employees AS
SELECT id, name, dept FROM employees WHERE active = 1;

-- FUNCTION
CREATE OR REPLACE FUNCTION add_numbers(a NUMBER, b NUMBER) RETURN NUMBER IS
BEGIN
    RETURN a + b;
END;
/

-- PROCEDURE
CREATE OR REPLACE PROCEDURE log_action(msg VARCHAR2) IS
BEGIN
    INSERT INTO audit_log (message, ts) VALUES (msg, SYSDATE);
END;
/
```

### SQL Server（CREATE OR ALTER）

```sql
-- SQL Server 2016 SP1+ 引入 CREATE OR ALTER
-- 注意: 语法是 ALTER 不是 REPLACE，语义是原地修改

-- VIEW
CREATE OR ALTER VIEW v_employees AS
SELECT id, name, dept FROM employees WHERE active = 1;

-- FUNCTION
CREATE OR ALTER FUNCTION dbo.add_numbers(@a INT, @b INT) RETURNS INT
AS BEGIN RETURN @a + @b; END;

-- PROCEDURE
CREATE OR ALTER PROCEDURE dbo.log_action @msg NVARCHAR(200)
AS BEGIN
    INSERT INTO audit_log (message, ts) VALUES (@msg, GETDATE());
END;
```

### Snowflake（最广泛的支持）

```sql
-- VIEW
CREATE OR REPLACE VIEW v_employees AS
SELECT id, name, dept FROM employees WHERE active = TRUE;

-- TABLE: Snowflake 独特地支持 OR REPLACE TABLE
CREATE OR REPLACE TABLE metrics (
    metric_date DATE,
    value FLOAT,
    source STRING
);
-- 等效于 DROP TABLE IF EXISTS + CREATE TABLE
-- 注意: 旧表数据会丢失！但 Time Travel 可以恢复

-- FUNCTION
CREATE OR REPLACE FUNCTION add_numbers(a FLOAT, b FLOAT)
RETURNS FLOAT
AS 'a + b';

-- STAGE
CREATE OR REPLACE STAGE my_stage URL = 's3://bucket/path/';
```

### DuckDB

```sql
-- VIEW
CREATE OR REPLACE VIEW v_employees AS
SELECT id, name, dept FROM employees WHERE active;

-- TABLE
CREATE OR REPLACE TABLE metrics (metric_date DATE, value FLOAT);

-- MACRO（DuckDB 特色）
CREATE OR REPLACE MACRO add(a, b) AS a + b;
```

### MySQL（仅 VIEW）

```sql
-- VIEW: 支持
CREATE OR REPLACE VIEW v_employees AS
SELECT id, name, dept FROM employees WHERE active = 1;

-- FUNCTION: 不支持 OR REPLACE
-- 替代方案:
DROP FUNCTION IF EXISTS add_numbers;
CREATE FUNCTION add_numbers(a INT, b INT) RETURNS INT DETERMINISTIC
BEGIN RETURN a + b; END;

-- TABLE: 不支持 OR REPLACE
DROP TABLE IF EXISTS metrics;
CREATE TABLE metrics (metric_date DATE, value FLOAT);
```

## 对引擎开发者的实现建议

1. OR REPLACE 的语义选择

实现 `CREATE OR REPLACE` 时需要决定核心语义：

| 策略 | 描述 | 代表 |
|------|------|------|
| DROP + CREATE | 先删除旧对象，再创建新的 | Snowflake (TABLE) |
| ALTER in-place | 原地修改对象定义 | SQL Server (CREATE OR ALTER) |
| Replace metadata | 替换元数据但保留关联 | PostgreSQL (VIEW) |

建议根据对象类型选择不同策略：
- **VIEW/FUNCTION**: Replace metadata（保留权限、依赖关系）
- **TABLE**: 谨慎！DROP + CREATE 会丢数据。建议像 Snowflake 一样仅替换结构
- **PROCEDURE/TRIGGER**: Replace metadata

2. 权限保留

`DROP + CREATE` 的最大问题是权限丢失：

```sql
-- 场景: DBA 给 analyst 角色授了查看权限
GRANT SELECT ON v_report TO analyst;

-- 开发者更新视图
DROP VIEW v_report;          -- 权限丢失！
CREATE VIEW v_report AS ...;
-- analyst 角色的 SELECT 权限没了

-- OR REPLACE 的优势: 保留权限
CREATE OR REPLACE VIEW v_report AS ...;
-- analyst 角色的权限仍然存在
```

引擎实现时，`OR REPLACE` 应该保留已有的 GRANT，这是比 `DROP + CREATE` 更优的核心原因。

3. 依赖关系处理

当被 REPLACE 的对象有下游依赖时：

```sql
-- v_base 被 v_derived 依赖
CREATE OR REPLACE VIEW v_base AS SELECT id, name FROM users;
-- 如果新定义删除了 name 列，v_derived 怎么办？
```

策略选择：
- **PostgreSQL**: 如果新定义不兼容（删列、改类型），报错拒绝替换
- **Snowflake**: 允许替换，下游依赖变为失效状态，查询时报错
- **Oracle**: 允许替换，下游变为 INVALID，首次访问时尝试重新编译

建议: 采用 PostgreSQL 的保守策略——不兼容时报错，要求用户显式 `DROP CASCADE`。

4. 事务性

`CREATE OR REPLACE` 应该是原子操作。实现方式：

1. 在同一事务中：获取元数据锁 → 删除旧定义 → 创建新定义 → 提交
2. 如果中间步骤失败，整个操作回滚，旧对象不受影响

5. DDL 日志

```
-- 需要在 DDL 审计日志中区分操作类型
CREATE OR REPLACE VIEW v → 记录为 REPLACE（不是 CREATE 也不是 DROP + CREATE）
```

## CREATE IF NOT EXISTS 的设计对比

```sql
-- IF NOT EXISTS: 仅在不存在时创建
CREATE TABLE IF NOT EXISTS t (id INT, name TEXT);
-- 如果 t 已存在但结构不同，不会报错也不会修改——静默跳过
-- 这是一个常见的误解来源

-- OR REPLACE: 确保定义是最新的
CREATE OR REPLACE TABLE t (id INT, name TEXT);
-- 如果 t 已存在，替换为新定义
```

两者适用场景不同：
- `IF NOT EXISTS`: 初始化脚本（只关心对象存在即可）
- `OR REPLACE`: 部署脚本（确保定义与代码一致）

## 参考资料

- PostgreSQL: [CREATE VIEW](https://www.postgresql.org/docs/current/sql-createview.html)
- SQL Server: [CREATE OR ALTER](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-or-alter)
- Snowflake: [CREATE OR REPLACE TABLE](https://docs.snowflake.com/en/sql-reference/sql/create-table)
- Oracle: [CREATE OR REPLACE](https://docs.oracle.com/en/database/oracle/oracle-database/19/lnpls/CREATE-PROCEDURE-statement.html)
