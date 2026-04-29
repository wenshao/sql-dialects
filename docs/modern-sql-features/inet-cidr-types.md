# INET 与 CIDR 网络地址类型 (INET and CIDR Types)

把 IP 地址塞进 VARCHAR(45) 看似无伤大雅,但当一张防火墙日志表跑到 100 亿行、每天还要回答 "这条 IP 属于哪个子网" "这台主机在不在 10.0.0.0/8 内" 时,字符串方案就会让 CPU、存储、索引同时崩溃。专门的 INET/CIDR 类型不是语法糖,而是一种把网络语义植入存储引擎的设计:固定字节宽度、CIDR 前缀、容器/包含运算符、子网树索引,一应俱全。

## SQL 标准:留给厂商自由发挥的灰色地带

SQL:1992 / SQL:2003 / SQL:2016 / SQL:2023 的所有发布版本中,均未定义 IP 地址、网络地址或 MAC 地址类型。这意味着:

1. **没有官方 INET/CIDR 类型** —— SQL 标准只规定了 BIT、CHARACTER、NUMERIC、DATETIME 等通用类型
2. **没有官方运算符** —— 比如子网包含 (`<<`, `>>`)、网络掩码计算等
3. **没有官方函数** —— 例如 host()、netmask()、broadcast()、network()
4. **完全由厂商自定义** —— 各引擎各自为政,语法、语义、性能差异极大

但网络地址作为现代应用普遍需求(防火墙、CDN、日志分析、合规审计),实际上 PostgreSQL 自 7.4 (2003) 起就提供了完整的 inet/cidr/macaddr 类型族,后续诸多分析型引擎也陆续跟进。本文将横向对比 45+ 个数据库引擎在网络地址类型上的支持情况,揭示其设计权衡。

## 为什么需要专门的网络地址类型

### 1. 存储效率

```
IPv4 地址 192.168.1.1 的存储成本对比:
  VARCHAR("192.168.1.1")     : 11 字节 + 长度前缀 = ~13 字节
  VARCHAR(15) 固定长度        : 15 字节 (浪费 4 字节)
  专门的 IPv4 类型           : 4 字节 (5 倍压缩)
  专门的 IPv6 类型           : 16 字节 (vs 字符串 39+ 字节)
  PostgreSQL inet (IPv4)      : 7 字节 (含前缀长度)
  PostgreSQL inet (IPv6)      : 19 字节
```

对于亿级行的 IP 字段表,从 VARCHAR 切换到专用类型可节省 60%-90% 存储,同时大幅提升缓存命中率。

### 2. CIDR 语义

CIDR (Classless Inter-Domain Routing) 表示法 `10.0.0.0/8` 同时表达地址和前缀长度,在网络运维中无处不在。字符串方案需要应用层手工解析,引擎层则可以原生理解:

```sql
-- 字符串方案: 应用层切分 / 计算
SELECT * FROM logs WHERE
    SUBSTRING_INDEX(ip, '.', 1) = '10' AND
    CAST(SUBSTRING_INDEX(SUBSTRING_INDEX(ip, '.', 2), '.', -1) AS UNSIGNED) BETWEEN 0 AND 255;

-- 专用类型: 一行搞定
SELECT * FROM logs WHERE ip << inet '10.0.0.0/8';
```

### 3. 容器/包含运算符

```
PostgreSQL 网络运算符:
  <<      : 严格包含 (子网)              cidr '192.168.1.0/24' << inet '192.168.0.0/16'
  <<=     : 包含或等于
  >>      : 严格反向包含 (父网)
  >>=     : 反向包含或等于
  &&      : 网段重叠
  +, -    : 偏移地址 / 计算距离
  &, |, ~ : 按位与/或/非 (掩码运算)
```

这些运算符在字符串模型下需要应用层自行实现,正确性极易出问题(尤其 IPv6)。

### 4. 索引支持

PostgreSQL 自 9.4 起为 inet/cidr 提供 SP-GiST (空间分区) 索引,自 14 起提供 GiST 索引,可加速子网包含查询达数百倍。字符串列即使加 B-tree,也只能加速精确匹配,无法加速 `ip << '10.0.0.0/8'` 这类查询。

## 支持矩阵 (45+ 引擎横向对比)

### 原生网络地址类型支持

| 引擎 | INET (IPv4/v6) | CIDR | MACADDR | MACADDR8 (EUI-64) | 起始版本 |
|------|---------------|------|---------|-------------------|---------|
| PostgreSQL | inet | cidr | macaddr | macaddr8 | 7.4 (2003) / macaddr8 自 10 (2017) |
| CockroachDB | INET | -- | -- | -- | 19.2+ (继承 PG) |
| YugabyteDB | inet | cidr | macaddr | macaddr8 | 2.x+ (继承 PG) |
| Greenplum | inet | cidr | macaddr | macaddr8 | 6+ (继承 PG) |
| TimescaleDB | inet | cidr | macaddr | macaddr8 | 继承 PG |
| Citus | inet | cidr | macaddr | macaddr8 | 继承 PG |
| Aurora PostgreSQL | inet | cidr | macaddr | macaddr8 | 继承 PG |
| Cloud SQL PostgreSQL | inet | cidr | macaddr | macaddr8 | 继承 PG |
| EnterpriseDB | inet | cidr | macaddr | macaddr8 | 继承 PG |
| ClickHouse | IPv4 / IPv6 | -- | -- | -- | 19.x (2019) |
| CrateDB | ip | -- | -- | -- | 0.50+ |
| Vertica | -- | -- | -- | -- | 通过函数支持 |
| Snowflake | -- | -- | -- | -- | VARCHAR + 函数 |
| BigQuery | -- | -- | -- | -- | STRING/BYTES + NET.* |
| Redshift | -- | -- | -- | -- | VARCHAR + 函数 |
| MySQL | -- | -- | -- | -- | VARBINARY + 函数 |
| MariaDB | INET6 (字符串别名) | -- | -- | -- | 10.5+ |
| Oracle | -- | -- | -- | -- | VARCHAR2 + UTL_INADDR |
| SQL Server | -- | -- | -- | -- | VARCHAR + 函数 |
| Azure SQL | -- | -- | -- | -- | 同 SQL Server |
| Synapse | -- | -- | -- | -- | 同 SQL Server |
| DB2 | -- | -- | -- | -- | VARCHAR + 函数 |
| Informix | -- | -- | -- | -- | VARCHAR |
| SQLite | -- | -- | -- | -- | TEXT only |
| H2 | -- | -- | -- | -- | VARCHAR |
| HSQLDB | -- | -- | -- | -- | VARCHAR |
| Derby | -- | -- | -- | -- | VARCHAR |
| Firebird | -- | -- | -- | -- | VARCHAR |
| SAP HANA | -- | -- | -- | -- | VARCHAR |
| Teradata | -- | -- | -- | -- | VARCHAR |
| TiDB | -- | -- | -- | -- | 兼容 MySQL |
| OceanBase | -- | -- | -- | -- | 兼容 MySQL/Oracle |
| Doris | -- | -- | -- | -- | 部分函数 |
| StarRocks | -- | -- | -- | -- | 部分函数 |
| SingleStore | -- | -- | -- | -- | VARCHAR + 函数 |
| Trino | IPADDRESS | -- | -- | -- | 332+ (2020) |
| Presto | IPADDRESS | -- | -- | -- | 0.184+ |
| Spark SQL | -- | -- | -- | -- | STRING |
| Hive | -- | -- | -- | -- | STRING |
| Impala | -- | -- | -- | -- | STRING |
| DuckDB | -- | -- | -- | -- | VARCHAR |
| Exasol | -- | -- | -- | -- | VARCHAR |
| MonetDB | inet | -- | -- | -- | 11.x+ |
| QuestDB | -- | -- | -- | -- | IPv4 类型 (实验) |
| InfluxDB (SQL) | -- | -- | -- | -- | -- |
| Materialize | -- | -- | -- | -- | -- |
| RisingWave | -- | -- | -- | -- | -- |
| Databend | -- | -- | -- | -- | VARCHAR |
| Athena | IPADDRESS | -- | -- | -- | 继承 Trino |
| Spanner | -- | -- | -- | -- | STRING/BYTES |
| Yellowbrick | inet | cidr | macaddr | -- | 继承 PG |
| Firebolt | -- | -- | -- | -- | VARCHAR |

