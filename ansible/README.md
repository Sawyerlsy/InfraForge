## 一、常用命令
#### 1、
```shell
ansible-playbook -i chrony_hosts chrony.yml

ansible-playbook playbook.yml --tags "redis,nginx"

ansible-playbook playbook.yml --skip-tags "loki,promtail"
```
