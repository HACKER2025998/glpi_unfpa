#!/bin/bash
# ================================================
# Entrypoint GLPI — Bureau UNFPA Togo
# S'execute a CHAQUE demarrage du conteneur, donc
# APRES le montage des volumes : c'est le seul
# endroit ou corriger les droits a un effet reel.
# ================================================
set -e

GLPI_DIR=/var/www/html/glpi
CONF="${GLPI_DIR}/config/config_db.php"

log() { echo "[entrypoint] $*"; }

# ────────────────────────────────────────────────
# 1. ATTENDRE QUE MARIADB REPONDE
# ────────────────────────────────────────────────
log "Attente de MariaDB (${MARIADB_HOST}:${MARIADB_PORT})..."
for i in $(seq 1 60); do
    if php -r '
        $c=@mysqli_connect(getenv("MARIADB_HOST"),getenv("MARIADB_USER"),
                           getenv("MARIADB_PASSWORD"),getenv("MARIADB_DATABASE"),
                           (int)getenv("MARIADB_PORT"));
        exit($c ? 0 : 1);' 2>/dev/null; then
        log "MariaDB repond."
        break
    fi
    [ "$i" = "60" ] && { log "ERREUR : MariaDB injoignable apres 60s"; exit 1; }
    sleep 1
done

# ────────────────────────────────────────────────
# 2. DROITS — apres montage des volumes
# ────────────────────────────────────────────────
log "Application des droits..."
mkdir -p "${GLPI_DIR}/files" "${GLPI_DIR}/config" \
         "${GLPI_DIR}/plugins" "${GLPI_DIR}/marketplace"

chown -R www-data:www-data "${GLPI_DIR}"
find "${GLPI_DIR}" -type d -exec chmod 755 {} \;
find "${GLPI_DIR}" -type f -exec chmod 644 {} \;

# Ces repertoires doivent etre inscriptibles par Apache
chmod -R u+rwX,g+rwX "${GLPI_DIR}/files" "${GLPI_DIR}/config" \
                     "${GLPI_DIR}/plugins" "${GLPI_DIR}/marketplace"

touch /var/log/glpi_php_errors.log /var/log/glpi_cron.log
chown www-data:www-data /var/log/glpi_php_errors.log /var/log/glpi_cron.log

# ────────────────────────────────────────────────
# 3. CONFIG_DB.PHP — genere si la base est deja peuplee
#    (cas d'un dump SQL importe avant le demarrage)
# ────────────────────────────────────────────────
if [ ! -f "$CONF" ]; then
    DEJA=$(php -r '
        $c=@mysqli_connect(getenv("MARIADB_HOST"),getenv("MARIADB_USER"),
                           getenv("MARIADB_PASSWORD"),getenv("MARIADB_DATABASE"),
                           (int)getenv("MARIADB_PORT"));
        if(!$c){echo "0";exit;}
        $r=mysqli_query($c,"SHOW TABLES LIKE \"glpi_configs\"");
        echo ($r && mysqli_num_rows($r)>0) ? "1" : "0";' 2>/dev/null || echo 0)

    if [ "$DEJA" = "1" ]; then
        log "Base deja peuplee : generation de config_db.php (installeur contourne)."
        PWD_ENC=$(php -r 'echo rawurlencode(getenv("MARIADB_PASSWORD"));')
        cat > "$CONF" <<PHPEOF
<?php
class DB extends DBmysql {
   public \$dbhost     = '${MARIADB_HOST}:${MARIADB_PORT}';
   public \$dbuser     = '${MARIADB_USER}';
   public \$dbpassword = '${PWD_ENC}';
   public \$dbdefault  = '${MARIADB_DATABASE}';
   public \$use_timezones      = true;
   public \$allow_myisam       = false;
   public \$allow_datetime     = false;
   public \$allow_signed_keys  = false;
}
PHPEOF
        chown www-data:www-data "$CONF"
        chmod 640 "$CONF"

        # Cle de chiffrement : obligatoire, regeneree si absente
        if [ ! -f "${GLPI_DIR}/config/glpicrypt.key" ]; then
            log "Generation de la cle de chiffrement..."
            php -r '
              $k = random_bytes(32);
              file_put_contents("'"${GLPI_DIR}"'/config/glpicrypt.key", $k);'
            chown www-data:www-data "${GLPI_DIR}/config/glpicrypt.key"
            chmod 600 "${GLPI_DIR}/config/glpicrypt.key"
        fi
    else
        log "Base vierge : l'installeur web sera propose."
    fi
else
    log "config_db.php present : demarrage direct."
fi

# ────────────────────────────────────────────────
# 4. NEUTRALISER LES PLUGINS SANS FICHIERS
#    (cause des "Unable to load plugin ...")
# ────────────────────────────────────────────────
if [ -f "$CONF" ]; then
    log "Verification de la coherence des plugins..."
    php -r '
      $c=@mysqli_connect(getenv("MARIADB_HOST"),getenv("MARIADB_USER"),
                         getenv("MARIADB_PASSWORD"),getenv("MARIADB_DATABASE"),
                         (int)getenv("MARIADB_PORT"));
      if(!$c) exit(0);
      $r=@mysqli_query($c,"SELECT id,directory FROM glpi_plugins");
      if(!$r) exit(0);
      while($p=mysqli_fetch_assoc($r)){
        $d="/var/www/html/glpi/plugins/".$p["directory"];
        $m="/var/www/html/glpi/marketplace/".$p["directory"];
        if(!is_dir($d) && !is_dir($m)){
          mysqli_query($c,"UPDATE glpi_plugins SET state=0 WHERE id=".(int)$p["id"]);
          fwrite(STDERR,"[entrypoint] plugin sans fichiers desactive : ".$p["directory"]."\n");
        }
      }' 2>&1 || true
fi

# ────────────────────────────────────────────────
# 5. VERROUILLER L'INSTALLEUR SI DEJA INSTALLE
# ────────────────────────────────────────────────
if [ -f "$CONF" ] && [ -d "${GLPI_DIR}/install" ]; then
    touch "${GLPI_DIR}/install/.lock" 2>/dev/null || true
fi

# ────────────────────────────────────────────────
# 6. DEMARRAGE
# ────────────────────────────────────────────────
log "Demarrage de cron..."
service cron start >/dev/null 2>&1 || true

log "Test de la configuration Apache..."
apache2ctl configtest

log "GLPI pret. Demarrage d'Apache."
exec apache2-foreground
