# MariaDB: 分区

与 MySQL 分区基本一致, 系统版本分区是独有特性

参考资料:
[1] MariaDB Knowledge Base - Partitioning
https://mariadb.com/kb/en/partitioning/

## 1. RANGE 分区

```sql
CREATE TABLE access_logs (
    id         BIGINT NOT NULL AUTO_INCREMENT,
    user_id    BIGINT NOT NULL,
    action     VARCHAR(50) NOT NULL,
    created_at DATETIME NOT NULL,
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (YEAR(created_at)) (
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION pmax  VALUES LESS THAN MAXVALUE
);
```


## 2. LIST / HASH / KEY 分区

```sql
CREATE TABLE orders_by_region (
    id     BIGINT NOT NULL, region VARCHAR(20) NOT NULL, amount DECIMAL(10,2),
    PRIMARY KEY (id, region)
) PARTITION BY LIST COLUMNS (region) (
    PARTITION p_asia   VALUES IN ('CN', 'JP', 'KR'),
    PARTITION p_europe VALUES IN ('DE', 'FR', 'UK'),
    PARTITION p_other  VALUES IN (DEFAULT)   -- 10.2+: DEFAULT 分区
);

CREATE TABLE sessions (id BIGINT PRIMARY KEY, data TEXT)
PARTITION BY HASH(id) PARTITIONS 8;
```


## 3. 系统版本分区 (MariaDB 独有)

```sql
CREATE TABLE versioned_products (
    id    BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    name  VARCHAR(255) NOT NULL,
    price DECIMAL(10,2)
) WITH SYSTEM VERSIONING
PARTITION BY SYSTEM_TIME INTERVAL 1 MONTH (
    PARTITION p_history HISTORY,
    PARTITION p_current CURRENT
);
```

历史数据自动按月分区, 当前数据在单独分区
可以对历史分区使用不同的存储引擎 (如 Archive) 节省空间
这是 MariaDB 系统版本表的杀手级特性

## 4. 对引擎开发者: 版本分区的实现

SYSTEM_TIME 分区的实现要点:
1. 行更新时: 旧行移动到匹配时间范围的历史分区
2. 分区路由: 基于 row_end 时间戳判断目标历史分区
3. 自动分区管理: INTERVAL 子句自动创建新的历史分区
4. 查询优化: FOR SYSTEM_TIME 查询可以利用分区裁剪
这比 MySQL 的分区更智能: 将 temporal 语义嵌入分区策略
