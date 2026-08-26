#!/bin/bash
# Komari Agent - gen-config.sh
# 从 WIZARD_* 环境变量生成初始 config.json（零第三方依赖，仅 bash 内置）
# 用法: WIZARD_ENDPOINT=... WIZARD_TOKEN=... gen-config.sh <outfile>
set -u

OUT="${1:?usage: gen-config.sh <outfile>}"

# JSON 字符串转义（先反斜杠后双引号，防破坏 JSON 结构）
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

# 数字/布尔兜底解析
num_or() { # num_or <value> <default>
  local v="$1" d="$2"
  case "$v" in
    ''|*[!0-9.]*) printf '%s' "$d" ;;
    *) printf '%s' "$v" ;;
  esac
}
bool_or() { # bool_or <value> <default>
  local v="$1" d="$2"
  case "$v" in
    true|false) printf '%s' "$v" ;;
    '') printf '%s' "$d" ;;
    *) printf '%s' "$d" ;;
  esac
}

EP="$(json_escape "${WIZARD_ENDPOINT:-}")"
TK="$(json_escape "${WIZARD_TOKEN:-}")"
IV="$(num_or "${WIZARD_INTERVAL:-}" "3")"
WS="$(bool_or "${WIZARD_DISABLE_WEB_SSH:-}" "false")"
GPU="$(bool_or "${WIZARD_ENABLE_GPU:-}" "false")"
CERT="$(bool_or "${WIZARD_IGNORE_UNSAFE_CERT:-}" "false")"

cat > "$OUT" <<EOF
{
  "endpoint": "$EP",
  "token": "$TK",
  "interval": $IV,
  "disable_auto_update": true,
  "disable_web_ssh": $WS,
  "ignore_unsafe_cert": $CERT,
  "max_retries": 3,
  "reconnect_interval": 5,
  "info_report_interval": 5,
  "protocol_version": 2,
  "enable_gpu": $GPU,
  "_fnos_log_enabled": true,
  "_fnos_log_max_size_mb": 5,
  "_fnos_log_keep": 3
}
EOF

chmod 600 "$OUT" 2>/dev/null
exit 0
