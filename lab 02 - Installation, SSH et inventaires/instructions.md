# Lab 02 — Installation, SSH et inventaires

> ⭐ Niveau : ⭐⭐ | ⏱ Durée estimée : 45 min | Module : **M2 — Architecture, configuration & inventaires**

## Objectifs pédagogiques

* Installer Ansible sur le nœud de contrôle et comprendre le rôle de `ansible-core`
* Mettre en place l'authentification SSH par clé (public / privé)
* Écrire un inventaire statique en INI puis en YAML
* Structurer le parc en groupes et groupes de groupes
* Comprendre la hiérarchie de résolution du fichier `ansible.cfg`
* Valider l'ensemble avec `ansible -m ping` et `ansible-inventory --graph`

## Notions abordées

* `ansible` vs `ansible-core` : le paquet et les collections
* Clés SSH : paire publique/privée, `ssh-keygen`, `ssh-copy-id`
* Inventaire statique : formats INI et YAML
* Groupes, groupes de groupes (`:children`), hôte `all` implicite
* Variables d'inventaire : `ansible_host`, `ansible_user`, `ansible_port`
* `ansible.cfg` : ordre de recherche et directives essentielles
* Commandes de diagnostic : `ansible-config`, `ansible-inventory`

## Documentation de référence

* [Building an inventory](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html)
* [Ansible configuration settings](https://docs.ansible.com/ansible/latest/reference_appendices/config.html)
* [Connection methods](https://docs.ansible.com/ansible/latest/inventory_guide/connection_details.html)

## Contexte

L'environnement est en place, mais Ansible n'est installé nulle part et chaque connexion SSH
réclame un mot de passe. Votre mission : rendre le nœud de contrôle opérationnel, puis
décrire le parc sous forme d'inventaire exploitable — `node1` et `node2` en serveurs web,
`node3` en base de données.

---

## Partie 1 — Installation d'Ansible sur le nœud de contrôle

### 1. Installez Ansible **uniquement** sur le controller. Vérifiez ensuite la version et l'emplacement du binaire.

<details><summary>Correction</summary>

```bash
# Depuis le controller
sudo apt-get update
sudo apt-get install -y ansible

# Vérification
ansible --version
which ansible
```

Sortie attendue (extrait) :

```
ansible [core 2.x.x]
  config file = /etc/ansible/ansible.cfg
  configured module search path = ['/home/vagrant/.ansible/plugins/modules', ...]
  ansible python module location = /usr/lib/python3/dist-packages/ansible
  executable location = /usr/bin/ansible
  python version = 3.10.x
```

**Méthode alternative (pip) — plus courante en entreprise** pour maîtriser la version :

```bash
python3 -m pip install --user ansible
export PATH="$HOME/.local/bin:$PATH"
```

> 💡 `apt install ansible` fournit une version figée par la distribution.
> `pip install ansible` permet d'épingler une version précise — utile quand plusieurs
> équipes doivent utiliser exactement la même.

</details>

---

### 2. Quelle différence entre le paquet `ansible` et `ansible-core` ? Listez les collections disponibles.

<details><summary>Correction</summary>

| Paquet | Contenu |
|:---|:---|
| `ansible-core` | Le moteur seul + la collection `ansible.builtin` (~70 modules essentiels) |
| `ansible` | `ansible-core` **+ ~85 collections** de la communauté (`community.general`, `ansible.posix`, `community.mysql`…) |

```bash
# Lister les collections installées
ansible-galaxy collection list

# Vérifier la présence d'un module précis
ansible-doc -l | grep -c .          # nombre total de modules disponibles
ansible-doc ansible.builtin.apt | head -20
```

**En pratique :** on installe `ansible` (le paquet complet) pour démarrer, puis en
production on bascule sur `ansible-core` + les collections explicitement déclarées dans un
`requirements.yml` — c'est reproductible et beaucoup plus léger.

</details>

---

### 3. Où Ansible cherche-t-il son fichier de configuration ? Donnez l'ordre de priorité.

<details><summary>Correction</summary>

```bash
ansible --version | grep "config file"
ansible-config dump --only-changed
```

**Ordre de recherche (le premier trouvé gagne, les autres sont ignorés) :**

| Priorité | Emplacement | Usage typique |
|:---|:---|:---|
| 1 | `$ANSIBLE_CONFIG` (variable d'env.) | Surcharge ponctuelle / CI |
| 2 | `./ansible.cfg` (répertoire courant) | **Configuration du projet ← le plus courant** |
| 3 | `~/.ansible.cfg` | Préférences personnelles |
| 4 | `/etc/ansible/ansible.cfg` | Défaut système |

> ⚠️ **Piège classique :** ce n'est **pas** une fusion. Si un `ansible.cfg` existe dans le
> répertoire courant, il est le **seul** lu — les directives de `/etc/ansible/ansible.cfg`
> ne s'y ajoutent pas.

> ⚠️ **Second piège :** un `ansible.cfg` situé dans un répertoire **world-writable** est
> ignoré pour raison de sécurité. Si votre config semble n'avoir aucun effet dans `/tp`
> (monté en 777), c'est la cause. Solution : `export ANSIBLE_CONFIG=/tp/ansible.cfg`.

</details>

---

## Partie 2 — Authentification SSH par clé

Saisir un mot de passe à chaque tâche est impraticable. Ansible s'appuie sur le mécanisme
standard des clés SSH.

### 1. Générez une paire de clés SSH sur le controller, sans passphrase.

<details><summary>Correction</summary>

```bash
# -t ed25519 : algorithme moderne, plus court et plus sûr que RSA
# -N ''      : pas de passphrase (adapté au lab ; en prod, utilisez ssh-agent)
# -C         : commentaire identifiant la clé
ssh-keygen -t ed25519 -N '' -C "ansible-controller" -f ~/.ssh/id_ed25519

ls -l ~/.ssh/
```

Deux fichiers sont créés :

| Fichier | Nature | Permissions | À diffuser ? |
|:---|:---|:---|:---|
| `id_ed25519` | Clé **privée** | `600` | ❌ **JAMAIS** — elle reste sur le controller |
| `id_ed25519.pub` | Clé **publique** | `644` | ✅ à copier sur toutes les cibles |

```bash
cat ~/.ssh/id_ed25519.pub
```

</details>

---

### 2. Déployez la clé publique sur les 3 nœuds pour l'utilisateur `admin`.

<details><summary>Correction</summary>

```bash
for n in node1 node2 node3; do
  ssh-copy-id -o StrictHostKeyChecking=no admin@$n
done
# Mot de passe demandé pour chaque nœud : admin
```

**Version non interactive** (utile en CI) — `sshpass` doit d'abord être installé sur le
controller :

```bash
sudo apt-get install -y sshpass

for n in node1 node2 node3; do
  sshpass -p admin ssh-copy-id -o StrictHostKeyChecking=no admin@$n
done
```

**Vérification — aucun mot de passe ne doit être demandé :**

```bash
for n in node1 node2 node3; do
  echo -n "$n : "
  ssh -o BatchMode=yes admin@$n hostname
done
```

Résultat attendu :

```
node1 : node1.wizetraining.local
node2 : node2.wizetraining.local
node3 : node3.wizetraining.local
```

> `-o BatchMode=yes` interdit toute invite interactive : si la clé ne fonctionne pas, la
> commande échoue immédiatement au lieu de demander un mot de passe. C'est le bon test.

</details>

---

### 3. Que fait exactement `ssh-copy-id` ? Vérifiez sur `node1`.

<details><summary>Correction</summary>

```bash
ssh admin@node1 'cat ~/.ssh/authorized_keys'
ssh admin@node1 'ls -ld ~/.ssh; ls -l ~/.ssh/authorized_keys'
```

`ssh-copy-id` réalise trois choses :

1. Crée `~/.ssh` sur la cible avec les permissions `700`
2. Ajoute (en mode *append*) la clé publique dans `~/.ssh/authorized_keys`
3. Positionne les permissions `600` sur `authorized_keys`

> ⚠️ Les permissions sont **critiques** : sshd refuse silencieusement une clé si `~/.ssh`
> ou `authorized_keys` sont trop permissifs. C'est la cause n°1 des « ma clé ne marche
> pas » alors que le fichier semble correct. Diagnostic : `ssh -vvv admin@node1`.

</details>

---

## Partie 3 — Premier inventaire (format INI)

### 1. Créez `/tp/inventory` décrivant les 3 nœuds, avec `node1` et `node2` dans le groupe `web` et `node3` dans `db`.

<details><summary>Correction</summary>

```bash
mkdir -p /tp && cd /tp

cat > /tp/inventory <<'EOF'
[web]
node1
node2

[db]
node3
EOF

cat /tp/inventory
```

**Test immédiat :**

```bash
ansible -i /tp/inventory all -m ping -u admin
```

Sortie attendue :

```
node1 | SUCCESS => { "changed": false, "ping": "pong" }
node2 | SUCCESS => { "changed": false, "ping": "pong" }
node3 | SUCCESS => { "changed": false, "ping": "pong" }
```

> 💡 Le module `ping` d'Ansible **n'est pas** un ping ICMP. Il vérifie la chaîne complète :
> connexion SSH réussie **+** interpréteur Python fonctionnel sur la cible. C'est le test
> de bout en bout de la « plomberie » Ansible.

</details>

---

### 2. Créez `/tp/ansible.cfg` pour ne plus avoir à taper `-i` et `-u` à chaque commande.

<details><summary>Correction</summary>

```bash
cat > /tp/ansible.cfg <<'EOF'
[defaults]
# Inventaire par défaut : plus besoin de -i
inventory = /tp/inventory

# Utilisateur de connexion par défaut : plus besoin de -u
remote_user = admin

# Ne pas demander de validation des host keys (lab uniquement)
host_key_checking = False

# Sortie lisible : une ligne par tâche au lieu du JSON brut
stdout_callback = yaml

# Nombre de nœuds traités en parallèle (défaut : 5)
forks = 10

# Désactiver la création de fichiers .retry
retry_files_enabled = False

[privilege_escalation]
become = False
become_method = sudo
become_user = root
become_ask_pass = False
EOF
```

**Test — la commande devient minimale :**

```bash
cd /tp
ansible all -m ping
```

> ⚠️ Si la configuration semble ignorée, c'est probablement le piège du répertoire
> world-writable (`/tp` est monté en 777). Dans ce cas :
> ```bash
> echo 'export ANSIBLE_CONFIG=/tp/ansible.cfg' >> ~/.bashrc
> source ~/.bashrc
> ansible --version | grep "config file"
> ```

**Vérifier ce qui est effectivement pris en compte :**

```bash
ansible-config dump --only-changed
```

</details>

---

### 3. Enrichissez l'inventaire : ajoutez un groupe de groupes `prod` et des variables de groupe.

<details><summary>Correction</summary>

```bash
cat > /tp/inventory <<'EOF'
# ---------- Serveurs web ----------
[web]
node1
node2

# ---------- Base de données ----------
[db]
node3

# ---------- Groupe de groupes ----------
[prod:children]
web
db

# ---------- Variables de groupe ----------
[web:vars]
http_port=80
app_name=monapp

[db:vars]
db_port=3306
db_name=monapp_db

[prod:vars]
env=production
ansible_user=admin
EOF
```

**Visualiser la hiérarchie :**

```bash
ansible-inventory --graph
```

Sortie attendue :

```
@all:
  |--@prod:
  |  |--@db:
  |  |  |--node3
  |  |--@web:
  |  |  |--node1
  |  |  |--node2
  |--@ungrouped:
```

**Vérifier les variables résolues pour un hôte :**

```bash
ansible-inventory --host node1
```

```json
{
    "ansible_user": "admin",
    "app_name": "monapp",
    "env": "production",
    "http_port": 80
}
```

> 💡 `node1` hérite de `web:vars` **et** de `prod:vars` (via `[prod:children]`).
> L'héritage descend du parent vers l'enfant, et l'enfant est prioritaire en cas de
> conflit.

</details>

---

### 4. Ciblez différents sous-ensembles du parc. Testez les motifs suivants.

<details><summary>Correction</summary>

```bash
ansible web       --list-hosts     # node1, node2
ansible db        --list-hosts     # node3
ansible prod      --list-hosts     # les 3
ansible all       --list-hosts     # les 3
ansible 'web:db'  --list-hosts     # union      → les 3
ansible 'prod:!db' --list-hosts    # exclusion  → node1, node2
ansible 'node*'   --list-hosts     # joker      → les 3
ansible 'web[0]'  --list-hosts     # 1er du groupe → node1
```

| Motif | Signification |
|:---|:---|
| `web:db` | Union (OU) |
| `web:&prod` | Intersection (ET) |
| `prod:!db` | Exclusion (SAUF) |
| `node*` | Joker sur le nom |
| `web[0]` / `web[1:]` | Indexation / tranche |

> 💡 `--list-hosts` est le réflexe de sécurité avant toute commande destructrice :
> il montre **exactement** quelles machines seront touchées, sans rien exécuter.

</details>

---

## Partie 4 — Inventaire au format YAML

Le format INI est simple mais limité (pas de structures imbriquées). Le YAML est le format
recommandé pour les projets qui grandissent.

### 1. Convertissez l'inventaire INI en YAML dans `/tp/inventory.yml`.

<details><summary>Correction</summary>

```yaml
# /tp/inventory.yml
---
all:
  children:

    prod:
      vars:
        env: production
        ansible_user: admin

      children:

        web:
          vars:
            http_port: 80
            app_name: monapp
          hosts:
            node1:
            node2:

        db:
          vars:
            db_port: 3306
            db_name: monapp_db
          hosts:
            node3:
```

**Vérifier l'équivalence stricte avec la version INI :**

```bash
ansible-inventory -i /tp/inventory.yml --graph
ansible-inventory -i /tp/inventory.yml --host node1
```

La sortie doit être **identique** à celle de la version INI.

**Basculer le projet sur le YAML :**

```bash
sed -i 's|inventory = /tp/inventory$|inventory = /tp/inventory.yml|' /tp/ansible.cfg
ansible all -m ping
```

</details>

---

### 2. Ajoutez `node3` à un second groupe `backup` sans le retirer de `db`. Que constatez-vous ?

<details><summary>Correction</summary>

```yaml
all:
  children:
    prod:
      children:
        web:
          hosts:
            node1:
            node2:
        db:
          hosts:
            node3:
    backup:
      vars:
        backup_hour: 3
      hosts:
        node3:
```

```bash
ansible-inventory -i /tp/inventory.yml --graph
ansible-inventory -i /tp/inventory.yml --host node3
```

**Constat :** un hôte peut appartenir à **autant de groupes que nécessaire**. `node3` est à
la fois dans `db` (donc dans `prod`) et dans `backup`. Il cumule les variables des deux.

**C'est le mécanisme central de l'organisation d'un parc :** on croise des groupes par
*fonction* (`web`, `db`), par *environnement* (`prod`, `staging`), par *localisation*
(`paris`, `lyon`). Un serveur est simplement à l'intersection de plusieurs groupes.

> ⚠️ En cas de conflit de variable entre deux groupes de même niveau, Ansible applique
> l'ordre **alphabétique** des noms de groupes — le dernier gagne. C'est une source de bugs
> subtils ; on lève l'ambiguïté avec `ansible_group_priority` ou en évitant le conflit.

</details>

---

### 3. Un serveur `node4` existe à l'IP `192.168.56.24`, mais son nom n'est pas résolvable et son SSH écoute sur le port `2222`. Comment le déclarer ?

<details><summary>Correction</summary>

```yaml
web:
  hosts:
    node1:
    node2:
    node4:
      ansible_host: 192.168.56.24    # adresse réelle de connexion
      ansible_port: 2222             # port SSH non standard
      ansible_user: ubuntu           # utilisateur spécifique à cet hôte
```

**Variables de connexion les plus utiles :**

| Variable | Rôle |
|:---|:---|
| `ansible_host` | Adresse/FQDN réel de connexion (le nom d'inventaire devient un simple alias) |
| `ansible_port` | Port SSH (défaut : 22) |
| `ansible_user` | Utilisateur de connexion |
| `ansible_ssh_private_key_file` | Clé privée spécifique à cet hôte |
| `ansible_connection` | `ssh` (défaut), `local`, `docker`, `winrm` |
| `ansible_python_interpreter` | Chemin de Python si non standard |

> 💡 **Distinction essentielle :** `inventory_hostname` est le **nom dans l'inventaire**
> (`node4`), `ansible_host` est l'**adresse de connexion** (`192.168.56.24`). Cela permet
> de nommer les machines par leur rôle métier tout en les joignant par IP.

> ℹ️ `node4` n'existe pas dans le lab : cet exercice est déclaratif. Retirez-le de
> l'inventaire avant de continuer, sinon `ansible all -m ping` signalera un échec.

</details>

---

## Partie 5 — Validation finale

### 1. Vérifiez l'ensemble de la chaîne et produisez un état des lieux du parc.

<details><summary>Correction</summary>

```bash
cd /tp

# 1. Connectivité complète
ansible all -m ping

# 2. Structure de l'inventaire
ansible-inventory --graph --vars

# 3. Configuration effective
ansible-config dump --only-changed

# 4. Identité réelle des machines jointes
ansible all -m command -a "hostname -f"

# 5. Escalade de privilèges fonctionnelle
ansible all -m command -a "id" --become
```

La dernière commande doit renvoyer `uid=0(root)` pour les 3 nœuds — preuve que `become`
fonctionne.

</details>

---

### 2. Un nœud ne répond pas. Quelle est votre démarche de diagnostic ?

<details><summary>Correction</summary>

**Méthode, du plus bas niveau au plus haut :**

```bash
# 1. Le réseau répond-il ?
ping -c1 node2

# 2. Le port SSH est-il ouvert ?
nc -zv node2 22

# 3. La connexion SSH manuelle fonctionne-t-elle ?
ssh -o BatchMode=yes admin@node2 hostname

# 4. Python est-il présent sur la cible ?
ssh admin@node2 'python3 --version'

# 5. Ansible voit-il bien cet hôte dans l'inventaire ?
ansible-inventory --host node2

# 6. Trace complète Ansible (le -vvvv montre la commande SSH exacte)
ansible node2 -m ping -vvvv
```

**Erreurs fréquentes et leur signification :**

| Message | Cause | Correction |
|:---|:---|:---|
| `Permission denied (publickey,password)` | Clé non déployée ou permissions `~/.ssh` incorrectes | Rejouer `ssh-copy-id` ; vérifier `chmod 700 ~/.ssh` |
| `Failed to connect ... Name or service not known` | Résolution DNS/hosts | Vérifier `/etc/hosts` ou utiliser `ansible_host` |
| `/usr/bin/python: not found` | Pas d'interpréteur Python | Installer `python3` ou définir `ansible_python_interpreter` |
| `Missing sudo password` | `become` sans `NOPASSWD` | Ajouter `--ask-become-pass` ou configurer sudoers |
| `Host key verification failed` | Empreinte SSH inconnue | `host_key_checking = False` (lab) ou `ssh-keyscan` (prod) |

> 🔑 **Le réflexe :** `-vvvv` affiche la commande SSH exacte qu'Ansible exécute. Copiez-la,
> lancez-la à la main : vous verrez immédiatement si le problème vient d'Ansible ou de SSH.

</details>

---

## À retenir

| Point clé | Détail |
|:---|:---|
| **Installation** | Ansible s'installe **uniquement** sur le nœud de contrôle. |
| **`ansible` vs `ansible-core`** | Le premier embarque ~85 collections, le second le moteur seul. |
| **Clés SSH** | La privée ne quitte **jamais** le controller. Permissions `~/.ssh` = `700`, `authorized_keys` = `600`. |
| **`ansible.cfg`** | Le **premier** fichier trouvé gagne — aucune fusion. Ignoré si le répertoire est world-writable. |
| **Inventaire** | INI pour démarrer, YAML pour durer. Un hôte peut appartenir à plusieurs groupes. |
| **`inventory_hostname` ≠ `ansible_host`** | Le nom dans l'inventaire vs l'adresse de connexion. |
| **Module `ping`** | Teste SSH **+** Python, pas ICMP. |
| **`--list-hosts`** | Le réflexe avant toute commande à impact. |

### Les commandes à connaître par cœur

```bash
ansible all -m ping                       # valider la chaîne complète
ansible-inventory --graph --vars          # visualiser le parc et ses variables
ansible-config dump --only-changed        # savoir ce qui est réellement configuré
ansible <motif> --list-hosts              # vérifier la cible AVANT d'agir
ansible <hôte> -m ping -vvvv              # diagnostic bas niveau
```

---

⬅️ **Lab précédent :** [Lab 01 — Mise en place de l'environnement](<../lab 01 - Mise en place de l'environnement/instructions.md>)
➡️ **Lab suivant :** [Lab 03 — Commandes ad-hoc et idempotence](<../lab 03 - Commandes ad-hoc et idempotence/instructions.md>)
