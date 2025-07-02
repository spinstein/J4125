#!/bin/bash

# 1. 创建分区挂载配置
cat > files/etc/fstab <<EOF
# 自定义分区表
/dev/sda1 /boot vfat defaults,ro 0 0
/dev/sda2 / ext4 defaults,noatime 0 0
/dev/sda3 /opt/docker btrfs defaults,compress-force=zstd 0 0
/dev/sda4 /opt/downloads xfs defaults,noatime,nodiratime 0 0
EOF

# 2. 初始化脚本 (首次启动执行)
cat > files/etc/init.d/init-storage <<'EOF'
#!/bin/sh /etc/rc.common
START=99

start() {
  # 检查是否首次启动
  [ -f /opt/.initialized ] && exit 0

  # 创建交换文件
  dd if=/dev/zero of=/opt/swap bs=1M count=2048
  mkswap /opt/swap
  swapon /opt/swap

  # 创建下载目录
  mkdir -p /opt/downloads
  chmod 1777 /opt/downloads
  
  # 配置Aria2
  echo "dir=/opt/downloads" >> /etc/aria2.conf
  echo "rpc-secret=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)" >> /etc/aria2.conf

  # 标记已初始化
  touch /opt/.initialized
}
EOF
chmod +x files/etc/init.d/init-storage

# 3. 预置网络配置
cat > files/etc/config/network <<EOF
config interface 'wan'
  option device 'eth0'
  option proto 'dhcp'

config interface 'lan'
  option device 'eth1 eth2 eth3'
  option type 'bridge'
  option ipaddr '192.168.1.1'
  option netmask '255.255.255.0'
EOF

# 4. 固化防火墙规则
cat > files/etc/config/firewall <<EOF
config zone
  option name 'lan'
  option input 'ACCEPT'
  option output 'ACCEPT'
  option forward 'ACCEPT'

config zone
  option name 'wan'
  option input 'REJECT'
  option output 'ACCEPT'
  option forward 'REJECT'
  option masq '1'
  option mtu_fix '1'

# 禁止WAN访问管理界面
config rule
  option name 'Block-WAN-Web'
  option src 'wan'
  option proto 'tcp'
  option dest_port '80 443'
  option target 'REJECT'
EOF

# 5. 青龙面板Docker配置
mkdir -p files/opt/docker
cat > files/opt/docker/docker-compose.yml <<EOF
version: '3'
services:
  qinglong:
    image: whyour/qinglong
    container_name: qinglong
    ports:
      - "5800:5700"
    volumes:
      - /opt/docker/qinglong:/ql/data
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
EOF

# 6. 穿透工具自动配置
cat > files/etc/rc.local <<'EOF'
# 首次启动生成Cpolar密码
if [ ! -f /etc/cpolar/auth ]; then
  USER="admin"
  PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)
  echo "$USER:$PASS" > /etc/cpolar/auth
  echo "Cpolar Access: https://$(hostname).cpolar.top" > /etc/motd
  echo "Username: $USER" >> /etc/motd
  echo "Password: $PASS" >> /etc/motd
fi
exit 0
EOF
