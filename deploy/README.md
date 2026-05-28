# J4125 Debian 13 路由器部署指南

從零開始部署 J4125 作為家庭軟路由，含 PPPoE 撥號、nftables 防火牆、dnsmasq DHCP/DNS、mihomo 代理、Tailscale 遠程訪問。

> **系統：** Debian 13 Trixie  
> **硬體：** J4125 四網口迷你主機，250GB SSD  
> **網絡：** 中國移動 PPPoE（需 MAC 欺騙）

---

## 一、基礎系統安裝

### 1.1 下載與寫盤

```bash
# 下載 Debian 13 netinst ISO
wget https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.0.0-amd64-netinst.iso

# 寫入 U 盤（Linux）
dd if=debian-13.0.0-amd64-netinst.iso of=/dev/sdX bs=4M status=progress
```

### 1.2 安裝注意事項

- **語言：** English（後續可加中文 locale）
- **主機名：** pve-router
- **網卡選擇：** 安裝時插 TC7102 LAN 口，選擇自動識別的網卡（通常是 eno1）
- **軟體選擇：** 只選 SSH server + standard system utilities
- **不裝桌面環境**

### 1.3 安裝後 SSH 登入

```bash
ssh root@192.168.200.xxx  # 安裝時分配的 DHCP IP
# 密碼：安裝時設定的 root 密碼
```

---

## 二、網絡配置

### 2.1 網卡規劃

| 網卡 | MAC | 用途 | 連接 |
|------|-----|------|------|
| eno1 (enp3s0) | 60:be:b4:07:19:e2 | LAN | TC7102（AP模式） |
| enp1s0 | 60:be:b4:07:19:e6 | WAN | 光貓（PPPoE） |

### 2.2 配置 /etc/network/interfaces

```bash
cat > /etc/network/interfaces << 'EOF'
# WAN - 接光貓（PPPoE）
auto enp1s0
iface enp1s0 inet manual

# LAN - 接 TC7102
auto eno1
iface eno1 inet manual

# LAN 橋接
auto br-lan
iface br-lan inet static
    bridge_ports eno1
    address 192.168.200.254/24
    dns-nameserver 8.8.8.8

# PPPoE
auto pppoe-wan
iface pppoe-wan inet ppp
    provider j4125-pppoe
    pre-up /bin/ip link set enp1s0 address 1c:e5:04:fa:dc:af
    pre-up /bin/ip link set enp1s0 up
EOF
```

> **注意：** 中國移動需要 MAC 欺騙。在 `/etc/ppp/peers/j4125-pppoe` 中設置 `hwaddr 1c:e5:04:fa:dc:af`（填入你的光貓 MAC）。

### 2.3 PPPoE 配置

```bash
# 安裝 PPPoE
apt install pppoe

# 創建 PPPoE 撥號配置
cat > /etc/ppp/peers/j4125-pppoe << 'EOF'
# 介面
plugin pppoe.so
enp1s0

# 認證
user "你的寬帶帳號"
password "你的寬帶密碼"

# MAC 欺騙（中國移動必需）

# IP
noipdefault
usepeerdns
persist
maxfail 0
holdoff 5

# 性能
defaultroute
replacedefaultroute
noauth
EOF
```

### 2.4 重啟網絡

```bash
systemctl restart networking
```

確認 PPPoE 已撥上：
```bash
ip addr show ppp0
# 應該看到一個公網 IP
```

---

## 三、防火牆（nftables）

### 3.1 安裝

```bash
apt install nftables
```

### 3.2 配置 /etc/nftables.conf

```bash
cat > /etc/nftables.conf << 'EOF'
flush ruleset

table inet nat {
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "ppp*" masquerade
    }
}

table inet mangle {
    chain forward {
        type filter hook forward priority mangle; policy accept;
        tcp flags syn tcp option maxseg size set rt mtu
    }
    chain output {
        type route hook output priority mangle; policy accept;
        tcp flags syn tcp option maxseg size set rt mtu
    }
}

table inet filter {
    chain forward {
        type filter hook forward priority filter; policy drop;
        iifname "br-lan" oifname "ppp*" accept
        iifname "ppp*" oifname "br-lan" ct state established,related accept
    }
    chain input {
        type filter hook input priority filter; policy drop;
        iif lo accept
        ct state established,related accept
        iifname "br-lan" tcp dport { 22, 53, 80, 443 } accept
        iifname "tailscale0" accept
    }
}
EOF
```

