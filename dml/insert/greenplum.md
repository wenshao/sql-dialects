# Greenplum: INSERT

> 参考资料:
> - [Greenplum SQL Reference](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-sql_ref.html)
> - [Greenplum Admin Guide](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-intro-about_greenplum.html)


基本插入
```sql
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);
```


多行插入
```sql
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);
```


从查询结果插入
```sql
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;
```


带 RETURNING
```sql
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25)
RETURNING id, username;
```


CTE + INSERT
```sql
WITH new_users AS (
    SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age
)
INSERT INTO users (username, email, age)
SELECT * FROM new_users;
```


批量加载（COPY，适合大批量导入）
```sql
COPY users (username, email, age) FROM '/data/users.csv'
    WITH (FORMAT csv, HEADER true, DELIMITER ',');
```


从标准输入加载
COPY users FROM STDIN WITH (FORMAT csv);

gpfdist 加载（Greenplum 推荐的高速并行加载）
1. 先启动 gpfdist 服务: gpfdist -d /data -p 8081
2. 创建外部表
```sql
CREATE READABLE EXTERNAL TABLE ext_users_load (
    username VARCHAR(64),
    email    VARCHAR(255),
    age      INTEGER
)
LOCATION ('gpfdist://etl_host:8081/users.csv')
FORMAT 'CSV' (HEADER DELIMITER ',');
```


3. 通过外部表插入
```sql
INSERT INTO users (username, email, age)
SELECT * FROM ext_users_load;
```


gpload（YAML 配置文件方式，封装 gpfdist）
gpload -f load_config.yaml

PXF 加载（从 HDFS/S3/Hive 加载）
CREATE EXTERNAL TABLE pxf_source (id INT, name TEXT)
LOCATION ('pxf://bucket/data.csv?PROFILE=s3:text')
FORMAT 'CSV';
INSERT INTO users SELECT * FROM pxf_source;

ON CONFLICT（PostgreSQL 9.5+，Greenplum 7+ 支持）
```sql
INSERT INTO users (id, username, email) VALUES (1, 'alice', 'alice@example.com')
ON CONFLICT (id) DO NOTHING;

INSERT INTO users (id, username, email) VALUES (1, 'alice', 'new@example.com')
ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email;
```


注意：Greenplum 兼容 PostgreSQL INSERT 语法
注意：大批量加载推荐 gpfdist / COPY / gpload
注意：INSERT VALUES 单行插入性能较低（需要协调多个 Segment）
