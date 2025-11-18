### Docker资源地址
https://download.docker.com/linux/static/stable

### Docker Compose资源地址
https://github.com/docker/compose/releases

### 常用配置

#### 2、自定义Docker seccomp配置
```shell
# 配置seccomp
vim /etc/docker/daemon.json

{
  "insecure-registries": ["core.harbor.domain:32388"],
  "seccomp-profile" : "/etc/docker/seccomp.json"
}

# 创建seccomp配置文件
touch /etc/docker/seccomp.json


# 重新加载服务配置和重启docker
sudo systemctl daemon-reload
sudo systemctl restart docker

# 查看 Docker 守护进程的默认日志驱动
docker info --format '{{.LoggingDriver}}'

# 查看容器的具体日志配置
docker inspect <container_id> | grep LogConfig -A 10
```
> - 注意：日志轮转配置后仅对之后新增的容器生效,旧容器的日志不会被轮转

#### 3、Docker日志轮转
```shell
# 添加json配置
vim /etc/docker/daemon.json

{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}

# 重新加载服务配置和重启docker
sudo systemctl daemon-reload
sudo systemctl restart docker

# 查看 Docker 守护进程的默认日志驱动
docker info --format '{{.LoggingDriver}}'

# 查看容器的具体日志配置
docker inspect <container_id> | grep LogConfig -A 10
```
> - 注意：日志轮转配置后仅对之后新增的容器生效,旧容器的日志不会被轮转

### 常用功能
#### 1、清理镜像和容器
```shell
# 删除镜像
docker rmi $(docker images | grep "none" | awk '{print $3}') 

# 删除容器
docker rm $(docker ps -aq --filter "status=exited") 
```

#### 2、创建swarm集群
<h6>在Docker Swarm集群中，管理节点（Manager Nodes） 负责集群的管理和编排，工作节点（Worker Nodes） 则负责运行容器任务。管理节点数量为奇数，最少为3个。
如果只有三台服务器,那么三台服务器都建议作为manager节点,同时运行容器任务</h6>
```shell
# 创建集群,并指定manager节点的IP地址
docker swarm init --advertise-addr 10.194.66.176 --dispatcher-heartbeat 180s

# 在管理节点上获取worker或者manager的加入命令
docker swarm join-token manager
docker swarm join-token worker

# 查看节点
docker node ls

# 退出集群
docker swarm leave --force

# 添加标签
docker node update --label-add app=virtual-station-rebuild --label-add zone=hebei --label-add service=upload production2

# 查看节点信息
docker node inspect <node_id>
docker node inspect --pretty <node_id>

# 创建集群overlay网络
docker network create --driver overlay --attachable --subnet=192.168.0.0/24 --gateway=192.168.0.254  app_net
```
