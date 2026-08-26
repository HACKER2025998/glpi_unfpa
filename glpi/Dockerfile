# ================================================
# Image GLPI — Bureau UNFPA Togo
# Base : PHP 8.2 + Apache
# GLPI : 10.0.16   |   Data Injection : 2.13.5
# Auteur : Adjogble Bernard — Stage IAI-Togo 2026
# ================================================

FROM php:8.2-apache

LABEL maintainer="Adjogble Bernard"
LABEL description="GLPI 10.0.16 - Gestion Parc Informatique UNFPA Togo"
LABEL version="2.0"

ENV GLPI_VERSION=10.0.16
ENV DATAINJECTION_VERSION=2.13.5
ENV DEBIAN_FRONTEND=noninteractive

# ────────────────────────────
# DEPENDANCES SYSTEME
# libsodium-dev ajoute : GLPI 10 verifie l'extension sodium
# bzip2 ajoute : necessaire pour decompresser les plugins .tar.bz2
# ────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
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
        libsodium-dev \
        wget \
        ca-certificates \
        unzip \
        bzip2 \
        cron \
        default-mysql-client \
    && rm -rf /var/lib/apt/lists/*

# ────────────────────────────
# EXTENSIONS PHP
# ────────────────────────────
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-configure ldap \
    && docker-php-ext-install -j"$(nproc)" \
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
        bcmath \
        sodium

# ────────────────────────────
# CONFIGURATION PHP ET APACHE
# ────────────────────────────
COPY php-glpi.ini    /usr/local/etc/php/conf.d/glpi.ini
COPY apache-glpi.conf /etc/apache2/sites-available/glpi.conf

RUN a2enmod rewrite headers expires \
    && a2dissite 000-default.conf \
    && a2ensite glpi.conf

# ────────────────────────────
# GLPI
# ────────────────────────────
RUN wget -q --show-progress --progress=bar:force \
        "https://github.com/glpi-project/glpi/releases/download/${GLPI_VERSION}/glpi-${GLPI_VERSION}.tgz" \
        -O /tmp/glpi.tgz \
    && tar -xzf /tmp/glpi.tgz -C /var/www/html/ \
    && rm /tmp/glpi.tgz \
    && test -f /var/www/html/glpi/public/index.php \
    && mkdir -p /var/www/html/glpi/marketplace

# ────────────────────────────
# PLUGIN DATA INJECTION
# Sans ses fichiers, un dump SQL qui le reference provoque
# "Unable to load plugin dataInjection" sur toutes les pages.
# ────────────────────────────
RUN wget -q \
        "https://github.com/pluginsGLPI/datainjection/releases/download/${DATAINJECTION_VERSION}/glpi-datainjection-${DATAINJECTION_VERSION}.tar.bz2" \
        -O /tmp/datainjection.tar.bz2 \
    && tar -xjf /tmp/datainjection.tar.bz2 -C /var/www/html/glpi/plugins/ \
    && rm /tmp/datainjection.tar.bz2 \
    && test -d /var/www/html/glpi/plugins/datainjection

# ────────────────────────────
# DROITS DE BASE (recalcules au demarrage par l'entrypoint)
# ────────────────────────────
# Un seul passage recursif. L'ancienne version utilisait
# "find -exec chmod {} \;" : un processus par fichier, soit plus de
# 40 000 appels, d'ou les ~400 s de build sur cette etape.
RUN chown -R www-data:www-data /var/www/html/glpi \
    && chmod -R u=rwX,g=rX,o=rX /var/www/html/glpi

# ────────────────────────────
# CRON GLPI
# ────────────────────────────
RUN echo "*/2 * * * * www-data /usr/local/bin/php /var/www/html/glpi/front/cron.php >> /var/log/glpi_cron.log 2>&1" \
        > /etc/cron.d/glpi-cron \
    && chmod 0644 /etc/cron.d/glpi-cron

# ────────────────────────────
# ENTRYPOINT
# ────────────────────────────
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD php -r 'exit(@file_get_contents("http://127.0.0.1/") === false ? 1 : 0);'

EXPOSE 80

CMD ["/usr/local/bin/docker-entrypoint.sh"]
