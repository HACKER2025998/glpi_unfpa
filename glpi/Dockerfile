# ================================================
# Image GLPI — Bureau UNFPA Togo
# Base : PHP 8.2 + Apache
# GLPI version : 10.0.15
# Auteur : Adjogble Bernard — Stage IAI-Togo 2026
# ================================================

FROM php:8.2-apache

LABEL maintainer="Adjogble Bernard"
LABEL description="GLPI 10.0.15 - Gestion Parc Informatique UNFPA Togo"
LABEL version="1.0"

ENV GLPI_VERSION=10.0.15
ENV DEBIAN_FRONTEND=noninteractive

# ────────────────────────────
# DÉPENDANCES SYSTÈME
# ────────────────────────────
RUN apt-get update && apt-get install -y \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libzip-dev \
    libldap2-dev \
    libbz2-dev \
    libicu-dev \
    libxml2-dev \
    libcurl4-openssl-dev \
    libonig-dev \
    wget \
    unzip \
    cron \
    && rm -rf /var/lib/apt/lists/*

# ────────────────────────────
# EXTENSIONS PHP REQUISES
# ────────────────────────────
RUN docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg \
    && docker-php-ext-configure ldap \
    && docker-php-ext-install -j$(nproc) \
        gd \
        mysqli \
        pdo \
        pdo_mysql \
        zip \
        bz2 \
        intl \
        xml \
        curl \
        opcache \
        ldap \
        mbstring \
        exif \
        bcmath

# ────────────────────────────
# CONFIGURATION PHP
# ────────────────────────────
COPY php-glpi.ini /usr/local/etc/php/conf.d/glpi.ini

# ────────────────────────────
# CONFIGURATION APACHE
# ────────────────────────────
COPY apache-glpi.conf /etc/apache2/sites-available/glpi.conf

RUN a2enmod rewrite headers \
    && a2dissite 000-default.conf \
    && a2ensite glpi.conf

# ────────────────────────────
# TÉLÉCHARGEMENT ET INSTALLATION GLPI
# ────────────────────────────
RUN wget -q \
    https://github.com/glpi-project/glpi/releases/download/${GLPI_VERSION}/glpi-${GLPI_VERSION}.tgz \
    -O /tmp/glpi.tgz \
    && tar -xzf /tmp/glpi.tgz -C /var/www/html/ \
    && rm /tmp/glpi.tgz \
    && chown -R www-data:www-data /var/www/html/glpi \
    && chmod -R 755 /var/www/html/glpi

# ────────────────────────────
# CRON POUR TÂCHES AUTO GLPI
# ────────────────────────────
RUN echo "*/2 * * * * www-data /usr/local/bin/php \
    /var/www/html/glpi/front/cron.php \
    >> /var/log/glpi_cron.log 2>&1" \
    > /etc/cron.d/glpi-cron \
    && chmod 0644 /etc/cron.d/glpi-cron

# ────────────────────────────
# SCRIPT DE DÉMARRAGE
# ────────────────────────────
RUN printf '#!/bin/bash\nservice cron start\nexec apache2-foreground\n' \
    > /start.sh \
    && chmod +x /start.sh

EXPOSE 80

CMD ["/start.sh"]