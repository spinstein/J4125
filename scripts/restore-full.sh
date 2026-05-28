#!/bin/bash
# restore-full.sh — J4125 全盤還原（Live USB 環境下執行）
# 用法: bash restore-full.sh [備份文件] [目標磁碟]
# 默認: 自動找 USB 上最新鏡像，寫入 /dev/sda

set -euo pipefail

BACKUP_FILE="${1:-$(ls -t /mnt/usb/j4125-*-full.img.gz 2>/dev/null | head -1)}"
TARGET_DISK="${2:-/dev/sda}"

[ -z "$BACKUP_FILE" ] && { echo "❌ 找不到備份文件"; exit 1; }
[ ! -f "$BACKUP_FILE" ] && { echo "❌ 文件不存在: $BACKUP_FILE"; exit 1; }

echo "=== $BACKUP_FILE → $TARGET_DISK ==="

echo "[1/4] gunzip -t 完整性檢查"
gunzip -t "$BACKUP_FILE" && echo "✅" || { echo "❌ 壓縮包損壞"; exit 1; }

echo "[2/4] 讀取分區表"
zcat "$BACKUP_FILE" | dd bs=4M count=1 2>/dev/null | fdisk -l /dev/stdin || true

echo "[3/4] 確認目標磁碟"
lsblk "$TARGET_DISK"
read -p "⚠️ 將覆寫 $TARGET_DISK，輸入 YES 確認: " confirm
[ "$confirm" = "YES" ] || { echo "已取消"; exit 1; }

echo "[4/4] 寫入鏡像（30-60 分鐘）"
if command -v pigz &>/dev/null; then
  pigz -dc -p 1 "$BACKUP_FILE" | dd of="$TARGET_DISK" bs=4M status=progress
else
  gunzip -c "$BACKUP_FILE" | dd of="$TARGET_DISK" bs=4M status=progress
fi

sync && sync
echo "✅ 還原完成。拔出 Live USB，重啟。"
