#!/bin/bash
# ================================================
# Script de deploiement automatique GLPI
# Bureau UNFPA Togo
# Auteur : Adjogble Bernard — Stage IAI-Togo 2026
# Version 2.0
# ================================================

set -o pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[ATTENTION]${NC} $1"; }
error() { echo -e "${RED}[ERREUR]${NC} $1"; exit 1; }

clear
echo -e "${BLUE}"
echo "+================================================+"
echo "|   GLPI 10.0.16 - Bureau UNFPA Togo             |"
echo "|   Deploiement automatique conteneurise         |"
echo "|   Stage IAI-Togo 2026 - Adjogble Bernard       |"
echo "+================================================+"
echo -e "${NC}"

[ "$EUID" -ne 0 ] && error "Ce script doit etre execute en root (sudo)"

cd "$(dirname "$0")" || error "Impossible d'acceder au repertoire du script"

for f in docker-compose.yml glpi/Dockerfile glpi/apache-glpi.conf \
         glpi/php-glpi.ini glpi/docker-entrypoint.sh mariadb/init.sql; do
    [ -f "$f" ] || error "Fichier manquant : $f"
done
chmod +x glpi/docker-entrypoint.sh
ok "Arborescence du projet complete"

# ────────────────────────────────────────────────
# DOCKER
# ────────────────────────────────────────────────
info "Verification de Docker..."
if ! command -v docker &> /dev/null; then
    warn "Docker non trouve - installation en cours..."
    apt-get update -qq
    apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin \
        || error "Echec de l'installation de Docker"
    ok "Docker installe"
else
    ok "Docker present - $(docker --version)"
fi

docker compose version &>/dev/null || error "Le plugin 'docker compose' est absent"

# ────────────────────────────────────────────────
# REPARTIR DE ZERO
# Un volume rescape d'un essai precedent conserve les
# anciens droits et l'ancienne config : c'est la cause
# numero un des "ca marchait hier".
# ────────────────────────────────────────────────
if docker volume ls -q | grep -q "glpi_"; then
    echo ""
    warn "Des volumes GLPI existent deja (deploiement precedent)."
    read -r -p " Tout effacer et repartir propre ? (o/n) : " RAZ
    if [ "$RAZ" = "o" ] || [ "$RAZ" = "O" ]; then
        info "Suppression des conteneurs et volumes..."
        docker compose down -v --remove-orphans 2>/dev/null
        ok "Environnement remis a zero"
    else
        warn "Conservation des volumes - des erreurs de droits restent possibles"
    fi
fi

# ────────────────────────────────────────────────
# PARAMETRES
# ────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}   Configuration du deploiement         ${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

read -r -p " Utilisateur base de donnees [glpiuser] : " DB_USER
DB_USER=${DB_USER:-glpiuser}

read -r -s -p " Mot de passe base de donnees : " DB_PASS; echo ""
[ -z "$DB_PASS" ] && error "Le mot de passe ne peut pas etre vide"

read -r -s -p " Mot de passe ROOT MariaDB    : " DB_ROOT_PASS; echo ""
[ -z "$DB_ROOT_PASS" ] && error "Le mot de passe root ne peut pas etre vide"

read -r -p " Port d'acces GLPI [80] : " GLPI_PORT
GLPI_PORT=${GLPI_PORT:-80}

if ss -lnt 2>/dev/null | awk '{print $4}' | grep -q ":${GLPI_PORT}$"; then
    warn "Le port ${GLPI_PORT} est deja utilise sur cette machine."
    read -r -p " Continuer quand meme ? (o/n) : " C
    [ "$C" != "o" ] && [ "$C" != "O" ] && error "Deploiement annule"
fi

# L'utilisateur du init.sql est fixe : on l'aligne sur le choix reel
sed -i "s/'glpiuser'@'%'/'${DB_USER}'@'%'/g" mariadb/init.sql

cat > .env << EOF
# Configuration GLPI - Bureau UNFPA Togo
# Genere automatiquement le $(date)
MYSQL_ROOT_PASSWORD=${DB_ROOT_PASS}
MYSQL_DATABASE=glpidb
MYSQL_USER=${DB_USER}
MYSQL_PASSWORD=${DB_PASS}
GLPI_PORT=${GLPI_PORT}
EOF
chmod 600 .env
ok "Fichier .env cree (droits 600)"

# ────────────────────────────────────────────────
# DUMP SQL : on demande AVANT de demarrer GLPI
# ────────────────────────────────────────────────
echo ""
read -r -p " Importer une base de donnees existante ? (o/n) : " IMPORT_DB
SQL_FILE=""
if [ "$IMPORT_DB" = "o" ] || [ "$IMPORT_DB" = "O" ]; then
    read -r -p " Chemin complet du fichier SQL : " SQL_FILE
    [ -f "$SQL_FILE" ] || error "Fichier SQL introuvable : $SQL_FILE"
    ok "Dump trouve : $(du -h "$SQL_FILE" | cut -f1)"
fi

# ────────────────────────────────────────────────
# ETAPE 1 : MARIADB SEULE
# ────────────────────────────────────────────────
echo ""
info "Construction de l'image GLPI (telechargement de GLPI et du plugin)..."
docker compose build || error "Echec du build - relancez avec : docker compose build"
ok "Image construite"

info "Demarrage de MariaDB..."
docker compose up -d mariadb || error "Echec du demarrage de MariaDB"

