#!/bin/bash
#
# 在 feeds 安装完、`make defconfig` 之前执行。工作目录为 LEDE 源码根目录。
#
set -e

# 把仓库里的 files/ 覆盖层塞进固件（OpenWrt 会把源码根目录的 files/ 直接打进 rootfs）
SRC_FILES="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")/.." && pwd)}/files"
if [ -d "$SRC_FILES" ]; then
	echo ">>> 注入 files/ 覆盖层"
	mkdir -p files
	cp -a "$SRC_FILES/." files/
	chmod +x files/etc/init.d/* files/etc/uci-defaults/* 2>/dev/null || true
fi

# LAN 地址默认沿用 192.168.1.1。要改成别的（比如避免和现有主路由冲突）就打开下面这行。
# sed -i 's/192.168.1.1/192.168.3.3/g' package/base-files/files/bin/config_generate

echo ">>> diy-part2 完成"