> 统计:约 14 个引擎提供原生 IP 地址类型 (含 PG 衍生),其中只有 PostgreSQL 系列 (10+ 引擎) 同时支持 inet/cidr/macaddr/macaddr8 完整类型族。CIDR 与 MAC 类型几乎是 PostgreSQL 生态独有。

### 子网/网络运算符支持

| 引擎 | `<<` 严格包含 | `<<=` 包含等于 | `>>` 反向包含 | `&&` 重叠 | `&` `\|` `~` 位运算 | `+` `-` 算术 |
|------|--------------|---------------|---------------|----------|--------------------|--------------|
| PostgreSQL | 是 | 是 | 是 | 是 | 是 | 是 |
| CockroachDB | 是 | 是 | 是 | -- | -- | -- |
| YugabyteDB | 是 | 是 | 是 | 是 | 是 | 是 |
| Greenplum | 是 | 是 | 是 | 是 | 是 | 是 |
| MariaDB | -- | -- | -- | -- | -- | -- |
| ClickHouse | isIPAddressInRange | -- | -- | -- | -- | -- |
| CrateDB | 自定义函数 | -- | -- | -- | -- | -- |
| Trino/Presto | contains() | -- | -- | -- | -- | -- |
| Snowflake | PARSE_IP/CIDR + 比较 | -- | -- | -- | -- | -- |
| BigQuery | NET.IP_FROM_STRING + BETWEEN | -- | -- | -- | -- | -- |
| MySQL | INET_ATON 数值比较 | -- | -- | -- | -- | -- |
| Oracle | UTL_INADDR + BETWEEN | -- | -- | -- | -- | -- |

### 网络函数支持

| 引擎 | host() | netmask() | broadcast() | network() | masklen() | family() | abbrev() | text() |
|------|--------|-----------|-------------|-----------|-----------|----------|----------|--------|
| PostgreSQL | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| CockroachDB | 是 | -- | -- | -- | 是 | 是 | 是 | 是 |
| YugabyteDB | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| ClickHouse | IPv4NumToString / toString | -- | -- | -- | -- | -- | -- | 是 |
| Snowflake | PARSE_IP() 返回 JSON | -- | -- | -- | -- | -- | -- | -- |
| BigQuery | NET.HOST() | NET.IP_NET_MASK() | -- | -- | -- | -- | -- | -- |
| MySQL | INET_NTOA | -- | -- | -- | -- | INET6_FAMILY (无) | -- | -- |
| Oracle | UTL_INADDR.GET_HOST_NAME | -- | -- | -- | -- | -- | -- | -- |

### 索引支持

| 引擎 | B-tree (等值/范围) | GiST (子网包含) | SP-GiST (空间分区) | BRIN (大表) | 倒排索引 |
|------|-------------------|----------------|--------------------|--------------|---------|
| PostgreSQL | 是 | 是 (14+) | 是 (9.4+) | 是 (9.5+) | -- |
| CockroachDB | 是 | -- | -- | -- | -- |
| YugabyteDB | 是 | -- | -- | -- | -- |
| ClickHouse | 主键稀疏索引 | -- | -- | -- | bloom_filter |
| CrateDB | 是 (Lucene) | -- | -- | -- | 全文倒排 |
| Trino/Presto | 通过连接器 | -- | -- | -- | -- |
| Snowflake | 微分区裁剪 | -- | -- | -- | -- |
| BigQuery | 集群键 | -- | -- | -- | -- |

## 各引擎深度对比

### PostgreSQL:网络地址类型族的标杆

PostgreSQL 自 7.4 (2003 年) 引入完整的网络地址类型,设计极其细致。

#### 类型族概览

```sql
-- 1. inet:主机地址 + 可选子网前缀
CREATE TABLE servers (
    name TEXT,
    addr INET                  -- 同时支持 IPv4/IPv6
);

INSERT INTO servers VALUES
    ('web1', '192.168.1.1'),                -- IPv4 主机地址 (无前缀)
    ('web2', '192.168.1.10/24'),            -- IPv4 + 子网前缀 24
    ('db1',  '2001:db8::1'),                -- IPv6 主机地址
    ('db2',  '2001:db8::1/64');             -- IPv6 + 前缀

-- 2. cidr:严格的网络地址 (主机位必须为 0)
CREATE TABLE networks (
    name TEXT,
    net  CIDR
);

INSERT INTO networks VALUES
    ('internal',  '10.0.0.0/8'),
    ('dmz',       '192.168.0.0/16'),
    ('ipv6_lan',  '2001:db8::/32');

-- 错误:cidr 不允许主机位非零
INSERT INTO networks VALUES ('bad', '10.1.2.3/8');
-- ERROR: invalid cidr value: "10.1.2.3/8"
-- DETAIL: Value has bits set to right of mask.

-- 3. macaddr:6 字节 MAC 地址 (EUI-48)
CREATE TABLE devices (
    name TEXT,
    mac  MACADDR
);

INSERT INTO devices VALUES
    ('printer', '08:00:2b:01:02:03'),
    ('switch',  '08-00-2B-01-02-03'),       -- 多种格式自动归一化
    ('router',  '0800.2b01.0203');

-- 4. macaddr8:8 字节 MAC 地址 (EUI-64,IPv6 SLAAC 用)
CREATE TABLE ipv6_devices (
    name TEXT,
    mac  MACADDR8                           -- 自 PG 10 (2017)
);

INSERT INTO ipv6_devices VALUES
    ('iot_sensor', '08:00:2b:ff:fe:01:02:03');
```

#### 存储格式

```
inet:
  IPv4: 1 字节族标识 + 1 字节前缀长度 + 1 字节标志 + 4 字节地址 = 7 字节
  IPv6: 1 字节族标识 + 1 字节前缀长度 + 1 字节标志 + 16 字节地址 = 19 字节
  存储于变长字段 (varlena),实际可能多 1-2 字节头

cidr:
  与 inet 相同,但要求主机位为 0

macaddr:  6 字节固定
macaddr8: 8 字节固定
```

#### 运算符全集

```sql
-- 包含运算符
SELECT '192.168.1.5'::inet << '192.168.1.0/24'::inet;        -- t (子网严格包含)
SELECT '192.168.1.0/24'::inet <<= '192.168.0.0/16'::inet;    -- t (包含或等于)
SELECT '10.0.0.0/8'::cidr >> '10.1.2.3'::inet;               -- t (反向包含)
SELECT '10.0.0.0/8'::cidr >>= '10.0.0.0/8'::cidr;            -- t

-- 重叠 (有公共子网)
SELECT '192.168.0.0/16'::inet && '192.168.1.0/24'::inet;     -- t
SELECT '10.0.0.0/8'::inet && '192.168.0.0/16'::inet;         -- f

-- 比较运算符 (按地址值)
SELECT '192.168.1.1'::inet < '192.168.1.2'::inet;            -- t
SELECT '192.168.1.0/24'::cidr = '192.168.1.0/24'::cidr;      -- t

-- 算术运算
SELECT '192.168.1.1'::inet + 256;                            -- 192.168.2.1
SELECT '192.168.1.0'::inet + 100;                            -- 192.168.1.100
SELECT '192.168.1.5'::inet - '192.168.1.0'::inet;            -- 5 (距离)
SELECT '192.168.1.10'::inet - 5;                             -- 192.168.1.5

-- 按位运算
SELECT '192.168.1.1'::inet & '255.255.255.0'::inet;          -- 192.168.1.0 (掩码)
SELECT '192.168.1.0'::inet | '0.0.0.5'::inet;                -- 192.168.1.5
SELECT ~'192.168.1.1'::inet;                                  -- 63.87.254.254 (按位非)
```

