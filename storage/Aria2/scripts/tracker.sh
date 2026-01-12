#!/usr/bin/env bash
# 
# update the trackerslist

CHECK_CORE_FILE() {
    CORE_FILE="$(dirname $0)/core"
    if [[ -f "${CORE_FILE}" ]]; then
        . "${CORE_FILE}"
    else
        echo && echo "!!! core file does not exist !!!"
        exit 1
    fi
}

GET_TRACKERS() {
    PREFIX="bt-tracker="
    for line in $(curl -fsSL --connect-timeout 3 --max-time 3 --retry 2 $1)
    do
        PREFIX=${PREFIX}","${line}
    done
    trackers=$(echo ${PREFIX} | awk -F '=,' '{print $2}')

    [[ -z "${trackers}" ]] && {
        echo
        echo -e "$(DATE_TIME) ${ERROR} Unable to get trackers, network failure or invalid links." && exit 1
    }
}

ECHO_TRACKERS() {
    GET_TRACKERS "https://trackerslist.com/all.txt"
    echo -e "
--------------------[BitTorrent Trackers]--------------------
${trackers}
--------------------[BitTorrent Trackers]--------------------
"
}

ADD_TRACKERS_RPC() {
    if [[ "${RPC_SECRET}" ]]; then
        RPC_PAYLOAD='{"jsonrpc":"2.0","method":"aria2.changeGlobalOption","id":"rclone","params":["token:'${RPC_SECRET}'",{"bt-tracker":"'${trackers}'"}]}'
    else
        RPC_PAYLOAD='{"jsonrpc":"2.0","method":"aria2.changeGlobalOption","id":"rclone","params":[{"bt-tracker":"'${trackers}'"}]}'
    fi
    RPC_RESULT=$(curl "${RPC_ADDRESS}" -fsSd "${RPC_PAYLOAD}" || curl "https://${RPC_ADDRESS}" -kfsSd "${RPC_PAYLOAD}")
    [[ $(echo ${RPC_RESULT} | grep OK) ]] &&
        echo -e "$(DATE_TIME) ${INFO} BT trackers successfully added to Aria2 !" ||
        echo -e "$(DATE_TIME) ${ERROR} Network failure or Aria2 RPC interface error!"
}

ADD_TRACKERS_LOCAL_RPC() {
    if [ ! -f ${ARIA2_CONF} ]; then
        echo -e "$(DATE_TIME) ${ERROR} '${ARIA2_CONF}' does not exist."
        exit 1
    else
        RPC_PORT=$(grep ^rpc-listen-port ${ARIA2_CONF} | cut -d= -f2-)
        RPC_SECRET=$(grep ^rpc-secret ${ARIA2_CONF} | cut -d= -f2-)
        [[ ${RPC_PORT} ]] || {
            echo -e "$(DATE_TIME) ${ERROR} Aria2 configuration file incomplete."
            exit 1
        }
        RPC_ADDRESS="localhost:${RPC_PORT}/jsonrpc"
        echo -e "$(DATE_TIME) ${INFO} Adding BT trackers to Aria2 ..." && echo
        ADD_TRACKERS_RPC
    fi
}

ADD_TRACKERS() {
    [ -z $(grep "bt-tracker=" ${ARIA2_CONF}) ] && echo -e "\nbt-tracker=" >>${ARIA2_CONF}
    sed -i "s|^\(bt-tracker=\).*|\1${trackers}|g" ${ARIA2_CONF} && echo -e "$(DATE_TIME) ${INFO} BT trackers successfully added to Aria2 configuration file !"
}

ADD_TRACKERS_LOCAL() {
    if [ -f "/etc/systemd/system/aria2.service" ]; then
        echo -e "\e[34m[Info]\e[0m find aria2.service, restarting..."
        systemctl restart aria2.service
    else
        echo -e "\e[31m[Info]\e[0m cannot find aria2.service..."
    fi
}

CHECK_CORE_FILE

if [ "$1" = "RPC" ]; then
    ECHO_TRACKERS
    ADD_TRACKERS
    ADD_TRACKERS_LOCAL_RPC
else
    ECHO_TRACKERS
    ADD_TRACKERS
    ADD_TRACKERS_LOCAL
fi
