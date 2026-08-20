# GLPI — Bureau UNFPA Togo
## Déploiement containerisé Docker

**Projet :** Mise en place d'un gestionnaire de parc informatique  
**Structure :** Bureau Pays UNFPA Togo  
**Stagiaire :** Adjogble Bernard — IAI-Togo 2026  
**Encadreur :** Nestor Konlambigue — ICT/LAN Manager  

---

## Prérequis
- Ubuntu Server 22.04 LTS
- Git installé
- Connexion Internet

## Déploiement en une commande

```bash
git clone https://github.com/HACKER2025998/glpi_unfpa.git
cd glpi_unfpa_
sudo bash deploy.sh
```

Le script installe Docker automatiquement si absent,
demande les paramètres nécessaires et lance tout.

## Commandes utiles

```bash
# État des conteneurs
docker compose ps

# Logs en temps réel
docker compose logs -f

# Sauvegarder la base
docker exec glpi-mariadb mysqldump \
  -u glpiuser -p glpidb > backup_$(date +%Y%m%d).sql

# Arrêter les services
docker compose down

# Redémarrer
docker compose up -d
```

## Structure du projet
- `deploy.sh` — Script de déploiement automatique
- `docker-compose.yml` — Orchestration des conteneurs
- `glpi/` — Configuration Apache, PHP, Dockerfile
- `mariadb/` — Initialisation base de données
- `backups/` — Sauvegardes SQL