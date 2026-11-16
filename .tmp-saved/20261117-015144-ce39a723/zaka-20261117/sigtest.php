<?php
declare(strict_types=1);

$cfgf = '/www/wwwroot/ios.ouovo.cc/storage/bot_config.php';
$orig = file_get_contents($cfgf);

function call(array $c, string $action, string $body, $ts, $sign)
{
    $ch = curl_init('https://127.0.0.1/bot.php' . ($action !== '' ? '?action=' . $action : ''));
    $h = ['Host: ios.ouovo.cc', 'X-Api-Key: ' . $c['api_key'], 'Content-Type: application/json'];
    if ($ts !== null) {
        $h[] = 'X-Timestamp: ' . $ts;
    }
    if ($sign !== null) {
        $h[] = 'X-Sign: ' . $sign;
    }
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => 1, CURLOPT_POST => 1, CURLOPT_POSTFIELDS => $body,
        CURLOPT_SSL_VERIFYPEER => 0, CURLOPT_SSL_VERIFYHOST => 0,
        CURLOPT_HTTPHEADER => $h, CURLOPT_TIMEOUT => 20,
    ]);
    $r = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    echo str_pad($action === '' ? 'cards.generate' : $action, 16), '[', $code, '] ', $r, PHP_EOL;
    return json_decode((string) $r, true);
}

$c = require $cfgf;
$c['require_signature'] = true;
file_put_contents($cfgf, "<?php\nreturn " . var_export($c, true) . ";\n");

try {
    $body = json_encode(['count' => 1, 'days' => 1, 'batch' => 'SIGTEST', 'note' => 'api-sigtest']);
    $ts = (string) time();
    $sig = fn(string $s) => hash_hmac('sha256', $s . "\nPOST\ncards.generate\n" . $body, $c['secret']);

    echo "--- good sig ---\n";
    $r = call($c, '', $body, $ts, $sig($ts));
    echo "--- bad sig ---\n";
    call($c, '', $body, $ts, str_repeat('a', 64));
    echo "--- no sig ---\n";
    call($c, '', $body, null, null);
    echo "--- stale ts ---\n";
    $old = (string) (time() - 1000);
    call($c, '', $body, $old, $sig($old));

    if (!empty($r['codes'])) {
        echo 'CODE=', $r['codes'][0], PHP_EOL;
    }
} finally {
    file_put_contents($cfgf, $orig);
    echo "CONFIG_RESTORED\n";
}
