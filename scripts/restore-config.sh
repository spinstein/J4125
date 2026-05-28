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
echo "[1/3] gunzip -t 完整性檢查"
gunzip -t "$BACKUP_FILE" && echo "✅" || { echo "❌ 壓縮包損壞"; exit 1; }

# --- 解壓 ---
WORKDIR=$(mktemp -d)
tar xzf "$BACKUP_FILE" -C "$WORKDIR"
echo "[2/3] 已解壓到 $WORKDIR"

# --- 還原配置 ---
echo "[3/3] 還原配置檔案"
MISSING=0
for conf in network/interfaces mihomo/config.yaml dnsmasq.conf nftables.conf; do
  src="$WORKDIR/etc/$conf"
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
systemctl restart networking dnsmasq || true
systemctl restart mihomo 2>/dev/null || echo "⚠️ mihomo 重啟報錯（手動檢查）"

rm -rf "$WORKDIR"
echo "=== 還原完成 ==="

if [ "$MISSING" -gt 0 ]; then
  echo "⚠️ 有 $MISSING 個文件跳過，建議檢查備份包完整性"
fi
echo "✅ 建議執行 verify-restore.sh 確認"
