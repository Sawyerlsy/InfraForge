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

