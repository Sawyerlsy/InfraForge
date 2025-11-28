## ELK 日志监控
### 1、
#### 1.1、Elasticsearch所在机器需要设置
```shell
# 对于 Elasticsearch 这样的搜索引擎，它需要高速处理海量的数据文件（索引文件）。为了实现极致性能，它大量使用内存映射技术来访问这些文件。这意味着在运行过程中，尤其是进行高并发查询或处理复杂查询时，Elasticsearch 会创建成千上万个内存映射区域（即需要贴很多书签）
# vm.max_map_count:控制单个进程能够拥有的最大内存映射区域数量
sysctl vm.max_map_count

# 添加 vm.max_map_count=262144
vim /etc/sysctl.conf
sysctl -p
```

#### 1.2 设置elastic账号密码
```shell
# 进入 Elasticsearch 容器
docker exec -it elasticsearch /bin/sh

# 查看有哪些内置用户
curl -u elastic:elastic "http://localhost:9200/_security/user?pretty"

# 设置 kibana、kibana_system、logstash_system、 beats_system 的密码
./bin/elasticsearch-reset-password -u kibana -i
./bin/elasticsearch-reset-password -u kibana_system -i
./bin/elasticsearch-reset-password -u logstash_system -i
./bin/elasticsearch-reset-password -u beats_system -i

```

#### 1.3 elasticsearch状态检查
```shell


# 1. 检查集群整体健康状态
# status字段:
# green（绿色）：一切正常。
# yellow（黄色）：所有主分片可用，但副本分片未全部分配。这通常发生在单节点集群或副本丢失时。
# red（红色）：至少有一个主分片不可用。这是最严重的情况，会导致部分数据完全无法访问
curl -u elastic:elastic -XGET 'http://10.194.65.135:9200/_cluster/health?pretty'

# 2. 查看所有节点的状态
curl -u elastic:elastic -XGET 'http://10.194.65.135:9200/_cat/nodes?v'

# 3. 查看索引状态,确保所有索引的状态（status）都是 open，没有 red或 yellow
curl -u elastic:elastic -XGET 'http://10.194.65.135:9200/_cat/indices?v'
curl -u elastic:elastic -XGET 'http://10.194.65.135:9200/_cat/indices?v' | grep -E "(red|yellow|security|kibana)"


# 查看所有分片状态,检查输出中是否有 UNASSIGNED状态的分片。如果没有，说明所有分片都已分配
curl -u elastic:elastic -XGET 'http://10.194.65.135:9200/_cat/shards?v'

# 找出是哪个索引的哪个分片没有分配
curl -u elastic:elastic -XGET 'http://10.194.65.135:9200/_cat/shards?v&h=index,shard,prirep,state,unassigned.reason' | grep UNASSIGNED

# 诊断未分配的根本原因
# 重点关注:unassigned_info.reason
# 常见的原因如下：
# CLUSTER_RECOVERED"：集群恢复期间无法分配。
# NODE_LEFT：持有该分片的节点离开了集群。
# DISK_AVAILABLE_SPACE_LOW：节点磁盘空间不足（这是一个非常常见的原因）
curl -u elastic:elastic -XGET 'http://10.194.65.135:9200/_cluster/allocation/explain?pretty' | python -m json.tool

curl -u elastic:elastic -XGET "http://10.194.65.135:9200/_cluster/allocation/explain?pretty" -H 'Content-Type: application/json' -d'
{
"index": "您的_data_stream名",  # 替换为上一步找到的索引名
"shard": 0,                    # 替换为具体的分片号
"primary": false # 因为是副本分片，所以是 false
}
'

# 查看特定索引模式的分片分布
curl -u elastic:elastic -XGET 'http://10.194.65.135:9200/_cat/shards/logs-*?v'

# 查看所有模板
curl -u elastic:elastic -XGET 'http://10.194.65.135:9200/_index_template?pretty' 

# 查看指定模板的配置，如：logs
curl -u elastic:elastic -XGET 'http://10.194.65.135:9200/_index_template/logs?pretty' 

# data_stream logs类型默认的模板为logs,由多个组件模板组成,要修改配置的话
# 需要查看当前模板引用的 logs@settings组件模板的具体配置，以确保在原有基础上修改。
curl -u elastic:elastic -XGET 'http://10.194.65.135:9200/_component_template/logs@settings?pretty'

# 在原有的logs@settings组件模板基础上修改配置,修改副本数为0
curl -u elastic:elastic -XPUT 'http://10.194.65.135:9200/_component_template/logs@settings' -H 'Content-Type: application/json' -d'
{
  "version": 18,
  "template": {
    "settings": {
      "index": {
        "number_of_replicas": 0,
        "lifecycle": {
          "name": "logs"
        },
        "codec": "best_compression",
        "default_pipeline": "logs@default-pipeline",
        "mapping": {
          "total_fields": {
            "ignore_dynamic_beyond_limit": "true"
          },
          "ignore_malformed": "true"
        }
      }
    },
    "data_stream_options": {
      "failure_store": {
        "enabled": true
      }
    }
  },
  "_meta": {
    "managed": true,
    "description": "default settings for the logs index template installed by x-pack"
  },
  "deprecated": false
}'

# 查看索引的详细设置和统计信息
curl -u elastic:elastic -XGET 'http://10.194.65.135:9200/.monitoring-kibana-7-2025.11.19/_stats'

# 查看索引的设置
curl -u elastic:elastic -XGET 'http://10.194.65.135:9200/.monitoring-kibana-7-2025.11.19/_settings'

# 查看索引的映射
curl -u elastic:elastic -XGET 'http://10.194.65.135:9200/.monitoring-kibana-7-2025.11.19/_mapping'
```

