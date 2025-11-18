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

curl -XGET 'http://10.194.65.135:9200/_cluster/health?pretty'

# 2. 查看所有节点的状态
curl -XGET 'http://10.194.65.135:9200/_cat/nodes?v'

# 3. 查看所有索引的状态，特别关注 .security-* 和 .kibana_* 等系统索引
curl -XGET 'http://10.194.65.135:9200/_cat/indices?v' | grep -E "(red|yellow|security|kibana)"


# 此命令会返回详细的解释，说明为什么有分片无法分配
# 重点关注:unassigned_info.reason
# 常见的原因如下：
# CLUSTER_RECOVERED"：集群恢复期间无法分配。
# NODE_LEFT：持有该分片的节点离开了集群。
# DISK_AVAILABLE_SPACE_LOW：节点磁盘空间不足（这是一个非常常见的原因）
curl -XGET 'http://10.194.65.135:9200/_cluster/allocation/explain?pretty' | python -m json.tool
```



对于单节点集群，最直接有效的解决方案就是将所有索引的副本数（number_of_replicas）设置为0
。这是因为Elasticsearch为了保障数据高可用，规定同一个索引的主分片和其副本分片不能存放在同一个节点上。在单节点环境下，副本分片没有其他节点可以分配，因此一直处于“未分配”状态，导致集群报黄
。
请按照以下步骤操作：
设置全局副本数为0
执行以下命令，将集群中所有现有索引的副本数设置为0。这能立即解决当前大量分片未分配的问题。
curl -u elastic:elastic -X PUT "http://10.194.65.135:9200/_all/_settings" -H 'Content-Type: application/json' -d'
{
"index.number_of_replicas": 0
}
'
为未来索引创建设置默认模板（推荐）
为了避免后续新创建的索引再次出现此问题，可以创建一个索引模板，自动为新索引设置副本数为0。
curl -u elastic:elastic -X PUT "http://10.194.65.135:9200/_template/zero_replicas_template" \
-H 'Content-Type: application/json' \
-d '{
"index_patterns": ["*"],
"settings": {
"number_of_replicas": 0
}
}'
✅ 验证解决效果
完成上述设置后，进行以下检查来确认问题是否解决：
再次检查集群健康状态：
curl -u elastic:elastic -XGET 'http://10.194.65.135:9200/_cluster/health?pretty'
稍等片刻，集群状态（status）应该会从 yellow​ 变为 green。同时，unassigned_shards的数量应该变为 0。




curl -u elastic:elastic -XGET 'http://10.194.65.135:9200/_cluster/allocation/explain?pretty'



# 将一个现有索引的副本数改为 2
curl -u elastic:elastic -X PUT "http://10.194.65.135:9200/my_existing_index/_settings" -H 'Content-Type: application/json' -d'
{
"index.number_of_replicas": 2
}



# 将特定索引（.kibana-event-log-ds）的副本数设置为0
curl -u elastic:elastic -X PUT "http://10.194.65.135:9200/.kibana-event-log-ds/_settings" -H 'Content-Type: application/json' -d'
{
"number_of_replicas": 0
}
'

# 如果您想一劳永逸，为集群中所有现有索引设置副本数为0，可以使用以下命令
curl -u elastic:elastic -X PUT "http://10.194.65.135:9200/_all/_settings" -H 'Content-Type: application/json' -d'
{
"number_of_replicas": 0
}
'


# 检查特定索引（比如那个有问题的.kibana-event-log-ds）的设置
curl -u elastic:elastic -XGET "http://10.194.65.135:9200/.kibana-event-log-ds/_settings?pretty"

# 或者快速查看所有索引的副本数设置
curl -u elastic:elastic -XGET "http://10.194.65.135:9200/_cat/indices?v&h=index,rep"


curl -u elastic:elastic -XGET "http://10.194.65.135:9200/_cluster/allocation/explain?pretty" -H 'Content-Type: application/json' -d'
{
"index": "[你的索引名]",
"shard": [分片号],
"primary": [true或false]
}
'
重点关注返回结果中的 "decision": "NO"和 "explanation"字段，这是阻止分配的根本原因 


# 如果磁盘曾经达到洪水阶段水位线（95%），索引会被自动设置为只读块（read_only_allow_delete）
curl -u elastic:elastic -XGET "http://10.194.65.135:9200/.kibana-event-log-ds/_settings?pretty" | grep read_only

# 手动解锁索引
curl -u elastic:elastic -X PUT "http://10.194.65.135:9200/_all/_settings" -H 'Content-Type: application/json' -d'
{
"index.blocks.read_only_allow_delete": null
}
'


# 查看所有分片状态,检查输出中是否有 UNASSIGNED状态的分片。如果没有，说明所有分片都已分配
curl -u elastic:elastic -XGET 'http://10.194.65.135:9200/_cat/shards?v'

# 查看索引状态,确保所有索引的状态（status）都是 open，没有 red或 yellow
curl -u elastic:elastic -XGET 'http://10.194.65.135:9200/_cat/indices?v'
