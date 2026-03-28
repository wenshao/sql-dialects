# 时态表 / 系统版本化

数据库原生记录"过去某个时间点数据是什么样"——SQL:2011 标准引入的时间旅行能力，让审计和历史查询从应用层回归数据库层。

## 支持矩阵

| 引擎 | 支持类型 | 版本 | 备注 |
|------|---------|------|------|
| SQL Server | SYSTEM_TIME | 2016+ | **最完善的标准实现** |
| MariaDB | SYSTEM_TIME | 10.3+ | WITH SYSTEM VERSIONING 语法 |
| Db2 | SYSTEM_TIME + APPLICATION_TIME | 10.1+ | Time Travel Query |
| Oracle | SYSTEM_TIME（变体） | 11g+ | Flashback Data Archive，非标准语法 |
| CockroachDB | SYSTEM_TIME（变体） | 20.2+ | `AS OF SYSTEM TIME` 基于 MVCC |
| PostgreSQL | 不支持 | - | 需触发器或 temporal_tables 扩展 |
| MySQL | 不支持 | - | 无原生支持 |
| ClickHouse | 不支持 | - | 追加模式天然保留历史（ReplacingMergeTree） |
| Snowflake | 部分支持 | GA | Time Travel（基于保留期，非标准语法） |
| BigQuery | 部分支持 | GA | FOR SYSTEM_TIME AS OF（7 天快照） |
| DuckDB | 不支持 | - | 无原生支持 |

## 核心概念

### SQL:2011 定义了两种时态

**SYSTEM_TIME（系统时间 / 事务时间）**
- 由数据库自动管理的时间维度
- 记录行的有效期: `[system_time_start, system_time_end)`
- INSERT 时自动设置 start = 当前事务时间，end = 无穷大
- UPDATE 时旧行的 end 设为当前时间，新行的 start 设为当前时间
- DELETE 时行的 end 设为当前时间（逻辑删除）
- 用户不能手动修改 system_time 列

**APPLICATION_TIME（应用时间 / 有效时间）**
- 由应用程序管理的业务时间维度
- 例如: 合同有效期、员工在职期、价格生效期
- 用户可以自由设置和修改
- 支持 `UPDATE FOR PORTION OF` 语法

```
SYSTEM_TIME: "这行数据在数据库中什么时候有效"
APPLICATION_TIME: "这个业务事实在现实世界中什么时候有效"
```

## 语法对比

### SQL Server 2016+（最接近标准）

```sql
-- 创建时态表
CREATE TABLE employees (
    emp_id INT PRIMARY KEY,
    name NVARCHAR(100),
    dept NVARCHAR(50),
    salary DECIMAL(10,2),
    -- 系统时间列（SQL Server 使用 datetime2）
    valid_from DATETIME2 GENERATED ALWAYS AS ROW START NOT NULL,
    valid_to   DATETIME2 GENERATED ALWAYS AS ROW END NOT NULL,
    -- 声明时态周期
    PERIOD FOR SYSTEM_TIME (valid_from, valid_to)
)
WITH (SYSTEM_VERSIONING = ON (
    HISTORY_TABLE = dbo.employees_history  -- 历史表
));

-- 正常 DML（系统自动维护时间列）
INSERT INTO employees (emp_id, name, dept, salary)
VALUES (1, '张三', '工程部', 15000);

UPDATE employees SET salary = 18000 WHERE emp_id = 1;
-- 自动: 旧行移入 employees_history，valid_to 设为当前时间
-- 自动: 新行在 employees 中，valid_from 设为当前时间

-- 时间旅行查询
-- 查询某个时间点的数据
SELECT * FROM employees
FOR SYSTEM_TIME AS OF '2024-06-15 10:00:00';

-- 查询某个时间范围内的所有版本
SELECT * FROM employees
FOR SYSTEM_TIME BETWEEN '2024-01-01' AND '2024-12-31';

-- 查询所有历史版本
SELECT * FROM employees
FOR SYSTEM_TIME ALL;

-- 查询与时间范围重叠的版本
SELECT * FROM employees
FOR SYSTEM_TIME FROM '2024-06-01' TO '2024-07-01';

-- 包含端点的范围查询
SELECT * FROM employees
FOR SYSTEM_TIME CONTAINED IN ('2024-06-01', '2024-07-01');
```

