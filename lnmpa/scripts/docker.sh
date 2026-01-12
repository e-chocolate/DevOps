#!/usr/bin/env bash
export PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin

# Check if user is root
if [ $(id -u) != "0" ]; then
  echo "Error: You must be root to run this script"
  exit 1
fi

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)
      echo "amd64"
      ;;
    aarch64|arm64)
      echo "arm64"
      ;;
    armv7l|armv6l)
      echo "arm32"
      ;;
    i386|i686)
      echo "386"
      ;;
    s390x)
      echo "s390x"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

get_distrib_info() {
  ARCH=$(detect_arch)
  RELEASE=$(cat /etc/lsb-release | grep "DISTRIB_RELEASE" | cut -d"=" -f 2)
  CODENAME=$(cat /etc/lsb-release | grep "DISTRIB_CODENAME" | cut -d"=" -f 2)
}

download_docker() {
  docker_base="https://download.docker.com/linux/ubuntu/dists/noble/pool/stable/${ARCH}"

  wget ${docker_base}/containerd.io_${containerd_io_version}~ubuntu.${RELEASE}~${CODENAME}_${ARCH}.deb -O /tmp/containerd.io.deb
  wget ${docker_base}/docker-ce-cli_${docker_ce_cli_version}~ubuntu.${RELEASE}~${CODENAME}_${ARCH}.deb -O /tmp/docker-ce.deb
  wget ${docker_base}/docker-ce_${docker_ce_version}~ubuntu.${RELEASE}~${CODENAME}_${ARCH}.deb -O /tmp/docker-ce-cli.deb
  wget ${docker_base}/docker-buildx-plugin_${docker_buildx_plugin_version}~ubuntu.${RELEASE}~${CODENAME}_${ARCH}.deb -O /tmp/docker-buildx-plugin.deb
  wget ${docker_base}/docker-compose-plugin_${docker_compose_plugin_version}~ubuntu.${RELEASE}~${CODENAME}_${ARCH}.deb -O /tmp/docker-compose-plugin.deb
}

install_docker() {
  dpkg -i /tmp/containerd.io.deb \
          /tmp/docker-ce.deb \
          /tmp/docker-ce-cli.deb \
          /tmp/docker-buildx-plugin.deb \
          /tmp/docker-compose-plugin.deb
}

clean() {
  rm -f /tmp/containerd.io.deb /tmp/docker-ce.deb /tmp/docker-ce-cli.deb /tmp/docker-buildx-plugin.deb /tmp/docker-compose-plugin.deb
}

create_docker_user() {
  # 创建无法登录的系统用户，专门启动不同的docker容器
  getent group docker
  if [ $? -eq 0 ]; then
    dockerGid=$(getent group docker | awk -F ':' '{print $3}')
    id ${dockerGid}
    if [ $? -ne 0 ]; then
      uidConfig="-u ${dockerGid}"
    fi
    groupConfig="-g docker"
  fi
  useradd ${uidConfig} ${groupConfig} -d /var/lib/docker -r -s /sbin/nologin docker
  [ ! -d '/var/lib/docker' ] && mkdir /var/lib/docker
  chown -R docker:docker /var/lib/docker
}

add_docker_user() {
  # 将现有用户加入到docker用户组
  getent passwd $1
  if [ $? -eq 0 ]; then
    uid=$(getent passwd $1 | awk -F ':' '{print $3}')
  fi
  usermod -aG docker $uid
}

install() {
  get_distrib_info
  download_docker
  install_docker
  clean
  create_docker_user
}

containerd_io_version="2.2.1-1"
docker_ce_version="29.1.4-1"
docker_ce_cli_version="29.1.4-1"
docker_buildx_plugin_version="0.30.1-1"
docker_compose_plugin_version="5.0.1-1"

if [ ! -d "${HOME}/logs" ]; then
  mkdir ${HOME}/logs
fi
install 2>&1 | tee ${HOME}/logs/docker.log
