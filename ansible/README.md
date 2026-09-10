# Ansible 自动化部署工具

基于 Ansible 的基础设施自动化部署方案，附赠常用 Playbook 示例。

## 目录结构

```
ansible/
├── deploy/                    # 离线部署资源（CentOS 7 / x86_64）
│   ├── install.sh             # 一键离线安装脚本
│   ├── hosts.txt              # 目标主机 IP 列表（模板）
│   └── *.rpm                  # Ansible 及依赖 RPM 包
├── docker/                    # Docker 部署（Ansible Semaphore UI）
│   └── docker-compose.yml     # Semaphore + Ansible 容器编排
└── example/                   # Playbook 使用示例
    ├── machine.yml            # 主机初始化
    ├── chrony/                # Chrony 时钟同步
    └── ntp/                   # NTP 时钟同步
```

---

## 一、Ansible 部署

### 1.1 在线安装

#### CentOS / RHEL

```bash
# CentOS 7 安装 EPEL 源后安装 Ansible
yum install -y epel-release
yum install -y ansible

# CentOS 8 / RHEL 8+
dnf install -y ansible
```

#### Ubuntu / Debian

```bash
sudo apt update
sudo apt install -y software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install -y ansible
```

#### pip 安装（跨平台）

```bash
pip3 install ansible
```

#### 验证安装

```bash
ansible --version
```

### 1.2 离线安装

适用于无外网访问的生产环境。

#### RPM 离线安装（CentOS 7）

1. 在有网络的同系统机器上下载 RPM 包及其依赖：

```bash
mkdir ansible-offline && cd ansible-offline
yum install --downloadonly --downloaddir=. ansible
```

2. 将整个目录传输至目标控制机，执行离线安装：

```bash
rpm -Uvh ./*.rpm --nodeps --force
```

3. 验证安装：

```bash
ansible --version
```

> 项目 `deploy/` 目录已提供 CentOS 7 的完整离线 RPM 包（Ansible 2.9.27），可直接使用其中的 `install.sh` 一键安装。

#### pip 离线安装

1. 下载 Ansible 及依赖包：

```bash
mkdir ansible-pip && cd ansible-pip
pip3 download ansible
```

2. 传输至目标机器后离线安装：

```bash
pip3 install --no-index --find-links=. ansible
```

### 1.3 Docker 部署（Semaphore UI）

