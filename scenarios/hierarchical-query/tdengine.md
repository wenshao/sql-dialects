# TDengine: 层次查询与树形结构 (Hierarchical Query & Tree Traversal)

> 参考资料:
> - [TDengine Documentation - SQL Reference](https://docs.taosdata.com/taos-sql/)
> - [TDengine Documentation - Data Model](https://docs.taosdata.com/concept/)
> - ============================================================
> - TDengine 是时序数据库，不适合传统层次查询
> - 但其超级表/子表的层次结构本身就是一种层次模型
> - ============================================================
> - TDengine 的层次结构：Database > STable > SubTable
> - 这种结构天然支持设备层次管理
> - ============================================================
> - 1. 超级表/子表的层次模型
> - ============================================================

```sql
CREATE STABLE device_metrics (
    ts          TIMESTAMP,
    temperature FLOAT,
    humidity    FLOAT
) TAGS (
    region      NCHAR(64),
    site        NCHAR(64),
    device_type NCHAR(32)
);
```

## 按层次创建子表

```sql
CREATE TABLE dev_bj_01 USING device_metrics TAGS ('北京', '朝阳区机房', '传感器');
CREATE TABLE dev_bj_02 USING device_metrics TAGS ('北京', '海淀区机房', '传感器');
CREATE TABLE dev_sh_01 USING device_metrics TAGS ('上海', '浦东机房', '传感器');
```

## 按标签层次查询（模拟层次遍历）


## 查询某个区域下的所有设备数据

```sql
SELECT * FROM device_metrics
WHERE region = '北京'
ORDER BY ts DESC LIMIT 100;
```

## 按层次分组统计

```sql
SELECT region, site, COUNT(*) AS device_count
FROM (SELECT DISTINCT TBNAME, region, site FROM device_metrics)
GROUP BY region, site;
```

## 使用标签表示层次关系


## TDengine 3.0 的标签可以表示层次

```sql
CREATE STABLE org_nodes (
    ts    TIMESTAMP,
    value INT
) TAGS (
    node_id    INT,
    node_name  NCHAR(100),
    parent_id  INT,
    node_path  NCHAR(500)  -- 物化路径
);
```

## 按物化路径查询子树

```sql
SELECT DISTINCT node_name, node_path
FROM org_nodes
WHERE node_path LIKE '1/2%';
```

## 4-6. TDengine 的局限性


TDengine 不支持递归 CTE
TDengine 不支持 CONNECT BY
TDengine 不支持自连接
层次查询应在应用层或其他 SQL 引擎中完成
注意：TDengine 是时序数据库，不适合通用层次查询
注意：超级表/子表/标签本身构成两级层次结构
注意：使用物化路径标签可以模拟简单的层次关系
注意：复杂层次查询需要在应用层实现
