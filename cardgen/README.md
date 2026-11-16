# 黑猫公益拦截 · 卡密生成接口

部署位置：`/www/wwwroot/ios.ouovo.cc/public/bot.php`
访问地址：`POST https://ios.ouovo.cc/bot.php`

只做一件事：**生成卡密**。查卡、作废、续期、踢设备、公告、统计那些接口已经全部删掉了（后台管理页照旧能查能管）。

---

## 一、鉴权

每个请求带一个头：

```
X-Api-Key: <storage/bot_config.php 里的 api_key>
```

也支持 `Authorization: Bearer <api_key>`。

密钥文件在网站目录之外的 `storage/bot_config.php`，我没动里面的 api_key / secret。要换密钥就改这个文件里的 `api_key`（32 位字符串，改完记得同步改你机器人那边的配置）。

---

## 二、请求参数（JSON，全部可选）

| 参数 | 类型 | 范围 | 默认 | 说明 |
|---|---|---|---|---|
| `count` | int | 1 ~ 500 | 1 | 一次生成几张 |
| `days` | float | 0.0007 ~ 30 | 7 | 有效天数，支持小数（如 0.5 = 12 小时） |
| `seconds` | int | 60 ~ 2592000 | — | 直接给秒数，优先于 `days` |
| `charset` | string | std / digit / alpha / full | std | std=去掉形近字（I O S 0 1 2 5 8 B Z），适合人眼看 |
| `batch` | string | ≤32 字符 | `ZK+日期` | 批次号，方便你在后台按批次查 |
| `note` | string | ≤110 字 | `api:IP` | 备注，后台可见 |

**卡密格式**：`XXXX-XXXX-XXXX-XXXX`（16 位，4 组）

> 有效期是从**首次兑换**开始算的，不是从生成那刻算。生成后放着不兑换就不会走时间。

---

## 三、返回

```json
{
  "ok": true,
  "created": 2,
  "count": 2,
  "duration_sec": 604800,
  "duration_days": 7,
  "charset": "std",
  "batch": "HM20261117",
  "note": "公益发放",
  "codes": ["PQGL-UXW7-YMYF-KC3W", "33EM-URRM-KN9T-CU7R"],
  "time": 1794851439
}
```

## 四、错误

| HTTP | error | 意思 |
|---|---|---|
| 401 | `missing_api_key` | 没带 key |
| 401 | `bad_api_key` | key 不对 |
| 401 | `missing_signature` / `bad_signature` | 开了签名但没带 / 签名错 |
| 401 | `stale_timestamp` | 时间戳超过 ±300 秒 |
| 403 | `ip_not_allowed` | IP 不在白名单 |
| 404 | `unknown_action` | 传了不存在的 action |
| 405 | `method_not_allowed` | 用了 GET，这个接口只收 POST |
| 500 | `server_error` | 服务端异常，详情看 `storage/logs/cardapi-日期.log` |

---

## 五、接口地址两种写法（等价）

```
POST https://ios.ouovo.cc/bot.php
POST https://ios.ouovo.cc/bot.php?action=cards.generate
```

`GET /bot.php?action=health` 不行，但 `POST ?action=health` 可以，用来确认服务活着（也要带 key）。

---

## 六、可选：开启请求签名（默认关闭）

现在的模式是「有 api_key 就能调」。如果你想更严（防 key 被截了重放），在 `storage/bot_config.php` 里加一行：

```php
'require_signature' => true,
```

开启后每个请求要额外带：

```
X-Timestamp: 秒级时间戳（±300 秒内有效）
X-Sign: hash_hmac('sha256', ts."\n".METHOD."\n".action."\n".rawBody, secret)
```

`secret` 就是配置文件里那个 64 位字符串。示例脚本里已经把这套写好了，把 `REQUIRE_SIGN = True` 就行。

其它可选配置（同样写进 `bot_config.php`）：

```php
'allowed_ips'  => ['1.2.3.4', '5.6.7.*'],  // IP 白名单，空数组=不限制
'max_count'    => 500,
'max_days'     => 30,
'default_days' => 7,
'time_window'  => 300,
```

> 我在你服务器上验证过：开启签名后，正确签名 200、错误签名 401、没带签名 401、过期时间戳 401，四种都符合预期。测试完已经把配置恢复成原来的（签名关闭）。

---

## 七、现成调用示例

同目录下：

- `cardgen.py` —— Python（对接机器人最常用）
- `cardgen.php` —— PHP
- `cardgen.sh` —— curl 命令行

---

## 八、改了什么

- 原 `bot.php` 有 12 个接口，现在只留 `cards.generate` 和 `health`
- 移除：`cards.info` / `cards.disable` / `cards.enable` / `cards.extend` / `pins.status` / `pins.revoke` / `announcement.get` / `announcement.set` / `announcement.clear` / `stats`
- 新增：`Authorization: Bearer` 支持、IP 白名单、单次数量/天数上限可配
- 原来的 `bot_config.php` 没改，api_key / secret 照旧
- 原文件备份在服务器 `/root/bak-20261116_175017/public/bot.php`

## 九、上限想调

现在单张最长 30 天、单次最多 500 张。要发更长的卡（比如 90 天 / 一年），跟我说一句，改两个数字就行。
