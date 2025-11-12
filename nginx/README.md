### 1、常用配置

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
