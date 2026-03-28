# Apache Doris: 迁移速查

 Apache Doris: 迁移速查

 参考资料:
   [1] Doris Documentation - https://doris.apache.org/docs/

## 1. MySQL -> Doris 核心差异

 必须选择数据模型: Duplicate/Aggregate/Unique Key
 必须指定 DISTRIBUTED BY HASH(col) BUCKETS N
 无 AUTO_INCREMENT(2.1+ 实验性支持)
 无外键、CHECK、UNIQUE 约束
 无事务(2.1+ 有限 BEGIN/COMMIT)
 MySQL 客户端可直接连接(兼容 MySQL 协议)

## 2. 类型映射

 MySQL INT/BIGINT       -> Doris INT/BIGINT
 MySQL VARCHAR(n)       -> Doris VARCHAR(n)
 MySQL TEXT             -> Doris STRING
 MySQL DATETIME         -> Doris DATETIME
 MySQL JSON             -> Doris JSON(1.2+)
 MySQL AUTO_INCREMENT   -> 不支持(2.1+ 实验)
 MySQL BLOB             -> 不支持
 MySQL ENUM             -> VARCHAR

## 3. 函数映射 (基本兼容 MySQL)

 IFNULL -> IFNULL/COALESCE
 NOW()  -> NOW()
 CONCAT -> CONCAT
 DATE_FORMAT -> DATE_FORMAT
 GROUP_CONCAT -> GROUP_CONCAT
 LIMIT -> LIMIT

## 4. 写入方式

 少量: INSERT INTO
 批量: Stream Load(HTTP) / Broker Load(HDFS/S3)
 实时: Routine Load(Kafka)
 Flink CDC: 实时同步 MySQL binlog

## 5. 常见陷阱

BUCKETS 数量影响性能(每个 100MB~1GB)
数据模型选择不可更改(建表后不能切换)
BITMAP/HLL 类型用于近似/精确去重
VARCHAR(n) 的 n 是字节数(UTF-8 中文 3 字节)

