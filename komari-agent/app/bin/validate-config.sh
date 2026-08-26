#!/bin/bash
# Komari Agent - validate-config.sh
# 用 komari-agent 自身校验 config.json：
#   写临时文件 → 以 --config 试运行（timeout 3s）→
#   rc=124（被 timeout 优雅停止，说明解析通过并正常持续运行）→ 校验通过
#   rc=其他（agent 立即退出，通常是配置解析失败）→ 校验失败，输出 agent 错误日志
# 用法: validate-config.sh <config文件>
#   返回 0 = 通过；返回 1 = 失败（错误信息打印到 stdout）
set -u

APP_DIR="/var/apps/komari-agent/target"
TMP_DIR="/var/apps/komari-agent/tmp"
AGENT_BIN="${APP_DIR}/komari-agent"
SRC="${1:?usage: validate-config.sh <config-file>}"

[ -f "$SRC" ] || { echo "配置文件不存在: $SRC"; exit 1; }
[ -x "$AGENT_BIN" ] || { echo "agent 二进制不可执行: $AGENT_BIN"; exit 1; }

mkdir -p "$TMP_DIR" 2>/dev/null || true
TMP_FILE="${TMP_DIR}/validate.$$.json"
TMP_ERR="${TMP_FILE}.err"
trap 'rm -f "$TMP_FILE" "$TMP_ERR"' EXIT

cp "$SRC" "$TMP_FILE"
chmod 600 "$TMP_FILE" 2>/dev/null

# 试运行 3 秒：解析通过则 agent 会持续运行直到被 timeout 优雅停止（124）
timeout 3 "$AGENT_BIN" --config "$TMP_FILE" >/dev/null 2>"$TMP_ERR"
RC=$?

if [ "$RC" = "124" ]; then
  exit 0
fi

echo "配置校验失败（agent 退出码 $RC）："
echo "----------------------------------------------------------------"
sed -n '1,20p' "$TMP_ERR" 2>/dev/null || echo "(agent 未输出错误信息)"
echo "----------------------------------------------------------------"
echo "请修正配置中的语法或字段错误后重试。"
exit 1
