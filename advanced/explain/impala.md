# Apache Impala: 执行计划与查询分析

> 参考资料:
> - [Impala Documentation - EXPLAIN](https://impala.apache.org/docs/build/html/topics/impala_explain.html)
> - [Impala Documentation - EXPLAIN_LEVEL](https://impala.apache.org/docs/build/html/topics/impala_explain_level.html)
> - [Impala Documentation - PROFILE](https://impala.apache.org/docs/build/html/topics/impala_profile.html)


## EXPLAIN 基本用法


```sql
EXPLAIN SELECT * FROM users WHERE age > 25;
```


## EXPLAIN 详细级别


设置 EXPLAIN 级别
```sql
SET EXPLAIN_LEVEL=0;  -- 最简（只显示操作符）
SET EXPLAIN_LEVEL=1;  -- 标准（默认，含估算行数）
SET EXPLAIN_LEVEL=2;  -- 扩展（含更多细节）
SET EXPLAIN_LEVEL=3;  -- 详细（含全部信息）

EXPLAIN SELECT * FROM users WHERE age > 25;
```


## PROFILE（实际执行统计）


在 impala-shell 中执行查询后：
PROFILE;

PROFILE 输出包含：
- 每个操作符的实际执行时间
- 内存使用和峰值内存
- I/O 统计（HDFS 读取字节数/行数）
- 网络传输量
- 每个节点的执行统计

## SUMMARY（执行摘要）


在 impala-shell 中执行查询后：
SUMMARY;

输出表格包含：
Operator | #Hosts | Avg Time | Max Time | #Rows | Est. #Rows | Peak Mem

## 执行计划关键操作


SCAN HDFS           HDFS 文件扫描
SCAN KUDU           Kudu 表扫描
SCAN HBASE          HBase 表扫描
HASH JOIN           哈希连接
NESTED LOOP JOIN    嵌套循环连接
AGGREGATE           聚合
SORT                排序
TOP-N               Top N
EXCHANGE            数据交换（节点间传输）
HASH JOIN BUILD     构建哈希表
HASH JOIN PROBE     探测哈希表
ANALYTIC            分析函数
UNION               联合

数据分布：
BROADCAST           广播（小表）
HASH                按连接键 Hash 重分布
RANDOM              随机分布
UNPARTITIONED       汇集到单节点

## 查询性能视图


Impala Web UI（默认端口 25000）提供：
1. 查询列表（活跃和已完成）
2. 查询详情和执行计划
3. Profile 下载
4. 内存使用

## 统计信息


收集表统计信息
```sql
COMPUTE STATS users;
COMPUTE INCREMENTAL STATS users;  -- 增量统计（分区表）
```


查看统计信息
```sql
SHOW TABLE STATS users;
SHOW COLUMN STATS users;
```


## Hint 控制执行计划


连接 Hint
```sql
SELECT /* +BROADCAST */ u.*, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;

SELECT /* +SHUFFLE */ u.*, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;
```


3.1+: 括号格式
```sql
SELECT u.*, o.amount
FROM users u JOIN /* +BROADCAST */ orders o ON u.id = o.user_id;
```


注意：EXPLAIN 有四个级别（0-3），级别越高信息越详细
注意：PROFILE 提供实际执行后的详细统计（需要在 impala-shell 中使用）
注意：SUMMARY 提供简洁的执行摘要表格
注意：COMPUTE STATS 是确保优化器正确决策的关键
注意：缺少统计信息时 Impala 会使用默认估算，可能导致低效的计划
注意：BROADCAST vs SHUFFLE 的选择显著影响连接性能
