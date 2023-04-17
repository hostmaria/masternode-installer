#!/bin/bash

TMP_FOLDER=$(mktemp -d)
CONFIG_FILE="maria.conf"
maria_DAEMON="/usr/local/bin/mariad"
maria_CLI="/usr/local/bin/maria-cli"
maria_REPO="https://github.com/hostmaria/mariacoin.git"
maria_PARAMS="https://github.com/hostmaria/mariacoin/releases/download/v5.5.1/util.zip"
maria_LATEST_RELEASE="https://github.com/hostmaria/mariacoin/releases/download/v5.5.1/maria-5.5.1-ubuntu18-daemon.zip"
COIN_BOOTSTRAP='https://bootstrap.mariacoin.com/boot_strap.tar.gz'
COIN_ZIP=$(echo $maria_LATEST_RELEASE | awk -F'/' '{print $NF}')
COIN_CHAIN=$(echo $COIN_BOOTSTRAP | awk -F'/' '{print $NF}')
COIN_NAME='maria'
CONFIGFOLDER='.maria'
COIN_BOOTSTRAP_NAME='boot_strap.tar.gz'

DEFAULT_maria_PORT=47773
DEFAULT_maria_RPC_PORT=47774
DEFAULT_maria_USER="maria"
maria_USER="maria"
NODE_IP=NotCheckedYet
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

