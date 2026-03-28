# DB2: 执行计划与查询分析

> 参考资料:
> - [IBM Documentation - EXPLAIN statement](https://www.ibm.com/docs/en/db2/11.5?topic=statements-explain)
> - [IBM Documentation - db2expln](https://www.ibm.com/docs/en/db2/11.5?topic=commands-db2expln)
> - [IBM Documentation - Explain tables](https://www.ibm.com/docs/en/db2/11.5?topic=tools-explain-tables)
> - ============================================================
> - EXPLAIN 基本用法
> - ============================================================
> - 将执行计划存入 EXPLAIN 表

```sql
EXPLAIN PLAN FOR
SELECT * FROM users WHERE username = 'alice';
```

## 使用 SET CURRENT EXPLAIN MODE

```sql
SET CURRENT EXPLAIN MODE = EXPLAIN;
SELECT * FROM users WHERE age > 25;
SET CURRENT EXPLAIN MODE = NO;
```

## 查看执行计划（从 EXPLAIN 表）


创建 EXPLAIN 表（如果不存在）
运行脚本：CALL SYSPROC.SYSINSTALLOBJECTS('EXPLAIN', 'C', NULL, CURRENT SCHEMA)
查询 EXPLAIN 表

```sql
SELECT operator_type, object_name, total_cost, io_cost, cpu_cost,
       stream_count AS estimated_rows
FROM explain_operator o
JOIN explain_stream s ON o.operator_id = s.target_id
    AND o.explain_time = s.explain_time
ORDER BY o.operator_id;
```

## db2expln 命令行工具


在操作系统命令行（不是 SQL）：
db2expln -d mydb -q "SELECT * FROM users WHERE age > 25" -g -t
选项：
d  数据库名
q  SQL 语句
g  图形化显示
t  终端输出

## Visual Explain（Data Studio）


IBM Data Studio 提供图形化执行计划查看器
1. 右键点击 SQL 语句
2. 选择 "Visual Explain"
3. 查看图形化操作树

## db2advis（索引建议工具）


在操作系统命令行：
db2advis -d mydb -s "SELECT * FROM users WHERE age > 25"
分析工作负载文件：
db2advis -d mydb -i workload.sql

## 执行计划关键操作


TBSCAN          表扫描
IXSCAN          索引扫描
FETCH           通过 RID 获取数据行
RIDSCN          RID 扫描
SORT            排序
TEMP            临时表
NLJOIN          嵌套循环连接
HSJOIN          哈希连接
MSJOIN          合并扫描连接
GRPBY           分组
UNION           UNION
INSERT / UPDATE / DELETE  DML 操作

## MON_GET 监控函数（10.5+）


## 查看当前活动的 SQL 语句

```sql
SELECT application_handle, elapsed_time_sec, rows_read, rows_returned,
       stmt_text
FROM TABLE(MON_GET_ACTIVITY(NULL, -2))
ORDER BY elapsed_time_sec DESC;
```

## 查看包缓存中的 SQL（类似 SQL Server 的计划缓存）

```sql
SELECT num_executions, total_act_time, rows_read, rows_returned,
       stmt_text
FROM TABLE(MON_GET_PKG_CACHE_STMT(NULL, NULL, NULL, -2))
ORDER BY total_act_time DESC
FETCH FIRST 10 ROWS ONLY;
```

## EXPLAIN SNAPSHOT


## 保存执行计划快照

```sql
EXPLAIN PLAN WITH SNAPSHOT FOR
SELECT * FROM users u JOIN orders o ON u.id = o.user_id WHERE u.age > 25;
```

## 统计信息管理


## 收集统计信息

```sql
RUNSTATS ON TABLE schema.users WITH DISTRIBUTION AND DETAILED INDEXES ALL;
```

## 查看表统计信息

```sql
SELECT tabname, card AS row_count, npages, fpages
FROM syscat.tables WHERE tabname = 'USERS';
```

## 查看索引统计信息

```sql
SELECT indname, colnames, nleaf, nlevels, fullkeycard
FROM syscat.indexes WHERE tabname = 'USERS';
```

注意：DB2 使用 EXPLAIN 表存储执行计划
注意：db2expln 命令行工具可以直接显示执行计划
注意：Visual Explain（Data Studio）提供图形化界面
注意：MON_GET 系列函数（10.5+）提供实时监控
注意：RUNSTATS 收集统计信息是优化器正确决策的基础
注意：db2advis 可以自动建议索引
