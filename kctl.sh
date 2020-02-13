#!/bin/bash

rlink() {
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

TOOL_NAME=kctl

helpText() {
cat <<EOF
$TOOL_NAME is a lightweight tool to manage multiple clusters of k8, and making life easy.

Usage:
  $TOOL_NAME [flags] command

Available Commands:
    Getting help
      help        $TOOL_NAME help get
    Get a resource details
      get         $TOOL_NAME get <pod_nick_name>[/<pod|svc|ing>] [<custom_arguments_for_kubectl>]
      -           $TOOL_NAME - (its alias for \`get\`, same as above)
    Describe resource details
      desc        $TOOL_NAME desc <pod_nick_name>[/<pod|svc|ing>] [<custom_arguments_for_kubectl>]
    Deleting a resource
      del         $TOOL_NAME del <pod_nick_name>[/<pod|svc|ing>] [<custom_arguments_for_kubectl>]
    Port forward
      pf          $TOOL_NAME pf <pod_nick_name> [<custom_arguments>]
    Exec into pod
      ex          $TOOL_NAME ex <pod_nick_name> [<custom_arguments>]
    SSH into container
      ssh         $TOOL_NAME ssh <pod_nick_name> <username_to_ssh> [<custom_arguments>]
    Apply a yaml file
      apply       $TOOL_NAME apply <file_path> [<custom_arguments>]
    Copy from container
      cp          $TOOL_NAME cp <pod_nick_name> <source_pod_path> <dest_path> [<custom_arguments>]
    Copy to container
      upcp        $TOOL_NAME upcp <pod_nick_name> <source_machine_path> <dest_pod_path> [<custom_arguments>]
    See logs of pod
      log         $TOOL_NAME log <pod_nick_name> [<custom_arguments_for_logs_as_of_kubectl>]
    Pass arguments as it to kubectl
      --          $TOOL_NAME -- <arguments_to_pass>
    Open k8 dashboard and copy dashboard token on clipboard
      ds          $TOOL_NAME ds [s]
    Update current kube config
      cf          $TOOL_NAME cf <key.nestedkey> <value> [<other_arguments_as_of_yq>]
    Update pod details
      pd          $TOOL_NAME pd <key.nestedkey> <value> [<other_arguments_as_of_yq>]
    Set current cluster
      ln          $TOOL_NAME ln <cluster_nick_name> [<kube_config_path_if_you_already_have>]

Flags:
  -v    verbose mode
  -vv   do \`set -x\` of bash, will print every single details
  -v0   Disable verbose completely 
        Disable confirmation input before delete
        Useful if you are piping output to different command
EOF
}

getHelp() {
  if [ `basename $0` = "$TOOL_NAME" ]; then
    echo "$(helpText)"
    echo ""
  else
    echo "exported KUBECONFIG to $KUBECONFIG"
  fi
}

COPY_CMD='xclip -selection c'

check_xclip() {
  if ! command -v xclip > /dev/null 2>&1; then
    if command -v pbcopy > /dev/null 2>&1; then
      COPY_CMD='pbcopy -selection c'
    else
      echo "Please install pbcopy or xclip. Exiting..!"
      exit 1
    fi
  fi
}

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
KCTL_POD_FILE=${KCTL_POD_FILE:-$SDIR/pod.yaml}

YQ_CMD='yq'
if ! command -v $YQ_CMD > /dev/null 2>&1; then
  YQ_CMD="$SDIR/vendor/yq"
fi

VERBOSE=

if [ "$1" = "-vv" ]; then
  set -x
  shift
elif [ "$1" = "-v0" ]; then
  VERBOSE=0
  shift
elif [ "$1" = "-v" ]; then
  VERBOSE=1
  shift
fi

KCTL_KEY=_kctl
KCTL_KUBECONFIGS_DIR=${KCTL_KUBECONFIGS_DIR:-`$YQ_CMD r $KCTL_POD_FILE $KCTL_KEY.kubeconfigs_dir`}
([ "$KCTL_KUBECONFIGS_DIR" = "" ] || [ "$KCTL_KUBECONFIGS_DIR" = "null" ]) && KCTL_KUBECONFIGS_DIR=$DIR/configs
KCTL_DEFAULT_NS=${KCTL_DEFAULT_NS:-`$YQ_CMD r $KCTL_POD_FILE $KCTL_KEY.default_ns`}
([ "$KCTL_DEFAULT_NS" = "" ] || [ "$KCTL_DEFAULT_NS" = "null" ]) && KCTL_DEFAULT_NS=default
KCTL_DEFAULT_ING_NS=${KCTL_DEFAULT_ING_NS:-`$YQ_CMD r $KCTL_POD_FILE $KCTL_KEY.default_ing_ns`}
([ "$KCTL_DEFAULT_ING_NS" = "" ] || [ "$KCTL_DEFAULT_ING_NS" = "null" ]) && KCTL_DEFAULT_ING_NS=default

getNSandPod() {
  EKEY=$(echo "$1" | cut -d'/' -f1)
  APPLY_ON=$(echo "$1" | cut -d'/' -f2)
  NAME_SPACE=$($YQ_CMD r $KCTL_POD_FILE $EKEY.ns)
  POD_NAME=$($YQ_CMD r $KCTL_POD_FILE $EKEY.pod)
  if [ "${NAME_SPACE}" = "" ] || [ "${NAME_SPACE}" = "null" ]; then
    NAME_SPACE=default
    if [ "$VERBOSE" != "0" ]; then
      echo "No info found for \`$EKEY.ns\`. To set, please run : \`$TOOL_NAME pd $EKEY.ns <namespace-name>\`"
      echo "For now, using default \`$EKEY.ns $NAME_SPACE\`."
    fi
  fi
  case "${APPLY_ON}"
  in
    ("ing")
      NAME_SPACE=$($YQ_CMD r $KCTL_POD_FILE $EKEY.ingns)
      [ "$NAME_SPACE" = "null" ] && NAME_SPACE=default
    ;;
  esac
  if [ "$APPLY_ON" = "$EKEY" ]; then
    APPLY_ON=$($YQ_CMD r $KCTL_POD_FILE $EKEY.applyon)
    [ "$APPLY_ON" = "null" ] && APPLY_ON=pod
  fi
  if [ "${POD_NAME}" = "" ] || [ "${POD_NAME}" = "null" ]; then
    if [ "$VERBOSE" != "0" ]; then
      echo "No info found for \`$EKEY.pod\`. To set, please run : \`$TOOL_NAME pd $EKEY.pod <podname_prefix>\`"
      echo "For now, using default \`$EKEY.pod $EKEY-\`"
    fi
    POD_NAME=${EKEY}-
  fi
  if [ "$APPLY_ON" = "pod" ]; then
    LABEL_FILTER=
    if [ "$1" = "cm" ]; then
      LABEL_FILTER=-l\ $($YQ_CMD r $KCTL_POD_FILE $EKEY.label)
    fi
    if [ "$VERBOSE" = "1" ]; then
      echo "RUNNING : kubectl get pod -n ${NAME_SPACE} $LABEL_FILTER | grep ${POD_NAME} | head -1 | awk '{ print \$1 }'"
    fi
    ACT_ENTITY=$(kubectl get pod -n ${NAME_SPACE} $LABEL_FILTER | grep ${POD_NAME} | head -1 | awk '{ print $1 }')
    if [ "$ACT_ENTITY" = "" ]; then
      POD_NAME=${EKEY}
      ACT_ENTITY=$(kubectl get pod -n $EKEY $LABEL_FILTER | grep ${POD_NAME} | head -1 | awk '{ print $1 }')
      if [ "$ACT_ENTITY" = "" ]; then
        for ns in $(kubectl get namespaces | awk '{ print $1 }'); do
          if [ "$ns" != "NAME" ]; then
            ACT_ENTITY=$(kubectl get pod -n $ns $LABEL_FILTER | grep ${POD_NAME} | head -1 | awk '{ print $1 }')
            if [ "$ACT_ENTITY" != "" ]; then
              if [ "$VERBOSE" != "0" ]; then
                read -p "Pod \`$ACT_ENTITY\` found in namespace \`$ns\`. Should i remember for future? (yY/nN): " confirm && [[ $confirm = [yY] || $confirm = [yY][eE][sS] ]] || continue
              fi
              NAME_SPACE=$ns
              $YQ_CMD w -i $KCTL_POD_FILE $EKEY.ns $ns
              $YQ_CMD w -i $KCTL_POD_FILE $EKEY.pod $POD_NAME
              break
            fi
          fi
        done
      else
        if [ "$VERBOSE" != "0" ]; then
          read -p "Pod \`$ACT_ENTITY\` found in namespace \`$EKEY\`. Should i remember for future? (yY/nN): " confirm && [[ $confirm = [yY] || $confirm = [yY][eE][sS] ]] || true
        fi
        NAME_SPACE=$EKEY
        $YQ_CMD w -i $KCTL_POD_FILE $EKEY.ns $EKEY
        $YQ_CMD w -i $KCTL_POD_FILE $EKEY.pod $POD_NAME
      fi
    fi
    if [ "$ACT_ENTITY" = "" ]; then
      echo "No pod found for \`$EKEY\`. To set, please run : \`$TOOL_NAME pd $EKEY.pod <pod-name>\`"
      exit 1
    fi
  else
    ACT_ENTITY=$($YQ_CMD r $KCTL_POD_FILE $EKEY.$APPLY_ON)
    [ "$ACT_ENTITY" = "null" ] && ACT_ENTITY=$EKEY
  fi
}

crud() {
  if [ "$VERBOSE" != "0" ]; then echo RUNNING ON `basename $KUBECONFIG`; fi
  case "${2}"
  in
    ("ing")
      case "${3}"
      in
        ("all")
          for ns in default; do
            if [ "$VERBOSE" = "1" ]; then
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
        if [ "$VERBOSE" = "1" ] || [ "$1" = "delete" ]; then
          echo RUNNING : kubectl -n ${NAME_SPACE} $1 "$APPLY_ON" "${@:3}" $ACT_ENTITY
        fi
        if [ "$1" = "delete" ]; then
          read -p "Continue? (yY/nN): " confirm && [[ $confirm = [yY] || $confirm = [yY][eE][sS] ]] || exit 1
        fi
      fi
      kubectl -n ${NAME_SPACE} $1 "$APPLY_ON" "${@:3}" $ACT_ENTITY
    ;;
  esac
}

export KUBECONFIG=`cat $SDIR/cluster`

dopf() {
    portmap=$($YQ_CMD r $KCTL_POD_FILE $2.portmap)
    getNSandPod "$2"
    echo RUNNING : kubectl -n ${NAME_SPACE} port-forward "${@:3}" $APPLY_ON/$ACT_ENTITY $portmap
    dport=$(echo $portmap | cut -d':' -f1)
    hport=$(echo $portmap | cut -d':' -f2)
    hps=
    if [[ "$hport" = *"443"* ]];then hps="s"; fi
    kubectl -n ${NAME_SPACE} port-forward "${@:3}" $APPLY_ON/$ACT_ENTITY $portmap &
    while ! nc -z localhost $dport; do sleep 1; done
    "$BROWSER" "http$hps://localhost:$dport"
}

set_container() {
  CONTAINER_NAME=$($YQ_CMD r $KCTL_POD_FILE $EKEY.cont)
  [ $CONTAINER_NAME = "null" ] && CONTAINER_NAME=""
  [ ! -z $CONTAINER_NAME ] && CONTAINER_NAME="-c $CONTAINER_NAME"
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
      if [ "$VERBOSE" = "1" ]; then
        echo RUNNING : kubectl apply -f ${2} "${@:3}"
      fi
      if [ "$VERBOSE" != "0" ]; then
        read -p "Continue? (yY/nN): " confirm && [[ $confirm = [yY] || $confirm = [yY][eE][sS] ]] || exit 1
      fi
      kubectl apply -f ${2} "${@:3}"
      ;;
    ("ex")
      if [ "$VERBOSE" != "0" ]; then echo RUNNING ON `basename $KUBECONFIG`; fi
      getNSandPod "$2"
      set_container
      if [ "$VERBOSE" = "1" ]; then
        echo 'RUNNING : kubectl -n '${NAME_SPACE}' exec -it '$ACT_ENTITY' '${CONTAINER_NAME}' -- '
      fi
      CMD=bash
      if [ "$3" = "" ];then
        CMD=$($YQ_CMD r $KCTL_POD_FILE $EKEY.exas)
        if [ "$CMD" = "null" ];then
          if [ "$4" = "" ];then
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
      if [ "$4" = "" ];then
        kubectl -n ${NAME_SPACE} exec -it $ACT_ENTITY ${CONTAINER_NAME} -- $CMD
        if [ "$?" = "126" ]; then
          if [ "$VERBOSE" != "0" ]; then
            read -p "Command not found in pod. Should i remember reset it to \`sh\`? (yY/nN): " confirm && \
              [[ $confirm = [yY] || $confirm = [yY][eE][sS] ]] && \
              $YQ_CMD w -i $KCTL_POD_FILE $EKEY.exas sh && \
              $YQ_CMD w -i $KCTL_POD_FILE $EKEY._prev_exas "$CMD"
          fi
          kubectl -n ${NAME_SPACE} exec -it $ACT_ENTITY ${CONTAINER_NAME} -- sh
        fi
      else
        kubectl -n ${NAME_SPACE} exec -it $ACT_ENTITY ${CONTAINER_NAME} -- $3 "${@:4}"
      fi
      ;;
    ("ssh")
      if [ "$VERBOSE" != "0" ]; then echo RUNNING ON `basename $KUBECONFIG`; fi
      getNSandPod "$2"
      set_container
      if [ "$VERBOSE" = "1" ]; then
        echo RUNNING : kubectl-ssh "${@:4}" -n ${NAME_SPACE} -u $3 ${CONTAINER_NAME} $ACT_ENTITY
      fi
      $SDIR/vendor/kubectl-ssh "${@:4}" -n ${NAME_SPACE} -u $3 ${CONTAINER_NAME} $ACT_ENTITY
      ;;
    ("log")
      if [ "$VERBOSE" != "0" ]; then echo RUNNING ON `basename $KUBECONFIG`; fi
      getNSandPod "$2"
      cmds="${@:3}"
      if [[ "$cmds" != *"--tail="* ]]; then
        if [ "${cmds}" = "" ]; then
          cmds="--tail=30"
        else
          cmds="--tail=30 ${cmds}"
        fi
      fi
      if [ "$VERBOSE" = "1" ]; then
        echo RUNNING : kubectl -n ${NAME_SPACE} logs $ACT_ENTITY --all-containers $cmds
      fi
      kubectl -n ${NAME_SPACE} logs $ACT_ENTITY --all-containers $cmds
      ;;
    ("pf")
      if [ "$VERBOSE" != "0" ]; then echo RUNNING ON `basename $KUBECONFIG`; fi
      dopf $1 $2
      wait
      ;;
    ("cp"|"upcp")
      if [ "$VERBOSE" != "0" ]; then echo RUNNING ON `basename $KUBECONFIG`; fi
      getNSandPod "$2"
      set_container
      from="${CONTAINER_NAME} ${NAME_SPACE}/$ACT_ENTITY:$3"
      to=$4
      if [ "$1" = "upcp" ]; then
        from=$3
        to="${CONTAINER_NAME} ${NAME_SPACE}/$ACT_ENTITY:$4"
      fi
      if [ "$VERBOSE" = "1" ]; then
        echo RUNNING : kubectl cp "${@:5}" $from $to
      fi
      kubectl cp "${@:5}" $from $to
      ;;
    ("ds")
      if [ "$VERBOSE" != "0" ]; then echo RUNNING ON `basename $KUBECONFIG`; fi
      KCTL_ds_token=$($YQ_CMD r $KUBECONFIG ds.token)
      if [ "$KCTL_ds_token" = "null" ]; then
        KCTL_ds_token=$(kubectl describe secret $(kubectl get secrets | grep kubernetes-dashboard- | head -1 | awk '{ print $1 }') | tail -1 | awk '{print $2}')
        if [ "${#KCTL_ds_token}" -gt 5 ]; then
          $YQ_CMD w -i $KUBECONFIG ds.token "${KCTL_ds_token}"
        else
          echo "Dashboard token is not available. To set, please run : \`$TOOL_NAME cf ds.token <long_dashboard_token>\`"
          KCTL_ds_token=
        fi
      fi
      if [ "$KCTL_ds_token" != "" ]; then
        check_xclip
        echo $KCTL_ds_token | $COPY_CMD
      fi
      if [[ "$2" = *s* ]]; then
        echo "Token copied to cliboard."
      else
        url=$($YQ_CMD r $KUBECONFIG ds.url)
        if [ "$url" = "null" ]; then
          dopf pf ds
          wait
        else
          "$BROWSER" $($YQ_CMD r $KUBECONFIG ds.url)
        fi
      fi
      ;;
    ("cf")
      if [ "$VERBOSE" != "0" ]; then echo RUNNING ON `basename $KUBECONFIG`; fi
      if [ "$2" != "" ] && [ "$3" != "" ]; then
        if [ ! -f $KUBECONFIG ]; then
          echo "Creating new config file: $KUBECONFIG"
          $YQ_CMD n "${@:2}" > $KUBECONFIG
        else
          $YQ_CMD w -i $KUBECONFIG "${@:2}"
        fi
      fi
      ;;
    ("pd")
      if [ "$2" != "" ] && [ "$3" != "" ]; then
        $YQ_CMD w -i $KCTL_POD_FILE "${@:2}"
      fi
      ;;
    ("--")
      if [ "$VERBOSE" != "0" ]; then echo RUNNING ON `basename $KUBECONFIG`; fi
      case "${2}"
      in
        ("delete"|"apply"|"create")
          if [ "$VERBOSE" != "0" ]; then
            read -p "Continue? (yY/nN): " confirm && [[ $confirm = [yY] || $confirm = [yY][eE][sS] ]] || exit 1
          fi
        ;;
      esac
      kubectl "${@:2}"
      ;;
    ("ln")
      if [ "$2" = "" ]; then
        echo CURRENTLY ON `basename $KUBECONFIG`
        exit 0
      fi
      if [ "$3" != "" ]; then
        cp $3 ${KCTL_KUBECONFIGS_DIR}/${2}
        echo "${KCTL_KUBECONFIGS_DIR}/${2}" > $SDIR/cluster
      fi
      echo "${KCTL_KUBECONFIGS_DIR}/$2" > $SDIR/cluster
      echo SWITCHED TO $2
      ;;
    (*)
      getHelp
      ;;
esac