### 3.3 啟用 IP 轉發

```bash
echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/99-net.conf
sysctl -p /etc/sysctl.d/99-net.conf
```

### 3.4 啟動防火牆

```bash
systemctl enable --now nftables
```

---

## 四、DHCP/DNS（dnsmasq）

### 4.1 安裝

```bash
apt install dnsmasq
```

### 4.2 配置 /etc/dnsmasq.conf

```bash
cat > /etc/dnsmasq.conf << 'EOF'
# DHCP
interface=br-lan
dhcp-range=192.168.200.100,192.168.200.200,255.255.255.0,24h
dhcp-option=3,192.168.200.254
dhcp-option=6,192.168.200.254

# DNS
server=223.5.5.5
server=114.114.114.114
no-resolv
no-poll
bind-interfaces
domain-needed
bogus-priv
expand-hosts
EOF
```

### 4.3 啟動

```bash
systemctl enable --now dnsmasq
```

---

## 五、代理（mihomo）

### 5.1 安裝 mihomo

```bash
# 下載 compatible 版本（J4125 不支持 x86-64-v3）
wget https://github.com/MetaCubeX/mihomo/releases/download/v1.19.3/mihomo-linux-amd64-compatible-v1.19.3.gz
gunzip mihomo-linux-amd64-compatible-v1.19.3.gz
chmod +x mihomo-linux-amd64-compatible-v1.19.3
mv mihomo-linux-amd64-compatible-v1.19.3 /usr/local/bin/mihomo
```

### 5.2 配置 /etc/mihomo/config.yaml

```bash
mkdir -p /etc/mihomo
```

mihomo 配置包含：mixed-port 7893、allow-lan、DNS 1053、proxy-providers（訂閱地址）。
> **注意：** 訂閱 URL 和節點信息為敏感數據，不在本手冊中展示。使用自己的機場訂閱地址。

### 5.3 systemd 服務

```bash
cat > /etc/systemd/system/mihomo.service << 'EOF'
[Unit]
Description=mihomo Daemon
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mihomo -d /etc/mihomo
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl enable --now mihomo
```

### 5.4 代理測試

```bash
# 測試代理
curl -x http://127.0.0.1:7893 -s -o /dev/null -w "%{http_code}" https://www.google.com
# 預期輸出：200
```

---

## 六、Tailscale 遠程訪問

### 6.1 安裝 Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

### 6.2 啟動並認證

```bash
tailscale up --accept-dns=false
# 會輸出一個 URL，在瀏覽器中打開並登入 Tailscale 帳號
```

### 6.3 驗證

```bash
tailscale status
# 應該看到 pve-router 在線
```

---

## 七、備份系統

### 7.1 安裝備份工具

```bash
apt install pigz
```

### 7.2 配置備份腳本

備份腳本在 `/root/j4125/scripts/`（見 GitHub `scripts/` 目錄）。

### 7.3 設置定時備份

```bash
crontab -e
# 加入：
0 2 * * * /root/j4125-backup.sh all
```

### 7.4 手動觸發全盤備份

```bash
# 凍結文件系統 → dd 備份 → 解凍
sync && sync
fsfreeze -f /
dd if=/dev/sda bs=4M status=progress | pigz -c > /mnt/usb/j4125-$(date +%Y%m%d)-full.img.gz
fsfreeze -u /
```

---

## 八、還原

還原腳本在 `/root/j4125/scripts/`：

- `restore-full.sh` — 全盤還原（需 Live USB）
- `restore-config.sh` — 配置還原（SSH 可操作）
- `verify-restore.sh` — 還原後驗證
- `deep-verify.sh` — 深度文件系統檢查（需 HDD）

詳見 [`../v6-plan.md`](../v6-plan.md) 和 [`../scripts/`](../scripts/)。

---

## 九、關鍵信息匯總

| 項目 | 值 |
|------|-----|
| LAN IP | 192.168.200.254/24 |
| DHCP 範圍 | 192.168.200.100-200 |
| DNS | 223.5.5.5 / 114.114.114.114 |
| mihomo 端口 | 7890 (HTTP) / 7893 (mixed) |
| mihomo DNS | 1053 |
| Tailscale IP | 100.x.x.x（動態） |
| SSH 端口 | 22 |
| 備份路徑 | /mnt/usb/（USB）/ 待 HDD |
| 自動備份 | 每天 02:00 |
