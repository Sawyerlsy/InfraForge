### 国产化问题集锦
##### 1、银河麒麟系统可能预装了 Podman，而 Podman 与 Docker 的守护进程（dockerd）存在冲突。当两者同时运行时，可能导致权限问题
```shell
# 卸载 Podman
sudo yum remove podman -y
# 重启 Docker
sudo systemctl restart docker
```
