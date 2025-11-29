### Redis集群部署
##### 1、编译安装
```shell
# 解压及编译安装
tar xzf redis-6.2.19.tar.gz
cd redis-6.2.19
make BUILD_TLS=yes && sudo make install PREFIX=/usr/local/redis
sudo ln -s /usr/local/redis/bin/* /usr/local/bin/
```

##### 2、创建目录
```shell
# 创建目录
mkdir -p /data/redis/{7001,7002,7003}/{data,logs,pid,conf}
```
#### 3、修改配置
```shell
vim /data/redis/redis_template.conf
```
```properties
# 网络与安全
bind 0.0.0.0                      # 监听所有IP
protected-mode no                 # 允许外部访问
port {port}                         # 实例端口
requirepass hgrica1@    # 集群访问密码
masterauth hgrica1@     # 主从同步密码（与requirepass一致）
tcp-backlog 10240  # 高并发连接队列,需与内核参数net.core.somaxconn=10240匹配，避免连接丢弃

# 集群核心配置
cluster-enabled yes               # 启用集群模式
cluster-config-file nodes-{port}.conf # 自动生成的集群元数据文件
cluster-node-timeout 15000        # 节点失联超时（毫秒）
cluster-replica-validity-factor 10 # 从节点有效性验证
min-replicas-to-write 1           # 防脑裂：至少1个从节点同步才允许写入[4](@ref)

# 持久化与内存
dir /data/redis/{port}/data         # 数据存储路径
appendonly yes                    # 启用AOF持久化
appendfsync everysec              # 平衡性能与数据安全
maxmemory 16gb                    # 建议不超过物理内存70%
maxmemory-policy volatile-lru     # 内存淘汰策略
aof-use-rdb-preamble yes          # 开启混合持久化（核心配置）

# 配置AOF重写规则（防文件膨胀）
auto-aof-rewrite-percentage 100  # 文件增长100%触发重写
auto-aof-rewrite-min-size 64mb   # 最小64MB才触发重写

# 可选：RDB策略（补充备份）
save 3600 1     # 1小时至少1次修改备份

# 日志与进程
daemonize yes
pidfile /data/redis/{port}/pid/redis.pid
logfile /data/redis/{port}/logs/redis.log
```

#### 4、生成其他节点配置
```shell
# 批量生成7002/7003配置
for port in 7001 7002 7003; do
  cp -r /data/redis/redis_template.conf /data/redis/$port/conf/redis.conf
  sed -i -e 's/[[:space:]]*#.*$//' -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]*$//' -e '/^$/d' /data/redis/$port/conf/redis.conf
  sed -i "s/{port}/$port/g" /data/redis/$port/conf/redis.conf
done
```

```shell
# 创建专有用户
useradd -M -s /sbin/nologin redis
chown -R redis:redis /data/redis
```

#### 5、启动节点
```shell
# 每台服务器启动3个实例
redis-server /data/redis/7001/conf/redis.conf \
&& redis-server /data/redis/7002/conf/redis.conf \
&& redis-server /data/redis/7003/conf/redis.conf

# 验证进程
ps -ef | grep redis-server  # 应显示3个进程
```

#### 6、创建集群
```shell
redis-cli -a hgrica1@ --cluster create \
  192.168.1.101:7001 \
  192.168.1.102:7004 \
  192.168.1.103:7007 \
  192.168.1.101:7002 \
  192.168.1.101:7003 \
  192.168.1.102:7005 \
  192.168.1.102:7006 \
  192.168.1.103:7008 \
  192.168.1.103:7009 \
  --cluster-replicas 2
  
# 前 N 个节点作为主节点，后续节点按顺序作为从节点分配给主节点
# 192.168.1.101:7002 和 192.168.1.101:7003 → 作为192.168.1.101:7001的从节点
# 192.168.1.102:7005 和 192.168.1.102:7006 → 作为192.168.1.102:7004的从节点
# 192.168.1.103:7008 和 192.168.1.103:7009 → 作为192.168.1.103:7007的从节点
```

#### 7、集群验证与高可用测试
##### 7.1、基础验证
```shell
# 检查集群状态
redis-cli -a hgrica1@ -c -h 192.168.1.101 -p 7001 cluster info
# 输出应包含：cluster_state:ok 和 cluster_slots_assigned:16384

# 查看节点拓扑
redis-cli -a hgrica1@ -c -h 192.168.1.101 -p 7001 cluster nodes
# 确认每个主节点有2个从节点，且分布在其他物理机

# 关闭redis
redis-cli -a hgrica1@ -p 7001 shutdown
```