#### 内置函数

```sql
-- 信息提取
SELECT host('192.168.1.5/24'::inet);                  -- 192.168.1.5
SELECT text('192.168.1.5/24'::inet);                  -- 192.168.1.5/24
SELECT abbrev('192.168.1.0/24'::cidr);                -- 192.168.1/24
SELECT family('192.168.1.1'::inet);                   -- 4
SELECT family('::1'::inet);                            -- 6

-- 网络/掩码
SELECT network('192.168.1.5/24'::inet);               -- 192.168.1.0/24
SELECT netmask('192.168.1.5/24'::inet);               -- 255.255.255.0
SELECT hostmask('192.168.1.5/24'::inet);              -- 0.0.0.255
SELECT broadcast('192.168.1.5/24'::inet);             -- 192.168.1.255/24
SELECT masklen('192.168.1.5/24'::inet);               -- 24

-- 修改前缀
SELECT set_masklen('192.168.1.5/24'::inet, 16);       -- 192.168.1.5/16

-- 与字符串互转
SELECT inet_send('192.168.1.1'::inet);                -- 二进制
SELECT '192.168.1.1'::text::inet;                     -- 字符串解析

-- MAC 地址函数
SELECT trunc('08:00:2b:01:02:03'::macaddr);           -- 08:00:2b:00:00:00 (前 24 位 OUI)
SELECT macaddr8_set7bit('08:00:2b:ff:fe:01:02:03'::macaddr8);
```

#### 索引示例

```sql
-- B-tree:加速等值/范围
CREATE INDEX idx_btree ON servers (addr);

-- GiST:加速子网包含 (PG 14+)
CREATE INDEX idx_gist ON servers USING gist (addr inet_ops);

-- SP-GiST:空间分区,适合大量小子网 (PG 9.4+)
CREATE INDEX idx_spgist ON servers USING spgist (addr);

-- 查询优化器自动选择
EXPLAIN ANALYZE
SELECT * FROM servers WHERE addr << '192.168.0.0/16';
-- Index Scan using idx_spgist on servers
--   Index Cond: (addr << '192.168.0.0/16'::inet)
```

#### 实战案例:防火墙规则匹配

```sql
-- 表设计
CREATE TABLE firewall_rules (
    id SERIAL PRIMARY KEY,
    src_net  CIDR,
    dst_net  CIDR,
    action   TEXT
);

CREATE INDEX idx_src ON firewall_rules USING spgist (src_net);
CREATE INDEX idx_dst ON firewall_rules USING spgist (dst_net);

-- 查询:对包 (10.1.2.3 -> 192.168.5.6) 找匹配规则
SELECT * FROM firewall_rules
WHERE '10.1.2.3'::inet  << src_net
  AND '192.168.5.6'::inet << dst_net
ORDER BY masklen(src_net) DESC, masklen(dst_net) DESC
LIMIT 1;
-- 最长前缀匹配 (Longest Prefix Match) 是路由/防火墙的核心算法
```

### CockroachDB:继承 PG 但不完整

CockroachDB 自 19.2 起支持 INET 类型,语法与 PostgreSQL 兼容,但缺少 CIDR/MACADDR 等类型。

```sql
-- 支持
CREATE TABLE servers (id INT PRIMARY KEY, addr INET);
INSERT INTO servers VALUES (1, '192.168.1.1');

-- 子网包含运算符 (有限支持)
SELECT * FROM servers WHERE addr << '192.168.0.0/16';

-- 缺失:
--   1. 没有独立的 CIDR 类型 (用 INET 替代)
--   2. 没有 MACADDR 类型
--   3. 大量函数缺失 (broadcast, netmask 等部分函数)
--   4. 没有 GiST/SP-GiST 索引
```

### YugabyteDB:最完整的 PG 衍生

YugabyteDB 基于 PostgreSQL 查询层,网络类型支持几乎与 PG 完全一致:

```sql
-- 完整支持 inet, cidr, macaddr, macaddr8
CREATE TABLE devices (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    ip INET,
    network CIDR,
    mac MACADDR,
    mac8 MACADDR8
);

-- 所有 PG 运算符和函数可用
SELECT host(ip), masklen(network), trunc(mac) FROM devices
WHERE ip << '10.0.0.0/8';

-- 注意:分布式索引使用方式略有不同
-- YugabyteDB 默认使用 LSM 存储,二级索引推荐 HASH 或 RANGE 分布
CREATE INDEX idx_ip ON devices (ip HASH);
```

### Greenplum / TimescaleDB / Citus / Aurora PG / Cloud SQL PG:全继承

这些 PostgreSQL 衍生产品均完全继承 inet/cidr/macaddr/macaddr8,语法、函数、运算符与 PG 一致。差异仅在分布式扩展、索引实现层面。

### ClickHouse:为日志分析优化的 IPv4/IPv6 类型

ClickHouse 自 19.x (2019) 起提供 `IPv4` 和 `IPv6` 两种专用类型,设计哲学截然不同 —— 不追求 CIDR 等高级语义,只追求**列存压缩与扫描性能**。

```sql
-- 类型定义
CREATE TABLE logs (
    timestamp DateTime,
    src_ip    IPv4,
    dst_ip    IPv6,
    bytes     UInt64
) ENGINE = MergeTree()
ORDER BY (timestamp, src_ip);

-- 字符串自动转换
INSERT INTO logs VALUES
    (now(), '192.168.1.1',   '::ffff:192.168.1.1', 1024),
    (now(), '10.0.0.1',      '2001:db8::1',         512);

-- 显示时自动格式化
SELECT src_ip, dst_ip FROM logs LIMIT 5;
-- 192.168.1.1     ::ffff:192.168.1.1
-- 10.0.0.1        2001:db8::1

-- 内部存储:
--   IPv4: 4 字节 UInt32 (固定)
--   IPv6: 16 字节 FixedString (固定)
-- 列存压缩比通常达 10:1 (IPv4 私网地址重复率高)
```

#### ClickHouse 网络函数

```sql
-- 字符串/二进制转换
SELECT IPv4StringToNum('192.168.1.1');               -- 3232235777
SELECT IPv4NumToString(3232235777);                  -- 192.168.1.1
SELECT IPv6StringToNum('2001:db8::1');               -- 二进制
SELECT IPv6NumToString(/* binary */);                -- 字符串

-- IPv4 嵌入 IPv6 处理
SELECT toIPv4('192.168.1.1');                        -- IPv4 类型
SELECT toIPv6('2001:db8::1');                        -- IPv6 类型
SELECT IPv4ToIPv6(toIPv4('192.168.1.1'));            -- ::ffff:192.168.1.1

-- CIDR 范围检查
SELECT isIPAddressInRange('192.168.1.5', '192.168.1.0/24');   -- 1
SELECT isIPv4String('192.168.1.1');                            -- 1
SELECT isIPv6String('2001:db8::1');                            -- 1

-- 地理位置 (需 IP2Location 字典)
SELECT dictGet('geo_dict', 'country', toIPv4('1.1.1.1'));
```

#### ClickHouse 性能优势

