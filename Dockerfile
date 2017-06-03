FROM goodrainapps/alpine:3.6

# china repositories mirror
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories

# docker-entrypoint.sh dependencies
RUN apk add --no-cache bash sed curl tar netcat-openbsd tzdata && \
    mkdir /run/nginx/ -pv && \
    echo "Asia/Shanghai" >  /etc/timezone && \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    apk del --no-cache tzdata


RUN apk add --no-cache apache2 php7 php7-mcrypt php7-mysqli php7-mysqlnd php7-opcache php7-openssl php7-pdo \
php7-pcntl php7-exif php7-gd php7-gettext php7-iconv php7-imap php7-apache2 php7-json php7-mbstring \
php7-ctype php7-curl php7-imagick  php7-zip php7-zlib


WORKDIR /var/www/html
VOLUME /var/www/html

ENV WORDPRESS_VERSION 4.7.4

RUN set -ex; \
  mkdir -pv /usr/src/; \
	curl -o wordpress.zip -fSL "https://cn.wordpress.org/wordpress-${WORDPRESS_VERSION}-zh_CN.zip"; \
	unzip wordpress.zip -d /usr/src/; \
	rm wordpress.zip; \
	chown -R apache:apache /usr/src/wordpress

COPY docker-entrypoint.sh /
COPY etc /etc
RUN mkdir /run/apache2/ && \
    chown apache.apache /run/apache2/ && \
    chmod +x /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["apache2"]
