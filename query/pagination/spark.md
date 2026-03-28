# Spark SQL: 分页 (Pagination)

> 参考资料:
> - [1] Spark SQL - LIMIT
>   https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-limit.html


## 1. LIMIT: 基本分页

```sql
SELECT * FROM users ORDER BY id LIMIT 10;

```

LIMIT + OFFSET（Spark 3.4+）

```sql
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

```

SQL 标准语法（Spark 3.4+）

```sql
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;

```

 设计分析: LIMIT 在分布式环境中的实现
   Spark 的 LIMIT 不是简单的"取前 N 行":
### 1. 每个分区取 top N（并行执行，每个 Executor 独立取 N 行）

### 2. 合并所有分区的结果到 Driver 端

### 3. 在 Driver 端取最终的 top N

   这意味着: LIMIT 总是全局有序的（需要数据传输到 Driver）
   大 LIMIT 值可能导致 Driver OOM

## 2. 窗口函数分页（全版本通用）


```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

```

 优点: 不需要 OFFSET 语法（Spark 3.4 之前的唯一方式）
 缺点: 需要全局排序 + 全量行号计算（大数据集上昂贵）

## 3. Keyset 分页（推荐用于大数据集）


页 1

```sql
SELECT * FROM users ORDER BY id LIMIT 10;
```

记住最后一个 id (假设是 10)

页 2

```sql
SELECT * FROM users WHERE id > 10 ORDER BY id LIMIT 10;
```

记住最后一个 id (假设是 20)

页 3

```sql
SELECT * FROM users WHERE id > 20 ORDER BY id LIMIT 10;

```

 设计分析:
   Keyset 分页比 OFFSET 分页高效得多:
   - OFFSET N: 数据库必须扫描并跳过 N 行（O(N) 成本）
   - WHERE id > last_id: 利用排序/分区裁剪直接定位（O(log N) 成本）

   在 Spark 中这一差异更显著:
   OFFSET 100000: 需要全局排序并跳过 10 万行
   WHERE id > last_id: 分区裁剪直接跳过不相关的文件

 对比:
   MySQL:      LIMIT offset, count（简单但大 OFFSET 慢）
   PostgreSQL: LIMIT + OFFSET（同理）/ Keyset 分页推荐
   BigQuery:   推荐 Keyset 分页（无 OFFSET 的原生支持在早期版本）
   ClickHouse: LIMIT + OFFSET 支持但推荐 WHERE 条件分页

## 4. Top-N 分组


```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t
WHERE rn <= 5;

```

## 5. TABLESAMPLE: 随机采样（非分页）


```sql
SELECT * FROM users TABLESAMPLE (10 PERCENT);
SELECT * FROM users TABLESAMPLE (100 ROWS);
SELECT * FROM users TABLESAMPLE (BUCKET 1 OUT OF 10 ON id);

```

 TABLESAMPLE 不是确定性的（每次执行结果不同）
 适用于: 数据探索、近似分析、测试

## 6. 版本演进

Spark 2.0: LIMIT, TABLESAMPLE
Spark 3.4: OFFSET, FETCH FIRST ... ROWS ONLY

限制:
OFFSET 在 Spark 3.4 之前不支持（需用窗口函数模拟）
LIMIT 将结果收集到 Driver——大 LIMIT 值可能 OOM
LIMIT 无 ORDER BY 时结果不确定（非确定性）
无 SCROLL 游标（不是数据库，无持久化会话状态）
大数据集上推荐 Keyset 分页而非 OFFSET 分页

