# 竞斗云 2.0 (P&W R619AC) OpenWrt 编译方案

为 IPQ4019 追求最大转发性能的固件构建仓库。GitHub Actions 云编译，也可本地 WSL2 编译。

## 为什么是这个组合

IPQ4019 **没有 NSS 协处理器**（NSS 只存在于 IPQ806x / IPQ807x / IPQ6018），所以 OpenWrt
上不存在真正的硬件 NAT offload。这台机器上能拿到的"加速"是两部分：

1. **essedma + ar40xx 以太网驱动**（Qualcomm SDK 改的老驱动）—— 16 个硬件队列、RSS
   多核中断分发、checksum/TSO/GRO 硬件卸载。这是吃到 SoC 实力的关键。
2. **软件快速转发引擎** —— natflow / shortcut-fe / 内核 flowtable，绕过 netfilter 慢路径。

决定性能的最大变量是**以太网驱动**，不是插件。上游 OpenWrt 在 2021-10 删除了
essedma + ar40xx（22.03/23.05 起生效），换成新的 DSA 驱动，实测只跑单核：

| 底包 | 以太网驱动 | 实测 NAT 吞吐 |
| --- | --- | --- |
| ImmortalWrt 21.02.7 + flow offload | essedma | 跑满千兆 |
| ImmortalWrt / OpenWrt 23.05+ | DSA | ~200 Mbps |
| OpenWrt snapshot | DSA | ~500 Mbps |
| DSA + natflow | DSA | ~860 Mbps |
| **Lean LEDE + natflow（本仓库）** | **essedma** | **跑满千兆 PPPoE** |

数据来源：ImmortalWrt discussion #1195、OpenWrt issue #9848、issue #12429。

`coolsnowwolf/lede` master 至今保留 ipq40xx 的内核 5.10 + `CONFIG_ESSEDMA=y` +
`CONFIG_AR40XX_PHY=y` + `swconfig`，防火墙仍是 fw3/iptables，且带 `p2w_r619ac-128m` 机型。
这与恩山「竞斗云 hwnat lede」帖子的做法一致。

## 目录结构

```
config/r619ac-lede.config          种子 .config（只写关键项，defconfig 补全依赖）
scripts/diy-part1.sh               feeds 更新前：从 x-wrt 取 natflow 包
scripts/diy-part2.sh               feeds 安装后：注入 files/ 覆盖层
files/etc/config/natflow           natflow 运行配置（enabled=1，见下）
files/etc/uci-defaults/99-r619ac-defaults   首次开机：关 fw3 offload、关无线、设时区
files/etc/init.d/r619ac-perf                每次开机：CPU 定频 + natflow 状态记录
.github/workflows/build-r619ac.yml 云编译流程
```

### 关于 natflow 的两个坑

**一、`/etc/config/natflow` 必须自己补。** 上游把这个文件放在 `natflow-auth` 包里，而
`natflow-auth` 依赖 `lua-ipops`（只存在于 com.x-wrt），LEDE 里装不了。缺了它，
`natflow-boot` 的 `uci get natflow.main.enabled` 取不到值会回落到 `0`，natflow 开机
就是停用状态 —— 编译一切正常，但加速根本没生效。本仓库的 `files/etc/config/natflow`
就是为了填这个坑。

**二、`ethtool` 是必需依赖，不是可选。** `natflow-boot` 的 init 脚本会遍历所有 `eth*`
接口执行 `ethtool -K ... gro off / gso off`。这恰好绕开了 essedma 上 GRO 与快速路径
相互干扰的老问题（OpenWrt issue #9848），所以不用手工去关 GRO。没装 ethtool 的话
这一步会静默跳过。

## 云编译

1. 把这个仓库推到你自己的 GitHub 账号（public 或 private 都行）。
2. Settings → Actions → General → Workflow permissions 选 **Read and write permissions**
   （否则创建 Release 会 403）。
3. Actions → **Build R619AC (LEDE + natflow)** → Run workflow。

首次约 1.5–2.5 小时。产物在 Release 和 Artifact 里：

- `openwrt-ipq40xx-generic-p2w_r619ac-128m-squashfs-nand-factory.ubi` —— 从 opboot 刷
- `openwrt-ipq40xx-generic-p2w_r619ac-128m-squashfs-sysupgrade.bin` —— 从已有 OpenWrt 升级

