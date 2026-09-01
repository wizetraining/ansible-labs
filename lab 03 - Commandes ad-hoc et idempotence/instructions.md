# Lab 03 — Commandes ad-hoc et idempotence

> ⭐ Niveau : ⭐⭐ | ⏱ Durée estimée : 45 min | Module : **M3 — Commandes ad-hoc, modules & idempotence**

## Objectifs pédagogiques

* Maîtriser la structure d'une commande ad-hoc et savoir quand l'utiliser
* Manipuler les modules essentiels : `command`, `shell`, `copy`, `file`, `apt`, `user`, `service`
* Distinguer `command` de `shell` et savoir pourquoi les éviter
* Démontrer l'idempotence par l'observation des statuts `ok` / `changed`
* Exploiter le module `setup` pour découvrir les facts d'une machine
* Lire la documentation d'un module sans quitter le terminal

## Notions abordées

* Syntaxe ad-hoc : `ansible <motif> -m <module> -a "<arguments>"`
* Escalade de privilèges : `--become` / `-b`
* Statuts de retour : `ok`, `changed`, `failed`, `unreachable`, `skipped`
* Idempotence et son rapport avec le statut `changed`
* Modules « non idempotents par nature » : `command`, `shell`, `raw`
* Facts et module `setup`
* `ansible-doc` : la documentation hors ligne

## Documentation de référence

