# J4125 Debian Router 部署指南

J4125 上 Debian 13 路由器系統的完整部署和重建流程。

---

## 一、SSD 完好時（系統故障 / 配置搞砸）

系統還能啟動或重裝後還能識別舊 SSD，從備份恢復配置：

```bash
# 1. 掛載備份 U 盤
mount /dev/sdb1 /mnt

# 2. 恢復所有套件
dpkg --set-selections < /mnt/j4125-rebuild/packages.list
apt-get dselect-upgrade -y

# 3. 恢復配置
tar xzf /mnt/j4125-rebuild/configs.tar.gz -C /

# 4. 恢復加密敏感文件（使用私密密碼）
# gpg --decrypt /mnt/j4125-rebuild/secrets.tar.gz.gpg | tar xzf - -C /

# 5. 載入 Docker 映像
gunzip -c /mnt/j4125-rebuild/docker-images.tar.gz | docker load

# 6. 啟用服務
systemctl enable nftables dnsmasq mihomo tailscaled rc-local
systemctl start nftables dnsmasq mihomo tailscaled rc-local

# 7. 啟用轉發
sysctl -p /etc/sysctl.d/99-net.conf

# 8. 重啟
reboot
```

---

## 二、SSD 損壞時（換新硬碟）

### 方案 A：整碟備份還原（需 ≥250GB 目標盤）

從備份 U 盤還原完整系統鏡像：

```bash
# 1. 換上新 SSD（≥250GB）
# 2. 從 Live USB（SystemRescue/Ubuntu Live）啟動
# 3. 掛載備份 U 盤
mount /dev/sdb1 /mnt

# 4. 還原整碟鏡像
pigz -dc /mnt/j4125-*-sda-v2.img.gz | dd of=/dev/sda bs=4M status=progress

# 5. 重啟
reboot
```

### 方案 B：配置重建（SSD 容量可不同）

同「SSD 完好時」流程，先裝好 Debian 13 再恢復配置。

---

## 三、備份文件清單

| 文件 | 位置 | 說明 |
|------|------|------|
| j4125-*.img.gz | U 盤 / HDD | 全盤 dd 鏡像 |
| packages.list | U 盤 j4125-rebuild/ | 所有已裝套件清單 |
| configs.tar.gz | U 盤 j4125-rebuild/ | 關鍵配置文件 |
| secrets.tar.gz.gpg | U 盤 j4125-rebuild/ | GPG 加密敏感文件 |
| docker-images.tar.gz | U 盤 j4125-rebuild/ | Docker 映像 |

---

## 四、腳本位置

- **復原腳本：** `../scripts/`（restore-full.sh、restore-config.sh、verify-restore.sh、deep-verify.sh）
- **本文件：** `deploy/README.md`
