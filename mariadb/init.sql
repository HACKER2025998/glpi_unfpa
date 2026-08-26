-- ================================================
-- Initialisation MariaDB — GLPI UNFPA Togo


-- GLPI exige utf8mb4 ; on le garantit explicitement.
ALTER DATABASE glpidb
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

-- Acces en lecture aux tables de fuseaux horaires : sans ce droit,
-- GLPI signale "Les donnees de fuseaux horaires ne sont pas remplies".
GRANT SELECT ON mysql.time_zone_name TO 'glpiuser'@'%';

FLUSH PRIVILEGES;
