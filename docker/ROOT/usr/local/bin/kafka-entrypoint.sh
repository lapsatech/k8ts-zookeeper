#!/usr/bin/env bash

function die() {
   >&2 echo "$1"
   sleep 20s
   exit 1
}

function required_var() {
  test "x${!1}" == "x" && die "$1 var is required"
}

function override_args() {
  while read -r name; do
    [[ "$name" =~ \s*(OVERRIDE_(.*))\s*=.* ]] && {
        VAR="${BASH_REMATCH[1]}"
        NO_PREFIX_VAR="${BASH_REMATCH[2]}"
        KAFKA_OVERRIDE_ARG=$(echo -n "$NO_PREFIX_VAR" | tr '[:upper:]' '[:lower:]' | sed -e 's/_/./g')
        KAFKA_OVERRIDE_VALUE=${!VAR}
        echo " --override ${KAFKA_OVERRIDE_ARG}=${KAFKA_OVERRIDE_VALUE}"
    }
  done < <(env)
}

function create_log4j_props() {
  local _path=$1
  cat <<EOF > ${_path}
#This file was autogenerated DO NOT EDIT
log4j.appender.console=org.apache.log4j.ConsoleAppender
logrj.appender.console.Target=System.out
log4j.appender.console.layout=org.apache.log4j.PatternLayout
log4j.appender.console.layout.ConversionPattern=[%d] %p %m (%c)%n
log4j.rootLogger=${LOG_LEVEL:-INFO}, console
EOF
  echo "${_path} created"
}

required_var ZOOKEEPER_CONNECT
required_var DATA_DIR
required_var MEMORY_HEAP

required_var BROKER_INDEX
required_var BROKER_INT_PORT
required_var BROKER_EXT_PORT
required_var BROKER_EXT_ADDRESS_PRINTF

BROKER_FQDN=$(hostname -f)
BROKER_EXT_ADDRESS=$(printf "${BROKER_EXT_ADDRESS_PRINTF}" ${BROKER_INDEX})

LOG4J_PROPS_PATH=$(mktemp -d)/log4j.properties

export LOG_DIR=$(mktemp -d)
export KAFKA_HEAP_OPTS="-Xmx${MEMORY_HEAP} -Xms${MEMORY_HEAP}"
export KAFKA_LOG4J_OPTS="-Dlog4j.configuration=file:${LOG4J_PROPS_PATH}"
export KAFKA_GC_LOG_OPTS="-Xloggc:/dev/stderr -XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintGCTimeStamps"

RUNCMD="kafka-server-start.sh /opt/kafka/config/server.properties \
          --override broker.id=${BROKER_INDEX} \
          --override zookeeper.connect=${ZOOKEEPER_CONNECT} \
          --override listeners=INTERNAL://0.0.0.0:${BROKER_INT_PORT},EXTERNAL://0.0.0.0:${BROKER_EXT_PORT} \
          --override listener.security.protocol.map=INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT \
          --override advertised.listeners=INTERNAL://${BROKER_FQDN}:${BROKER_INT_PORT},EXTERNAL://${BROKER_EXT_ADDRESS} \
          --override inter.broker.listener.name=INTERNAL \
          $(override_args)"

test "x${DONT_START}" = "x" && RUNCMD="exec ${RUNCMD}" || RUNCMD="echo ${RUNCMD}"

true \
  && create_log4j_props ${LOG4J_PROPS_PATH} \
  && echo "=======================================" \
  && echo "--------- ${LOG4J_PROPS_PATH} ---------" \
  && cat ${LOG4J_PROPS_PATH} \
  && echo "=======================================" \
  && echo "KAFKA_HEAP_OPTS=\"${KAFKA_HEAP_OPTS}\"" \
  && echo "KAFKA_LOG4J_OPTS=\"${KAFKA_LOG4J_OPTS}\"" \
  && echo "KAFKA_GC_LOG_OPTS=\"${KAFKA_GC_LOG_OPTS}\"" \
  && echo "DATA_DIR=\"${DATA_DIR}\"" \
  && echo "=======================================" \
  && echo ${RUNCMD} \
  && echo "=======================================" \
  && ${RUNCMD} \
  && true

ret=$?
echo "Exit code ${ret}"

sleep 20s
exit $ret
