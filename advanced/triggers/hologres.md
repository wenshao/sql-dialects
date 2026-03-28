# Hologres: 触发器

> 参考资料:
> - [Hologres SQL Reference](https://help.aliyun.com/zh/hologres/user-guide/overview-27)
> - [Hologres Documentation](https://help.aliyun.com/zh/hologres/)


## Hologres 不支持传统 PostgreSQL 触发器

虽然兼容 PostgreSQL 语法，但触发器不在兼容范围内

## 替代方案 1: Binlog（变更数据捕获）


Hologres 支持 Binlog，可以捕获表的变更
类似触发器的 AFTER INSERT/UPDATE/DELETE
启用 Binlog

```sql
CALL set_table_property('users', 'binlog.level', 'replica');
CALL set_table_property('users', 'binlog.ttl', '86400');  -- 保留 24 小时
```

Binlog 可以被 Flink 消费，实现实时处理
Flink SQL 消费 Hologres Binlog：
CREATE TABLE holo_source (
id BIGINT,
username STRING,
email STRING
) WITH (
'connector' = 'hologres',
'dbname' = 'mydb',
'tablename' = 'users',
'binlog' = 'true',
'endpoint' = '...',
...
);

## 替代方案 2: Flink 实时处理


使用 Flink 消费 Binlog 并写回 Hologres
实现类似触发器的实时数据处理管道
Flink 处理流程：
Hologres 表变更 -> Binlog -> Flink 处理 -> 写入 Hologres 目标表
示例场景：
1. 用户表变更时，自动更新用户统计表
2. 订单创建时，自动更新库存表
3. 数据变更时，自动发送通知

## 替代方案 3: 定时调度


使用 DataWorks 调度定时执行 SQL
类似定时触发器
示例：每小时更新汇总表
INSERT INTO order_summary
SELECT
DATE(order_date) AS day,
COUNT(*) AS cnt,
SUM(amount) AS total
FROM orders
WHERE order_date >= NOW() - INTERVAL '1 hour'
GROUP BY DATE(order_date)
ON CONFLICT (day) DO UPDATE SET cnt = EXCLUDED.cnt, total = EXCLUDED.total;

## 替代方案 4: INSERT ... ON CONFLICT（UPSERT）


## 使用 ON CONFLICT 实现类似 BEFORE INSERT 触发器的逻辑

在主键冲突时自动更新

```sql
INSERT INTO users (id, username, email, updated_at)
VALUES (1, 'alice', 'alice@example.com', now())
ON CONFLICT (id) DO UPDATE SET
    username = EXCLUDED.username,
    email = EXCLUDED.email,
    updated_at = now();
```

## 替代方案 5: 外部表联动


## 通过 Hologres 外部表关联 MaxCompute

MaxCompute 任务完成后，Hologres 自动可以查询到新数据

```sql
CREATE FOREIGN TABLE mc_orders (
    id     BIGINT,
    amount NUMERIC(10,2)
)
SERVER odps_server
OPTIONS (project_name 'myproject', table_name 'orders');
```

## 替代方案 6: 物化视图（有限支持）


Hologres 的物化视图支持有限
主要通过 Flink + Binlog 实现实时聚合
注意：Hologres 不支持 PostgreSQL 的 CREATE TRIGGER 语法
注意：Binlog + Flink 是最推荐的实时触发器替代方案
注意：ON CONFLICT 实现了主键冲突时的自动处理
注意：定时调度适合非实时的定期处理场景
注意：Hologres 定位为实时数仓，Binlog 是其核心能力