#### 1.4 elasticsearch常见问题处理
#### 1.4.1 调整副本数（针对单节点集群）
```shell
# 情形一：调整副本数（针对单节点集群）
# 如果您的环境是单节点开发或测试集群，这是最直接有效的方法。它将副本数设为0，牺牲高可用性以换取绿色状态。
# 数据流：为特定的 Data Stream 的后备索引设置
curl -u elastic:elastic -XPUT 'http://10.194.65.135:9200/.ds-logs-guangdong-virtual-station-old-production-2025.11.20-000001/_settings' -H 'Content-Type: application/json' -d'{
"index.number_of_replicas": 0
}'

# 数据流：更推荐在索引模板中永久修改，影响后续创建的所有新索引
curl -u elastic:elastic -XPUT 'http://10.194.65.135:9200/_index_template/logs ' -H 'Content-Type: application/json' -d'{
"index_patterns": ["logs-*"],
"template": {
"settings": {
"number_of_replicas": 0
}
}
}'

# 标准索引和数据流：
# 对于单节点集群，最直接有效的解决方案就是将所有索引的副本数（number_of_replicas）设置为0
# 这是因为Elasticsearch为了保障数据高可用，规定同一个索引的主分片和其副本分片不能存放在同一个节点上。在单节点环境下，副本分片没有其他节点可以分配，因此一直处于“未分配”状态，导致集群报黄
# 该命令会删除所有现有副本
curl -u elastic:elastic -X PUT "http://10.194.65.135:9200/_all/_settings" -H 'Content-Type: application/json' -d'
{
"index.number_of_replicas": 0
}
'

# 标准索引和数据流： 为未来索引创建设置默认模板（推荐） ,为了避免后续新创建的索引再次出现此问题，可以创建一个索引模板，自动为新索引设置副本数为0。
curl -u elastic:elastic -X PUT "http://10.194.65.135:9200/_template/zero_replicas_template" \
-H 'Content-Type: application/json' \
-d '{
"index_patterns": ["*"],
"settings": {
"number_of_replicas": 0
}
}'
```

#### 1.4.2 磁盘空间不足
```shell
# 如果是因为磁盘空间超过使用水位（默认85%），需要清理空间或扩容。临时方案是调整水位线（生产环境慎用）。
# 提高低水位线（如到90%），允许继续分配分片.不推荐该方式,根本原因是磁盘空间不足,集群无法正常工作
curl -u elastic:elastic -XPUT 'http://10.194.65.135:9200/_cluster/settings' -H 'Content-Type: application/json' -d'{
"persistent": {
"cluster.routing.allocation.disk.watermark.low": "90%"
}
}'

# 如果磁盘曾经达到洪水阶段水位线（95%），索引会被自动设置为只读块（read_only_allow_delete）
curl -u elastic:elastic -XGET "http://10.194.65.135:9200/.kibana-event-log-ds/_settings?pretty" | grep read_only

# 手动解锁索引
curl -u elastic:elastic -X PUT "http://10.194.65.135:9200/_all/_settings" -H 'Content-Type: application/json' -d'
{
"index.blocks.read_only_allow_delete": null
}
'
```

#### 1.4.2 启用分片分配
```shell
# 检查并确保分片分配没有被人为关闭。
# 确保分片分配是启用的
curl -u elastic:elastic -XPUT 'http://10.194.65.135:9200/_cluster/settings' -H 'Content-Type: application/json' -d'{
"persistent": {
"cluster.routing.allocation.enable": "all"
}
}'
```

#### 1.5 elasticsearch配置索引生命周期管理（ILM）策略



#### 1.6 测试分词
```shell
curl -u elastic:elastic -X POST "http://10.194.65.135:9200/_analyze?pretty" -H 'Content-Type: application/json' -d'
{
"analyzer": "standard",
"text": "Your text to analyze here"
}'
```


#### 1.7 分词器插件
