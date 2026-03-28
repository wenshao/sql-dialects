# TDengine: 表分区策略

> 参考资料:
> - [TDengine Documentation - Data Model](https://docs.taosdata.com/concept/)


## TDengine 使用超级表 + 子表模型代替传统分区

## 超级表（STable）= 分区模板


```sql
CREATE STABLE meters (
    ts TIMESTAMP, voltage FLOAT, current FLOAT, phase FLOAT
) TAGS (
    location NCHAR(64), group_id INT
);
```

## 子表 = 分区


## 每个设备一个子表

```sql
CREATE TABLE device_001 USING meters TAGS ('Beijing', 1);
CREATE TABLE device_002 USING meters TAGS ('Shanghai', 2);
```

## 自动创建子表（INSERT 时）

```sql
INSERT INTO device_003 USING meters TAGS ('Guangzhou', 3)
VALUES (NOW, 220.5, 10.2, 0.3);
```

## 按 Tag 查询（类似分区裁剪）


```sql
SELECT * FROM meters WHERE location = 'Beijing';

SELECT AVG(voltage) FROM meters WHERE group_id = 1;
```

## 数据保留


## 创建数据库时设置数据保留时间

```sql
CREATE DATABASE sensor_db KEEP 365;  -- 保留 365 天
```

Vnode 管理
TDengine 将数据分布到多个 Vnode
VGROUPS 参数控制 Vnode 数量
注意：TDengine 用超级表/子表模型代替传统分区
注意：每个子表对应一个数据源（如一个设备）
注意：Tag 过滤实现类似分区裁剪的效果
注意：KEEP 参数控制数据保留时间
注意：数据自动按时间窗口存储在不同文件中
