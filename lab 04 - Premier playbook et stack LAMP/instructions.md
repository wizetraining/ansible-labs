# Lab 04 — Premier playbook et stack LAMP

> ⭐ Niveau : ⭐⭐ → ⭐⭐⭐ | ⏱ Durée estimée : 120 min | Module : **M4 — Playbooks : structure, variables & handlers**

> 📌 **C'est le lab le plus long de la formation.** Il est volontairement progressif :
> les premières parties sont très guidées, les dernières demandent de combiner
> plusieurs notions. Les exercices vraiment complexes (Apache + PHP, MySQL,
> templates, Vault) sont regroupés en fin de lab.
>
> Chaque exercice est découpé en **tâches numérotées**, avec une correction par tâche.
> Traitez-les dans l'ordre : chaque tâche s'appuie sur la précédente.

## Objectifs pédagogiques

* Écrire un playbook YAML valide et comprendre ses sections
* Enchaîner les modules essentiels : `debug`, `apt`, `user`, `group`, `file`, `copy`, `lineinfile`
* Définir des variables à plusieurs niveaux et connaître leur priorité
* Exploiter `register`, `ignore_errors` et `when` pour diagnostiquer un échec
* Utiliser les handlers pour ne redémarrer un service que si nécessaire
* Déployer une stack LAMP complète (Apache + PHP, MariaDB)
* Externaliser variables et secrets avec `vars_files`

## Notions abordées

* Structure d'un playbook : play, `hosts`, `vars`, `tasks`, `handlers`
* Sections `pre_tasks` / `post_tasks`
* Variables : `vars`, `vars_files`, `group_vars/`, `host_vars/`, `--extra-vars`
* Priorité des variables (les 22 niveaux, en pratique)
* `register`, `ignore_errors`, `failed_when`, `when` — première approche
* `notify` / `handlers` : déclenchement sur `changed` uniquement
* Filtre `password_hash` et hachage des mots de passe
* Modes de vérification : `--syntax-check`, `--check`, `--diff`, `--step`

## Documentation de référence

* [Intro to playbooks](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_intro.html)
* [Using variables](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html)
* [Handlers](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_handlers.html)
* [Hashing and encrypting strings and passwords](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_filters.html#hashing-and-encrypting-strings-and-passwords)

## Contexte

L'équipe applicative a besoin d'un environnement LAMP reproductible : **Apache + PHP** sur
les serveurs web, **MariaDB** sur le serveur de base de données. Aujourd'hui, ce
déploiement prend une demi-journée et le résultat diffère d'un serveur à l'autre.

Vous allez y arriver par étapes : d'abord des playbooks d'une seule tâche, puis la gestion
des utilisateurs et des fichiers, puis le diagnostic d'un service qui refuse de démarrer, et
enfin la stack complète.

## Parcours du lab

| Partie | Thème | Exercices | Difficulté |
|:---|:---|:---|:---|
| 1 | Le playbook minimal | 1 | ⭐ |
| 2 | Inventaire et modules de base | 2, 3.1, 4, 5, 10, 11 | ⭐ |
| 3 | Variables et priorité | V1, V2, V3 | ⭐⭐ |
| 4 | Utilisateurs, groupes et fichiers système | 6, 3.2, 13, 12 | ⭐⭐ |
| 5 | Handlers et diagnostic d'un service en échec | H1, 7, 7.2 | ⭐⭐⭐ |
| 6 | La stack LAMP complète | 9, 8, final | ⭐⭐⭐ |
| 7 | Variables externes et secrets | 14 | ⭐⭐⭐ |
| 8 | Diagnostic et nettoyage | D1, D2 | ⭐⭐ |

---

## Partie 1 — Le playbook minimal

### Exercice 1 — Votre premier playbook

**Spécifications :**

| Élément | Valeur |
|:---|:---|
| Fichier | `/tp/playbooks/exo01-hello.yml` |
| Nom du play | `Exercice 1 - Hello Lab` |
| Cible | tous les hôtes de l'inventaire |
| Collecte des facts | désactivée (tâches 1 et 2) |

---

**Tâche 1 —** Écrivez une tâche nommée `Afficher un message` qui affiche exactement le texte
suivant sur chaque hôte :

```
Hello Lab!
```

Quel module avez-vous utilisé ? Consultez sa documentation avec `ansible-doc`.

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/playbooks/exo01-hello.yml
---
- name: Exercice 1 - Hello Lab
  hosts: all
  gather_facts: false

  tasks:
    - name: Afficher un message
      ansible.builtin.debug:
        msg: "Hello Lab!"
```

```bash
cd /tp
ansible-playbook playbooks/exo01-hello.yml
```

**Le module est `ansible.builtin.debug`.** Il n'agit pas sur la cible : il affiche une
valeur. C'est l'outil n°1 de mise au point.

```bash
ansible-doc ansible.builtin.debug
```

**Anatomie du fichier :**

| Élément | Rôle |
|:---|:---|
| `---` | Début de document YAML (conventionnel) |
| `- name:` | Nom du **play** — le tiret indique une liste de plays |
| `hosts:` | Le motif de cibles (**obligatoire**) |
| `gather_facts:` | Collecte des facts (`true` par défaut) |
| `tasks:` | La liste ordonnée des tâches |

</details>

---

**Tâche 2 —** Ajoutez une seconde tâche nommée `Message personnalisé` qui affiche le nom de
la machine, sous la forme :

```
Hello Lab depuis node1 !
```

<details><summary>Correction — tâche 2</summary>

```yaml
    - name: Message personnalisé
      ansible.builtin.debug:
        msg: "Hello Lab depuis {{ inventory_hostname }} !"
```

`inventory_hostname` est une **variable magique** : le nom de l'hôte courant tel qu'il
figure dans l'inventaire. Elle est toujours disponible, même sans collecte de facts.

</details>

---

**Tâche 3 —** Ajoutez une troisième tâche qui affiche la **variable** `inventory_hostname`
(et non un message la contenant). Quelle est la différence d'écriture avec la tâche 2 ?

<details><summary>Correction — tâche 3</summary>

```yaml
    - name: Afficher une variable brute
      ansible.builtin.debug:
        var: inventory_hostname
```

Sortie :

```
ok: [node1] => {
    "inventory_hostname": "node1"
}
```

> ⚠️ **La différence, et le piège le plus fréquent chez les débutants :**
>
> | Paramètre | Écriture | Usage |
> |:---|:---|:---|
> | `var:` | le nom **sans** `{{ }}` | Inspecter le contenu d'une variable |
> | `msg:` | une chaîne **avec** `{{ }}` | Composer un message lisible |
>
> ```yaml
> - ansible.builtin.debug:
>     var: ansible_default_ipv4.address          # ✅ correct
>
> - ansible.builtin.debug:
>     msg: "IP = {{ ansible_default_ipv4.address }}"   # ✅ correct
>
> - ansible.builtin.debug:
>     var: "{{ inventory_hostname }}"            # ❌ affiche la VALEUR comme un nom
> ```

**Variante utile — n'afficher qu'en mode verbeux :**

```yaml
    - ansible.builtin.debug:
        msg: "Détail technique"
        verbosity: 2       # visible seulement avec -vv
```

</details>

---

### Exercice 1.2 — Valider avant d'exécuter

**Tâche 1 —** Vérifiez la syntaxe de votre playbook **sans vous connecter** aux machines.

<details><summary>Correction — tâche 1</summary>

```bash
ansible-playbook playbooks/exo01-hello.yml --syntax-check
```

Sortie attendue :

```
playbook: playbooks/exo01-hello.yml
```

Aucune connexion SSH n'est établie : Ansible se contente de parser le YAML et de valider la
structure du playbook. C'est instantané, et c'est le premier réflexe avant toute exécution.

</details>

---

**Tâche 2 —** Cassez volontairement le playbook en décalant `hosts:` d'un espace
supplémentaire, relancez la validation, et notez le message obtenu.

<details><summary>Correction — tâche 2</summary>

```yaml
- name: Exercice 1 - Hello Lab
   hosts: all          # ← 3 espaces au lieu de 2
```

```bash
ansible-playbook playbooks/exo01-hello.yml --syntax-check
```

```
ERROR! We were unable to read either as JSON nor YAML
mapping values are not allowed in this context
```

**Les 5 erreurs YAML les plus fréquentes :**

| Erreur | Symptôme | Correction |
|:---|:---|:---|
| Tabulation au lieu d'espaces | `found character '\t'` | YAML **interdit** les tabulations |
| Indentation incohérente | `mapping values are not allowed` | 2 espaces par niveau, partout |
| Deux-points dans une valeur non quotée | `could not find expected ':'` | Quoter : `msg: "Erreur: échec"` |
| `{{ }}` en début de valeur non quotée | `found unexpected '{'` | Quoter : `msg: "{{ var }}"` |
| Tiret manquant devant une tâche | La tâche est absorbée par la précédente | Chaque tâche commence par `-` |

> 🔑 **Réflexes :** `--syntax-check` avant chaque exécution, et configurez votre éditeur
> pour afficher les espaces et convertir les tabulations. Au Lab 10, `ansible-lint` ira
> beaucoup plus loin.

**Rétablissez l'indentation correcte avant de continuer.**

</details>

---

## Partie 2 — Inventaire et modules de base

### Exercice 2 — Réorganiser l'inventaire et installer un paquet

**Spécifications de l'inventaire :**

| Groupe | Membres |
|:---|:---|
| `web_servers` | `node1`, `node2` |
| `db_servers` | `node3` |
| `prod` (parent) | `web_servers` + `db_servers` |

Variables du groupe `prod` : `env: production`, `ansible_user: admin`.

---

**Tâche 1 —** Réécrivez `/tp/inventory.yml` conformément à ces spécifications, puis
affichez la hiérarchie obtenue.

<details><summary>Correction — tâche 1</summary>

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
        web_servers:
          hosts:
            node1:
            node2:
        db_servers:
          hosts:
            node3:
```

```bash
ansible-inventory --graph
```

```
@all:
  |--@prod:
  |  |--@db_servers:
  |  |  |--node3
  |  |--@web_servers:
  |  |  |--node1
  |  |  |--node2
```

**Contrôle de la connectivité :**

```bash
ansible web_servers --list-hosts
ansible all -m ping
```

> 💡 **Note de cohérence :** les labs précédents utilisaient les groupes `web` et `db`.
> Un hôte peut appartenir à **plusieurs groupes** (vu au Lab 02) — vous pouvez donc
> conserver les deux jeux de noms. Les labs suivants reviendront à `web` / `db`.

</details>

---

**Tâche 2 —** Écrivez `/tp/playbooks/exo02-git.yml` qui installe le paquet `git`
uniquement sur `web_servers`. Le cache APT doit être rafraîchi.

<details><summary>Correction — tâche 2</summary>

```yaml
# /tp/playbooks/exo02-git.yml
---
- name: Exercice 2 - Installation de Git
  hosts: web_servers
  become: true

  tasks:
    - name: Installer Git
      ansible.builtin.apt:
        name: git
        state: present
        update_cache: true
```

```bash
ansible-playbook playbooks/exo02-git.yml
ansible web_servers -m command -a "git --version" -o
ansible db_servers -m command -a "git --version" -o    # doit échouer : non installé
```

> ⚠️ `become: true` est indispensable : installer un paquet exige les droits root.

</details>

---

**Tâche 3 —** Quel module avez-vous utilisé ? Consultez sa documentation, puis **donnez son
avantage et son inconvénient** face au module générique équivalent.

<details><summary>Correction — tâche 3</summary>

```bash
ansible-doc ansible.builtin.apt | head -40
ansible-doc ansible.builtin.package | head -30
```

**`apt` ou `package` ? Les deux fonctionnent ici :**

| Module | Avantages | Inconvénients |
|:---|:---|:---|
| **`package`** | Générique — masque les détails de distribution. Le **même** playbook fonctionne sur Debian, RedHat, SUSE… | Moins de contrôle : pas d'accès aux options spécifiques (`purge`, `autoremove`, `deb`, `cache_valid_time`, `dpkg_options`) |
| **`apt`** | Accès aux fonctionnalités avancées de Debian/Ubuntu, contrôle fin du cache et des dépendances | Moins portable : un playbook `apt` ne tourne pas sur RHEL. Plus de maintenance si le parc est hétérogène |

```yaml
# Version portable multi-distribution
- name: Installer Git (portable)
  ansible.builtin.package:
    name: git
    state: present
```

> 🔑 **La règle en pratique :** parc homogène → `apt` (plus de contrôle). Parc hétérogène
> ou rôle destiné à être partagé → `package`, ou `apt`/`dnf` avec une condition `when` sur
> `ansible_os_family` (voir Lab 05).

> ⚠️ **Évitez `state: latest` en production.** Il rend le playbook non déterministe : le
> résultat dépend du jour où vous le jouez. Deux environnements provisionnés à une semaine
> d'écart n'auront pas les mêmes versions. Préférez `state: present`.

</details>

---

### Exercice 3.1 — Créer un utilisateur simple

**Spécifications :**

| Attribut | Valeur |
|:---|:---|
| Nom | `ansible_user` |
| Cible | tous les hôtes |
| État | présent |
| Fichier | `/tp/playbooks/exo03-user.yml` |

---

**Tâche 1 —** Écrivez le playbook qui crée cet utilisateur, puis vérifiez sa présence.

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/playbooks/exo03-user.yml
---
- name: Exercice 3.1 - Création d'utilisateur
  hosts: all
  become: true

  tasks:
    - name: Créer un utilisateur
      ansible.builtin.user:
        name: ansible_user
        state: present
```

```bash
ansible-playbook playbooks/exo03-user.yml
ansible all -m command -a "id ansible_user" -o
```

</details>

---

**Tâche 2 —** Rejouez **exactement** le même playbook. Quel statut obtenez-vous, et
pourquoi ? Comparez avec ce que ferait `useradd ansible_user` lancé deux fois.

<details><summary>Correction — tâche 2</summary>

```bash
ansible-playbook playbooks/exo03-user.yml
```

```
TASK [Créer un utilisateur] ****
ok: [node1]
ok: [node2]
ok: [node3]

PLAY RECAP
node1 : ok=1  changed=0
```

**Statut `ok`, `changed=0`.** Le module `user` a **inspecté l'état actuel** de la machine,
constaté que le compte existait déjà avec les bons attributs, et n'a rien fait.

**Comparaison avec la commande brute :**

```bash
ansible node1 -m command -a "useradd ansible_user" --become
```

```
useradd: user 'ansible_user' already exists
non-zero return code
```

| | `useradd` | module `user` |
|:---|:---|:---|
| 1re exécution | crée le compte | `changed` |
| 2e exécution | **échoue** | `ok` — rien à faire |
| Notion d'état désiré | ❌ impératif | ✅ déclaratif |

> 🔑 **C'est l'idempotence.** Elle permet de rejouer un playbook sans crainte, et rend le
> statut `changed` fiable : il signale un **vrai** changement sur le parc.

</details>

---

### Exercice 4 — Créer un répertoire avec des attributs précis

**Spécifications :**

| Attribut | Valeur |
|:---|:---|
| Chemin | `/var/www/html` |
| Type | répertoire |
| Propriétaire | `www-data` |
| Groupe | `www-data` |
| Permissions | `0755` |
| Cible | `web_servers` |

---

**Tâche 1 —** Écrivez `/tp/playbooks/exo04-repertoire.yml` respectant ces spécifications,
puis vérifiez le résultat avec `ls -ld`.

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/playbooks/exo04-repertoire.yml
---
- name: Exercice 4 - Création de répertoire
  hosts: web_servers
  become: true

  tasks:
    - name: Créer le répertoire racine du site
      ansible.builtin.file:
        path: /var/www/html
        state: directory
        owner: www-data
        group: www-data
        mode: "0755"
```

```bash
ansible-playbook playbooks/exo04-repertoire.yml
ansible web_servers -m command -a "ls -ld /var/www/html" -o
```

Résultat attendu :

```
drwxr-xr-x 2 www-data www-data 4096 ... /var/www/html
```

> 💡 Si `www-data` n'existe pas encore (Apache pas installé sur cette machine), remplacez
> temporairement par `owner: root`. Ce compte est créé par le paquet `apache2`.

</details>

---

**Tâche 2 —** Remplacez `mode: "0755"` par `mode: 0755` (sans guillemets) et relancez.
Que constatez-vous sur les permissions ?

<details><summary>Correction — tâche 2</summary>

```bash
ansible-playbook playbooks/exo04-repertoire.yml --diff
ansible web_servers -m command -a "ls -ld /var/www/html" -o
```

Selon la version d'Ansible, vous obtiendrez soit un avertissement, soit des permissions
**inattendues** (`drwx--x--t` ou équivalent).

> ⚠️ **Le piège du mode.** Sans guillemets, YAML interprète `0755` comme un **entier
> décimal** (755), pas comme une valeur octale. Ansible reçoit alors 755 en base 10, ce qui
> ne correspond pas aux permissions voulues.
>
> **Écrivez toujours `mode: "0755"` entre guillemets.** C'est également une règle
> `ansible-lint` (`risky-file-permissions`), que vous rencontrerez au Lab 10.

**Rétablissez `mode: "0755"` avant de continuer.**

**Les valeurs de `state` du module `file` :**

| `state` | Effet |
|:---|:---|
| `directory` | Crée le répertoire **et ses parents** (comme `mkdir -p`) |
| `touch` | Crée un fichier vide s'il n'existe pas |
| `file` | Vérifie qu'il existe (n'en crée **pas**) et ajuste les attributs |
| `absent` | Supprime (récursivement pour un répertoire) |
| `link` / `hard` | Crée un lien symbolique / physique |