* [Introduction to ad hoc commands](https://docs.ansible.com/ansible/latest/command_guide/intro_adhoc.html)
* [Module index](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/index.html)

## Contexte

Un incident vient d'être déclaré : on vous demande de vérifier en urgence l'espace disque
et la charge de l'ensemble du parc, puis d'appliquer un correctif rapide. Vous n'allez pas
écrire un playbook pour cela — les **commandes ad-hoc** sont faites exactement pour ce
besoin : une action, tout de suite, sur un ensemble de machines.

Vous en profiterez pour établir *par la mesure* la différence entre un module idempotent et
une simple commande shell.

---

## Partie 1 — Anatomie d'une commande ad-hoc

La structure est toujours la même :

```bash
ansible <motif-de-cibles> -m <module> -a "<arguments-du-module>" [options]
```

### 1. Interrogez l'ensemble du parc : date/heure, uptime, espace disque et mémoire.

<details><summary>Correction</summary>

```bash
cd /tp

# Date et heure de chaque machine
ansible all -m command -a "date"

# Uptime et charge
ansible all -m command -a "uptime"

# Espace disque (format lisible)
ansible all -m command -a "df -h /"

# Mémoire
ansible all -m command -a "free -m"
```

> 💡 `-m command` est le module **par défaut** : `ansible all -a "date"` fonctionne aussi.
> On l'écrit explicitement au début pour bien ancrer la structure.

**Sortie plus compacte** — utile quand on interroge beaucoup de machines :

```bash
ansible all -m command -a "uptime" -o
```

</details>

---

### 2. Quelle est la différence entre les modules `command` et `shell` ? Démontrez-la.

<details><summary>Correction</summary>

```bash
# Avec command : le pipe est passé comme un ARGUMENT LITTÉRAL, pas interprété
ansible node1 -m command -a "cat /etc/passwd | wc -l"
# → échec ou résultat aberrant : « | » et « wc » sont vus comme des arguments de cat

# Avec shell : la commande passe par /bin/sh, le pipe fonctionne
ansible node1 -m shell -a "cat /etc/passwd | wc -l"
# → 22 (ou équivalent)
```

| Module | Passe par un shell ? | Pipes, `>`, `&&`, `$VAR`, `*` | Sécurité |
|:---|:---|:---|:---|
| `command` | ❌ Non | ❌ Non interprétés | ✅ Plus sûr (pas d'injection shell) |
| `shell` | ✅ Oui (`/bin/sh`) | ✅ Interprétés | ⚠️ Sensible à l'injection |
| `raw` | ✅ Oui, **sans Python** | ✅ | Réservé au bootstrap (cible sans Python) |

**Règle de choix :**

1. Cherchez d'abord un **module dédié** (`apt`, `file`, `user`, `service`…) — c'est
   idempotent et cela produit un vrai rapport
2. Si aucun module ne convient → `command`
3. Si vous avez besoin de pipes/redirections → `shell`
4. `raw` uniquement pour installer Python sur une machine qui n'en a pas

> ⚠️ `command` et `shell` sont **toujours** `changed`. Ils ne peuvent pas savoir si l'état
> a réellement été modifié. C'est pourquoi on les évite dès qu'un module existe.

</details>

---

### 3. Consultez la documentation d'un module sans quitter le terminal.

<details><summary>Correction</summary>

```bash
# Documentation complète
ansible-doc ansible.builtin.file

# Uniquement les exemples (le plus utile au quotidien)
ansible-doc ansible.builtin.file | sed -n '/EXAMPLES/,/RETURN/p'

# Un extrait rapide (snippet à copier-coller)
ansible-doc -s ansible.builtin.user

# Chercher un module par mot-clé
ansible-doc -l | grep -i mysql
ansible-doc -l | grep -i "^ansible.builtin.s"
```

> 🔑 `ansible-doc` fonctionne **hors ligne** et documente la version exacte que vous avez
> installée. C'est plus fiable que le site web, qui documente la dernière version.

</details>

---

## Partie 2 — Modules de gestion des fichiers

### 1. Créez le répertoire `/opt/monapp` sur tous les nœuds, propriétaire `admin`, permissions `0755`.

<details><summary>Correction</summary>

```bash
ansible all -m file -a "path=/opt/monapp state=directory owner=admin group=admin mode=0755" --become
```

**Vérification :**

```bash
ansible all -m command -a "ls -ld /opt/monapp"
```

**Les valeurs de `state` du module `file` :**

| `state` | Effet |
|:---|:---|
| `directory` | Crée le répertoire (et ses parents, comme `mkdir -p`) |
| `touch` | Crée un fichier vide s'il n'existe pas |
| `file` | Vérifie qu'il existe (n'en crée **pas**) et ajuste les attributs |
| `absent` | Supprime (récursivement pour un répertoire) |
| `link` / `hard` | Crée un lien symbolique / physique |

> ⚠️ **Piège du mode :** écrivez `mode=0755` (avec le zéro initial) et non `mode=755`.
> En YAML, `755` non quoté est interprété comme un **entier décimal**, ce qui donne des
> permissions inattendues. Dans un playbook, écrivez `mode: "0755"` entre guillemets.

</details>

---

### 2. Déposez un fichier `/opt/monapp/README.txt` sur les serveurs `web` uniquement, avec un contenu inline.

<details><summary>Correction</summary>

```bash
ansible web -m copy -a 'content="Application monapp - environnement de production\n" dest=/opt/monapp/README.txt owner=admin mode=0644' --become
```

**Vérification :**

```bash
ansible web -m command -a "cat /opt/monapp/README.txt"
```

**Les deux usages du module `copy` :**

```bash
# 1. Contenu inline (pratique pour de petits fichiers)
ansible web -m copy -a 'content="texte" dest=/chemin/fichier'

# 2. Depuis un fichier local du controller (cas le plus courant)
echo "Config applicative" > /tp/app.conf
ansible web -m copy -a "src=/tp/app.conf dest=/opt/monapp/app.conf mode=0644" --become
```

> 💡 Modules connexes à connaître :
> * `template` — comme `copy` mais avec rendu Jinja2 (voir Lab 06)
> * `fetch` — l'inverse : récupère un fichier **depuis** les cibles vers le controller
> * `lineinfile` — modifie **une ligne** dans un fichier existant
> * `blockinfile` — insère/met à jour un **bloc** délimité par des marqueurs

</details>

---

### 3. **Démonstration centrale : l'idempotence.** Rejouez la commande de l'exercice 1 et observez le statut.

<details><summary>Correction</summary>

```bash
# 1re exécution (le répertoire a été créé plus haut)
ansible all -m file -a "path=/opt/monapp state=directory owner=admin mode=0755" --become

# 2e exécution — EXACTEMENT la même commande
ansible all -m file -a "path=/opt/monapp state=directory owner=admin mode=0755" --become
```

**Observation :**

| Exécution | Statut | Couleur | Signification |
|:---|:---|:---|:---|
| 1re | `CHANGED` | 🟡 jaune | Le répertoire n'existait pas → Ansible l'a créé |
| 2e | `SUCCESS` / `ok` | 🟢 vert | Le répertoire est déjà conforme → **rien n'a été fait** |

**Comparez avec l'équivalent en `command` :**

```bash
ansible all -m command -a "mkdir -p /opt/monapp" --become
ansible all -m command -a "mkdir -p /opt/monapp" --become
```

→ **Toujours `CHANGED`**, les deux fois. Le module `command` ne peut pas savoir si quelque
chose a réellement changé : il exécute, point.

**C'est toute la valeur d'Ansible :**

* Le statut `changed` devient une **information fiable** : « voici ce qui a réellement été
  modifié sur mon parc »
* On peut rejouer un playbook sans crainte
* Les **handlers** (Lab 04) se déclenchent uniquement sur un vrai `changed` — donc on ne
  redémarre un service que s'il y a une raison

> 🔑 **Le critère de qualité :** un playbook bien écrit doit afficher `changed=0` lors de
> sa seconde exécution consécutive. Si ce n'est pas le cas, cherchez les `command`/`shell`
> mal maîtrisés.

</details>

---

## Partie 3 — Paquets, utilisateurs et services

### 1. Installez `tree` sur tous les nœuds, puis vérifiez l'idempotence.

<details><summary>Correction</summary>

```bash
# 1re fois → changed
ansible all -m apt -a "name=tree state=present update_cache=yes" --become

# 2e fois → ok
ansible all -m apt -a "name=tree state=present" --become
```

**Valeurs de `state` du module `apt` :**

| `state` | Effet |
|:---|:---|
| `present` | Installé (n'importe quelle version) — **le plus courant** |
| `absent` | Désinstallé |
| `latest` | Mis à jour vers la dernière version disponible |
| `build-dep` | Installe les dépendances de compilation |

> ⚠️ **Évitez `state: latest` en production.** Il rend le playbook non déterministe : le
> résultat dépend du jour où vous le jouez. Deux environnements provisionnés à une semaine
> d'écart n'auront pas les mêmes versions. Préférez `state: present` avec une version
> épinglée : `name: nginx=1.18.*`.

**Installer plusieurs paquets en une tâche :**

```bash
ansible all -m apt -a "name=htop,curl,git state=present" --become
```

**Module générique multi-distribution :**

```bash
# package choisit automatiquement apt / yum / dnf selon l'OS
ansible all -m package -a "name=tree state=present" --become
```

</details>

---

### 2. Créez un utilisateur applicatif `deployer` avec un shell `/bin/bash` et un home dédié.

<details><summary>Correction</summary>

```bash
ansible all -m user -a "name=deployer shell=/bin/bash home=/home/deployer createhome=yes state=present" --become
```

**Vérification :**

```bash
ansible all -m command -a "id deployer"
ansible all -m command -a "ls -ld /home/deployer"
```

**Idempotence :** rejouez la commande → `ok`, contrairement à `useradd` qui échouerait avec
`user already exists`.

**Options utiles du module `user` :**

```bash
# Ajouter à des groupes secondaires SANS retirer les existants
ansible all -m user -a "name=deployer groups=sudo,adm append=yes" --become

# Générer une paire de clés SSH pour cet utilisateur
ansible all -m user -a "name=deployer generate_ssh_key=yes ssh_key_bits=2048" --become

# Supprimer l'utilisateur ET son home
ansible all -m user -a "name=deployer state=absent remove=yes" --become
```

> ⚠️ **Piège :** sans `append=yes`, l'option `groups` **remplace** tous les groupes
> secondaires. Un utilisateur peut ainsi perdre son appartenance à `sudo` sans que vous
> l'ayez voulu.

</details>

---

### 3. Installez Apache sur le groupe `web`, démarrez-le et activez-le au boot. Vérifiez qu'il répond.

<details><summary>Correction</summary>

```bash
# 1. Installation
ansible web -m apt -a "name=apache2 state=present update_cache=yes" --become

# 2. Démarrage + activation au boot
ansible web -m service -a "name=apache2 state=started enabled=yes" --become

# 3. Vérification du service
ansible web -m command -a "systemctl is-active apache2"

# 4. Vérification HTTP depuis les nœuds eux-mêmes
ansible web -m uri -a "url=http://localhost return_content=no status_code=200"
```

**Valeurs de `state` du module `service` :**

| `state` | Effet |
|:---|:---|
| `started` | Démarré s'il ne l'est pas (**idempotent**) |
| `stopped` | Arrêté |
| `restarted` | **Toujours** redémarré (**jamais idempotent**) |
| `reloaded` | Recharge la configuration sans coupure |

Et `enabled=yes|no` gère le démarrage automatique au boot — c'est **indépendant** de
`state`.

> ⚠️ `state=restarted` est **toujours** `changed` et coupe le service à chaque exécution.
> Ne l'utilisez jamais « au cas où » dans un playbook : c'est le rôle des **handlers**
> (Lab 04) de redémarrer uniquement quand la configuration a effectivement changé.

</details>

---

## Partie 4 — Les facts : découvrir les machines

### 1. Récupérez l'ensemble des facts de `node1`. Combien y en a-t-il ?

<details><summary>Correction</summary>

```bash
# Tous les facts (sortie très volumineuse)
ansible node1 -m setup

# Compter les facts collectés
ansible node1 -m setup | grep -c '":'

# Filtrer par motif — indispensable en pratique
ansible node1 -m setup -a "filter=ansible_distribution*"
ansible node1 -m setup -a "filter=ansible_mem*"
ansible node1 -m setup -a "filter=ansible_processor*"
```

Ansible collecte **plusieurs centaines** de facts : OS, version, architecture, CPU, RAM,
interfaces réseau, disques, points de montage, variables d'environnement, date/heure…

> 💡 Le module `setup` est exécuté **automatiquement** au début de chaque play (étape
> `Gathering Facts`). C'est pour cela que vous pouvez utiliser `ansible_distribution` dans
> un playbook sans l'avoir demandé.

</details>

---

### 2. Extrayez les facts les plus utiles du parc : OS, version, IP, RAM, nombre de CPU.

<details><summary>Correction</summary>

```bash
# Distribution et version
ansible all -m setup -a "filter=ansible_distribution_version"

# Adresse IP principale
ansible all -m setup -a "filter=ansible_default_ipv4"

# Mémoire totale (Mo)
ansible all -m setup -a "filter=ansible_memtotal_mb"

# Nombre de cœurs
ansible all -m setup -a "filter=ansible_processor_vcpus"
```

**Vue synthétique du parc en une commande :**

```bash
ansible all -m setup -a "filter=ansible_hostname,ansible_distribution,ansible_distribution_version,ansible_memtotal_mb,ansible_processor_vcpus" -o
```

**Les facts les plus fréquemment utilisés :**

| Fact | Exemple de valeur | Usage typique |
|:---|:---|:---|
| `ansible_distribution` | `Ubuntu` | Condition `when` multi-OS |
| `ansible_distribution_major_version` | `22` | Choisir un dépôt ou un paquet |
| `ansible_os_family` | `Debian` | Condition large (`Debian` / `RedHat`) |
| `ansible_default_ipv4.address` | `192.168.56.21` | Générer une configuration réseau |
| `ansible_hostname` / `ansible_fqdn` | `node1` | Nommer dans un template |
| `ansible_memtotal_mb` | `972` | Dimensionner un pool applicatif |
| `ansible_processor_vcpus` | `1` | Calculer un nombre de workers |

</details>

---

### 3. La collecte des facts ralentit l'exécution. Comment la désactiver, et quand est-ce pertinent ?

<details><summary>Correction</summary>

**Mesurer le coût :**

```bash
time ansible all -m ping                        # avec collecte implicite ? non
time ansible all -m setup > /dev/null           # coût réel de la collecte
```

**Désactiver dans un playbook :**

```yaml
- name: Playbook rapide sans facts
  hosts: all
  gather_facts: no        # ← gain de 1 à 3 secondes PAR HÔTE
  tasks:
    - ansible.builtin.ping:
```

**Collecte partielle** (compromis) :

```yaml
- hosts: all
  gather_facts: yes
  gather_subset:
    - '!all'
    - '!min'
    - network        # on ne collecte QUE le réseau
```

**Quand désactiver ?**

* ✅ Le playbook n'utilise **aucune** variable `ansible_*`
* ✅ Parc de plusieurs centaines de machines où chaque seconde compte
* ❌ **Ne pas** désactiver si vous utilisez des conditions sur l'OS, des templates avec des
  IP, ou tout fait de la machine

> 💡 Pour un parc important, activez plutôt le **cache de facts** (`fact_caching = jsonfile`
> dans `ansible.cfg`) : les facts sont collectés une fois puis réutilisés pendant une durée
> configurable.

</details>

---

## Partie 5 — Mise en situation : intervention d'urgence

### 1. Un disque sature. Identifiez en une commande les nœuds dont `/` dépasse 50 % d'utilisation.

<details><summary>Correction</summary>

```bash
ansible all -m shell -a "df -h / | tail -1 | awk '{print \$5}'" -o
```

Version plus lisible avec le seuil appliqué côté cible :

```bash
ansible all -m shell -a "df --output=pcent / | tail -1 | tr -d ' %'" -o
```

> 💡 Ici `shell` est justifié : on a besoin de pipes. Un module dédié n'existe pas pour ce
> besoin de reporting ponctuel.
>
> Alternative sans shell, en exploitant les facts :
> ```bash
> ansible all -m setup -a "filter=ansible_mounts"
> ```

</details>

---

### 2. Appliquez le correctif d'urgence : purger le cache APT et les logs de plus de 7 jours, sur tout le parc.

<details><summary>Correction</summary>

```bash
# 1. Toujours vérifier la cible AVANT une action destructrice
ansible all --list-hosts

# 2. Purge du cache APT
ansible all -m apt -a "autoclean=yes autoremove=yes" --become

# 3. Rotation forcée des journaux systemd (garder 7 jours)
ansible all -m command -a "journalctl --vacuum-time=7d" --become

# 4. Contrôle du résultat
ansible all -m shell -a "df -h / | tail -1" -o
```

> 🔑 **Le réflexe `--list-hosts`** : avant toute commande à impact, vérifiez la liste exacte
> des machines ciblées. Un motif mal écrit (`all` au lieu de `web`) sur un parc de
> production ne pardonne pas.

**Deux options de sécurité supplémentaires :**

```bash
# --check : mode simulation, rien n'est modifié
ansible all -m apt -a "name=nginx state=present" --become --check

# --limit : restreindre la cible même si le motif est large
ansible all -m apt -a "name=nginx state=present" --become --limit node1
```

</details>

---

### 3. Nettoyez l'environnement pour le lab suivant.

<details><summary>Correction</summary>

```bash
ansible web -m service -a "name=apache2 state=stopped" --become
ansible web -m apt -a "name=apache2 state=absent purge=yes autoremove=yes" --become
ansible all -m user -a "name=deployer state=absent remove=yes" --become
ansible all -m file -a "path=/opt/monapp state=absent" --become

# Vérification
ansible all -m command -a "ls /opt/" -o
```

</details>

---

## À retenir

| Point clé | Détail |
|:---|:---|
| **Structure ad-hoc** | `ansible <motif> -m <module> -a "<args>" [-b]` |
| **Quand l'utiliser** | Action ponctuelle, diagnostic, urgence. Pas pour du récurrent → playbook. |
| **`command` vs `shell`** | `command` ne passe pas par un shell (plus sûr). `shell` interprète pipes et variables. |
| **Toujours `changed`** | `command`, `shell`, `raw`, et `service state=restarted`. |
| **Idempotence** | Un module dédié vérifie l'état avant d'agir → `ok` si déjà conforme. |
| **`--check`** | Mode simulation : voir l'impact sans rien modifier. |
| **`--list-hosts`** | Le réflexe de sécurité avant toute action. |
| **Facts** | Collectés automatiquement par `setup`. `filter=` pour ne voir que l'utile. |
| **`ansible-doc`** | La documentation de VOTRE version, hors ligne. |

### Les 8 modules à connaître par cœur

| Module | Usage |
|:---|:---|
| `ping` | Valider SSH + Python |
| `setup` | Découvrir les facts |
| `command` / `shell` | Exécuter une commande (en dernier recours) |
| `copy` / `template` | Déposer un fichier |
| `file` | Répertoires, permissions, liens, suppression |
| `apt` / `package` | Gérer les paquets |
| `user` / `group` | Gérer les comptes |
| `service` / `systemd` | Gérer les services |

---

⬅️ **Lab précédent :** [Lab 02 — Installation, SSH et inventaires](<../lab 02 - Installation, SSH et inventaires/instructions.md>)
➡️ **Lab suivant :** [Lab 04 — Premier playbook et stack LAMP](<../lab 04 - Premier playbook et stack LAMP/instructions.md>)
