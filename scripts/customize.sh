#!/usr/bin/env bash
set -euo pipefail

# NX30 Pro (pg-go/immortalwrt-mt798x-6.6, nx30pro-nmbm-build) 定制包拉取脚本
#
# 拉取 configs/nx30pro-nmbm.config 里 =y、但 feeds / 内核树里没有的包：
#   EasyTier：easytier-noweb + luci-app-easytier
#   Homi：mihomo + homi + luci-app-homi（用户自有项目）
#   Aurora：luci-theme-aurora + luci-app-aurora-config（用户常用主题）
#   NetPath：luci-app-netpath（用户自有项目，LuCI 仪表盘）
# 注意：NetPath 用 main 分支（1.0.15），不要用 v1.0.16 tag——那个 tag
# 是已放弃的 8080 独立 Web 版（第二 uhttpd 实例），不在主线。
#
# 运行点：workflow 的 "Prepare custom packages" 步，feeds install 之后、
# cp configs/nx30pro-nmbm.config .config 之前。定制包拷进 package/custom/
# 后重建索引并校验，否则 .config 里的 =y 会被 make defconfig 静默剔除。
#
# 注意：connector push 会丢可执行位，workflow 里必须用 `bash scripts/customize.sh`
# 调用，不能直接 `./scripts/customize.sh`。

echo "=== [NX30Pro] Preparing custom packages (EasyTier / Homi / Aurora / NetPath) ==="

PKG_DIR="package/custom"
mkdir -p "$PKG_DIR"

clone() {  # clone <url> <dir> [branch]
  local url="$1" dir="$2" br="$3"
  [ -d "$dir" ] && { echo "已存在，跳过: $dir"; return 0; }
  echo "--- git clone $url -> $dir ---"
  if [ -n "$br" ]; then
    git clone --depth 1 -b "$br" "$url" "$dir" 2>&1 | tail -3
  else
    git clone --depth 1 "$url" "$dir" 2>&1 | tail -3
  fi
  if [ -d "$dir" ]; then
    echo "✅ 克隆成功: $dir"
    return 0
  fi
  echo "::error::克隆失败: $url"
  return 1
}

# --- EasyTier：easytier-noweb（预编译二进制）+ luci-app-easytier ---
# 源：EasyTier/luci-app-easytier（monorepo，拷出子目录；整仓丢进 package/custom
# 会让包名对不上）。本体不用 Rust 源码编译，Makefile 下载预编译二进制
# （easytier-linux-aarch64，v2.7.0）。
ET_TMP="$(mktemp -d)/easytier"
if ! clone https://github.com/EasyTier/luci-app-easytier "$ET_TMP" main; then
  echo "::error::EasyTier/luci-app-easytier 拉取失败，easytier-noweb / luci-app-easytier 会被 defconfig 剔除"
  exit 1
fi
for p in easytier-noweb luci-app-easytier; do
  if [ ! -f "$ET_TMP/$p/Makefile" ]; then
    echo "::error::$ET_TMP/$p/Makefile 不存在（上游改结构了？）"
    exit 1
  fi
  rm -rf "$PKG_DIR/$p"
  cp -a "$ET_TMP/$p" "$PKG_DIR/"
  echo "✅ 已拷贝: $p"
done
rm -rf "$ET_TMP"

# --- Homi：mihomo 内核 + homi 服务 + luci-app-homi 界面 ---
# 源：pg-go/luci-app-homi（用户自有项目）。包在三个子目录，拷出子目录。
# 注意 mihomo 是 Go 源码编译，会给固件构建增加约 10 分钟。
HOMI_TMP="$(mktemp -d)/homi"
if ! clone https://github.com/pg-go/luci-app-homi "$HOMI_TMP" main; then
  echo "::error::pg-go/luci-app-homi 拉取失败，mihomo / homi / luci-app-homi 会被 defconfig 剔除"
  exit 1
fi
for p in mihomo homi luci-app-homi; do
  if [ ! -f "$HOMI_TMP/$p/Makefile" ]; then
    echo "::error::$HOMI_TMP/$p/Makefile 不存在（上游改结构了？）"
    exit 1
  fi
  rm -rf "$PKG_DIR/$p"
  cp -a "$HOMI_TMP/$p" "$PKG_DIR/"
  echo "✅ 已拷贝: $p"
done
rm -rf "$HOMI_TMP"

