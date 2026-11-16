#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
黑猫公益拦截 · 卡密生成接口 · Python 示例

依赖: pip install requests
"""

import hashlib
import hmac
import json
import time

import requests

API_URL = "https://ios.ouovo.cc/bot.php"

# 从服务器 /www/wwwroot/ios.ouovo.cc/storage/bot_config.php 里抄过来
API_KEY = "在这里填 api_key"

# 只有开启 require_signature 时才需要
SECRET = "在这里填 secret"
REQUIRE_SIGN = False


def gen_cards(count=1, days=7, charset="std", batch="", note=""):
    """生成卡密，返回接口的原始 dict。

    count   : 1 ~ 500
    days    : 最长 30，可以给小数
    charset : std(无歧义) / digit(纯数字) / alpha(纯字母) / full
    """
    body = {"count": int(count), "days": float(days), "charset": charset}
    if batch:
        body["batch"] = batch
    if note:
        body["note"] = note

    # 签名必须对「发出去的原始字节」做 HMAC，所以先序列化再发字符串
    raw = json.dumps(body, separators=(",", ":"), ensure_ascii=False)

    headers = {
        "X-Api-Key": API_KEY,
        "Content-Type": "application/json",
    }

    if REQUIRE_SIGN:
        ts = str(int(time.time()))
        payload = f"{ts}\nPOST\ncards.generate\n{raw}"
        headers["X-Timestamp"] = ts
        headers["X-Sign"] = hmac.new(
            SECRET.encode("utf-8"), payload.encode("utf-8"), hashlib.sha256
        ).hexdigest()

    r = requests.post(API_URL, data=raw.encode("utf-8"), headers=headers, timeout=20)
    try:
        data = r.json()
    except ValueError:
        raise RuntimeError(f"HTTP {r.status_code} 非 JSON 响应: {r.text[:200]}")

    if not data.get("ok"):
        raise RuntimeError(f"生成失败: {data.get('error')} (HTTP {r.status_code})")

    return data


def health():
    headers = {"X-Api-Key": API_KEY}
    r = requests.post(f"{API_URL}?action=health", headers=headers, data=b"", timeout=10)
    return r.json()


if __name__ == "__main__":
    print(health())

    res = gen_cards(count=3, days=7, charset="std", batch="HM20261117", note="公益发放")
    print(f"生成了 {res['created']} 张，有效 {res['duration_days']} 天，批次 {res['batch']}")
    for code in res["codes"]:
        print(code)

    # 对接 Telegram Bot 的写法大概长这样：
    #
    # from telegram import Update
    # from telegram.ext import CommandHandler, ContextTypes
    #
    # async def cmd_gen(update: Update, context: ContextTypes.DEFAULT_TYPE):
    #     if update.effective_user.id not in ADMIN_IDS:
    #         return
    #     res = gen_cards(count=1, days=7, batch="HM-TG", note=f"tg:{update.effective_user.id}")
    #     await update.message.reply_text(f"卡密：{res['codes'][0]}\n有效期：{res['duration_days']} 天")
    #
    # app.add_handler(CommandHandler("gen", cmd_gen))
