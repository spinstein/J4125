#!/bin/bash
# restore-config.sh — J4125 配置還原（SSH 環境執行）
# 用法:
#   bash restore-config.sh              # 自動找最新備份包
#   bash restore-config.sh --git        # 從 GitHub 拉取
#   bash restore-config.sh --backup /path/to/configs-*.tar.gz  # 指定包
#
# 還原項目: network/interfaces, mihomo/config.yaml, dnsmasq.conf, nftables.conf

set -euo pipefail

# --- Git 模式 ---
if [ "${1:-}" = "--git" ]; then
  echo "=== 從 GitHub 拉取 ==="
  cd /root
  [ -d j4125 ] || git clone https://github.com/spinstein/j4125.git
  cd j4125 && git pull
  echo "✅ 完成，執行對應 setup.sh"
  exit 0
fi

# --- 定位備份包 ---
BACKUP_FILE=""
if [ "${1:-}" = "--backup" ] && [ -n "${2:-}" ]; then
  BACKUP_FILE="$2"
else
  BACKUP_FILE=$(ls -t /mnt/usb/j4125/configs-*.tar.gz 2>/dev/null | head -1)
  [ -z "$BACKUP_FILE" ] && BACKUP_FILE=$(ls -t /data/auto-backup/j4125/configs-*.tar.gz 2>/dev/null | head -1)
fi

[ -z "$BACKUP_FILE" ] && { echo "❌ 找不到備份包"; exit 1; }
echo "=== 備份包: $BACKUP_FILE ==="

# --- 完整性檢查 ---
echo "[1/4] gunzip -t 完整性檢查"
gunzip -t "$BACKUP_FILE" && echo "✅" || { echo "❌ 壓縮包損壞"; exit 1; }

# --- 還原前備份當前配置 ---
echo "[2/4] 備份當前配置"
BACKUP_DIR="/tmp/config-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
for conf in network/interfaces mihomo/config.yaml dnsmasq.conf nftables.conf; do
  src="/etc/$conf"
  if [ -f "$src" ]; then
    mkdir -p "$(dirname "$BACKUP_DIR/$conf")"
    cp -f "$src" "$BACKUP_DIR/$conf"
  fi
done
echo "✅ 當前配置已備份到 $BACKUP_DIR"
echo "   如需回滾：cp -r $BACKUP_DIR/* / 或逐文件回復"

# --- 解壓 ---
WORKDIR=$(mktemp -d)
tar xzf "$BACKUP_FILE" -C "$WORKDIR"
echo "[3/4] 已解壓到 $WORKDIR"

# --- 還原配置 ---
echo "[4/4] 還原配置檔案"
MISSING=0
for conf in network/interfaces mihomo/config.yaml dnsmasq.conf nftables.conf; do
  # 兼容兩種備份包格式：etc_xxx/xxx 或 etc/xxx
  src="$WORKDIR/etc_$conf"
  [ ! -f "$src" ] && src="$WORKDIR/etc/$conf"
  [ ! -f "$src" ] && src="$WORKDIR/j4125-configs/etc-$(echo $conf | tr '/' '-')"
  
  dst="/etc/$conf"
  if [ -f "$src" ]; then
    cp -f "$src" "$dst" && echo "✅ $conf"
  else
    echo "⚠️ $conf 不在備份包中（跳過）"
    MISSING=$((MISSING+1))
  fi
done

# --- sync 後重啟服務 ---
sync
systemctl restart networking || true
sleep 2
systemctl restart dnsmasq || true
systemctl restart mihomo 2>/dev/null || echo "⚠️ mihomo 重啟報錯（手動檢查）"

rm -rf "$WORKDIR"
echo "=== 還原完成 ==="

if [ "$MISSING" -gt 0 ]; then
  echo "⚠️ 有 $MISSING 個文件跳過，建議檢查備份包完整性"
fi
echo "✅ 建議執行 verify-restore.sh 確認"
echo "💡 如需回滾：cp -r $BACKUP_DIR/* /"
