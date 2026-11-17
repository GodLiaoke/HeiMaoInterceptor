<?php
return [
    'db_path'       => __DIR__ . '/sqlite/app.db',
    'pin_len'       => 8,
    'grant_seconds' => 300,
    'auth_window_sec' => 600,   /* 在线校验窗口（秒）：600 秒，客户端每 60 秒续期一次 */
    'grace_sec'     => 300,     /* 断网宽限（秒）：窗口过期后再容忍 5 分钟 */
    'rate_ip'       => 120,
    'rate_pin'      => 40,
    'timezone'      => 'Asia/Shanghai',
    'api_key'       => 'YOUR_API_KEY_HERE',   // v2 加密协议密钥，客户端内置同一把
];
