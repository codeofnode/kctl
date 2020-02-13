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
  curl -Lo vendor/yq https://github.com/mikefarah/yq/releases/download/2.4.1/yq_linux_amd64
  chmod +x vendor/yq
  YQ_CMD=vendor/yq
fi

KCTL_KEY=_kctl
KCTL_POD_FILE=${KCTL_POD_FILE:-$1}
[ -z $KCTL_POD_FILE ] && KCTL_POD_FILE=$DIR/pod.yaml
[ ! -f $KCTL_POD_FILE ] && touch $KCTL_POD_FILE
KCTL_KUBECONFIGS_DIR=${KCTL_KUBECONFIGS_DIR:-`$YQ_CMD r $KCTL_POD_FILE $KCTL_KEY.kubeconfigs_dir`}
if_null $KCTL_KUBECONFIGS_DIR && KCTL_KUBECONFIGS_DIR=$DIR/configs

if [ ! -f vendor/kubectl-ssh ]; then
  curl -o vendor/kubectl-ssh https://raw.githubusercontent.com/jordanwilson230/kubectl-plugins/master/kubectl-ssh
  sed -i.bak -e 's/dh:p:n:u:c/dc:p:n:u:h/' -- vendor/kubectl-ssh && rm -- vendor/kubectl-ssh.bak
  chmod +x vendor/kubectl-ssh
fi

if [ ! -f /usr/local/bin/kctl ]; then
  chmod +x $DIR/kctl.sh
  if [ -d $HOME/bin ]; then
    ln -s $DIR/kctl.sh $HOME/bin/kctl
    if ! command -v kctl > /dev/null 2>&1; then
      echo "Make sure to have $HOME/bin into your \$PATH."
    fi
  else
    echo sudo ln -s $DIR/kctl.sh /usr/local/bin/kctl
  fi
fi

mkdir -p ${KCTL_KUBECONFIGS_DIR}
if [ ! -f $DIR/cluster ]; then
  filep=${2:-dev}
  bn=${3:-`basename "$filep"`}
  if [ "$2" != "" ]; then
    cp $2 ${KCTL_KUBECONFIGS_DIR}/${bn}
  fi
  echo "${KCTL_KUBECONFIGS_DIR}/${bn}" > $DIR/cluster
fi
cd $PRV_DIR
