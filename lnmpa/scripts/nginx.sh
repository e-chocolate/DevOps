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
  Nginx_Parent_PATH="$(dirname $0)/.."

  if [[ "$Nginx_Parent_PATH" != /* ]]; then
    echo -e "${ERROR} ${Nginx_Parent_PATH} 不是绝对路径，尝试获取绝对路径"
    Nginx_Parent_PATH="$(pwd)/$(dirname $0)/.."
  fi

  if [[ "$Nginx_Parent_PATH" == /* ]] && [[ -n "$Nginx_Parent_PATH" ]]; then
    echo -e "${INFO} ${Nginx_Parent_PATH}"
  else
    echo -e "${ERROR} 获取绝对路径失败"
    exit 1
  fi
}

get_github_latest() {
  local repo_name=$1
  local version=$(curl -s https://api.github.com/repos/${repo_name}/releases/latest | grep tag_name | head -n 1 | cut -d '"' -f 4)
  [ -z $version ] && {
    sleep 5
    version=$(curl -s https://api.github.com/repos/${repo_name}/tags | grep "name" | grep -vEi ".*(rc|r).*" | cut -d '"' -f 4 | sort -Vr | head -n 1)
  }
  [ -z $version ] && {
    echo -e "${ERROR} Cant get version for repo: ${repo_name}."
    exit 1
  }
  sleep 5
  echo -e $version
}

read_parameters() {
  echo -en "\e[0;33mEnter Your website dir(default: /home/wwwroot/default): \e[0m"
  read Default_Website_Dir
  [ -z ${Default_Website_Dir} ] && Default_Website_Dir="/home/wwwroot/default"
  echo " Your website dir: ${Default_Website_Dir}"

  echo -en "\e[0;33mUsing Nginx as a reverse proxy for Apache(y,n default n): \e[0m"
  read nginx_reverse_proxy

  while :;do
    echo -en "\e[0;33mPlease enter your email address: \e[0m"
    read email_address
    if [[ "${email_address}" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}$ ]]; then
      echo "Email address ${email_address} is valid."
      break
    else
      echo "Email address ${email_address} is invalid! Please re-enter."
    fi
  done
}

add_user() {
  # groupadd -g 2000 www && useradd -M -g www -u 2000 www -s /sbin/nologin
  useradd -r -s /sbin/nologin www
}

install_dependency() {
  cd ${HOME}/nginx

  # zlib
  wget https://zlib.net/current/zlib.tar.gz -O zlib.tar.gz
  # OpenSSL
  local openssl_vserion=$(get_github_latest "openssl/openssl")
  wget https://github.com/openssl/openssl/releases/download/${openssl_vserion}/${openssl_vserion}.tar.gz -O openssl.tar.gz
  # Pcre
  local pcre2_vserion=$(get_github_latest "PCRE2Project/pcre2")
  wget https://github.com/PCRE2Project/pcre2/releases/download/${pcre2_vserion}/${pcre2_vserion}.tar.gz -O pcre2.tar.gz

  mkdir zlib && tar zxf zlib.tar.gz --strip-components=1 --directory=zlib
  mkdir openssl && tar zxf openssl.tar.gz --strip-components=1 --directory=openssl
  mkdir pcre2 && tar zxf pcre2.tar.gz --strip-components=1 --directory=pcre2

  rm -f zlib.tar.gz openssl.tar.gz pcre2.tar.gz
}

configure_luajit() {
  cd ${HOME}/nginx

  git clone https://github.com/openresty/luajit2.git
  cd luajit2

  make -j `grep 'processor' /proc/cpuinfo | wc -l` && make install PREFIX=/usr/local/luajit

  echo "/usr/local/luajit/lib" > /etc/ld.so.conf.d/luajit.conf

  ln -sf /usr/local/luajit/lib/libluajit-5.1.so.2 /lib64/libluajit-5.1.so.2

  echo "export LUAJIT_LIB=/usr/local/luajit/lib" > /etc/profile.d/luajit.sh
  echo "export LUAJIT_INC=/usr/local/luajit/include/luajit-2.1" >> /etc/profile.d/luajit.sh

  cd -
}

download_nginx_lua() {
  cd ${HOME}/nginx

  # NDK
  local ngx_devel_kit_vserion=$(get_github_latest "vision5/ngx_devel_kit")
  wget https://github.com/vision5/ngx_devel_kit/archive/refs/tags/${ngx_devel_kit_vserion}.tar.gz -O ngx_devel_kit.tar.gz
  # Ngx_Lua
  local lua_nginx_module_version=$(get_github_latest "openresty/lua-nginx-module")
  wget https://github.com/openresty/lua-nginx-module/archive/refs/tags/${lua_nginx_module_version}.tar.gz -O lua-nginx-module.tar.gz

  # Ngx_Stream_Lua
  local stream_lua_nginx_module_version=$(get_github_latest "openresty/stream-lua-nginx-module")
  wget https://github.com/openresty/stream-lua-nginx-module/archive/refs/tags/${stream_lua_nginx_module_version}.tar.gz -O stream-lua-nginx-module.tar.gz

  # LuaRestyLrucache
  local lua_resty_lrucache_version=$(get_github_latest "openresty/lua-resty-lrucache")
  wget https://github.com/openresty/lua-resty-lrucache/archive/refs/tags/${lua_resty_lrucache_version}.tar.gz -O lua-resty-lrucache.tar.gz

  # LuaRestCore
  local lua_resty_core_version=$(get_github_latest "openresty/lua-resty-core")
  wget https://github.com/openresty/lua-resty-core/archive/refs/tags/${lua_resty_core_version}.tar.gz -O lua-resty-core.tar.gz

  mkdir ngx_devel_kit && tar zxf ngx_devel_kit.tar.gz --strip-components=1 --directory=ngx_devel_kit
  mkdir lua-nginx-module && tar zxf lua-nginx-module.tar.gz --strip-components=1 --directory=lua-nginx-module
  mkdir stream-lua-nginx-module && tar zxf stream-lua-nginx-module.tar.gz --strip-components=1 --directory=stream-lua-nginx-module
  mkdir lua-resty-lrucache && tar zxf lua-resty-lrucache.tar.gz --strip-components=1 --directory=lua-resty-lrucache
  mkdir lua-resty-core && tar zxf lua-resty-core.tar.gz --strip-components=1 --directory=lua-resty-core

  rm -f ngx_devel_kit.tar.gz lua-nginx-module.tar.gz stream-lua-nginx-module.tar.gz lua-resty-lrucache.tar.gz lua-resty-core.tar.gz
}

configure_lua() {
  cd ${HOME}/nginx

  cd lua-resty-lrucache
  make install PREFIX=/usr/local/nginx LUA_LIB_DIR=/usr/local/nginx/lib/lua
  cd -

  cd lua-resty-core
  make install PREFIX=/usr/local/nginx LUA_LIB_DIR=/usr/local/nginx/lib/lua
  cd -
}

download_nginx_fancy() {
  cd ${HOME}/nginx

  local fancyindex_version=$(get_github_latest "aperezdc/ngx-fancyindex")
  local fancyindex_download_version=$(echo $fancyindex_version | sed 's/v//g')
  wget https://github.com/aperezdc/ngx-fancyindex/releases/download/${fancyindex_version}/ngx-fancyindex-${fancyindex_download_version}.tar.xz -O ngx-fancyindex.tar.gz
  mkdir ngx-fancyindex && tar xf ngx-fancyindex.tar.gz --strip-components=1 --directory=ngx-fancyindex
  rm ngx-fancyindex.tar.gz
}

make_nginx() {
  cd ${HOME}/nginx

  [ -z $1 ] && {
    echo -e "${ERROR} Unavailable Nginx Version."
    exit 1
  }

  wget "https://nginx.org/download/nginx-$1.tar.gz" -O nginx.tar.gz
  mkdir nginx && tar zxf nginx.tar.gz --strip-components=1 --directory=nginx
  rm nginx.tar.gz && cd nginx

  source /etc/profile.d/luajit.sh

  ./configure \
    --http-client-body-temp-path=/usr/local/nginx/client_body_temp \
    --http-proxy-temp-path=/usr/local/nginx/proxy_temp \
    --http-fastcgi-temp-path=/usr/local/nginx/fastcgi_temp \
    --http-uwsgi-temp-path=/usr/local/nginx/uwsgi_temp \
    --http-scgi-temp-path=/usr/local/nginx/scgi_temp \
    --user=www --group=www \
    --prefix=/usr/local/nginx\
    --with-http_stub_status_module \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_v3_module \
    --with-http_gzip_static_module \
    --with-http_sub_module \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-http_realip_module \
    --with-http_addition_module \
    --with-openssl=${HOME}/nginx/openssl \
    --with-openssl-opt='enable-weak-ssl-ciphers' \
    --with-pcre=${HOME}/nginx/pcre2 --with-pcre-jit \
    --with-zlib=${HOME}/nginx/zlib \
    --with-ld-opt=-Wl,-rpath,/usr/local/luajit/lib \
    --add-module=${HOME}/nginx/ngx_devel_kit \
    --add-module=${HOME}/nginx/lua-nginx-module \
    --add-module=${HOME}/nginx/stream-lua-nginx-module \
    --add-module=${HOME}/nginx/ngx-fancyindex

  make -j `grep 'processor' /proc/cpuinfo | wc -l`
  make install

  cd -

  ln -sf /usr/local/nginx/sbin/nginx /usr/bin/nginx
}

fastcgi() {
  cat >${Default_Website_Dir}/.user.ini<<EOF
open_basedir=${Default_Website_Dir}:/tmp/:/proc/
EOF
  chown www:www ${Default_Website_Dir}/.user.ini && chmod 644 ${Default_Website_Dir}/.user.ini
  # chattr +i ${Default_Website_Dir}/.user.ini
  cat >>/usr/local/nginx/conf/fastcgi.conf<<EOF
fastcgi_param PHP_ADMIN_VALUE "open_basedir=\$document_root/:/tmp/:/proc/";
EOF
}

apache() {
  \cp -a "${Nginx_Parent_PATH}/conf/nginx-proxy/proxy-pass-php.conf"          /usr/local/nginx/conf/
  \cp -a "${Nginx_Parent_PATH}/conf/nginx-proxy/proxy.conf"                   /usr/local/nginx/conf/
  \cp -a "${Nginx_Parent_PATH}/conf/nginx-proxy/nginx.conf"                   /usr/local/nginx/conf/
}

conf_nginx() {
  \cp -a "${Nginx_Parent_PATH}/conf/nginx/enable-php-pathinfo.conf"           /usr/local/nginx/conf/
  \cp -a "${Nginx_Parent_PATH}/conf/nginx/enable-php.conf"                    /usr/local/nginx/conf/
  \cp -a "${Nginx_Parent_PATH}/conf/nginx/example"                            /usr/local/nginx/conf/
  \cp -a "${Nginx_Parent_PATH}/conf/nginx/pathinfo.conf"                      /usr/local/nginx/conf/
  \cp -a "${Nginx_Parent_PATH}/conf/nginx/rewrite"                            /usr/local/nginx/conf/
  \cp -a "${Nginx_Parent_PATH}/conf/nginx/nginx.conf"                         /usr/local/nginx/conf/
  cat /dev/null > /usr/local/nginx/conf/blacklist.conf
  fastcgi
  if [ ! -z $nginx_reverse_proxy ] && [ $nginx_reverse_proxy = 'y' ]; then
    apache
  fi
  sed -i "s|root  {Default_Website_Dir};|root  ${Default_Website_Dir};|g" /usr/local/nginx/conf/nginx.conf
  mkdir -p /usr/local/nginx/conf/vhost
  chown -R root:root /usr/local/nginx/conf/
}

end_nginx() {
  \cp -a "${Nginx_Parent_PATH}/bin/nginx" /etc/init.d/nginx
  chown root:root /etc/init.d/nginx && chmod +x /etc/init.d/nginx

  cat "${Nginx_Parent_PATH}/service/nginx.service" > /etc/systemd/system/nginx.service
  systemctl enable nginx.service
  \cp -a "${Nginx_Parent_PATH}/bin/lmnp" /bin/lmnp
  chown root:root /bin/lmnp && chmod +x /bin/lmnp
}

install_acme() {
  [ -f /usr/local/acme.sh/acme.sh ] && return 0

  cd ${HOME}/nginx
  git clone https://github.com/acmesh-official/acme.sh.git
  cd ./acme.sh
  ./acme.sh --install -m $email_address
}

check_nginx()
{
  echo "============================== Check install =============================="
  echo "Checking ..."
  if [[ -s /usr/local/nginx/conf/nginx.conf && -s /usr/local/nginx/sbin/nginx ]]; then
    systemctl daemon-reload
    systemctl start nginx.service
    echo -e "${INFO} Nginx: OK"
  else
    echo -e "${ERROR} Nginx install failed."
  fi
}

install() {
  determine_path
  read_parameters
  echo -e "[Starting time: `date +'%Y-%m-%d %H:%M:%S'`]"
  TIME_START=$(date +%s)
  add_user
  [ ! -d $Default_Website_Dir ] && mkdir -p ${Default_Website_Dir}
  chmod +w ${Default_Website_Dir}
  chown -R www:www ${Default_Website_Dir}

  [ ! -d $web_logs_path ] && mkdir -p $web_logs_path
  chown -R www:www $web_logs_path && chmod 777 $web_logs_path

  install_dependency
  configure_luajit
  download_nginx_lua
  configure_lua
  download_nginx_fancy
  make_nginx $nginx_version
  conf_nginx
  end_nginx
  install_acme
  check_nginx
  echo -e "[End time: `date +'%Y-%m-%d %H:%M:%S'`]"
  TIME_END=$(date +%s)
  echo -e "${INFO} Successfully done! Command takes $((TIME_END-TIME_START)) seconds."
}

web_logs_path="/home/wwwlogs"
nginx_version="1.28.1"

[ -d "${HOME}/nginx" ] && mv ${HOME}/nginx ${HOME}/nginx-$(date +'%Y-%m-%d')
[ ! -d "${HOME}/nginx" ] && mkdir ${HOME}/nginx
[ ! -d "${HOME}/logs" ] && mkdir ${HOME}/logs
install 2>&1 | tee ${HOME}/logs/nginx.log
