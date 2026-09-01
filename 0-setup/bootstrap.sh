#!/bin/bash

# vagrant crée par défaut sa propre paire de clés pour toutes les machines. L'authentification par mot de passe est désactivée par défaut et l'activer permet d'effectuer l'authentification par mot de passe.

sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# Supprimer le message de bannière à chaque fois que vous vous connectez à la boîte vagrant.

touch /home/vagrant/.hushlogin

# Updating the hosts file for all the 3 nodes with the IP given in vagrantfile

# 192.168.56.20 controller.wizetraining.local controller
# 192.168.56.21 node1.wizetraining.local node1
# 192.168.56.22 node2.wizetraining.local node2
# 192.168.56.23 node3.wizetraining.local node3

sudo echo -e "192.168.56.20 controller.wizetraining.local controller\n192.168.56.21 node1.wizetraining.local node1\n192.168.56.22 node2.wizetraining.local node2\n192.168.56.23 node3.wizetraining.local node3" >> /etc/hosts

# Add Ansible user account

sudo useradd -m -s /bin/bash admin
echo "admin:admin" | sudo chpasswd

cat << _EOF | sudo tee /etc/sudoers.d/admin
admin         ALL=(ALL)       NOPASSWD:ALL
_EOF







