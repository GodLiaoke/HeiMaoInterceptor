<?php
declare(strict_types=1);

/**
 * 功能库校验
 *
 * 客户端每次强校验把「每个功能 5 条 CRC」一起报上来，格式：
 *   crypto.sha256:1,2,3,4,5|crypto.hmac:...|ruleset.parse:...
 *
 * 服务端按「build + 功能」登记一条哈希：
 *   hash = sha256(build|feature|crc1|...|crc5)
 *
 * 第一次见到的组合自动登记（新版本发布不用人工填表），之后每一次上报都逐条比对。
 * 不一致只记录、只回 fc_ok=false，不阻断用户 —— 先把基线攒起来，
 * 确认误报为零之后再决定要不要拿它做硬门禁。
 */
final class FeatureService
{
    /** 一个 build 最多接受多少个功能，防止有人拿脏数据把表撑爆 */
    private const MAX_FEATURES = 24;

    public static function evaluate(string $pin, string $raw, int $build, string $ip, string $ua): array
    {
        $raw = trim($raw);
        if ($raw === '' || $build <= 0) {
            return ['ok' => true, 'features' => 0, 'new' => 0, 'mismatch' => [], 'checked' => false];
        }

        $items = self::parse($raw);
        if ($items === []) {
            return ['ok' => false, 'features' => 0, 'new' => 0, 'mismatch' => [], 'checked' => false];
        }

        $pdo = Database::pdo();
        $now = date('Y-m-d H:i:s');

        $sel = $pdo->prepare(
            'SELECT id, crc1, crc2, crc3, crc4, crc5, hash
               FROM feature_checks WHERE build = ? AND feature = ?'
        );
        $ins = $pdo->prepare(
            'INSERT INTO feature_checks
                (build, feature, crc1, crc2, crc3, crc4, crc5, hash, first_pin, hits, created_at, updated_at)
             VALUES (?,?,?,?,?,?,?,?,?,1,?,?)'
        );
        $hit = $pdo->prepare('UPDATE feature_checks SET hits = hits + 1, updated_at = ? WHERE id = ?');
        $bad = $pdo->prepare(
            'UPDATE feature_checks SET mismatches = mismatches + 1,
                    last_mismatch_at = ?, last_mismatch_pin = ? WHERE id = ?'
        );

        $mismatch = [];
        $new      = 0;

        foreach ($items as $feature => $crcs) {
            $hash = self::hash($build, $feature, $crcs);
            $sel->execute([$build, $feature]);
            $row = $sel->fetch(PDO::FETCH_ASSOC);

            if (!$row) {
                try {
                    $ins->execute([
                        $build, $feature,
                        $crcs[0], $crcs[1], $crcs[2], $crcs[3], $crcs[4],
                        $hash, $pin, $now, $now,
                    ]);
                    $new++;
                } catch (Throwable $e) {
                    /* 并发下同一个 (build, feature) 被两条请求同时登记：唯一键会挡掉一条，忽略即可 */
                    Log::file('feature', 'register race ' . $feature . ': ' . $e->getMessage());
                }
                continue;
            }

            $same = ((int) $row['crc1'] === $crcs[0]
                  && (int) $row['crc2'] === $crcs[1]
                  && (int) $row['crc3'] === $crcs[2]
                  && (int) $row['crc4'] === $crcs[3]
                  && (int) $row['crc5'] === $crcs[4]
                  && hash_equals((string) $row['hash'], $hash));

            if ($same) {
                $hit->execute([$now, $row['id']]);
            } else {
                $bad->execute([$now, $pin, $row['id']]);
                $mismatch[] = $feature;
            }
        }

        if ($mismatch !== []) {
            Log::file('feature', sprintf(
                'mismatch build=%d pin=%s ip=%s ua=%s features=%s',
                $build, $pin, $ip, $ua, implode(',', $mismatch)
            ));
        }

        return [
            'ok'       => $mismatch === [],
            'features' => count($items),
            'new'      => $new,
            'mismatch' => $mismatch,
            'checked'  => true,
        ];
    }

    /** 解析上报串；任何一段格式不对就整体拒掉（不做部分采信） */
    private static function parse(string $raw): array
    {
        $out = [];
        foreach (explode('|', $raw) as $chunk) {
            $chunk = trim($chunk);
            if ($chunk === '') {
                continue;
            }
            $parts = explode(':', $chunk);
            if (count($parts) !== 2) {
                return [];
            }
            $feature = $parts[0];
            if (!preg_match('/^[a-z][a-z0-9_.]{2,40}$/', $feature)) {
                return [];
            }
            $vals = array_map('trim', explode(',', $parts[1]));
            if (count($vals) !== 5) {
                return [];
            }
            $crcs = [];
            foreach ($vals as $v) {
                if (!preg_match('/^\d{1,10}$/', $v)) {
                    return [];
                }
                $crcs[] = (int) $v;
            }
            $out[$feature] = $crcs;
            if (count($out) > self::MAX_FEATURES) {
                return [];
            }
        }
        return $out;
    }

    /** 一条功能哈希：build 参与运算，跨版本不会互相顶掉 */
    public static function hash(int $build, string $feature, array $crcs): string
    {
        return hash('sha256', $build . '|' . $feature . '|' . implode('|', $crcs));
    }

    /** 后台看板用：某个 build 的登记与命中情况 */
    public static function overview(int $build = 0): array
    {
        $pdo = Database::pdo();
        if ($build > 0) {
            $st = $pdo->prepare('SELECT * FROM feature_checks WHERE build = ? ORDER BY feature');
            $st->execute([$build]);
        } else {
            $st = $pdo->query('SELECT * FROM feature_checks ORDER BY build DESC, feature');
        }
        return $st->fetchAll(PDO::FETCH_ASSOC) ?: [];
    }
}