通过 [Ansible Semaphore](https://github.com/semaphoreui/semaphore) 提供 Web 界面管理 Ansible 任务，适用于需要可视化操作和团队协作的场景。

```bash
# 使用项目提供的 docker-compose.yml
cd docker
docker-compose up -d
```

访问 `http://<主机IP>:3000` 进入 Web 管理界面。

---

## 二、控制机配置

### 2.1 SSH 密钥配置

Ansible 通过 SSH 连接目标主机，推荐使用密钥认证方式。

```bash
# 生成密钥对（RSA 4096 位）
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ''

# 分发公钥至目标主机
ssh-copy-id -i ~/.ssh/id_rsa.pub root@<目标IP>

# 批量分发（配合 sshpass）
sshpass -p '<密码>' ssh-copy-id -i ~/.ssh/id_rsa.pub -o StrictHostKeyChecking=no root@<目标IP>
```

### 2.2 主机指纹信任

首次连接目标主机时需确认指纹，可提前批量添加：

```bash
# 单台添加
ssh-keyscan -T 5 <目标IP> >> ~/.ssh/known_hosts

# 批量添加（从 IP 列表文件）
while read -r ip; do
    ssh-keyscan -T 5 "$ip" >> ~/.ssh/known_hosts 2>/dev/null
done < hosts.txt
```

### 2.3 Ansible 配置文件

Ansible 按以下顺序查找配置文件（优先级从高到低）：

1. 环境变量 `ANSIBLE_CONFIG` 指定的文件
2. 当前目录下的 `ansible.cfg`
3. 用户目录 `~/.ansible.cfg`
4. `/etc/ansible/ansible.cfg`

常用配置项：

```ini
[defaults]
inventory      = /etc/ansible/hosts      # 主机清单路径
host_key_checking = False                 # 跳过 SSH 主机指纹检查
forks          = 50                       # 并发数（默认 5）
log_path       = /var/log/ansible.log     # 日志路径
timeout        = 30                       # SSH 连接超时（秒）

[privilege_escalation]
become         = True                     # 是否提权
become_method  = sudo                     # 提权方式
become_user    = root                     # 提权目标用户
```

---

## 三、主机清单（Inventory）

Inventory 是 Ansible 管理目标主机的配置文件，支持 INI 和 YAML 两种格式。

### 3.1 基本格式（INI）

```ini
# 未分组主机
10.194.65.130
10.194.65.131

# 按架构分组
[x86_64]
10.194.65.130
10.194.65.131

[arm64]
10.194.68.221
10.194.68.222

# 按功能分组
[ntp_server]
10.194.66.30

[ntp_client]
10.194.65.130
10.194.65.131
```

### 3.2 主机变量

在 Inventory 中直接为主机指定连接参数：

```ini
# SSH 密码认证
10.194.65.130  ansible_ssh_user="root" ansible_ssh_pass="your_password"

# 非 root 用户 + sudo 提权
10.194.65.131  ansible_ssh_user="deploy" ansible_ssh_pass="deploy_pass" ansible_become_method="sudo" ansible_become_user="root" ansible_become_pass="sudo_pass"

# 自定义 SSH 端口
10.194.65.132  ansible_ssh_port=2222 ansible_ssh_user="root"
```

### 3.3 组变量

为整组主机统一设置变量：

```ini
[x86_64:vars]
ansible_ssh_user="root"
ansible_ssh_pass="default_password"

[ntp_client:vars]
ntp_server_ip="10.194.66.30"
```

### 3.4 嵌套分组

```ini
[redis]
10.194.65.130

[mysql]
10.194.65.131

# 将多个子组合并为父组
[database:children]
redis
mysql
```

### 3.5 常用 Inventory 变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `ansible_ssh_user` | SSH 登录用户 | 当前用户 |
| `ansible_ssh_pass` | SSH 登录密码 | — |
| `ansible_ssh_port` | SSH 端口 | 22 |
| `ansible_ssh_private_key_file` | 私钥文件路径 | `~/.ssh/id_rsa` |
| `ansible_become_method` | 提权方式 | `sudo` |
| `ansible_become_user` | 提权目标用户 | `root` |
| `ansible_become_pass` | 提权密码 | — |
| `ansible_python_interpreter` | Python 解释器路径 | 自动检测 |

---

## 四、Playbook 编写与执行

Playbook 是 Ansible 的任务编排文件，使用 YAML 格式描述目标主机上要执行的操作。

### 4.1 基本结构

```yaml
---
- name: Play 名称            # Play 的描述信息
  hosts: all                  # 目标主机组
  become: yes                 # 是否提权
  ignore_errors: true         # 忽略错误继续执行
  vars:                       # 变量定义
    key: value
  tasks:                      # 任务列表
    - name: 任务描述
      模块名:
        参数: 值
      tags:
        - tag_name
  handlers:                   # 处理器（由 notify 触发）
    - name: 处理器名称
      模块名:
        参数: 值
```

### 4.2 常用模块

| 模块 | 用途 | 示例 |
|------|------|------|
| `ping` | 测试主机连通性 | `ansible all -m ping` |
| `shell` | 执行 Shell 命令 | `shell: uptime` |
| `copy` | 复制文件到远端 | `copy: src=./file dest=/tmp/file` |
| `template` | 渲染模板文件到远端 | `template: src=app.conf.j2 dest=/etc/app.conf` |
| `file` | 创建/删除目录和文件 | `file: path=/opt/app state=directory mode=0755` |
| `unarchive` | 解压文件 | `unarchive: src=app.tar.gz dest=/opt/ remote_src=yes` |
| `yum` / `dnf` | 包管理 | `yum: name=nginx state=present` |
| `service` / `systemd` | 服务管理 | `systemd: name=nginx state=started enabled=yes` |
| `lineinfile` | 修改文件中的单行 | `lineinfile: path=/etc/hosts line='127.0.0.1 localhost'` |
| `authorized_key` | 管理 SSH 公钥 | `authorized_key: user=root key="{{ lookup('file', '~/.ssh/id_rsa.pub') }}"` |
| `user` | 管理用户 | `user: name=appuser groups=docker append=yes` |
| `cron` | 管理定时任务 | `cron: name="sync" job="ntpdate pool.ntp.org" minute=0` |

### 4.3 条件与循环

**条件判断**：使用 `when` 按条件执行任务

```yaml
- name: 仅在 x86_64 组安装
  shell: rpm -Uvh /opt/app/*.rpm --nodeps --force
  when: inventory_hostname in groups['x86_64']

- name: 仅在 CentOS 系统执行
  yum: name=nginx state=present
  when: ansible_facts['os_family'] == 'RedHat'
```

**循环**：使用 `loop` 批量操作

```yaml
- name: 创建多个目录
  file:
    path: "{{ item }}"
    state: directory
  loop:
    - /opt/app/logs
    - /opt/app/data
    - /opt/app/conf
```

### 4.4 触发器（Handlers）

Handlers 不会立即执行，而是由任务的 `notify` 触发，且在所有 tasks 执行完毕后统一运行。适合用于服务重启等场景。

```yaml
tasks:
  - name: 修改网卡配置
    lineinfile:
      path: /etc/sysconfig/network-scripts/ifcfg-eth0
      regexp: '^IPADDR='
      line: 'IPADDR={{ inventory_hostname }}'
    notify:
      - Restart network

handlers:
  - name: Restart network
    service:
      name: network
      state: restarted
```

### 4.5 Tags 标签

为任务打标签，支持按标签选择性执行或跳过：

```yaml
tasks:
  - name: 安装 Chrony 包
    yum: name=chrony state=present
    tags:
      - chrony

  - name: 推送 Chrony 配置
    copy: src=./chrony.conf dest=/etc/chrony.conf
    tags:
      - chrony_client

  - name: 启动 Chrony 服务
    service: name=chronyd state=started
    tags:
      - chrony_client
```

```bash
# 仅执行 chrony 相关任务
ansible-playbook -i hosts playbook.yml --tags "chrony"

# 跳过 chrony_client 任务
ansible-playbook -i hosts playbook.yml --skip-tags "chrony_client"
```

---

## 五、项目示例说明

### 示例 1：主机初始化

`example/machine.yml` 完成新主机的初始化操作：

- 分发 SSH 公钥至目标主机
- 配置网卡 `eth0` 为开机自启并设置 IP 地址
- 关闭 firewalld 防火墙
- 禁用 SELinux
- 重启 Docker 服务

```bash
ansible-playbook -i your_hosts machine.yml
```

### 示例 2：Chrony 时钟同步

`example/chrony/` 部署 Chrony 时间同步服务，通过 `[x86_64]` 和 `[arm64]` 分组区分架构：

```bash
cd example/chrony

# 完整安装与配置
ansible-playbook -i chrony_hosts chrony.yml

# 仅安装软件包
ansible-playbook -i chrony_hosts chrony.yml --tags "chrony"

# 仅推送配置并重启
ansible-playbook -i chrony_hosts chrony.yml --tags "chrony_client"
```

### 示例 3：NTP 时钟同步

`example/ntp/` 部署 NTP 时间同步服务，通过 `[ntp_server]` 和 `[ntp_client]` 分组为不同角色推送对应配置：

```bash
cd example/ntp
ansible-playbook -i ntp_hosts ntp.yml
```

---

## 六、常用命令速查

### 主机管理

```bash
# 测试所有主机连通性
ansible -i hosts all -m ping

# 查看主机信息
ansible -i hosts all -m setup

# 在所有主机上执行命令
ansible -i hosts all -m shell -a "uptime"

# 指定分组执行
ansible -i hosts x86_64 -m shell -a "hostname"
```

### Playbook 执行

```bash
# 执行完整 Playbook
ansible-playbook -i hosts playbook.yml

# 语法检查（不实际执行）
ansible-playbook -i hosts playbook.yml --syntax-check

# 模拟执行（Dry Run）
ansible-playbook -i hosts playbook.yml -C

# 查看主机列表
ansible-playbook -i hosts playbook.yml --list-hosts

# 查看任务列表
ansible-playbook -i hosts playbook.yml --list-tasks
```

### Tags 过滤

```bash
# 仅执行指定 Tag 的任务
ansible-playbook -i hosts playbook.yml --tags "chrony"

# 执行多个 Tag
ansible-playbook -i hosts playbook.yml --tags "redis,nginx"

# 跳过指定 Tag
ansible-playbook -i hosts playbook.yml --skip-tags "loki,promtail"
```

### 调试排错

```bash
# 详细输出（-v / -vv / -vvv 逐级递增）
ansible-playbook -i hosts playbook.yml -vvv

# 从某个任务开始执行
ansible-playbook -i hosts playbook.yml --start-at-task="Start NTP service"

# 限制单台主机执行（调试用）
ansible-playbook -i hosts playbook.yml --limit "10.194.65.130"
```

---

## 七、注意事项

1. **操作系统兼容性**：目标主机需安装 Python 2.7 或 Python 3.x，CentOS 7 默认自带 Python 2.7。
2. **SSH 连接**：确保控制机到目标主机的 SSH 端口（默认 22）网络可达。
3. **密码安全**：Inventory 文件中包含明文密码时，请注意文件权限控制（`chmod 600`），生产环境建议使用 SSH 密钥认证或 [ansible-vault](https://docs.ansible.com/ansible/latest/user_guide/vault.html) 加密敏感变量。
4. **幂等性**：大部分 Ansible 模块具有幂等性，重复执行不会产生副作用，可放心多次运行 Playbook。
5. **并发控制**：默认并发数为 5，大规模主机场景建议在 `ansible.cfg` 中调大 `forks` 参数。
6. **防火墙影响**：关闭 firewalld 后可能影响 Docker 网络转发，需重启 Docker 服务。