##### 7.2、故障转移测试
```shell
# 模拟主节点宕机（如192.168.1.101:7001）
redis-cli -a hgrica1 -h 192.168.1.101 -p 7001 DEBUG SEGFAULT

# 观察故障转移（约15秒后）
watch -n 1 'redis-cli -a hgrica1@ cluster nodes | grep master'
# 原从节点（如7002）应升主，且集群状态恢复OK
```
##### 7.3、数据稳定性测试
```shell
# 跨节点写入读取
redis-cli -a hgrica1@ -c -h 192.168.1.101 -p 7001 set foo "cluster_test"
redis-cli -a hgrica1 -c -h 192.168.1.102 -p 7004 get foo  # 应返回"cluster_test"
```


#### 8、创建服务
##### 8.1、创建服务文件（以7001为例）
```shell
vi /data/redis/redis_template.service

[Unit]
Description=Redis Cluster Node {port}
After=network.target

[Service]
Type=forking
User=redis
Group=redis
ExecStart=/usr/local/bin/redis-server /data/redis/{port}/conf/redis.conf
ExecStop=/usr/local/bin/redis-cli -a hgrica1@ -p {port} shutdown
Restart=always
RestartSec=3
WorkingDirectory=/data/redis/{port}/data

[Install]
WantedBy=multi-user.target
```

##### 8.2、启动服务
```shell
# 批量配置
for port in 7001 7002 7003; do
  cp /data/redis/redis_template.service /etc/systemd/system/redis-$port.service
  sed -i "s/{port}/$port/g" /etc/systemd/system/redis-$port.service
  systemctl daemon-reload
  systemctl enable redis-$port
  systemctl start redis-$port
done
```

#### 9、常用操作
##### 9.1、添加主节点
```shell
# 添加新节点到集群,默认添加的是主节点（无槽位）
redis-cli -a password --cluster add-node NEW_HOST:NEW_PORT EXISTING_HOST:EXISTING_PORT


# 添加主节点后，由于其初始状态下不包含任何哈希槽，需要手动或通过平衡操作为其分配槽位，它才能真正存储数据 
# 方式1：使用 reshard命令可以重新分配槽位，这是一个交互式过程 
# 执行后会依次询问：
# 要移动多少个槽位（How many slots do you want to move）：根据需求输入数量。
# 接收这些槽位的目标节点ID（What is the receiving node ID）：输入新主节点的ID。
# 从哪些节点转移出这些槽位（Please enter all the source node IDs）：可以输入 all表示从所有现有主节点平均抽取，或输入特定源节点的ID，然后输入 done结束。
# 确认迁移计划（Do you want to proceed with the proposed reshard plan）：输入 yes开始迁移 
redis-cli -a yourpassword --cluster reshard 192.168.1.102:7004

# 方式2：使用 rebalance 自动平衡集群各节点的槽位数量,可指定权重、阈值等 （灵活性低、由集群自动处理，可能导致变动范围过大,不推荐）
# redis-cli --cluster rebalance HOST:PORT
```

##### 9.2、添加从节点
```shell
# EXISTING_HOST:EXISTING_PORT是集群发现的入口
# master-id是cluster nodes中的主节点ID
redis-cli -a password --cluster add-node NEW_HOST:NEW_PORT EXISTING_HOST:EXISTING_PORT --cluster-slave --cluster-master-id <master-id>
```

##### 9.3、让指定从节点成为主节点
在从节点上执行 CLUSTER FAILOVER命令会发起一次有序的主从切换，原主节点会将其数据同步到该从节点，确保数据安全后再完成角色切换。这是最安全的手动提升方式
在从节点上执行 CLUSTER FAILOVER时，流程如下:
- step1: 执行 CLUSTER FAILOVER命令
- step2: 向集群请求主节点暂停写入
- step3: 等待数据同步完成
- step4: 数据同步异常（包括磁盘空间不足、网络异常、从节点宕机等）时，主节点检测到同步失败或者等待超时，主节点会恢复写入，故障转移失败，集群恢复正常;
- step5: 数据同步成功后, 从节点发起选举，赢得集群中多数节点的投票后升级为主节点，原主节点成为新主节点的从节点，完成角色切换
- step6: 新主节点恢复写入，故障转移完成
```shell
# 1. 连接到要提升的从节点
redis-cli -a hgrica1@ -h 192.168.1.101 -p 7002

# 2.1 使用标准模式执行手动故障转移，安全的主从切换，零数据丢失
CLUSTER FAILOVER

# 2.2 使用强制模式执行手动故障转移，主节点宕机时快速选主，跳过偏移量检查，依赖固有同步，数据可能丢失
CLUSTER FAILOVER FORCE

# 2.3 使用强制模式执行手动故障转移，不检查数据，直接抢占主节点，数据可能丢失
CLUSTER FAILOVER TAKEOVER

# 3. 验证节点角色变更
CLUSTER NODES
```
##### 9.4、删除从节点
从节点没有槽位，直接删除即可
```shell
redis-cli --cluster del-node <existing-host>:<existing-port> <node-id-of-slave-to-remove>
```

