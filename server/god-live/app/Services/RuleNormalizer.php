<?php
declare(strict_types=1);

/**
 * 规则导入适配器
 *
 * 后台「导入 txt」用它把各种来源的规则统一成客户端认识的三段式：
 *
 *   #IP      1.2.3.4 / 1.2.3.0/24
 *   #DOMAIN  example.com（含全部子域）
 *   #DIRECT  example.com（放行，优先命中）
 *   #PORT    443
 *
 * 能吃进去的格式：
 *   - 原生分段（#IP / #DOMAIN / #DIRECT / #PORT）
 *   - 纯 IP、CIDR、一行多个（空格 / 逗号 / 制表符分隔）
 *   - hosts：0.0.0.0 example.com（拦截）、127.0.0.1 example.com（放行）
 *   - dnsmasq：address=/example.com/0.0.0.0
 *   - AdGuard / 通用订阅：||example.com^、@@||example.com^、|https://example.com
 *   - 带端口：1.2.3.4:8080、example.com:443
 *   - 端口范围：1000-2000
 *   - 注释：# 开头、! 开头、; 开头、// 开头、行尾 " #"
 *   - 通配与噪声符号：*. ^ | @@
 *
 * 认不出来的行不报错，计入 skipped，最后在后台显示，方便对账。
 */
final class RuleNormalizer
{
    public static function normalise(string $raw): array
    {
        $raw = str_replace(["\r\n", "\r"], "\n", $raw);
        $raw = preg_replace('/^\xEF\xBB\xBF/', '', $raw) ?? $raw;

        $ips     = [];
        $cidrs   = [];
        $domains = [];
        $direct  = [];
        $ports   = [];
        $skipped = 0;

        $section  = '';
        $lines    = explode("\n", $raw);
        $lineCount = count($lines);

        foreach ($lines as $line) {
            $line = trim($line);
            if ($line === '') {
                continue;
            }

            // 段落标记
            if ($line[0] === '#') {
                $head = strtoupper($line);
                if (strpos($head, '#IP') === 0 && strlen($line) <= 8)    { $section = 'ip'; continue; }
                if (strpos($head, '#DOMAIN') === 0 && strlen($line) <= 14) { $section = 'domain'; continue; }
                if (strpos($head, '#DIRECT') === 0 && strlen($line) <= 14) { $section = 'direct'; continue; }
                if (strpos($head, '#PORT') === 0 && strlen($line) <= 10)  { $section = 'port'; continue; }
                continue;
            }
            if ($line[0] === '!' || $line[0] === ';' || strpos($line, '//') === 0) {
                continue;
            }

            // 行尾注释
            $pos = strpos($line, ' #');
            if ($pos !== false) {
                $line = trim(substr($line, 0, $pos));
            }
            if ($line === '') {
                continue;
            }

            $tokens = preg_split('/[\s,]+/u', $line) ?: [];

            // hosts：0.0.0.0 a.com b.com / 127.0.0.1 a.com
            if (count($tokens) > 1 && self::ipToInt($tokens[0]) !== null
                && in_array($tokens[0], ['0.0.0.0', '127.0.0.1'], true)) {
                $isDirect = ($tokens[0] === '127.0.0.1');
                for ($i = 1; $i < count($tokens); $i++) {
                    $d = self::cleanDomain($tokens[$i]);
                    if ($d !== '') {
                        if ($isDirect) { $direct[$d] = true; } else { $domains[$d] = true; }
                    } else {
                        $skipped++;
                    }
                }
                continue;
            }

            foreach ($tokens as $token) {
                $add = self::absorb($token, $section);
                $skipped += $add['skipped'];
                if ($add['ip'] !== null)    { $ips[$add['ip']] = true; }
                if ($add['cidr'] !== null)  { $cidrs[$add['cidr']] = true; }
                if ($add['domain'] !== null) { $domains[$add['domain']] = true; }
                if ($add['direct'] !== null) { $direct[$add['direct']] = true; }
                foreach ($add['ports'] as $p) { $ports[$p] = true; }
            }
        }

        // 输出：IP 数值序，域名/端口字典序，保证同样的输入永远得到同样的输出
        $ipList = array_keys($ips);
        usort($ipList, function ($a, $b) {
            return self::ipToInt($a) <=> self::ipToInt($b);
        });
        $cidrList = array_keys($cidrs);
        sort($cidrList, SORT_STRING);

        $domainList = array_keys($domains);
        sort($domainList, SORT_STRING);
        $directList = array_keys($direct);
        sort($directList, SORT_STRING);

        $portList = array_keys($ports);
        sort($portList, SORT_NUMERIC);

        $out = '';
        if ($ipList || $cidrList) {
            $out .= "#IP\n" . implode("\n", array_merge($ipList, $cidrList)) . "\n";
        }
        if ($domainList) {
            $out .= "#DOMAIN\n" . implode("\n", $domainList) . "\n";
        }
        if ($directList) {
            $out .= "#DIRECT\n" . implode("\n", $directList) . "\n";
        }
        if ($portList) {
            $out .= "#PORT\n" . implode("\n", array_map('strval', $portList)) . "\n";
        }

        if ($out === '') {
            return [
                'ok'      => false,
                'error'   => 'no_rules',
                'message' => '这个文件里没认出任何规则，检查一下是不是规则 txt',
                'ips'     => 0, 'domains' => 0, 'direct' => 0, 'ports' => 0,
                'skipped' => $skipped, 'lines' => $lineCount, 'text' => '',
            ];
        }

        return [
            'ok'      => true,
            'text'    => $out,
            'ips'     => count($ipList) + count($cidrList),
            'domains' => count($domainList),
            'direct'  => count($directList),
            'ports'   => count($portList),
            'skipped' => $skipped,
            'lines'   => $lineCount,
        ];
    }

