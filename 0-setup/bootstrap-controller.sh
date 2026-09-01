#!/bin/bash
# =============================================================================
# bootstrap-controller.sh — Provisioning SPÉCIFIQUE au nœud de contrôle
#
# NOTE PÉDAGOGIQUE : Ansible n'est volontairement PAS installé ici.
# C'est l'objet du Lab 02 : les stagiaires installent et configurent Ansible
# eux-mêmes. On ne prépare que les prérequis.
# =============================================================================
set -euo pipefail

echo "[controller] Préparation du nœud de contrôle"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

# sshpass : nécessaire pour ssh-copy-id non interactif (Lab 02)
# git     : versionner les playbooks (Lab 11)
# jq      : lire les sorties JSON d'Ansible
apt-get install -y -qq \
  sshpass git jq tree vim python3-pip python3-venv >/dev/null

# -----------------------------------------------------------------------------
# Répertoire de travail : /tp est monté depuis l'hôte (synced_folder)
# On crée un lien depuis le home pour y accéder rapidement.
# -----------------------------------------------------------------------------
mkdir -p /tp/playbooks
ln -sfn /tp /home/vagrant/tp
chown -h vagrant:vagrant /home/vagrant/tp

# -----------------------------------------------------------------------------
# Confort de travail : complétion et alias
# -----------------------------------------------------------------------------
cat > /etc/profile.d/ansible-lab.sh <<'EOF'
# Alias de la formation Ansible
alias ap='ansible-playbook'
alias ai='ansible-inventory'
alias ll='ls -alF'
export ANSIBLE_NOCOWS=1
cd /tp 2>/dev/null || true
EOF
chmod 644 /etc/profile.d/ansible-lab.sh

echo "[controller] Prérequis installés."
echo "[controller] Ansible sera installé pendant le Lab 02."
