<?php
declare(strict_types=1);

/**
 * 黑猫公益拦截 · 卡密生成接口 · PHP 示例
 */

const API_URL = 'https://ios.ouovo.cc/bot.php';
const API_KEY = '在这里填 api_key';
const SECRET  = '在这里填 secret';      // 只在开启签名时需要
const REQUIRE_SIGN = false;

/**
 * @return array 接口返回的原始结构
 * @throws RuntimeException
 */
function gen_cards(int $count = 1, float $days = 7, string $charset = 'std',
                   string $batch = '', string $note = ''): array
{
    $body = ['count' => $count, 'days' => $days, 'charset' => $charset];
    if ($batch !== '') { $body['batch'] = $batch; }
    if ($note !== '')  { $body['note']  = $note; }

    // 签名要对「实际发出去的原始字节」算，所以先 encode 再发字符串
    $raw = json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);

    $headers = [
        'X-Api-Key: ' . API_KEY,
        'Content-Type: application/json',
    ];

    if (REQUIRE_SIGN) {
        $ts = (string) time();
        $payload = $ts . "\n" . 'POST' . "\n" . 'cards.generate' . "\n" . $raw;
        $headers[] = 'X-Timestamp: ' . $ts;
        $headers[] = 'X-Sign: ' . hash_hmac('sha256', $payload, SECRET);
    }

    $ch = curl_init(API_URL);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => $raw,
        CURLOPT_HTTPHEADER     => $headers,
        CURLOPT_TIMEOUT        => 20,
    ]);
    $resp = curl_exec($ch);
    $http = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err  = curl_error($ch);
    curl_close($ch);

    if ($resp === false) {
        throw new RuntimeException('请求失败: ' . $err);
    }

    $data = json_decode((string) $resp, true);
    if (!is_array($data)) {
        throw new RuntimeException('HTTP ' . $http . ' 非 JSON: ' . substr((string) $resp, 0, 200));
    }
    if (empty($data['ok'])) {
        throw new RuntimeException('生成失败: ' . ($data['error'] ?? 'unknown') . ' (HTTP ' . $http . ')');
    }
    return $data;
}

// ---------------- 用法 ----------------
try {
    $r = gen_cards(3, 7, 'std', 'HM20261117', '公益发放');
    echo "生成了 {$r['created']} 张，有效 {$r['duration_days']} 天\n";
    foreach ($r['codes'] as $code) {
        echo $code, "\n";
    }
} catch (Throwable $e) {
    echo '错误: ', $e->getMessage(), "\n";
}
