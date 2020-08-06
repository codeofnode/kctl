PRV_DIR=$(pwd)
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

SFILE=`rlink $0`
DIR="$(cd `dirname $SFILE` && pwd)"
source $DIR/utils.sh

cd $DIR
mkdir -p vendor

if ! command -v xclip > /dev/null 2>&1; then
  if ! command -v pbcopy > /dev/null 2>&1; then
    echo "WARNING -----> xclip / pbcopy is not installed. Please install to copy tokens automatically."
    if command -v apt-get > /dev/null 2>&1; then
      echo sudo apt-get install xclip
    fi
  fi
fi

YQ_CMD='yq'
if ! command -v $YQ_CMD > /dev/null 2>&1; then
  if [ ! -f "vendor/yq" ]; then
    curl -Lo vendor/yq https://github.com/mikefarah/yq/releases/download/3.3.2/yq_`uname | tr '[:upper:]' '[:lower:]'`_amd64
    chmod +x vendor/yq
  fi
  YQ_CMD=vendor/yq
fi

KCTL_KEY=_kctl
KCTL_POD_FILE=${KCTL_POD_FILE:-$1}
[ -z $KCTL_POD_FILE ] && KCTL_POD_FILE=$DIR/pod.yaml
[ ! -f $KCTL_POD_FILE ] && touch $KCTL_POD_FILE
KCTL_KUBECONFIGS_DIR=${KCTL_KUBECONFIGS_DIR:-`$YQ_CMD r $KCTL_POD_FILE $KCTL_KEY.kubeconfigs_dir`}
if_null $KCTL_KUBECONFIGS_DIR && KCTL_KUBECONFIGS_DIR=$HOME/.kube

if [ ! -f vendor/kubectl-ssh ]; then
  curl -o vendor/kubectl-ssh https://raw.githubusercontent.com/jordanwilson230/kubectl-plugins/master/kubectl-ssh
  sed -i.bak -e 's/dh:p:n:u:c/dc:p:n:u:h/' -- vendor/kubectl-ssh && rm -- vendor/kubectl-ssh.bak
  chmod +x vendor/kubectl-ssh
fi

if [ ! -f /usr/local/bin/kctl ]; then
  chmod +x $DIR/kctl.sh
  DUMP_IN=$HOME/.local/bin
  if [ ! -d $DUMP_IN ]; then
    DUMP_IN=$HOME/bin
  fi
  if [ -d $DUMP_IN ]; then
    rm -f $DUMP_IN/kctl
    ln -s $DIR/kctl.sh $DUMP_IN/kctl
    if ! command -v kctl > /dev/null 2>&1; then
      echo "Make sure to have $DUMP_IN into your \$PATH."
    fi
  else
    echo sudo ln -s $DIR/kctl.sh /usr/local/bin/kctl
  fi
fi

mkdir -p ${KCTL_KUBECONFIGS_DIR}
if [ ! -f $DIR/cluster ]; then
  filep=${2:-config}
  bn=${3:-`basename "$filep"`}
  if [ "$2" != "" ]; then
    cp $2 ${KCTL_KUBECONFIGS_DIR}/${bn}
  fi
  echo "${KCTL_KUBECONFIGS_DIR}/${bn}" > $DIR/cluster
fi
cd $PRV_DIR
