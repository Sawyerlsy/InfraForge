```shell
# 启动 chronyd 服务并设为开机自启
sudo systemctl enable --now chronyd
# 说明：
# enable: 配置服务在系统启动时自动运行。
# --now: 同时立即启动服务。
# CentOS/RHEL 系的服务名称为 `chronyd`。

# 查看时间源状态
chronyc sources -v
# 输出说明：
# * 表示当前使用的时间源
# + 表示可用的备用时间源
# ? 表示不可用的时间源

chronyc sourcestats

# 查看跟踪信息（关键命令）
# 关注 Last offset等值，它们应该很小（通常是几毫秒或几十毫秒），表示同步良好
chronyc tracking
# 输出示例：
# Reference ID    : C0A80164 (192.168.1.100)
# Stratum         : 3
# Ref time (UTC)  : Thu Dec 11 08:00:00 2023
# System time     : 0.000000 seconds slow of NTP time
# Last offset     : +0.000123 seconds
# RMS offset      : 0.000456 seconds
# Frequency       : 16.234 ppm slow
# Residual freq   : +0.001 ppm
# Skew            : 0.012 ppm
# Root delay      : 0.001234 seconds
# Root dispersion : 0.002345 seconds
# Update interval : 64.2 seconds
# Leap status     : Normal

# 查看详细的同步状态
chronyc ntpdata

# 检查系统时间
timedatectl status

# 查看NTP服务器列表
chronyc activity


# 强制同步
chronyc -a makestep

```
