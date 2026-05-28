# J4125 備份還原保障方案 v6（最終版）

適用系統：J4125 Debian 13 路由器  
系統狀態：✅ SSH 正常（2026-05-28 確認）  
路徑約定：`{{USB}}` = `/mnt/usb/`，`{{HDD}}` = 待 HDD 到貨確認

---

## 三種還原場景總覽

| 場景 | 適用時機 | 所需工具 | 時間 | 風險 |
|------|----------|----------|------|------|
| 全盤還原 | 系統無法啟動、更換 SSD | Live USB + 備份 USB | 30-60 分鐘 | 中 |
| 設置還原 | 系統可啟動，配置損壞 | SSH + Git + 配置包 | 5-10 分鐘 | 低 |
| 單項還原 | 單一配置改壞了 | SSH + Git | 1-2 分鐘 | 極低 |

---

## 場景一：全盤還原

**適用時機：** 系統無法啟動、更換 SSD、需要回到特定時間點的快照

**前提條件：**
- ✅ 有 fsfreeze 完整備份（j4125-*-full.img.gz）
- ✅ 壓縮包可 gunzip -t 檢查完整性
- ✅ 需要 Live USB（SystemRescue 或 Ubuntu Live）
- ✅ 目標磁碟容量 ≥ 250GB
- ⚠️ HDD 到後可做完整 fsck 深度驗證

**還原腳本：** `scripts/restore-full.sh`

```bash
set -euo pipefail

BACKUP_FILE="${1:-$(ls -t /mnt/usb/j4125-*-full.img.gz 2>/dev/null | head -1)}"
TARGET_DISK="${2:-/dev/sda}"

# 1. gunzip -t 檢查壓縮包完整性
gunzip -t "$BACKUP_FILE" || exit 1

# 2. 讀取分區表確認鏡像
zcat "$BACKUP_FILE" | dd bs=4M count=1 2>/dev/null | fdisk -l /dev/stdin

# 3. 顯示目標磁碟 → 輸入 YES 確認
lsblk "$TARGET_DISK"
read -p "⚠️ 將覆寫 $TARGET_DISK，輸入 YES 確認: " confirm
[ "$confirm" = "YES" ] || exit 1

# 4. 寫入鏡像（pigz 優先，gunzip 回退）
if command -v pigz &>/dev/null; then
  pigz -dc -p 1 "$BACKUP_FILE" | dd of="$TARGET_DISK" bs=4M status=progress
else
  gunzip -c "$BACKUP_FILE" | dd of="$TARGET_DISK" bs=4M status=progress
fi

sync && sync
echo "✅ 還原完成。拔出 Live USB，重啟。"
```

**還原後驗證：** `scripts/verify-restore.sh`

```bash
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
  echo "✅ 外網"; PASS=$((PASS+1))
else
  echo "❌ 外網"; FAIL=$((FAIL+1))
fi

echo "=== 配置檔案 ==="
for f in /etc/network/interfaces /etc/mihomo/config.yaml /etc/dnsmasq.conf /etc/nftables.conf; do
  [ -f "$f" ] && echo "✅ $f" || echo "❌ $f"
done

echo "=== 結果: $PASS ✅  $FAIL ❌ ==="
```

---

## 場景二：設置還原

**適用時機：** 系統能 SSH 登入，配置損壞或丟失，不需 Live USB

**前提條件：**
- ✅ 系統能 SSH 登入
- ✅ GitHub repo：github.com/spinstein/J4125
- ✅ 配置備份包在 `/mnt/usb/j4125/configs-*.tar.gz` 或 `/data/auto-backup/j4125/`

**還原腳本：** `scripts/restore-config.sh`（完整流程）

```bash
set -euo pipefail

# Git 模式：從 GitHub 拉取最新配置腳本
if [ "${1:-}" = "--git" ]; then
  cd /root
  [ -d j4125 ] || git clone https://github.com/spinstein/j4125.git
  cd j4125 && git pull
  exit 0
fi

# 定位備份包（自動找最新或指定路徑）
BACKUP_FILE=$(ls -t /mnt/usb/j4125/configs-*.tar.gz 2>/dev/null | head -1)
[ -z "$BACKUP_FILE" ] && BACKUP_FILE=$(ls -t /data/auto-backup/j4125/configs-*.tar.gz 2>/dev/null | head -1)

# [1/4] gunzip -t 完整性檢查
gunzip -t "$BACKUP_FILE" || exit 1

# [2/4] 還原前備份當前配置（安全回滾）
BACKUP_DIR="/tmp/config-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
for conf in network/interfaces mihomo/config.yaml dnsmasq.conf nftables.conf; do
  cp -f "/etc/$conf" "$BACKUP_DIR/$conf" 2>/dev/null || true
done

# [3/4] 解壓備份包（支援 etc_xxx/ etc/ j4125-configs/ 三種格式）
WORKDIR=$(mktemp -d)
tar xzf "$BACKUP_FILE" -C "$WORKDIR"

# 還原配置，兼容多種備份包命名格式
for conf in network/interfaces mihomo/config.yaml dnsmasq.conf nftables.conf; do
  src="$WORKDIR/etc_$conf"
  [ ! -f "$src" ] && src="$WORKDIR/etc/$conf"
  [ ! -f "$src" ] && src="$WORKDIR/j4125-configs/etc-$(echo $conf | tr '/' '-')"
  [ -f "$src" ] && cp -f "$src" "/etc/$conf"
done

# [4/4] sync → 重啟服務（sleep 2 等網橋就緒）
sync
systemctl restart networking || true
sleep 2
systemctl restart dnsmasq || true
systemctl restart mihomo 2>/dev/null || true

rm -rf "$WORKDIR"
```