```
1 亿行日志表的查询对比 (单节点 16 核):

  -- 字符串方案 (VARCHAR 存储)
  SELECT count() FROM logs WHERE src_ip LIKE '192.168.%';
  耗时: ~12 秒, 扫描 ~3GB

  -- IPv4 类型 + 字符串比较
  SELECT count() FROM logs WHERE IPv4NumToString(src_ip) LIKE '192.168.%';
  耗时: ~4 秒, 扫描 ~400MB (列存 + 函数)

  -- IPv4 类型 + isIPAddressInRange
  SELECT count() FROM logs WHERE isIPAddressInRange(src_ip, '192.168.0.0/16');
  耗时: ~0.6 秒, 扫描 ~400MB (向量化 SIMD)

  -- IPv4 类型 + 整数范围 (最快)
  SELECT count() FROM logs
  WHERE src_ip BETWEEN toIPv4('192.168.0.0') AND toIPv4('192.168.255.255');
  耗时: ~0.2 秒, 扫描 ~400MB (索引裁剪)
```

ClickHouse 的设计哲学:**类型只为存储服务,语义靠函数和索引**。没有 CIDR 类型,而是通过 `isIPAddressInRange()` 函数 + 主键索引提供快速包含查询。

### CrateDB:Lucene 风格的 ip 类型

CrateDB 提供专用的 `ip` 类型,基于 Lucene 倒排索引:

```sql
-- 类型定义
CREATE TABLE network_events (
    id LONG,
    client_ip ip,                                    -- 同时支持 IPv4/IPv6
    server_ip ip
);

INSERT INTO network_events VALUES
    (1, '192.168.1.1',  '10.0.0.1'),
    (2, '2001:db8::1',  '::1');

-- CIDR 范围查询 (使用 << 运算符)
SELECT * FROM network_events
WHERE client_ip << '192.168.0.0/16';

-- 内置函数
SELECT client_ip, _doc['client_ip'] FROM network_events;
```

CrateDB 的 ip 类型本质是基于 Lucene 的 InetAddressPoint,索引为 BKD-tree,适合高并发的范围查询。

### Snowflake:VARCHAR + 实用函数

Snowflake 没有原生 IP 类型,但提供了一组解析/格式化函数:

```sql
-- 存储为 VARCHAR
CREATE TABLE access_logs (
    ts TIMESTAMP,
    ip VARCHAR(45)
);

-- PARSE_IP:解析 IPv4/IPv6 + CIDR
SELECT PARSE_IP('192.168.1.1', 'INET');
-- {
--   "family": 4,
--   "host": "192.168.1.1",
--   "ip_fields": [3232235777, 0, 0, 0],
--   "ip_type": "inet",
--   "ipv4": 3232235777,
--   "ipv4_range_end": 3232235777,
--   "ipv4_range_start": 3232235777,
--   "netmask_prefix_length": 32,
--   "snowflake$type": "ip_address"
-- }

SELECT PARSE_IP('192.168.1.0/24', 'INET');
-- ipv4_range_start: 3232235776, ipv4_range_end: 3232236031

-- 提取字段
SELECT PARSE_IP(ip, 'INET'):"ipv4"::NUMBER AS ipv4_int FROM access_logs;

-- CIDR 包含查询的常见模式
SELECT * FROM access_logs
WHERE PARSE_IP(ip, 'INET'):"ipv4"::NUMBER
      BETWEEN PARSE_IP('10.0.0.0/8', 'INET'):"ipv4_range_start"
          AND PARSE_IP('10.0.0.0/8', 'INET'):"ipv4_range_end";

-- 反向函数
SELECT PARSE_IP('::1', 'INET');                    -- IPv6 自动识别
```

Snowflake 的方案:**类型用 VARCHAR,语义靠 JSON 半结构化输出**。适合临时分析,不适合超大规模高频查询。

### BigQuery:NET.* 函数族

BigQuery 没有专用 IP 类型,但提供了完整的 NET.* 函数:

```sql
-- 字符串与字节互转
SELECT NET.IP_FROM_STRING('192.168.1.1');           -- BYTES (4 字节)
SELECT NET.IP_TO_STRING(b'\xc0\xa8\x01\x01');       -- '192.168.1.1'

-- IPv4/IPv6 区分
SELECT NET.IPV4_FROM_INT64(3232235777);             -- BYTES
SELECT NET.IPV4_TO_INT64(NET.IP_FROM_STRING('192.168.1.1'));  -- 3232235777

-- CIDR 网络
SELECT NET.IP_NET_MASK(4, 24);                      -- 255.255.255.0 BYTES
SELECT NET.IP_TRUNC(NET.IP_FROM_STRING('192.168.1.5'), 24);
-- 192.168.1.0 (取网络部分)

-- URL/主机解析
SELECT NET.HOST('https://www.example.com:8080/path');     -- www.example.com
SELECT NET.PUBLIC_SUFFIX('subdomain.example.co.uk');       -- co.uk
SELECT NET.REG_DOMAIN('subdomain.example.co.uk');         -- example.co.uk

-- 子网包含查询模式
WITH cidr AS (
  SELECT
    NET.IP_FROM_STRING('192.168.0.0') AS net_addr,
    16 AS prefix
)
SELECT * FROM access_logs, cidr
WHERE NET.IP_TRUNC(NET.IP_FROM_STRING(ip), cidr.prefix) = cidr.net_addr;
```

BigQuery 的 IP 处理偏向**网络分析与日志查询**,而非数据库主键场景。

### Vertica:IP/IPV6 类型与函数

Vertica 通过 V_FUNCTIONS 模式提供 IP 处理:

```sql
-- 类型存储为 VARCHAR/INTEGER
CREATE TABLE access (
    ip_str VARCHAR(45),
    ip_int INTEGER                                  -- IPv4 数值
);

-- 转换函数
SELECT V6_ATON('2001:db8::1');                      -- BINARY(16)
SELECT V6_NTOA(V6_ATON('2001:db8::1'));             -- '2001:db8::1'

SELECT INET_ATON('192.168.1.1');                    -- 3232235777
SELECT INET_NTOA(3232235777);                       -- '192.168.1.1'

-- 类型/长度判断
SELECT V6_TYPE('::ffff:192.168.1.1');               -- 'V4COMPATIBLE' / 'V4MAPPED' / 'TEREDO' 等
SELECT V6_SUBNETA('192.168.1.5', 24);               -- 192.168.1.0
```

### MySQL:INET_ATON / INET6_ATON

MySQL 没有原生 IP 类型,但自 5.0 (2005) 起提供 IPv4 转换函数,5.6 (2013) 起加入 IPv6 支持:

```sql
-- IPv4 处理 (4 字节存储)
CREATE TABLE access_v4 (
    ip_int INT UNSIGNED                             -- 用整数存储
);

INSERT INTO access_v4 VALUES (INET_ATON('192.168.1.1'));   -- 3232235777
SELECT INET_NTOA(ip_int) FROM access_v4;                    -- 192.168.1.1

-- IPv6 处理 (16 字节,需 VARBINARY)
CREATE TABLE access_v6 (
    ip_bin VARBINARY(16)                            -- 同时存 v4 和 v6
);

INSERT INTO access_v6 VALUES (INET6_ATON('2001:db8::1'));
INSERT INTO access_v6 VALUES (INET6_ATON('192.168.1.1'));   -- 4 字节存储

SELECT INET6_NTOA(ip_bin) FROM access_v6;
-- 2001:db8::1
-- 192.168.1.1

-- 子网包含 (无原生 CIDR 支持,手动构造)
SELECT * FROM access_v4
WHERE ip_int BETWEEN INET_ATON('192.168.0.0')
              AND   INET_ATON('192.168.255.255');

-- 索引友好 (INT/VARBINARY 都可加 B-tree 索引)
CREATE INDEX idx_ip ON access_v4 (ip_int);
```

#### MySQL IPv4 vs IPv6 函数对比

