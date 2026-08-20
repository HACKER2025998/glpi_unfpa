#!/bin/bash

# ================================================
# Script de déploiement automatique GLPI
# Bureau UNFPA Togo
# Auteur : Adjogble Bernard — Stage IAI-Togo 2026
# ================================================

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Fonctions d'affichage
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[ATTENTION]${NC} $1"; }
error() { echo -e "${RED}[ERREUR]${NC} $1"; exit 1; }

# ────────────────────────────────────────────────
# BANNIÈRE
# ────────────────────────────────────────────────
clear
echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════╗"
echo "║   GLPI — Bureau UNFPA Togo                    ║"
echo "║   Script de déploiement automatique           ║"
echo "║   Stage IAI-Togo 2026 — Adjogble Bernard      ║"
echo "╚════════════════════════════════════════════════╝"
echo -e "${NC}"

# ────────────────────────────────────────────────
# VÉRIFICATION ROOT
# ────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    error "Ce script doit être exécuté en tant que root (sudo)"
fi

# ────────────────────────────────────────────────
# VÉRIFICATION ET INSTALLATION DOCKER
# ────────────────────────────────────────────────
info "Vérification de Docker..."
if ! command -v docker &> /dev/null; then
    warn "Docker non trouvé — installation en cours..."
    apt-get update -qq
    apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) \
        signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -qq
    apt-get install -y docker-ce docker-ce-cli \
        containerd.io docker-compose-plugin
    ok "Docker installé avec succès"
else
    ok "Docker déjà installé — $(docker --version)"
fi

# ────────────────────────────────────────────────
# PARAMÈTRES INTERACTIFS
# ────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}════════════════════════════════════════${NC}"
echo -e "${YELLOW}   Configuration de votre déploiement   ${NC}"
echo -e "${YELLOW}════════════════════════════════════════${NC}"
echo ""

read -p "📌 Nom d'utilisateur base de données [glpiuser] : " DB_USER
DB_USER=${DB_USER:-glpiuser}

read -s -p "🔒 Mot de passe base de données : " DB_PASS
echo ""
if [ -z "$DB_PASS" ]; then
    error "Le mot de passe ne peut pas être vide"
fi

read -s -p "🔒 Mot de passe ROOT MariaDB : " DB_ROOT_PASS
echo ""
if [ -z "$DB_ROOT_PASS" ]; then
    error "Le mot de passe root ne peut pas être vide"
fi

read -p "🌐 Port d'accès GLPI [80] : " GLPI_PORT
GLPI_PORT=${GLPI_PORT:-80}

# ────────────────────────────────────────────────
# GÉNÉRATION DU FICHIER .ENV
# ────────────────────────────────────────────────
info "Génération du fichier de configuration..."

cat > .env << EOF
# Configuration GLPI — Bureau UNFPA Togo
# Généré automatiquement le $(date)
MYSQL_ROOT_PASSWORD=${DB_ROOT_PASS}
MYSQL_DATABASE=glpidb
MYSQL_USER=${DB_USER}
MYSQL_PASSWORD=${DB_PASS}
GLPI_PORT=${GLPI_PORT}
EOF

ok "Fichier .env créé"

# ────────────────────────────────────────────────
# LANCEMENT DES CONTENEURS
# ────────────────────────────────────────────────
echo ""
info "Lancement des conteneurs Docker..."
docker compose up -d --build

if [ $? -ne 0 ]; then
    error "Échec du lancement des conteneurs — vérifiez les logs : docker compose logs"
fi

# ────────────────────────────────────────────────
# VÉRIFICATION DES SERVICES
# ────────────────────────────────────────────────
info "Vérification des services..."
sleep 15

GLPI_STATUS=$(docker inspect -f '{{.State.Running}}' glpi-app 2>/dev/null)
DB_STATUS=$(docker inspect -f '{{.State.Running}}' glpi-mariadb 2>/dev/null)

if [ "$GLPI_STATUS" = "true" ]; then
    ok "Conteneur GLPI : actif"
else
    error "Conteneur GLPI non démarré — docker compose logs glpi"
fi

if [ "$DB_STATUS" = "true" ]; then
    ok "Conteneur MariaDB : actif"
else
    error "Conteneur MariaDB non démarré — docker compose logs mariadb"
fi

# ────────────────────────────────────────────────
# IMPORT BASE DE DONNÉES EXISTANTE
# ────────────────────────────────────────────────
echo ""
read -p "📦 Voulez-vous importer une base de données existante ? (o/n) : " IMPORT_DB

if [ "$IMPORT_DB" = "o" ] || [ "$IMPORT_DB" = "O" ]; then
    read -p "📂 Chemin complet du fichier SQL : " SQL_FILE
    if [ -f "$SQL_FILE" ]; then
        info "Import de la base de données en cours..."
        docker exec -i glpi-mariadb mysql \
            -u "$DB_USER" \
            -p"$DB_PASS" \
            glpidb < "$SQL_FILE"
        if [ $? -eq 0 ]; then
            ok "Base de données importée avec succès"
        else
            error "Échec de l'import — vérifiez le fichier SQL"
        fi
    else
        error "Fichier SQL non trouvé : $SQL_FILE"
    fi
else
    info "GLPI démarrera avec une base vierge"
fi

# ────────────────────────────────────────────────
# RÉSUMÉ FINAL
# ────────────────────────────────────────────────
SERVER_IP=$(hostname -I | awk '{print $1}')
echo ""
echo -e "${GREEN}"
echo "╔════════════════════════════════════════════════╗"
echo "║         DÉPLOIEMENT RÉUSSI !                  ║"
echo "╠════════════════════════════════════════════════╣"
echo "║  GLPI accessible sur :                        ║"
echo "║  http://${SERVER_IP}:${GLPI_PORT}/glpi        ║"
echo "║                                               ║"
echo "║  Commandes utiles :                           ║"
echo "║  docker compose ps      → état des conteneurs ║"
echo "║  docker compose logs -f → logs en temps réel  ║"
echo "║  docker compose down    → arrêter les services║"
echo "╚════════════════════════════════════════════════╝"
echo -e "${NC}"