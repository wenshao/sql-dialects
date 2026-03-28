# Hologres: 索引

> 参考资料:
> - [Hologres SQL - CREATE TABLE](https://help.aliyun.com/zh/hologres/user-guide/create-table)
> - [Hologres SQL Reference](https://help.aliyun.com/zh/hologres/user-guide/overview-27)
> - Hologres 通过表属性设置索引和数据组织方式
> - 兼容部分 PostgreSQL 索引语法
> - ============================================================
> - 聚集索引（Clustering Key）
> - ============================================================
> - 决定数据在文件内的排序方式，加速范围查询

```sql
CREATE TABLE orders (
    id         BIGINT NOT NULL,
    user_id    BIGINT NOT NULL,
    order_date DATE NOT NULL,
    amount     NUMERIC(10,2),
    PRIMARY KEY (id)
);
CALL set_table_property('orders', 'clustering_key', 'order_date');
```

## Segment Key（分段键）

## 文件级别的索引，加速过滤和范围扫描

```sql
CALL set_table_property('orders', 'segment_key', 'order_date');
```

## Bitmap 索引

## 对指定列建立 bitmap 索引，加速等值过滤

```sql
CALL set_table_property('orders', 'bitmap_columns', 'user_id,status');
```

## 字典编码（Dictionary Encoding）

## 对低基数列进行字典编码，减少存储空间和加速查询

```sql
CALL set_table_property('orders', 'dictionary_encoding_columns', 'status,region');
```

## 分布键（Distribution Key）

## 决定数据在 shard 间的分布，影响 JOIN 和 GROUP BY 性能

```sql
CALL set_table_property('orders', 'distribution_key', 'user_id');
```

## 分区（List Partitioning）


```sql
CREATE TABLE orders_partitioned (
    id         BIGINT NOT NULL,
    user_id    BIGINT,
    amount     NUMERIC(10,2),
    order_date DATE NOT NULL,
    PRIMARY KEY (id, order_date)
)
PARTITION BY LIST (order_date);

CREATE TABLE orders_20240115 PARTITION OF orders_partitioned
FOR VALUES IN ('2024-01-15');
```

## 行存表的主键索引

## 行存表的 PRIMARY KEY 自动建立索引，用于点查优化

```sql
CREATE TABLE users (
    id       BIGINT NOT NULL,
    username TEXT NOT NULL,
    email    TEXT,
    PRIMARY KEY (id)
);
CALL set_table_property('users', 'orientation', 'row');
```

## 列存表属性组合推荐


```sql
CREATE TABLE events (
    id         BIGINT NOT NULL,
    user_id    BIGINT,
    event_type TEXT,
    event_time TIMESTAMPTZ NOT NULL,
    data       JSONB,
    PRIMARY KEY (id)
);
CALL set_table_property('events', 'orientation', 'column');
CALL set_table_property('events', 'clustering_key', 'event_time');
CALL set_table_property('events', 'segment_key', 'event_time');
CALL set_table_property('events', 'bitmap_columns', 'user_id,event_type');
CALL set_table_property('events', 'dictionary_encoding_columns', 'event_type');
CALL set_table_property('events', 'distribution_key', 'user_id');
```

注意：Hologres 不支持 PostgreSQL 的 CREATE INDEX 语法
注意：索引通过 CALL set_table_property 设置
注意：clustering_key 建议选择范围查询频繁的列
注意：bitmap_columns 建议选择等值过滤频繁的列
注意：行存表主键自动索引，列存表通过属性优化