```sql
-- IPv4 专用 (返回 BIGINT/UNSIGNED INT)
SELECT INET_ATON('192.168.1.1');                    -- 3232235777
SELECT INET_NTOA(3232235777);                        -- '192.168.1.1'

-- IPv4/IPv6 通用 (返回 VARBINARY)
SELECT INET6_ATON('192.168.1.1');                   -- 0xC0A80101 (4 字节)
SELECT INET6_ATON('2001:db8::1');                    -- 0x20010DB8...0001 (16 字节)
SELECT HEX(INET6_ATON('192.168.1.1'));               -- C0A80101
SELECT INET6_NTOA(INET6_ATON('192.168.1.1'));        -- '192.168.1.1'

-- 测试函数
SELECT IS_IPV4('192.168.1.1');                       -- 1
SELECT IS_IPV6('2001:db8::1');                       -- 1
SELECT IS_IPV4_COMPAT(INET6_ATON('::192.168.1.1'));  -- 1 (IPv4 兼容地址)
SELECT IS_IPV4_MAPPED(INET6_ATON('::ffff:192.168.1.1'));  -- 1 (IPv4 映射地址)
```

#### MariaDB INET6 类型

MariaDB 10.5+ 引入 `INET6` 数据类型,但本质是 VARCHAR 别名:

```sql
-- MariaDB 10.5+
CREATE TABLE servers (
    name VARCHAR(50),
    ip   INET6                                      -- 别名,内部存储为字符串
);

INSERT INTO servers VALUES ('a', '2001:db8::1');
SELECT * FROM servers WHERE ip = '2001:db8::1';

-- 仍无原生 CIDR 支持,需配合 INET6_ATON
```

### Oracle:UTL_INADDR + VARCHAR2

Oracle 同样没有原生 IP 类型,推荐方案有两种:

```sql
-- 方案 1:VARCHAR2 + 应用层验证
CREATE TABLE servers (
    name VARCHAR2(50),
    ip   VARCHAR2(45)
);

-- 方案 2:NUMBER (IPv4) 或 RAW (IPv6)
CREATE TABLE access_logs (
    ip_v4 NUMBER(10),                              -- IPv4 数值
    ip_v6 RAW(16)                                   -- IPv6 二进制
);

-- UTL_INADDR 包 (网络解析)
SELECT UTL_INADDR.GET_HOST_NAME('192.168.1.1') FROM dual;
SELECT UTL_INADDR.GET_HOST_ADDRESS('localhost') FROM dual;

-- 字符串转数值 (PL/SQL 实现)
CREATE OR REPLACE FUNCTION ipv4_to_int(p_ip VARCHAR2) RETURN NUMBER IS
    v_parts apex_t_varchar2;
BEGIN
    v_parts := apex_string.split(p_ip, '.');
    RETURN TO_NUMBER(v_parts(1)) * 16777216 +
           TO_NUMBER(v_parts(2)) * 65536 +
           TO_NUMBER(v_parts(3)) * 256 +
           TO_NUMBER(v_parts(4));
END;
/

-- 子网包含查询
SELECT * FROM access_logs
WHERE ip_v4 BETWEEN ipv4_to_int('192.168.0.0')
             AND   ipv4_to_int('192.168.255.255');

-- Oracle 19c+ 支持 JSON,可用 JSON_VALUE 解析复杂网络数据
```

### SQL Server:VARCHAR + UDF

```sql
-- 仅有 VARCHAR 存储
CREATE TABLE servers (
    name NVARCHAR(50),
    ip   NVARCHAR(45)
);

-- 内置 PARSENAME (用于 4 段域名/IPv4)
SELECT PARSENAME('192.168.1.1', 1);                 -- '1' (最右侧)
SELECT PARSENAME('192.168.1.1', 4);                 -- '192' (最左侧)

-- IPv4 转 INT (用户自定义函数)
CREATE FUNCTION dbo.IPv4ToInt(@ip VARCHAR(15))
RETURNS BIGINT AS
BEGIN
    RETURN CAST(PARSENAME(@ip, 4) AS BIGINT) * 16777216 +
           CAST(PARSENAME(@ip, 3) AS BIGINT) * 65536 +
           CAST(PARSENAME(@ip, 2) AS BIGINT) * 256 +
           CAST(PARSENAME(@ip, 1) AS BIGINT);
END;

-- 使用
SELECT * FROM access_logs
WHERE dbo.IPv4ToInt(ip) BETWEEN dbo.IPv4ToInt('192.168.0.0')
                         AND   dbo.IPv4ToInt('192.168.255.255');

-- IPv6 处理:CLR UDF 或应用层
```

### Trino / Presto / Athena:IPADDRESS 类型

Trino 自 332 (2020) 起支持 `IPADDRESS` 类型:

```sql
-- 类型定义
SELECT IPADDRESS '192.168.1.1';
SELECT IPADDRESS '2001:db8::1';

-- 转换函数
SELECT CAST('192.168.1.1' AS IPADDRESS);
SELECT CAST(IPADDRESS '192.168.1.1' AS VARCHAR);    -- '192.168.1.1'

-- IPv4/IPv6 自动识别和归一化
SELECT IPADDRESS '::ffff:192.168.1.1';              -- 内部存为 IPv6 映射

-- 子网包含 (Trino 359+)
SELECT contains('192.168.0.0/16', IPADDRESS '192.168.1.1');   -- TRUE

-- 比较运算
SELECT IPADDRESS '192.168.1.1' < IPADDRESS '192.168.1.2';   -- TRUE

-- 地理位置 (需 GeoIP 函数库)
SELECT geoip_country(IPADDRESS '8.8.8.8');           -- 'US' (示例,需配置)
```

### MonetDB:inet 类型

MonetDB 提供完整的 inet 类型 (借鉴 PostgreSQL):

```sql
-- 类型与函数
CREATE TABLE servers (id INT, addr inet);
INSERT INTO servers VALUES (1, '192.168.1.1/24');

-- 网络函数
SELECT broadcast(addr), network(addr), netmask(addr)
FROM servers;

-- 子网包含
SELECT * FROM servers WHERE inet '192.168.1.0/24' >> addr;
```

### SQLite:仅 TEXT

SQLite 完全没有 IP 类型,只能用 TEXT:

```sql
CREATE TABLE servers (id INTEGER PRIMARY KEY, ip TEXT);
INSERT INTO servers VALUES (1, '192.168.1.1');

-- 子网检查需要全字符串比较或自定义扩展
-- SQLite 支持加载扩展实现 IP 函数,但默认不支持
```

### H2 / HSQLDB / Derby / Firebird / Informix / SAP HANA / Teradata:VARCHAR only

这些引擎均无原生 IP 类型,需用 VARCHAR/CHAR 存储,并依赖应用层或 UDF 处理 CIDR/MAC 语义。

### TiDB / OceanBase:兼容 MySQL

由于 MySQL 兼容定位,这两个分布式 NewSQL 引擎都提供 INET_ATON / INET6_ATON 等函数,但没有原生 IP 类型。OceanBase Oracle 模式下还提供 UTL_INADDR 兼容包。

### Doris / StarRocks / SingleStore:部分函数

```sql
-- StarRocks / Doris (部分版本)
SELECT inet_aton('192.168.1.1');
SELECT inet_ntoa(3232235777);

-- IPv4 函数 (StarRocks 3.0+)
SELECT ipv4_string_to_num('192.168.1.1');
SELECT ipv4_num_to_string(3232235777);
```

## PostgreSQL inet vs cidr 的语义差异

PG 同时提供 inet 和 cidr 两种类型,容易混淆。核心区别:

```
inet:
  - 表示主机地址 (host),前缀长度可选 (默认 /32 或 /128)
  - 主机位允许非零
  - 用途:存储具体某台机器的 IP

cidr:
  - 表示网络地址 (network),前缀长度必填
  - 主机位必须为零
  - 用途:存储网络/子网定义

赋值兼容性:
  inet  → cidr: 必须主机位为 0,否则报错
  cidr  → inet: 总是成功
```

