PRV_DIR=$pwd
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd $DIR
mkdir -p vendor

if ! command -v xclip > /dev/null 2>&1; then
  if ! command -v pbcopy > /dev/null 2>&1; then
    echo "WARNING -----> xclip / pbcopy is not installed. Please install to copy tokens automatically."
    if command -v apt-get > /dev/null 2>&1; then
      echo sudo apt-get install xclip
      exit 1
    fi
  fi
fi

if ! command -v yq > /dev/null 2>&1; then
  if command -v snap > /dev/null 2>&1; then
    echo sudo snap install yq
    exit 1
  elif command -v brew > /dev/null 2>&1; then
    brew install yq
  elif command -v apt-get > /dev/null 2>&1; then
    echo sudo add-apt-repository ppa:rmescandon/yq
    echo sudo apt-get update
    echo sudo apt-get install yq -y
    exit 1
  else
    echo "Please install yq first. https://github.com/mikefarah/yq"
    exit 1
  fi
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
      echo "Make sure to have $HOME/bin into your \$PATH. And retry."
      exit 1
    fi
  else
    echo sudo ln -s $DIR/kctl.sh /usr/local/bin/kctl
    exit 1
  fi
fi

mkdir -p ${KCTL_CONFIG_DIR}
if [ ! -f $DIR/cluster ]; then
  filep=${1:-dev}
  bn=`basename "$filep"`
  if [ "$1" != "" ]; then
    cp $1 ${KCTL_CONFIG_DIR}/${bn}
  fi
  echo "${KCTL_CONFIG_DIR}/${bn}" > $DIR/cluster
fi
cd $PRV_DIR
