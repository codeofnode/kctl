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

if ! command -v yq > /dev/null 2>&1; then
  curl -Lo vendor/yq https://github.com/mikefarah/yq/releases/download/2.4.1/yq_linux_amd64
  chmod +x vendor/yq
fi

KCTL_CONFIG_DIR=${KCTL_CONFIG_DIR:-$DIR/configs}

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
    exit 1
  fi
fi

mkdir -p ${KCTL_CONFIG_DIR}
if [ ! -f $DIR/cluster ]; then
  filep=${1:-dev}
  bn=${2:-`basename "$filep"`}
  if [ "$1" != "" ]; then
    cp $1 ${KCTL_CONFIG_DIR}/${bn}
  fi
  echo "${KCTL_CONFIG_DIR}/${bn}" > $DIR/cluster
fi
cd $PRV_DIR
