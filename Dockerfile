FROM php:7.1-fpm-alpine

# docker-entrypoint.sh dependencies
RUN apk add --no-cache bash sed curl nginx netcat-openbsd tzdata && \
    mkdir /run/nginx/ -pv && \
    echo "Asia/Shanghai" >  /etc/timezone && \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    apk del --no-cache tzdata


RUN set -ex; \
	\
	apk add --no-cache --virtual .build-deps \
		libjpeg-turbo-dev \
		libpng-dev \
	; \
	\
	docker-php-ext-configure gd --with-png-dir=/usr --with-jpeg-dir=/usr; \
	docker-php-ext-install gd mysqli opcache; \
	\
	runDeps="$( \
		scanelf --needed --nobanner --recursive \
			/usr/local/lib/php/extensions \
			| awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
			| sort -u \
			| xargs -r apk info --installed \
			| sort -u \
	)"; \
	apk add --virtual .wordpress-phpexts-rundeps $runDeps; \
	apk del .build-deps

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.interned_strings_buffer=8'; \
		echo 'opcache.max_accelerated_files=4000'; \
		echo 'opcache.revalidate_freq=2'; \
		echo 'opcache.fast_shutdown=1'; \
		echo 'opcache.enable_cli=1'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini

VOLUME /var/www/html

ENV WORDPRESS_VERSION 4.7.4
ENV WORDPRESS_SHA1 fbe0ee1d9010265be200fe50b86f341587187302

RUN set -ex; \
	curl -o wordpress.zip -fSL "https://cn.wordpress.org/wordpress-${WORDPRESS_VERSION}-zh_CN.zip"; \
	echo "$WORDPRESS_SHA1 *wordpress.zip" | sha1sum -c -; \
	unzip wordpress.zip -d /usr/src/; \
	rm wordpress.zip; \
	chown -R www-data:www-data /usr/src/wordpress

COPY docker-entrypoint.sh /usr/local/bin/

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["php-fpm"]
