# Spanner: 执行计划

> 参考资料:
> - [Spanner Documentation - Query execution plans](https://cloud.google.com/spanner/docs/query-execution-plans)
> - [Spanner Documentation - Query statistics](https://cloud.google.com/spanner/docs/query-statistics-tables)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

## 查看执行计划（Google Cloud Console）


在 Cloud Console 中：
## 进入 Spanner 实例

## 点击 "Query" 页面

## 输入查询并点击 "Run"

## 查看 "Explanation" 选项卡


## 客户端 API 获取执行计划


gcloud CLI：
gcloud spanner databases execute-sql mydb \
  --instance=myinstance \
  --query-mode=PROFILE \
  --sql="SELECT * FROM users WHERE username = 'alice'"

query-mode 选项：
NORMAL    正常执行（默认）
PLAN      只返回计划（不执行）
PROFILE   执行并返回统计

## 执行计划操作符


Distributed Union    分布式联合（跨 split 执行）
Distributed Cross Apply  分布式交叉应用
Serialize Result     序列化结果
Scan                 表扫描
Index Scan           索引扫描
Filter Scan          带过滤的扫描
Hash Join            哈希连接
Cross Apply          交叉应用
Sort                 排序
Aggregate            聚合
Limit                限制

## 查询统计信息表


最近 1 分钟的 Top 查询
```sql
SELECT text, execution_count, avg_latency_seconds,
       avg_rows_scanned, avg_cpu_seconds
FROM spanner_sys.query_stats_top_minute
ORDER BY avg_latency_seconds DESC;

```

最近 10 分钟的统计
```sql
SELECT * FROM spanner_sys.query_stats_top_10minute
ORDER BY execution_count DESC LIMIT 10;

```

最近 1 小时
```sql
SELECT * FROM spanner_sys.query_stats_top_hour
ORDER BY avg_latency_seconds DESC LIMIT 10;

```

汇总统计
```sql
SELECT * FROM spanner_sys.query_stats_total_minute;

```

## 事务统计


```sql
SELECT fprint, read_columns, write_constructive_columns,
       avg_total_latency_seconds, avg_commit_latency_seconds
FROM spanner_sys.txn_stats_top_minute
ORDER BY avg_total_latency_seconds DESC;

```

## Key Visualizer


Cloud Console 提供 Key Visualizer：
- 展示数据行的读写热点
- 识别数据倾斜
- 发现热点行
- 时间序列可视化

## 优化建议


## 使用 Interleaved Tables 减少 Distributed Union

## 使用二级索引避免全表扫描

## 使用 FORCE_INDEX Hint

```sql
SELECT * FROM users@{FORCE_INDEX=idx_users_age} WHERE age > 25;

```

## 使用 JOIN_TYPE Hint

```sql
SELECT * FROM users u
JOIN@{JOIN_TYPE=HASH_JOIN} orders o ON u.id = o.user_id;

```

**注意:** Spanner 没有 SQL EXPLAIN 语句
**注意:** 通过 Cloud Console 或 API 的 PLAN/PROFILE 模式获取执行计划
**注意:** Distributed Union 是 Spanner 分布式架构的核心操作符
**注意:** spanner_sys 表提供查询和事务的性能统计
**注意:** Key Visualizer 帮助识别数据访问热点
**注意:** Interleaved Tables 可以减少跨 split 的操作
