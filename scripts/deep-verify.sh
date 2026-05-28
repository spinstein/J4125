#!/bin/bash
# deep-verify.sh — 完整文件系統級驗證（需 HDD 250GB+ 空間）
# 用法: bash deep-verify.sh [備份文件]
# 默認: 自動找 USB 上最新全盤鏡像

set -euo pipefail

BACKUP_FILE="${1:-$(ls -t /mnt/usb/j4125-*-full.img.gz 2>/dev/null | head -1)}"
[ -z "$BACKUP_FILE" ] && { echo "❌ 找不到備份文件"; exit 1; }

VERIFY_IMG="/mnt/hdd/verify-$(date +%Y%m%d).img"

echo "[1/4] gunzip -t"
gunzip -t "$BACKUP_FILE" || exit 1

echo "[2/4] 解壓到 HDD"
pigz -dc "$BACKUP_FILE" > "$VERIFY_IMG"

echo "[3/4] losetup + fsck"
losetup /dev/loop0 "$VERIFY_IMG" || { echo "❌ losetup 失敗"; exit 1; }
partx -a /dev/loop0 2>/dev/null || true
fsck -n /dev/loop0p2; r=$?
losetup -d /dev/loop0

echo "[4/4] 清理"
rm -f "$VERIFY_IMG"

case $r in
  0) echo "✅ 文件系統乾淨";;
  1) echo "⚠️ 已修復";;
  2) echo "❌ 需重啟修復"; exit 2;;
  *) echo "❌ fsck 錯誤 $r"; exit $r;;
esac
