#!/bin/bash

[ $DEBUG ]  && set -x

if [ ! -n "${!MYSQL_*}" ]; then
  echo "Please link the MySQL application!"
	exit 1
else
  MYSQL_HOST=${MYSQL_HOST:-127.0.0.1}
  MYSQL_PORT=${MYSQL_PORT:-3306}
  MYSQL_USER=${MYSQL_USER:-root}
  MYSQL_PASS=${MYSQL_PASS:-`head -c1m /dev/urandom | sha1sum | cut -d' ' -f1`}

	DB_HOST=${MYSQL_HOST}:${MYSQL_PORT}
	WORDPRESS_DB_NAME=${WORDPRESS_DB_NAME:-wordpress}
	WORDPRESS_TABLE_PREFIX=${WORDPRESS_TABLE_PREFIX:-wp_}
	WORDPRESS_DEBUG=${WORDPRESS_DEBUG:-1}
  MAXWAIT=${MAXWAIT:-30}

fi

# waitting mysql is ready
wait=0
while [ $wait -lt $MAXWAIT ]
do
    nc -w 1 -v $MYSQL_HOST $MYSQL_PORT > /dev/null 2>&1
    if [ $? -eq 0 ];then
      echo "MySQL is ready."
      break
    fi

    ((wait++))
    echo "Waiting MySQL service $wait seconds"
    sleep 1
done

if [ "$wait" == "$MAXWAIT" ]; then
 echo >&2 'Can not connect to the MySQL database,Wordpress failed to start.'
 exit 1
fi

if [[ "$1" == apache2* ]] || [ "$1" == php-fpm ]; then
	if ! [ -e index.php -a -e wp-includes/version.php ]; then
		echo >&2 "WordPress not found in $PWD - copying now..."
		if [ "$(ls -A)" ]; then
			echo >&2 "WARNING: $PWD is not empty - press Ctrl+C now if this is an error!"
			( set -x; ls -A; sleep 10 )
		else
		  tar cf - --one-file-system -C /usr/src/wordpress . | tar xf -
		  echo >&2 "Complete! WordPress has been successfully copied to $PWD"
    fi

		if [ ! -e .htaccess ]; then
			# NOTE: The "Indexes" option is disabled in the php:apache base image
			cat > .htaccess <<-'EOF'
				# BEGIN WordPress
				<IfModule mod_rewrite.c>
				RewriteEngine On
				RewriteBase /
				RewriteRule ^index\.php$ - [L]
				RewriteCond %{REQUEST_FILENAME} !-f
				RewriteCond %{REQUEST_FILENAME} !-d
				RewriteRule . /index.php [L]
				</IfModule>
				# END WordPress
			EOF
			chown apache:apache .htaccess
		fi
	fi

	# allow any of these "Authentication Unique Keys and Salts." to be specified via
	# environment variables with a "WORDPRESS_" prefix (ie, "WORDPRESS_AUTH_KEY")
	uniqueEnvs=(
		AUTH_KEY
		SECURE_AUTH_KEY
		LOGGED_IN_KEY
		NONCE_KEY
		AUTH_SALT
		SECURE_AUTH_SALT
		LOGGED_IN_SALT
		NONCE_SALT
	)

		if [ ! -e wp-config.php ]; then
			awk '/^\/\*.*stop editing.*\*\/$/ && c == 0 { c = 1; system("cat") } { print }' wp-config-sample.php > wp-config.php
			cat >> wp-config.php <<'EOPHP'
// If we're behind a proxy server and using HTTPS, we need to alert Wordpress of that fact
// see also http://codex.wordpress.org/Administration_Over_SSL#Using_a_Reverse_Proxy
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
	$_SERVER['HTTPS'] = 'on';
}

EOPHP
			chown apache.apache wp-config.php
		fi

    sed -ri -e 's/\r$//' wp-config*

		# see http://stackoverflow.com/a/2705678/433558
		sed_escape_lhs() {
			echo "$@" | sed -e 's/[]\/$*.^|[]/\\&/g'
		}
		sed_escape_rhs() {
			echo "$@" | sed -e 's/[\/&]/\\&/g'
		}
		php_escape() {
			php -r 'var_export(('$2') $argv[1]);' -- "$1"
		}
		set_config() {
			key="$1"
			value="$2"
			var_type="${3:-string}"
			start="(['\"])$(sed_escape_lhs "$key")\2\s*,"
			end="\);"
			if [ "${key:0:1}" = '$' ]; then
				start="^(\s*)$(sed_escape_lhs "$key")\s*="
				end=";"
			fi
			sed -ri -e "s/($start\s*).*($end)$/\1$(sed_escape_rhs "$(php_escape "$value" "$var_type")")\3/" wp-config.php
		}

		set_config 'DB_HOST' "$MYSQL_HOST:$MYSQL_PORT"
		set_config 'DB_USER' "$MYSQL_USER"
		set_config 'DB_PASSWORD' "$MYSQL_PASS"
		set_config 'DB_NAME' "$WORDPRESS_DB_NAME"
		set_config '$table_prefix' "$WORDPRESS_TABLE_PREFIX"
		set_config 'WP_DEBUG' 1 boolean

		for unique in "${uniqueEnvs[@]}"; do
			uniqVar="WORDPRESS_$unique"
			if [ -n "${!uniqVar}" ]; then
				set_config "$unique" "${!uniqVar}"
			else
				# if not specified, let's generate a random value
				currentVal="$(sed -rn -e "s/define\((([\'\"])$unique\2\s*,\s*)(['\"])(.*)\3\);/\4/p" wp-config.php)"
				if [ "$currentVal" = 'put your unique phrase here' ]; then
					set_config "$unique" "$(head -c1m /dev/urandom | sha1sum | cut -d' ' -f1)"
				fi
			fi
		done



sleep ${PAUSE:-0}

TERM=dumb php -- "${DB_HOST}" "$MYSQL_USER" "$MYSQL_PASS" "$WORDPRESS_DB_NAME" <<'EOPHP'
<?php
// database might not exist, so let's try creating it (just to be safe)

$stderr = fopen('php://stderr', 'w');

list($host, $port) = explode(':', $argv[1], 2);

$maxTries = 20;
do {
	$mysql = new mysqli($host, $argv[2], $argv[3], '', (int)$port);
	if ($mysql->connect_error) {
		fwrite($stderr, "\n" . 'MySQL Connection Error: (' . $mysql->connect_errno . ') ' . $mysql->connect_error . "\n");
		--$maxTries;
		if ($maxTries <= 0) {
      fwrite($stderr, "\n" . "Can not connect to the MySQL database, please check whether MySQL is ready.");
			exit(1);
		}
		sleep(3);
	}
} while ($mysql->connect_error);

if (!$mysql->query('CREATE DATABASE IF NOT EXISTS `' . $mysql->real_escape_string($argv[4]) . '`')) {
	fwrite($stderr, "\n" . 'MySQL "CREATE DATABASE" Error: ' . $mysql->error . "\n");
	$mysql->close();
	exit(1);
}

$mysql->close();
EOPHP
	fi


exec httpd -k start -DFOREGROUND
