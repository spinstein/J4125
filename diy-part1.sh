#!/bin/bash

# 1. 添加额外软件源
echo "src-git dockerman https://github.com/lisaac/luci-app-dockerman" >> feeds.conf.default
echo "src-git passwall https://github.com/xiaorouji/openwrt-passwall" >> feeds.conf.default

# 2. 下载青龙面板镜像
mkdir -p files/opt/docker
docker pull whyour/qinglong:latest
docker save whyour/qinglong:latest -o files/opt/docker/qinglong.tar

# 3. 预置安全密钥
mkdir -p files/etc/dropbear
dropbearkey -t ed25519 -f files/etc/dropbear/dropbear_ed25519_host_key

# 4. 禁用高危模块
sed -i 's/CONFIG_PACKAGE_luci-app-upnp=y/# CONFIG_PACKAGE_luci-app-upnp is not set/' .config
