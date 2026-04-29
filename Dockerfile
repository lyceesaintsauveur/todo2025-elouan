# -- Stage 1 : builder ------------------------------------------
FROM php:8.3-cli-alpine AS builder

# Installation des dépendances système nécessaires à la compilation
RUN apk add --no-cache \
    libpng-dev libjpeg-turbo-dev libwebp-dev \
    libxml2-dev oniguruma-dev icu-dev \
    && docker-php-ext-install pdo_mysql mbstring xml gd fileinfo intl

# Composer installé depuis son image officielle (propre)
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Node.js pour Vite
RUN apk add --no-cache nodejs npm

WORKDIR /app

# On copie TOUT le code source (artisan doit être présent pour
# les scripts post-install de Composer)
COPY . .

# Installation des dépendances PHP sans les packages de dev
RUN composer install --no-dev --no-interaction \
    --optimize-autoloader --prefer-dist

# Build des assets front (Vite génère public/build/manifest.json)
RUN npm ci && npm run build

# -- Stage 2 : runtime ------------------------------------------
FROM php:8.3-fpm-alpine AS runtime

# Extensions compilées : installation des headers, compilation, suppression des headers,
# réinstallation des libs runtime nécessaires à l'exécution de gd
RUN apk add --no-cache \
    libpng-dev libjpeg-turbo-dev libwebp-dev \
    libxml2-dev oniguruma-dev \
    && docker-php-ext-install pdo_mysql mbstring xml gd fileinfo opcache \
    && apk del libpng-dev libjpeg-turbo-dev libwebp-dev \
              libxml2-dev oniguruma-dev \
    && apk add --no-cache libpng libjpeg-turbo libwebp \
    && rm -rf /var/cache/apk/*

# OPcache : accélère PHP en gardant le bytecode en mémoire
RUN { \
    echo 'opcache.enable=1'; \
    echo 'opcache.memory_consumption=256'; \
    echo 'opcache.validate_timestamps=0'; \
} > /usr/local/etc/php/conf.d/opcache.ini

# Sécurité : l'application tourne sous un utilisateur non-root
RUN addgroup -g 1000 -S www && adduser -u 1000 -S www -G www

WORKDIR /var/www/html

# Copie du code compilé depuis le stage builder
COPY --from=builder --chown=www:www /app .

# Création des dossiers d'écriture Laravel
RUN mkdir -p storage/framework/{sessions,views,cache} storage/logs \
             bootstrap/cache \
    && chown -R www:www storage bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache

USER www
EXPOSE 9000
CMD ["php-fpm"]