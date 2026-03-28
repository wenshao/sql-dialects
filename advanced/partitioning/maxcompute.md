# MaxCompute (ODPS): 表分区策略

> 参考资料:
> - [1] MaxCompute Documentation - Partitioned Tables
>   https://help.aliyun.com/zh/maxcompute/user-guide/partition


## 1. 分区表 —— MaxCompute 最核心的设计


```sql
CREATE TABLE orders (
    id       BIGINT,
    user_id  BIGINT,
    amount   DECIMAL(10,2),
    order_time DATETIME
)
PARTITIONED BY (dt STRING, region STRING)
LIFECYCLE 90;

```

 设计决策: 分区列不是普通列
   分区列值编码在目录路径中: /orders/dt=20240115/region=cn/data_files
   不存储在 AliORC 数据文件中
   这来自 Hive 的设计，MaxCompute 完整继承

   影响:
     SELECT * FROM orders: 分区列在结果集最后（不在建表时定义的位置）
     INSERT 时分区列不在 VALUES 中: 通过 PARTITION (dt='...') 指定
     分区列类型推荐 STRING: 目录路径本质上是字符串
     分区列不能被 ALTER: 目录路径不能改名

   对比:
     BigQuery:    分区列是普通列（用户无感知）
     Snowflake:   微分区自动管理（无需手动分区）
     ClickHouse:  PARTITION BY 表达式（灵活但分区列是普通列）
     Hive:        与 MaxCompute 完全相同

## 2. 分区操作


添加分区（DDL 操作，创建目录）

```sql
ALTER TABLE orders ADD PARTITION (dt = '20240615', region = 'East');
ALTER TABLE orders ADD IF NOT EXISTS PARTITION (dt = '20240615', region = 'West');

```

删除分区（DDL 操作，删除目录及所有数据文件）

```sql
ALTER TABLE orders DROP PARTITION (dt = '20240101', region = 'East');
ALTER TABLE orders DROP PARTITION (dt >= '20240101' AND dt <= '20240131');

```

写入分区数据（静态分区: 指定分区值）

```sql
INSERT OVERWRITE TABLE orders PARTITION (dt = '20240615', region = 'East')
SELECT id, user_id, amount, order_time FROM raw_orders
WHERE order_date = '2024-06-15' AND region = 'East';

```

动态分区: 由数据值自动确定分区

```sql
INSERT OVERWRITE TABLE orders PARTITION (dt, region)
SELECT id, user_id, amount, order_time, order_date AS dt, region
FROM raw_orders;

```

查看分区

```sql
SHOW PARTITIONS orders;

```

## 3. 分区设计最佳实践


### 3.1 分区粒度选择

   按天分区: 最常见（dt = '20240115'）
   按小时分区: 实时性要求高的场景
   按地区分区: 二级分区（dt + region）
   分区不宜过细: 每个分区对应一个目录 + 元数据记录
     分区过多（>10万）: 元数据压力大，SHOW PARTITIONS 慢
     分区过少: 单分区数据量大，查询必须扫描大量数据

### 3.2 分区列选择原则

   选择查询中最常用的过滤条件（WHERE dt = '...'）
   选择基数适中的列（千~万级分区）
   避免高基数列做分区（如 user_id → 数百万分区）

### 3.3 多级分区

```sql
CREATE TABLE logs (
    id      BIGINT,
    message STRING,
    level   STRING
)
PARTITIONED BY (
    dt     STRING,                          -- 一级分区: 日期
    region STRING,                          -- 二级分区: 地区
    hour   STRING                           -- 三级分区: 小时
);

```

 多级分区的裁剪: 必须从左到右连续指定
 好: WHERE dt = '20240115' AND region = 'cn'
 好: WHERE dt = '20240115'
 差: WHERE region = 'cn'（跳过 dt，无法裁剪第一级）

## 4. 分区与成本控制


MaxCompute 按量付费: 按扫描数据量计费
分区裁剪直接影响费用:
无分区裁剪: 扫描全表（TB 级 → 大额费用）
有分区裁剪: 只扫描指定分区（GB 级 → 低费用）

COST SQL 验证:

```sql
COST SQL SELECT * FROM orders WHERE dt = '20240115';
```

对比:

```sql
COST SQL SELECT * FROM orders;              -- 全表扫描 — 费用可能高 100 倍

```

## 5. LIFECYCLE 与分区的交互


分区表的 LIFECYCLE 作用于分区（不是整个表）

```sql
ALTER TABLE orders SET LIFECYCLE 90;

```

 最后修改时间超过 90 天的分区被自动回收
 最后修改时间 = 该分区最后一次数据写入的时间
 只读查询不更新最后修改时间

 手动延长分区生命:
 ALTER TABLE orders PARTITION (dt='20240101') TOUCH;  -- 更新修改时间

## 6. 分区表的限制


 单表最大分区数: 60,000（可申请调整）
 多级分区最多: 6 级
 分区列类型: 推荐 STRING（也支持 TINYINT/SMALLINT/INT/BIGINT）
 分区值长度: 最大 256 字节
 分区列不能被 ALTER（ADD/DROP/CHANGE）
 分区列在 SELECT * 中排在最后

## 7. 横向对比: 分区策略


 分区方式:
MaxCompute: PARTITIONED BY（显式目录分区）  | Hive: 完全相同
BigQuery:   按 DATE/TIMESTAMP/INT 列分区    | Snowflake: 自动微分区
ClickHouse: PARTITION BY 表达式（灵活）     | Spark: PARTITIONED BY

 分区列是否是普通列:
   MaxCompute/Hive: 不是（编码在目录路径中）
   BigQuery/ClickHouse: 是（对用户透明）
   Snowflake: 无传统分区概念（自动微分区）

 动态分区:
MaxCompute: PARTITION (dt) 不指定值          | Hive: 相同
BigQuery:   自动按列值分区                   | Spark: 相同

 自动管理:
MaxCompute: 手动 ADD/DROP PARTITION          | Hive: 手动
BigQuery:   自动创建分区                     | Snowflake: 完全自动

 TTL/LIFECYCLE:
MaxCompute: LIFECYCLE N（天）                | ClickHouse: TTL expression
BigQuery:   partition_expiration_days        | Hive: 无内置

## 8. 对引擎开发者的启示


### 1. 分区是大数据引擎最重要的数据管理和性能优化机制

### 2. 分区列不是普通列的设计简化了实现但增加了用户认知负担

### 3. BigQuery/Snowflake 的"分区对用户透明"是更好的用户体验

### 4. LIFECYCLE 与分区的结合是存储治理的最佳实践

### 5. 分区裁剪是最大的成本优化杠杆 — 引擎应在 EXPLAIN 中明确显示

### 6. 分区数量上限和元数据管理是大规模环境的隐藏瓶颈

