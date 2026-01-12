#!/usr/bin/env bash
export PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin

# Check if user is root
if [ $(id -u) != "0" ]; then
  echo "Error: You must be root to run this script"
  exit 1
fi

INFO="\e[0;32m[INFO]\e[0m"
ERROR="\e[0;31m[ERROR]\e[0m"

determine_path() {
  PHP_Parent_PATH="$(dirname $0)/.."

  if [[ "$PHP_Parent_PATH" != /* ]]; then
    echo -e "${ERROR} ${PHP_Parent_PATH} 不是绝对路径，尝试获取绝对路径"
    PHP_Parent_PATH="$(pwd)/$(dirname $0)/.."
  fi

  if [[ "$PHP_Parent_PATH" == /* ]] && [[ -n "$PHP_Parent_PATH" ]]; then
    echo -e "${INFO} ${PHP_Parent_PATH}"
  else
    echo -e "${ERROR} 获取绝对路径失败"
    exit 1
  fi
}

init() {
  if [[ `getconf WORD_BIT` = '32' && `getconf LONG_BIT` = '64' ]] ; then
    Is_64bit='y'
    ARCH='x86_64'
  else
    Is_64bit='n'
    ARCH='i386'
  fi

  if uname -m | grep -Eqi "arm|aarch64"; then
    Is_ARM='y'
    if uname -m | grep -Eqi "armv7|armv6"; then
      ARCH='armhf'
    elif uname -m | grep -Eqi "aarch64"; then
      ARCH='aarch64'
    else
      ARCH='arm'
    fi
  fi

  MemTotal=$(awk '/MemTotal/ {printf( "%d\n", $2 / 1024 )}' /proc/meminfo)
}

ext_postgresql() {
  apt-get --no-install-recommends install -y libpq-dev
  with_pgsql="--with-pgsql --with-pdo-pgsql"
}

make_php() {
  cd ${HOME}/php

  [ -z $1 ] && {
    echo -e "${ERROR} Unavailable PHP Version."
    exit 1
  }

  wget https://www.php.net/distributions/php-$1.tar.gz -O php.tar.gz
  mkdir php && tar zxf php.tar.gz --strip-components=1 --directory=php
  rm php.tar.gz && cd php

  if pkg-config --modversion icu-i18n | grep -Eqi '^6[89]|7[0-9]'; then
    export CXX="g++ -DTRUE=1 -DFALSE=0"
    export  CC="gcc -DTRUE=1 -DFALSE=0"
  fi

  if [ -s /usr/local/apache/bin/httpd ] && [ -s /usr/local/apache/conf/httpd.conf ] && [ -s /etc/init.d/httpd ]; then
    php_mode='mod_php'
    with_php_mode='--with-apxs2=/usr/local/apache/bin/apxs'
  else
    php_mode='php-fpm'
    with_php_mode='--enable-fpm --with-fpm-user=www --with-fpm-group=www'
  fi

  ext_postgresql

  ./configure \
    --prefix=${PHP_Path} \
    --with-config-file-path=${PHP_Path}/etc \
    --with-config-file-scan-dir=${PHP_Path}/conf.d \
    ${with_php_mode} \
    --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd \
    ${with_pgsql} \
    --with-iconv=/usr/local \
    --with-freetype=/usr/local/freetype \
    --with-jpeg \
    --with-zlib \
    --enable-xml \
    --disable-rpath \
    --enable-bcmath \
    --enable-shmop \
    --enable-sysvsem \
    --with-curl \
    --enable-mbregex \
    --enable-mbstring \
    --enable-intl \
    --enable-pcntl \
    --enable-ftp \
    --enable-gd \
    --with-openssl \
    --with-mhash \
    --enable-sockets \
    --with-zip \
    --enable-soap \
    --with-gettext \
    --enable-opcache \
    --with-xsl \
    --with-pear \
    --with-webp \
    --enable-exif \
    --with-ldap --with-ldap-sasl \
    --with-bz2 \
    --with-sodium

    make ZEND_EXTRA_LIBS='-liconv' -j `grep 'processor' /proc/cpuinfo | wc -l`
    if [ $? -ne 0 ]; then
      make ZEND_EXTRA_LIBS='-liconv'
    fi
    make install

  # 安装 libs
  # /usr/local/apache/build/libtool --finish /root/php/php-$1/libs

  # 路径
  ln -sf ${PHP_Path}/bin/php /usr/bin/php
  ln -sf ${PHP_Path}/bin/phpize /usr/bin/phpize
  ln -sf ${PHP_Path}/bin/pear /usr/bin/pear
  ln -sf ${PHP_Path}/bin/pecl /usr/bin/pecl
}

php_fpm() {
  ln -sf ${PHP_Path}/sbin/php-fpm /usr/bin/php-fpm
  echo "Creating new php-fpm configure file..."
  cat >${PHP_Path}/etc/php-fpm.conf<<EOF
[global]
pid = ${PHP_Path}/var/run/php-fpm.pid
error_log = ${PHP_Path}/var/log/php-fpm.log
log_level = notice

[www]
listen = /tmp/php-cgi.sock
listen.backlog = -1
listen.allowed_clients = 127.0.0.1
listen.owner = www
listen.group = www
listen.mode = 0666
user = www
group = www
pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 6
pm.max_requests = 1024
pm.process_idle_timeout = 10s
request_terminate_timeout = 100
request_slowlog_timeout = 0
slowlog = var/log/slow.log
EOF

  echo "Copy php-fpm init.d file..."
  \cp sapi/fpm/init.d.php-fpm /etc/init.d/php-fpm
  chown root:root /etc/init.d/php-fpm && chmod +x /etc/init.d/php-fpm
  cat "${PHP_Parent_PATH}/service/php-fpm.service" > /etc/systemd/system/php-fpm.service
}

conf_php() {
  echo "Copy new php configure file..."
  rm -f ${PHP_Path}/conf.d/*
  mkdir -p ${PHP_Path}/{etc,conf.d}
  \cp php.ini-production ${PHP_Path}/etc/php.ini

  if [ $php_mode = 'php-fpm' ]; then
    php_fpm
  fi
  # php extensions
  echo "Modify php.ini......"
  sed -i 's/post_max_size =.*/post_max_size = 50M/g' ${PHP_Path}/etc/php.ini
  sed -i 's/upload_max_filesize =.*/upload_max_filesize = 50M/g' ${PHP_Path}/etc/php.ini
  sed -i 's/;date.timezone =.*/date.timezone = PRC/g' ${PHP_Path}/etc/php.ini
  sed -i 's/short_open_tag =.*/short_open_tag = On/g' ${PHP_Path}/etc/php.ini
  sed -i 's/;cgi.fix_pathinfo=.*/cgi.fix_pathinfo=0/g' ${PHP_Path}/etc/php.ini
  sed -i 's/max_execution_time =.*/max_execution_time = 300/g' ${PHP_Path}/etc/php.ini
  sed -i 's/disable_functions =.*/disable_functions = passthru,exec,system,chroot,chgrp,chown,shell_exec,proc_open,proc_get_status,popen,ini_alter,ini_restore,dl,openlog,syslog,readlink,symlink,popepassthru,stream_socket_server/g' ${PHP_Path}/etc/php.ini

  pear config-set php_ini ${PHP_Path}/etc/php.ini
  pecl config-set php_ini ${PHP_Path}/etc/php.ini
}

install_composer() {
  wget --progress=dot:giga --prefer-family=IPv4 --no-check-certificate -T 120 -t3 https://getcomposer.org/download/latest-stable/composer.phar -O /usr/local/bin/composer
  chmod +x /usr/local/bin/composer
}

install_pie() {
  curl -fL --output /tmp/pie.phar https://github.com/php/pie/releases/latest/download/pie.phar && \
  # gh attestation verify --owner php /tmp/pie.phar && \
  mv /tmp/pie.phar /usr/local/bin/pie && \
  chmod +x /usr/local/bin/pie
  if [ -f /usr/local/bin/pie ]; then
    # allow the following functions and then pie can install successfully : proc_open, proc_get_status
    sed -i 's/disable_functions =.*/disable_functions = passthru,exec,system,chroot,chgrp,chown,shell_exec,popen,ini_alter,ini_restore,dl,openlog,syslog,readlink,symlink,popepassthru,stream_socket_server/g' ${PHP_Path}/etc/php.ini
    echo "Usage: pie install <vendor>/<package>"
  fi
}

Opt_PHP() {
  if [[ ${MemTotal} -gt 1024 && ${MemTotal} -le 2048 ]]; then
    sed -i "s#pm.max_children.*#pm.max_children = 20#" ${PHP_Path}/etc/php-fpm.conf
    sed -i "s#pm.start_servers.*#pm.start_servers = 10#" ${PHP_Path}/etc/php-fpm.conf
    sed -i "s#pm.min_spare_servers.*#pm.min_spare_servers = 10#" ${PHP_Path}/etc/php-fpm.conf
    sed -i "s#pm.max_spare_servers.*#pm.max_spare_servers = 20#" ${PHP_Path}/etc/php-fpm.conf
  elif [[ ${MemTotal} -gt 2048 && ${MemTotal} -le 4096 ]]; then
    sed -i "s#pm.max_children.*#pm.max_children = 40#" ${PHP_Path}/etc/php-fpm.conf
    sed -i "s#pm.start_servers.*#pm.start_servers = 20#" ${PHP_Path}/etc/php-fpm.conf
    sed -i "s#pm.min_spare_servers.*#pm.min_spare_servers = 20#" ${PHP_Path}/etc/php-fpm.conf
    sed -i "s#pm.max_spare_servers.*#pm.max_spare_servers = 40#" ${PHP_Path}/etc/php-fpm.conf
  elif [[ ${MemTotal} -gt 4096 && ${MemTotal} -le 8192 ]]; then
    sed -i "s#pm.max_children.*#pm.max_children = 60#" ${PHP_Path}/etc/php-fpm.conf
    sed -i "s#pm.start_servers.*#pm.start_servers = 30#" ${PHP_Path}/etc/php-fpm.conf
    sed -i "s#pm.min_spare_servers.*#pm.min_spare_servers = 30#" ${PHP_Path}/etc/php-fpm.conf
    sed -i "s#pm.max_spare_servers.*#pm.max_spare_servers = 60#" ${PHP_Path}/etc/php-fpm.conf
  elif [[ ${MemTotal} -gt 8192 ]]; then
    sed -i "s#pm.max_children.*#pm.max_children = 80#" ${PHP_Path}/etc/php-fpm.conf
    sed -i "s#pm.start_servers.*#pm.start_servers = 40#" ${PHP_Path}/etc/php-fpm.conf
    sed -i "s#pm.min_spare_servers.*#pm.min_spare_servers = 40#" ${PHP_Path}/etc/php-fpm.conf
    sed -i "s#pm.max_spare_servers.*#pm.max_spare_servers = 80#" ${PHP_Path}/etc/php-fpm.conf
  fi
}

start_php() {
  if [ $php_mode = 'mod_php' ]; then
    echo "Restarting Apache......"
    /etc/init.d/httpd restart
  else
    echo "Start php-fpm......"
    systemctl daemon-reload && systemctl start php-fpm
  fi
}

ext_imap() {
  apt-get install -y libc-client-dev libkrb5-dev

  cd ${HOME}/php
  echo "IMAP cannot be installed by PIE..."
  wget https://pecl.php.net/get/imap-1.0.3.tgz -O imap.tar.gz
  mkdir php/ext/imap && tar zxf imap.tar.gz --strip-components=1 --directory=php/ext/imap && rm imap.tar.gz
  cd php/ext/imap
  ${PHP_Path}/bin/phpize
  ./configure --with-php-config=${PHP_Path}/bin/php-config --with-imap --with-imap-ssl --with-kerberos
  make && make install

  cd -
  cat >${PHP_Path}/conf.d/009-imap.ini<<EOF
extension = "imap.so"
EOF
}

ext_opcache() {
  cat >${PHP_Path}/conf.d/004-opcache.ini<<EOF
[Zend Opcache]
opcache.memory_consumption=128
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=4000
opcache.revalidate_freq=60
opcache.fast_shutdown=1
opcache.enable_cli=1

opcache.jit = 1255
opcache.jit_buffer_size = 64M
EOF

  echo "Copy Opcache Control Panel..."
  \cp "${PHP_Parent_PATH}/php/ocp.php" ${Web_Dir}/ocp.php
  chown www:www ${Web_Dir}/ocp.php && chmod +x ${Web_Dir}/ocp.php
}

install_php_tools() {
  echo "Create PHP Info Tool..."
  cat >${Web_Dir}/phpinfo.php<<EOF
<?php
phpinfo();
?>
EOF
  chown www:www ${Web_Dir}/phpinfo.php && chmod +x ${Web_Dir}/phpinfo.php
  echo "Copy PHP Prober..."
  \cp "${PHP_Parent_PATH}/php/p.php" ${Web_Dir}/p.php
  chown www:www ${Web_Dir}/p.php && chmod +x ${Web_Dir}/p.php
}

php_info(){
  Cur_PHP_Version="`${PHP_Path}/bin/php-config --version`"
  zend_ext_dir="`${PHP_Path}/bin/php-config --extension-dir`/"
  PHP_Short_Ver="$(echo ${Cur_PHP_Version} | cut -d. -f1-2)"
}

check_php() {
  if [[ -s ${PHP_Path}/bin/php && -s ${PHP_Path}/etc/php.ini ]]; then
    if [ $php_mode = 'mod_php' ] && [ -s /usr/local/apache/modules/libphp.so ]; then
      echo -e "${INFO} PHP: OK, running in mode: ${php_mode}."
      return 0
    fi
    if [ $php_mode = 'php-fpm' ] && [ -s ${PHP_Path}/sbin/php-fpm ]; then
      echo -e "${INFO} PHP: OK, running in mode: ${php_mode}."
      return 0
    fi
  fi
  echo -e "${ERROR} PHP install failed."
}

install() {
  echo -e "[Starting time: `date +'%Y-%m-%d %H:%M:%S'`]"
  determine_path
  TIME_START=$(date +%s)
  init
  make_php $PHP_Stable_Version
  conf_php
  install_composer
  install_pie
  Opt_PHP
  php_info
  ext_imap
  ext_opcache
  install_php_tools
  start_php
  check_php
  echo -e "[End time: `date +'%Y-%m-%d %H:%M:%S'`]"
  TIME_END=$(date +%s)
  echo -e "${INFO} Successfully done! Command takes $((TIME_END-TIME_START)) seconds."
}

PHP_Path="/usr/local/php"
Web_Dir="/home/wwwroot/default"
PHP_Stable_Version="8.5.1"

echo -n "Please enter the website directory (default ${Web_Dir}): "
read Web_Dir

[ -z ${Web_Dir} ] && Web_Dir="/home/wwwroot/default"
[ ! -d ${Web_Dir} ] && mkdir -p ${Web_Dir}

[ -d "${HOME}/php" ] && mv ${HOME}/php ${HOME}/php-$(date +'%Y-%m-%d')
[ ! -d "${HOME}/php" ] && mkdir ${HOME}/php
[ ! -d "${HOME}/logs" ] && mkdir ${HOME}/logs

install 2>&1 | tee ${HOME}/logs/php.log