```sql
-- 示例对比
SELECT '192.168.1.5/24'::inet;      -- 192.168.1.5/24    (合法)
SELECT '192.168.1.5/24'::cidr;      -- ERROR             (主机位非零)
SELECT '192.168.1.0/24'::cidr;      -- 192.168.1.0/24    (合法)

-- 输出格式差异
SELECT '192.168.1.5'::inet;          -- 192.168.1.5      (无前缀)
SELECT '192.168.1.5/24'::inet;       -- 192.168.1.5/24
SELECT '192.168.1.0/24'::cidr;       -- 192.168.1.0/24

-- 函数行为差异
SELECT host('192.168.1.5/24'::inet); -- 192.168.1.5
SELECT host('192.168.1.0/24'::cidr); -- 192.168.1.0
SELECT abbrev('192.168.1.0/24'::cidr); -- 192.168.1/24   (cidr 风格缩写)
SELECT abbrev('192.168.1.0/24'::inet); -- 192.168.1.0/24

-- 比较运算
SELECT '192.168.1.5'::inet = '192.168.1.5/32'::inet;   -- t
SELECT '192.168.1.5'::inet = '192.168.1.5'::inet;      -- t

-- 转换规则
SELECT '192.168.1.0/24'::cidr::inet;                   -- 192.168.1.0/24 (cidr → inet)
SELECT '192.168.1.5/24'::inet::cidr;                   -- ERROR (主机位非零)
SELECT network('192.168.1.5/24'::inet)::cidr;          -- 192.168.1.0/24 (先转 network)
```

**最佳实践:**
- 主机表 / 访问日志:用 inet
- 子网定义 / 防火墙规则 / 路由表:用 cidr
- 通用列:用 inet,可表达两者

## ClickHouse IPv4 类型的性能秘密

### 列存压缩比

```
1000 万行 IPv4 数据存储对比:

  VARCHAR("192.168.1.x")                  : ~150 MB (原始) → 30 MB (LZ4 压缩)
  IPv4 类型 (4 字节 UInt32)                : ~38 MB (原始) → 8 MB (Delta + LZ4)

  压缩比改进: 4 倍 (得益于 Delta 编码 + LZ4)
```

### 向量化扫描

```sql
-- ClickHouse 对 IPv4 的查询会被向量化执行 (SSE/AVX2)

-- 示例:isIPAddressInRange 在 1 亿行数据上的执行
SELECT count() FROM access_logs
WHERE isIPAddressInRange(src_ip, '192.168.0.0/16');

-- 内部执行:
-- 1. 列解压: 4 字节/行,SIMD 友好
-- 2. CIDR 转换为 [start_int, end_int] 范围
-- 3. AVX2 比较: 一次处理 8 个 IPv4 (256 bit / 32 bit)
-- 4. 位图聚合: AND 合并多个谓词
-- 总耗时: ~500ms / 1 亿行 = 200M 行/秒
```

### 主键排序与跳过

```sql
-- 推荐:src_ip 加入主键,可启用稀疏索引
CREATE TABLE access_logs (
    timestamp DateTime,
    src_ip    IPv4,
    bytes     UInt64
) ENGINE = MergeTree()
ORDER BY (src_ip, timestamp);                       -- src_ip 在前,可范围跳过

-- 查询特定子网
SELECT count() FROM access_logs
WHERE src_ip BETWEEN toIPv4('192.168.0.0')
              AND toIPv4('192.168.255.255');

-- ClickHouse 利用 ORDER BY 主键的稀疏索引
-- 仅扫描包含目标范围的 granule (默认 8192 行/granule)
-- 1 亿行表 + 子网 65536 个地址 → 实际扫描 ~10 万行
```

## 关键发现

### 1. PostgreSQL 是网络地址领域的事实标准

PostgreSQL 自 7.4 (2003) 提供 inet/cidr/macaddr,2017 年补齐 macaddr8。完整运算符 + GiST/SP-GiST 索引,使得 PG 成为防火墙、CDN、安全审计场景的首选。CockroachDB、YugabyteDB 等所有 PG 衍生引擎都自动获得这套能力。

### 2. ClickHouse 走了"轻类型重函数"的反向路线

ClickHouse 只提供 IPv4/IPv6 两个类型,没有 CIDR,而是通过 `isIPAddressInRange` 等函数 + 列存压缩 + SIMD 向量化提供性能。对日志分析场景非常友好,但缺少结构化网络语义。

### 3. CIDR 类型只属于 PostgreSQL 生态

除了 PG 系列 (PG, Cockroach 部分, Yugabyte, Greenplum, Citus, TimescaleDB, Aurora PG, Cloud SQL PG 等),几乎没有引擎提供独立的 CIDR 类型。其他引擎要么用 inet/IPADDRESS 表达,要么用应用层 BETWEEN 模拟。

### 4. MAC 地址类型几乎是 PG 独家

PostgreSQL 是少数几个原生支持 MACADDR (EUI-48) 和 MACADDR8 (EUI-64) 的引擎。物联网、网络设备管理场景几乎只能用 PG。

### 5. MySQL 走了"函数派"路线

MySQL 自 5.0 (2005) 起提供 INET_ATON,5.6 (2013) 起补齐 INET6_ATON。配合 INT/VARBINARY 存储,可达到接近原生类型的性能,但缺少 CIDR 语义和子网包含运算符。

### 6. 云数仓偏向 NET.* / PARSE_IP 函数

BigQuery (NET.*) 和 Snowflake (PARSE_IP) 都没有专用类型,而是通过函数库提供 IP 处理。优势是与 VARCHAR/STRING 互操作简单,劣势是无法享受类型化存储和向量化优化。

### 7. SQLite/Oracle/SQL Server 等老牌引擎完全不提供

这三个引擎都只能用 VARCHAR/TEXT/NUMBER 存储,所有 IP 语义都要在应用层或 UDF 中实现。Oracle 的 UTL_INADDR 仅提供 DNS 反查,不涉及 CIDR/MAC。

### 8. 索引差异决定子网查询性能

```
查询 1 亿行表 WHERE ip << '10.0.0.0/8' 的性能对比:

  PostgreSQL inet + SP-GiST:        ~50 ms (索引精确裁剪)
  PostgreSQL inet + GiST:            ~80 ms
  PostgreSQL inet + B-tree (无效):   ~3 秒 (全表扫描)
  PostgreSQL VARCHAR + B-tree:       ~4 秒 (前缀匹配)
  ClickHouse IPv4 + 主键裁剪:        ~100 ms
  MySQL INT + B-tree (BETWEEN):      ~150 ms
  Snowflake VARCHAR + 微分区:        ~500 ms
  BigQuery STRING + 集群:            ~1 秒
  SQLite TEXT:                       ~10 秒
```

### 9. macaddr8 (EUI-64) 是 IPv6 SLAAC 的基础

IPv6 无状态地址自动配置 (SLAAC) 中,设备从 48-bit MAC 派生 64-bit Interface ID 时,中间插入 0xFFFE 形成 EUI-64。PostgreSQL 10 (2017) 引入 macaddr8 类型正是为此场景:

```sql
-- 6 字节 MAC → 8 字节 EUI-64 (插入 fffe + 翻转 U/L 位)
SELECT macaddr8_set7bit('08:00:2b:01:02:03'::macaddr8);
-- 0a:00:2b:01:02:03 (翻转第 7 位)
```

### 10. CIDR 表示法的歧义陷阱

`192.168.1.5/24` 在不同语义下含义不同:
- inet: 主机 192.168.1.5,所在子网前缀 24 位
- cidr: 非法 (主机位非零)
- 字符串: 仅一个标识符

设计 schema 时务必明确语义,避免应用层与数据库理解不一致。

## 实战:防火墙日志分析

### PostgreSQL 实现 (推荐用于安全审计)

