# Lab 01 — Mise en place de l'environnement

> ⭐ Niveau : ⭐ | ⏱ Durée estimée : 45 min | Module : **M1 — Fondamentaux : IaC, DevOps & positionnement d'Ansible**

## Objectifs pédagogiques

* Déployer l'infrastructure de lab : 1 nœud de contrôle + 3 nœuds cibles
* Comprendre concrètement ce que signifie « **agentless** » en inspectant les nœuds cibles
* Identifier la seule dépendance réelle d'Ansible sur une machine gérée
* Mesurer l'écart entre une approche « scripts shell » et une approche déclarative
* Valider la connectivité SSH, socle de tout le fonctionnement d'Ansible

## Notions abordées

* Architecture push / agentless d'Ansible
* Nœud de contrôle vs nœuds gérés (*managed nodes*)
* Prérequis réels d'un nœud cible : SSH + Python
* Idempotence : première approche par l'exemple
* Infrastructure as Code : la machine décrite dans un fichier

## Documentation de référence

* [Getting started — Ansible](https://docs.ansible.com/ansible/latest/getting_started/index.html)
* [Installation guide](https://docs.ansible.com/ansible/latest/installation_guide/index.html)

## Contexte

Vous rejoignez une équipe qui gère un parc de serveurs Linux. Aujourd'hui, chaque
installation se fait « à la main » en SSH, ou via des scripts bash recopiés de serveur en
serveur. Résultat : personne ne sait exactement dans quel état se trouve chaque machine.

Avant d'écrire la moindre ligne d'Ansible, vous allez monter l'environnement de travail et
**vérifier par vous-même** pourquoi Ansible n'a besoin de rien installer sur les machines
qu'il pilote.

---

## Partie 1 — Démarrage de l'infrastructure

### 1. Démarrez les 4 machines du lab et vérifiez leur état.

Placez-vous dans le répertoire `0-setup` puis lancez l'environnement.

<details><summary>Correction</summary>

**Option Vagrant :**

```bash
cd 0-setup
vagrant up
vagrant status
```

Sortie attendue :

```
controller                running (virtualbox)
node1                     running (virtualbox)
node2                     running (virtualbox)
node3                     running (virtualbox)
```

**Option Docker :**

```bash
cd 0-setup/docker
docker compose up -d --build
docker compose ps
```

</details>

---

### 2. Connectez-vous au nœud de contrôle et repérez le répertoire de travail partagé.

Quel est l'intérêt d'un répertoire synchronisé entre votre machine et la VM ?

<details><summary>Correction</summary>

```bash
vagrant ssh controller            # ou : docker exec -it controller bash

# Le répertoire /tp est monté depuis l'hôte
ls -la /tp
df -h /tp
```

**Intérêt :** vous éditez vos playbooks YAML avec votre éditeur habituel (VS Code, vim…)
sur votre machine, et ils sont **immédiatement** disponibles dans la VM sans copie manuelle.
C'est aussi ce qui vous permettra de versionner votre travail dans Git (Lab 11) depuis
l'hôte.

</details>

---

## Partie 2 — Comprendre « agentless » par la preuve

C'est **le** point qui différencie Ansible de Puppet, Chef ou Salt. Vérifions-le
concrètement plutôt que de le croire sur parole.

### 1. Connectez-vous à `node1` et cherchez un éventuel agent Ansible installé. Que trouvez-vous ?

<details><summary>Correction</summary>

```bash
vagrant ssh node1        # ou : docker exec -it node1 bash

# Chercher un binaire Ansible
which ansible ansible-playbook 2>&1
# → aucun résultat

# Chercher un paquet installé
dpkg -l | grep -i ansible
# → aucun résultat

# Chercher un service qui tournerait en permanence
systemctl list-units --type=service | grep -i ansible
# → aucun résultat
```

**Conclusion :** il n'y a **rien** d'Ansible sur le nœud cible. Aucun binaire, aucun paquet,
aucun démon. C'est cela, « agentless ».

**Conséquences pratiques :**
* Rien à installer avant de piloter un serveur
* Aucun service supplémentaire à sécuriser, patcher ou monitorer
* Aucun port à ouvrir en plus de SSH (déjà présent partout)
* Une machine neuve est pilotable immédiatement

</details>

---

### 2. Quels sont alors les **deux seuls** prérequis d'un nœud cible ? Vérifiez leur présence.

<details><summary>Correction</summary>

```bash
# Prérequis 1 : un serveur SSH accessible
systemctl status ssh --no-pager | head -5
ss -tlnp | grep :22

# Prérequis 2 : un interpréteur Python
python3 --version
which python3
```

**Les deux prérequis :**

| Prérequis | Rôle |
|:---|:---|
| **SSH** | Le transport. Ansible ouvre une connexion SSH standard pour atteindre la machine. |
| **Python 3** | L'exécution. Ansible **copie** un module Python sur la cible, l'exécute, récupère le JSON, puis **supprime** le module. |

> 💡 C'est tout. Les deux sont déjà présents sur pratiquement toutes les distributions
> Linux serveur. C'est pourquoi Ansible s'adopte si vite : il n'y a pas de phase
> « déploiement de l'agent sur le parc ».

</details>

---

### 3. Observez le cycle de vie d'un module Ansible sur la cible.

Sur `node1`, surveillez le répertoire temporaire d'Ansible pendant qu'une commande
s'exécute depuis le controller. Que se passe-t-il ?

<details><summary>Correction</summary>

Le mécanisme, étape par étape :

```
1. Le controller ouvre une connexion SSH vers node1
2. Il crée un répertoire temporaire   ~/.ansible/tmp/ansible-tmp-<timestamp>/
3. Il y COPIE le module Python (ex: ping.py, apt.py…)
4. Il EXÉCUTE ce module → le module renvoie du JSON sur stdout
5. Il SUPPRIME le répertoire temporaire
6. Il ferme la connexion SSH
```

Pour l'observer (après le Lab 02, une fois Ansible installé) :

```bash
# Sur node1, dans un terminal
watch -n 0.2 'ls -la ~/.ansible/tmp/ 2>/dev/null'

# Depuis le controller, dans un autre terminal
ansible node1 -m setup
```

**À retenir :** rien ne persiste sur la cible. C'est aussi pourquoi Ansible ne peut pas
« dériver » : il n'y a pas d'état local à corrompre.

</details>

---

## Partie 3 — Pourquoi pas simplement des scripts bash ?

### 1. Voici un script d'installation classique. Exécutez-le **deux fois** sur `node1` et observez.

```bash
# Sur node1
cat > /tmp/install-web.sh <<'EOF'
#!/bin/bash
apt-get install -y apache2
echo "ServerName node1" >> /etc/apache2/apache2.conf
useradd -m webadmin
mkdir /var/www/html/app
EOF

sudo bash /tmp/install-web.sh
echo "===== DEUXIÈME EXÉCUTION ====="
sudo bash /tmp/install-web.sh
```

Que se passe-t-il à la seconde exécution ?

<details><summary>Correction</summary>

À la seconde exécution :

```
useradd: user 'webadmin' already exists          ← ERREUR
mkdir: cannot create directory '/var/www/html/app': File exists   ← ERREUR
```

Et surtout, silencieusement :

```bash
grep -c "ServerName node1" /etc/apache2/apache2.conf
# → 2    ← la ligne a été ajoutée DEUX fois !
```

**Les trois problèmes du script bash :**

| Problème | Conséquence |
|:---|:---|
| **Non idempotent** | Rejouer le script casse ou duplique. On n'ose plus le relancer. |
| **Pas de notion d'état désiré** | Le script décrit *comment faire*, pas *ce qu'on veut obtenir*. |
| **Pas de rapport** | Impossible de savoir ce qui a réellement changé. |

Vérifiez la corruption du fichier de configuration :

```bash
sudo grep "ServerName" /etc/apache2/apache2.conf
```

</details>

---

### 2. Comment Ansible résout-il ce problème ? (question de réflexion, avant de coder)

<details><summary>Correction</summary>

Ansible raisonne en **état désiré** (déclaratif), pas en suite d'instructions (impératif).

L'équivalent Ansible du script ci-dessus :

```yaml
- name: Installer Apache
  ansible.builtin.apt:
    name: apache2
    state: present          # « je veux qu'il SOIT installé »

- name: Définir le ServerName
  ansible.builtin.lineinfile:
    path: /etc/apache2/apache2.conf
    line: "ServerName {{ inventory_hostname }}"
    regexp: '^ServerName'   # « une seule ligne ServerName, celle-ci »

- name: Créer l'utilisateur webadmin
  ansible.builtin.user:
    name: webadmin
    state: present          # « je veux qu'il EXISTE »

- name: Créer le répertoire applicatif
  ansible.builtin.file:
    path: /var/www/html/app
    state: directory        # « je veux que ce répertoire EXISTE »
```

**Ce que fait chaque module avant d'agir :** il *vérifie l'état actuel*.
* Déjà dans l'état voulu → il ne fait rien et rapporte `ok`
* Pas dans l'état voulu → il agit et rapporte `changed`

Vous pouvez donc rejouer ce playbook 100 fois : le résultat est identique, et à partir de
la 2ᵉ exécution tout est `ok` — **zéro modification**. C'est l'**idempotence**, et c'est ce
qui rend l'automatisation sûre.

> 🔑 Un playbook Ansible qui produit `changed=0` en seconde exécution est un playbook
> correctement écrit. C'est votre critère de qualité tout au long de la formation.

</details>

---

### 3. Nettoyez `node1` pour repartir d'un état propre.

<details><summary>Correction</summary>

```bash
# Sur node1
sudo apt-get remove -y apache2
sudo userdel -r webadmin 2>/dev/null
sudo rm -rf /var/www/html/app /tmp/install-web.sh
sudo sed -i '/^ServerName node1/d' /etc/apache2/apache2.conf 2>/dev/null
```

</details>

---

## Partie 4 — Cartographier son parc

### 1. Relevez les informations des 4 machines et complétez ce tableau.

| Machine | Nom d'hôte | IP | OS | Version Python | Rôle prévu |
|:---|:---|:---|:---|:---|:---|
| controller | ? | ? | ? | ? | Nœud de contrôle |
| node1 | ? | ? | ? | ? | ? |
| node2 | ? | ? | ? | ? | ? |
| node3 | ? | ? | ? | ? | ? |

<details><summary>Correction</summary>

Commandes à jouer sur chaque machine :

```bash
hostname -f
hostname -I
cat /etc/os-release | grep PRETTY_NAME
python3 --version
```

Résultat attendu (option Vagrant) :

| Machine | Nom d'hôte | IP | OS | Python | Rôle prévu |
|:---|:---|:---|:---|:---|:---|
| controller | controller.anslab.com | 192.168.56.20 | Ubuntu 22.04 | 3.10.x | Nœud de contrôle |
| node1 | node1.wizetraining.local | 192.168.56.21 | Ubuntu 22.04 | 3.10.x | Serveur web (`web`) |
| node2 | node2.wizetraining.local | 192.168.56.22 | Ubuntu 22.04 | 3.10.x | Serveur web (`web`) |
| node3 | node3.wizetraining.local | 192.168.56.23 | Ubuntu 22.04 | 3.10.x | Base de données (`db`) |

> En option Docker, les IP sont en `172.28.0.x` — c'est normal et sans impact.

**Ce tableau, c'est déjà votre inventaire.** Au Lab 02, vous allez simplement l'écrire dans
un format qu'Ansible sait lire.

</details>

---

### 2. Vérifiez que le controller peut joindre les 3 nœuds par leur nom court.

<details><summary>Correction</summary>

```bash
# Depuis le controller
for n in node1 node2 node3; do
  ping -c1 -W1 $n >/dev/null 2>&1 && echo "$n : OK" || echo "$n : KO"
done
```

Résultat attendu :

```
node1 : OK
node2 : OK
node3 : OK
```

**Si un nœud est KO**, vérifiez `/etc/hosts` sur le controller :

```bash
grep anslab /etc/hosts
```

La résolution de noms est assurée par le `bootstrap.sh` (Vagrant) ou par les `extra_hosts`
du `docker-compose.yml`.

</details>

---

### 3. Testez une connexion SSH manuelle vers `node1` avec le compte `admin`.

<details><summary>Correction</summary>

```bash
# Depuis le controller — mot de passe : admin
ssh admin@node1
```

Une fois connecté, vérifiez l'escalade de privilèges :

```bash
sudo whoami       # → root, sans demander de mot de passe
exit
```

**Pourquoi c'est important :** Ansible utilisera exactement ce chemin — connexion SSH avec
`admin`, puis `sudo` pour les tâches privilégiées (`become: yes`). Si cette commande
manuelle fonctionne, Ansible fonctionnera.

> ⚠️ Le mot de passe sera saisi à chaque connexion. Au Lab 02, vous mettrez en place
> l'authentification par clé pour supprimer cette friction.

</details>

---

## À retenir

| Point clé | Détail |
|:---|:---|
| **Agentless** | Rien n'est installé sur les nœuds gérés. Ni binaire, ni démon, ni paquet. |
| **2 prérequis seulement** | SSH (transport) + Python 3 (exécution des modules). |
| **Cycle d'un module** | Copie → exécution → retour JSON → suppression. Rien ne persiste. |
| **Push, pas pull** | C'est le controller qui initie. Les cibles n'appellent jamais le controller. |
| **Impératif → déclaratif** | On décrit l'**état voulu**, pas la suite d'instructions. |
| **Idempotence** | Rejouer doit produire `changed=0`. C'est le critère de qualité d'un playbook. |

### Le piège classique

Croire qu'il faut « installer Ansible partout ». **Non** : Ansible s'installe **uniquement**
sur le nœud de contrôle. C'est la première erreur des débutants venant du monde
Puppet/Chef, où un agent tourne effectivement sur chaque machine.

---

➡️ **Lab suivant :** [Lab 02 — Installation, SSH et inventaires](<../lab 02 - Installation, SSH et inventaires/instructions.md>)
