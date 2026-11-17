<?php
declare(strict_types=1);

/**
 * 云端规则库：按卡密下发、加密、密钥每日轮换
 *
 * 下发链路：
 *   1. 客户端带 (pin, 卡密) 请求 manifest，服务端校验卡密有效后返回版本 / 指纹 / 当日密钥桶
 *   2. 客户端用 SHA256(pin|卡密|桶|版本) → HKDF-SHA256 推出当日密钥
 *   3. 客户端下载二进制包：HMR1 + nonce(12) + AES-256-GCM 密文 + tag(16)
 *   4. 客户端本地解密 → sha256 校验 → 只在内存里解析
 *
 * 因此：没有有效卡密拿不到包；拿到了包没有卡密也解不开；
 * 密钥每天 UTC 0 点轮换，隔天旧密钥失效。
 */
final class RulesService
{
    public const MAGIC = 'HMR1';
    public const SALT = 'heimao-salt-v1';
    public const INFO = 'heimao-rules-v1';

    /** 当前生效的规则包 */
    public static function current(): ?array
    {
        $row = Database::pdo()->query(
            'SELECT id, version, note, sha256, bytes, ip_count, domain_count, port_count, updated_at
             FROM rule_packs WHERE active = 1 ORDER BY id DESC LIMIT 1'
        )->fetch();
        return $row ?: null;
    }

    public static function content(int $id): string
    {
        $st = Database::pdo()->prepare('SELECT content FROM rule_packs WHERE id = ?');
        $st->execute([$id]);
        $c = $st->fetchColumn();
        return $c === false ? '' : (string) $c;
    }

    /** 保存一版新规则（同时把旧的置为非生效） */
    public static function save(string $version, string $note, string $content, string $admin, string $ip): array
    {
        $version = trim($version);
        if ($version === '' || strlen($version) > 32) {
            return ['ok' => false, 'error' => 'bad_version'];
        }
        $content = str_replace("\r\n", "\n", $content);
        if (strlen($content) < 20) {
            return ['ok' => false, 'error' => 'empty_rules'];
        }
        if (strlen($content) > 2 * 1024 * 1024) {
            return ['ok' => false, 'error' => 'too_large'];
        }

        $counts = self::counts($content);
        $sha = hash('sha256', $content);
        $pdo = Database::pdo();

        $pdo->beginTransaction();
        try {
            $pdo->exec('UPDATE rule_packs SET active = 0');
            $pdo->prepare(
                'INSERT INTO rule_packs(version, note, content, sha256, bytes, ip_count, domain_count, port_count, active, updated_at)
                 VALUES(?,?,?,?,?,?,?,?,1,?)'
            )->execute([
                $version, mb_substr(trim($note), 0, 200), $content, $sha, strlen($content),
                $counts['ip'], $counts['domain'], $counts['port'], time(),
            ]);
            $id = (int) $pdo->lastInsertId();
            $pdo->prepare('INSERT INTO audit(ts, admin, action, target, ip, detail) VALUES(?,?,?,?,?,?)')
                ->execute([time(), $admin, 'rules.save', $version, $ip,
                           json_encode($counts, JSON_UNESCAPED_UNICODE)]);
            $pdo->commit();
        } catch (Throwable $e) {
            $pdo->rollBack();
            Log::file('app', 'rules save error: ' . $e->getMessage());
            return ['ok' => false, 'error' => 'server_error'];
        }

        return ['ok' => true, 'id' => $id, 'version' => $version, 'sha256' => $sha,
                'bytes' => strlen($content)] + $counts;
    }

    /** 当日密钥桶 + 距离轮换的秒数 */
    public static function bucket(): array
    {
        $now = time();
        return [gmdate('Ymd', $now), 86400 - ($now % 86400)];
    }

    /** 客户端与服务端用同一套参数推导当日密钥 */
    public static function deriveKey(string $pin, string $code, string $bucket, string $version): string
    {
        $ikm = hash('sha256', $pin . '|' . $code . '|' . $bucket . '|' . $version, true);
        return hash_hkdf('sha256', $ikm, 32, self::INFO, self::SALT);
    }

    /** AES-256-GCM 加密，输出 MAGIC + nonce + 密文 + tag */
    public static function encrypt(string $plain, string $key): string
    {
        $nonce = random_bytes(12);
        $tag = '';
        $ct = openssl_encrypt($plain, 'aes-256-gcm', $key, OPENSSL_RAW_DATA, $nonce, $tag, '', 16);
        if ($ct === false) {
            throw new RuntimeException('aes encrypt failed');
        }
        return self::MAGIC . $nonce . $ct . $tag;
    }

    /** 规则条数统计（与客户端解析口径一致） */
    public static function counts(string $content): array
    {
        $ip = 0; $domain = 0; $port = 0;
        $section = '';
        foreach (preg_split('/\n/', $content) ?: [] as $line) {
            $line = trim($line);
            if ($line === '' || $line === '0') { continue; }
            if ($line[0] === '#' || substr($line, 0, 2) === '//' || $line[0] === ';') {
                $key = strtoupper(trim(substr($line, 1)));
                if (strpos($key, 'IP') === 0) { $section = 'ip'; }
                elseif (strpos($key, 'DOMAIN') === 0 || strpos($key, 'HOST') === 0) { $section = 'domain'; }
                elseif (strpos($key, 'PORT') === 0) { $section = 'port'; }
                continue;
            }
            if ($section === 'ip') { $ip++; }
            elseif ($section === 'domain') { $domain++; }
            elseif ($section === 'port') { $port++; }
        }
        return ['ip' => $ip, 'domain' => $domain, 'port' => $port];
    }

    /** 给客户端下发的 manifest（不含任何规则内容） */
    public static function manifest(): array
    {
        $pack = self::current();
        if (!$pack) {
            return ['ok' => false, 'error' => 'no_rules'];
        }
        [$bucket, $ttl] = self::bucket();
        return [
            'ok'        => true,
            'version'   => (string) $pack['version'],
            'sha256'    => (string) $pack['sha256'],
            'bytes'     => (int) $pack['bytes'],
            'bucket'    => $bucket,
            'key_ttl'   => $ttl,
            'algorithm' => 'AES-256-GCM/HKDF-SHA256',
            'counts'    => [
                'ip'     => (int) $pack['ip_count'],
                'domain' => (int) $pack['domain_count'],
                'port'   => (int) $pack['port_count'],
            ],
            'server_time' => time(),
        ];
    }
}
