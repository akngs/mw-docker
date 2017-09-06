#!/usr/bin/env bash
set -e

: ${MEDIAWIKI_SITE_NAME:=MediaWiki}
: ${MEDIAWIKI_SITE_LANG:=en}
: ${MEDIAWIKI_ADMIN_USER:=admin}
: ${MEDIAWIKI_ADMIN_PASS:=rosebud}
: ${MEDIAWIKI_DB_TYPE:=mysql}
: ${MEDIAWIKI_DB_SCHEMA:=mediawiki}
: ${MEDIAWIKI_ENABLE_SSL:=false}

if [ -z "$MEDIAWIKI_DB_HOST" ]; then
	if [ -n "$MYSQL_PORT_3306_TCP_ADDR" ]; then
		MEDIAWIKI_DB_HOST=$MYSQL_PORT_3306_TCP_ADDR
	elif [ -n "$POSTGRES_PORT_5432_TCP_ADDR" ]; then
		MEDIAWIKI_DB_TYPE=postgres
		MEDIAWIKI_DB_HOST=$POSTGRES_PORT_5432_TCP_ADDR
	elif [ -n "$DB_PORT_3306_TCP_ADDR" ]; then
		MEDIAWIKI_DB_HOST=$DB_PORT_3306_TCP_ADDR
	elif [ -n "$DB_PORT_5432_TCP_ADDR" ]; then
		MEDIAWIKI_DB_TYPE=postgres
		MEDIAWIKI_DB_HOST=$DB_PORT_5432_TCP_ADDR
	else
		echo >&2 'error: missing MEDIAWIKI_DB_HOST environment variable'
		echo >&2 '	Did you forget to --link your database?'
		exit 1
	fi
fi

if [ -z "$MEDIAWIKI_RESTBASE_URL" ]; then
	export MEDIAWIKI_RESTBASE_URL=restbase-is-not-specified
fi

if [ -z "$MEDIAWIKI_DB_USER" ]; then
	if [ "$MEDIAWIKI_DB_TYPE" = "mysql" ]; then
		echo >&2 'info: missing MEDIAWIKI_DB_USER environment variable, defaulting to "root"'
		MEDIAWIKI_DB_USER=root
	elif [ "$MEDIAWIKI_DB_TYPE" = "postgres" ]; then
		echo >&2 'info: missing MEDIAWIKI_DB_USER environment variable, defaulting to "postgres"'
		MEDIAWIKI_DB_USER=postgres
	else
		echo >&2 'error: missing required MEDIAWIKI_DB_USER environment variable'
		exit 1
	fi
fi

if [ -z "$MEDIAWIKI_DB_PASSWORD" ]; then
	if [ -n "$MYSQL_ENV_MYSQL_ROOT_PASSWORD" ]; then
		MEDIAWIKI_DB_PASSWORD=$MYSQL_ENV_MYSQL_ROOT_PASSWORD
	elif [ -n "$POSTGRES_ENV_POSTGRES_PASSWORD" ]; then
		MEDIAWIKI_DB_PASSWORD=$POSTGRES_ENV_POSTGRES_PASSWORD
	elif [ -n "$DB_ENV_MYSQL_ROOT_PASSWORD" ]; then
		MEDIAWIKI_DB_PASSWORD=$DB_ENV_MYSQL_ROOT_PASSWORD
	elif [ -n "$DB_ENV_POSTGRES_PASSWORD" ]; then
		MEDIAWIKI_DB_PASSWORD=$DB_ENV_POSTGRES_PASSWORD
	else
		echo >&2 'error: missing required MEDIAWIKI_DB_PASSWORD environment variable'
		echo >&2 '	Did you forget to -e MEDIAWIKI_DB_PASSWORD=... ?'
		echo >&2
		echo >&2 '	(Also of interest might be MEDIAWIKI_DB_USER and MEDIAWIKI_DB_NAME)'
		exit 1
	fi
fi

: ${MEDIAWIKI_DB_NAME:=mediawiki}

