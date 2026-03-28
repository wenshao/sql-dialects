# openGauss / GaussDB: 分页 (Pagination)

> 参考资料:
> - [openGauss SQL Reference - SELECT](https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/SELECT.html)
> - [openGauss 开发者指南 - 游标](https://docs.opengauss.org/zh/docs/latest/docs/Developerguide/declaring-a-cursor.html)
> - [GaussDB 文档中心](https://support.huaweicloud.com/gaussdb/index.html)
> - [GaussDB SQL Reference](https://support.huaweicloud.com/intl/en-us/gaussdb/index.html)


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

## OFFSET 的性能问题


大 OFFSET 的性能瓶颈:
即使有索引，仍需遍历 B-tree 叶子节点 OFFSET 次
时间复杂度: O(OFFSET + LIMIT)
在分布式 GaussDB 中问题更严重: 每个 DN 都要返回 offset+limit 行
GaussDB 分布式架构下的分页开销:
假设 4 个 DN（数据节点），LIMIT 10 OFFSET 100000:
每个 DN 返回 100010 行到协调节点 (CN)
CN 全局排序后取第 100001~100010 行
网络传输量: 4 * 100010 行（而非 10 行）

## 键集分页（Keyset Pagination）: 高性能替代方案


## 第一页

```sql
SELECT * FROM users ORDER BY id LIMIT 10;
```

## 后续页（已知上一页最后一条 id = 100）

```sql
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;
```

## 多列排序的键集分页

```sql
SELECT * FROM users
WHERE (created_at, id) > ('2025-01-01', 100)
ORDER BY created_at, id
LIMIT 10;
```

## 索引支持:

```sql
CREATE INDEX idx_users_created_id ON users (created_at, id);
```

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

## 服务端游标（大数据集逐批处理）


## 游标在事务中声明，逐批 FETCH

```sql
BEGIN;
DECLARE user_cursor CURSOR FOR SELECT * FROM users ORDER BY id;
FETCH 100 FROM user_cursor;
FETCH 100 FROM user_cursor;
CLOSE user_cursor;
COMMIT;
```

## openGauss / GaussDB 特有说明


openGauss 与 PostgreSQL 的分页兼容性:
LIMIT / OFFSET:     完全兼容
FETCH FIRST:        完全兼容
DECLARE CURSOR:     完全兼容
GaussDB 分布式版本注意事项:
分页查询需要跨 DN 合并结果，全局排序有数据移动开销
如果排序键是分布键，可以避免跨 DN 排序（分片内排序即可）
推荐将分页查询的排序键设为分布键（或包含分布键的复合键）
GaussDB 的查询优化:
优化器会对 ORDER BY + LIMIT 进行 Top-N 优化
Stream 算子负责分布式环境下的数据重分布

## 版本演进

openGauss 2.0:  LIMIT / OFFSET，FETCH FIRST，基本窗口函数
openGauss 3.0:  增强分布式查询优化
GaussDB:        分布式架构下的分页优化，Stream 算子

## 横向对比: 分页语法差异


语法对比:
openGauss:   LIMIT n OFFSET m + FETCH FIRST（同 PostgreSQL）
PostgreSQL:  LIMIT n OFFSET m + FETCH FIRST（openGauss 的上游）
MySQL:       LIMIT n OFFSET m / LIMIT m, n（不支持 FETCH FIRST）
Oracle:      FETCH FIRST (12c+)，传统用 ROWNUM
KingbaseES:  LIMIT n OFFSET m + FETCH FIRST（同 PostgreSQL 兼容族）
分布式分页对比:
GaussDB 分布式:  需要 CN 协调多 DN 结果，排序开销大
PolarDB-X:       同为分布式，跨分片收集后全局排序
TDSQL:           shardkey 路由可减少跨分片查询
TiDB:            类似，需全局排序后取 LIMIT
