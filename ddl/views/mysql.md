# MySQL: 视图

> 参考资料:
> - [MySQL 8.0 Reference Manual - CREATE VIEW](https://dev.mysql.com/doc/refman/8.0/en/create-view.html)
> - [MySQL 8.0 Reference Manual - View Algorithms](https://dev.mysql.com/doc/refman/8.0/en/view-algorithms.html)
> - [MySQL 8.0 Reference Manual - Updatable Views](https://dev.mysql.com/doc/refman/8.0/en/view-updatability.html)
> - [MySQL 8.0 Reference Manual - WITH CHECK OPTION](https://dev.mysql.com/doc/refman/8.0/en/view-check-option.html)

## 基本语法

创建视图
```sql
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;
```

CREATE OR REPLACE（原子替换，不需要先 DROP）
```sql
CREATE OR REPLACE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;
```

指定算法、定义者和安全性
```sql
CREATE
    ALGORITHM = MERGE
    DEFINER = 'admin'@'localhost'
    SQL SECURITY DEFINER
VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;
```

可更新视图 + WITH CHECK OPTION
```sql
CREATE VIEW adult_users AS
SELECT id, username, email, age
FROM users
WHERE age >= 18
WITH CASCADED CHECK OPTION;    -- CASCADED（默认）或 LOCAL

-- 通过视图执行 DML
INSERT INTO adult_users (username, email, age) VALUES ('alice', 'alice@b.com', 25);
UPDATE adult_users SET email = 'new@b.com' WHERE id = 1;
DELETE FROM adult_users WHERE id = 1;
```

删除视图
```sql
DROP VIEW IF EXISTS active_users;
```

## 视图算法: MERGE vs TEMPTABLE（对 SQL 引擎开发者）

### MERGE 算法

原理: 将视图的 SELECT 与外层查询合并（view merging），生成单一查询
示例:
  视图: CREATE VIEW v AS SELECT * FROM users WHERE age >= 18;
  查询: SELECT * FROM v WHERE city = 'Beijing';
  合并后: SELECT * FROM users WHERE age >= 18 AND city = 'Beijing';

优点:
  a. 优化器可以看到完整查询，做全局优化（索引选择、JOIN 重排等）
  b. 没有中间结果集的物化开销
  c. 视图可以是可更新的（因为直接对基表操作）

限制（以下情况不能使用 MERGE）:
  - 视图包含 AGGREGATE 函数（SUM/COUNT/MAX 等）
  - 视图包含 DISTINCT、GROUP BY、HAVING
  - 视图包含 UNION / UNION ALL
  - 视图的 SELECT 列表中有子查询
  - 视图包含 LIMIT（与外层 LIMIT 合并语义不明确）

### TEMPTABLE 算法

原理: 先将视图的 SELECT 结果物化到内部临时表，再在临时表上执行外层查询

影响:
  a. 两次查询: 第一次物化视图结果，第二次在临时表上查询
  b. 临时表没有索引（除非优化器自动添加），大结果集的外层 WHERE 效率低
  c. 视图不可更新（无法将对临时表的修改映射回基表）
  d. 如果结果集包含 TEXT/BLOB 列，内存临时表自动退化为磁盘临时表

### UNDEFINED 算法（默认）

MySQL 自动选择 MERGE 或 TEMPTABLE:
  能 MERGE 则 MERGE，不能 MERGE 则退化为 TEMPTABLE
推荐: 不显式指定 ALGORITHM（除非有特定需求），让优化器决定

### 如何诊断视图算法

EXPLAIN 查看视图是否被合并:
```sql
  EXPLAIN SELECT * FROM v WHERE city = 'Beijing';
```

  如果 MERGE: 直接看到基表的访问计划
  如果 TEMPTABLE: 出现 <derived2> 这样的临时表引用

对引擎开发者的启示:
  视图合并（View Merging）是查询优化器的重要能力:
  - 大部分现代优化器默认进行视图合并（PostgreSQL、Oracle、SQL Server 都是）
  - 视图合并不仅适用于 CREATE VIEW，也适用于子查询/CTE 的展开
  - 关键挑战: 合并后的查询可能改变语义（如带 LIMIT 的视图合并需要特殊处理）
  - MySQL 的 ALGORITHM 是显式控制，其他引擎通常由优化器自动判断
  - Oracle 和 PG 通过 optimizer hints 或 GUC 参数控制（如 PG 的 from_collapse_limit）

## 可更新视图的限制（对 SQL 引擎开发者）

### MySQL 的可更新视图条件（所有条件都必须满足）:

  a. 视图与基表行之间存在一对一映射
  b. 不使用 AGGREGATE / DISTINCT / GROUP BY / HAVING / UNION
  c. 不使用子查询（在 SELECT 列表中）
  d. 不使用 ALGORITHM = TEMPTABLE
  e. JOIN 视图: 只能更新其中一个基表的列（不能同时更新多个表）
  f. 表达式列不可更新（如 CONCAT(a, b) AS full_name）

### WITH CHECK OPTION 的两种模式:

  CASCADED（默认）: 检查当前视图和所有底层视图的 WHERE 条件
  LOCAL: 只检查当前视图的 WHERE 条件，不检查底层视图

示例: 嵌套视图
```sql
CREATE VIEW base_view AS SELECT * FROM users WHERE age >= 18;
CREATE VIEW top_view AS SELECT * FROM base_view WHERE city = 'Beijing'
    WITH CASCADED CHECK OPTION;
```

通过 top_view 插入: CASCADED 会同时检查 age >= 18 AND city = 'Beijing'
如果用 LOCAL: 只检查 city = 'Beijing'，age < 18 的数据可以通过

### 对比 INSTEAD OF 触发器方案:

  SQL Server / PostgreSQL: 支持 INSTEAD OF 触发器
    可以让任何视图变得 "可更新"（用触发器自定义 INSERT/UPDATE/DELETE 的行为）
  MySQL: 不支持 INSTEAD OF 触发器
    如果视图不满足可更新条件，只能退化为 "先查视图获取 ID，再直接操作基表"

## 物化视图: MySQL 的缺失（对 SQL 引擎开发者）

MySQL 不支持原生物化视图，只能手动模拟:

### 方案一: 表 + EVENT 定时刷新

```sql
CREATE TABLE mv_order_summary (
    user_id      BIGINT PRIMARY KEY,
    order_count  INT,
    total_amount DECIMAL(18,2),
    refreshed_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

DELIMITER //
CREATE EVENT refresh_mv_order_summary
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    TRUNCATE TABLE mv_order_summary;
    INSERT INTO mv_order_summary (user_id, order_count, total_amount)
    SELECT user_id, COUNT(*), SUM(amount)
    FROM orders
    GROUP BY user_id;
END //
DELIMITER ;
```

### 方案二: 触发器增量维护（实时性好但复杂度高）

在 orders 表上创建 AFTER INSERT/UPDATE/DELETE 触发器，增量更新 mv_order_summary
> **问题**: 触发器逻辑复杂，增加 DML 延迟，且对 DELETE + UPDATE 的增量逻辑容易出错

### 各引擎物化视图对比:

PostgreSQL:
```sql
  CREATE MATERIALIZED VIEW mv AS SELECT ...;
```

  REFRESH MATERIALIZED VIEW mv;                            -- 全量刷新（持有 ACCESS EXCLUSIVE 锁）
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv;               -- 增量刷新（需要唯一索引，不阻塞读）
  限制: 没有自动刷新（需要 pg_cron 或应用层触发），CONCURRENTLY 刷新性能有限

Oracle（最成熟的实现）:
  ON COMMIT 刷新: 基表事务提交时自动刷新（同步，影响提交延迟）
  ON DEMAND 刷新: 手动调用 DBMS_MVIEW.REFRESH
  FAST 刷新: 通过物化视图日志（MV Log）增量刷新（只处理变更部分）
  COMPLETE 刷新: 全量重建
  Query Rewrite: 优化器自动将对基表的查询重写为对物化视图的查询（透明加速）

SQL Server:
  Indexed View（物化视图的变体）: 在视图上创建聚集索引，数据自动同步维护
  限制: 视图定义有严格约束（SCHEMABINDING、不能用 OUTER JOIN 等）
  优点: 自动维护，无需手动刷新

ClickHouse:
  物化视图 = INSERT 触发器: 新数据写入基表时自动转换并写入目标表
```sql
  CREATE MATERIALIZED VIEW mv TO target_table AS SELECT ...;
```

  不是 "查询快照"，而是实时 ETL 管道（只处理增量数据，不回填历史）

BigQuery:
  物化视图自动刷新（后台异步），支持自动 query rewrite
  适合聚合查询加速，但有语法限制（必须基于单表、有聚合函数等）

对引擎开发者的总结:
  1) 视图合并是优化器必备能力，比 TEMPTABLE 方案高效得多
  2) 可更新视图需要精确的一对一行映射判断逻辑
  3) 物化视图对 OLAP 引擎极其重要:
     - 最小实现: 手动刷新 + 全量重建（PG 级别）
     - 完整实现: 增量刷新 + 自动 query rewrite（Oracle 级别）
     - 创新方案: 实时增量管道（ClickHouse 级别）
  4) MySQL 至今（8.4）不支持物化视图，这是其 OLAP 能力的重要短板
