#!/usr/bin/env bash
export PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin

# Check if user is root
if [ $(id -u) != "0" ]; then
    echo "Error: You must be root to run this script"
    exit 1
fi

INFO="\e[0;32m[INFO]\e[0m"
ERROR="\e[0;31m[ERROR]\e[0m"

init() {
  echo -e "[Starting time: `date +'%Y-%m-%d %H:%M:%S'`]"
  TIME_START=$(date +%s)
  apt-get update -y
  [[ $? -ne 0 ]] && apt-get update --allow-releaseinfo-change -y
  apt-get autoremove -y
  apt-get -fy install

  for packages in \
    build-essential \
    git autoconf automake libtool m4 make gcc g++ cmake \
    pkg-config \
    rsync \
    clang \
    libc6-dev \
    bzip2 unzip \
    libbz2-dev \
    libjpeg-dev \
    libpng-dev \
    zlib1g \
    zlib1g-dev \
    curl \
    libcurl3-gnutls \
    libcurl4-gnutls-dev \
    libcurl4-openssl-dev \
    libpcre3-dev \
    gzip \
    openssl libssl-dev \
    libexpat1-dev \
    libpcre2-dev \
    libldap2-dev \
    libsasl2-dev \
    libzip-dev \
    libsodium-dev \
    libc-client-dev \
    libkrb5-dev \
    bison re2c \
    libicu-dev \
    libxml2-dev \
    libsqlite3-dev \
    libwebp-dev \
    libonig-dev \
    libxslt1.1 libxslt1-dev \
    rsync clang libboost-all-dev \
    python3 python3-pip \
  ;
  do apt-get --no-install-recommends install -y $packages; done
  install_dependency
  echo -e "[End time: `date +'%Y-%m-%d %H:%M:%S'`]"
  TIME_END=$(date +%s)
  echo -e "${INFO} Successfully done! Command takes $((TIME_END-TIME_START)) seconds."
}

install_dependency() {
  cd ${HOME}
  install_libiconv 2>&1 | tee ${HOME}/init/libiconv.log
  install_mhash 2>&1 | tee ${HOME}/init/mhash.log
  install_libmcrypt 2>&1 | tee ${HOME}/init/libmcrypt.log
  install_mcrypt 2>&1 | tee ${HOME}/init/mcrypt.log
  install_freetype 2>&1 | tee ${HOME}/init/freetype.log
  cd ${HOME}
}

install_libiconv() {
  cd ${HOME}/init
  wget https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.18.tar.gz -O libiconv.tar.gz
  mkdir libiconv && tar zxf libiconv.tar.gz --strip-components=1 --directory=libiconv
  rm libiconv.tar.gz && cd libiconv

  ./configure --enable-static
  make -j `grep 'processor' /proc/cpuinfo | wc -l` && make install

  cd -
}

install_mhash() {
  cd ${HOME}/init
  wget https://downloads.sourceforge.net/project/mhash/mhash/0.9.9.9/mhash-0.9.9.9.tar.bz2 -O mhash.tar.bz2
  mkdir mhash && tar jxf mhash.tar.bz2 --strip-components=1 --directory=mhash
  rm mhash.tar.bz2 && cd mhash

  ./configure
  make -j `grep 'processor' /proc/cpuinfo | wc -l` && make install

  cd -

  ln -sf /usr/local/lib/libmhash.a /usr/lib/libmhash.a
  ln -sf /usr/local/lib/libmhash.la /usr/lib/libmhash.la
  ln -sf /usr/local/lib/libmhash.so /usr/lib/libmhash.so
  ln -sf /usr/local/lib/libmhash.so.2 /usr/lib/libmhash.so.2
  ln -sf /usr/local/lib/libmhash.so.2.0.1 /usr/lib/libmhash.so.2.0.1
  ldconfig
}

install_libmcrypt() {
  cd ${HOME}/init
  wget https://downloads.sourceforge.net/project/mcrypt/Libmcrypt/2.5.8/libmcrypt-2.5.8.tar.gz -O libmcrypt.tar.gz
  mkdir libmcrypt && tar zxf libmcrypt.tar.gz --strip-components=1 --directory=libmcrypt
  rm -rf libmcrypt.tar.gz && cd libmcrypt

  ./configure
  make -j `grep 'processor' /proc/cpuinfo | wc -l` && make install && make install

  /sbin/ldconfig

  cd libltdl/

  ./configure --enable-ltdl-install
  make -j `grep 'processor' /proc/cpuinfo | wc -l` && make install && make install

  ln -sf /usr/local/lib/libmcrypt.la /usr/lib/libmcrypt.la
  ln -sf /usr/local/lib/libmcrypt.so /usr/lib/libmcrypt.so
  ln -sf /usr/local/lib/libmcrypt.so.4 /usr/lib/libmcrypt.so.4
  ln -sf /usr/local/lib/libmcrypt.so.4.4.8 /usr/lib/libmcrypt.so.4.4.8
  ldconfig

  cd -
  cd ..
}

install_mcrypt() {
  cd ${HOME}/init
  wget https://downloads.sourceforge.net/project/mcrypt/MCrypt/2.6.8/mcrypt-2.6.8.tar.gz -O mcrypt.tar.gz

  mkdir mcrypt && tar zxf mcrypt.tar.gz --strip-components=1 --directory=mcrypt
  rm mcrypt.tar.gz && cd mcrypt

  ./configure
  make -j `grep 'processor' /proc/cpuinfo | wc -l` && make install

  cd -
}

install_freetype() {
  cd ${HOME}/init
  wget https://downloads.sourceforge.net/project/freetype/freetype2/2.14.1/freetype-2.14.1.tar.xz -O freetype.tar.xz
  mkdir freetype && tar Jxf freetype.tar.xz --strip-components=1 --directory=freetype
  rm freetype.tar.xz && cd freetype

  ./configure --prefix=/usr/local/freetype --enable-freetype-config
  make -j `grep 'processor' /proc/cpuinfo | wc -l` && make install

  cd -

  \cp /usr/local/freetype/lib/pkgconfig/freetype2.pc /usr/lib/pkgconfig/
  echo "/usr/local/freetype/lib" > /etc/ld.so.conf.d/freetype.conf

  ldconfig
  ln -sf /usr/local/freetype/include/freetype2/* /usr/include/
}

check_kernel() {
  echo "=== 共享内存 ==="
  echo "shmmax: $(cat /proc/sys/kernel/shmmax)"
  echo "shmall: $(cat /proc/sys/kernel/shmall)"

  echo -e "\n=== 网络参数 ==="
  echo "somaxconn: $(cat /proc/sys/net/core/somaxconn)"
  echo "tcp_max_syn_backlog: $(cat /proc/sys/net/ipv4/tcp_max_syn_backlog)"

  echo -e "\n=== 文件描述符 ==="
  echo "file-max: $(cat /proc/sys/fs/file-max)"
}

[ -d "${HOME}/init" ] && mv ${HOME}/init ${HOME}/init-$(date +'%Y-%m-%d')
[ ! -d "${HOME}/init" ] && mkdir ${HOME}/init

cd ${HOME}
[ ! -d "${HOME}/logs" ] && mkdir ${HOME}/logs
init 2>&1 | tee ${HOME}/logs/init.log
check_kernel
