<?php
declare(strict_types=1);

/** 客户端版本管理：最新版本 / 强制更新 / 下载地址 */
final class VersionService
{
    public static function all(int $limit = 50): array
    {
        $st = Database::pdo()->prepare(
            'SELECT id, platform, version, build, force_update, url, notes, min_version, active, created_at
             FROM app_versions ORDER BY platform ASC, id DESC LIMIT ?'
        );
        $st->bindValue(1, $limit, PDO::PARAM_INT);
        $st->execute();
        return $st->fetchAll();
    }

    public static function save(array $in, string $admin, string $ip): array
    {
        $platform = ($in['platform'] ?? 'ios') === 'android' ? 'android' : 'ios';
        $version  = trim((string) ($in['version'] ?? ''));
        if (!preg_match('/^\d+(\.\d+){0,3}$/', $version)) {
            return ['ok' => false, 'error' => 'bad_version'];
        }
        $build = max(1, (int) ($in['build'] ?? 1));
        $url   = trim((string) ($in['url'] ?? ''));
        if ($url !== '' && !preg_match('#^https?://#i', $url)) {
            return ['ok' => false, 'error' => 'bad_url'];
        }
        $minVersion = trim((string) ($in['min_version'] ?? ''));
        if ($minVersion !== '' && !preg_match('/^\d+(\.\d+){0,3}$/', $minVersion)) {
            return ['ok' => false, 'error' => 'bad_min_version'];
        }
        $notes = mb_substr(trim((string) ($in['notes'] ?? '')), 0, 1000);
        $force = !empty($in['force_update']) ? 1 : 0;
        $active = array_key_exists('active', $in) ? (!empty($in['active']) ? 1 : 0) : 1;

        $pdo = Database::pdo();
        $id = (int) ($in['id'] ?? 0);

        if ($id > 0) {
            $pdo->prepare(
                'UPDATE app_versions SET platform=?, version=?, build=?, force_update=?, url=?, notes=?,
                        min_version=?, active=? WHERE id=?'
            )->execute([$platform, $version, $build, $force, $url, $notes, $minVersion, $active, $id]);
        } else {
            $pdo->prepare(
                'INSERT INTO app_versions(platform, version, build, force_update, url, notes, min_version, active, created_at)
                 VALUES(?,?,?,?,?,?,?,?,?)'
            )->execute([$platform, $version, $build, $force, $url, $notes, $minVersion, $active, time()]);
            $id = (int) $pdo->lastInsertId();
        }

        $pdo->prepare('INSERT INTO audit(ts, admin, action, target, ip, detail) VALUES(?,?,?,?,?,?)')
            ->execute([time(), $admin, 'version.save', $platform . '/' . $version, $ip,
                       'force=' . $force . ' build=' . $build]);

        return ['ok' => true, 'id' => $id];
    }

    public static function remove(int $id, string $admin, string $ip): bool
    {
        $pdo = Database::pdo();
        $st = $pdo->prepare('DELETE FROM app_versions WHERE id = ?');
        $st->execute([$id]);
        $pdo->prepare('INSERT INTO audit(ts, admin, action, target, ip, detail) VALUES(?,?,?,?,?,?)')
            ->execute([time(), $admin, 'version.delete', (string) $id, $ip, '']);
        return $st->rowCount() > 0;
    }

    /** 客户端检测更新 */
    public static function check(string $platform, string $current): array
    {
        $platform = $platform === 'android' ? 'android' : 'ios';
        $st = Database::pdo()->prepare(
            'SELECT version, build, force_update, url, notes, min_version, created_at
             FROM app_versions WHERE platform = ? AND active = 1 ORDER BY id DESC LIMIT 1'
        );
        $st->execute([$platform]);
        $row = $st->fetch();

        if (!$row) {
            return ['ok' => true, 'update_available' => false, 'force_update' => false,
                    'current' => $current, 'latest' => null];
        }

        $updateAvailable = self::compare($current, (string) $row['version']) < 0;
        $force = $updateAvailable && (
            (int) $row['force_update'] === 1
            || ((string) $row['min_version'] !== '' && self::compare($current, (string) $row['min_version']) < 0)
        );

        return [
            'ok'               => true,
            'update_available' => $updateAvailable,
            'force_update'     => $force,
            'current'          => $current,
            'latest'           => [
                'version'    => (string) $row['version'],
                'build'      => (int) $row['build'],
                'url'        => (string) $row['url'],
                'notes'      => (string) $row['notes'],
                'min_version'=> (string) $row['min_version'],
                'force'      => (int) $row['force_update'] === 1,
                'released_at'=> (int) $row['created_at'],
            ],
        ];
    }

    /** 语义化版本比较 */
    public static function compare(string $a, string $b): int
    {
        $pa = array_map('intval', explode('.', $a === '' ? '0' : $a));
        $pb = array_map('intval', explode('.', $b === '' ? '0' : $b));
        $n = max(count($pa), count($pb));
        for ($i = 0; $i < $n; $i++) {
            $x = $pa[$i] ?? 0;
            $y = $pb[$i] ?? 0;
            if ($x !== $y) {
                return $x < $y ? -1 : 1;
            }
        }
        return 0;
    }
}