## 本地编译（WSL2）

```powershell
wsl --install -d Ubuntu-24.04
```

源码必须放在 Linux 文件系统里（`~/`），**不要放 `/mnt/c`**，否则慢到不可用，且 PATH 里
的 Windows 路径会导致编译失败。

```bash
git clone --depth=1 -b master https://github.com/coolsnowwolf/lede openwrt
cd openwrt
../scripts/diy-part1.sh            # 假设本仓库在 openwrt 的同级目录
./scripts/feeds update -a && ./scripts/feeds install -a
cp ../config/r619ac-lede.config .config
../scripts/diy-part2.sh
make defconfig
make download -j8
make -j$(nproc) V=s
```

需要约 40 GB 磁盘。

## 刷机

前提：opboot **≥ 1.0.9**（128M 分区支持），双击 reset 进 opboot web 界面。

1. **必须不保留配置。** essedma(swconfig) 和 DSA 的 `/etc/config/network` 格式完全不兼容，
   保留配置必然起不来。
2. 128M 机型要用 `.ubi` 从 opboot 刷（会重建 UBI 分区），不能用 sysupgrade.bin。
3. opboot 在 16 MB NOR 里，刷 NAND 刷不坏它 —— 任何时候翻车都能进 opboot 重刷。
   **动手前先在手边存一个已知能启动的 `.ubi`。**

### 已知风险

LEDE 的 ipq40xx 从内核 5.4 升到 5.10 后，R619AC 128M 出现过反复重启起不来的问题
（`coolsnowwolf/lede` issue #11530）。后来有 `ipq40xx: fixes k5.10 boot issue` 修复提交，
但恩山上仍有零星翻车反馈。所以：**别在没有备用网络的时候折腾**，并备好 opboot 回退路径。

如果这个包起不来，两个退路：

- 把 `config/r619ac-lede.config` 里的机型换成 `CONFIG_TARGET_ipq40xx_generic_DEVICE_p2w_r619ac-64m=y` 试试。
- 换底包到 ImmortalWrt 24.10（改 workflow 的 `REPO_URL`/`REPO_BRANCH`），配合
  [chenmozhijin/turboacc](https://github.com/chenmozhijin/turboacc) 或 natflow，
  接受 DSA 带来的性能损失（约 500–860 Mbps）。

另一类可能的失败是 **natflow 编不过** —— 它主要面向新内核，在内核 5.10 上有版本风险。
遇到这种情况，给 workflow 加一个环境变量把它固定到较老的 tag 重试：

```yaml
- name: 执行 diy-part1（集成 natflow）
  env:
    NATFLOW_VERSION: '20220820'   # 换成 ptpt52/natflow 上某个较老的 tag
```

## 刷完后的验证

```sh
# 1. natflow 模块是否加载
lsmod | grep natflow

# 2. natflow 是否真的启用了（关键！disabled 必须是 0）
cat /dev/natflow_ctl

# 3. fw3 的 flow offloading 应为 0（和 natflow 抢同一条快速路径）
uci get firewall.@defaults[0].flow_offloading

# 4. GRO/GSO 应该已被 natflow-boot 关掉
ethtool -k eth0 | grep -E 'generic-(receive|segmentation)-offload'

# 5. essedma 中断是否分散到 4 个核；只落 CPU0 说明 RSS 没生效
grep edma /proc/interrupts

# 6. CPU 是否定频
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# 7. 开机日志里的自检结果
logread | grep -E 'natflow|r619ac-perf'
```

第 2 步最容易翻车：如果 `disabled=1`，说明 `/etc/config/natflow` 没生效，手动
`uci set natflow.main.enabled=1 && uci commit natflow && /etc/init.d/natflow-boot restart`。

跑满速时 `top` 看 sirq 占用。加速生效的话，500 Mbps 以上 sirq 应该很低。

## 硬件规格

- SoC：Qualcomm IPQ4019，4 × Cortex-A7 @ 717 MHz
- 内存：512 MB DDR3
- 闪存：16 MB NOR（含 opboot）+ 128 MB NAND
- 网口：5 × GbE（4 LAN + 1 WAN）
- 其他：USB 3.0 × 1、MicroSD、未焊 mPCIe/SIM 位
- 串口：J2 排针，115200 8N1
