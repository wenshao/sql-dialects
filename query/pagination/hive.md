# Hive: 分页 (Pagination)

> 参考资料:
> - [1] Apache Hive Language Manual - SELECT
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Select
> - [2] Apache Hive - Sort/Distribute/Cluster By
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+SortBy


## 1. LIMIT (所有版本)

```sql
SELECT * FROM users ORDER BY id LIMIT 10;

```

 ORDER BY + LIMIT 触发 Top-K 优化:
 优化器将全局排序转为每个 Reducer 维护大小为 K 的堆
 避免全量排序，显著降低内存和计算开销

## 2. LIMIT + OFFSET (Hive 2.0+)

```sql
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

```

### 2.0 之前的替代方案: ROW_NUMBER 窗口函数

```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn FROM users
) t WHERE t.rn BETWEEN 21 AND 30;

```

## 3. ORDER BY vs SORT BY vs DISTRIBUTE BY (Hive 特有)

这是 Hive 最独特的排序设计，反映了底层 MapReduce 执行模型。

ORDER BY: 全局排序（所有数据汇聚到单个 Reducer）

```sql
SELECT * FROM users ORDER BY id LIMIT 10;
```

问题: 大数据量下单 Reducer 是严重瓶颈（TB 级数据可能需要数小时）
建议: 始终配合 LIMIT 使用

SORT BY: 局部排序（每个 Reducer 内部分别排序）

```sql
SELECT * FROM users SORT BY id;
```

每个 Reducer 的输出是有序的，但全局不保证有序
适用: 不需要全局有序的场景（如准备合并排序的输入）

DISTRIBUTE BY: 数据分发（按键分配到不同 Reducer）

```sql
SELECT * FROM users DISTRIBUTE BY city;
```

相同 city 的行发送到同一个 Reducer，但不排序

DISTRIBUTE BY + SORT BY: 分区内排序

```sql
SELECT * FROM users DISTRIBUTE BY city SORT BY age DESC;
```

按 city 分发，每个 Reducer 内按 age 降序排列

CLUSTER BY: DISTRIBUTE BY + SORT BY 的简写（只能升序）

```sql
SELECT * FROM users CLUSTER BY id;

```

 设计分析: 为什么 Hive 需要四种排序语义?
 MapReduce 模型有三个阶段: Map → Shuffle(Partition+Sort) → Reduce
 ORDER BY:      强制 1 个 Reducer（全局排序）
 SORT BY:       多个 Reducer 各自排序（Reducer 内排序）
 DISTRIBUTE BY: 控制 Shuffle 分区键（哪些行去哪个 Reducer）
 CLUSTER BY:    同时控制分区键和排序键

 RDBMS 只有 ORDER BY 因为没有分布式 Shuffle 的概念。
 Spark SQL 也继承了 SORT BY/DISTRIBUTE BY 但使用频率低于 Hive。

## 4. 窗口函数分页 (Hive 0.11+)

ROW_NUMBER 分页

```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn FROM users
) t WHERE t.rn BETWEEN 21 AND 30;

```

分组后 Top-N

```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t WHERE rn <= 3;

```

## 5. 键集分页 (Keyset Pagination)

第一页

```sql
SELECT * FROM users ORDER BY id LIMIT 10;

```

后续页（已知上一页最后 id = 100）

```sql
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

```

 键集分页的优势:
1. 性能稳定: 不需要 OFFSET 跳过大量行

2. 与 Hive 分区配合好: WHERE dt > '2024-01-15' ORDER BY dt LIMIT 10


## 6. 大数据场景下的分页建议

 小结果集(< 100万行): LIMIT/OFFSET 可用
 中等结果集(100万~1亿): SORT BY + LIMIT（多 Reducer 并行）
 大结果集(> 1亿): 避免分页，改用分区过滤或数据导出

 Tez 执行引擎: 减少中间落盘，ORDER BY + LIMIT 性能优于 MapReduce
 LLAP 执行引擎: 常驻进程，避免作业启动开销

## 7. 跨引擎对比: 分页语法

 引擎          分页语法                  特殊排序语义
 MySQL         LIMIT n OFFSET m          无
 PostgreSQL    LIMIT n OFFSET m / FETCH  无
 Oracle        FETCH FIRST / ROWNUM      无
 Hive          LIMIT n OFFSET m (2.0+)   SORT BY/DISTRIBUTE BY/CLUSTER BY
 Spark SQL     LIMIT n OFFSET m          继承 Hive 但少用
 BigQuery      LIMIT n OFFSET m          无
 Trino         LIMIT n OFFSET m / FETCH  无

## 8. 已知限制

1. 不支持 FETCH FIRST ... ROWS ONLY（SQL 标准语法）

2. 不支持 TOP N（SQL Server 语法）

3. 不支持 LIMIT offset, count（MySQL 简写语法）

4. 不支持服务端游标 (DECLARE CURSOR)

5. OFFSET 在 2.0 之前不可用


## 9. 对引擎开发者的启示

1. SORT BY/DISTRIBUTE BY 暴露了分布式执行模型:

    Hive 让用户直接控制 Shuffle 行为，这在 RDBMS 中不存在
2. Top-K 优化是 ORDER BY + LIMIT 的必备:

    在分布式引擎中，全局排序是最昂贵的操作之一
3. 键集分页比 OFFSET 分页更适合大数据:

OFFSET 需要跳过大量行，键集分页直接定位到起始点

