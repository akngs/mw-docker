#!/usr/bin/env bash
# Wait for the DB to come up
echo "Waiting for database to come up at mysql:3306..."
while [ `/bin/nc -w 1 mysql 3306 < /dev/null > /dev/null 2>&1; echo $?` != 0 ]; do
    sleep 1
done

cd /var/www/mediawiki

: ${MEDIAWIKI_CUSTOM:=/custom}
rm -rf LocalSettings.post.php
envsubst '${MEDIAWIKI_PROTOCOL} ${MEDIAWIKI_SITE_SERVER}' < ${MEDIAWIKI_CUSTOM}/LocalSettings.post.php > LocalSettings.post.php
rm -rf statics
ln -s "$MEDIAWIKI_CUSTOM/statics" statics

: ${MEDIAWIKI_SHARED:=/data}
if [ -d "$MEDIAWIKI_SHARED" ]; then
	# Symlink files and directories
	if [ -e "$MEDIAWIKI_SHARED/LocalSettings.php" -a ! -e LocalSettings.php ]; then
		ln -s "$MEDIAWIKI_SHARED/LocalSettings.php" LocalSettings.php
	fi
	if [ -d "$MEDIAWIKI_SHARED/images" -a ! -h images ]; then
		echo >&2 "Found 'images' folder in data volume, creating symbolic link."
		rm -rf images
		ln -s "$MEDIAWIKI_SHARED/images" images
	fi
fi

# SSL
rm -f /etc/nginx/sites-enabled/*
if [ "$MEDIAWIKI_PROTOCOL" == "https" ]; then
    if [ -d "$MEDIAWIKI_SHARED/letsencrypt" ]; then
        cp -r "$MEDIAWIKI_SHARED/letsencrypt" /etc
    else
        certbot certonly --standalone --email "${MEDIAWIKI_ADMIN_EMAIL}" --agree-tos -d "${MEDIAWIKI_SITE_SERVER}" -n
        cp -r /etc/letsencrypt "$MEDIAWIKI_SHARED"
    fi

    if [ ! -f $MEDIAWIKI_SHARED/dhparam.pem ]; then
        openssl dhparam 2048 > $MEDIAWIKI_SHARED/dhparam.pem
    fi
    cp $MEDIAWIKI_SHARED/dhparam.pem /etc/nginx/dhparam.pem

    envsubst '${MEDIAWIKI_SITE_SERVER}' < /etc/nginx/sites-available/mediawiki_https.conf > /etc/nginx/sites-enabled/mediawiki_https
else
    envsubst '${MEDIAWIKI_SITE_SERVER}' < /etc/nginx/sites-available/mediawiki_http.conf > /etc/nginx/sites-enabled/mediawiki_http
fi


# If there is no LocalSettings.php, create one using maintenance/install.php
if [ ! -e "LocalSettings.php" ]; then
    echo >&2 'info: Running maintenance/install.php'
	php maintenance/install.php \
		--confpath /var/www/mediawiki \
		--dbname "mw" \
		--dbschema "mw" \
		--dbport "3306" \
		--dbserver "mysql" \
		--dbtype "mysql" \
		--dbuser "$MEDIAWIKI_DB_USER" \
		--dbpass "$MEDIAWIKI_DB_PASSWORD" \
		--installdbuser "$MEDIAWIKI_DB_USER" \
		--installdbpass "$MEDIAWIKI_DB_PASSWORD" \
		--server "//$MEDIAWIKI_SITE_SERVER" \
		--scriptpath "" \
		--lang "$MEDIAWIKI_SITE_LANG" \
		--pass "$MEDIAWIKI_ADMIN_PASS" \
		"$MEDIAWIKI_SITE_NAME" \
		"$MEDIAWIKI_ADMIN_USER"

    # Delete unused skins
    sed -i "/wfLoadSkin( 'CologneBlue' );/d" LocalSettings.php
    sed -i "/wfLoadSkin( 'Modern' );/d" LocalSettings.php
    sed -i "/wfLoadSkin( 'MonoBook' );/d" LocalSettings.php
    sed -i "/wfLoadSkin( 'Nostalgia' );/d" LocalSettings.php

    # Include additional settings
    echo "require 'LocalSettings.post.php';" >> LocalSettings.php

    if [ -d "$MEDIAWIKI_SHARED" ]; then
        mv LocalSettings.php "$MEDIAWIKI_SHARED/LocalSettings.php"
        ln -s "$MEDIAWIKI_SHARED/LocalSettings.php" LocalSettings.php

        mv images "$MEDIAWIKI_SHARED/images"
        ln -s "$MEDIAWIKI_SHARED/images" images
    fi
    echo >&2 'info: Finished running maintenance/install.php'
fi

# Update
echo >&2 'info: Running maintenance/update.php'
MW_INSTALL_PATH=/var/www/mediawiki php maintenance/update.php --quick --conf ./LocalSettings.php
echo >&2 'info: Finished running maintenance/update.php'

# Run
chown -R www-data: /data/images

echo >&2 'info: Starting PHP FPM and Nginx...'
service php7.2-fpm start
nginx -g "daemon off;"
