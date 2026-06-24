### 1、nginx日志轮转
#### 创建配置文件
```
touch /etc/logrotate.d/nginx
```

#### 添加内容
编译安装的nginx
```
/var/log/nginx/*.log,/var/log/nginx/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 640 root root
    su root root
    sharedscripts
    postrotate
        [ -f /var/run/nginx.pid ] && kill -USR1 $(cat /var/run/nginx.pid)
    endscript
}            
```
容器化的nginx
```
/root/app/nginx/logs/*.log /root/app/nginx/logs/http/*.log /root/app/nginx/logs/stream/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 640 root root
    su root root
    sharedscripts
    postrotate
        docker kill --signal=USR1 nginx
    endscript
}            
```
```text
daily: 每天轮转一次日志文件。
rotate 7: 保留最近7天的日志文件，超过7天的旧日志会被删除。
compress: 轮转后的日志文件会被压缩，减少磁盘占用。
delaycompress: 当前日志文件在轮转后才会被压缩，避免数据丢失。
notifempty: 如果日志文件为空，则不会进行轮转操作。
create 640 nginx nginx: 创建新的日志文件时，设置权限为 640，所有者为 nginx，组为 nginx。
postrotate: 在日志轮转后执行的命令。这里通过发送 USR1 信号通知 Nginx 刷新日志文件。

```
### 测试配置 
```
# 模拟执行，检查语法
sudo logrotate -d /etc/logrotate.d/nginx

# 强制执行日志轮转
sudo logrotate -f /etc/logrotate.d/nginx
```

### 验证信号
```
# 手动向容器发送 USR1 信号
docker kill --signal=USR1 <你的Nginx容器名>

# 检查 Nginx 是否仍在正常写入新日志
tail -f /path/to/your/nginx/logs/http/access.log

# 如果日志在持续刷新，说明配置成功。
```