</details>

---

### Exercice 5 — Copier un fichier vers les cibles

**Spécifications :**

| Élément | Valeur |
|:---|:---|
| Fichier source (sur le controller) | `/tp/files/index.html` |
| Destination | `/var/www/html/index.html` |
| Propriétaire / groupe | `root` / `root` |
| Permissions | `0644` |
| Cible | `web_servers` |

Contenu attendu du fichier source : une page HTML simple avec un titre `Lab Ansible` et un
en-tête `<h1>` de votre choix.

---

**Tâche 1 —** Créez le fichier `index.html` sur le nœud de contrôle.

<details><summary>Correction — tâche 1</summary>

```bash
mkdir -p /tp/files

cat > /tp/files/index.html <<'EOF'
<!DOCTYPE html>
<html lang="fr">
  <head><meta charset="utf-8"><title>Lab Ansible</title></head>
  <body>
    <h1>Bienvenue sur le lab Ansible</h1>
    <p>Cette page a été déployée automatiquement.</p>
  </body>
</html>
EOF

cat /tp/files/index.html
```

> 💡 Le répertoire `files/` est la convention Ansible pour les fichiers statiques copiés
> tels quels. Le pendant pour les fichiers Jinja2 est `templates/` (exercice 9).

</details>

---

**Tâche 2 —** Écrivez `/tp/playbooks/exo05-copie.yml` qui déploie ce fichier avec les
attributs demandés, puis vérifiez le contenu sur les cibles.

<details><summary>Correction — tâche 2</summary>

```yaml
# /tp/playbooks/exo05-copie.yml
---
- name: Exercice 5 - Copie de fichier
  hosts: web_servers
  become: true

  tasks:
    - name: Copier la page d'accueil
      ansible.builtin.copy:
        src: /tp/files/index.html
        dest: /var/www/html/index.html
        owner: root
        group: root
        mode: "0644"
```

```bash
ansible-playbook playbooks/exo05-copie.yml
ansible web_servers -m command -a "cat /var/www/html/index.html"
ansible web_servers -m command -a "ls -l /var/www/html/index.html" -o
```

**Testez l'idempotence :** rejouez → `changed=0`. Le module `copy` compare les **sommes de
contrôle** du fichier source et du fichier distant, et ne transfère que s'ils diffèrent.

</details>

---

**Tâche 3 —** Réécrivez la même tâche **sans fichier source**, en plaçant le contenu
directement dans le playbook. Dans quel cas cette variante est-elle préférable ?

<details><summary>Correction — tâche 3</summary>

```yaml
    - name: Copier la page d'accueil (contenu inline)
      ansible.builtin.copy:
        content: |
          <!DOCTYPE html>
          <html lang="fr">
            <head><meta charset="utf-8"><title>Lab Ansible</title></head>
            <body><h1>Bienvenue sur {{ inventory_hostname }}</h1></body>
          </html>
        dest: /var/www/html/index.html
        owner: root
        mode: "0644"
```

**Les trois usages du module `copy` :**

| Paramètre | Source | Cas d'usage |
|:---|:---|:---|
| `src:` | fichier du **controller** | Le plus courant — fichier versionné dans le projet |
| `content:` | chaîne inline | Petit fichier, quelques lignes, pas de fichier séparé à gérer |
| `remote_src: true` | fichier **de la cible** | Copier d'un endroit à un autre sur la machine distante |

> ⚠️ **Le piège `remote_src`.** Par défaut, `src:` désigne un fichier **du controller**.
> Pour dupliquer un fichier déjà présent sur la cible (une sauvegarde de configuration, par
> exemple), il faut `remote_src: true` — sinon Ansible cherche le fichier sur le controller
> et échoue avec `Could not find or access`.

> 💡 **Modules connexes :**
> * `template` — comme `copy` mais avec rendu Jinja2 (exercice 9)
> * `fetch` — l'inverse : récupère un fichier **depuis** les cibles
> * `lineinfile` — modifie **une ligne** dans un fichier existant (exercice 6)
> * `synchronize` — wrapper rsync, pour des arborescences volumineuses

</details>

---

### Exercice 10 — Mettre à jour le système

**Spécifications :**

| Élément | Valeur |
|:---|:---|
| Fichier | `/tp/playbooks/exo10-maj.yml` |
| Cible | tous les hôtes |
| Cache APT | rafraîchi, valide 1 heure |
| Type de mise à jour | complète (`dist-upgrade`) |

---

**Tâche 1 —** Écrivez les deux tâches : rafraîchissement du cache, puis mise à jour
complète de la distribution.

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/playbooks/exo10-maj.yml
---
- name: Exercice 10 - Mise à jour du système
  hosts: all
  become: true

  tasks:
    - name: Mettre à jour le cache APT
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600

    - name: Mise à jour complète de la distribution
      ansible.builtin.apt:
        upgrade: dist
```

```bash
ansible-playbook playbooks/exo10-maj.yml
```

**Les valeurs de `upgrade` :**

| Valeur | Équivalent APT |
|:---|:---|
| `yes` / `safe` | `apt-get upgrade` — n'installe ni ne supprime de paquets |
| `full` / `dist` | `apt-get dist-upgrade` — peut installer/supprimer pour résoudre les dépendances |
| `no` | Aucune mise à jour (défaut) |

> 💡 `cache_valid_time: 3600` évite de rafraîchir le cache APT s'il a moins d'une heure —
> gain de temps notable sur un parc important.

</details>

---

**Tâche 2 —** Ajoutez deux tâches qui détectent si un redémarrage est nécessaire (présence
du fichier `/var/run/reboot-required`) et affichent un avertissement le cas échéant.

<details><summary>Correction — tâche 2</summary>

```yaml
    - name: Vérifier si un redémarrage est nécessaire
      ansible.builtin.stat:
        path: /var/run/reboot-required
      register: reboot

    - name: Alerter sur le redémarrage
      ansible.builtin.debug:
        msg: "⚠️ {{ inventory_hostname }} nécessite un redémarrage"
      when: reboot.stat.exists
```

```bash
ansible-playbook playbooks/exo10-maj.yml
```

**Le module `stat`** inspecte un fichier et renvoie ses métadonnées. La clé qui nous
intéresse ici est `stat.exists` (booléen).

```yaml
# Explorer tout ce que stat renvoie
- ansible.builtin.debug:
    var: reboot
```

> ⚠️ **En production, une mise à jour complète ne se joue jamais sur tout le parc en même
> temps.** On la combine avec `serial:` pour traiter les machines par lots (Lab 09), et on
> vérifie le service après chaque lot.

</details>

---

### Exercice 11 — Créer un utilisateur avec privilèges sudo

**Spécifications :**

| Attribut | Valeur |
|:---|:---|
| Nom | `lab1` |
| Shell | `/bin/bash` |
| Groupe secondaire | `sudo` |
| Groupes existants | **conservés** |
| Cible | tous les hôtes |

---

**Tâche 1 —** Créez l'utilisateur et ajoutez-le au groupe `sudo`, **en une seule tâche**.

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/playbooks/exo11-sudo.yml
---
- name: Exercice 11 - Création d'utilisateur avec sudo
  hosts: all
  become: true

  tasks:
    - name: Créer l'utilisateur lab1 et l'ajouter au groupe sudo
      ansible.builtin.user:
        name: lab1
        groups: sudo
        append: true          # ⭐ ne PAS écraser les groupes existants
        shell: /bin/bash
        state: present
```

```bash
ansible-playbook playbooks/exo11-sudo.yml
ansible all -m command -a "id lab1" -o
```

> 💡 Le module `user` gère la création **et** l'appartenance aux groupes simultanément :
> une seule tâche suffit, inutile d'en écrire deux.

</details>

---

**Tâche 2 —** Retirez `append: true`, ajoutez `groups: users` à la place de `sudo`, et
relancez. Que devient l'appartenance de `lab1` au groupe `sudo` ?

<details><summary>Correction — tâche 2</summary>

```yaml
      ansible.builtin.user:
        name: lab1
        groups: users        # sans append
```

```bash
ansible-playbook playbooks/exo11-sudo.yml
ansible all -m command -a "id lab1" -o
```

**`lab1` a perdu son appartenance au groupe `sudo`.**

> ⚠️ **Le piège d'`append`.** Sans `append: true`, l'option `groups` **remplace**
> l'intégralité des groupes secondaires. Un compte peut ainsi perdre `sudo`, `docker` ou
> `adm` sans que vous l'ayez voulu — et sans le moindre avertissement.
>
> **Mettez `append: true` par défaut**, sauf si vous voulez explicitement réinitialiser les
> groupes d'un compte.

**Rétablissez la version de la tâche 1 avant de continuer.**

</details>

---

**Tâche 3 —** Accordez à `lab1` le droit d'utiliser `sudo` **sans mot de passe**, via un
fichier dédié dans `/etc/sudoers.d/`. Le fichier doit être validé avant d'être écrit.

<details><summary>Correction — tâche 3</summary>

```yaml
    - name: Accorder sudo sans mot de passe à lab1
      ansible.builtin.copy:
        dest: /etc/sudoers.d/lab1
        content: "lab1 ALL=(ALL) NOPASSWD:ALL\n"
        owner: root
        group: root
        mode: "0440"
        validate: 'visudo -cf %s'     # ⭐ valide AVANT d'écrire
```

```bash
ansible-playbook playbooks/exo11-sudo.yml --check --diff
ansible-playbook playbooks/exo11-sudo.yml
ansible all -m command -a "sudo -l -U lab1" --become -o
```

> 🔑 **`validate:` est ici critique.** Un `/etc/sudoers` invalide peut rendre `sudo`
> totalement inutilisable sur la machine — et donc vous en verrouiller définitivement.
>
> Avec `validate`, Ansible :
> 1. génère le fichier dans un emplacement **temporaire**
> 2. exécute `visudo -cf <fichier temporaire>` (le `%s` est remplacé par ce chemin)
> 3. n'écrit à destination **que si** la commande réussit
>
> **Testez la protection** — introduisez volontairement une erreur :
> ```yaml
>         content: "CETTE LIGNE EST INVALIDE\n"
> ```
> La tâche échoue avec `Validation failed`, et `/etc/sudoers.d/lab1` **n'est pas modifié**.

**Les commandes de validation à connaître :**