if [ -z "$MEDIAWIKI_DB_PORT" ]; then
	if [ -n "$MYSQL_PORT_3306_TCP_PORT" ]; then
		MEDIAWIKI_DB_PORT=$MYSQL_PORT_3306_TCP_PORT
	elif [ -n "$POSTGRES_PORT_5432_TCP_PORT" ]; then
		MEDIAWIKI_DB_PORT=$POSTGRES_PORT_5432_TCP_PORT
	elif [ -n "$DB_PORT_3306_TCP_PORT" ]; then
		MEDIAWIKI_DB_PORT=$DB_PORT_3306_TCP_PORT
	elif [ -n "$DB_PORT_5432_TCP_PORT" ]; then
		MEDIAWIKI_DB_PORT=$DB_PORT_5432_TCP_PORT
	elif [ "$MEDIAWIKI_DB_TYPE" = "mysql" ]; then
		MEDIAWIKI_DB_PORT="3306"
	elif [ "$MEDIAWIKI_DB_TYPE" = "postgres" ]; then
		MEDIAWIKI_DB_PORT="5432"
	fi
fi

# Wait for the DB to come up
echo "Waiting for database to come up at $MEDIAWIKI_DB_HOST:$MEDIAWIKI_DB_PORT..."
while [ `/bin/nc -w 1 $MEDIAWIKI_DB_HOST $MEDIAWIKI_DB_PORT < /dev/null > /dev/null; echo $?` != 0 ]; do
    sleep 1
done

export MEDIAWIKI_DB_TYPE MEDIAWIKI_DB_HOST MEDIAWIKI_DB_USER MEDIAWIKI_DB_PASSWORD MEDIAWIKI_DB_NAME

TERM=dumb php -- <<'EOPHP'
<?php
// database might not exist, so let's try creating it (just to be safe)
if ($_ENV['MEDIAWIKI_DB_TYPE'] == 'mysql') {
	$mysql = new mysqli($_ENV['MEDIAWIKI_DB_HOST'], $_ENV['MEDIAWIKI_DB_USER'], $_ENV['MEDIAWIKI_DB_PASSWORD'], '', (int) $_ENV['MEDIAWIKI_DB_PORT']);
	if ($mysql->connect_error) {
		file_put_contents('php://stderr', 'MySQL Connection Error: (' . $mysql->connect_errno . ') ' . $mysql->connect_error . "\n");
		exit(1);
	}
	if (!$mysql->query('CREATE DATABASE IF NOT EXISTS `' . $mysql->real_escape_string($_ENV['MEDIAWIKI_DB_NAME']) . '`')) {
		file_put_contents('php://stderr', 'MySQL "CREATE DATABASE" Error: ' . $mysql->error . "\n");
		$mysql->close();
		exit(1);
	}
	$mysql->close();
}
EOPHP

rm -rf /var/www/html
ln -sf /usr/src/mediawiki /var/www/html
cd /var/www/html

: ${MEDIAWIKI_CUSTOM:=/custom}
rm -rf LocalSettings.post.php
ln -s "$MEDIAWIKI_CUSTOM/LocalSettings.post.php" LocalSettings.post.php
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

if [ $MEDIAWIKI_ENABLE_SSL = true ]; then
    if [ -d "$MEDIAWIKI_SHARED/letsencrypt" ]; then
        cp -r "$MEDIAWIKI_SHARED/letsencrypt" /etc
    else
        certbot certonly --standalone --email "${MEDIAWIKI_ADMIN_EMAIL}" --agree-tos -d "${MEDIAWIKI_SITE_SERVER}" -n
        cp -r /etc/letsencrypt "$MEDIAWIKI_SHARED"
    fi
    a2enmod ssl
fi

# If there is no LocalSettings.php, create one using maintenance/install.php
if [ ! -e "LocalSettings.php" ]; then
	php maintenance/install.php \
		--confpath /var/www/html \
		--dbname "$MEDIAWIKI_DB_NAME" \
		--dbschema "$MEDIAWIKI_DB_SCHEMA" \
		--dbport "$MEDIAWIKI_DB_PORT" \
		--dbserver "$MEDIAWIKI_DB_HOST" \
		--dbtype "$MEDIAWIKI_DB_TYPE" \
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
fi

# Update
echo >&2 'info: Running maintenance/update.php';
MW_INSTALL_PATH=/var/www/html php maintenance/update.php --quick --conf ./LocalSettings.php

# Fix file ownership and permissions
chown -R www-data: /usr/src/mediawiki
chown -R www-data: /data/images

# Done
apachectl -e info -D FOREGROUND