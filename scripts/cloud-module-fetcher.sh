#!/usr/bin/env bash

READLINK="readlink"
if [[ $(uname -s) == "Darwin" ]]; then
  READLINK="greadlink"
fi

CLOUD_MODULE_NAME="cloud_module_beta"
VERBOSE_FLAG="off"
SAVE_TO_FLAG="local"
OUTPUT_FILEPATH=
OUTPUT_CONFIGMAP_NAMESPACE=
OUTPUT_CONFIGMAP_NAME=

help() {
cat << EOF
Usage: cloud-module-fetcher.sh [options]

Options:
    -s,  --save-to     where should the cloud module codes save, optional values are: [local, configmap]
    -o,  --output      the filepath to save the cloud module codes (when --save-to is local); or the configmap namespace and name (when --save-to is configmap), using ':' to separate the namespace and name.
    -v,  --verbose     make the operation more talkative
    -h, --help         display this help and exit
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
    -s | --save-to)
      SAVE_TO_FLAG=$2
      shift
      ;;
    -o | --output)
      OUTPUT_FLAG=$2
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
      error "the argument[$1] is unexpected"
      ;;
    esac
    shift
  done
}

validate() {
    debug "validating command line options"

    if [[ ${SAVE_TO_FLAG} != configmap ]] && [[ ${SAVE_TO_FLAG} != local ]]; then
        error "invalid --save-to option: ${SAVE_TO_FLAG}"
    fi

    if [[ ${SAVE_TO_FLAG} = local ]]; then
        OUTPUT_FILEPATH=${OUTPUT_FLAG}
        if [[ -z $OUTPUT_FILEPATH ]]; then
            OUTPUT_FILEPATH="/tmp"
        fi
    else
        OUTPUT_FILEPATH="/tmp"
        OUTPUT_CONFIGMAP_NAMESPACE=`echo $OUTPUT_FLAG | awk -F ':' '{print $1}'`
        OUTPUT_CONFIGMAP_NAME=`echo $OUTPUT_FLAG | awk -F ':' '{print $2}'`

        if [[ -z ${OUTPUT_CONFIGMAP_NAMESPACE} ]] || [[ -z ${OUTPUT_CONFIGMAP_NAME} ]]; then
            error "--invalid --output option: ${OUTPUT_FLAG}, when --save-to is configmap"
        fi
    fi
}

download_cloud_module() {
    mkdir -p ${OUTPUT_FILEPATH}
    echo -e "> downloading cloud module"
    curl -sL https://github.com/api7/cloud-scripts/raw/7da72fa3a4d563fac23fcd628fcdc601aa78dbb0/assets/${CLOUD_MODULE_NAME}.tar.gz | tar -C ${OUTPUT_FILEPATH} -zxf -

    if [[ $? = 0 ]]; then
        echo -e "> save cloud module to ${OUTPUT_FILEPATH}/${CLOUD_MODULE_NAME}"
    else
        error "failed to download cloud module"
    fi
}

make_configmap() {
    if [[ -n ${OUTPUT_CONFIGMAP_NAMESPACE} ]]; then
        echo -e "> creating configmap ${OUTPUT_CONFIGMAP_NAMESPACE}/${OUTPUT_CONFIGMAP_NAME}"
        kubectl delete configmap ${OUTPUT_CONFIGMAP_NAME} --namespace ${OUTPUT_CONFIGMAP_NAMESPACE}
        kubectl create configmap ${OUTPUT_CONFIGMAP_NAME} \
            --from-file=cloud.ljbc=${OUTPUT_FILEPATH}/${CLOUD_MODULE_NAME}/cloud.ljbc \
            --from-file=cloud-agent.ljbc=${OUTPUT_FILEPATH}/${CLOUD_MODULE_NAME}/cloud/agent.ljbc \
            --from-file=cloud-metrics.ljbc=${OUTPUT_FILEPATH}/${CLOUD_MODULE_NAME}/cloud/metrics.ljbc \
            --from-file=cloud-utils.ljbc=${OUTPUT_FILEPATH}/${CLOUD_MODULE_NAME}/cloud/utils.ljbc \
            --namespace ${OUTPUT_CONFIGMAP_NAMESPACE}
    fi
}

main() {
  args_parse $@
  validate
  download_cloud_module
  make_configmap
}

main $@
