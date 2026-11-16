#!/usr/bin/env bash
# 黑猫公益拦截 · 卡密生成 · curl 示例
#
# 用法:
#   ./cardgen.sh                # 生成 1 张 7 天
#   ./cardgen.sh 5 7            # 生成 5 张 7 天
#   ./cardgen.sh 100 30 HM1117  # 生成 100 张 30 天，批次 HM1117

set -euo pipefail

API="https://ios.ouovo.cc/bot.php"
KEY="${CARD_API_KEY:?请先 export CARD_API_KEY=<storage/bot_config.php 里的 api_key>}"

COUNT="${1:-1}"
DAYS="${2:-7}"
BATCH="${3:-}"

if [ -n "$BATCH" ]; then
  BODY="{\"count\":${COUNT},\"days\":${DAYS},\"charset\":\"std\",\"batch\":\"${BATCH}\"}"
else
  BODY="{\"count\":${COUNT},\"days\":${DAYS},\"charset\":\"std\"}"
fi

curl -sS -X POST "$API" \
  -H "X-Api-Key: ${KEY}" \
  -H "Content-Type: application/json" \
  --data-binary "$BODY"
echo
