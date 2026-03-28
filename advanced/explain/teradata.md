# Teradata: 执行计划与查询分析

> 参考资料:
> - [Teradata Documentation - EXPLAIN](https://docs.teradata.com/r/Teradata-Database-SQL-Data-Manipulation-Language/June-2017/EXPLAIN)
> - [Teradata Documentation - Query Performance](https://docs.teradata.com/r/Teradata-VantageTM-SQL-Request-and-Transaction-Processing)


## EXPLAIN 基本用法


Teradata 的 EXPLAIN 返回自然语言描述
```sql
EXPLAIN SELECT * FROM users WHERE username = 'alice';
```


输出示例（自然语言描述）：
1) First, we lock a distinct MYDB."pseudo table" for read on a
RowHash to prevent global deadlock for MYDB.users.
2) Next, we do an all-AMPs RETRIEVE step from MYDB.users by
way of the primary index "MYDB.users.username = 'alice'"
with no residual conditions into Spool 1...
3) Finally, we send out an END TRANSACTION step to all AMPs
involved in processing the request.

## EXPLAIN 关键术语


置信度级别：
"(no confidence)"    无统计信息
"no confidence"      有统计信息但不可靠
"low confidence"     低置信度
"high confidence"    高置信度
"index join confidence" 索引连接置信度

访问方式：
"all-AMPs RETRIEVE"      所有 AMP 参与
"single-AMP RETRIEVE"    单 AMP（主索引查找）
"two-AMP RETRIEVE"       两个 AMP
"group-AMP RETRIEVE"     部分 AMP

## 连接分析


```sql
EXPLAIN
SELECT u.username, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id
WHERE o.amount > 100;
```


连接方式：
"merge join"          合并连接（排序后合并）
"hash join"           哈希连接
"nested join"         嵌套连接
"product join"        笛卡尔积连接（需要优化）
"exclusion merge join" 排除合并连接

## 查看估算时间和成本


EXPLAIN 输出中包含：
"The estimated time for this step is X.XX seconds."
"estimated rows = N"
"into Spool N"

## DBQL（Database Query Log）


查看查询日志
```sql
SELECT QueryID, UserName, QueryText,
       FirstStepTime, AMPCPUTime, TotalIOCount,
       SpoolUsage, NumResultRows
FROM DBC.QryLog
WHERE UserName = USER
ORDER BY StartTime DESC;
```


查看查询步骤
```sql
SELECT QueryID, StepNum, CPUTime, IOCount, SpoolUsage
FROM DBC.QryLogSteps
WHERE QueryID = 12345
ORDER BY StepNum;
```


## Visual EXPLAIN（Teradata Studio）


Teradata Studio 提供图形化 Visual EXPLAIN：
1. 右键点击 SQL
2. 选择 "Visual EXPLAIN"
3. 查看图形化计划

QryLogExplain 表存储了 EXPLAIN 文本
```sql
SELECT QueryID, ExplainText
FROM DBC.QryLogExplain
WHERE QueryID = 12345;
```


## DIAGNOSTIC 帮助信息


查看查询分步骤的详细 I/O 和 CPU
```sql
DIAGNOSTIC HELPSTATS ON FOR SESSION;

EXPLAIN
SELECT * FROM users WHERE age > 25;
```


关闭
```sql
DIAGNOSTIC HELPSTATS OFF FOR SESSION;
```


## 统计信息


收集统计信息
```sql
COLLECT STATISTICS ON users COLUMN (username);
COLLECT STATISTICS ON users COLUMN (age);
COLLECT STATISTICS ON users INDEX (username);
```


查看统计信息
```sql
HELP STATISTICS users;
```


删除统计信息
```sql
DROP STATISTICS ON users COLUMN (username);
```


## 重新分布分析


检查数据倾斜
```sql
SELECT AMP, COUNT(*) AS row_count
FROM users
GROUP BY AMP
ORDER BY row_count DESC;
```


注意：Teradata EXPLAIN 返回自然语言描述，非图表
注意：置信度级别反映统计信息的质量
注意："product join" 通常表示需要优化（缺少连接条件或统计信息）
注意：single-AMP 操作最高效，all-AMPs 操作涉及所有节点
注意：DBQL（DBC.QryLog）提供详细的历史查询性能数据
注意：COLLECT STATISTICS 是确保优化器正确决策的关键