### MariaDB 10.3+

```sql
-- 创建系统版本化表
CREATE TABLE employees (
    emp_id INT PRIMARY KEY,
    name VARCHAR(100),
    dept VARCHAR(50),
    salary DECIMAL(10,2)
) WITH SYSTEM VERSIONING;
-- MariaDB 自动添加隐式时间列（不需要显式声明）

-- 时间旅行查询
SELECT * FROM employees
FOR SYSTEM_TIME AS OF TIMESTAMP '2024-06-15 10:00:00';

SELECT * FROM employees
FOR SYSTEM_TIME BETWEEN (TIMESTAMP '2024-01-01') AND (TIMESTAMP '2024-12-31');

SELECT * FROM employees
FOR SYSTEM_TIME ALL;

-- MariaDB 特色: 可以按版本数分区（控制历史表大小）
CREATE TABLE employees (
    emp_id INT PRIMARY KEY,
    name VARCHAR(100),
    salary DECIMAL(10,2)
) WITH SYSTEM VERSIONING
PARTITION BY SYSTEM_TIME INTERVAL 1 MONTH (
    PARTITION p_history HISTORY,
    PARTITION p_current CURRENT
);
```

### Oracle Flashback（非标准语法）

```sql
-- Oracle 使用 Flashback 技术实现类似功能
-- 基于 UNDO 的短期时间旅行
SELECT * FROM employees
AS OF TIMESTAMP TO_TIMESTAMP('2024-06-15 10:00:00', 'YYYY-MM-DD HH24:MI:SS');

-- Flashback 版本查询
SELECT emp_id, name, salary,
       VERSIONS_STARTTIME, VERSIONS_ENDTIME, VERSIONS_OPERATION
FROM employees
VERSIONS BETWEEN TIMESTAMP
    TO_TIMESTAMP('2024-06-01', 'YYYY-MM-DD') AND
    TO_TIMESTAMP('2024-07-01', 'YYYY-MM-DD');

-- Flashback Data Archive（长期历史）
-- 需要先创建 Flashback Archive
CREATE FLASHBACK ARCHIVE long_term_archive
    TABLESPACE archive_ts RETENTION 10 YEAR;

ALTER TABLE employees FLASHBACK ARCHIVE long_term_archive;
```

### Db2（双时态支持）

```sql
-- Db2 同时支持 SYSTEM_TIME 和 APPLICATION_TIME
CREATE TABLE insurance_policies (
    policy_id INT NOT NULL,
    holder_name VARCHAR(100),
    premium DECIMAL(10,2),
    -- 系统时间
    sys_start TIMESTAMP(12) GENERATED ALWAYS AS ROW BEGIN NOT NULL,
    sys_end   TIMESTAMP(12) GENERATED ALWAYS AS ROW END NOT NULL,
    -- 应用时间
    bus_start DATE NOT NULL,
    bus_end   DATE NOT NULL,
    PERIOD SYSTEM_TIME (sys_start, sys_end),
    PERIOD BUSINESS_TIME (bus_start, bus_end)
);

-- 系统时间查询
SELECT * FROM insurance_policies
FOR SYSTEM_TIME AS OF '2024-06-15';

-- 应用时间查询
SELECT * FROM insurance_policies
FOR BUSINESS_TIME AS OF '2024-06-15';

-- 双时态查询（同时指定两个时间维度）
SELECT * FROM insurance_policies
FOR SYSTEM_TIME AS OF '2024-06-15'
FOR BUSINESS_TIME AS OF '2024-06-15';
```

### Snowflake Time Travel

```sql
-- Snowflake 的 Time Travel 基于保留期（默认 1 天，最长 90 天）
-- 查询历史数据
SELECT * FROM employees
AT (TIMESTAMP => '2024-06-15 10:00:00'::TIMESTAMP_LTZ);

SELECT * FROM employees
AT (OFFSET => -3600);  -- 1 小时前

SELECT * FROM employees
BEFORE (STATEMENT => 'query_id_here');  -- 某条语句执行前

-- 恢复误删数据
CREATE TABLE employees_restored CLONE employees
AT (TIMESTAMP => '2024-06-15 10:00:00'::TIMESTAMP_LTZ);

-- Snowflake Time Travel 不是标准时态表——它基于存储快照，有保留期限制
```

