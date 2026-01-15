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
  Redis_Parent_PATH="$(dirname $0)/.."

  if [[ "$Redis_Parent_PATH" != /* ]]; then
    echo -e "${ERROR} ${Redis_Parent_PATH} 不是绝对路径，尝试获取绝对路径"
    Redis_Parent_PATH="$(pwd)/$(dirname $0)/.."
  fi

  if [[ "$Redis_Parent_PATH" == /* ]] && [[ -n "$Redis_Parent_PATH" ]]; then
    echo -e "${INFO} ${Redis_Parent_PATH}"
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

init() {
  apt-get update -y
  for packages in \
          ca-certificates \
          wget \
          dpkg-dev \
          gcc \
          g++ \
          libc6-dev \
          libssl-dev \
          make \
          git \
          cmake \
          python3 \
          python3-pip \
          python3-venv \
          python3-dev \
          unzip \
          rsync \
          clang \
          automake \
          autoconf \
          libtool \
  ;
  do apt-get --no-install-recommends install -y $packages; done
}

enter_overcommit() {
  overcommit_memory='y'
  echo -e "Redis need to enable overcommit_memory, or redis background save and replication may fail under low memory condition.\nMore info see https://github.com/jemalloc/jemalloc/issues/1328."
  echo -en "\e[0;33mEnable always overcommit memory(y/n, default y): \e[0m"
  read overcommit_memory
  if [ "${overcommit_memory}" = "y" ]; then check_overcommit; fi     
}

check_overcommit() {
  grep -P "vm.overcommit_memory.*=.*1" /etc/sysctl.conf
  if [ $? -eq 0 ]; then
    echo "Already enabled overcommit memory..."
  else
    echo -e "\n# Redis\nvm.overcommit_memory = 1" >> /etc/sysctl.conf
    sysctl -p
  fi
}

make_redis() {
  cd ${HOME}/redis
  echo "Build Redis from source..."
  redis_version=$(get_github_latest "redis/redis")
  wget -O redis.tar.gz https://github.com/redis/redis/archive/refs/tags/${redis_version}.tar.gz
  mkdir redis && tar zxf redis.tar.gz --strip-components=1 --directory=redis
  rm redis.tar.gz && cd redis

  export BUILD_TLS=yes
  export BUILD_WITH_MODULES=yes
  export INSTALL_RUST_TOOLCHAIN=yes
  export DISABLE_WERRORS=yes

  make -j `grep 'processor' /proc/cpuinfo | wc -l` all
  make PREFIX=/usr/local/redis install
  mkdir -p /usr/local/redis/etc/
  \cp redis.conf redis-full.conf /usr/local/redis/etc/
  sed -i 's/daemonize no/daemonize yes/g' /usr/local/redis/etc/redis.conf
  sed -i 's#^pidfile /var/run/redis_6379.pid#pidfile /var/run/redis.pid#g' /usr/local/redis/etc/redis.conf

  sed -i 's#include redis.conf#include ./etc/redis.conf#g' /usr/local/redis/etc/redis-full.conf
  sed -i 's#loadmodule .*\/#loadmodule ./lib/redis/modules/#g' /usr/local/redis/etc/redis-full.conf
}

config_redis() {
  \cp "${Redis_Parent_PATH}/bin/lmredis" /bin/lmredis
  chown root:root /bin/lmredis && chmod +x /bin/lmredis
  cat "${Redis_Parent_PATH}/service/redis.service" > /etc/systemd/system/redis.service
  systemctl daemon-reload && systemctl enable redis.service
  systemctl start redis.service
  sleep 5
}

check_redis() {
  if [[ -s /usr/local/redis/bin/redis-server && -s /usr/local/redis/bin/redis-cli && -s /usr/local/redis/etc/redis-full.conf ]]; then
    echo -e "\e[0;32m`/usr/local/redis/bin/redis-cli INFO`\e[0m"
  else
    echo -e "${ERROR} Redis install failed."
  fi
}

enter_acl() {
  echo -e "Enable Redis Access Control List?\nMore info see https://redis.io/docs/latest/operate/oss_and_stack/management/security/acl/"
  echo -en "\e[0;33mEnable Redis ACL (y/n, deafult n): \e[0m"
  read enable_acl
  [ -z ${enable_acl} ] && enable_acl='n'
}

acl() {
  echo "user default off" > /usr/local/redis/etc/users.acl
  user1=$(acl_user 'admin' '~*' '&*' '+@all')
  user2=$(acl_user 'readonly' '~app:* ~stats:*' '&app.' '+@read +@pubsub -publish -flushall -flushdb -config -debug -module -slaveof')
  header=$(printf "%-20s : %s\n" 'username' 'password')
  sed -i 's|# aclfile /etc/redis/users.acl|aclfile ./etc/users.acl|g' /usr/local/redis/etc/redis.conf
  echo -e "\e[0;32m${header}\e[0m"
  echo "${user1}"
  echo "${user2}"
}

acl_user() {
  user=$1
  if [ -z '${user}' ]; then
    echo -e " \e[0;31mWrong: No username.\e[0m"
    return 1
  fi
  keys=$2
  if [ -z '${keys}' ]; then
    keys='~app:* ~session:* ~cache:*'
  fi
  channels=$3
  if [ -z '${channels}' ]; then
    channels='&app.* &notifications.*'
  fi
  commands=$4
  if [ -z '${commands}' ]; then
    commands='+@read +@write +@pubsub -flushall -flushdb -config -debug -module -slaveof -save -bgsave'
  fi
  local pd=$(tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c 12)
  local sha256pd=$(echo -n "${pd}" | sha256sum | awk '{print $1}')
  echo "user ${user} on #${sha256pd} ${keys} ${channels} ${commands}" >> /usr/local/redis/etc/users.acl
  printf "%-20s : %s\n" $1 $pd
}

install() {
  determine_path
  # init
  enter_overcommit
  enter_acl
  echo -e "[Starting time: `date +'%Y-%m-%d %H:%M:%S'`]"
  TIME_START=$(date +%s)
  make_redis
  config_redis
  check_redis
  if [ ${enable_acl} = 'y' ]; then
    acl
    systemctl stop redis.service
    sleep 5
    systemctl start redis.service
  fi
  echo -e "[End time: `date +'%Y-%m-%d %H:%M:%S'`]"
  TIME_END=$(date +%s)
  echo -e "${INFO} Successfully done! Command takes $((TIME_END-TIME_START)) seconds."
}

[ -d "${HOME}/redis" ] && mv ${HOME}/redis ${HOME}/redis-$(date +'%Y-%m-%d')
[ ! -d "${HOME}/redis" ] && mkdir ${HOME}/redis
[ ! -d "${HOME}/logs" ] && mkdir ${HOME}/logs
install 2>&1 | tee ${HOME}/logs/redis.log
