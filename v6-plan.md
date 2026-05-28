# J4125 備份還原保障方案 v6

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
- ✅ 需要 Live USB（SystemRescue 或 Ubuntu Live，自帶 pigz/gunzip + dd + fdisk）
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

---

## 場景二：設置還原

**適用時機：** 系統能 SSH 登入，配置損壞或丟失，不需 Live USB

**前提條件：**
- ✅ 系統能 SSH 登入
- ✅ GitHub repo：github.com/spinstein/j4125.git
- ✅ 配置備份包在 `/mnt/usb/j4125/configs-*.tar.gz` 或 `/data/auto-backup/j4125/`

**還原腳本：** `scripts/restore-config.sh`
```bash
set -euo pipefail

# 兩種模式：
# --git      從 GitHub 拉取腳本
# --backup   從指定備份包還原
# (無參數)   自動找最新備份包

# 1. gunzip -t 檢查備份包完整性
gunzip -t "$BACKUP_FILE" || exit 1

# 2. 解壓到臨時目錄
tar xzf "$BACKUP_FILE" -C "$WORKDIR"

# 3. 逐一還原配置（跳過不存在的文件，記錄 MISSING）
for conf in network/interfaces mihomo/config.yaml dnsmasq.conf nftables.conf; do
  cp -f "$src" "$dst" || MISSING=$((MISSING+1))
done

# 4. sync → 重啟服務
sync
systemctl restart networking dnsmasq || true
systemctl restart mihomo 2>/dev/null || echo "⚠️ mihomo 報錯"

# 5. 如果 MISSING > 0 則報警
```

**手動驗證步驟（SSH 執行）：**
```bash
# 1. 看備份文件
ls -la /mnt/usb/j4125/

# 2. 取最新一個
LATEST=$(ls -t /mnt/usb/j4125/configs-*.tar.gz | head -1)
cp "$LATEST" /tmp/latest-config.tar.gz
tar xzf latest-config.tar.gz -C /tmp/restore-test/

# 3. 看包裡有什麼
ls -la /tmp/restore-test/etc/

# 4. 比對內容
diff /tmp/restore-test/etc/dnsmasq.conf /etc/dnsmasq.conf

# 5. 確認無誤後還原
cp -f /tmp/restore-test/etc/network/interfaces /etc/network/interfaces
cp -f /tmp/restore-test/etc/mihomo/config.yaml /etc/mihomo/config.yaml
cp -f /tmp/restore-test/etc/dnsmasq.conf /etc/dnsmasq.conf
cp -f /tmp/restore-test/etc/nftables.conf /etc/nftables.conf

# 6. 重啟服務
systemctl restart networking dnsmasq mihomo

# 7. 驗證
ping -c 3 223.5.5.5
curl -x http://127.0.0.1:7890 -s -o /dev/null -w "%{http_code}" https://www.google.com
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

**L1 驗證（快速）：**
```bash
gunzip -t /mnt/usb/j4125-20260527-full.img.gz    # 壓縮包沒壞？
zcat ... | dd bs=4M count=1 | fdisk -l /dev/stdin  # 分區表可讀？
```

**L2 深度驗證（HDD）：** `scripts/deep-verify.sh`
```bash
# 需 HDD 250GB+ 空間
VERIFY_IMG="/mnt/hdd/verify-$(date +%Y%m%d).img"

gunzip -t "$BACKUP_FILE"     # 1. 壓縮包完整性
pigz -dc "$BACKUP_FILE" > "$VERIFY_IMG"  # 2. 解壓到 HDD
losetup + partx + fsck -n    # 3. 文件系統檢查
rm -f "$VERIFY_IMG"          # 4. 清理

case $r in
  0) echo "✅ 文件系統乾淨";;
  1) echo "⚠️ 已修復";;
  2) echo "❌ 需重啟修復"; exit 2;;
esac
```

---

## 還原後驗證

`scripts/verify-restore.sh` — 重啟後在 J4125 執行：

- 服務檢查：networking / mihomo / dnsmasq / tailscaled
- 網路連通：ping 223.5.5.5
- 配置文件存在：/etc/network/interfaces / /etc/mihomo/config.yaml / /etc/dnsmasq.conf / /etc/nftables.conf
- 輸出：PASS/FAIL 分數

---

## Manifest（備份歷史記錄）

存於 `/data/auto-backup/j4125/manifest.yaml`：

```yaml
- version: v1
  date: 2026-05-27_14:00
  type: config
  file: configs-20260527-1400.tar.gz
  size: 4.2M
  note: 系統安裝完成，Debian 13 base
  restore: 設置還原 / 單項還原

- version: v7
  date: 2026-05-27_21:00
  type: config
  file: configs-20260527-2100.tar.gz
  size: 4.5M
  note: 最終版本（含鏡像備份前狀態）
  restore: 設置還原 / 單項還原

- version: full-v1
  date: 2026-05-27_21:00
  type: full
  file: j4125-20260527-full.img.gz
  size: 2.9G
  fsfreeze: true
  verify: gunzip-t + 分區表 OK
  note: 整盤 dd 鏡像
  restore: 全盤還原（需 Live USB）
```

---

## 方案邊界 ⚠️

1. **gunzip -t 只能驗證壓縮包沒壞**，不能檢查文件系統內部的文件完整性
2. **深度 fsck 可覆蓋 99% 情況** — HDD 到後可執行
3. **SSD 壞道風險** — dd 讀取時可能靜默跳過或返回 0，L2 深度驗證 + fsck 可捕獲
4. **最終保險** — 還原後跑 verify-restore.sh，服務能啟 + 網路通 = 系統可用
5. **配置備份範圍有限** — 目前只含 4 個核心配置文件（network/interfaces、mihomo、dnsmasq、nftables），後續新增配置需手動補充到備份清單
6. **不能跨系統版本恢復** — 全盤 dd 鏡像需寫回容量 ≥250GB 的同類磁碟

---

## 後續可加強的方向

| 優先級 | 事項 | 預計時間 | 依賴 |
|--------|------|----------|------|
| 🔴 | 配置腳本化（setup.sh/install.sh）推 GitHub | 本週 | — |
| 🟡 | Timeshift 安裝 + 自動快照配置 | HDD 到後 | HDD |
| 🟡 | 深度 fsck 驗證腳本（L2）納入 cron | HDD 到後 | HDD |
| 🟢 | 每月自動化還原測試（restore drill） | 月度 | HDD + cron |
