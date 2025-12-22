## 一、CentOS
#### 1、在联网的“制备机”上准备离线安装包 (RPM)
```shell
# 步骤 1：安装必要的下载工具
sudo yum install -y yum-utils
# 说明：yum-utils 工具包提供了 yumdownloader 命令，用于下载RPM包及其依赖。

# 步骤 2：创建专用目录并进入
mkdir -p chrony-offline/centos && cd chrony-offline/centos
# 说明：创建一个独立的目录来存放所有相关文件，避免混乱。

# 步骤 3：下载 chrony 及其所有依赖包
# yumdownloader --resolve --destdir=/opt/ansible_offline ansible
yumdownloader --resolve chrony
# 说明：
# --resolve 参数是核心，它会自动分析并下载 chrony 软件运行所需的所有依赖包。
# 执行后，当前目录会生成一系列 .rpm 文件。

# 步骤 4：打包所有文件以便传输
tar -czf ../chrony-offline-centos.tar.gz .
# 说明：将当前目录所有文件打包成一个压缩文件，便于复制到离线环境。
```
#### 2、在离线的“目标机”上安装与配置
```shell
# 步骤 1：解压离线安装包
cd /tmp
tar -xzf chrony-offline-centos.tar.gz
# 说明：进入文件所在目录并解压。

# 步骤 2：安装所有 RPM 包
sudo rpm -Uvh *.rpm --nodeps --force
# 说明：
# -Uvh: U（升级/安装），v（显示详细信息），h（显示进度条）。
# --nodeps --force: 在离线环境中，忽略非关键性依赖警告并强制安装，确保所有包都被安装。

# 步骤 3：备份原始配置文件（重要）
sudo cp /etc/chrony.conf /etc/chrony.conf.bak
# 说明：任何配置修改前都应备份，以便出错时回滚。

# 步骤 4：编辑 chrony 配置文件
sudo vi /etc/chrony.conf
# 说明：使用 vi 编辑器（也可使用 nano 如果已安装）。在文件中进行以下修改：
# 1. 注释掉（在行首添加#）或删除所有以 `server` 或 `pool` 开头的现有时间服务器配置行。
# 2. 在文件末尾或合适位置，添加指向内部时间服务器的配置：
#    server 10.194.66.30 iburst
#    参数 `iburst` 可在启动时快速发起一系列同步请求，加速初始同步过程。
# 3. （可选但建议）为了在网络隔离时仍能提供一致的时间，可以添加：
#    local stratum 10
#    这允许本地时钟在失去所有上级源时，仍可作为时间源（层级为10）。

# 步骤 5：启动 chronyd 服务并设为开机自启
sudo systemctl enable --now chronyd
# 说明：
# enable: 配置服务在系统启动时自动运行。
# --now: 同时立即启动服务。
# CentOS/RHEL 系的服务名称为 `chronyd`。

# 步骤 6：检查服务运行状态
sudo systemctl status chronyd
# 说明：确认服务状态为 “active (running)”。按 `q` 键可退出状态视图。
```
## 二、Ubuntu
#### 1、在联网的“制备机”上准备离线安装包 (DEB)
```shell
# 步骤 1：更新软件包列表
sudo apt-get update
# 说明：确保本地软件包缓存信息是最新的，以便正确解析依赖关系。

# 步骤 2：创建专用目录并进入
mkdir -p chrony-offline/ubuntu && cd chrony-offline/ubuntu

# 步骤 3：下载 chrony 及其所有依赖包
# 这是一个复合命令，分步解析如下：
# 1. `apt-cache depends chrony`: 列出chrony的依赖关系。
# 2. `--recurse, --no-recommends...`: 递归列出所有必须的依赖，并过滤掉推荐、建议等非必须包。
# 3. `grep "^\w"`: 使用正则表达式提取出纯软件包名称行。
# 4. `apt-get download`: 下载前面列出的所有软件包。
# apt-get download默认情况下不允许使用root用户进行下载,如果提示相关问题,可以考虑切换用户
apt-get download $(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances chrony | grep "^\w")

# 步骤 4：打包所有文件以便传输
tar -czf ../chrony-offline-ubuntu.tar.gz .
# 说明：将当前目录所有 .deb 文件打包。
```
#### 2、在离线的“目标机”上安装与配置
```shell
# 步骤 1：解压离线安装包
cd /tmp
tar -xzf chrony-offline-ubuntu.tar.gz

# 卸载自带的时钟同步服务
sudo dpkg --purge systemd-timesyncd

# 步骤 2：安装所有 DEB 包
sudo dpkg -i *.deb
# 说明：`dpkg -i` 用于安装 .deb 格式的软件包。如果提示依赖问题，在本场景下通常是因为所有依赖包已包含在当前目录，可以继续。

# 步骤 3：备份原始配置文件（重要）
sudo cp /etc/chrony/chrony.conf /etc/chrony/chrony.conf.bak
# 注意：Ubuntu的配置文件路径与CentOS不同，位于 `/etc/chrony/` 目录下。

# 步骤 4：编辑 chrony 配置文件
sudo nano /etc/chrony/chrony.conf
# 说明：Ubuntu 默认通常安装 nano 编辑器，更适合初学者。同样进行以下修改：
# 1. 注释掉或删除所有 `pool` 或 `server` 开头的行。
# 2. 添加：server 10.194.66.30 iburst
# 3. （可选）添加：local stratum 10

# 步骤 5：启动 chrony 服务并设为开机自启
sudo systemctl enable --now chrony
# 注意：Ubuntu/Debian 系的服务名称为 `chrony`（没有末尾的 ‘d’）。

# 步骤 6：检查服务运行状态
sudo systemctl status chrony
```
## 三、常用资源地址
