# Derby: JSON 类型

## Derby 不支持原生 JSON 类型

使用 VARCHAR/CLOB 存储 JSON 字符串

## VARCHAR/CLOB 存储 JSON


```sql
CREATE TABLE events (
    id      INT NOT NULL GENERATED ALWAYS AS IDENTITY,
    data    VARCHAR(32672),                  -- JSON 作为字符串
    PRIMARY KEY (id)
);
```

## CLOB 用于大 JSON

```sql
CREATE TABLE documents (
    id      INT NOT NULL GENERATED ALWAYS AS IDENTITY,
    content CLOB,
    PRIMARY KEY (id)
);
```

## 插入 JSON 字符串

```sql
INSERT INTO events (data) VALUES ('{"name": "alice", "age": 25, "tags": ["vip"]}');
INSERT INTO events (data) VALUES ('{"name": "bob", "age": 30}');
```

## 字符串方式查询 JSON


## LIKE 搜索

```sql
SELECT * FROM events WHERE data LIKE '%"name": "alice"%';
SELECT * FROM events WHERE data LIKE '%"vip"%';
```

## LOCATE 查找

```sql
SELECT * FROM events WHERE LOCATE('"alice"', data) > 0;
```

## Java 存储过程处理 JSON


创建 Java 函数提取 JSON 字段
public class JsonUtils {
public static String getField(String json, String field) {
// 使用 Jackson/Gson 解析
ObjectMapper mapper = new ObjectMapper();
JsonNode node = mapper.readTree(json);
return node.get(field).asText();
}
}
注册为 Derby 函数
CREATE FUNCTION JSON_VALUE(json_str VARCHAR(32672), field_name VARCHAR(256))
RETURNS VARCHAR(32672)
LANGUAGE JAVA PARAMETER STYLE JAVA
NO SQL
EXTERNAL NAME 'JsonUtils.getField';
使用自定义函数
SELECT JSON_VALUE(data, 'name') FROM events;

## 不支持的 JSON 功能


不支持 JSON 类型
不支持 JSON 路径表达式
不支持 JSON 操作符（->, ->>）
不支持 JSON 构造函数
不支持 JSON 聚合函数
不支持 JSON 索引
注意：Derby 不支持原生 JSON 类型
注意：使用 VARCHAR/CLOB 存储 JSON 字符串
注意：JSON 查询只能通过字符串函数或 Java 存储过程
注意：推荐在应用层处理 JSON 逻辑
注意：可通过 Java 存储过程集成 Jackson/Gson 库