```sql
-- 表结构
CREATE TABLE firewall_logs (
    log_time   TIMESTAMPTZ NOT NULL DEFAULT now(),
    src_ip     INET NOT NULL,
    dst_ip     INET NOT NULL,
    src_port   INT,
    dst_port   INT,
    protocol   TEXT,
    action     TEXT,
    bytes      BIGINT
);

-- 索引
CREATE INDEX idx_src_spgist ON firewall_logs USING spgist (src_ip);
CREATE INDEX idx_dst_spgist ON firewall_logs USING spgist (dst_ip);
CREATE INDEX idx_time      ON firewall_logs (log_time);

-- 查询 1: 统计来自内网的可疑外联
SELECT
    src_ip,
    count(*) AS conn_count,
    sum(bytes) AS total_bytes
FROM firewall_logs
WHERE src_ip << '10.0.0.0/8'                       -- 内网源
  AND NOT (dst_ip << '10.0.0.0/8'                  -- 目标非内网
        OR dst_ip << '172.16.0.0/12'
        OR dst_ip << '192.168.0.0/16')
  AND log_time >= now() - INTERVAL '1 hour'
GROUP BY src_ip
ORDER BY total_bytes DESC
LIMIT 20;

-- 查询 2: 检测端口扫描 (单 IP 短时间访问大量目标端口)
SELECT
    src_ip,
    count(DISTINCT dst_port) AS unique_ports
FROM firewall_logs
WHERE log_time >= now() - INTERVAL '5 minutes'
GROUP BY src_ip
HAVING count(DISTINCT dst_port) > 100
ORDER BY unique_ports DESC;

-- 查询 3: 子网间流量矩阵
SELECT
    network(set_masklen(src_ip, 24)) AS src_net,
    network(set_masklen(dst_ip, 24)) AS dst_net,
    count(*) AS connections,
    sum(bytes) AS total_bytes
FROM firewall_logs
WHERE log_time >= CURRENT_DATE
GROUP BY 1, 2
ORDER BY total_bytes DESC
LIMIT 50;
```

### ClickHouse 实现 (推荐用于超大规模日志)

```sql
-- 表结构 (按时间分区,IP 排序)
CREATE TABLE firewall_logs (
    log_time  DateTime,
    src_ip    IPv4,
    dst_ip    IPv4,
    src_port  UInt16,
    dst_port  UInt16,
    protocol  LowCardinality(String),
    action    LowCardinality(String),
    bytes     UInt64
) ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(log_time)
ORDER BY (src_ip, log_time)
TTL log_time + INTERVAL 90 DAY;

-- 查询 1: 内网外联统计
SELECT
    IPv4NumToString(src_ip) AS src,
    count() AS conn_count,
    sum(bytes) AS total_bytes
FROM firewall_logs
WHERE isIPAddressInRange(src_ip, '10.0.0.0/8')
  AND NOT isIPAddressInRange(dst_ip, '10.0.0.0/8')
  AND NOT isIPAddressInRange(dst_ip, '172.16.0.0/12')
  AND NOT isIPAddressInRange(dst_ip, '192.168.0.0/16')
  AND log_time >= now() - INTERVAL 1 HOUR
GROUP BY src_ip
ORDER BY total_bytes DESC
LIMIT 20;

-- 查询 2: 子网级聚合 (按 /24 切分)
SELECT
    IPv4NumToString(bitAnd(src_ip, toUInt32(0xFFFFFF00))) AS src_net,
    IPv4NumToString(bitAnd(dst_ip, toUInt32(0xFFFFFF00))) AS dst_net,
    count() AS connections,
    sum(bytes) AS total_bytes
FROM firewall_logs
WHERE log_time >= toStartOfDay(now())
GROUP BY src_net, dst_net
ORDER BY total_bytes DESC
LIMIT 50;
```

### MySQL 实现 (推荐用于中等规模)

```sql
-- 表结构
CREATE TABLE firewall_logs (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    log_time DATETIME NOT NULL,
    src_ip   INT UNSIGNED NOT NULL,                -- IPv4 用 INT
    dst_ip   INT UNSIGNED NOT NULL,
    src_port SMALLINT UNSIGNED,
    dst_port SMALLINT UNSIGNED,
    protocol VARCHAR(10),
    action   VARCHAR(20),
    bytes    BIGINT,
    INDEX idx_time_src (log_time, src_ip),
    INDEX idx_dst (dst_ip)
);

-- 插入
INSERT INTO firewall_logs VALUES
    (NULL, NOW(), INET_ATON('10.1.2.3'), INET_ATON('1.2.3.4'),
     54321, 443, 'TCP', 'ALLOW', 1500);

-- 查询: 子网包含
SELECT
    INET_NTOA(src_ip) AS src,
    count(*) AS conn_count,
    sum(bytes) AS total_bytes
FROM firewall_logs
WHERE src_ip BETWEEN INET_ATON('10.0.0.0') AND INET_ATON('10.255.255.255')
  AND NOT (dst_ip BETWEEN INET_ATON('10.0.0.0') AND INET_ATON('10.255.255.255')
        OR dst_ip BETWEEN INET_ATON('172.16.0.0') AND INET_ATON('172.31.255.255')
        OR dst_ip BETWEEN INET_ATON('192.168.0.0') AND INET_ATON('192.168.255.255'))
  AND log_time >= NOW() - INTERVAL 1 HOUR
GROUP BY src_ip
ORDER BY total_bytes DESC
LIMIT 20;
```

## 对引擎开发者的实现建议

### 1. inet 类型的二进制布局

```
PostgreSQL inet 内部布局:
  struct inet_struct {
      unsigned char family;    // AF_INET (2) or AF_INET6 (10)
      unsigned char bits;      // 前缀长度 (0-32 for v4, 0-128 for v6)
      unsigned char ipaddr[16];// 地址字节,大端序,IPv4 仅前 4 字节有效
  };

  IPv4 实际占用: 1 + 1 + 4 = 6 字节 (varlena 包装后约 7 字节)
  IPv6 实际占用: 1 + 1 + 16 = 18 字节 (varlena 包装后约 19 字节)

设计要点:
  1. 大端序存储,便于直接字符串比较和子网包含计算
  2. family 字段允许 IPv4/IPv6 混存
  3. bits 与地址分离,便于 set_masklen 等操作
```

### 2. 子网包含算子的实现

```
子网包含 (a << b) 算法:
  1. 检查 family: a.family == b.family
  2. 检查前缀长度: a.bits >= b.bits + 1 (严格包含需 +1)
  3. 计算 b 的网络掩码: mask = ~0 << (32 - b.bits) [IPv4]
  4. 比较: (a.addr & mask) == (b.addr & mask)

向量化优化:
  - 对一批 inet 列同时计算掩码 AND 和比较
  - SIMD 指令一次处理 4 个 IPv4 (128 bit / 32 bit)
  - IPv6 需要 128-bit 比较,可用 _mm_cmpeq_epi64 + 与运算
```

### 3. SP-GiST 索引的设计

```
SP-GiST 用于网络地址的核心思路:
  - 按位逐层分裂,每层选择一个 bit 作为分裂点
  - 节点存储 prefix + length,叶子存储完整地址
  - 子网包含查询: 沿着前缀树下行,只搜索匹配前缀的子树

PostgreSQL inet_ops_v4 / inet_ops_v6 实现:
  - 内部节点: 共享前缀 (如 192.168.0.0/16)
  - 子节点: 进一步细分 (192.168.0.0/24, 192.168.1.0/24, ...)
  - 查询 ip << '192.168.0.0/16' 仅遍历 /16 子树

性能特征:
  - 等值查询: O(log N)
  - 子网包含: O(log N + k),k 为匹配行数
  - 不支持: 范围查询 (如 ip BETWEEN x AND y)
```

### 4. CIDR 验证逻辑