### CockroachDB

```sql
-- CockroachDB 基于 MVCC 的 AS OF SYSTEM TIME
SELECT * FROM employees
AS OF SYSTEM TIME '2024-06-15 10:00:00';

-- 支持相对时间
SELECT * FROM employees
AS OF SYSTEM TIME '-5m';  -- 5 分钟前

-- 注意: 受 GC TTL 限制（默认 25 小时）
```

## 经典用例

### 用例 1: 审计追踪

```sql
-- SQL Server: 谁在什么时候修改了什么
SELECT emp_id, name, salary,
       valid_from AS changed_at,
       valid_to AS replaced_at
FROM employees FOR SYSTEM_TIME ALL
WHERE emp_id = 1001
ORDER BY valid_from;
-- 结果:
-- emp_id | name | salary | changed_at          | replaced_at
-- 1001   | 张三 | 10000  | 2023-01-15 09:00:00 | 2023-07-01 10:30:00
-- 1001   | 张三 | 12000  | 2023-07-01 10:30:00 | 2024-01-01 08:00:00
-- 1001   | 张三 | 15000  | 2024-01-01 08:00:00 | 9999-12-31 23:59:59 (当前)
```

### 用例 2: 合规报表（月末快照）

```sql
-- 每月月末的员工薪资快照
SELECT emp_id, name, dept, salary
FROM employees
FOR SYSTEM_TIME AS OF '2024-06-30 23:59:59';
```

### 用例 3: 缓慢变化维（SCD Type 2）

```sql
-- 时态表天然实现 SCD Type 2
-- 维度表:
CREATE TABLE dim_customer (
    customer_id INT PRIMARY KEY,
    name NVARCHAR(100),
    segment NVARCHAR(50),
    valid_from DATETIME2 GENERATED ALWAYS AS ROW START,
    valid_to   DATETIME2 GENERATED ALWAYS AS ROW END,
    PERIOD FOR SYSTEM_TIME (valid_from, valid_to)
) WITH (SYSTEM_VERSIONING = ON);

-- 事实表关联维度的历史版本
SELECT f.order_id, f.amount,
       d.name, d.segment
FROM fact_orders f
JOIN dim_customer FOR SYSTEM_TIME AS OF f.order_date d
    ON f.customer_id = d.customer_id;
```

### 用例 4: 数据恢复

```sql
-- 误操作恢复（SQL Server）
-- 1. 找到误操作之前的数据
SELECT * FROM employees
FOR SYSTEM_TIME AS OF '2024-06-15 09:59:00'
WHERE emp_id IN (SELECT emp_id FROM employees_affected);

-- 2. 恢复数据
INSERT INTO employees (emp_id, name, dept, salary)
SELECT emp_id, name, dept, salary
FROM employees FOR SYSTEM_TIME AS OF '2024-06-15 09:59:00'
WHERE emp_id IN (1001, 1002, 1003);
```

## 对引擎开发者的实现分析

1. 存储策略: 影子表 vs 内联版本列

**影子表方案（SQL Server, MariaDB）**

```
employees 表（当前数据）:
| emp_id | name | salary | valid_from | valid_to   |
| 1      | 张三 | 15000  | 2024-01-01 | 9999-12-31 |

employees_history 表（历史数据）:
| emp_id | name | salary | valid_from | valid_to   |
| 1      | 张三 | 10000  | 2023-01-15 | 2023-07-01 |
| 1      | 张三 | 12000  | 2023-07-01 | 2024-01-01 |
```

优点: 当前数据查询不受历史数据影响，性能无退化
缺点: 历史查询需要 UNION 两表，DDL 变更需要同步两表

**内联版本方案（CockroachDB 基于 MVCC）**

```
所有版本存储在同一棵 LSM/B+ 树中，通过版本链链接。
当前查询只读最新版本，历史查询通过版本链回溯。
```

优点: 实现简单，利用已有 MVCC 机制
缺点: 大量历史版本会导致存储膨胀和 GC 压力

2. 时间戳精度

```
SQL Server:  datetime2(7)  — 100 纳秒精度
MariaDB:     timestamp(6)  — 微秒精度
Db2:         timestamp(12) — 皮秒精度（最高）
```