| Fichier | Commande |
|:---|:---|
| `sudoers` | `visudo -cf %s` |
| `sshd_config` | `sshd -t -f %s` |
| VirtualHost Apache | `apache2ctl -f %s -t` |
| Config Nginx | `nginx -t -c %s` |

</details>

---

## Partie 3 — Variables et priorité

### Exercice V1 — Déclarer et exploiter des variables

**Spécifications — variables à déclarer dans la section `vars:` du play :**

| Variable | Type | Valeur |
|:---|:---|:---|
| `app_name` | chaîne | `monapp` |
| `app_version` | chaîne | `"2.1.0"` (quotée) |
| `app_port` | entier | `8080` |
| `app_features` | liste | `authentification`, `cache`, `metrics` |
| `app_config` | dictionnaire | `timeout: 30`, `max_connections: 100` |

| Élément | Valeur |
|:---|:---|
| Fichier | `/tp/playbooks/exo-variables.yml` |
| Cible | `web_servers` |
| Collecte des facts | activée |

---

**Tâche 1 —** Déclarez les cinq variables, puis écrivez une tâche qui affiche exactement :

```
Application monapp v2.1.0 sur le port 8080
```

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/playbooks/exo-variables.yml
---
- name: Découverte des variables
  hosts: web_servers
  gather_facts: true

  vars:
    app_name: monapp
    app_version: "2.1.0"
    app_port: 8080
    app_features:
      - authentification
      - cache
      - metrics
    app_config:
      timeout: 30
      max_connections: 100

  tasks:
    - name: Afficher les informations applicatives
      ansible.builtin.debug:
        msg: "Application {{ app_name }} v{{ app_version }} sur le port {{ app_port }}"
```

```bash
ansible-playbook playbooks/exo-variables.yml
```

Sortie :

```
ok: [node1] => {
    "msg": "Application monapp v2.1.0 sur le port 8080"
}
```

> 💡 **Types YAML :** `app_version: "2.1.0"` doit être quoté, sinon YAML pourrait
> l'interpréter comme un nombre — et `"2.10"` deviendrait `2.1`. `app_port: 8080` reste un
> entier. **Quotez systématiquement les versions** et les valeurs commençant par `0`.

</details>

---

**Tâche 2 —** Ajoutez une tâche qui affiche le **premier élément** de la liste
`app_features` :

```
Première fonctionnalité : authentification
```

<details><summary>Correction — tâche 2</summary>

```yaml
    - name: Afficher un élément de liste
      ansible.builtin.debug:
        msg: "Première fonctionnalité : {{ app_features[0] }}"
```

**Accéder à une liste :**

```yaml
{{ app_features[0] }}          # premier élément     → authentification
{{ app_features[-1] }}         # dernier élément     → metrics
{{ app_features | length }}    # nombre d'éléments   → 3
{{ app_features | join(', ') }}  # liste en chaîne   → authentification, cache, metrics
```

> ⚠️ Les indices commencent à **0**. `app_features[3]` sur une liste de 3 éléments
> provoque une erreur `list object has no element 3`.

</details>

---

**Tâche 3 —** Ajoutez une tâche qui affiche la valeur `timeout` du dictionnaire
`app_config` :

```
Timeout = 30s
```

<details><summary>Correction — tâche 3</summary>

```yaml
    - name: Afficher un élément de dictionnaire
      ansible.builtin.debug:
        msg: "Timeout = {{ app_config.timeout }}s"
```

**Deux notations équivalentes pour un dictionnaire :**

```yaml
{{ app_config.timeout }}          # notation pointée — la plus lisible
{{ app_config['timeout'] }}       # notation crochets — obligatoire si la clé
                                  # contient un tiret ou un espace
```

> ⚠️ **Quand la notation pointée échoue :** si une clé s'appelle `max-connections`
> (avec un tiret), `app_config.max-connections` est interprété comme une soustraction.
> Utilisez alors `app_config['max-connections']`.

**Affichez le dictionnaire entier pour vérifier :**

```yaml
    - ansible.builtin.debug:
        var: app_config
```

</details>

---

**Tâche 4 —** Ajoutez une dernière tâche qui combine vos variables **et les facts** de la
machine, sous la forme :

```
monapp tourne sur node1 (Ubuntu 22.04) — 972 Mo de RAM
```

<details><summary>Correction — tâche 4</summary>

```yaml
    - name: Combiner variables et facts
      ansible.builtin.debug:
        msg: >-
          {{ app_name }} tourne sur {{ inventory_hostname }}
          ({{ ansible_distribution }} {{ ansible_distribution_version }})
          — {{ ansible_memtotal_mb }} Mo de RAM
```

```bash
ansible-playbook playbooks/exo-variables.yml
```

> 💡 **Le bloc `>-`** est un scalaire YAML replié : il permet d'écrire un message long sur
> plusieurs lignes, qui sera rendu sur **une seule** ligne. Le `-` supprime le saut de ligne
> final. Indispensable pour rester sous les 100 colonnes sans casser le message.

> ⚠️ **`gather_facts: true` est obligatoire** pour utiliser `ansible_distribution` ou
> `ansible_memtotal_mb`. Avec `gather_facts: false`, la tâche échoue avec
> `'ansible_distribution' is undefined`.

</details>

---

### Exercice V2 — Externaliser les variables

**Spécifications — fichiers à créer :**

| Fichier | Variables |
|:---|:---|
| `/tp/group_vars/all.yml` | `env: production`, `admin_email: ops@example.com`, `timezone: Europe/Paris` |
| `/tp/group_vars/web_servers.yml` | `http_port: 80`, `app_name: monapp`, `document_root: /var/www/monapp`, `php_version: "8.1"` |
| `/tp/group_vars/db_servers.yml` | `db_port: 3306`, `db_name: monapp_db`, `db_user: monapp` |
| `/tp/host_vars/node1.yml` | `server_role: primary`, `http_port: 8080` |

---

**Tâche 1 —** Créez les quatre fichiers conformément au tableau.

<details><summary>Correction — tâche 1</summary>

```bash
mkdir -p /tp/group_vars /tp/host_vars
```

```yaml
# /tp/group_vars/all.yml — s'applique à TOUS les hôtes
---
env: production
admin_email: ops@example.com
timezone: Europe/Paris
```

```yaml
# /tp/group_vars/web_servers.yml — uniquement le groupe web_servers
---
http_port: 80
app_name: monapp
document_root: /var/www/monapp
php_version: "8.1"
```

```yaml
# /tp/group_vars/db_servers.yml — uniquement le groupe db_servers
---
db_port: 3306
db_name: monapp_db
db_user: monapp
```

```yaml
# /tp/host_vars/node1.yml — uniquement node1
---
server_role: primary
http_port: 8080          # surcharge la valeur de group_vars/web_servers.yml
```

> 💡 **Convention :** Ansible charge automatiquement `group_vars/<groupe>.yml` et
> `host_vars/<hôte>.yml` situés **à côté de l'inventaire** ou **à côté du playbook**.
> Aucun `include` n'est nécessaire — c'est la façon standard d'organiser un projet.
>
> Le nom du fichier doit correspondre **exactement** au nom du groupe ou de l'hôte.
> Un fichier `group_vars/webservers.yml` (sans underscore) ne serait jamais chargé.

</details>

---

**Tâche 2 —** Sans écrire de playbook, affichez les variables effectivement résolues pour
`node1` puis pour `node2`. Quelle valeur de `http_port` obtient chacun, et pourquoi ?

<details><summary>Correction — tâche 2</summary>

```bash
ansible-inventory --host node1 | jq
ansible-inventory --host node2 | jq
```

`node1` :

```json
{
  "admin_email": "ops@example.com",
  "ansible_user": "admin",
  "app_name": "monapp",
  "document_root": "/var/www/monapp",
  "env": "production",
  "http_port": 8080,          ← host_vars gagne
  "php_version": "8.1",
  "server_role": "primary",
  "timezone": "Europe/Paris"
}
```

`node2` :

```json
{
  "http_port": 80,            ← group_vars/web_servers.yml
  ...
}
```

**Explication :** `node1` reçoit `http_port` de deux sources — `group_vars/web_servers.yml`
(80) et `host_vars/node1.yml` (8080). Les `host_vars` ayant une **priorité supérieure** aux
`group_vars`, c'est 8080 qui l'emporte. `node2` n'a pas de `host_vars`, il conserve donc 80.

> 🔑 `ansible-inventory --host <hôte>` est l'outil de diagnostic à connaître : il montre la
> valeur **finale** de chaque variable, après résolution de toute la hiérarchie. Beaucoup
> plus rapide que d'écrire un playbook de `debug`.

</details>

---

**Tâche 3 —** Écrivez `/tp/playbooks/exo-groupvars.yml` (cible `web_servers`,
`gather_facts: false`) affichant pour chaque hôte :

```
node1 → port 8080 | env production | rôle primary
node2 → port 80 | env production | rôle standard
```

`node2` n'ayant pas de `server_role`, prévoyez une valeur de repli.

<details><summary>Correction — tâche 3</summary>

```yaml
# /tp/playbooks/exo-groupvars.yml
---
- name: Vérifier la résolution des variables
  hosts: web_servers
  gather_facts: false

  tasks:
    - name: Afficher les variables résolues
      ansible.builtin.debug:
        msg: >-
          {{ inventory_hostname }} → port {{ http_port }}
          | env {{ env }}
          | rôle {{ server_role | default('standard') }}
```

```bash
ansible-playbook playbooks/exo-groupvars.yml
```

> 🔑 **Le filtre `default()`** fournit une valeur de repli si la variable n'existe pas.
> Sans lui, `node2` ferait échouer le playbook avec `'server_role' is undefined`.
>
> C'est **le filtre le plus utilisé d'Ansible**. Il rend vos playbooks et vos templates
> tolérants aux variables absentes.
>
> ```yaml
> {{ var | default('valeur') }}          # si var n'est pas définie
> {{ var | default('valeur', true) }}    # si var est absente OU vide OU false
> {{ var | mandatory }}                  # échoue explicitement si absente
> ```

</details>

---

### Exercice V3 — Établir la priorité réelle

**Objectif :** surcharger la **même** variable `http_port` à quatre niveaux différents et
observer laquelle gagne.

| Niveau | Source | Valeur |
|:---|:---|:---|
| 1 | `group_vars/web_servers.yml` | `80` |
| 2 | `host_vars/node1.yml` | `8080` |
| 3 | `vars:` du play | `3000` |
| 4 | `vars:` de la tâche | `4000` |
| 5 | `--extra-vars` | `9999` |

---

**Tâche 1 —** Écrivez `/tp/playbooks/exo-priorite.yml` (cible `node1`) déclarant
`http_port: 3000` dans le play, avec une tâche qui affiche la variable. Quelle valeur
s'affiche ?

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/playbooks/exo-priorite.yml
---
- name: Test de priorité
  hosts: node1
  gather_facts: false

  vars:
    http_port: 3000          # niveau : play vars

  tasks:
    - name: Quelle valeur gagne ?
      ansible.builtin.debug:
        var: http_port
```

```bash
ansible-playbook playbooks/exo-priorite.yml
```

```
ok: [node1] => { "http_port": 3000 }
```

**`3000`.** Les `vars:` du play l'emportent sur `host_vars` (8080) et sur `group_vars` (80).

</details>

---

**Tâche 2 —** Ajoutez une seconde tâche qui redéfinit `http_port: 4000` **au niveau de la
tâche**. Quelle valeur s'affiche cette fois ?

<details><summary>Correction — tâche 2</summary>

```yaml
    - name: Surcharge au niveau de la tâche
      ansible.builtin.debug:
        var: http_port
      vars:
        http_port: 4000      # niveau : task vars
```

```bash
ansible-playbook playbooks/exo-priorite.yml
```

```
TASK [Quelle valeur gagne ?] ****
ok: [node1] => { "http_port": 3000 }

TASK [Surcharge au niveau de la tâche] ****
ok: [node1] => { "http_port": 4000 }
```

**`4000`.** Les `vars:` d'une tâche sont plus prioritaires que celles du play, mais leur
portée est **limitée à cette tâche** : la tâche suivante retrouverait 3000.

</details>

---

**Tâche 3 —** Relancez le playbook en imposant `http_port=9999` en ligne de commande.
Que constatez-vous sur les **deux** tâches ?

<details><summary>Correction — tâche 3</summary>

```bash
ansible-playbook playbooks/exo-priorite.yml -e "http_port=9999"
```

```
TASK [Quelle valeur gagne ?] ****
ok: [node1] => { "http_port": "9999" }

TASK [Surcharge au niveau de la tâche] ****
ok: [node1] => { "http_port": "9999" }
```

**`9999` partout — y compris sur la tâche qui déclarait pourtant `http_port: 4000`.**

> 🔑 **`--extra-vars` (`-e`) est le niveau le plus élevé de toute la hiérarchie.** Rien ne
> peut le contredire, pas même une variable de tâche. C'est ce qui en fait l'outil de
> surcharge ponctuelle par excellence — et ce qui le rend dangereux si on l'utilise par
> habitude.

> ⚠️ Notez que la valeur est devenue une **chaîne** (`"9999"` avec guillemets) et non un
> entier. Les variables passées en `-e` sur la ligne de commande sont des chaînes, sauf à
> utiliser la syntaxe JSON : `-e '{"http_port": 9999}'`.

</details>

---

**Tâche 4 —** Classez les sources de variables du plus faible au plus fort. Quelles sont
les **deux** règles à retenir en pratique ?

<details><summary>Correction — tâche 4</summary>

**Priorité en pratique (du plus faible au plus fort) :**

