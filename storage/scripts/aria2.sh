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
  Aria2_ROOT_PATH="$(dirname $0)/../Aria2"

  if [[ "$Aria2_ROOT_PATH" != /* ]]; then
    echo -e "${ERROR} ${Aria2_ROOT_PATH} 不是绝对路径，尝试获取绝对路径"
    Aria2_ROOT_PATH="$(pwd)/$(dirname $0)/../Aria2"
  fi

  if [[ "$Aria2_ROOT_PATH" == /* ]] && [[ -n "$Aria2_ROOT_PATH" ]]; then
    echo -e "${INFO} ${Aria2_ROOT_PATH}"
  else
    echo -e "${ERROR} 获取绝对路径失败"
    exit 1
  fi
}

enter_parameters() {
  # 需要用户手动设置的参数
  echo -en "\e[0;33mEnter the user who runs aria2: \e[0m"
  read my_aria2_user

  [ -z $my_aria2_user ] && {
    echo -e "${ERROR} Invaild user."
    exit 1
  }
  id $my_aria2_user
  [ $? -ne 0 ] && {
    echo -e "${ERROR} Invaild user."
    exit 1
  }

  # getent passwd "$user" | cut -d':' -f 6
  userHome=$(getent passwd "$my_aria2_user" | awk -F ':' '{print $6}')
  [ ! -d $userHome ] && {
    echo -e "${ERROR} $userHome not exists. Try to create..."
    mkdir -p $userHome
    chown -R $my_aria2_user:$my_aria2_user $userHome
  }

  echo -en "\e[0;33mEnter Aria2 listen port(default 33333): \e[0m"
  read my_bt_listen_port
  [ -z $my_bt_listen_port ] && my_bt_listen_port="33333"

  echo -en "\e[0;33mEnter Aria2 dht listen port(default 33333): \e[0m"
  read my_dht_listen_port
  [ -z $my_dht_listen_port ] && my_dht_listen_port="33333"

  echo -en "\e[0;33mEnter Aria2 rpc listen port(default 33334): \e[0m"
  read my_rpc_listen_port
  [ -z $my_rpc_listen_port ] && my_rpc_listen_port="33334"

  if [ $my_rpc_listen_port -eq $my_bt_listen_port ] || [ $my_rpc_listen_port -eq $my_dht_listen_port ]; then
    echo -e "${ERROR} Rpc port has been used."
    exit 1
  fi

  my_rpc_secret=$(tr -dc 'A-Za-z0-9_+-' < /dev/urandom | head -c 12)

  echo -en "\e[0;33mEnable upload bt files after completion(y/n, default n): \e[0m"
  read my_bt_download_complete

  if [ ! -z $my_bt_download_complete ] && [ $my_bt_download_complete = 'y' ]; then
    echo -en "\e[0;33mEnter the rclone drive name: \e[0m"
    read my_rlone_drive_name
  fi
}

install_aria2() {
  for packages in \
    aria2 \
  ;
  do apt-get --no-install-recommends install -y $packages; done
}

configure_aria2() {
  mkdir -p $userHome/.config/aria2 && touch $userHome/.config/aria2/aria2.session
  chown -R $my_aria2_user:$my_aria2_user $userHome/.config/aria2
  mkdir -p $userHome/{aria2,Downloads}
  chown -R $my_aria2_user:$my_aria2_user $userHome/aria2 $userHome/Downloads
  mkdir -p $userHome/logs
  chown -R $my_aria2_user:$my_aria2_user $userHome/logs

  \cp -a "$Aria2_ROOT_PATH/dht.dat" $userHome/.config/aria2/dht.dat
  \cp -a "$Aria2_ROOT_PATH/dht6.dat" $userHome/.config/aria2/dht6.dat

  mkdir -p $Aria2_Config_PATH && \cp -a "$Aria2_ROOT_PATH/aria2.conf" $Aria2_Config_PATH/aria2.conf
  sed -i "s|dir={download-dir}|dir=$userHome/aria2|g" $Aria2_Config_PATH/aria2.conf
  sed -i "s|input-file={session-file}|input-file=$userHome/.config/aria2/aria2.session|g" $Aria2_Config_PATH/aria2.conf
  sed -i "s|save-session={session-file}|save-session=$userHome/.config/aria2/aria2.session|g" $Aria2_Config_PATH/aria2.conf
  sed -i "s|listen-port={bt-listen-port}|listen-port=$my_bt_listen_port|g" $Aria2_Config_PATH/aria2.conf
  sed -i "s|dht-listen-port={dht-listen-port}|dht-listen-port=$my_dht_listen_port|g" $Aria2_Config_PATH/aria2.conf
  sed -i "s|dht-file-path={dht-file}|dht-file-path=$userHome/.config/aria2/dht.dat|g" $Aria2_Config_PATH/aria2.conf
  sed -i "s|dht-file-path6={dht6-file}|dht-file-path6=$userHome/.config/aria2/dht6.dat|g" $Aria2_Config_PATH/aria2.conf
  if [ ! -z $my_bt_download_complete ] && [ $my_bt_download_complete = 'y' ]; then
    sed -i "s|#on-bt-download-complete=|on-bt-download-complete=$Aria2_Config_PATH/scripts/upload.sh|g" $Aria2_Config_PATH/aria2.conf
  fi
  sed -i "s|rpc-listen-port={rpc-port}|rpc-listen-port=$my_rpc_listen_port|g" $Aria2_Config_PATH/aria2.conf
  sed -i "s|rpc-secret={rpc-secret}|rpc-secret=$my_rpc_secret|g" $Aria2_Config_PATH/aria2.conf
  sed -i "s|log={log-file}|log=$userHome/logs/aria2.log|g" $Aria2_Config_PATH/aria2.conf
}

configure_aria2_scripts() {
  \cp -a "$Aria2_ROOT_PATH/scripts" $Aria2_Config_PATH/
  chown -R root:root $Aria2_Config_PATH/scripts/
  # chmod -R +x /usr/local/etc/aria2/scripts/

  sed -i "s|ARIA2_SESSION=\"{session-file}\"|ARIA2_SESSION=\"$userHome/.config/aria2/aria2.session\"|g" $Aria2_Config_PATH/scripts/core

  if [ ! -z $my_bt_download_complete ] && [ $my_bt_download_complete = 'y' ]; then
    sed -i "s|drive-name={rlone-drive-name}|drive-name=$my_rlone_drive_name|g" $Aria2_Config_PATH/scripts/script.conf
    sed -i "s|upload-log={upload-log-file}|upload-log=$userHome/logs/aria2-upload.log|g" $Aria2_Config_PATH/scripts/script.conf
  fi
  sed -i "s|dest-dir={move-dest-dir}|dest-dir=$userHome/Downloads|g" $Aria2_Config_PATH/scripts/script.conf
}

install_aria2_service() {
  cat > /etc/systemd/system/aria2.service <<EOF
[Unit]
Description=Aria2
After=network.target

[Service]
User=$my_aria2_user
Type=forking
ExecStart=/usr/bin/aria2c --conf-path=$Aria2_Config_PATH/aria2.conf -D
Restart=on-failure

[Install]
WantedBy=multi-user.target

EOF
}

print_configuration() {
  printf "\e[0;32m%-20s : %s\n\e[0m" 'parameter' 'value'
  printf "%-20s : %s\n" "rpc-listen-port" $my_rpc_listen_port
  printf "%-20s : %s\n" "rpc-secret" $my_rpc_secret
  printf "%-20s : %s\n" "dir" "$userHome/aria2"
  printf "%-20s : %s\n" "log" "$userHome/logs/aria2.log"
}

install() {
  determine_path
  enter_parameters
  install_aria2
  configure_aria2
  configure_aria2_scripts
  install_aria2_service
  systemctl daemon-reload && systemctl enable --now aria2
  print_configuration
}

Aria2_Config_PATH="/usr/local/etc/aria2"

[ ! -d "${HOME}/logs" ] && mkdir ${HOME}/logs
install 2>&1 | tee ${HOME}/logs/aria2.log
