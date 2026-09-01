#!/bin/bash
# =============================================================================
# bootstrap.sh — Provisioning commun à TOUS les nœuds (controller + cibles)
# =============================================================================
set -euo pipefail

echo "[bootstrap] Configuration de $(hostname)"

# -----------------------------------------------------------------------------
# 1. SSH : autoriser l'authentification par mot de passe
#    Vagrant génère une paire de clés par machine et désactive le mot de passe.
#    On le réactive pour que les stagiaires puissent pratiquer ssh-copy-id.
# -----------------------------------------------------------------------------
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
# Ubuntu 22.04+ place parfois la directive dans un include qui écrase la valeur
if [ -d /etc/ssh/sshd_config.d ]; then
  echo "PasswordAuthentication yes" > /etc/ssh/sshd_config.d/99-lab.conf
fi
systemctl restart ssh || systemctl restart sshd

# -----------------------------------------------------------------------------
# 2. Supprimer la bannière de connexion (sortie plus lisible pendant les demos)
# -----------------------------------------------------------------------------
touch /home/vagrant/.hushlogin 2>/dev/null || true

# -----------------------------------------------------------------------------
# 3. Résolution de noms : tous les nœuds se connaissent par leur nom court
#    Indispensable : les inventaires des labs utilisent node1/node2/node3.
# -----------------------------------------------------------------------------
sed -i '/anslab.local/d' /etc/hosts
cat >> /etc/hosts <<'EOF'
192.168.56.20 controller.anslab.local controller
192.168.56.21 node1.anslab.local node1
192.168.56.22 node2.anslab.local node2
192.168.56.23 node3.anslab.local node3
EOF

# -----------------------------------------------------------------------------
# 4. Compte applicatif 'admin' utilisé comme remote_user dans les labs
#    sudo sans mot de passe : requis pour 'become: yes'
# -----------------------------------------------------------------------------
if ! id admin &>/dev/null; then
  useradd -m -s /bin/bash admin
  echo "admin:admin" | chpasswd
fi

cat > /etc/sudoers.d/admin <<'EOF'
admin ALL=(ALL) NOPASSWD:ALL
EOF
chmod 440 /etc/sudoers.d/admin

# -----------------------------------------------------------------------------
# 5. Python 3 : la seule dépendance réelle d'Ansible sur les nœuds cibles
# -----------------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq python3 python3-apt tree curl >/dev/null

echo "[bootstrap] $(hostname) prêt — Python $(python3 --version 2>&1 | cut -d' ' -f2)"
