#!/bin/bash
#
# 在 `./scripts/feeds update -a` 之前执行。工作目录为 LEDE 源码根目录。
#
set -e

# natflow 不在 LEDE 源码里，从 x-wrt 单独取这一个包。
# 不整个加成 feed —— com.x-wrt 里大量包会和 LEDE 自带的同名包冲突。
echo ">>> 集成 x-wrt natflow"
rm -rf package/natflow /tmp/com.x-wrt
git clone --depth=1 https://github.com/x-wrt/com.x-wrt.git /tmp/com.x-wrt
cp -r /tmp/com.x-wrt/natflow package/natflow
rm -rf /tmp/com.x-wrt

# 只需要 kmod-natflow 和 natflow-boot；natflow-auth/hostacl 依赖 lua-ipops、urllogger，
# LEDE 里没有，留着也只是不可选，不影响编译。
grep -q 'PKG_NAME:=natflow' package/natflow/Makefile && echo ">>> natflow 就位"
grep '^PKG_VERSION' package/natflow/Makefile

# natflow 最新版本主要面向新内核，如果在内核 5.10 上编译失败，把 NATFLOW_VERSION
# 设成某个较老的 tag 重试（同时要换掉 PKG_HASH，或直接删掉 PKG_HASH 那一行）。
if [ -n "${NATFLOW_VERSION:-}" ]; then
	echo ">>> 将 natflow 固定到 $NATFLOW_VERSION"
	sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$NATFLOW_VERSION/" package/natflow/Makefile
	sed -i '/^PKG_HASH:=/d' package/natflow/Makefile
	sed -i '/^PKG_MIRROR_HASH:=/d' package/natflow/Makefile
fi
