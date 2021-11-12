#!/usr/bin/env bash

READLINK="readlink"
if [[ $(uname -s) == "Darwin" ]]; then
  READLINK="greadlink"
fi

HOME=$($READLINK -f .)

HTTP_PORT=9080
HTTPS_PORT=9443

DOCKER_IMAGE="api7/apisix-cloud-dp:dev"

VERBOSE_FLAG=
FOREGROUND_FLAG=

help() {
cat << EOF
Usage: cloud_data_plane_setup.sh [options]

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

check_dependencies() {
  # check if docker is installed
  if [[ -z "$(docker version 2>/dev/null |grep  -o 'Version:')" ]]; then
    error "service: docker has not been installed yet."
  fi

  if [[ "${VERBOSE_FLAG}" == "on" ]]; then
    ver="$(docker version 2>/dev/null |grep -o "Version:.*" | awk '{print $2}')"
    debug "docker version: $ver"
  fi
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
  debug "make sure certificate and private key are existing"

  # ensure certs existed
  [[ -f $CA_CERT ]] || error "CA certificate: ${CA_CERT} is not a file"
  [[ -f $CERT ]] || error "client certificate: ${CERT} is not file or existed"
  [[ -f $KEY ]] || error "private key: ${KEY} is not file or existed"

  # domain cannot be empty
  [[ -z "$DOMAIN" ]] && error "domain cannot be empty"
}

configure_certificate() {
  debug "converting to absolute path"

  CA_CERT="$($READLINK -f $CA_CERT)"
  CERT="$($READLINK -f $CERT)"
  KEY="$($READLINK -f $KEY)"
}

# generate the APISIX gateway configuration file
generate_configuration() {
  debug "generating APISIX configuration"

  if [[ ! -d ${HOME}/.cloud ]]; then
    mkdir -p ${HOME}/.cloud
  else
    [[ -f ${HOME}/.cloud/config.yaml ]] && echo "> config.yaml file existed, it will be overwritten"
  fi

  cat > ${HOME}/.cloud/config.yaml << EOF
apisix:
  enable_admin: false
  ssl:
    ssl_trusted_certificate: /usr/local/cloud/cert/ca.crt

etcd:
  host:
    - "https://${DOMAIN}:443"
  tls:
    cert: /usr/local/cloud/cert/tls.crt
    key: /usr/local/cloud/cert/tls.key
    sni: ${DOMAIN}
    verify: true

plugin_attr:
  cloud:
    domain: ${DOMAIN}
    port: 443
    cert: /usr/local/cloud/cert/tls.crt
    key: /usr/local/cloud/cert/tls.key

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

# run APISIX in docker
run_apisix_docker() {
  debug "starting APISIX gateway"

  docker_command="
      -p ${HTTP_PORT}:9080 \
      -p ${HTTPS_PORT}:9443 \
      --mount type=bind,source=${HOME}/.cloud/config.yaml,target=/usr/local/apisix/conf/config.yaml,readonly \
      --mount type=bind,source=${CA_CERT},target=/usr/local/cloud/cert/ca.crt,readonly \
      --mount type=bind,source=${CERT},target=/usr/local/cloud/cert/tls.crt,readonly \
      --mount type=bind,source=${KEY},target=/usr/local/cloud/cert/tls.key,readonly \
      ${DOCKER_IMAGE}"

  if [[ "${FOREGROUND_FLAG}" == "on" ]]; then
    docker run $docker_command
  else
    docker_id=$(docker run -d $docker_command)
    if [[ $? -ne 0 ]]; then
      error "failed to run APISIX gateway."
    fi

    echo -e "> docker id: ${docker_id}"
    echo -e "\033[32m> run APISIX gateway successfully on docker.\033[0m"
  fi
}

main() {
  args_parse $@

  validate

  check_dependencies

  configure_certificate

  generate_configuration

  download_docker_image

  run_apisix_docker

  cleanup 0
}

main $@
