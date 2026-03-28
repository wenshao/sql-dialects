# TDengine: 缓慢变化维度 (Slowly Changing Dimension)

> 参考资料:
> - [TDengine Documentation](https://docs.tdengine.com/reference/sql/)


## 注意: TDengine 是时序数据库，不适用于传统 SCD 模式

TDengine 数据模型以时间序列为核心:
超级表 (STABLE) 定义 schema
子表 (TABLE) 每个采集设备一个
标签 (TAG) 类似维度属性，可更新

## 超级表和子表示例

```sql
CREATE STABLE sensors (
    ts        TIMESTAMP,
    temperature FLOAT,
    humidity    FLOAT,
    power_usage FLOAT
) TAGS (
    location  NCHAR(64),
    status    NCHAR(20),
    model     NCHAR(32)
);
```

## 自动创建子表

```sql
CREATE TABLE sensor_001 USING sensors TAGS ('room_101', 'active', 'model_A');
CREATE TABLE sensor_002 USING sensors TAGS ('room_102', 'active', 'model_B');
```

## SCD Type 1: 更新标签（直接覆盖，不保留历史）

```sql
ALTER TABLE sensor_001 SET TAG location = 'room_201';
ALTER TABLE sensor_001 SET TAG status = 'maintenance';
ALTER TABLE sensor_002 SET TAG model = 'model_C';
```

## 查询当前标签值

```sql
SELECT DISTINCT TBNAME, location, status, model
FROM sensors
WHERE location = 'room_201';
```

## SCD Type 2: TDengine 不原生支持

标签变化不保留历史
如需跟踪标签变化历史，建议以下方案:
方案 1: 在应用层记录变更日志
INSERT INTO tag_changelog VALUES(NOW, 'sensor_001', 'location', 'room_101', 'room_201');
方案 2: 将变更事件写入时序数据
CREATE STABLE tag_history (
ts         TIMESTAMP,
tag_name   NCHAR(64),
old_value  NCHAR(200),
new_value  NCHAR(200)
) TAGS (device_id NCHAR(64));
方案 3: 使用外部关系数据库（MySQL/PostgreSQL）存储维度表
TDengine 负责时序数据，关系数据库负责维度管理

## 查询标签信息

## 列出所有子表及其标签

```sql
SELECT TBNAME, location, status, model FROM sensors;
```

## 按标签过滤查询

```sql
SELECT AVG(temperature), MAX(temperature)
FROM sensors
WHERE location = 'room_201' AND ts >= NOW - 1h;
```

注意：TDengine 标签类似维度属性但只支持覆盖更新（SCD Type 1）
注意：ALTER TABLE ... SET TAG 是原子操作
限制：不支持 SCD Type 2（版本化历史）
限制：不支持 MERGE INTO, UPSERT 等传统维度加载语法
