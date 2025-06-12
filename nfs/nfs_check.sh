#!/bin/bash
LOG_FILE="/etc/keepalived/nfs_ha.log"
COUNTER_FILE="/etc/keepalived/nfs_ha_counter"

# 自动获取共享路径（兼容IPv6和复杂路径）
SERVER_SHARE=$(awk '!/^#/ && $1 {print $1; exit}' /etc/exports)
[ -z "$SERVER_SHARE" ] && SERVER_SHARE="/data/nfs_share"

# 初始化计数器
[ -f "$COUNTER_FILE" ] || echo 0 > "$COUNTER_FILE"
counter=$(cat "$COUNTER_FILE")
counter=$(( (counter + 1) % 12 ))
echo $counter > "$COUNTER_FILE"  # 保存新计数

# 智能日志记录（异常时写入）
log() {
  if grep -q "异常\|失败\|错误" <<<"$1"; then
    [ ! -f "$LOG_FILE" ] && touch "$LOG_FILE"
    # 日志轮转（保留最新1000行）
    [ $(wc -l < "$LOG_FILE") -gt 1000 ] && sed -i '1,100d' "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
  fi
}

# 基础检测（高频）
check_ports() {
  ss -tuln | grep -Pq ':(111|2049)\b' || {
    log "端口异常：111(RPC)或2049(NFS)未监听";
    return 1;
  }
}

check_processes() {
  systemctl is-active nfs-server &>/dev/null && \
  pgrep -x 'nfsd|rpcbind' >/dev/null || {
    log "进程异常：nfsd/rpcbind未运行";
    return 1;
  }
}

# 服务层检测（中频）
check_rpc() {
  timeout 2 rpcinfo -t localhost nfs &>/dev/null || {
    log "RPC异常：nfs服务未注册";
    return 1;
  }
  timeout 2 showmount -e localhost &>/dev/null || {
    log "NFS共享异常：导出列表获取失败";
    return 1;
  }
}

# 数据层检测（低频）
check_write() {
  local testfile="${SERVER_SHARE}/.nfs_ha_test_$(hostname)"
  if ! touch "$testfile" 2>/dev/null; then
    log "写入失败：${SERVER_SHARE}不可写(权限/磁盘满)";
    return 1
  fi
  rm -f "$testfile" 2>/dev/null
}

# 高频检测（每次都会执行）
check_ports && check_processes || exit 1

# 中频检测（每2次脚本执行才执行一次）
[ $((counter % 2)) -eq 0 ] && { check_rpc || exit 1; }

# 低频检测（每12次脚本执行才执行一次）
[ $counter -eq 0 ] && {
  check_write || exit 1
}

exit 0