##### 9.5、删除主节点
删除主节点：必须先将该主节点上所有的哈希槽迁移到其他主节点上，否则删除操作会失败
- 使用 reshard 命令将待删除主节点的所有槽位迁移至其他主节点。
- 确认待删除主节点不再包含任何槽位后，再执行 del-node命令

步骤1：检查当前集群状态
```shell
# 查看当前节点和槽位分布
redis-cli -a hgrica1@ -h 192.168.1.102 -p 7004 CLUSTER NODES

# 检查集群状态
redis-cli -a hgrica1@ --cluster check 192.168.1.102:7004
```

步骤2：将要删除的主节点槽位迁移到其他主节点
假设要删除 192.168.1.101:7001，将其槽位迁移到 192.168.1.102:7004 和 192.168.1.103:7007：
```shell
# 执行reshard操作
redis-cli -a hgrica1@ --cluster reshard 192.168.1.102:7004

# 交互过程示例：
# 1. 输入要移动的槽位数量（如要删除节点有5000个槽位）
How many slots do you want to move (from 1 to 16384)? 5000

# 2. 输入接收槽位的目标节点ID（第一个目标节点）
What is the receiving node ID? <node_id_of_192.168.1.102:7004>

# 3. 输入源节点ID（要删除的节点）
Please enter all the source node IDs.
  Type 'all' to use all the nodes as source nodes for the hash slots.
  Type 'done' once you entered all the source nodes IDs.
Source node #1: <node_id_of_192.168.1.101:7001>
Source node #2: done

# 重复上述过程，将剩余槽位迁移到另一个目标节点
```

步骤3：验证槽位迁移完成
```shell
# 检查要删除的节点是否还有槽位
redis-cli -a hgrica1@ -h 192.168.1.101 -p 7001 CLUSTER NODES | grep "192.168.1.101:7001"

# 预期输出：该节点应该显示没有槽位或者只有极少数槽位
# 例如：<node_id> 192.168.1.101:7001@17001 slave - 0 1234567890000 0 connected
```

步骤4：删除空主节点
```shell
# 确认节点没有槽位后删除
redis-cli -a hgrica1@ --cluster del-node 192.168.1.102:7004 <node_id_of_192.168.1.101:7001>

# 验证节点已删除
redis-cli -a hgrica1@ --cluster check 192.168.1.102:7004
```


##### 9.6、检查集群状态
check命令可以对集群进行全面的健康检查，包括节点数量、角色、槽位分布、槽位状态等
```shell
# 确保每个主节点有足够的从节点
redis-cli -a hgrica1@ --cluster check 192.168.1.102:7004

# 预期输出应该显示：
# [OK] All nodes agree about slots configuration.
# >>> Check for open slots...
# >>> Check slots coverage...
# [OK] All 16384 slots covered.
```


##### 9.7、验证数据是否同步完成
从节点升级为主节点时，同步过程中或结束后可以验证数据是否同步完成

> 关键指标： 
> - master_repl_offset == slave_repl_offset 
> - lag = 0（表示无延迟） 
> - master_link_status: up

- 检查复制偏移量
```shell
# 在主节点上检查
redis-cli -a hgrica1@ -h 192.168.1.102 -p 7004 INFO replication
# 关注：
# master_repl_offset:xxxxxx
# slaveX:ip=192.168.1.101,port=7002,offset=xxxxxx,lag=0

# 在从节点上检查
redis-cli -a hgrica1@ -h 192.168.1.101 -p 7002 INFO replication
# 关注：
# master_repl_offset:xxxxxx
# slave_repl_offset:xxxxxx
```
- 实时监控同步进度
```shell
# 持续监控复制状态
watch -n 0.5 "redis-cli -a hgrica1@ -h 192.168.1.101 -p 7002 INFO replication | grep -E '(offset|lag|status)'"

# 输出示例：
# master_repl_offset:12567890
# slave_repl_offset:12567890
# master_last_io_seconds_ago:1
# slave_lag:0
```

##### 9.3、计算健属于哪个槽
```shell
redis-cli -a password CLUSTER KEYSLOT <key_name>
```