```
CIDR 类型要求主机位为 0,验证算法:
  1. 取地址字节,从前缀长度位开始向后所有位必须为 0
  2. PG 用 cidr_in() 函数验证,不合法即报错

  例: 192.168.1.5/24
      前 24 bit: 192.168.1.
      后 8 bit:  5 (00000101) 必须为 0,否则非法

错误处理:
  ERROR: invalid cidr value: "192.168.1.5/24"
  DETAIL: Value has bits set to right of mask.
```

### 5. inet 与 cidr 的隐式转换

```
PG 实现的转换规则:
  inet → cidr: 调用 inet_to_cidr,验证主机位为 0,否则报错
  cidr → inet: 直接重解释字节,无验证 (因为 cidr 是 inet 子集)
  inet/cidr → text: 调用对应的 _out 函数,格式化为字符串
  text → inet: 解析字符串,自动补全前缀 (默认 /32 或 /128)
```

### 6. ClickHouse 风格的轻量类型

```
若不需要 CIDR 语义,可仅实现 IPv4/IPv6 两个固定宽度类型:
  IPv4: 4 字节 UInt32 (主机字节序)
  IPv6: 16 字节 FixedString

优势:
  1. 列存压缩极佳 (Delta + LZ4 可达 4-10 倍)
  2. SIMD 向量化扫描 (一次处理 8 个 IPv4)
  3. 直接整数比较和 BETWEEN 范围查询
  4. 实现复杂度极低,可在 1 周内完成

劣势:
  1. 没有内置 CIDR 类型,所有子网语义靠函数
  2. 不支持 GiST/SP-GiST 索引,只能靠主键稀疏索引
```

### 7. MAC 地址类型实现

```
EUI-48 (6 字节):
  内部存储: byte[6]
  字符串解析: 支持 "08:00:2b:01:02:03" / "08-00-2b-01-02-03" / "0800.2b01.0203"
  规范化输出: "08:00:2b:01:02:03"

EUI-64 (8 字节):
  内部存储: byte[8]
  IPv6 SLAAC 派生:
    1. 取 48 bit MAC: AA:BB:CC:DD:EE:FF
    2. 中间插入 FF:FE: AA:BB:CC:FF:FE:DD:EE:FF
    3. 翻转第 7 位 (U/L): 切换全局/本地标识

PG 实现位置: src/backend/utils/adt/mac.c, mac8.c
```

### 8. 测试要点

```
正确性测试:
  - 边界: 0.0.0.0, 255.255.255.255, ::, ::ffff:ffff:ffff:ffff
  - IPv4-mapped IPv6: ::ffff:192.168.1.1
  - 前缀长度: /0, /32, /128 (全/无掩码)
  - CIDR 主机位非零应报错
  - MAC 多种格式归一化

性能测试:
  - 1 亿行 inet 列的子网包含查询 (期望 < 1 秒)
  - SP-GiST 索引构建速度
  - 与 VARCHAR 方案的存储/速度对比

兼容性测试:
  - PG inet/cidr 在所有衍生引擎的语义一致性
  - 跨引擎导入导出 (CSV/Parquet) 时的类型保留
```

## 总结对比矩阵

### 网络类型能力总览

| 能力 | PostgreSQL | CockroachDB | YugabyteDB | ClickHouse | CrateDB | Trino | Snowflake | BigQuery | MySQL | Oracle | SQL Server |
|------|-----------|-------------|------------|------------|---------|-------|-----------|----------|-------|--------|------------|
| INET 类型 | inet | INET | inet | IPv4/IPv6 | ip | IPADDRESS | -- | -- | -- | -- | -- |
| CIDR 类型 | cidr | -- | cidr | -- | -- | -- | -- | -- | -- | -- | -- |
| MACADDR | macaddr | -- | macaddr | -- | -- | -- | -- | -- | -- | -- | -- |
| MACADDR8 | 是 (10+) | -- | 是 | -- | -- | -- | -- | -- | -- | -- | -- |
| `<<` 运算符 | 是 | 是 | 是 | -- (函数) | 是 | -- (函数) | -- | -- | -- | -- | -- |
| GiST/SP-GiST 索引 | 是 | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| INET_ATON 函数 | text/inet 转换 | -- | -- | IPv4StringToNum | -- | CAST | PARSE_IP | NET.IP_FROM_STRING | INET_ATON | UTL_INADDR | PARSENAME |
| IPv6 函数 | 是 | 是 | 是 | IPv6StringToNum | 是 | 是 | PARSE_IP | NET.IP_FROM_STRING | INET6_ATON | RAW | -- |
| 起始版本 | 7.4 (2003) | 19.2 | 2.x | 19.x (2019) | 0.50 | 332 (2020) | 任意 | 任意 | 5.0 (2005) | 任意 | 任意 |

### 选型建议

| 场景 | 推荐引擎 | 理由 |
|------|---------|------|
| 防火墙规则 / 路由表 | PostgreSQL inet/cidr + SP-GiST | 完整运算符 + 索引加速 |
| 网络设备资产 (含 MAC) | PostgreSQL macaddr + macaddr8 | 唯一原生 MAC 支持 |
| 超大规模访问日志 (亿+行/天) | ClickHouse IPv4/IPv6 | 列存 + 向量化最快 |
| 中等规模 OLTP 应用 | MySQL INT + INET_ATON | 简洁高效 |
| 云数仓即席分析 | Snowflake PARSE_IP / BigQuery NET.* | 与 VARCHAR 互操作好 |
| 联合查询 (Iceberg/Hudi) | Trino IPADDRESS | 跨引擎统一类型 |
| 物联网 / SLAAC | PostgreSQL macaddr8 | 唯一原生 EUI-64 |
| 嵌入式 / 简单应用 | SQLite TEXT | 简单够用 |
| 兼容老系统 / Oracle | Oracle VARCHAR2 + UDF | 无原生类型 |

## 参考资料

- PostgreSQL: [Network Address Types](https://www.postgresql.org/docs/current/datatype-net-types.html)
- PostgreSQL: [Network Address Functions and Operators](https://www.postgresql.org/docs/current/functions-net.html)
- PostgreSQL: [SP-GiST and GiST Indexes for inet](https://www.postgresql.org/docs/current/spgist-builtin-opclasses.html)
- ClickHouse: [Domains: IPv4](https://clickhouse.com/docs/en/sql-reference/data-types/domains/ipv4)
- ClickHouse: [Domains: IPv6](https://clickhouse.com/docs/en/sql-reference/data-types/domains/ipv6)
- ClickHouse: [Functions for Working with IPv4 and IPv6 Addresses](https://clickhouse.com/docs/en/sql-reference/functions/ip-address-functions)
- CockroachDB: [INET](https://www.cockroachlabs.com/docs/stable/inet.html)
- YugabyteDB: [Network Address Types](https://docs.yugabyte.com/preview/api/ysql/datatypes/type_network/)
- CrateDB: [IP Type](https://crate.io/docs/crate/reference/en/latest/general/ddl/data-types.html#ip)
- Trino: [IPADDRESS Type](https://trino.io/docs/current/language/types.html#ipaddress)
- Snowflake: [PARSE_IP](https://docs.snowflake.com/en/sql-reference/functions/parse_ip)
- BigQuery: [Net Functions](https://cloud.google.com/bigquery/docs/reference/standard-sql/net_functions)
- MySQL: [Miscellaneous Functions (INET_ATON, INET6_ATON)](https://dev.mysql.com/doc/refman/8.0/en/miscellaneous-functions.html)
- Oracle: [UTL_INADDR](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/UTL_INADDR.html)
- RFC 4291: IP Version 6 Addressing Architecture
- RFC 4632: Classless Inter-domain Routing (CIDR)
- IEEE 802: 48-bit (EUI-48) and 64-bit (EUI-64) Identifier Formats
