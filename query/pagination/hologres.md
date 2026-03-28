# Hologres: 分页 (Pagination)

兼容 PostgreSQL 语法。

> 参考资料:
> - [Hologres SQL - SELECT (LIMIT/OFFSET)](https://help.aliyun.com/zh/hologres/user-guide/select)
> - [Hologres 最佳实践 - 数据查询优化](https://help.aliyun.com/zh/hologres/user-guide/query-optimization)
> - [Hologres 兼容 PostgreSQL 说明](https://help.aliyun.com/zh/hologres/product-overview/compatible-with-postgresql)


## LIMIT / OFFSET（传统分页）


## 基本分页: 跳过前 20 行，取 10 行

```sql
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;
```

## 仅取前 N 行

```sql
SELECT * FROM users ORDER BY id LIMIT 10;
```

## 带总行数的分页（一次查询获取数据和总数）

```sql
SELECT *, COUNT(*) OVER() AS total_count
FROM users ORDER BY id LIMIT 10 OFFSET 20;
```

## FETCH FIRST（SQL 标准语法）


## SQL 标准 OFFSET / FETCH 语法

```sql
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;
```

## FETCH NEXT（等价于 FETCH FIRST）

```sql
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;
```

## 仅取前 N 行（标准语法）

```sql
SELECT * FROM users ORDER BY id FETCH FIRST 10 ROWS ONLY;
```

## OFFSET 的性能问题（列存引擎的特殊考量）


Hologres 采用行列混存引擎，分页性能取决于存储格式:
行存表: 点查和范围扫描快，分页性能较好
列存表: 批量扫描快，但 OFFSET 需要读取所有列的数据
大 OFFSET 分页性能较差
列存引擎的 OFFSET 开销分析:
1. 需要从磁盘读取 offset + limit 行的数据（向量化的批处理）
2. 列存格式下，跳过行的代价与行存不同（需要解码向量）
3. 对于宽表（列数多），OFFSET 的代价更高
建议:
交互式分页查询优先使用行存表或行列混存
大数据量的分析查询避免使用 OFFSET 分页

## 键集分页（Keyset Pagination）: 高性能替代方案


## 第一页

```sql
SELECT * FROM users ORDER BY id LIMIT 10;
```

## 后续页（已知上一页最后一条 id = 100）

```sql
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;
```

## 多列排序的键集分页（使用 ROW 值比较）

```sql
SELECT * FROM users
WHERE (created_at, id) > ('2025-01-01', 100)
ORDER BY created_at, id
LIMIT 10;
```

索引支持:
Hologres 支持 TABLE 上的索引（如聚簇索引 Clustering Key）
建议将分页排序键设为 Clustering Key 以获得最佳性能
CREATE TABLE users (... , PRIMARY KEY (id)) WITH (clustering_key = 'created_at');

## 窗口函数辅助分页


## ROW_NUMBER 分页

```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn FROM users
) t WHERE rn BETWEEN 21 AND 30;
```

## 分组后 Top-N

```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t WHERE rn <= 3;
```

## 注意: 窗口函数方式需要计算所有行的 ROW_NUMBER，性能不如键集分页

## Hologres 特有说明


Hologres 兼容 PostgreSQL 语法，分页特性:
LIMIT / OFFSET:     支持
FETCH FIRST:        支持（SQL 标准）
ROW 值比较:         支持（键集分页可用）
DECLARE CURSOR:     不支持（Hologres 不支持服务端游标）
存储引擎选择对分页的影响:
行存表 (row_orientation): 适合点查 + 分页（OLTP 场景）
列存表 (column_orientation): 适合分析（OLAP），大 OFFSET 性能差
行列混存: 兼顾点查和分析的性能
分布键 (Distribution Key) 与分页:
如果排序键是分布键，查询只在目标 shard 上执行
如果不是分布键，需要跨 shard 汇总排序
建议将常用的分页排序键设为分布键

## 版本演进

Hologres V0.1:  LIMIT / OFFSET 基本支持（兼容 PG）
Hologres V0.8:  FETCH FIRST 支持，窗口函数增强
Hologres V1.1:  行列混存，优化 OLTP 分页场景
Hologres V1.3:  Clustering Key 优化，范围扫描增强

## 横向对比: 分页语法差异


语法对比:
Hologres:   LIMIT n OFFSET m + FETCH FIRST（PG 兼容）
PostgreSQL: LIMIT n OFFSET m + FETCH FIRST（Hologres 的语法基础）
MaxCompute: LIMIT n OFFSET m（MCQA 交互式场景）
ClickHouse: LIMIT n OFFSET m（不支持 FETCH FIRST）
分析引擎分页对比:
Hologres:    实时数仓，行列混存支持 OLTP 分页
ClickHouse:  列存分析引擎，大 OFFSET 极慢（需读取向量化块）
MaxCompute:  离线批处理，分页仅适用于 MCQA 交互式场景
Doris:       列存引擎，MySQL 兼容分页语法