info "Attente que MariaDB soit prete..."
for i in $(seq 1 60); do
    ETAT=$(docker inspect -f '{{.State.Health.Status}}' glpi-mariadb 2>/dev/null)
    [ "$ETAT" = "healthy" ] && break
    [ "$i" = "60" ] && error "MariaDB n'est pas prete - docker compose logs mariadb"
    sleep 2
done
ok "MariaDB operationnelle"

# ────────────────────────────────────────────────
# ETAPE 2 : FUSEAUX HORAIRES
# ────────────────────────────────────────────────
info "Chargement des fuseaux horaires dans MariaDB..."
docker exec glpi-mariadb bash -c \
    "mysql_tzinfo_to_sql /usr/share/zoneinfo 2>/dev/null | mysql -u root -p'${DB_ROOT_PASS}' mysql" \
    2>/dev/null && ok "Fuseaux horaires charges" \
    || warn "Fuseaux horaires non charges - avertissement mineur dans GLPI"

# ────────────────────────────────────────────────
# ETAPE 3 : IMPORT DU DUMP, AVANT GLPI
# ────────────────────────────────────────────────
if [ -n "$SQL_FILE" ]; then
    info "Import de la base de donnees..."
    if docker exec -i glpi-mariadb mysql \
            --default-character-set=utf8mb4 \
            -u root -p"${DB_ROOT_PASS}" glpidb < "$SQL_FILE"; then
        NB=$(docker exec glpi-mariadb mysql -u root -p"${DB_ROOT_PASS}" -N -B -e \
             "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='glpidb';" 2>/dev/null)
        ok "Base importee - ${NB} tables"
        [ "${NB:-0}" -lt 100 ] && warn "Nombre de tables faible pour GLPI - verifiez le dump"
    else
        error "Echec de l'import - verifiez le fichier SQL"
    fi
fi

# ────────────────────────────────────────────────
# ETAPE 4 : GLPI
# ────────────────────────────────────────────────
info "Demarrage de GLPI..."
docker compose up -d glpi || error "Echec du demarrage de GLPI"

info "Initialisation (droits, config, plugins)..."
sleep 10

RUN=$(docker inspect -f '{{.State.Running}}' glpi-app 2>/dev/null)
[ "$RUN" = "true" ] || { docker compose logs --tail 40 glpi; error "Conteneur GLPI arrete"; }
ok "Conteneur GLPI actif"

# ────────────────────────────────────────────────
# ETAPE 5 : VERIFICATION HTTP REELLE
# C'est ce controle qui manquait : le script annoncait
# "deploiement reussi" sans jamais tester l'URL.
# ────────────────────────────────────────────────
info "Verification de la reponse HTTP..."
CODE=""
for i in $(seq 1 40); do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -L --max-time 5 \
           "http://127.0.0.1:${GLPI_PORT}/" 2>/dev/null)
    case "$CODE" in
        200|302|303) break ;;
    esac
    [ $((i % 5)) -eq 0 ] && info "  toujours en attente d'Apache (${i}/40)..."
    sleep 3
done

SERVER_IP=$(hostname -I | awk '{print $1}')

if [ "$CODE" = "200" ] || [ "$CODE" = "302" ] || [ "$CODE" = "303" ]; then
    ok "GLPI repond correctement (HTTP ${CODE})"
else
    echo ""
    warn "GLPI ne repond pas comme attendu (HTTP ${CODE:-aucune reponse})"
    echo "--- 30 dernieres lignes du journal Apache ---"
    docker exec glpi-app tail -n 30 /var/log/apache2/glpi_error.log 2>/dev/null
    echo "--- journal du conteneur ---"
    docker compose logs --tail 30 glpi
    error "Diagnostic ci-dessus"
fi

# Warnings PHP visibles dans la page = regression
if curl -s -L "http://127.0.0.1:${GLPI_PORT}/" | grep -qi "<b>Warning</b>\|headers already sent"; then
    warn "Des avertissements PHP s'affichent dans la page."
    warn "Verifiez que php-glpi.ini contient bien : display_errors = Off"
else
    ok "Aucun avertissement PHP dans la page"
fi

# ────────────────────────────────────────────────
# RESUME
# ────────────────────────────────────────────────
if [ -n "$SQL_FILE" ]; then
    ACCES="Base importee : vos identifiants GLPI habituels"
else
    ACCES="Premiere installation : identifiants par defaut glpi / glpi"
fi

echo ""
echo -e "${GREEN}"
echo "+================================================+"
echo "|              DEPLOIEMENT REUSSI                |"
echo "+================================================+"
echo -e "${NC}"
echo "  URL       : http://${SERVER_IP}:${GLPI_PORT}/"
echo "  Acces     : ${ACCES}"
echo ""
echo "  Commandes utiles :"
echo "    docker compose ps            etat des conteneurs"
echo "    docker compose logs -f glpi  journaux en direct"
echo "    docker compose restart glpi  redemarrer GLPI"
echo "    docker compose down          arreter"
echo "    docker compose down -v       arreter et tout effacer"
echo ""
if [ -z "$SQL_FILE" ]; then
    echo -e "${YELLOW}  Apres l'installation web, pensez a supprimer :${NC}"
    echo "    docker exec glpi-app rm -rf /var/www/html/glpi/install"
    echo ""
fi