**還原前最佳做法：**
```bash
# 先 diff 確認差異，再執行還原
LATEST=$(ls -t /mnt/usb/j4125/configs-*.tar.gz | head -1)
tar xzf "$LATEST" -C /tmp/restore-test/
diff /tmp/restore-test/etc_dnsmasq.conf /etc/dnsmasq.conf
diff /tmp/restore-test/etc_nftables.conf /etc/nftables.conf
# 確認無誤後，執行 restore-config.sh
bash /root/j4125/scripts/restore-config.sh
```

---

## 場景三：單項還原

**適用時機：** 單一服務配置改壞了，從 Git 回退

```bash
cd /root/j4125
git log --oneline -5
git checkout <hash> -- mihomo/config.yaml
cp mihomo/config.yaml /etc/mihomo/
systemctl restart mihomo
```

---

## 備份驗證體系

| 層級 | 頻率 | 位置 | 內容 | 時間 |
|------|------|------|------|------|
| L1 快速驗證 | 每次備份後 | USB | gunzip -t + fdisk 分區表 | 幾秒 |
| L2 深度驗證 | 每週 / HDD 到後 | HDD | 解壓 → losetup → fsck | 30 分鐘 |
| L3 異地驗證 | 月度 | 阿里雲 ECS | 從 GD 拉備份，完整 fsck + 報告 | 非同步 |

**L1 驗證：**
```bash
gunzip -t /mnt/usb/j4125-20260527-full.img.gz    # 壓縮包沒壞？
zcat ... | dd bs=4M count=1 | fdisk -l /dev/stdin  # 分區表可讀？
```

**L2 深度驗證：** `scripts/deep-verify.sh`（需 HDD 250GB+ 空間）

---

## Manifest（備份歷史記錄）

存於 `/data/auto-backup/j4125/manifest.yaml`：

```yaml
- version: v1
  date: 2026-05-27_14:00
  type: config
  file: configs-20260527-1400.tar.gz
  restore: 設置還原 / 單項還原

- version: v7
  date: 2026-05-27_21:00
  type: config
  file: configs-20260527-2100.tar.gz
  restore: 設置還原 / 單項還原

- version: full-v1
  date: 2026-05-27_21:00
  type: full
  file: j4125-20260527-full.img.gz
  fsfreeze: true
  verify: gunzip-t + 分區表 OK
  restore: 全盤還原（需 Live USB）
```

---

## 方案邊界 ⚠️

1. **gunzip -t 只能驗證壓縮包沒壞**，不能檢查文件內部完整性 — 深度 fsck 需 HDD
2. **SSD 壞道風險** — dd 讀取時可能靜默跳過，L2 深度驗證可捕獲
3. **最終保險** — 還原後跑 verify-restore.sh，服務能啟 + 網路通 = 系統可用
4. **配置備份範圍有限** — 目前 4 個核心配置，新增配置需補充到備份清單
5. **不能跨系統版本恢復** — 全盤 dd 鏡像需 ≥250GB 的同類磁碟
6. **dnsmasq 啟動順序** — networking 重啟後需等網橋就緒（腳本已含 sleep 2）

---

## 2026-05-28 測試驗證記錄

**設置還原測試結果：**

| 環節 | 結果 |
|------|------|
| 備份包預覽 | ✅ |
| gunzip -t 完整性檢查 | ✅ |
| diff 比對備份 vs 當前配置 | ✅ 一致 |
| 還原前備份當前配置 | ✅ |
| 4 個配置文件寫回 | ✅ |
| networking 重啟 | ✅ |
| dnsmasq 重啟 | ⚠️ 首次失敗（br-lan 未就緒），修復腳本後 ✅ |
| mihomo 重啟 | ✅ |
| verify-restore.sh | ✅ 服務正常 |
| 外網連通 | 🟡 線未接，跳過 |

**發現並修復的 bug：**
- `systemctl restart networking dnsmasq` 在同一行執行，dnsmasq 啟動時 br-lan 網橋尚未就緒 → 加 `sleep 2` 隔開
- `restore-config.sh` 缺少還原前自動備份 → 已加 `[2/4] 備份當前配置`
- 備份包有三種命名格式（etc_/ etc/ j4125-configs/），腳本無法處理 → 已加格式兼容邏輯

---

## 後續可加強的方向

| 優先級 | 事項 | 預計時間 | 依賴 |
|--------|------|----------|------|
| 🔴 | 配置腳本化（setup.sh/install.sh）推 GitHub | 本週 | — |
| 🟡 | Timeshift 安裝 + 自動快照配置 | HDD 到後 | HDD |
| 🟡 | 深度 fsck 驗證腳本（L2）納入 cron | HDD 到後 | HDD |
| 🟢 | 每月自動化還原測試（restore drill） | 月度 | HDD + cron |
