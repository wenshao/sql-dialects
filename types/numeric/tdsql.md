# TDSQL: 数值类型

TDSQL distributed MySQL-compatible syntax.

> 参考资料:
> - [TDSQL-C MySQL Documentation](https://cloud.tencent.com/document/product/1003)
> - [TDSQL MySQL Documentation](https://cloud.tencent.com/document/product/557)
> - [MySQL 8.0 Reference Manual - Numeric Data Types](https://dev.mysql.com/doc/refman/8.0/en/numeric-types.html)
> - ============================================================
> - 1. 整数类型
> - ============================================================
> - TINYINT:   1 字节，-128 ~ 127（UNSIGNED: 0 ~ 255）
> - SMALLINT:  2 字节，-32768 ~ 32767（UNSIGNED: 0 ~ 65535）
> - MEDIUMINT: 3 字节，-8388608 ~ 8388607（UNSIGNED: 0 ~ 16777215）
> - INT:       4 字节，-2^31 ~ 2^31-1（UNSIGNED: 0 ~ 2^32-1）
> - BIGINT:    8 字节，-2^63 ~ 2^63-1（UNSIGNED: 0 ~ 2^64-1）

```sql
CREATE TABLE examples (
    tiny_val   TINYINT,
    small_val  SMALLINT,
    medium_val MEDIUMINT,
    int_val    INT,
    big_val    BIGINT,
    pos_val    INT UNSIGNED,
    flag       TINYINT(1)              -- 布尔值（TINYINT 的别名用法）
);
```

## 分布式环境下的整数类型考量


## 2.1 shardkey 列推荐使用 INT / BIGINT

整数 hash 分布均匀，适合作为分片键

```sql
CREATE TABLE distributed_orders (
    id         BIGINT NOT NULL AUTO_INCREMENT,
    user_id    BIGINT NOT NULL,         -- 推荐作为 shardkey
    amount     DECIMAL(10,2),
    PRIMARY KEY (id),
    SHARDKEY (user_id)
);
```

2.2 AUTO_INCREMENT 在分布式中的行为
TDSQL 的 AUTO_INCREMENT 保证全局唯一但不保证连续:
协调节点分配全局唯一 ID，使用类似 snowflake 的机制
不同分片可能产生不同的 ID 间隔
插入失败不会回收已分配的 ID（产生间隙）
注意: 不要假设 AUTO_INCREMENT 值是连续的
2.3 UNSIGNED 在分布式中的注意事项
UNSIGNED 类型可以作为 shardkey
但跨分片计算（SUM/COUNT 等）需注意 UNSIGNED 溢出
建议: 新项目不使用 UNSIGNED，直接用 BIGINT 替代

## 定点数: DECIMAL / NUMERIC


## DECIMAL(M,D) / NUMERIC(M,D): 完全等价

M = 总位数（最大 65），D = 小数位数（最大 30）

```sql
CREATE TABLE prices (
    price    DECIMAL(10,2),     -- 精确到分（8位整数+2位小数）
    rate     DECIMAL(5,4)       -- 汇率（1位整数+4位小数）
);
```

分布式环境下的 DECIMAL:
1. DECIMAL 列可以作为 shardkey（hash 值由精确数值计算）
2. 跨分片 SUM/AVG 在协调节点汇总，精度不受影响
3. 金融场景推荐使用 DECIMAL，避免浮点精度问题

## 浮点数


FLOAT:             4 字节，约 6 位有效数字
DOUBLE / DOUBLE PRECISION: 8 字节，约 15 位有效数字
IEEE 754 精度问题

```sql
SELECT 0.1 + 0.2;                    -- 0.30000000000000004（FLOAT/DOUBLE）
SELECT CAST(0.1 AS DECIMAL(10,2)) + CAST(0.2 AS DECIMAL(10,2)); -- 0.3（精确）
```

分布式场景下浮点数的额外问题:
跨分片 SUM/AVG 可能因浮点累积误差导致不同执行顺序结果不同
金融场景绝对不能使用 FLOAT/DOUBLE

## BIT 类型


## BIT(M): 位字段，M = 1 ~ 64

```sql
CREATE TABLE t (
    flags  BIT(8),                -- 8 位标志
    perms  BIT(32)                -- 32 位权限
);
```

## 插入: 使用 b'...' 或 0x... 格式

```sql
INSERT INTO t (flags) VALUES (b'10101010');
INSERT INTO t (perms) VALUES (0xFF00FF00);
```

BIT 类型的分布式注意事项:
1. BIT 类型不能作为 shardkey（不参与 hash 计算）
2. 跨分片查询中 BIT 列正常工作但性能不佳

## BOOL / BOOLEAN


## BOOLEAN = TINYINT(1): MySQL 的布尔别名

```sql
CREATE TABLE t (active BOOLEAN DEFAULT TRUE);
```

实际存储: TRUE=1, FALSE=0
与 PostgreSQL 的真正 BOOLEAN 不同
WHERE 条件: WHERE active = TRUE 或 WHERE active（隐式转换）

## 分布式数值计算


7.1 跨分片聚合
SUM / COUNT / AVG / MAX / MIN 在协调节点汇总
整数 SUM 可能溢出: TDSQL 自动转换为 DECIMAL 避免溢出
跨分片 AVG = SUM / COUNT，在协调节点计算（非各分片 AVG 的平均）
7.2 分布式序列
TDSQL 提供 AUTO_INCREMENT 全局唯一性:
方式1: 雪花算法（Snowflake）生成 64 位唯一 ID
方式2: 号段模式（Segment），预分配 ID 段给各分片
两种方式都保证全局唯一，但不保证严格递增
7.3 跨分片数值比较
WHERE 条件中的数值比较在各分片独立执行
ORDER BY + LIMIT 在协调节点归并排序
大结果集的排序可能消耗大量协调节点内存

## 数值函数（分布式常用）


## 聚合函数

```sql
SELECT SUM(amount), AVG(amount), COUNT(*) FROM orders;
SELECT MAX(created_at), MIN(created_at) FROM orders;
```

## 数学函数

```sql
SELECT ROUND(3.14159, 2);            -- 3.14
SELECT CEIL(3.14);                    -- 4
SELECT FLOOR(3.14);                   -- 3
SELECT ABS(-5);                       -- 5
SELECT MOD(10, 3);                    -- 1
```

## 随机数

```sql
SELECT RAND();                        -- 0 ~ 1 随机数
```

## 注意事项与最佳实践


## 数值类型与 MySQL 完全兼容，所有 MySQL 数值函数均可用

## shardkey 列推荐使用 INT 或 BIGINT，hash 分布最均匀

## AUTO_INCREMENT 保证全局唯一但不连续，不要依赖连续性

## 金融计算必须使用 DECIMAL，绝对不能用 FLOAT/DOUBLE

## BIT 类型不能作为 shardkey

## UNSIGNED 类型可用但建议避免，直接用更大类型替代

## 跨分片聚合在协调节点汇总，大结果集注意内存消耗

## 浮点数跨分片 SUM 可能因累积顺序不同产生微小差异