# --- Aurora 主题 + 设置页 ---
# 源：eamonxg/luci-theme-aurora 与 eamonxg/luci-app-aurora-config（设置页，
# 要求主题 ≥1.2.0）。两个仓库根目录就是包体（Makefile 在根目录），整仓拷
# （去掉 .git）。注意：两仓默认分支是 master，不是 main。
# 主题自带 root/etc/uci-defaults/30_luci-theme-aurora，首次安装自动把
# luci.main.mediaurlbase 设成 /luci-static/aurora，即默认主题就是 Aurora。
for repo in luci-theme-aurora luci-app-aurora-config; do
  AU_TMP="$(mktemp -d)/aurora"
  if ! clone "https://github.com/eamonxg/$repo" "$AU_TMP" master; then
    echo "::error::eamonxg/$repo 拉取失败，$repo 会被 defconfig 剔除"
    exit 1
  fi
  if [ ! -f "$AU_TMP/Makefile" ]; then
    echo "::error::$AU_TMP/Makefile 不存在（上游改结构了？）"
    exit 1
  fi
  rm -rf "$PKG_DIR/$repo"
  cp -a "$AU_TMP" "$PKG_DIR/$repo"
  rm -rf "$PKG_DIR/$repo/.git"
  echo "✅ 已拷贝: $repo"
  rm -rf "$AU_TMP"
done

# --- NetPath：LuCI 仪表盘 ---
# 源：pg-go/luci-app-netpath（用户自有项目）。包在子目录 luci-app-netpath，
# 拷出子目录。只用 main 分支（1.0.15，LuCI 版）；v1.0.16 tag 是已放弃的
# 8080 独立 Web 版，不要拉。
NP_TMP="$(mktemp -d)/netpath"
if ! clone https://github.com/pg-go/luci-app-netpath "$NP_TMP" main; then
  echo "::error::pg-go/luci-app-netpath 拉取失败，luci-app-netpath 会被 defconfig 剔除"
  exit 1
fi
if [ ! -f "$NP_TMP/luci-app-netpath/Makefile" ]; then
  echo "::error::$NP_TMP/luci-app-netpath/Makefile 不存在（上游改结构了？）"
  exit 1
fi
rm -rf "$PKG_DIR/luci-app-netpath"
cp -a "$NP_TMP/luci-app-netpath" "$PKG_DIR/"
echo "✅ 已拷贝: luci-app-netpath"
rm -rf "$NP_TMP"

# ---------------------------------------------------------
# 让新包进入索引
#   prepare-tmpinfo 直接扫 package/ 树（scan.mk: find -L package -maxdepth 5），
#   package/custom/<pkg>/Makefile 深度 3，本来就会被扫到，不需要注册 feed。
#   只删 tmp/.packageinfo 是不够的：prepare-tmpinfo 有 scan_unchanged 优化
#   （拿 tmp/info/.scan-*.stamp 比 mtime），stamp 还在且没有更新的 Makefile
#   时它会跳过扫描 —— 结果 .packageinfo 被删了却没人重建，索引反而空了。
#   所以 stamp 也要一起删。
# ---------------------------------------------------------
if [ -n "$(ls -A "$PKG_DIR" 2>/dev/null)" ]; then
  rm -f tmp/.packageinfo tmp/.targetinfo
  rm -f tmp/info/.scan-packageinfo.stamp tmp/info/.scan-targetinfo.stamp
  rm -f tmp/.config-package.in tmp/.config-target.in
  echo ">>> make prepare-tmpinfo（重新扫描 package/ 树）"
  make -s prepare-tmpinfo OPENWRT_BUILD= 2>&1 | tail -5 || true
  echo "=========================================="
  echo "包索引校验（判据：tmp/.packageinfo）"
  echo "=========================================="
  echo "package/custom 内容："
  INDEX_MISS=""
  for d in "$PKG_DIR"/*; do
    [ -d "$d" ] || continue
    n=$(basename "$d")
    if grep -qx "Package: $n" tmp/.packageinfo 2>/dev/null; then
      echo "  ✅ $n"
    else
      echo "  ❌ $n —— tmp/.packageinfo 里查不到"
      INDEX_MISS="$INDEX_MISS $n"
    fi
  done
  echo "------------------------------------------"
  echo "tmp/.packageinfo 包总数: $(grep -c '^Package: ' tmp/.packageinfo 2>/dev/null || echo 0)"
  echo "=========================================="
  # 必装插件（configs/nx30pro-nmbm.config 里是 =y 的那几个）必须进索引，
  # 否则 defconfig 会静默剔除。任一项没进索引，直接报错退出。
  REQUIRED="easytier-noweb luci-app-easytier mihomo homi luci-app-homi luci-theme-aurora luci-app-aurora-config luci-app-netpath"
  HARD_MISS=""
  for r in $REQUIRED; do
    grep -qx "Package: $r" tmp/.packageinfo 2>/dev/null || HARD_MISS="$HARD_MISS $r"
  done
  if [ -n "$HARD_MISS" ]; then
    echo "::error::以下必装插件未进入 tmp/.packageinfo，defconfig 会把 .config 里的 =y 静默剔除:$HARD_MISS"
    echo "  已索引缺失清单:$INDEX_MISS"
    exit 1
  fi
  [ -n "$INDEX_MISS" ] && echo "::warning::部分可选包未进入索引（不影响必装插件）:$INDEX_MISS"
else
  echo "未启用任何第三方插件"
fi
echo "🎉 customize.sh 执行完毕"
