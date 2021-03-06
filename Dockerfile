FROM debian:sid-slim
LABEL maintainer="jania902@gmail.com"

# Install debian packages
RUN set -x \
  && apt-get update \
  && apt-get install -f -y --no-install-recommends \
  ca-certificates \
  certbot \
  curl \
  git \
  gettext-base \
  graphviz \
  imagemagick \
  mscgen \
  netcat-traditional \
  nginx \
  php7.4 \
  php7.4-apcu \
  php7.4-cli \
  php7.4-curl \
  php7.4-gd \
  php7.4-fpm \
  php7.4-intl \
  php7.4-mbstring \
  php7.4-mysql \
  php7.4-xml \
  php-pear \
  python3-certbot-nginx \
  sendmail \
  software-properties-common \
  unzip \
  zip \
  && pear install mail Net_SMTP Auth_SASL mail_mime \
  && rm -rf /var/lib/apt/lists/* \
  && rm -rf /var/cache/apt/archives/* \
  && rm /etc/nginx/sites-enabled/default

# Get mediawiki and extensions
RUN set -x \
  && mkdir -p /usr/src \
  && git clone --depth 1 -b "wmf/1.36.0-wmf.22" https://github.com/wikimedia/mediawiki.git /usr/src/mediawiki \
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
  && git submodule update --init --recursive Thanks \
  && git submodule update --init --recursive TextExtracts \
  && git submodule update --init --recursive VisualEditor \
  && git submodule update --init --recursive WikiEditor \
  && git clone https://github.com/wikimedia/mediawiki-extensions-GraphViz.git GraphViz \
  && git clone https://github.com/wikimedia/mediawiki-extensions-ReplaceText.git ReplaceText \
  && git clone https://github.com/wikimedia/mediawiki-extensions-Cargo.git Cargo \
  && git clone https://github.com/wikimedia/mediawiki-extensions-PageSchemas.git PageSchemas \
  && git clone https://github.com/wikimedia/mediawiki-extensions-PageForms.git PageForms \
  && git clone https://github.com/wikimedia/mediawiki-extensions-YouTube.git YouTube \
  && git clone --recursive https://github.com/jmnote/SimpleMathJax.git \
  && git clone https://github.com/hangya/mw-ses-mailer.git \
  && mv mw-ses-mailer/SesMailer ./SesMailer \
  && cd .. \
  && ( find . -type d -name ".git" && find . -name ".gitignore" && find . -name ".gitmodules" ) | xargs rm -rf

# Install and execute composer
COPY composer.local.json /usr/src/mediawiki/composer.local.json
RUN set -x \
  && cd /usr/src/mediawiki \
  && curl https://getcomposer.org/composer-1.phar > composer.phar \
  && mv composer.phar /usr/local/bin/composer \
  && chmod 755 /usr/local/bin/composer \
  && composer update -o --no-dev \
  && composer clearcache

# Setup nginx
COPY mediawiki_http.nginx.conf /etc/nginx/sites-available/mediawiki_http.conf
COPY mediawiki_https.nginx.conf /etc/nginx/sites-available/mediawiki_https.conf

RUN set -x \
  && rm -rf /var/www/html \
  && ln -sf /usr/src/mediawiki /var/www/mediawiki

COPY mediawiki.php.ini /etc/php/7.4/fpm/conf.d/mediawiki.ini

# Done
EXPOSE 80 443
COPY entrypoint.sh /entrypoint.sh
CMD ["/entrypoint.sh"]
