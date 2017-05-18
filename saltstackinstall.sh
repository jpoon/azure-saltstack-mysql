#!/bin/bash

set -ex

echo $(date +"%F %T%z") "Starting saltstackinstall.sh"

# arguments
ADMINUSERNAME=${1:-saltadmin}
RESOURCEGROUPNAME=${2}
STORAGEACCOUNTNAME=${3}
VNETNAME=${4:-salt-vnet}
SUBNETNAME=${5:-subnet}
SUBSCRIPTIONID=${6}
SP_CLIENTID=${7}
SP_SECRET=${8}
SP_TENANTID=${9}

echo "----------------------------------"
echo "INSTALLING SALT"
echo "----------------------------------"

curl -s -o $HOME/bootstrap_salt.sh -L https://bootstrap.saltstack.com
sudo sh $HOME/bootstrap_salt.sh -M -p python-pip git v2017.5

sudo apt-get -y install build-essential libssl-dev libffi-dev python-dev
pip install --upgrade pip
pip install azure --user
pip install -U azure-mgmt-compute azure-mgmt-network azure-mgmt-resource azure-mgmt-storage azure-mgmt-web

vmPrivateIpAddress=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipaddress/0/ipaddress?api-version=2017-03-01&format=text")
vmPublicIpAddress=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipaddress/0/publicip?api-version=2017-03-01&format=text")
vmLocation=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/location?api-version=2017-03-01&format=text")

echo "
interface: ${vmPrivateIpAddress}
hash_type: sha256
file_roots:
  base:
    - /srv/salt
    - /srv/salt/mysql-formula
" | sudo tee --append /etc/salt/master

sudo systemctl start salt-master.service
sudo systemctl enable salt-master.service
sudo salt-cloud -u

echo "----------------------------------"
echo "CONFIGURING SALT-CLOUD"
echo "----------------------------------"

sudo mkdir -p /etc/salt/cloud.providers.d
echo "
azurearm-conf:
  driver: azurearm
  subscription_id: $SUBSCRIPTIONID
  client_id: $SP_CLIENTID
  secret: $SP_SECRET
  tenant: $SP_TENANTID
  minion:
    master: ${vmPublicIpAddress}
    hash_type: sha256
    tcp_keepalive: True
    tcp_keepalive_idle: 180
  grains:
    home: /home/$ADMINUSERNAME
    provider: azure
    user: $ADMINUSERNAME
" | sudo tee /etc/salt/cloud.providers.d/azure.conf

sudo mkdir -p /etc/salt/cloud.profiles.d 
sudo echo "
azure-ubuntu:
  provider: azurearm-conf
  image: Canonical|UbuntuServer|14.04.5-LTS|14.04.201612050
  size: Standard_D1_v2
  location: ${vmLocation}
  ssh_username: $ADMINUSERNAME
  ssh_password: SaltPa$$word!
  resource_group: $RESOURCEGROUPNAME
  network_resource_group: $RESOURCEGROUPNAME
  network: $VNETNAME
  subnet: $SUBNETNAME
  public_ip: True
  storage_account: $STORAGEACCOUNTNAME
" | sudo tee /etc/salt/cloud.profiles.d/azure.conf

echo "----------------------------------"
echo "RUNNING SALT-CLOUD"
echo "----------------------------------"

sudo salt-cloud -p azure-ubuntu ${RESOURCEGROUPNAME}-minion-0

echo "----------------------------------"
echo "CONFIGURING STATE"
echo "----------------------------------"

# Create user. Add SSH authorized keys.
sudo mkdir -p /srv/salt/key --parents
sudo cp ~/.ssh/authorized_keys /srv/salt/key/authorized_keys
echo "
$ADMINUSERNAME:
  group.present:
    - name: $ADMINUSERNAME
  user.present:
    - fullname: $ADMINUSERNAME
    - shell: /bin/bash
    - home: /home/$ADMINUSERNAME
    - groups:
      - sudo
      - $ADMINUSERNAME

/home/$ADMINUSERNAME/.ssh:
  file.directory:
    - user: $ADMINUSERNAME
    - group: $ADMINUSERNAME
    - mode: 700
  require:
    - user: $ADMINUSERNAME

/home/$ADMINUSERNAME/.ssh/authorized_keys:
  file:
    - managed
    - user: $ADMINUSERNAME
    - group: $ADMINUSERNAME
    - source: salt://key/authorized_keys
    - mode: 600
" | sudo tee /srv/salt/createuser.sls

# mysql
cd /srv/salt
sudo git clone https://github.com/saltstack-formulas/mysql-formula.git 
sudo systemctl restart salt-master.service

echo "
base:
  '*':
    - createuser
    - mysql
" | sudo tee /srv/salt/top.sls

echo "----------------------------------"
echo "CONFIGURING PILLAR"
echo "----------------------------------"

sudo mkdir -p /srv/pillar
echo "
base:
  '*':
    - mysql
" | sudo tee /srv/pillar/top.sls

echo "
mysql:
  server:
    root_password: 'devitconf'
  database:
    - devitconf
" | sudo tee /srv/pillar/mysql.sls

echo "----------------------------------"
echo "SALT APPLY STATE"
echo "----------------------------------"
sudo salt '*' state.highstate