    /** 单个 token → 各类目 */
    private static function absorb(string $token, string $section): array
    {
        $res = ['ip' => null, 'cidr' => null, 'domain' => null, 'direct' => null,
                'ports' => [], 'skipped' => 0];

        $t = trim($token);
        if ($t === '') { return $res; }

        // 单独出现的前导地址
        if ($t === '0.0.0.0' || $t === '127.0.0.1') { return $res; }

        // 正则类规则直接跳
        if ($t[0] === '/' || $t[0] === '[') { $res['skipped']++; return $res; }

        $isDirect = false;
        if (strpos($t, '@@') === 0) { $isDirect = true; $t = substr($t, 2); }

        // dnsmasq: address=/x.com/0.0.0.0
        if (stripos($t, 'address=') === 0) {
            $parts = explode('/', $t);
            foreach ($parts as $part) {
                $part = trim($part);
                if ($part === '' || $part === 'address=' || $part === '0.0.0.0' || $part === '127.0.0.1') {
                    continue;
                }
                $d = self::cleanDomain($part);
                if ($d !== '') { $res['domain'] = $d; return $res; }
            }
            $res['skipped']++;
            return $res;
        }

        // 通配与注解符号
        $t = ltrim($t, "|*.@");
        $t = rtrim($t, "^|*.");
        if ($t === '') { $res['skipped']++; return $res; }

        // 端口段 1000-2000
        if (preg_match('/^(\d{1,5})-(\d{1,5})$/', $t, $m)) {
            $a = (int) $m[1];
            $b = (int) $m[2];
            if ($a > 0 && $b >= $a && $b <= 65535) {
                for ($p = $a; $p <= $b && count($res['ports']) < 4096; $p++) {
                    $res['ports'][] = $p;
                }
                return $res;
            }
            $res['skipped']++;
            return $res;
        }

        // 纯端口
        if ($section === 'port' || preg_match('/^\d{1,5}$/', $t)) {
            $p = (int) $t;
            if ($p > 0 && $p <= 65535) {
                $res['ports'][] = $p;
                return $res;
            }
        }

        // IP:端口 / 域名:端口
        $host = $t;
        if (preg_match('/^([^\s:]+):(\d{1,5})$/', $t, $m)) {
            $host = $m[1];
            $p = (int) $m[2];
            if ($p > 0 && $p <= 65535) { $res['ports'][] = $p; }
        }

        // CIDR
        if (strpos($host, '/') !== false) {
            $c = self::cleanCidr($host);
            if ($c !== null) {
                $res['cidr'] = $c;
                return $res;
            }
        }

        // 纯 IP
        if ($section !== 'domain' && self::ipToInt($host) !== null) {
            $res['ip'] = $host;
            return $res;
        }

        // 域名
        $d = self::cleanDomain($host);
        if ($d !== '') {
            if ($isDirect || $section === 'direct') { $res['direct'] = $d; }
            else { $res['domain'] = $d; }
            return $res;
        }

        $res['skipped']++;
        return $res;
    }

    private static function cleanDomain(string $raw): string
    {
        $d = strtolower(trim($raw));
        if ($d === '') { return ''; }

        while (preg_match('/^(@@|\|\||\*\.|\.)/', $d)) {
            if (strpos($d, '@@') === 0 || strpos($d, '||') === 0) {
                $d = substr($d, 2);
            } else {
                $d = substr($d, 1);
            }
        }
        $d = rtrim($d, "^|*. ");
        $d = preg_replace('#^https?://#', '', $d) ?? $d;
        $slash = strpos($d, '/');
        if ($slash !== false) { $d = substr($d, 0, $slash); }
        $colon = strpos($d, ':');
        if ($colon !== false) { $d = substr($d, 0, $colon); }
        $d = rtrim($d, '.');

        if (strlen($d) < 3 || strlen($d) > 253 || strpos($d, '.') === false) {
            return '';
        }
        if (!preg_match('/^[a-z0-9]([a-z0-9\-_.]*[a-z0-9])?$/', $d)) {
            return '';
        }
        if (strpos($d, '..') !== false) {
            return '';
        }
        return $d;
    }

    private static function cleanCidr(string $raw): ?string
    {
        $parts = explode('/', $raw);
        if (count($parts) !== 2) { return null; }
        $ip = self::ipToInt($parts[0]);
        if ($ip === null) { return null; }
        if (!preg_match('/^\d{1,2}$/', $parts[1])) { return null; }
        $bits = (int) $parts[1];
        if ($bits < 0 || $bits > 32) { return null; }
        return $parts[0] . '/' . $bits;
    }

    private static function ipToInt(string $ip): ?int
    {
        $parts = explode('.', $ip);
        if (count($parts) !== 4) { return null; }
        $v = 0;
        foreach ($parts as $p) {
            if ($p === '' || !preg_match('/^\d+$/', $p)) { return null; }
            $n = (int) $p;
            if ($n < 0 || $n > 255) { return null; }
            $v = ($v << 8) | $n;
        }
        return $v;
    }
}
