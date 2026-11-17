-- 功能库校验：一个 build 的每个功能登记一条哈希（5 条 CRC 参与运算）
-- 首次上报自动登记，之后每次强校验逐条比对
CREATE TABLE IF NOT EXISTS `feature_checks` (
  `id`                INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `build`             INT NOT NULL,
  `feature`           VARCHAR(48) NOT NULL,
  `crc1`              BIGINT UNSIGNED NOT NULL,
  `crc2`              BIGINT UNSIGNED NOT NULL,
  `crc3`              BIGINT UNSIGNED NOT NULL,
  `crc4`              BIGINT UNSIGNED NOT NULL,
  `crc5`              BIGINT UNSIGNED NOT NULL,
  `hash`              CHAR(64) NOT NULL,
  `first_pin`         VARCHAR(16) NOT NULL DEFAULT '',
  `hits`              INT UNSIGNED NOT NULL DEFAULT 0,
  `mismatches`        INT UNSIGNED NOT NULL DEFAULT 0,
  `last_mismatch_at`  DATETIME NULL DEFAULT NULL,
  `last_mismatch_pin` VARCHAR(16) NOT NULL DEFAULT '',
  `created_at`        DATETIME NOT NULL,
  `updated_at`        DATETIME NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_build_feature` (`build`,`feature`),
  KEY `idx_mismatch` (`mismatches`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
