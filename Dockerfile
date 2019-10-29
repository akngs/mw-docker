FROM debian:sid-slim
LABEL maintainer="jania902@gmail.com"

# Install debian packages
RUN set -x \
  && apt update \
  && apt install -f -y --no-install-recommends \
    ca-certificates \
    certbot \
    curl \
    git \
    gettext-base \
    graphviz \
    imagemagick \
    mscgen \
    netcat \
    nginx \
    php7.3 \
    php7.3-apcu \
    php7.3-cli \
    php7.3-curl \
    php7.3-gd \
    php7.3-fpm \
    php7.3-intl \
    php7.3-mbstring \
    php7.3-mysql \
    php7.3-xml \
    python3-certbot-nginx \
    unzip \
    zip \
  && rm -rf /var/lib/apt/lists/* \
  && rm -rf /var/cache/apt/archives/* \
  && rm /etc/nginx/sites-enabled/default

# Get mediawiki and extensions
RUN set -x \
  && mkdir -p /usr/src \
  && git clone --depth 1 -b "wmf/1.35.0-wmf.2" https://github.com/wikimedia/mediawiki.git /usr/src/mediawiki \
  && cd /usr/src/mediawiki \
  && git submodule update --init skins \
  && git submodule update --init vendor \
  && cd extensions \
  && git submodule update --init --recursive BetaFeatures \
  && git submodule update --init --recursive CategoryTree \
  && git submodule update --init --recursive Cite \
  && git submodule update --init --recursive Citoid \
  && git submodule update --init --recursive CodeEditor \
  && git submodule update --init --recursive CodeMirror \
  && git submodule update --init --recursive Echo \
  && git submodule update --init --recursive Flow \
  && git submodule update --init --recursive ImageMap \
  && git submodule update --init --recursive Interwiki \
  && git submodule update --init --recursive MobileFrontend \
  && git submodule update --init --recursive PageImages \
  && git submodule update --init --recursive ParserFunctions \
  && git submodule update --init --recursive Popups \
  && git submodule update --init --recursive RevisionSlider \
  && git submodule update --init --recursive Scribunto \
  && git submodule update --init --recursive SyntaxHighlight_GeSHi \
  && git submodule update --init --recursive TemplateData \
  && git submodule update --init --recursive TextExtracts \
  && git submodule update --init --recursive VisualEditor \
  && git submodule update --init --recursive WikiEditor \
  && git clone https://github.com/wikimedia/mediawiki-extensions-GraphViz.git GraphViz \
  && git clone https://github.com/wikimedia/mediawiki-extensions-ReplaceText.git ReplaceText \
  && git clone https://github.com/wikimedia/mediawiki-extensions-Cargo.git Cargo \
  && git clone https://github.com/wikimedia/mediawiki-extensions-PageSchemas.git PageSchemas \
  && git clone https://github.com/wikimedia/mediawiki-extensions-PageForms.git PageForms \
  && git clone --recursive https://github.com/jmnote/SimpleMathJax.git \
  && cd .. \
  && ( find . -type d -name ".git" && find . -name ".gitignore" && find . -name ".gitmodules" ) | xargs rm -rf

# Install and execute composer
COPY composer.local.json /usr/src/mediawiki/composer.local.json
RUN set -x \
  && php -r "readfile('https://getcomposer.org/installer');" | php \
  && mv composer.phar /usr/local/bin/composer \
  && cd /usr/src/mediawiki \
  && composer update -o --no-dev \
  && composer clearcache

# Setup nginx
COPY mediawiki_http.nginx.conf /etc/nginx/sites-available/mediawiki_http.conf
COPY mediawiki_https.nginx.conf /etc/nginx/sites-available/mediawiki_https.conf

RUN set -x \
  && rm -rf /var/www/html \
  && ln -sf /usr/src/mediawiki /var/www/mediawiki

COPY mediawiki.php.ini /etc/php/7.3/fpm/conf.d/mediawiki.ini

# Done
EXPOSE 80 443
COPY entrypoint.sh /entrypoint.sh
CMD ["/entrypoint.sh"]
