# MaxCompute (ODPS): 分页 (Pagination)

> 参考资料:
> - [1] MaxCompute SQL - SELECT
>   https://help.aliyun.com/zh/maxcompute/user-guide/select
> - [2] MaxCompute MCQA 交互式分析
>   https://help.aliyun.com/zh/maxcompute/user-guide/mcqa


## 1. LIMIT —— 基本取前 N 行


```sql
SELECT * FROM users ORDER BY id LIMIT 10;

```

 设计分析: ORDER BY + LIMIT 的 Top-K 优化
   MaxCompute 优化器将 ORDER BY + LIMIT 转换为 Top-K 算子
   实现: 每个 Map 节点维护大小为 K 的堆 → Reduce 阶段合并
   避免了全量排序（O(N log N) → O(N log K)）
   对比: 所有现代引擎都做此优化（PostgreSQL、MySQL、BigQuery 等）

## 2. LIMIT + OFFSET（2.0+）


跳过前 20 行，取 10 行

```sql
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

```

带总行数的分页（窗口函数方式）

```sql
SELECT *, COUNT(*) OVER() AS total_count
FROM users ORDER BY id LIMIT 10 OFFSET 20;
```

 注意: COUNT(*) OVER() 需要扫描全部数据，大数据集下很慢

 OFFSET 的性能问题:
   LIMIT 10 OFFSET 1000000: 需要排序 1000010 行，只返回 10 行
   偏移量越大，性能越差（线性退化）
   这是所有引擎的 OFFSET 都有的问题，不是 MaxCompute 特有的

## 3. 窗口函数分页（早期版本替代方案）


ROW_NUMBER 分页（适用于所有版本）

```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

```

分组后 Top-N（不是分页，但关系密切）

```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t WHERE rn <= 3;

```

## 4. 键集分页（Keyset Pagination）—— 推荐方案


第一页

```sql
SELECT * FROM users ORDER BY id LIMIT 10;

```

后续页（已知上一页最后一条 id = 100）

```sql
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

```

多列排序的键集分页

```sql
SELECT * FROM users
WHERE created_at > '2025-01-01'
   OR (created_at = '2025-01-01' AND id > 100)
ORDER BY created_at, id
LIMIT 10;

```

 键集分页的优势:
   性能恒定: 无论第几页，都只需要扫描 LIMIT 行（无 OFFSET 退化）
   利用分区: WHERE id > 100 可以触发分区裁剪（如果 id 是分区键）
   缺点: 不能跳页（只能顺序翻页），复合排序条件 SQL 复杂

## 5. 不支持的分页语法


 FETCH FIRST ... ROWS ONLY: 不支持（SQL 标准语法）
 TOP N:                     不支持（SQL Server 语法）
 LIMIT offset, count:       不支持（MySQL 简写语法）
 DECLARE CURSOR:            不支持（服务端游标）

## 6. 大数据场景下的分页设计


MaxCompute 是批处理引擎，分页有特殊考量:

全表 ORDER BY 在大数据量下极其昂贵:
ORDER BY 需要将所有数据发送到一个 Reducer（单节点瓶颈）
对于 TB 级数据，单个 Reducer 内存和时间都不可接受
最佳实践: 始终配合 LIMIT 使用 ORDER BY（触发 Top-K 优化）

DISTRIBUTE BY + SORT BY（局部有序的替代方案）:
DISTRIBUTE BY hash_column: 按列值 hash 分发到不同 Reducer
SORT BY sort_col: 在每个 Reducer 内部排序（非全局排序）
适用: 只需局部有序 + LIMIT 的场景

```sql
SELECT * FROM users DISTRIBUTE BY id SORT BY id LIMIT 10;

```

 MCQA（交互式查询加速）:
   MCQA 场景下分页查询可以秒级响应（无需启动 MapReduce 作业）
   适用于数据量 < 百万行的交互式分析
   大数据集仍然建议使用键集分页或数据导出

 数据量建议:
   < 100 万行: LIMIT/OFFSET 可用（MCQA 场景）
   100 万~1 亿行: 键集分页 + LIMIT
   > 1 亿行: 避免分页，改用分区过滤或数据导出

## 7. 横向对比: 分页语法


 LIMIT + OFFSET:
MaxCompute: LIMIT n OFFSET m（2.0+）   | Hive: LIMIT n OFFSET m（2.0+）
PostgreSQL: LIMIT n OFFSET m           | MySQL: LIMIT m, n 或 LIMIT n OFFSET m
BigQuery:   LIMIT n OFFSET m           | Snowflake: LIMIT n OFFSET m

 FETCH FIRST（SQL 标准）:
MaxCompute: 不支持                     | PostgreSQL: 支持
Oracle:     12c+ 支持                  | SQL Server: 2012+ 支持

 服务端游标:
MaxCompute: 不支持（批处理引擎）       | PostgreSQL/MySQL/Oracle: 支持
BigQuery:   不支持                     | Snowflake: 不支持

 Top-K 优化:
MaxCompute: ORDER BY + LIMIT 自动优化  | 所有现代引擎均支持

## 8. 对引擎开发者的启示


1. Top-K 优化（堆排序代替全排序）是最基本的分页优化 — 必须支持

2. OFFSET 的线性退化是分页的根本缺陷 — 应鼓励键集分页

3. 批处理引擎的 ORDER BY 单节点瓶颈应该有 WARNING（无 LIMIT 时）

4. MCQA 类交互式加速是批处理引擎进入交互式分析的关键能力

5. 分布式引擎的分页与 OLTP 引擎有本质区别 — 文档应明确说明

6. SQL 标准的 FETCH FIRST 语法应该支持（兼容性收益）

