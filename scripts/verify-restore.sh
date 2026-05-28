#!/bin/bash
# verify-restore.sh — 全盤還原後驗證腳本（重啟後在 J4125 執行）
# 用法: bash verify-restore.sh

PASS=0; FAIL=0

echo "=== 服務檢查 ==="
for svc in networking mihomo dnsmasq tailscaled; do
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    echo "✅ $svc"; PASS=$((PASS+1))
  else
    echo "❌ $svc"; FAIL=$((FAIL+1))
  fi
done

echo "=== 網路連通 ==="
if ping -c 1 -W 3 223.5.5.5 >/dev/null 2>&1; then
  echo "✅ 外網 DNS"; PASS=$((PASS+1))
else
  echo "❌ 外網 DNS"; FAIL=$((FAIL+1))
fi

echo "=== 配置檔案 ==="
for f in /etc/network/interfaces /etc/mihomo/config.yaml /etc/dnsmasq.conf /etc/nftables.conf; do
  if [ -f "$f" ]; then
    echo "✅ $f"; PASS=$((PASS+1))
  else
    echo "❌ $f"; FAIL=$((FAIL+1))
  fi
done

echo "=== 結果: $PASS ✅  $FAIL ❌ ==="
