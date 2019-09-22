#!/bin/bash

function rlink {
  TARGET_FILE=$1
  cd `dirname $TARGET_FILE`
  TARGET_FILE=`basename $TARGET_FILE`
  while [ -L "$TARGET_FILE" ]
  do
    TARGET_FILE=`readlink $TARGET_FILE`
    cd `dirname $TARGET_FILE`
    TARGET_FILE=`basename $TARGET_FILE`
  done
  PHYS_DIR=`pwd -P`
  RESULT=$PHYS_DIR/$TARGET_FILE
  echo $RESULT
}

function helpText {
cat <<EOF
kctl is a lightweight tool to manage multiple clusters of k8, and making life easy.

Usage:
  kctl [flags] command

Available Commands:
    Getting help
      help        kctl help get
    Get a resource details
      get         kctl get <pod_nick_name>[/<pod|svc|ing>] [<custom_arguments_for_kubectl>]
      -           kctl - (its alias for \`get\`, same as above)
    Describe resource details
      desc        kctl desc <pod_nick_name>[/<pod|svc|ing>] [<custom_arguments_for_kubectl>]
    Deleting a resource
      del         kctl del <pod_nick_name>[/<pod|svc|ing>] [<custom_arguments_for_kubectl>]
    Port forward
      pf          kctl pf <pod_nick_name> [<custom_arguments>]
    Exec into pod
      ex          kctl ex <pod_nick_name> [<custom_arguments>]
    SSH into container
      ssh         kctl ssh <pod_nick_name> <username_to_ssh> [<custom_arguments>]
    Apply a yaml file
      apply       kctl apply <file_path> [<custom_arguments>]
    Copy from container
      cp          kctl cp <pod_nick_name> <source_pod_path> <dest_path> [<custom_arguments>]
    Copy to container
      upcp        kctl upcp <pod_nick_name> <source_machine_path> <dest_pod_path> [<custom_arguments>]
    See logs of pod
      log         kctl log <pod_nick_name> [<custom_arguments_for_logs_as_of_kubectl>]
    Pass arguments as it to kubectl
      --          kctl -- <arguments_to_pass>
    Open k8 dashboard and copy dashboard token on clipboard
      ds          kctl ds [s]
    Update current kube config
      cf          kctl cf <key.nestedkey> <value> [<other_arguments_as_of_yq>]
    Update pod details
      pd          kctl pd <key.nestedkey> <value> [<other_arguments_as_of_yq>]
    Set current cluster
      ln          kctl ln <cluster_nick_name> [<kube_config_path_if_you_already_have>]

Flags:
  -v    verbose mode
  -vv   do \`set -x\` of bash, will print every single details
  -v0   Disable verbose completely 
        Disable confirmation input before delete
        Useful if you are piping output to different command
EOF
}

function getHelp {
  if [ `basename $0` == "kctl" ]; then
    echo "$(helpText)"
    echo ""
  else
    echo "exported KUBECONFIG to $KUBECONFIG"
  fi
}

COPY_CMD='xclip -selection c'
if ! command -v xclip > /dev/null 2>&1; then
  if command -v pbcopy > /dev/null 2>&1; then
    COPY_CMD='pbcopy -selection c'
  else
    echo "Please install pbcopy or xclip. Exiting..!"
    exit 1
  fi
fi

BROWSER=google-chrome

if ! command -v $BROWSER > /dev/null 2>&1; then
  BROWSER=open
  if command -v xdg-open > /dev/null 2>&1; then
    BROWSER=xdg-open
  elif [ -f /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome ]; then
    BROWSER=open -a "Google Chrome"
  fi
fi

PRV_DIR=$(pwd)
SFILE=`rlink ${BASH_SOURCE[0]}`
SDIR="$( cd "$( dirname "$SFILE" )" && pwd )"
cd $PRV_DIR
KCTL_CONFIG_DIR=${KCTL_CONFIG_DIR:-$SDIR/configs}
KCTL_POD_FILE=${KCTL_POD_FILE:-$SDIR/pod.yaml}

VERBOSE=

if [[ "$1" == -v* ]]; then
  if [ "$1" == "-vv" ]; then
    set -x
  elif [ "$1" == "-v0" ]; then
    VERBOSE=0
  else
    VERBOSE=1
  fi
  shift
fi

function getNSandPod {
  EKEY=$(echo "$1" | cut -d'/' -f1)
  APPLY_ON=$(echo "$1" | cut -d'/' -f2)
  NAME_SPACE=$(yq r $KCTL_POD_FILE $EKEY.ns)
  POD_NAME=$(yq r $KCTL_POD_FILE $EKEY.pod)
  if [ "${NAME_SPACE}" == "" ] || [ "${NAME_SPACE}" == "null" ]; then
    NAME_SPACE=ctsp
    if [ "$VERBOSE" != "0" ]; then
      echo "No info found for \`$EKEY.ns\`. To set, please run : \`kctl pd $EKEY.ns <namespace-name>\`"
      echo "For now, using default \`$EKEY.ns $NAME_SPACE\`."
    fi
  fi
  case "${APPLY_ON}"
  in
    ("ing")
      NAME_SPACE=$(yq r $KCTL_POD_FILE $EKEY.ingns)
      [ "$NAME_SPACE" == "null" ] && NAME_SPACE=apigw
    ;;
  esac
  if [ "$APPLY_ON" == "$EKEY" ]; then
    APPLY_ON=$(yq r $KCTL_POD_FILE $EKEY.applyon)
    [ "$APPLY_ON" == "null" ] && APPLY_ON=pod
  fi
  if [ "${POD_NAME}" == "" ] || [ "${POD_NAME}" == "null" ]; then
    if [ "$VERBOSE" != "0" ]; then
      echo "No info found for \`$EKEY.pod\`. To set, please run : \`kctl pd $EKEY.pod <podname_prefix>\`"
      echo "For now, using default \`$EKEY.pod $EKEY-\`"
    fi
    POD_NAME=${EKEY}-
  fi
  if [ "$APPLY_ON" == "pod" ]; then
    LABEL_FILTER=
    if [ "$VERBOSE" == "1" ]; then
      echo "RUNNING : kubectl get pod -n ${NAME_SPACE} $LABEL_FILTER | grep ${POD_NAME} | head -1 | awk '{ print \$1 }'"
    fi
    ACT_ENTITY=$(kubectl get pod -n ${NAME_SPACE} $LABEL_FILTER | grep ${POD_NAME} | head -1 | awk '{ print $1 }')
    if [ "$ACT_ENTITY" == "" ]; then
      POD_NAME=${EKEY}
      ACT_ENTITY=$(kubectl get pod -n $EKEY $LABEL_FILTER | grep ${POD_NAME} | head -1 | awk '{ print $1 }')
      if [ "$ACT_ENTITY" == "" ]; then
        for ns in $(kctl -v0 -- get namespaces | awk '{ print $1 }'); do
          if [ "$ns" != "NAME" ]; then
            ACT_ENTITY=$(kubectl get pod -n $ns $LABEL_FILTER | grep ${POD_NAME} | head -1 | awk '{ print $1 }')
            if [ "$ACT_ENTITY" != "" ]; then
              if [ "$VERBOSE" != "0" ]; then
                read -p "Pod \`$ACT_ENTITY\` found in namespace \`$ns\`. Should i remember for future? (yY/nN): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || continue
              fi
              NAME_SPACE=$ns
              yq w -i $KCTL_POD_FILE $EKEY.ns $ns
              yq w -i $KCTL_POD_FILE $EKEY.pod $POD_NAME
              break
            fi
          fi
        done
      else
        if [ "$VERBOSE" != "0" ]; then
          read -p "Pod \`$ACT_ENTITY\` found in namespace \`$EKEY\`. Should i remember for future? (yY/nN): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || continue
        fi
        NAME_SPACE=$EKEY
        yq w -i $KCTL_POD_FILE $EKEY.ns $EKEY
        yq w -i $KCTL_POD_FILE $EKEY.pod $POD_NAME
      fi
    fi
    if [ "$ACT_ENTITY" == "" ]; then
      echo "No pod found for \`$EKEY\`. To set, please run : \`kctl pd $EKEY.pod <pod-name>\`"
      exit 1
    fi
  else
    ACT_ENTITY=$(yq r $KCTL_POD_FILE $EKEY.$APPLY_ON)
    [ "$ACT_ENTITY" == "null" ] && ACT_ENTITY=$EKEY
  fi
}

function crud {
  if [ "$VERBOSE" != "0" ]; then echo RUNNING ON `basename $KUBECONFIG`; fi
  case "${2}"
  in
    ("ing")
      case "${3}"
      in
        ("all")
          for ns in ctsp apigw; do
            if [ "$VERBOSE" == "1" ]; then
              echo "RUNNING : kubectl -n $ns $1 ingresses \$(kubectl -n $ns get ingresses | tail -n +2 | awk '{print \$1}')"
            fi
            kubectl -n $ns $1 ingresses $(kubectl -n $ns get ingresses | tail -n +2 | awk '{print $1}')
          done
        ;;
      esac
    ;;
    (*)
      getNSandPod "$2"
      case "$APPLY_ON"
      in
        ("cm") APPLY_ON=configmap ;;
      esac
      if [ "$VERBOSE" != "0" ]; then
        if [ "$VERBOSE" == "1" ] || [ "$1" == "delete" ]; then
          echo RUNNING : kubectl -n ${NAME_SPACE} $1 "$APPLY_ON" "${@:3}" $ACT_ENTITY
        fi
        if [ "$1" == "delete" ]; then
          read -p "Continue? (yY/nN): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
        fi
      fi
      kubectl -n ${NAME_SPACE} $1 "$APPLY_ON" "${@:3}" $ACT_ENTITY
    ;;
  esac
}

export KUBECONFIG=`cat $SDIR/cluster`

function dopf {
    portmap=$(yq r $KCTL_POD_FILE $2.portmap)
    getNSandPod "$2"
    echo RUNNING : kubectl -n ${NAME_SPACE} port-forward "${@:3}" $APPLY_ON/$ACT_ENTITY $portmap
    dport=$(echo $portmap | cut -d':' -f1)
    hport=$(echo $portmap | cut -d':' -f2)
    hps=
    if [[ "$hport" == *"443"* ]];then hps="s"; fi
    kubectl -n ${NAME_SPACE} port-forward "${@:3}" $APPLY_ON/$ACT_ENTITY $portmap &
    while ! nc -z localhost $dport; do sleep 1; done
    "$BROWSER" "http$hps://localhost:$dport"
}

case "${1}"
in
    ("del")
      crud delete "${@:2}"
      ;;
    ("get"|"-")
      crud get "${@:2}"
      ;;
    ("desc")
      crud describe "${@:2}"
      ;;
    ("apply")
      if [ "$VERBOSE" != "0" ]; then echo RUNNING ON `basename $KUBECONFIG`; fi
      if [ "$VERBOSE" == "1" ]; then
        echo RUNNING : kubectl apply -f "${@:3}" ${2}
      fi
      kubectl apply -f "${@:3}" ${2}
      ;;
    ("ex")
      if [ "$VERBOSE" != "0" ]; then echo RUNNING ON `basename $KUBECONFIG`; fi
      getNSandPod "$2"
      if [ "$VERBOSE" == "1" ]; then
        echo 'RUNNING : kubectl -n '${NAME_SPACE}' exec -it '$ACT_ENTITY' -- '
      fi
      CMD=bash
      if [ "$3" == "" ];then
        CMD=$(yq r $KCTL_POD_FILE $EKEY.exas)
        if [ "$CMD" == "null" ];then
          if [ "$4" == "" ];then
            CMD=bash
          else
            CMD=bash\ ${@:4}
          fi
        fi
      else
        CMD="$3"
        if [ "$4" != "" ];then
          CMD=$3\ ${@:4}
        fi
      fi
      if [ "$4" == "" ];then
        kubectl -n ${NAME_SPACE} exec -it $ACT_ENTITY -- "$CMD"
        if [ "$?" == "126" ]; then
          yq w -i $KCTL_POD_FILE $EKEY.exas sh
          kubectl -n ${NAME_SPACE} exec -it $ACT_ENTITY -- sh
        fi
      else
        kubectl -n ${NAME_SPACE} exec -it $ACT_ENTITY -- $3 "${@:4}"
      fi
      ;;
    ("ssh")
      if [ "$VERBOSE" != "0" ]; then echo RUNNING ON `basename $KUBECONFIG`; fi
      getNSandPod "$2"
      CONTAINER_NAME=$(yq r $KCTL_POD_FILE $EKEY.cont)
      if [ "$VERBOSE" == "1" ]; then
        echo RUNNING : kubectl-ssh "${@:4}" -n ${NAME_SPACE} -u $3 -c ${CONTAINER_NAME} $ACT_ENTITY
      fi
      $SDIR/vendor/kubectl-ssh "${@:4}" -n ${NAME_SPACE} -u $3 -c ${CONTAINER_NAME} $ACT_ENTITY
      ;;
    ("log")
      if [ "$VERBOSE" != "0" ]; then echo RUNNING ON `basename $KUBECONFIG`; fi
      getNSandPod "$2"
      if [ "$VERBOSE" == "1" ]; then
        echo RUNNING : kubectl -n ${NAME_SPACE} logs "${@:3}" --all-containers $ACT_ENTITY
      fi
      kubectl -n ${NAME_SPACE} logs "${@:3}" --all-containers $ACT_ENTITY
      ;;
    ("pf")
      if [ "$VERBOSE" != "0" ]; then echo RUNNING ON `basename $KUBECONFIG`; fi
      dopf $1 $2
      wait
      ;;
    ("cp"|"upcp")
      if [ "$VERBOSE" != "0" ]; then echo RUNNING ON `basename $KUBECONFIG`; fi
      getNSandPod "$2"
      from=${NAME_SPACE}/$ACT_ENTITY:$3
      to=$4
      if [ "$1" == "upcp" ]; then
        from=$3
        to=${NAME_SPACE}/$ACT_ENTITY:$4
      fi
      if [ "$VERBOSE" == "1" ]; then
        echo RUNNING : kubectl cp "${@:5}" $from $to
      fi
      kubectl cp "${@:5}" $from $to
      ;;
    ("ds")
      if [ "$VERBOSE" != "0" ]; then echo RUNNING ON `basename $KUBECONFIG`; fi
      KCTL_ds_token=$(yq r $KUBECONFIG ds.token)
      if [ "$KCTL_ds_token" == "null" ]; then
        KCTL_ds_token=$(kubectl describe secret $(kubectl get secrets | grep kubernetes-dashboard- | head -1 | awk '{ print $1 }') | tail -1 | awk '{print $2}')
        if [ "${#KCTL_ds_token}" -gt 5 ]; then
          yq w -i $KUBECONFIG ds.token "${KCTL_ds_token}"
        else
          echo "Dashboard token is not available. To set, please run : \`kctl cf ds.token <long_dashboard_token>\`"
          KCTL_ds_token=
        fi
      fi
      if [ "$KCTL_ds_token" != "" ]; then
        echo $KCTL_ds_token | $COPY_CMD
      fi
      if [[ "$2" == *s* ]]; then
        echo "Token copied to cliboard."
      else
        url=$(yq r $KUBECONFIG ds.url)
        if [ "$url" == "null" ]; then
          dopf pf ds
          wait
        else
          "$BROWSER" $(yq r $KUBECONFIG ds.url)
        fi
      fi
      ;;
    ("cf")
      if [ "$VERBOSE" != "0" ]; then echo RUNNING ON `basename $KUBECONFIG`; fi
      if [ "$2" != "" ] && [ "$3" != "" ]; then
        if [ ! -f $KUBECONFIG ]; then
          echo "Creating new config file: $KUBECONFIG"
          yq n "${@:2}" > $KUBECONFIG
        else
          yq w -i $KUBECONFIG "${@:2}"
        fi
      fi
      ;;
    ("pd")
      if [ "$2" != "" ] && [ "$3" != "" ]; then
        yq w -i $KCTL_POD_FILE "${@:2}"
      fi
      ;;
    ("--")
      if [ "$VERBOSE" != "0" ]; then echo RUNNING ON `basename $KUBECONFIG`; fi
      kubectl "${@:2}"
      ;;
    ("ln")
      if [ "$2" == "" ]; then
        echo CURRENTLY ON `basename $KUBECONFIG`
        exit 0
      fi
      if [ "$3" != "" ]; then
        cp $3 ${KCTL_CONFIG_DIR}/${2}
        echo "${KCTL_CONFIG_DIR}/${2}" > $SDIR/cluster
      fi
      echo "$KCTL_CONFIG_DIR/$2" > $SDIR/cluster
      echo SWITCHED TO $2
      ;;
    (*)
      getHelp
      ;;
esac
