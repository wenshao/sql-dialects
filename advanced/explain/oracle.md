# Oracle: 执行计划

> 参考资料:
> - [Oracle SQL Language Reference - EXPLAIN PLAN](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/EXPLAIN-PLAN.html)
> - [Oracle Documentation - DBMS_XPLAN](https://docs.oracle.com/en/database/oracle/oracle-database/23/arpls/DBMS_XPLAN.html)

## EXPLAIN PLAN + DBMS_XPLAN

生成执行计划（存入 PLAN_TABLE，不执行查询）
```sql
EXPLAIN PLAN FOR
SELECT * FROM users WHERE username = 'alice';
```

查看执行计划
```sql
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

显示格式选项
```sql
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC'));    -- 最简
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'TYPICAL'));  -- 默认
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'ALL'));      -- 全部

-- 设计分析:
--   Oracle 将执行计划存入 PLAN_TABLE（系统表），通过 DBMS_XPLAN 包读取。
--   这种"存入表→查询表"的两步模型是 Oracle 独有的。
--
-- 横向对比:
--   Oracle:     EXPLAIN PLAN → DBMS_XPLAN.DISPLAY（两步）
--   PostgreSQL: EXPLAIN / EXPLAIN ANALYZE（直接输出）
--   MySQL:      EXPLAIN / EXPLAIN ANALYZE (8.0.18+)（直接输出）
--   SQL Server: SET SHOWPLAN_XML ON 或 SSMS 图形计划
```

## DBMS_XPLAN.DISPLAY_CURSOR（已执行的实际执行计划）

先启用运行时统计收集
```sql
SELECT /*+ GATHER_PLAN_STATISTICS */ *
FROM users WHERE age > 25;
```

显示实际执行计划（包含实际行数 vs 估计行数）
```sql
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(NULL, NULL, 'ALLSTATS LAST'));
```

通过 SQL_ID 查看特定查询的计划
```sql
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR('sql_id_here', NULL, 'ALLSTATS'));
```

设计分析:
  DISPLAY_CURSOR 显示实际执行统计（Actual Rows vs Estimated Rows），
  这是诊断优化器估算偏差的核心工具。
  估算偏差 → 选择错误的执行计划 → 性能问题

  GATHER_PLAN_STATISTICS 提示启用行级统计（有约 5% 的性能开销）。
  类似 PostgreSQL 的 EXPLAIN (ANALYZE, BUFFERS)。

## 执行计划关键操作

表访问:
  TABLE ACCESS FULL:            全表扫描
  TABLE ACCESS BY INDEX ROWID:  通过索引回表
  TABLE ACCESS BY INDEX ROWID BATCHED: 批量回表（12c+）

索引操作:
  INDEX UNIQUE SCAN:     唯一索引精确查找
  INDEX RANGE SCAN:      索引范围扫描
  INDEX FULL SCAN:       索引全扫描（有序）
  INDEX FAST FULL SCAN:  索引快速全扫描（无序，多块读）
  INDEX SKIP SCAN:       跳过索引前导列（9i+，Oracle 独有优化）

连接操作:
  NESTED LOOPS:     嵌套循环（小表驱动大表）
  HASH JOIN:        哈希连接（大表等值连接）
  SORT MERGE JOIN:  排序合并（已排序或不等值连接）

分区:
  PARTITION RANGE ALL/SINGLE: 分区裁剪信息

## 优化器 Hint（Oracle 最丰富的 Hint 系统）

访问路径 Hint
```sql
SELECT /*+ FULL(u) */ * FROM users u WHERE id = 1;
SELECT /*+ INDEX(u idx_users_age) */ * FROM users u WHERE age > 25;
```

连接方式 Hint
```sql
SELECT /*+ USE_HASH(u o) */ u.username, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;

SELECT /*+ USE_NL(u o) */ u.username, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;
```

连接顺序 Hint
```sql
SELECT /*+ LEADING(o u) */ u.username, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;
```

并行执行 Hint
```sql
SELECT /*+ PARALLEL(u, 4) */ * FROM users u;
```

设计分析:
  Oracle 有 100+ 种 Hint，是最丰富的 Hint 系统。
  Hint 放在 /*+ ... */ 注释中，不影响语法解析。

横向对比:
  Oracle:     /*+ HINT */ 100+ 种，覆盖访问路径/连接/并行/物化/缓存
  PostgreSQL: 无 Hint（通过 SET 参数和 pg_hint_plan 扩展实现）
  MySQL:      /*+ */ 少量 Hint（HASH_JOIN, NO_INDEX 等，8.0+）
  SQL Server: OPTION (HASH JOIN) / WITH (INDEX=...)（较少但有效）

对引擎开发者的启示:
  Hint 是优化器的安全网: 当 CBO 做出错误决策时，专家用户可以介入。
  但过度依赖 Hint 说明优化器质量不够。
  推荐: 先做好 CBO，Hint 作为最后手段提供。

## SQL Monitor（Enterprise Edition，实时监控）

自动监控: 运行 > 5 秒或并行执行的查询
```sql
SELECT DBMS_SQLTUNE.REPORT_SQL_MONITOR(
    sql_id => 'sql_id_here', type => 'TEXT'
) FROM DUAL;
```

查看正在执行的 SQL
```sql
SELECT sql_id, status, elapsed_time/1000000 AS seconds,
       buffer_gets, disk_reads
FROM v$sql_monitor WHERE status = 'EXECUTING';
```

## V$SQL: 共享池中的执行信息

```sql
SELECT sql_id, plan_hash_value, executions,
       elapsed_time/1000000 AS total_sec,
       buffer_gets, disk_reads, rows_processed
FROM v$sql
WHERE sql_text LIKE '%users%'
ORDER BY elapsed_time DESC;
```

AWR 历史执行计划
```sql
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_AWR('sql_id'));
```

## 10046 跟踪（最详细的诊断手段）

```sql
ALTER SESSION SET EVENTS '10046 trace name context forever, level 12';
SELECT * FROM users WHERE age > 25;
ALTER SESSION SET EVENTS '10046 trace name context off';
```

生成跟踪文件，用 tkprof 分析

## SQL Tuning Advisor（Enterprise Edition）

```sql
DECLARE
    l_task_id VARCHAR2(100);
BEGIN
    l_task_id := DBMS_SQLTUNE.CREATE_TUNING_TASK(
        sql_id => 'sql_id_here',
        scope => DBMS_SQLTUNE.SCOPE_COMPREHENSIVE,
        time_limit => 300
    );
    DBMS_SQLTUNE.EXECUTE_TUNING_TASK(l_task_id);
END;
/
SELECT DBMS_SQLTUNE.REPORT_TUNING_TASK('task_name') FROM DUAL;
```

## 对引擎开发者的总结

1. Oracle 的两步 EXPLAIN（PLAN_TABLE + DBMS_XPLAN）比直接输出更灵活但更复杂。
2. DISPLAY_CURSOR + ALLSTATS 是诊断性能问题的核心工具（实际 vs 估算行数）。
3. 100+ Hint 系统是 Oracle 的特色，但好的 CBO 应该减少 Hint 的必要性。
4. INDEX SKIP SCAN 是 Oracle 独有的索引优化（跳过前导列）。
5. SQL Monitor 提供实时执行监控，对长查询诊断非常有价值。
### 对引擎最小可行方案: EXPLAIN + 实际行数 + 基本 Hint（INDEX, HASH_JOIN）。