| Rang | Source | Exemple |
|:---|:---|:---|
| 1 | Défauts de rôle | `roles/x/defaults/main.yml` |
| 2 | `group_vars/all` | `group_vars/all.yml` |
| 3 | `group_vars/<groupe>` | `group_vars/web_servers.yml` |
| 4 | `host_vars/<hôte>` | `host_vars/node1.yml` |
| 5 | Facts | `ansible_distribution` |
| 6 | **Play `vars`** | `vars:` dans le play |
| 7 | `vars_files` | Fichier chargé par le play |
| 8 | **Task `vars`** | `vars:` sur une tâche |
| 9 | `set_fact` / `register` | Défini en cours d'exécution |
| 10 | Variables de rôle | `roles/x/vars/main.yml` |
| 11 | **`--extra-vars` (`-e`)** | ⚡ **Gagne TOUJOURS** |

> 🔑 **Les deux règles à retenir :**
> 1. `defaults/` d'un rôle = le plus faible → c'est **fait pour** être surchargé
> 2. `-e` en ligne de commande = le plus fort → rien ne peut le contredire
>
> Ansible définit officiellement **22 niveaux**. En pratique, ces deux règles couvrent 95 %
> des cas. La [documentation officielle](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html#understanding-variable-precedence)
> donne la liste exhaustive.

</details>

---

## Partie 4 — Utilisateurs, groupes et fichiers système

### Exercice 6 — Durcir la configuration SSH

**Spécifications :**

| Élément | Valeur |
|:---|:---|
| Fichier cible | `/etc/ssh/sshd_config` |
| Directive 1 | `PasswordAuthentication no` |
| Directive 2 | `PubkeyAuthentication yes` |
| Validation | `sshd -t -f %s` avant écriture |
| Rechargement | par **handler** uniquement si modification |
| Cible | tous les hôtes |

---

**Tâche 1 —** Écrivez la tâche qui désactive l'authentification par mot de passe. Le motif
`regexp:` doit capturer aussi bien la ligne active que la ligne commentée.

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/playbooks/exo06-ssh.yml
---
- name: Exercice 6 - Durcissement SSH
  hosts: all
  become: true

  tasks:
    - name: Désactiver l'authentification par mot de passe
      ansible.builtin.lineinfile:
        path: /etc/ssh/sshd_config
        regexp: '^#?\s*PasswordAuthentication'
        line: 'PasswordAuthentication no'
        state: present
        validate: 'sshd -t -f %s'
      notify: Redemarrer SSH

  handlers:
    - name: Redemarrer SSH
      ansible.builtin.service:
        name: ssh
        state: restarted
```

**Décomposition du motif `'^#?\s*PasswordAuthentication'` :**

| Fragment | Signification |
|:---|:---|
| `^` | début de ligne |
| `#?` | un `#` **optionnel** — capture les lignes commentées |
| `\s*` | zéro ou plusieurs espaces |
| `PasswordAuthentication` | la directive elle-même |

Il capture donc `PasswordAuthentication yes`, `#PasswordAuthentication yes` et
`# PasswordAuthentication yes`.

</details>

---

**Tâche 2 —** Ajoutez la seconde directive (`PubkeyAuthentication yes`), puis simulez
l'exécution avec le détail des modifications — **sans rien appliquer**.

<details><summary>Correction — tâche 2</summary>

```yaml
    - name: Activer l'authentification par clé publique
      ansible.builtin.lineinfile:
        path: /etc/ssh/sshd_config
        regexp: '^#?\s*PubkeyAuthentication'
        line: 'PubkeyAuthentication yes'
        validate: 'sshd -t -f %s'
      notify: Redemarrer SSH
```

```bash
# TOUJOURS simuler d'abord sur une modification SSH
ansible-playbook playbooks/exo06-ssh.yml --check --diff
```

```diff
--- before: /etc/ssh/sshd_config
+++ after: /etc/ssh/sshd_config
@@ -57,7 +57,7 @@
-#PasswordAuthentication yes
+PasswordAuthentication no
```

> ⚠️ **DANGER — ce playbook peut vous verrouiller hors des machines.** Le lab a été
> provisionné avec `PasswordAuthentication yes` pour permettre `ssh-copy-id`.
> Si vous appliquez ce durcissement **avant** d'avoir déployé vos clés SSH (Lab 02), vous
> perdez tout accès.
>
> **Les trois protections :**
> 1. `validate: 'sshd -t -f %s'` — le fichier n'est écrit que si sa syntaxe est valide
> 2. `--check --diff` systématiquement avant l'exécution réelle
> 3. Garder une session SSH **ouverte** pendant l'opération
>
> Pour restaurer si besoin :
> ```bash
> ansible all -m lineinfile -a "path=/etc/ssh/sshd_config regexp='^PasswordAuthentication' line='PasswordAuthentication yes'" --become
> ansible all -m service -a "name=ssh state=restarted" --become
> ```

</details>

---

**Tâche 3 —** Retirez le paramètre `regexp:` de la première tâche et exécutez le playbook
**trois fois**. Comptez les occurrences de `PasswordAuthentication` dans le fichier.

<details><summary>Correction — tâche 3</summary>

```bash
ansible node1 -m shell -a "grep -c PasswordAuthentication /etc/ssh/sshd_config" --become
```

Sans `regexp:`, chaque exécution **ajoute** la ligne à la fin du fichier : après trois
passages, elle apparaît trois fois de plus.

**Pourquoi `regexp:` est indispensable :**

| Sans `regexp` | Avec `regexp` |
|:---|:---|
| La ligne est **ajoutée** si le texte exact est absent | La ligne **correspondante** est remplacée |
| Rejouer → duplication | **Idempotent** : une seule occurrence |
| La directive commentée reste présente | La ligne commentée est remplacée |

> 🔑 `lineinfile` **sans `regexp` n'est pas idempotent** au sens utile du terme. C'est
> l'une des causes les plus fréquentes de `changed` parasites dans un playbook.

**Rétablissez `regexp:` et nettoyez le fichier avant de continuer :**

```bash
ansible all -m shell -a "sed -i '/^PasswordAuthentication/d' /etc/ssh/sshd_config" --become
ansible-playbook playbooks/exo06-ssh.yml
```

> 💡 **`blockinfile`** est le module frère : il insère un **bloc** de lignes délimité par
> des marqueurs, et sait le mettre à jour ou le supprimer intégralement.

</details>

---

### Exercice 3.2 — Créer un utilisateur avec mot de passe

**Spécifications :**

| Attribut | Valeur |
|:---|:---|
| Nom | `labuser` |
| UID | `1999` |
| Commentaire (GECOS) | `Utilisateur Lab` |
| Groupe secondaire | `developpeurs` |
| Mot de passe | `labuser001` (haché en SHA-512) |
| Shell | `/bin/bash` |
| Cible | tous les hôtes |

> Le groupe `developpeurs` doit être créé **en commande ad-hoc** au préalable.
> L'exercice 13 montrera comment intégrer ce contrôle dans le playbook.

---

**Tâche 1 —** Créez le groupe `developpeurs` sur tous les hôtes, en une seule commande
ad-hoc.

<details><summary>Correction — tâche 1</summary>

```bash
ansible all -m group -a "name=developpeurs state=present" --become
ansible all -m command -a "getent group developpeurs" -o
```

</details>

---

**Tâche 2 —** Écrivez le playbook créant `labuser` selon les spécifications. Le mot de
passe ne doit **jamais** être stocké en clair sur la cible.

<details><summary>Correction — tâche 2</summary>

```yaml
# /tp/playbooks/exo03-2-labuser.yml
---
- name: Création de l'utilisateur labuser
  hosts: all
  become: true

  tasks:
    - name: Créer l'utilisateur labuser
      ansible.builtin.user:
        name: labuser
        uid: 1999
        comment: "Utilisateur Lab"
        groups: developpeurs
        append: true
        password: "{{ 'labuser001' | password_hash('sha512', 'mysecretsalt') }}"
        shell: /bin/bash
        state: present
```

```bash
ansible-playbook playbooks/exo03-2-labuser.yml
ansible all -m command -a "id labuser" -o
ansible all -m shell -a "getent shadow labuser | cut -c1-45" --become -o
```

Le champ mot de passe de `/etc/shadow` commence par `$6$` : c'est l'identifiant du hachage
**SHA-512**. Le mot de passe en clair n'est jamais transmis ni stocké.

</details>

---

**Tâche 3 —** Si vous obtenez une erreur mentionnant `passlib`, corrigez-la. **Sur quelle
machine** ce module Python doit-il être installé, et pourquoi ?

<details><summary>Correction — tâche 3</summary>

**La réponse : sur le nœud de contrôle.**

`password_hash` est un **filtre Jinja2**. Comme tous les filtres, il est évalué **sur le
controller**, avant même que la tâche ne soit envoyée à la cible. C'est donc là que
`passlib` doit être présent.

```bash
# Sur le controller
sudo apt-get install -y python3-passlib
# ou
python3 -m pip install --user passlib
```

**Depuis un playbook**, avec délégation explicite :

```yaml
    - name: Installer passlib sur le nœud de contrôle
      ansible.builtin.pip:
        name: passlib
      delegate_to: localhost
      run_once: true
      become: false
```

> ⚠️ **L'erreur classique** consiste à écrire ces deux tâches, qui installent `passlib` sur
> les **cibles** et ne résolvent donc rien :
>
> ```yaml
>     - ansible.builtin.apt: { name: python3-pip, state: present }
>     - ansible.builtin.pip: { name: passlib }
> ```
>
> C'est exactement la distinction filtre / module que le Lab 06 approfondira :
> **un filtre s'exécute sur le controller, un module sur la cible.**

</details>

---

**Tâche 4 —** Rejouez le playbook deux fois de suite. Le statut est-il `changed` ou `ok` ?
Quel rôle joue le second argument de `password_hash` ?

<details><summary>Correction — tâche 4</summary>

```bash
ansible-playbook playbooks/exo03-2-labuser.yml
ansible-playbook playbooks/exo03-2-labuser.yml
```

→ `changed=0` à la seconde exécution.

**Le second argument (`'mysecretsalt'`) est le sel de hachage.**

| Écriture | Comportement |
|:---|:---|
| `password_hash('sha512')` | Sel **aléatoire** à chaque exécution → hash différent → **toujours `changed`** |
| `password_hash('sha512', 'mysecretsalt')` | Sel **fixe** → hash stable → **idempotent** |

Testez la différence en retirant le sel :

```yaml
        password: "{{ 'labuser001' | password_hash('sha512') }}"
```

→ la tâche devient `changed` à **chaque** exécution, alors que rien n'a changé.

> ⚠️ **Mais un sel en dur dans un fichier versionné est une mauvaise pratique de
> sécurité** : il affaiblit la protection contre les attaques par table précalculée.
>
> **En production**, on stocke le **hash déjà calculé** dans un fichier chiffré par Vault,
> plutôt que le mot de passe en clair accompagné d'un sel :
>
> ```yaml
> # group_vars/all/vault.yml (chiffré)
> vault_labuser_hash: "$6$rounds=656000$xxxxxxxx$yyyyyyyyyy..."
> ```
> ```yaml
> password: "{{ vault_labuser_hash }}"
> ```
>
> Voir le Lab 08.

</details>

---

### Exercice 13 — Intégrer un contrôle conditionnel

**Spécifications :**

| Attribut | Valeur |
|:---|:---|
| Nom | `labuser2` |
| UID | `2000` |
| Commentaire | `Utilisateur Lab 2` |
| Groupe secondaire | `devops` |
| Mot de passe | `labuser002` (SHA-512) |
| Cible | tous les hôtes |

Le groupe `devops` n'existe pas encore. Le playbook doit :
1. tenter de créer `devops` avec le **gid `1500`**
2. considérer l'échec comme **non bloquant**
3. créer le groupe **sans gid imposé** si la première tentative a échoué
4. créer l'utilisateur avec ce groupe

---

**Tâche 1 —** Écrivez la tâche qui tente de créer le groupe avec le gid 1500, en capturant
son résultat et sans interrompre le playbook en cas d'échec.

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/playbooks/exo13-controle.yml
---
- name: Exercice 13 - Création avec contrôle de groupe
  hosts: all
  become: true

  tasks:
    - name: Tenter de créer le groupe devops avec le gid 1500
      ansible.builtin.group:
        name: devops
        gid: 1500
        state: present
      register: group_result
      ignore_errors: true
```

**Les deux directives combinées :**

| Directive | Rôle |
|:---|:---|
| `register: group_result` | Capture **tout** le résultat : `failed`, `changed`, `msg`, `gid`… |
| `ignore_errors: true` | Empêche l'échec d'interrompre le play pour cet hôte |

Inspectez ce que contient la variable :

```yaml
    - ansible.builtin.debug:
        var: group_result
```

</details>

---

**Tâche 2 —** Ajoutez la tâche de repli : créer `devops` **sans gid imposé**, uniquement si
la tâche précédente a échoué.

<details><summary>Correction — tâche 2</summary>

```yaml
    - name: Créer le groupe devops sans gid imposé (repli)
      ansible.builtin.group:
        name: devops
        state: present
      when: group_result is failed
```

**Les tests utilisables sur une variable `register` :**

| Test | Signification |
|:---|:---|
| `is failed` | La tâche a échoué |
| `is succeeded` | La tâche a réussi |
| `is changed` | La tâche a modifié quelque chose |
| `is skipped` | La tâche a été ignorée (`when` faux) |

> 💡 `group_result is failed` est préférable à `group_result.failed == true` : plus
> lisible, et fonctionne même si la clé `failed` est absente du résultat.

</details>

---

**Tâche 3 —** Complétez avec la création de `labuser2`, puis exécutez et vérifiez.

<details><summary>Correction — tâche 3</summary>

```yaml
    - name: Créer l'utilisateur labuser2
      ansible.builtin.user:
        name: labuser2
        uid: 2000
        comment: "Utilisateur Lab 2"
        groups: devops
        append: true
        password: "{{ 'labuser002' | password_hash('sha512', 'mysecretsalt') }}"
        shell: /bin/bash
        state: present
```

```bash
ansible-playbook playbooks/exo13-controle.yml
ansible all -m command -a "id labuser2" -o
ansible all -m command -a "getent group devops" -o
```

</details>

---

**Tâche 4 —** Provoquez réellement l'échec de la première tâche pour vérifier que le repli
fonctionne. Dans quel cas concret cette tâche échoue-t-elle ?

<details><summary>Correction — tâche 4</summary>

**La première tâche échoue si le gid `1500` est déjà pris** par un autre groupe.

```bash
# 1. Occuper le gid 1500 avec un autre groupe
ansible all -m group -a "name=occupe gid=1500 state=present" --become

# 2. Supprimer devops pour repartir de zéro
ansible all -m group -a "name=devops state=absent" --become

# 3. Rejouer : la 1re tâche échoue, le repli prend le relais
ansible-playbook playbooks/exo13-controle.yml
```

```
TASK [Tenter de créer le groupe devops avec le gid 1500] ****
fatal: [node1]: FAILED! => {"msg": "GID '1500' already exists"}
...ignoring

TASK [Créer le groupe devops sans gid imposé (repli)] ****
changed: [node1]

TASK [Créer l'utilisateur labuser2] ****
changed: [node1]
```

> 🔑 **Recul pédagogique.** Ce contrôle est un excellent exercice sur `register` /
> `ignore_errors` / `when`, mais dans la vraie vie il est **superflu** : le module `group`
> est déjà idempotent et crée le groupe s'il n'existe pas. Une seule tâche suffirait :
>
> ```yaml
> - name: Garantir la présence du groupe devops
>   ansible.builtin.group:
>     name: devops
>     state: present
> ```
>
> C'est le réflexe de **scripting défensif** hérité du bash, qui n'a pas lieu d'être avec
> des modules idempotents. Le contrôle explicite ne se justifie que si le gid `1500` est une
> **contrainte métier** dont l'échec doit être tracé.

</details>

---

### Exercice 12 — Sauvegarder avec un nom horodaté

**Spécifications :**

| Élément | Valeur |
|:---|:---|
| Répertoire à sauvegarder | `/var/www` |
| Répertoire de destination | `/backup` (mode `0750`, propriétaire `root`) |
| Nom de l'archive | `var_www_archive_YYYY-MM-DD_HH-mm-ss.tar.gz` |
| Format | `gz` |
| Cible | `web_servers` |

Exemple de nom attendu : `var_www_archive_2026-09-01_14-32-05.tar.gz`

---

**Tâche 1 —** Construisez la variable `timestamp` au format `YYYY-MM-DD_HH-mm-ss` et
affichez le nom d'archive qui en résulte.

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/playbooks/exo12-backup.yml
---
- name: Exercice 12 - Sauvegarde de /var/www
  hosts: web_servers
  become: true

  tasks:
    - name: Construire l'horodatage
      ansible.builtin.set_fact:
        timestamp: "{{ ansible_date_time.date }}_{{ ansible_date_time.time | regex_replace(':', '-') }}"

    - name: Afficher le nom de l'archive
      ansible.builtin.debug:
        msg: "Archive : var_www_archive_{{ timestamp }}.tar.gz"
```

**Décomposition :**

```
ansible_date_time.date                            →  2026-09-01
ansible_date_time.time                            →  14:32:05
ansible_date_time.time | regex_replace(':', '-')  →  14-32-05
                                       résultat   →  2026-09-01_14-32-05
```

Le filtre `regex_replace` est **indispensable** : les `:` sont interdits dans un nom de
fichier sur de nombreux systèmes de fichiers.

> ⚠️ **`gather_facts` doit rester activé.** `ansible_date_time` est un **fact**. Avec
> `gather_facts: false`, le playbook échoue avec `'ansible_date_time' is undefined`.

> 💡 **Alternative plus simple :** `ansible_date_time.iso8601_basic_short` renvoie
> directement `20260901T143205`, sans filtre.

</details>

---

**Tâche 2 —** Créez le répertoire `/backup` puis générez l'archive.

<details><summary>Correction — tâche 2</summary>

```yaml
    - name: Créer le répertoire de sauvegarde
      ansible.builtin.file:
        path: /backup
        state: directory
        owner: root
        mode: "0750"

    - name: Archiver /var/www
      community.general.archive:
        path: /var/www
        dest: "/backup/var_www_archive_{{ timestamp }}.tar.gz"
        format: gz
        owner: root
        mode: "0640"
```

```bash
ansible-galaxy collection install community.general
ansible-playbook playbooks/exo12-backup.yml
ansible web_servers -m command -a "ls -lh /backup" --become
```

> ⚠️ **Cette tâche n'est PAS idempotente**, et c'est **normal** : chaque exécution produit
> une archive avec un horodatage différent. C'est le comportement attendu d'une sauvegarde.
> N'essayez pas de forcer `changed=0` ici — le `changed` est légitime.

</details>

---

**Tâche 3 —** Ajoutez deux tâches qui listent les sauvegardes présentes et affichent leur
nombre ainsi que le nom de la plus récente.

<details><summary>Correction — tâche 3</summary>

```yaml
    - name: Lister les sauvegardes présentes
      ansible.builtin.find:
        paths: /backup
        patterns: "var_www_archive_*.tar.gz"
      register: sauvegardes

    - name: Bilan
      ansible.builtin.debug:
        msg: >-
          {{ inventory_hostname }} : {{ sauvegardes.matched }} sauvegarde(s),
          dernière = {{ sauvegardes.files | map(attribute='path') | sort | last | basename }}
```

```bash
ansible-playbook playbooks/exo12-backup.yml
ansible-playbook playbooks/exo12-backup.yml    # une 2e archive apparaît
```

**Le module `find`** renvoie :

| Clé | Contenu |
|:---|:---|
| `matched` | Nombre de fichiers trouvés |
| `files` | Liste de dictionnaires (`path`, `size`, `mtime`, `mode`…) |

La chaîne de filtres `map(attribute='path') | sort | last | basename` extrait les chemins,
les trie (l'horodatage ISO garantit un tri chronologique), prend le dernier et n'en garde
que le nom de fichier.

</details>

---

**Tâche 4 (bonus) —** Ajoutez la purge des sauvegardes de plus de 7 jours.

<details><summary>Correction — tâche 4</summary>

```yaml
    - name: Trouver les sauvegardes anciennes
      ansible.builtin.find:
        paths: /backup
        patterns: "var_www_archive_*.tar.gz"
        age: 7d
      register: anciennes

    - name: Supprimer les sauvegardes anciennes
      ansible.builtin.file:
        path: "{{ item.path }}"
        state: absent
      loop: "{{ anciennes.files }}"
      loop_control:
        label: "{{ item.path | basename }}"
```

> 💡 `loop_control.label` évite d'afficher le dictionnaire complet de chaque fichier dans
> la sortie — sans lui, le rapport devient illisible. Les boucles sont approfondies au
> **Lab 05**.

</details>

---

## Partie 5 — Handlers et diagnostic d'un service en échec

### Exercice H1 — Ne redémarrer que si nécessaire

**Spécifications :**

| Élément | Valeur |
|:---|:---|
| Fichier | `/tp/playbooks/exo-handlers.yml` |
| Cible | `web_servers` |
| Variable | `http_port: 80` |
| Handler | `Redemarrer Apache` |

---

**Tâche 1 —** Écrivez un playbook qui installe Apache, configure le port d'écoute dans
`/etc/apache2/ports.conf`, déploie une page d'accueil, et démarre le service. La
modification du port doit déclencher un redémarrage **par handler**.

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/playbooks/exo-handlers.yml
---
- name: Apache avec handler
  hosts: web_servers
  become: true

  vars:
    http_port: 80

  tasks:
    - name: Installer Apache
      ansible.builtin.apt:
        name: apache2
        state: present
        update_cache: true

    - name: Configurer le port d'écoute
      ansible.builtin.lineinfile:
        path: /etc/apache2/ports.conf
        regexp: '^Listen '
        line: "Listen {{ http_port }}"
      notify: Redemarrer Apache          # ← déclenche le handler SI changed

    - name: Déployer la page d'accueil
      ansible.builtin.copy:
        content: |
          <html><body><h1>Bienvenue sur {{ inventory_hostname }}</h1></body></html>
        dest: /var/www/html/index.html
        mode: "0644"

    - name: Démarrer et activer Apache
      ansible.builtin.service:
        name: apache2
        state: started
        enabled: true

  handlers:
    - name: Redemarrer Apache
      ansible.builtin.service:
        name: apache2
        state: restarted
```

```bash
ansible-playbook playbooks/exo-handlers.yml
```

</details>

---

**Tâche 2 —** Rejouez le playbook **sans rien modifier**. Le handler se déclenche-t-il ?
Relancez ensuite avec `http_port=8080`. Que se passe-t-il ?

<details><summary>Correction — tâche 2</summary>

```bash
# 2e exécution, aucune modification
ansible-playbook playbooks/exo-handlers.yml
```

```
PLAY RECAP
node1 : ok=4  changed=0
```

→ **Le handler ne se déclenche pas.** Aucune tâche n'a rapporté `changed`.

```bash
# Changement de port
ansible-playbook playbooks/exo-handlers.yml -e "http_port=8080"
```

```
TASK [Configurer le port d'écoute] ****
changed: [node1]

RUNNING HANDLER [Redemarrer Apache] ****
changed: [node1]
```

→ **Le handler part**, parce que la tâche `notify` a rapporté `changed`.

**Vérification :**

```bash
ansible web_servers -m shell -a "ss -tlnp | grep ':8080'" --become
```

**Les 5 règles des handlers :**

| Règle | Détail |
|:---|:---|
| 1. Déclenchement conditionnel | Uniquement si la tâche `notify` rapporte **`changed`** |
| 2. Exécution différée | À la **fin du play**, pas immédiatement après la tâche |
| 3. Dédoublonnage | 10 tâches notifient le même handler → il tourne **une seule fois** |
| 4. Ordre fixe | L'ordre de **déclaration** des handlers, pas celui des `notify` |
| 5. Ignorés si le play échoue | Sauf avec `--force-handlers` ou `force_handlers: true` |

</details>

---

**Tâche 3 —** Modifiez le `notify:` en `notify: redemarrer apache` (tout en minuscules) et
relancez avec un port différent. Que se passe-t-il, et pourquoi est-ce dangereux ?

<details><summary>Correction — tâche 3</summary>

```bash
ansible-playbook playbooks/exo-handlers.yml -e "http_port=9090"
```

Selon la version d'Ansible, vous obtenez soit une erreur `The requested handler was not
found`, soit — dans les configurations tolérantes — **rien du tout** : la tâche passe en
`changed`, mais **aucun handler ne s'exécute**.

> ⚠️ **Le piège silencieux.** Le nom dans `notify:` doit correspondre **exactement** (casse
> comprise) au `name:` du handler. Une faute de frappe peut ne produire **aucune erreur** —
> le service n'est simplement jamais redémarré, et la nouvelle configuration n'est pas
> appliquée. Le playbook « réussit » alors que rien ne fonctionne.
>
> C'est l'un des bugs les plus difficiles à repérer en revue de code.

**Rétablissez `notify: Redemarrer Apache`.**

**Forcer l'exécution immédiate** quand c'est vraiment nécessaire :

```yaml
- name: Appliquer les handlers maintenant
  ansible.builtin.meta: flush_handlers
```

</details>

---

### Exercice 7 — Diagnostiquer un service qui refuse de démarrer

**Préparation** — simulez la situation : un collègue a laissé tourner un Nginx sur le
port 80.

```bash
ansible web_servers -m apt -a "name=nginx state=present update_cache=yes" --become
ansible web_servers -m service -a "name=nginx state=started" --become
ansible web_servers -m shell -a "ss -tlnp | grep ':80 '" --become
```

**Spécifications du playbook :**

| Tâche | Contenu |
|:---|:---|
| 1 | Installer Apache |
| 2 | Redémarrer Apache, en enregistrant le résultat dans `apache_restart_output` |
| 3 | Afficher le contenu de cette variable |

---

**Tâche 1 —** Écrivez `/tp/playbooks/exo07-conflit.yml` selon ces spécifications et
exécutez-le.

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/playbooks/exo07-conflit.yml
---
- name: Exercice 7 - Redémarrage Apache
  hosts: web_servers
  become: true

  tasks:
    - name: Installation Apache
      ansible.builtin.apt:
        name: apache2
        state: present
        update_cache: true

    - name: Redémarrer Apache
      ansible.builtin.service:
        name: apache2
        state: restarted
      register: apache_restart_output

    - name: Afficher le retour de la tâche 2
      ansible.builtin.debug:
        var: apache_restart_output
```

```bash
ansible-playbook playbooks/exo07-conflit.yml
```

</details>

---

**Tâche 2 —** Répondez aux trois questions :
* Le playbook s'est-il exécuté correctement ?
* La 3ᵉ tâche s'est-elle exécutée ?
* Si non, pourquoi ?

<details><summary>Correction — tâche 2</summary>

**1. Le playbook s'est-il exécuté correctement ?** ❌ Non.

```
TASK [Redémarrer Apache] ****
fatal: [node1]: FAILED! => {"changed": false,
  "msg": "Unable to restart service apache2: Job for apache2.service failed
          because the control process exited with error code."}
```

**2. La 3ᵉ tâche s'est-elle exécutée ?** ❌ Non.

**3. Pourquoi ?** **Deux causes distinctes, à ne pas confondre :**

| Cause | Explication |
|:---|:---|
| **La tâche 2 échoue** | Nginx occupe déjà le port 80. Apache ne peut pas s'y lier : `Address already in use`. |
| **La tâche 3 ne part pas** | Par défaut, **dès qu'une tâche échoue sur un hôte, Ansible retire cet hôte du play**. Les tâches suivantes ne sont pas jouées pour lui. |

> 🔑 C'est le comportement par défaut d'Ansible : **fail fast**. Il évite d'enchaîner des
> tâches sur une machine dont l'état est déjà incertain.

</details>

---

**Tâche 3 —** Diagnostiquez la cause **système** de l'échec, comme vous le feriez en
production. Trois commandes suffisent.

<details><summary>Correction — tâche 3</summary>

```bash
# 1. Qui occupe le port 80 ?
ansible web_servers -m shell -a "ss -tlnp | grep ':80 '" --become

# 2. Que dit systemd ?
ansible web_servers -m shell -a "systemctl status apache2 --no-pager -l | tail -20" --become

# 3. Que disent les logs ?
ansible web_servers -m shell -a "journalctl -u apache2 -n 20 --no-pager" --become
```

Vous y lirez explicitement :

```
(98)Address already in use: AH00072: make_sock: could not bind to address 0.0.0.0:80
no listening sockets available, shutting down
```

> 💡 **La leçon de fond :** Ansible vous a signalé l'échec, mais la **cause** est un
> problème système classique — un conflit de port. Ansible ne remplace pas le diagnostic
> système ; il vous indique **où** regarder. `journalctl -u <service>` reste votre premier
> réflexe.

</details>

---

### Exercice 7.2 — Rendre le playbook tolérant à l'échec

**Spécifications — modifier le playbook précédent pour :**

| Tâche | Contenu |
|:---|:---|
| 2 | Ignorer l'erreur en cas d'échec |
| 3 | Afficher la variable (inchangée) |
| 4 | **Nouvelle** — signaler l'échec de la tâche 2 avec `debug` et `when` |

---

**Tâche 1 —** Modifiez la tâche 2 pour que l'échec n'interrompe plus le playbook.

<details><summary>Correction — tâche 1</summary>

```yaml
    - name: Redémarrer Apache
      ansible.builtin.service:
        name: apache2
        state: restarted
      register: apache_restart_output
      ignore_errors: true          # ⭐ le play continue malgré l'échec
```

</details>

---

**Tâche 2 —** Ajoutez la 4ᵉ tâche, qui affiche un message d'alerte **uniquement** si la
tâche 2 a échoué. Le message doit reprendre la cause remontée par Ansible.

<details><summary>Correction — tâche 2</summary>

```yaml
    - name: Signaler l'échec du redémarrage
      ansible.builtin.debug:
        msg: >-
          ⚠️ Le redémarrage d'Apache a échoué sur {{ inventory_hostname }} —
          {{ apache_restart_output.msg | default('cause inconnue') }}
      when: apache_restart_output is failed
```

**Playbook complet :**

```yaml
# /tp/playbooks/exo07-2-conflit.yml
---
- name: Exercice 7.2 - Redémarrage Apache avec gestion d'erreur
  hosts: web_servers
  become: true

  tasks:
    - name: Installation Apache
      ansible.builtin.apt:
        name: apache2
        state: present
        update_cache: true

    - name: Redémarrer Apache
      ansible.builtin.service:
        name: apache2
        state: restarted
      register: apache_restart_output
      ignore_errors: true

    - name: Afficher le retour de la tâche 2
      ansible.builtin.debug:
        var: apache_restart_output

    - name: Signaler l'échec du redémarrage
      ansible.builtin.debug:
        msg: >-
          ⚠️ Le redémarrage d'Apache a échoué sur {{ inventory_hostname }} —
          {{ apache_restart_output.msg | default('cause inconnue') }}
      when: apache_restart_output is failed
```

```bash
ansible-playbook playbooks/exo07-2-conflit.yml
```

Cette fois, les **quatre** tâches s'exécutent :

```
TASK [Redémarrer Apache] ****
fatal: [node1]: FAILED! => {...}
...ignoring                        ← ignore_errors

TASK [Afficher le retour de la tâche 2] ****
ok: [node1] => { "apache_restart_output": {...} }

TASK [Signaler l'échec du redémarrage] ****
ok: [node1] => { "msg": "⚠️ Le redémarrage d'Apache a échoué sur node1 — ..." }

PLAY RECAP
node1 : ok=4  changed=1  failed=0  ignored=1
```

</details>

---

**Tâche 3 —** Observez la ligne `PLAY RECAP`. Quel est le **danger** de `ignore_errors` ?
Quelles alternatives sont préférables ?

<details><summary>Correction — tâche 3</summary>

> ⚠️ **`failed=0` dans le récapitulatif.** Avec `ignore_errors`, le playbook se **termine en
> succès** alors qu'Apache ne tourne pas. C'est exactement le risque de cette directive :
> elle **masque** le problème. En CI/CD, le pipeline passerait au vert.

**Les alternatives, par ordre de préférence :**

```yaml
# ✅ 1. failed_when — REDÉFINIR ce qu'est un échec (exprime l'intention)
- ansible.builtin.command: grep "motif" /etc/passwd
  register: r
  failed_when: r.rc > 1       # 0 = trouvé, 1 = non trouvé, 2+ = vraie erreur
  changed_when: false

# ✅ 2. block / rescue — rattraper proprement (voir Lab 05)
- block:
    - name: Redémarrer Apache
      ansible.builtin.service: {name: apache2, state: restarted}
  rescue:
    - name: Diagnostiquer
      ansible.builtin.command: journalctl -u apache2 -n 20
      changed_when: false
      register: logs
    - ansible.builtin.debug: {var: logs.stdout_lines}
    - ansible.builtin.fail:
        msg: "Apache n'a pas pu démarrer — voir les logs ci-dessus"

# ⚠️ 3. ignore_errors — en dernier recours seulement
```

| Directive | Effet | Quand l'utiliser |
|:---|:---|:---|
| `ignore_errors: true` | Marque `failed` mais continue | Tâche **réellement** optionnelle |
| `failed_when: <cond>` | **Redéfinit** le critère d'échec | Code retour ≠ 0 qui n'est pas une erreur |
| `block`/`rescue` | Rattrape et compense | Échec prévisible avec plan B |

> 🔑 **La règle :** dès que l'échec est significatif, utilisez `failed_when` ou
> `block`/`rescue`. `ignore_errors` sur une tâche critique est une bombe à retardement.
> Ces mécanismes sont approfondis au **Lab 05**.

</details>

---

**Tâche 4 —** Résolvez le conflit de port et vérifiez qu'Apache répond.

<details><summary>Correction — tâche 4</summary>

```bash
ansible web_servers -m service -a "name=nginx state=stopped enabled=no" --become
ansible web_servers -m service -a "name=apache2 state=started" --become
ansible web_servers -m uri -a "url=http://localhost status_code=200"
```

</details>

---

### Exercice H2 — Sécuriser ses exécutions

**Tâche 1 —** Simulez une modification de port à `9090` **sans rien appliquer**, en
affichant le détail des changements.

<details><summary>Correction — tâche 1</summary>

```bash
ansible-playbook playbooks/exo-handlers.yml -e "http_port=9090" --check --diff
```

```diff
--- before: /etc/apache2/ports.conf
+++ after: /etc/apache2/ports.conf
@@ -1,1 +1,1 @@
-Listen 8080
+Listen 9090
```

**Vérifiez qu'aucune modification n'a été appliquée :**

```bash
ansible web_servers -m command -a "grep '^Listen' /etc/apache2/ports.conf" --become -o
```

| Option | Effet |
|:---|:---|
| `--check` | **Simulation** — aucune modification sur les cibles |
| `--diff` | Affiche le détail ligne à ligne des changements de fichiers |
| `--check --diff` | La combinaison à jouer avant toute exécution en production |

</details>

---

**Tâche 2 —** Relancez en mode interactif, en validant chaque tâche une par une. Puis
reprenez l'exécution à partir de la tâche `Déployer la page d'accueil`.

<details><summary>Correction — tâche 2</summary>

```bash
# Validation interactive : y (oui) / n (non) / c (continuer sans demander)
ansible-playbook playbooks/exo-handlers.yml --step

# Reprendre à une tâche précise, après un échec
ansible-playbook playbooks/exo-handlers.yml --start-at-task="Déployer la page d'accueil"
```

> ⚠️ **Limite de `--check`** : certaines tâches ne peuvent pas être simulées correctement.
> Si une tâche `command` crée un fichier que la tâche suivante lit, le mode check échouera
> en cascade. On neutralise ces tâches avec :
> ```yaml
> - name: Tâche non simulable
>   ansible.builtin.command: /opt/script.sh
>   check_mode: false       # exécutée même en --check
>   changed_when: false     # ne pollue pas le rapport
> ```

</details>

---

## Partie 6 — La stack LAMP complète

### Exercice 9 — Générer une configuration adaptée à chaque machine

**Spécifications :**

| Élément | Valeur |
|:---|:---|
| Template | `/tp/templates/app.conf.j2` |
| Destination | `/etc/app/app.conf` (mode `0644`, propriétaire `root`) |
| Répertoire | `/etc/app` (mode `0755`) à créer |
| Cible | `web_servers` |

**Contenu attendu du fichier généré** — les valeurs entre `< >` doivent être renseignées
automatiquement selon la machine :

```
# Sample conf
Adresse IP : <IP du Serveur>
Nom du serveur : <Hostname>
```

---

**Tâche 1 —** Écrivez le template Jinja2. Quelles variables Ansible fournissent l'adresse
IP et le nom d'hôte ?

<details><summary>Correction — tâche 1</summary>

```jinja
{# /tp/templates/app.conf.j2 #}
# Sample conf — généré par Ansible, ne pas éditer à la main
Adresse IP : {{ ansible_default_ipv4.address }}
Nom du serveur : {{ ansible_hostname }}
```

**Les deux facts utilisés :**

| Fact | Contenu | Exemple |
|:---|:---|:---|
| `ansible_default_ipv4.address` | IP de l'interface par défaut | `192.168.56.21` |
| `ansible_hostname` | Nom court de la machine | `node1` |

> 💡 Pour explorer les facts disponibles :
> ```bash
> ansible node1 -m setup -a "filter=ansible_default_ipv4"
> ansible node1 -m setup -a "filter=ansible_hostname"
> ```

**Version enrichie :**

```jinja
{# /tp/templates/app.conf.j2 #}
# Sample conf — généré par Ansible, ne pas éditer à la main
Adresse IP : {{ ansible_default_ipv4.address }}
Nom du serveur : {{ ansible_hostname }}

# Informations complémentaires
FQDN : {{ ansible_fqdn }}
OS : {{ ansible_distribution }} {{ ansible_distribution_version }}
RAM : {{ ansible_memtotal_mb }} Mo
Généré le : {{ ansible_date_time.iso8601 }}
```

</details>

---

**Tâche 2 —** Écrivez le playbook qui crée le répertoire et déploie le template, puis
vérifiez que le résultat **diffère** sur `node1` et `node2`.

<details><summary>Correction — tâche 2</summary>

```yaml
# /tp/playbooks/exo09-template.yml
---
- name: Exercice 9 - Déploiement de configuration par template
  hosts: web_servers
  become: true
  gather_facts: true          # ⭐ indispensable : le template utilise des facts

  tasks:
    - name: Créer le répertoire /etc/app
      ansible.builtin.file:
        path: /etc/app
        state: directory
        owner: root
        mode: "0755"

    - name: Générer app.conf depuis le template
      ansible.builtin.template:
        src: /tp/templates/app.conf.j2
        dest: /etc/app/app.conf
        owner: root
        mode: "0644"
        backup: true          # conserve une copie horodatée
```

```bash
mkdir -p /tp/templates
ansible-playbook playbooks/exo09-template.yml --diff
ansible web_servers -m command -a "cat /etc/app/app.conf"
```

**Le résultat diffère sur chaque machine :**

```
# node1
Adresse IP : 192.168.56.21
Nom du serveur : node1

# node2
Adresse IP : 192.168.56.22
Nom du serveur : node2
```

> ⚠️ **`gather_facts: true` est obligatoire.** Sans les facts, `ansible_default_ipv4` et
> `ansible_hostname` sont indéfinis et le rendu échoue avec
> `'ansible_default_ipv4' is undefined`.

</details>

---

**Tâche 3 —** Quelle est la différence entre `template` et `copy` ? Que se passerait-il si
vous utilisiez `copy` avec ce fichier `.j2` ?

<details><summary>Correction — tâche 3</summary>

Avec `copy`, le fichier serait transféré **tel quel** : les cibles recevraient littéralement

```
Adresse IP : {{ ansible_default_ipv4.address }}
Nom du serveur : {{ ansible_hostname }}
```

Aucune substitution ne serait effectuée.

| | `copy` | `template` |
|:---|:---|:---|
| Rendu Jinja2 | ❌ Contenu copié tel quel | ✅ Variables interprétées |
| Extension du source | quelconque | `.j2` par convention |
| Recherche du fichier | `files/` | `templates/` |
| Cas d'usage | Binaire, certificat, fichier figé | **Toute configuration** |

> 🔑 **La règle :** dès qu'une variable apparaît dans un fichier de configuration, on passe
> de `copy` à `template`. **Un seul** template remplace un fichier par serveur.

> 💡 Le module `template` accepte `validate:` comme `copy` — voir l'exercice 6 et 11.
> C'est le **Lab 06** qui approfondira Jinja2 : conditions, boucles, filtres.

</details>

---

### Exercice 8 — Installer et configurer MySQL

**Spécifications :**

| Élément | Valeur |
|:---|:---|
| Paquets | `mysql-server`, `python3-pymysql` |
| Fichier de configuration source | `/tp/files/my.cnf` |
| Destination | `/etc/mysql/conf.d/lab.cnf` (mode `0644`) |
| Redémarrage | par **handler**, uniquement si la config change |
| Cible | `db_servers` |

**Contenu de `my.cnf` :** `bind-address = 0.0.0.0`, `port = 3306`,
`max_connections = 100`, jeu de caractères `utf8mb4`.

---

**Tâche 1 —** Créez le fichier de configuration sur le controller.

<details><summary>Correction — tâche 1</summary>

```bash
mkdir -p /tp/files

cat > /tp/files/my.cnf <<'EOF'
[mysqld]
bind-address         = 0.0.0.0
port                 = 3306
max_connections      = 100
character-set-server = utf8mb4
collation-server     = utf8mb4_unicode_ci

# Journalisation
slow_query_log       = 1
slow_query_log_file  = /var/log/mysql/slow.log
long_query_time      = 2
EOF
```

</details>

---

**Tâche 2 —** Écrivez le playbook : installation, copie de la configuration, démarrage, et
handler de redémarrage.

<details><summary>Correction — tâche 2</summary>

```yaml
# /tp/playbooks/exo08-mysql.yml
---
- name: Exercice 8 - Installation MySQL
  hosts: db_servers
  become: true

  tasks:
    - name: Installer le serveur MySQL
      ansible.builtin.apt:
        name:
          - mysql-server
          - python3-pymysql
        state: present
        update_cache: true

    - name: Copier le fichier de configuration
      ansible.builtin.copy:
        src: /tp/files/my.cnf
        dest: /etc/mysql/conf.d/lab.cnf
        owner: root
        group: root
        mode: "0644"
      notify: Redemarrer MySQL

    - name: Démarrer et activer MySQL
      ansible.builtin.service:
        name: mysql
        state: started
        enabled: true

  handlers:
    - name: Redemarrer MySQL
      ansible.builtin.service:
        name: mysql
        state: restarted
```

```bash
ansible-playbook playbooks/exo08-mysql.yml
ansible db_servers -m command -a "systemctl is-active mysql"
ansible db_servers -m shell -a "mysql -e 'SHOW VARIABLES LIKE \"max_connections\";'" --become
```

> 💡 **`notify` plutôt qu'un `service: restarted` en dur.** Le redémarrage n'a lieu que si
> le fichier de configuration a réellement changé — sinon on couperait la base à chaque
> exécution du playbook.

</details>

---

**Tâche 3 —** L'énoncé demandait de déployer le fichier en `/etc/mysql/my.cnf`. Pourquoi la
correction utilise-t-elle `/etc/mysql/conf.d/lab.cnf` ?

<details><summary>Correction — tâche 3</summary>

> ⚠️ **Écraser `/etc/mysql/my.cnf` casse la configuration de la distribution.** Ce fichier
> contient des directives `!includedir` qui chargent les configurations par défaut du
> paquet. Les remplacer par notre contenu supprime ces inclusions.
>
> MySQL et MariaDB lisent **automatiquement** tous les fichiers de `/etc/mysql/conf.d/`.
> Y déposer un fichier dédié est **la** bonne pratique : on ajoute sa configuration sans
> détruire celle du paquet, et la désinstallation reste propre.

Vérifiez la mécanique :

```bash
ansible db_servers -m shell -a "grep -r includedir /etc/mysql/my.cnf" --become
ansible db_servers -m command -a "ls /etc/mysql/conf.d/" --become
```

Si votre contexte exige littéralement `/etc/mysql/my.cnf`, ajoutez au minimum
`backup: true` pour pouvoir restaurer.

> ℹ️ Sur Ubuntu 22.04, `mysql-server` installe MySQL 8. Les autres labs utilisent
> **MariaDB** (`mariadb-server`, service `mariadb`). Les deux fonctionnent ; adaptez le nom
> du service selon le paquet installé.

</details>

---

### Exercice final — La stack LAMP en deux plays

**Spécifications :**

| Play | Cible | Contenu |
|:---|:---|:---|
| 1 | `web_servers` | Apache + PHP, VirtualHost, page de test, validation HTTP |
| 2 | `db_servers` | MariaDB, base `monapp_db`, utilisateur `monapp` |

Variables du play 1 : `http_port: 80`, `document_root: /var/www/monapp`,
`php_packages: [php, php-mysql, libapache2-mod-php]`.

---

**Tâche 1 —** Écrivez le play 1 : installation d'Apache et PHP, racine documentaire,
VirtualHost, activation du site et désactivation du site par défaut.

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/playbooks/lamp.yml
---
- name: Déployer la couche web (Apache + PHP)
  hosts: web_servers
  become: true

  vars:
    http_port: 80
    document_root: /var/www/monapp
    php_packages:
      - php
      - php-mysql
      - libapache2-mod-php

  pre_tasks:
    - name: Mettre à jour le cache APT
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600

    - name: S'assurer qu'aucun Nginx ne squatte le port 80
      ansible.builtin.service:
        name: nginx
        state: stopped
        enabled: false
      failed_when: false

  tasks:
    - name: Installer Apache
      ansible.builtin.apt:
        name: apache2
        state: present

    - name: Installer PHP et ses modules
      ansible.builtin.apt:
        name: "{{ php_packages }}"
        state: present
      notify: Redemarrer Apache

    - name: Créer la racine documentaire
      ansible.builtin.file:
        path: "{{ document_root }}"
        state: directory
        owner: www-data
        group: www-data
        mode: "0755"

    - name: Déployer la page de test PHP
      ansible.builtin.copy:
        content: |
          <?php
            echo "<h1>monapp — " . gethostname() . "</h1>";
            echo "<p>PHP " . phpversion() . "</p>";
          ?>
        dest: "{{ document_root }}/index.php"
        owner: www-data
        mode: "0644"

    - name: Configurer le VirtualHost
      ansible.builtin.copy:
        content: |
          <VirtualHost *:{{ http_port }}>
              ServerName {{ inventory_hostname }}
              DocumentRoot {{ document_root }}
              DirectoryIndex index.php index.html
              ErrorLog ${APACHE_LOG_DIR}/monapp_error.log
              CustomLog ${APACHE_LOG_DIR}/monapp_access.log combined
          </VirtualHost>
        dest: /etc/apache2/sites-available/monapp.conf
        mode: "0644"
      notify: Redemarrer Apache

    - name: Activer le site monapp
      ansible.builtin.command: a2ensite monapp.conf
      args:
        creates: /etc/apache2/sites-enabled/monapp.conf     # ← idempotence
      notify: Redemarrer Apache

    - name: Désactiver le site par défaut
      ansible.builtin.command: a2dissite 000-default.conf
      args:
        removes: /etc/apache2/sites-enabled/000-default.conf
      notify: Redemarrer Apache

    - name: Démarrer et activer Apache
      ansible.builtin.service:
        name: apache2
        state: started
        enabled: true

  handlers:
    - name: Redemarrer Apache
      ansible.builtin.service:
        name: apache2
        state: restarted
```

> 💡 **`creates` et `removes`** rendent une tâche `command` idempotente : la commande n'est
> exécutée que si le fichier n'existe pas (`creates`) ou existe encore (`removes`). C'est la
> bonne façon d'utiliser `command` quand aucun module dédié n'existe.

> 💡 **`pre_tasks`** s'exécute **avant** toutes les `tasks` du play. C'est l'endroit des
> prérequis : rafraîchissement de cache, vérifications préalables, libération d'un port.

</details>

---

**Tâche 2 —** Ajoutez au play 1 une section `post_tasks` qui interroge la page PHP et
**échoue explicitement** si le contenu ne correspond pas à l'attendu.

<details><summary>Correction — tâche 2</summary>

```yaml
  post_tasks:
    - name: Interroger la page applicative
      ansible.builtin.uri:
        url: "http://localhost:{{ http_port }}/index.php"
        return_content: true
        status_code: 200
      register: page_result
      retries: 5
      delay: 2
      until: page_result.status == 200

    - name: Vérifier que la page contient le nom de l'application
      ansible.builtin.assert:
        that:
          - page_result.status == 200
          - "'monapp' in page_result.content"
        success_msg: "✅ {{ inventory_hostname }} : application accessible"
        fail_msg: "❌ {{ inventory_hostname }} : contenu inattendu"
```

**Le trio de validation :**

| Module | Rôle |
|:---|:---|
| `uri` | Interroge un endpoint HTTP et capture la réponse |
| `register` | Stocke `status`, `content`, `elapsed`… |
| `assert` | **Échoue** le play si une condition n'est pas remplie |

> 🔑 `assert` transforme votre playbook en **playbook auto-testé** : on ne se contente pas
> de déployer, on **vérifie** que le résultat est conforme. C'est la base des tests
> d'infrastructure, approfondis au **Lab 09**.

> 💡 `retries` / `delay` / `until` attendent que le service soit réellement prêt : Apache
> peut mettre une seconde ou deux à accepter les connexions après un redémarrage.

</details>

---

**Tâche 3 —** Écrivez le play 2 : MariaDB, base `monapp_db`, utilisateur `monapp` avec tous
les droits sur cette base, et écoute réseau ouverte.

<details><summary>Correction — tâche 3</summary>

```yaml
# =============================================================================
# PLAY 2 — Serveur de base de données : MariaDB
# =============================================================================
- name: Déployer la couche base de données (MariaDB)
  hosts: db_servers
  become: true

  vars:
    db_name: monapp_db
    db_user: monapp
    db_password: "ChangeMoi123!"        # ← sera chiffré au Lab 08

  tasks:
    - name: Installer MariaDB et le connecteur Python
      ansible.builtin.apt:
        name:
          - mariadb-server
          - python3-pymysql
        state: present
        update_cache: true

    - name: Démarrer et activer MariaDB
      ansible.builtin.service:
        name: mariadb
        state: started
        enabled: true

    - name: Créer la base applicative
      community.mysql.mysql_db:
        name: "{{ db_name }}"
        state: present
        login_unix_socket: /var/run/mysqld/mysqld.sock

    - name: Créer l'utilisateur applicatif
      community.mysql.mysql_user:
        name: "{{ db_user }}"
        password: "{{ db_password }}"
        priv: "{{ db_name }}.*:ALL"
        host: "%"
        state: present
        login_unix_socket: /var/run/mysqld/mysqld.sock
      no_log: true                       # ne pas afficher le mot de passe

    - name: Autoriser les connexions distantes
      ansible.builtin.lineinfile:
        path: /etc/mysql/mariadb.conf.d/50-server.cnf
        regexp: '^bind-address'
        line: "bind-address = 0.0.0.0"
      notify: Redemarrer MariaDB

  handlers:
    - name: Redemarrer MariaDB
      ansible.builtin.service:
        name: mariadb
        state: restarted
```

```bash
cd /tp
ansible-galaxy collection install community.mysql
ansible-playbook playbooks/lamp.yml --syntax-check
ansible-playbook playbooks/lamp.yml --check --diff      # simulation
ansible-playbook playbooks/lamp.yml                     # exécution réelle
```

> 💡 **`no_log: true`** empêche Ansible d'écrire le contenu de la tâche — donc le mot de
> passe — dans sa sortie et ses logs. À poser sur **toute** tâche manipulant un secret.
> Approfondi au **Lab 08**.

</details>

---

**Tâche 4 —** Validez le déploiement de bout en bout, puis **prouvez l'idempotence** de
l'ensemble.

<details><summary>Correction — tâche 4</summary>

```bash
# --- Couche web ---
ansible web_servers -m uri -a "url=http://localhost/index.php return_content=yes" | grep -o "monapp[^<]*"
ansible web_servers -m command -a "php --version" -o

# --- Couche base de données ---
ansible db_servers -m shell -a "mysql -e 'SHOW DATABASES;'" --become
ansible db_servers -m shell -a "mysql -e \"SELECT User,Host FROM mysql.user WHERE User='monapp';\"" --become

# --- Connectivité web → db ---
ansible web_servers -m shell -a "nc -zv node3 3306" 2>&1 | tail -3

# --- Idempotence : LE test qui compte ---
ansible-playbook playbooks/lamp.yml
```

Récapitulatif attendu :

```
PLAY RECAP ****
node1  : ok=12  changed=0   unreachable=0   failed=0
node2  : ok=12  changed=0   unreachable=0   failed=0
node3  : ok=6   changed=0   unreachable=0   failed=0
```

> 🔑 **`changed=0` en seconde exécution = playbook correct.** Si vous voyez du `changed`,
> identifiez la tâche fautive : c'est presque toujours un `command`/`shell` sans `creates`,
> ou un `service state=restarted` placé dans `tasks` au lieu d'un handler.

</details>

---

## Partie 7 — Variables externes et secrets

### Exercice 14 — Créer des utilisateurs depuis des fichiers externes

**Spécifications — liste des utilisateurs :**

| username | uid |
|:---|:---|
| `lab1` | `2001` |
| `lab2` | `2002` |
| `lab3` | `3003` |
| `lab4` | `3004` |

**Règles de répartition :**

| Condition | Cible |
|:---|:---|
| uid **< 3000** | `web_servers` |
| uid **≥ 3000** | `db_servers` |

Le mot de passe est **commun** à tous les comptes : `p@SSw0duser`, stocké dans un fichier
**chiffré par Ansible Vault**.

---

**Tâche 1 —** Créez `/tp/liste_utilisateurs.yml` contenant un dictionnaire nommé `users`
conforme au tableau.

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/liste_utilisateurs.yml
---
users:
  - username: lab1
    uid: 2001
  - username: lab2
    uid: 2002
  - username: lab3
    uid: 3003
  - username: lab4
    uid: 3004
```

**Vérifiez la structure :**

```bash
python3 -c "import yaml,sys; print(yaml.safe_load(open('/tp/liste_utilisateurs.yml')))"
```

> 💡 `users` est une **liste de dictionnaires**. Chaque élément possède les clés `username`
> et `uid`, accessibles par `item.username` et `item.uid` dans une boucle.

</details>

---

**Tâche 2 —** Créez `/tp/secret.yml` contenant la variable `user_passwd: p@SSw0duser`, puis
chiffrez-le avec `ansible-vault`. Vérifiez qu'il est bien devenu illisible.

<details><summary>Correction — tâche 2</summary>

```yaml
# /tp/secret.yml (avant chiffrement)
---
user_passwd: p@SSw0duser
```

```bash
cd /tp

# Chiffrer — un mot de passe de coffre vous est demandé
ansible-vault encrypt /tp/secret.yml

# Le contenu est devenu illisible
cat /tp/secret.yml
```

```
$ANSIBLE_VAULT;1.1;AES256
33393835626661383735313963636531373862373533303236613762346261363338...
64383734363936633561643666366533343464613437363333383733363464633862...
```

```bash
# Consulter le contenu déchiffré, sans modifier le fichier
ansible-vault view /tp/secret.yml

# Éditer (déchiffre en mémoire, rechiffre à la fermeture)
ansible-vault edit /tp/secret.yml
```

**Les commandes du coffre :**

| Commande | Effet |
|:---|:---|
| `create` | Crée un fichier directement chiffré |
| `encrypt` | Chiffre un fichier existant |
| `decrypt` | Déchiffre **définitivement** sur le disque ⚠️ |
| `view` | Affiche sans modifier |
| `edit` | Édite (jamais en clair sur le disque) |
| `rekey` | Change le mot de passe du coffre |

> 💡 Le **Lab 08** approfondira : pattern `vars.yml` + `vault.yml`, `vault-id` multiples,
> intégration CI/CD, `no_log`, hooks anti-fuite.

</details>

---

**Tâche 3 —** Écrivez le playbook qui importe les **deux** fichiers et crée les utilisateurs
selon les règles de répartition.

<details><summary>Correction — tâche 3</summary>

```yaml
# /tp/playbooks/exo14-utilisateurs.yml
---
- name: Exercice 14 - Création d'utilisateurs depuis des fichiers externes
  hosts: all
  become: true

  vars_files:
    - /tp/secret.yml                 # chiffré par Vault
    - /tp/liste_utilisateurs.yml     # en clair

  tasks:
    - name: Créer les utilisateurs sur web_servers (uid < 3000)
      ansible.builtin.user:
        name: "{{ item.username }}"
        uid: "{{ item.uid }}"
        password: "{{ user_passwd | password_hash('sha512', 'monselfixe') }}"
        shell: /bin/bash
        state: present
      loop: "{{ users }}"
      loop_control:
        label: "{{ item.username }} (uid {{ item.uid }})"
      when:
        - inventory_hostname in groups['web_servers']
        - item.uid | int < 3000

    - name: Créer les utilisateurs sur db_servers (uid >= 3000)
      ansible.builtin.user:
        name: "{{ item.username }}"
        uid: "{{ item.uid }}"
        password: "{{ user_passwd | password_hash('sha512', 'monselfixe') }}"
        shell: /bin/bash
        state: present
      loop: "{{ users }}"
      loop_control:
        label: "{{ item.username }} (uid {{ item.uid }})"
      when:
        - inventory_hostname in groups['db_servers']
        - item.uid | int >= 3000
```

**Les quatre mécanismes combinés :**

| Mécanisme | Rôle |
|:---|:---|
| `vars_files` | Charge des variables depuis des fichiers externes, chiffrés ou non |
| `loop` | Itère sur la liste `users` |
| `when` (liste) | Deux conditions combinées en **ET** logique |
| `item.uid \| int` | **Conversion obligatoire** avant comparaison numérique |

> ⚠️ **Le piège de `| int`.** Sans conversion, `"3003" < "3000"` est évalué comme une
> comparaison de **chaînes**, pas de nombres. Le résultat serait faux. Convertissez
> systématiquement avant toute comparaison numérique.

</details>

---

**Tâche 4 —** Exécutez le playbook. Comment fournir le mot de passe du coffre ? Donnez les
trois méthodes possibles.

<details><summary>Correction — tâche 4</summary>

```bash
cd /tp

# Option 1 — saisie interactive
ansible-playbook playbooks/exo14-utilisateurs.yml --ask-vault-pass

# Option 2 — fichier de mot de passe (indispensable en CI/CD)
echo 'MonMotDePasseVault' > ~/.vault_pass
chmod 600 ~/.vault_pass
ansible-playbook playbooks/exo14-utilisateurs.yml --vault-password-file ~/.vault_pass

# Option 3 — déclaré une fois pour toutes dans ansible.cfg
```

```ini
# /tp/ansible.cfg
[defaults]
vault_password_file = ~/.vault_pass
```

```bash
ansible-playbook playbooks/exo14-utilisateurs.yml    # plus aucune invite
```

**Vérification de la répartition :**

```bash
ansible web_servers -m shell -a "getent passwd lab1 lab2 lab3 lab4" -o
# → lab1 et lab2 seulement

ansible db_servers -m shell -a "getent passwd lab1 lab2 lab3 lab4" -o
# → lab3 et lab4 seulement
```

> 🔑 **N'oubliez pas le `.gitignore`.** Le fichier `~/.vault_pass` ne doit **jamais** être
> versionné :
> ```
> .vault_pass
> *vault_pass*
> ```

</details>

---

**Tâche 5 (bonus) —** Proposez une version plus élégante, sans condition `when` évaluée
pour chaque couple hôte × utilisateur.

<details><summary>Correction — tâche 5</summary>

```yaml
# /tp/playbooks/exo14-bis.yml
---
- name: Utilisateurs applicatifs sur les serveurs web
  hosts: web_servers
  become: true
  vars_files: [/tp/secret.yml, /tp/liste_utilisateurs.yml]

  tasks:
    - name: Créer les comptes uid < 3000
      ansible.builtin.user:
        name: "{{ item.username }}"
        uid: "{{ item.uid }}"
        password: "{{ user_passwd | password_hash('sha512', 'monselfixe') }}"
        shell: /bin/bash
      loop: "{{ users | selectattr('uid', '<', 3000) | list }}"
      loop_control:
        label: "{{ item.username }}"

- name: Utilisateurs applicatifs sur les serveurs de base de données
  hosts: db_servers
  become: true
  vars_files: [/tp/secret.yml, /tp/liste_utilisateurs.yml]

  tasks:
    - name: Créer les comptes uid >= 3000
      ansible.builtin.user:
        name: "{{ item.username }}"
        uid: "{{ item.uid }}"
        password: "{{ user_passwd | password_hash('sha512', 'monselfixe') }}"
        shell: /bin/bash
      loop: "{{ users | selectattr('uid', '>=', 3000) | list }}"
      loop_control:
        label: "{{ item.username }}"
```

**Ce qui change :**

| | Version tâche 3 | Version tâche 5 |
|:---|:---|:---|
| Ciblage | 1 play sur `all` + `when` sur le groupe | 2 plays ciblés |
| Filtrage des utilisateurs | `when` évalué N fois par hôte | `selectattr` évalué **une fois** |
| Lisibilité | Conditions imbriquées | Intention explicite |

> 💡 `selectattr('uid', '<', 3000)` filtre la liste **avant** la boucle. `selectattr` et
> `map` sont approfondis au **Lab 06**.

> ⚠️ **Autre point d'attention :** `inventory_hostname in groups['web_servers']` échoue si
> le groupe n'existe pas dans l'inventaire. Écriture défensive :
> `when: "'web_servers' in group_names"` — plus courte et plus idiomatique.

</details>

---

## Partie 8 — Diagnostic et nettoyage

### Exercice D1 — Trouver les 4 erreurs

Un collègue signale que son playbook « ne fait rien ». Trouvez les **4 erreurs**.

```yaml
---
- name: Playbook cassé
  host: web_servers
  tasks:
    - name: Installer nginx
      apt:
        name: nginx
        state: present
    - name: Copier la config
       copy:
         src: /tp/nginx.conf
         dest: /etc/nginx/nginx.conf
       notify: restart nginx
  handlers:
    - name: Restart Nginx
      service:
        name: nginx
        state: restarted
```

<details><summary>Correction — les 4 erreurs</summary>

**Erreur 1 — `host:` au lieu de `hosts:`**

```yaml
hosts: web_servers        # et non "host:"
```

Ansible ne reconnaît pas la clé `host:` et signale `the field 'hosts' is required`.

**Erreur 2 — `become: true` manquant**

Installer un paquet et écrire dans `/etc/` exige les privilèges root.

```yaml
- name: Playbook cassé
  hosts: web_servers
  become: true
```

**Erreur 3 — indentation incohérente**

La tâche « Copier la config » a `copy:` indenté de 3 espaces au lieu de 2.

```yaml
    - name: Copier la config
      copy:                     # aligné sur "name"
        src: /tp/nginx.conf
        dest: /etc/nginx/nginx.conf
      notify: restart nginx     # aligné sur "name"
```

**Erreur 4 — le `notify` ne correspond pas au nom du handler** ⚠️

`notify: restart nginx` (minuscules) ≠ `name: Restart Nginx` (majuscules).
Le handler ne se déclenchera **jamais**, silencieusement.

**Version corrigée :**

```yaml
---
- name: Playbook corrigé
  hosts: web_servers
  become: true

  tasks:
    - name: Installer nginx
      ansible.builtin.apt:
        name: nginx
        state: present

    - name: Copier la config
      ansible.builtin.copy:
        src: /tp/nginx.conf
        dest: /etc/nginx/nginx.conf
      notify: Restart Nginx        # ← correspond EXACTEMENT

  handlers:
    - name: Restart Nginx
      ansible.builtin.service:
        name: nginx
        state: restarted
```

> 💡 Trois de ces quatre erreurs seraient détectées par `--syntax-check` ou `ansible-lint`.
> La quatrième — le `notify` désaccordé — ne l'est par **aucun outil** : seule la relecture
> ou le test fonctionnel la révèle.

</details>

---

### Exercice D2 — Nettoyer l'environnement

**Tâche 1 —** Écrivez un playbook de remise à zéro qui arrête les services, désinstalle les
paquets, supprime les comptes, groupes et répertoires créés pendant ce lab.

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/playbooks/reset-lab04.yml
---
- name: Remise à zéro du lab 04
  hosts: all
  become: true

  vars:
    paquets:
      - apache2
      - nginx
      - mariadb-server
      - mysql-server
      - php
      - libapache2-mod-php
    comptes:
      - ansible_user
      - labuser
      - labuser2
      - lab1
      - lab2
      - lab3
      - lab4

  tasks:
    - name: Arrêter les services
      ansible.builtin.service:
        name: "{{ item }}"
        state: stopped
      loop: [apache2, nginx, mariadb, mysql]
      failed_when: false

    - name: Désinstaller les paquets
      ansible.builtin.apt:
        name: "{{ paquets }}"
        state: absent
        purge: true
        autoremove: true

    - name: Supprimer les comptes créés
      ansible.builtin.user:
        name: "{{ item }}"
        state: absent
        remove: true
      loop: "{{ comptes }}"
      failed_when: false

    - name: Supprimer les groupes créés
      ansible.builtin.group:
        name: "{{ item }}"
        state: absent
      loop: [developpeurs, devops, occupe]
      failed_when: false

    - name: Supprimer les répertoires
      ansible.builtin.file:
        path: "{{ item }}"
        state: absent
      loop:
        - /var/www/monapp
        - /etc/app
        - /backup
```

```bash
ansible-playbook playbooks/reset-lab04.yml
```

> 💡 `failed_when: false` sur les tâches de suppression : un service ou un compte
> inexistant ne doit pas faire échouer le nettoyage.

</details>

---

## À retenir

| Point clé | Détail |
|:---|:---|
| **Structure** | `- name` / `hosts` / `vars` / `pre_tasks` / `tasks` / `post_tasks` / `handlers` |
| **Un fichier, plusieurs plays** | Un playbook peut orchestrer plusieurs groupes en séquence. |
| **`debug`** | `var:` sans `{{ }}`, `msg:` avec `{{ }}`. |
| **`apt` vs `package`** | Contrôle fin vs portabilité multi-distribution. |
| **`append: true`** | Sur `user.groups`, sinon les groupes existants sont **écrasés**. |
| **`mode: "0755"`** | Toujours entre guillemets — sinon YAML lit un entier décimal. |
| **`regexp:` sur `lineinfile`** | Sans lui, la ligne est ajoutée en double à chaque exécution. |
| **`validate:`** | Sur `sshd_config`, `sudoers`, configs Apache/Nginx — évite de casser un service. |
| **`password_hash`** | Filtre → s'exécute **sur le controller**. Sel fixe = idempotence. |
| **`default()`** | Le filtre le plus utile : rend un playbook tolérant aux variables absentes. |
| **Priorité des variables** | `defaults/` = le plus faible, `-e` = **toujours** le plus fort. |
| **Handlers** | Déclenchés sur `changed`, à la fin du play, dédoublonnés. Nom **exact**. |
| **Échec = hôte retiré du play** | Les tâches suivantes ne sont pas jouées pour cet hôte. |
| **`ignore_errors`** | Le playbook finit **en succès** malgré l'échec. Préférez `failed_when`. |
| **`\| int`** | Obligatoire avant toute comparaison numérique dans un `when`. |
| **`creates` / `removes`** | Rendent une tâche `command` idempotente. |
| **`--check --diff`** | La combinaison à jouer avant toute exécution en production. |

### Le workflow d'exécution recommandé

```bash
ansible-playbook site.yml --syntax-check      # 1. la syntaxe est-elle valide ?
ansible-playbook site.yml --list-hosts        # 2. quelles machines vais-je toucher ?
ansible-playbook site.yml --check --diff      # 3. qu'est-ce qui va changer ?
ansible-playbook site.yml                     # 4. exécution
ansible-playbook site.yml                     # 5. contrôle : changed=0 attendu
```

### Ce qui sera approfondi plus loin

| Notion vue ici | Approfondie au |
|:---|:---|
| `when`, `loop`, `ignore_errors`, `block`/`rescue` | **Lab 05** — Contrôle du flux |
| `template`, Jinja2, `selectattr`, filtres, facts | **Lab 06** — Templating |
| Réutiliser ce playbook sous forme de rôle | **Lab 07** — Rôles |
| `ansible-vault`, `vault-id`, `no_log`, `.gitignore` | **Lab 08** — Vault |
| `assert`, tests d'infrastructure, `serial` | **Lab 09** — Orchestration |

---

⬅️ **Lab précédent :** [Lab 03 — Commandes ad-hoc et idempotence](<../lab 03 - Commandes ad-hoc et idempotence/instructions.md>)
➡️ **Lab suivant :** [Lab 05 — Contrôle du flux et gestion des erreurs](<../lab 05 - Contrôle du flux et gestion des erreurs/instructions.md>)
