FROM debian:sid
LABEL maintainer="jania902@gmail.com"

RUN set -x; \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        apache2 \
        ca-certificates \
        certbot \
        curl \
        git \
        imagemagick \
        libapache2-mod-php7.1 \
        netcat \
        php7.1-mysql \
        php7.1-cli \
        php7.1-gd \
        php7.1-curl \
        php7.1-intl \
        php7.1-mbstring \
        php7.1-xml \
        unzip \
        zip \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /var/cache/apt/archives/* \
    && a2dismod auth_basic -f \
    && a2dismod autoindex -f \
    && a2dismod status \
    && a2enmod rewrite \
    && a2enmod proxy \
    && a2enmod proxy_http \
    && rm /var/www/html/index.html \
    && php -r "readfile('https://getcomposer.org/installer');" | php \
    && mv composer.phar /usr/local/bin/composer

RUN set -x; \
    mkdir -p /usr/src \
    && git clone --depth 1 -b "wmf/1.31.0-wmf.20" https://github.com/wikimedia/mediawiki.git /usr/src/mediawiki \
    && cd /usr/src/mediawiki \
    && git submodule update --init skins \
    && git submodule update --init vendor \
    && cd extensions \
    && git submodule update --init --recursive BetaFeatures \
    && git submodule update --init --recursive CategoryTree \
    && git submodule update --init --recursive Cite \
    && git submodule update --init --recursive Citoid \
    && git submodule update --init --recursive CodeEditor \
    && git submodule update --init --recursive Echo \
    && git submodule update --init --recursive Flow \
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
    && git clone https://github.com/wikimedia/mediawiki-extensions-ReplaceText.git ReplaceText \
    && git clone --recursive https://github.com/jmnote/SimpleMathJax.git \
    && cd .. \
    && ( find . -type d -name ".git" && find . -name ".gitignore" && find . -name ".gitmodules" ) | xargs rm -rf

COPY composer.local.json /usr/src/mediawiki/composer.local.json
RUN set -x; \
    cd /usr/src/mediawiki \
    && composer update -o --no-dev \
    && composer clearcache

COPY mediawiki.php.ini /usr/local/etc/php/conf.d/mediawiki.ini
COPY apache2.conf /etc/apache2/apache2.conf
COPY mediawiki.apache2.conf /etc/apache2/sites-enabled/mediawiki.conf
COPY entrypoint.sh /entrypoint.sh

EXPOSE 80 443
CMD ["/entrypoint.sh"]
