#!/usr/bin/env bash

READLINK="readlink"
if [[ $(uname -s) == "Darwin" ]]; then
  READLINK="greadlink"
fi

HTTP_PORT=9080
HTTPS_PORT=9443
DOCKER_IMAGE="apache/apisix:2.11.0-centos"
CLOUD_MODULE_PATH="/tmp/cloud_module_beta"
CONFIG_PATH=
VERBOSE_FLAG=
FOREGROUND_FLAG=

help() {
cat << EOF
Usage: run-apisix-on-docker.sh [options]

Options:
    -d,  --domain        specify the domain of control plane
    -ca, --cacert        specify the CA certificate
    -c,  --cert          specify the client certificate
    -k,  --key           specify the private key
    -p,  --http-port     specify APISIX Gateway HTTP port
         --https-port    specify APISIX Gateway HTTPS port
    -di, --docker-image  docker image
    -f,  --foreground    run APISIX Gateway on the foreground
    -v,  --verbose       make the operation more talkative
    -h, --help           display this help and exit
EOF
}

# print information if VERBOSE on
debug() {
  [[ "$VERBOSE_FLAG" == "on" ]] && echo "> $1"
}

# print error message and exit in abnormal
error() {
  echo -e "\033[31m> $1\033[0m"
  cleanup 1
}

# sweep the workspace
cleanup() {
  exit $1
}

args_parse() {
  while [[ $# -gt 0 ]]; do key="$1"
    case $key in
    -d | --domain)
      DOMAIN=$2
      shift
      ;;
    -f | --foreground)
      FOREGROUND_FLAG="on"
      ;;
    -ca | --cacert)
      CA_CERT=$2
      shift
      ;;
    -c | --cert)
      CERT=$2
      shift
      ;;
    -k | --key)
      KEY=$2
      shift
      ;;
    -p | --http-port)
      HTTP_PORT=$2
      shift
      ;;
    --https-port)
      HTTPS_PORT=$2
      shift
      ;;
   -di | --docker-image)
      DOCKER_IMAGE=$2
      shift
      ;;
    -v | --verbose)
      VERBOSE_FLAG="on"
      ;;
    -h | --help)
      help
      exit 0
      ;;
    *)
      error "the argument[$1] is expected"
      ;;
    esac
    shift
  done
}

# validate the arguments
validate() {
  # ensure certs exist
  [[ -f $CA_CERT ]] || error "CA certificate: ${CA_CERT} is not a file"
  [[ -f $CERT ]] || error "certificate: ${CERT} is not file"
  [[ -f $KEY ]] || error "private key: ${KEY} is not file"

  # domain cannot be empty
  [[ -z "$DOMAIN" ]] && error "domain cannot be empty"

  CA_CERT="$($READLINK -f $CA_CERT)"
  CERT="$($READLINK -f $CERT)"
  KEY="$($READLINK -f $KEY)"
}

# generate the APISIX gateway configuration file
generate_configuration() {
  debug "generating APISIX configuration"
  CONFIG_PATH=`mktemp /tmp/apisix-config.yaml.XXXXXX`
  chmod a+r ${CONFIG_PATH}

  cat > ${CONFIG_PATH} << EOF
apisix:
  enable_admin: false
  ssl:
    ssl_trusted_certificate: /cloud/tls/ca.crt
  lua_module_hook: cloud
  extra_lua_path: /lua_module_hook/?.ljbc;
nginx_config:
  http:
    custom_lua_shared_dict:
      cloud: 1m
etcd:
  host:
    - "https://${DOMAIN}:443"
  tls:
    cert: /cloud/tls/tls.crt
    key: /cloud/tls/tls.key
    sni: ${DOMAIN}
    verify: true
EOF
}

# pull APISIX docker image
download_docker_image() {
  debug "pulling APISIX docker image ..."

  pulling_log=$(docker pull ${DOCKER_IMAGE})
  if [[ $? -ne 0 ]]; then
    error "failed to pull APISIX docker image"
    error "${pulling_log}"
  fi

  debug "downloaded APISIX docker image"
}

download_cloud_module() {
    debug "downloading cloud lua module ..."

    /bin/bash <(curl -fsSL 'https://raw.githubusercontent.com/api7/cloud-scripts/a9fa31ae0518e5188f66b42a5e46042b75cad993/scripts/cloud-module-fetcher.sh')
}

# run APISIX in docker
run_apisix_docker() {
  debug "starting APISIX"

  docker_command="
      -p ${HTTP_PORT}:9080 \
      -p ${HTTPS_PORT}:9443 \
      --mount type=bind,source=${CONFIG_PATH},target=/usr/local/apisix/conf/config.yaml,readonly \
      --mount type=bind,source=${CA_CERT},target=/cloud/tls/ca.crt,readonly \
      --mount type=bind,source=${CERT},target=/cloud/tls/tls.crt,readonly \
      --mount type=bind,source=${KEY},target=/cloud/tls/tls.key,readonly \
      --mount type=bind,source=${CLOUD_MODULE_PATH},target=/lua_module_hook,readonly \
      ${DOCKER_IMAGE}"

  if [[ "${FOREGROUND_FLAG}" == "on" ]]; then
    docker run $docker_command
  else
    docker_id=$(docker run -d $docker_command)
    if [[ $? -ne 0 ]]; then
      error "failed to run APISIX gateway."
    fi

    echo -e "> docker id: ${docker_id}"
    echo -e "\033[32m> launch successfully.\033[0m"
  fi
}

main() {
    args_parse $@
    validate
    download_cloud_module
    generate_configuration
    #download_docker_image
    run_apisix_docker
    cleanup 0
}

main $@
