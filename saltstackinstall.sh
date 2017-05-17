#!/bin/bash

echo $(date +"%F %T%z") "starting script saltstackinstall.sh"

# arguments
adminUsername=$1
adminPassword=$2
subscriptionId=$3
storageName=$4
vnetName=$5
location=$6
resourceGroupname=$7
subnetName=$8
clientid=$9
secret=${10}
tenantid=${11}
publicip=${12}
nsgname=${13}

echo "----------------------------------"
echo "INSTALLING SALT"
echo "----------------------------------"

curl -s -o $HOME/bootstrap_salt.sh -L https://bootstrap.saltstack.com
sh $HOME/bootstrap_salt.sh -M -p python-pip git v2017.5
#sh $HOME/bootstrap_salt.sh -M -p python2-boto git 54ed167

sudo apt-get install build-essential libssl-dev libffi-dev python-dev
pip install azure 
#pip install msrest msrestazure
pip install -U azure-mgmt-compute azure-mgmt-network azure-mgmt-resource azure-mgmt-storage azure-mgmt-web

cd /etc/salt

sed -i 's/#interface:.*/interface: $(hostname --ip-address)/' master
sed -i '/hash_type:.*/s/^#//g' master

sudo systemctl start salt-master.service
sudo systemctl enable salt-master.service
sudo salt-cloud -u

echo "----------------------------------"
echo "CONFIGURING SALT-CLOUD"
echo "----------------------------------"

#--- here is where i stopped on 5/13.

mkdir cloud.providers.d
cd cloud.providers.d
echo "azure:
  driver: azurearm
  subscription_id: $subscriptionId
  client_id: $clientid
  secret: $secret
  tenant: $tenantid
  minion:
    master: $publicip
    hash_type: sha256
    tcp_keepalive: True
    tcp_keepalive_idle: 180
  grains:
    home: /home/$adminUsername
    provider: azure
    user: $adminUsername" > azure.conf
cd ..
mkdir cloud.profiles.d && cd cloud.profiles.d