建议: 至少使用微秒精度。在高并发场景下，毫秒精度可能导致同一时间戳内多行版本冲突。

3. UPDATE 的实现

```
UPDATE employees SET salary = 18000 WHERE emp_id = 1;

引擎内部执行:
1. 读取当前行: (1, '张三', 15000, '2024-01-01', '9999-12-31')
2. 将旧行的 valid_to 设为 CURRENT_TIMESTAMP → 移入历史表
3. 插入新行: (1, '张三', 18000, CURRENT_TIMESTAMP, '9999-12-31')

这必须在同一个事务中原子完成。
```

4. DELETE 的实现

```
DELETE FROM employees WHERE emp_id = 1;

引擎内部执行:
1. 读取当前行
2. 将该行的 valid_to 设为 CURRENT_TIMESTAMP → 移入历史表
3. 从当前表中删除该行

历史表中仍保留完整历史。
```

5. FOR SYSTEM_TIME 查询重写

```sql
-- 用户写:
SELECT * FROM employees FOR SYSTEM_TIME AS OF @t;

-- 引擎改写为:
SELECT * FROM employees WHERE valid_from <= @t AND valid_to > @t
UNION ALL
SELECT * FROM employees_history WHERE valid_from <= @t AND valid_to > @t;

-- 优化: 在 valid_from, valid_to 上建索引
```

6. 历史数据清理

历史数据会持续增长，引擎需要提供清理机制：

```sql
-- SQL Server: 设置保留策略
ALTER TABLE employees SET (SYSTEM_VERSIONING = ON (
    HISTORY_TABLE = dbo.employees_history,
    HISTORY_RETENTION_PERIOD = 1 YEAR  -- 保留 1 年
));

-- MariaDB: 分区历史表，定期删除旧分区
ALTER TABLE employees DROP PARTITION p_2022;
```

## PostgreSQL 模拟方案

```sql
-- 使用触发器模拟时态表
CREATE TABLE employees (
    emp_id INT PRIMARY KEY,
    name TEXT,
    dept TEXT,
    salary NUMERIC
);

CREATE TABLE employees_history (
    emp_id INT,
    name TEXT,
    dept TEXT,
    salary NUMERIC,
    valid_from TIMESTAMPTZ NOT NULL,
    valid_to TIMESTAMPTZ NOT NULL
);

CREATE OR REPLACE FUNCTION employees_versioning()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        INSERT INTO employees_history
        VALUES (OLD.emp_id, OLD.name, OLD.dept, OLD.salary,
                OLD.valid_from, now());
        NEW.valid_from = now();
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO employees_history
        VALUES (OLD.emp_id, OLD.name, OLD.dept, OLD.salary,
                OLD.valid_from, now());
        RETURN OLD;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- 注意: 这是简化版本，生产环境建议使用 temporal_tables 扩展
```

## 设计争议

### 标准太复杂？

SQL:2011 的时态特性定义了大量语法和语义规则（标准文档超过 100 页）。完整实现需要处理的边界情况极多：
- 并发事务的时间戳一致性
- DDL 变更时历史表的 schema 同步
- 外键约束在历史版本上的行为
- TRUNCATE 是否保留历史

这是多数引擎实现不完整或不实现的根本原因。

### Event Sourcing 是否更好？

Event Sourcing 模式（存储事件流而非状态快照）在某些场景下是时态表的替代方案。区别在于：
- 时态表: 存储状态快照，查询简单，存储冗余
- Event Sourcing: 存储变更事件，查询需重放，存储紧凑

两者适用场景不同，并非替代关系。

## 参考资料

- ISO/IEC 9075-2:2011 Section 11.27 (Temporal)
- SQL Server: [Temporal Tables](https://learn.microsoft.com/en-us/sql/relational-databases/tables/temporal-tables)
- MariaDB: [System-Versioned Tables](https://mariadb.com/kb/en/system-versioned-tables/)
- Oracle: [Flashback Technology](https://docs.oracle.com/en/database/oracle/oracle-database/19/adfns/flashback.html)
- Db2: [Temporal Tables](https://www.ibm.com/docs/en/db2/11.5?topic=tables-temporal)