function download_bootstrap() {
  echo -e "${GREEN}Downloading and Installing $COIN_NAME BootStrap${NC}"
  mkdir -p /opt/chaintmp/
  cd /opt/chaintmp >/dev/null 2>&1
  rm -rf boot_strap* >/dev/null 2>&1
  wget $COIN_BOOTSTRAP >/dev/null 2>&1
  cd /home/$maria_USER/$CONFIGFOLDER
  rm -rf sporks zerocoin blocks database chainstate peers.dat
  cd /opt/chaintmp >/dev/null 2>&1
  tar -zxf $COIN_BOOTSTRAP_NAME
  cp -Rv cache/* /home/$maria_USER/$CONFIGFOLDER/ >/dev/null 2>&1
  chown -Rv $maria_USER /home/$maria_USER/$CONFIGFOLDER >/dev/null 2>&1
  cd ~ >/dev/null 2>&1
  rm -rf /opt/chaintmp >/dev/null 2>&1
}

function install_params() {
  echo -e "${GREEN}Downloading and Installing $COIN_NAME Params Files${NC}"
  mkdir -p /opt/tmp/
  cd /opt/tmp
  rm -rf util* >/dev/null 2>&1
  wget $maria_PARAMS >/dev/null 2>&1
  unzip util.zip >/dev/null 2>&1
  chmod -Rv 777 /opt/tmp/util/fetch-params.sh >/dev/null 2>&1
  runuser -l $maria_USER -c '/opt/tmp/util/./fetch-params.sh' >/dev/null 2>&1
}

purgeOldInstallation() {
    echo -e "${GREEN}Searching and removing old $COIN_NAME Daemon{NC}"
    #kill wallet daemon
	systemctl stop $maria_USER.service
	
	#Clean block chain for Bootstrap Update
    cd $CONFIGFOLDER >/dev/null 2>&1
    rm -rf *.pid *.lock database sporks chainstate zerocoin blocks >/dev/null 2>&1
	
    #remove binaries and maria utilities
    cd /usr/local/bin && sudo rm maria-cli maria-tx mariad > /dev/null 2>&1 && cd
    echo -e "${GREEN}* Done${NC}";
}


function compile_error() {
if [ "$?" -gt "0" ];
 then
  echo -e "${RED}Failed to compile $@. Please investigate.${NC}"
  exit 1
fi
}


function checks() {
if [[ $(lsb_release -d) != *18.04* ]]; then
  echo -e "${RED}You are not running Ubuntu 18.04. Installation is cancelled.${NC}"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}$0 must be run as root.${NC}"
   exit 1
fi

if [ -n "$(pidof $maria_DAEMON)" ] || [ -e "$maria_DAEMON" ] ; then
  echo -e "${GREEN}\c"
  echo -e "maria is already installed. Exiting..."
  echo -e "{NC}"
  exit 1
fi
}

function prepare_system() {

echo -e "Prepare the system to install maria master node."
apt-get update >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get update > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y -qq upgrade >/dev/null 2>&1
apt install -y software-properties-common >/dev/null 2>&1
echo -e "${GREEN}Adding Pivx PPA repository"
apt-add-repository -y ppa:pivx/pivx >/dev/null 2>&1
echo -e "Installing required packages, it may take some time to finish.${NC}"
apt-get update >/dev/null 2>&1
apt-get upgrade >/dev/null 2>&1
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" git make build-essential libtool bsdmainutils autotools-dev autoconf pkg-config automake python3 libssl-dev libgmp-dev libevent-dev libboost-all-dev libdb4.8-dev libdb4.8++-dev ufw fail2ban pwgen curl unzip >/dev/null 2>&1
NODE_IP=$(curl -s4 icanhazip.com)
clear
if [ "$?" -gt "0" ];
  then
    echo -e "${RED}Not all required packages were installed properly. Try to install them manually by running the following commands:${NC}\n"
    echo "apt-get update"
    echo "apt-get -y upgrade"
    echo "apt -y install software-properties-common"
    echo "apt-add-repository -y ppa:pivx/pivx"
    echo "apt-get update"
    echo "apt install -y git make build-essential libtool bsdmainutils autotools-dev autoconf pkg-config automake python3 libssl-dev libgmp-dev libevent-dev libboost-all-dev libdb4.8-dev libdb4.8++-dev unzip"
    exit 1
fi
clear

}

function ask_yes_or_no() {
  read -p "$1 ([Y]es or [N]o | ENTER): "
    case $(echo $REPLY | tr '[A-Z]' '[a-z]') in
        y|yes) echo "yes" ;;
        *)     echo "no" ;;
    esac
}

function compile_maria() {
echo -e "Checking if swap space is needed."
PHYMEM=$(free -g|awk '/^Mem:/{print $2}')
SWAP=$(free -g|awk '/^Swap:/{print $2}')
if [ "$PHYMEM" -lt "4" ] && [ -n "$SWAP" ]
  then
    echo -e "${GREEN}Server is running with less than 4G of RAM without SWAP, creating 8G swap file.${NC}"
    SWAPFILE=/swapfile
    dd if=/dev/zero of=$SWAPFILE bs=1024 count=8388608
    chown root:root $SWAPFILE
    chmod 600 $SWAPFILE
    mkswap $SWAPFILE
    swapon $SWAPFILE
    echo "${SWAPFILE} none swap sw 0 0" >> /etc/fstab
else
  echo -e "${GREEN}Server running with at least 4G of RAM, no swap needed.${NC}"
fi
clear
  echo -e "Clone git repo and compile it. This may take some time."
  cd $TMP_FOLDER
  git clone $maria_REPO maria
  cd maria
  ./autogen.sh
  ./configure
  make
  strip src/mariad src/maria-cli src/maria-tx
  make install
  cd ~
  rm -rf $TMP_FOLDER
  clear
}

function copy_maria_binaries(){
   cd /root
  wget $maria_LATEST_RELEASE
  unzip maria-5.5.1-ubuntu18-daemon.zip
  cp maria-cli mariad maria-tx /usr/local/bin >/dev/null
  chmod 755 /usr/local/bin/maria* >/dev/null
  clear
}

function install_maria(){
  echo -e "Installing maria files."
  echo -e "${GREEN}You have the choice between source code compilation (slower and requries 4G of RAM or VPS that allows swap to be added), or to use precompiled binaries instead (faster).${NC}"
  if [[ "no" == $(ask_yes_or_no "Do you want to perform source code compilation?") || \
        "no" == $(ask_yes_or_no "Are you **really** sure you want compile the source code, it will take a while?") ]]
  then
    copy_maria_binaries
    clear
  else
    compile_maria
    clear
  fi
}

function enable_firewall() {
  echo -e "Installing fail2ban and setting up firewall to allow ingress on port ${GREEN}$maria_PORT${NC}"
  ufw allow $maria_PORT/tcp comment "maria MN port" >/dev/null
  ufw allow ssh comment "SSH" >/dev/null 2>&1
  ufw limit ssh/tcp >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1
  echo "y" | ufw enable >/dev/null 2>&1
  systemctl enable fail2ban >/dev/null 2>&1
  systemctl start fail2ban >/dev/null 2>&1
}

function systemd_maria() {
  cat << EOF > /etc/systemd/system/$maria_USER.service
[Unit]
Description=maria service
After=network.target
[Service]
ExecStart=$maria_DAEMON -conf=$maria_FOLDER/$CONFIG_FILE -datadir=$maria_FOLDER
ExecStop=$maria_CLI -conf=$maria_FOLDER/$CONFIG_FILE -datadir=$maria_FOLDER stop
Restart=always
User=$maria_USER
Group=$maria_USER

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  sleep 3
  systemctl start $maria_USER.service
  systemctl enable $maria_USER.service
}

function ask_port() {
read -p "maria Port: " -i $DEFAULT_maria_PORT -e maria_PORT
: ${maria_PORT:=$DEFAULT_maria_PORT}
}

function ask_user() {
  echo -e "${GREEN}The script will now setup maria user and configuration directory. Press ENTER to accept defaults values.${NC}"
  read -p "maria user: " -i $DEFAULT_maria_USER -e maria_USER
  : ${maria_USER:=$DEFAULT_maria_USER}

  if [ -z "$(getent passwd $maria_USER)" ]; then
    USERPASS=$(pwgen -s 12 1)
    useradd -m $maria_USER
    echo "$maria_USER:$USERPASS" | chpasswd

    maria_HOME=$(sudo -H -u $maria_USER bash -c 'echo $HOME')
    DEFAULT_maria_FOLDER="$maria_HOME/.maria"
    read -p "Configuration folder: " -i $DEFAULT_maria_FOLDER -e maria_FOLDER
    : ${maria_FOLDER:=$DEFAULT_maria_FOLDER}
    mkdir -p $maria_FOLDER
    chown -R $maria_USER: $maria_FOLDER >/dev/null
  else
    clear
    echo -e "${RED}User exits. Please enter another username: ${NC}"
    ask_user
  fi
}

function check_port() {
  declare -a PORTS
  PORTS=($(netstat -tnlp | awk '/LISTEN/ {print $4}' | awk -F":" '{print $NF}' | sort | uniq | tr '\r\n'  ' '))
  ask_port

  while [[ ${PORTS[@]} =~ $maria_PORT ]] || [[ ${PORTS[@]} =~ $[maria_PORT+1] ]]; do
    clear
    echo -e "${RED}Port in use, please choose another port:${NF}"
    ask_port
  done
}

function create_config() {
  RPCUSER=$(pwgen -s 8 1)
  RPCPASSWORD=$(pwgen -s 15 1)
  cat << EOF > $maria_FOLDER/$CONFIG_FILE
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD
rpcallowip=127.0.0.1
rpcport=$DEFAULT_maria_RPC_PORT
listen=1
server=1
daemon=1
port=$maria_PORT
#External maria IPV4
addnode=188.40.233.38:47773
addnode=188.40.233.39:47773
addnode=188.40.233.43:47773
addnode=188.40.233.44:47773
addnode=188.40.233.40:47773
addnode=188.40.233.41:47773
addnode=199.127.140.224:47773
addnode=199.127.140.225:47773
addnode=199.127.140.228:47773
addnode=199.127.140.231:47773
addnode=199.127.140.233:47773
addnode=199.127.140.235:47773
addnode=199.127.140.236:47773
addnode=94.130.95.106:47773
addnode=188.40.233.45:47773
EOF
}

function create_key() {
  echo -e "Enter your ${RED}Masternode Private Key${NC}. Leave it blank to generate a new ${RED}Masternode Private Key${NC} for you:"
  read -e maria_KEY
  if [[ -z "$maria_KEY" ]]; then
  su $maria_USER -c "$maria_DAEMON -conf=$maria_FOLDER/$CONFIG_FILE -datadir=$maria_FOLDER -daemon"
  sleep 15
  if [ -z "$(ps axo user:15,cmd:100 | egrep ^$maria_USER | grep $maria_DAEMON)" ]; then
   echo -e "${RED}mariad server couldn't start. Check /var/log/syslog for errors.{$NC}"
   exit 1
  fi
  maria_KEY=$(su $maria_USER -c "$maria_CLI -conf=$maria_FOLDER/$CONFIG_FILE -datadir=$maria_FOLDER createmasternodekey")
  su $maria_USER -c "$maria_CLI -conf=$maria_FOLDER/$CONFIG_FILE -datadir=$maria_FOLDER stop"
fi
}

function update_config() {
  sed -i 's/daemon=1/daemon=0/' $maria_FOLDER/$CONFIG_FILE
  cat << EOF >> $maria_FOLDER/$CONFIG_FILE
maxconnections=256
masternode=1
masternodeaddr=$NODE_IP:$maria_PORT
masternodeprivkey=$maria_KEY
EOF
  chown -R $maria_USER: $maria_FOLDER >/dev/null
}

function important_information() {
 echo
 echo -e "================================================================================================================================"
 echo -e "Maria Masternode is up and running as user ${GREEN}$maria_USER${NC} and it is listening on port ${GREEN}$maria_PORT${NC}."
 echo -e "${GREEN}$maria_USER${NC} password is ${RED}$USERPASS${NC}"
 echo -e "Configuration file is: ${RED}$maria_FOLDER/$CONFIG_FILE${NC}"
 echo -e "Start: ${RED}systemctl start $maria_USER.service${NC}"
 echo -e "Stop: ${RED}systemctl stop $maria_USER.service${NC}"
 echo -e "VPS_IP:PORT ${RED}$NODE_IP:$maria_PORT${NC}"
 echo -e "MASTERNODE PRIVATEKEY is: ${RED}$maria_KEY${NC}"
 echo -e "Please check maria is running with the following command: ${GREEN}systemctl status $maria_USER.service${NC}"
 echo -e "================================================================================================================================"
}

function setup_node() {
  ask_user
  install_params
  download_bootstrap
  check_port
  create_config
  create_key
  update_config
  enable_firewall
  systemd_maria
  important_information
}


##### Main #####
clear
purgeOldInstallation
checks
prepare_system
install_maria
setup_node
