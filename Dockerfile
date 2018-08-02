FROM nginx:1.15.2-alpine
MAINTAINER Hacklab  sysadmin@hacklab.com.br

ENV DEBUG=false RAP_DEBUG="info" 
ARG VERSION_RANCHER_GEN="artifacts/master"

# Install Modsecurity
RUN apk add --no-cache --virtual .build-deps \
        gcc \
        libc-dev \
        make \
        openssl-dev \
        pcre-dev \
        zlib-dev \
        linux-headers \
        curl \
        gnupg \
        libxslt-dev \
        gd-dev \
        perl-dev \
    && apk add --no-cache --virtual .libmodsecurity-deps \
        pcre-dev \
        libxml2-dev \
        git \
        libtool \
        automake \
        autoconf \
        g++ \
        flex \
        bison \
       yajl-dev \
    && apk add --no-cache \
	yajl \
        libstdc++ \
    && mkdir -p /tmp/ModSecurity

WORKDIR /tmp/ModSecurity


RUN echo "Installing ModSec Library" && \
    git clone -b v3/master --single-branch https://github.com/SpiderLabs/ModSecurity . && \
    git submodule init && \
    git submodule update && \
    ./build.sh && \
    ./configure \ 
      --with-http_geoip_module=dynamic \
      --with-http_v2_module \
      --with-threads \
      --with-stream \
      --with-stream_ssl_module \
      --with-stream_ssl_preread_module \
      --with-stream_realip_module \
      --with-stream_geoip_module=dynamic \
      --with-http_slice_module \
      --with-mail \
      --with-mail_ssl_module \
      --with-http_ssl_module && \ 
    make && make install

WORKDIR /tmp

RUN echo 'Installing ModSec - Nginx connector' && \
    git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git && \
    wget http://nginx.org/download/nginx-$NGINX_VERSION.tar.gz && \
    tar zxvf nginx-$NGINX_VERSION.tar.gz

WORKDIR /tmp/nginx-$NGINX_VERSION


RUN ./configure --with-compat --add-dynamic-module=../ModSecurity-nginx && \
    make modules && \
    cp objs/ngx_http_modsecurity_module.so /etc/nginx/modules

RUN echo "Begin installing ModSec OWASP Rules" && \
    git clone -b v3.0/master https://github.com/SpiderLabs/owasp-modsecurity-crs && \
    mv owasp-modsecurity-crs/ /usr/local/

COPY nginx/nginx.conf /etc/nginx/
COPY nginx/modsec/ /etc/nginx/modsec/
COPY owasp/ /usr/local/owasp-modsecurity-crs/

RUN chown -R nginx:nginx /usr/share/nginx /etc/nginx

RUN apk del .build-deps && \
    apk del .libmodsecurity-deps && \
    rm -rf /tmp/ModSecurity && \
    rm -rf /tmp/ModSecurity-nginx && \
    rm -rf /tmp/nginx-$NGINX_VERSION.tar.gz && \
    rm -rf /tmp/nginx-$NGINX_VERSION && \
    echo "ModSecurty Installed" 

# Intall Rancher Active Proxy 

RUN apk add --no-cache nano ca-certificates unzip wget certbot bash openssl

# Install Forego & Rancher-Gen-RAP
ADD https://github.com/jwilder/forego/releases/download/v0.16.1/forego /usr/local/bin/forego

RUN wget "https://gitlab.com/adi90x/rancher-gen-rap/builds/$VERSION_RANCHER_GEN/download?job=compile-go" -O /tmp/rancher-gen-rap.zip \
	&& unzip /tmp/rancher-gen-rap.zip -d /usr/local/bin \
	&& chmod +x /usr/local/bin/rancher-gen \
	&& chmod u+x /usr/local/bin/forego \
	&& rm -f /tmp/rancher-gen-rap.zip
	
#Copying all templates and script	
COPY /app/ /app/
WORKDIR /app/

# Seting up repertories & Configure Nginx and apply fix for very long server names
RUN chmod +x /app/letsencrypt.sh \
    && mkdir -p /etc/nginx/certs /etc/nginx/vhost.d /etc/nginx/conf.d /usr/share/nginx/html /etc/letsencrypt \
    && echo "daemon off;" >> /etc/nginx/nginx.conf \
    && chmod u+x /app/remove 

ENTRYPOINT ["/bin/bash", "/app/entrypoint.sh" ]
CMD ["forego", "start", "-r"]
