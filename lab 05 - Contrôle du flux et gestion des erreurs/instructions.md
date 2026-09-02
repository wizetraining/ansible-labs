# Lab 05 — Contrôle du flux et gestion des erreurs

> ⭐ Niveau : ⭐⭐⭐ | ⏱ Durée estimée : 75 min | Module : **M5 — Contrôle du flux : conditions, boucles, blocks, tags**

> 📌 Chaque exercice est découpé en **tâches numérotées**, avec une correction par tâche.
> Traitez-les dans l'ordre : chaque tâche s'appuie sur la précédente.

## Objectifs pédagogiques

* Conditionner l'exécution d'une tâche avec `when` sur des facts et des variables
* Écrire des boucles modernes (`loop`) et savoir lire les anciennes (`with_*`)
* Regrouper des tâches et gérer les erreurs avec `block` / `rescue` / `always`
* Maîtriser `ignore_errors`, `failed_when` et `changed_when`
* Organiser un playbook avec des `tags` pour n'exécuter qu'une partie
* Découper un playbook avec `include_tasks` et `import_tasks`

## Notions abordées

* `when` : conditions simples, multiples (ET / OU), sur facts et sur `register`
* `loop`, `loop_control` (`label`, `index_var`, `pause`), `until` / `retries`
* `with_items`, `with_dict`, `with_fileglob` (syntaxe historique)
* `block` / `rescue` / `always` — le try/catch/finally d'Ansible
* `ignore_errors` vs `failed_when` : la vraie différence
* `changed_when: false` pour les tâches de lecture
* `tags`, tags spéciaux `always` / `never`, `--tags` / `--skip-tags`
* `include_*` (dynamique) vs `import_*` (statique)

## Documentation de référence

* [Conditionals](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_conditionals.html)
* [Loops](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_loops.html)
* [Error handling](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_error_handling.html)
* [Tags](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_tags.html)

## Prérequis

Ce lab reprend l'inventaire construit au **Lab 04** :

| Groupe | Membres |
|:---|:---|
| `web_servers` | `node1`, `node2` |
| `db_servers` | `node3` |

```bash
cd /tp
ansible-inventory --graph      # vérifiez avant de commencer
```

## Contexte

Votre playbook LAMP fonctionne, mais il est rigide : il suppose Ubuntu partout, répète dix
fois la même tâche pour dix paquets, et le moindre incident interrompt tout le déploiement
en laissant les serveurs à moitié configurés.

Vous allez le rendre **robuste et sélectif** : adaptable à plusieurs distributions, capable
de se rattraper sur erreur, et exécutable partiellement grâce aux tags.

## Parcours du lab

| Partie | Thème | Exercices | Difficulté |
|:---|:---|:---|:---|
| 1 | Conditions avec `when` | C1, C2, C3 | ⭐⭐ |
| 2 | Boucles | B1, B2, B3 | ⭐⭐ |
| 3 | `block` / `rescue` / `always` | E1, E2 | ⭐⭐⭐ |
| 4 | Tags et exécution partielle | T1, T2 | ⭐⭐ |
| 5 | Découper un playbook | I1, I2 | ⭐⭐⭐ |

---

## Partie 1 — Conditions avec `when`

### Exercice C1 — Installer le bon paquet selon la distribution

**Spécifications :**

| Élément | Valeur |
|:---|:---|
| Fichier | `/tp/playbooks/10-conditions.yml` |
| Cible | `web_servers` |
| Famille `Debian` | installer `apache2` |
| Famille `RedHat` | installer `httpd` |
| Autre famille | échouer avec un message explicite |

---

**Tâche 1 —** Écrivez la tâche qui installe `apache2` **uniquement** sur les machines de la
famille Debian. Quel fact utilisez-vous ?

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/playbooks/10-conditions.yml
---
- name: Installation multi-distribution
  hosts: web_servers
  become: true

  tasks:
    - name: Installer Apache (famille Debian/Ubuntu)
      ansible.builtin.apt:
        name: apache2
        state: present
        update_cache: true
      when: ansible_os_family == "Debian"
```

**Le fact utilisé est `ansible_os_family`.**

```bash
ansible web_servers -m setup -a "filter=ansible_os_family" -o
```

| Fact | Granularité | Exemple |
|:---|:---|:---|
| `ansible_os_family` | **Famille** — le plus utile pour les conditions | `Debian`, `RedHat`, `Suse` |
| `ansible_distribution` | Distribution précise | `Ubuntu`, `CentOS`, `Debian` |
| `ansible_distribution_major_version` | Version majeure | `22`, `9` |

> 💡 Préférez `ansible_os_family` à `ansible_distribution` dans les conditions : `Ubuntu`,
> `Debian` et `Linux Mint` partagent tous la famille `Debian`, donc le même gestionnaire de
> paquets. Une condition sur la famille couvre plus de cas avec moins de code.

</details>

---

**Tâche 2 —** Ajoutez la tâche équivalente pour la famille RedHat, puis une troisième tâche
qui **fait échouer** le playbook si la distribution n'appartient à aucune des deux familles.

<details><summary>Correction — tâche 2</summary>

```yaml
    - name: Installer Apache (famille RedHat/CentOS)
      ansible.builtin.dnf:
        name: httpd
        state: present
      when: ansible_os_family == "RedHat"

    - name: Signaler une distribution non supportée
      ansible.builtin.fail:
        msg: "Distribution {{ ansible_distribution }} non prise en charge"
      when: ansible_os_family not in ["Debian", "RedHat"]
```

```bash
cd /tp
ansible-playbook playbooks/10-conditions.yml
```

**Le module `fail`** interrompt volontairement l'exécution avec un message. C'est la façon
propre de signaler qu'une précondition n'est pas remplie, plutôt que de laisser le playbook
échouer plus loin avec une erreur incompréhensible.

> 💡 `not in [...]` teste l'absence dans une liste. On aurait pu écrire
> `when: ansible_os_family != "Debian" and ansible_os_family != "RedHat"` — moins lisible.

</details>

---

**Tâche 3 —** Exécutez le playbook et observez la sortie. Quel statut prend la tâche
RedHat, et pourquoi ? Ansible évalue-t-il la condition une fois, ou par machine ?

<details><summary>Correction — tâche 3</summary>

```
TASK [Installer Apache (famille Debian/Ubuntu)] ****
ok: [node1]
ok: [node2]

TASK [Installer Apache (famille RedHat/CentOS)] ****
skipping: [node1]
skipping: [node2]

TASK [Signaler une distribution non supportée] ****
skipping: [node1]
skipping: [node2]
```

**La tâche RedHat prend le statut `skipping`** : la condition est fausse sur ces machines.

**Ansible évalue la condition `when` indépendamment pour chaque hôte.** Chaque machine
décide seule si la tâche s'applique à elle. Sur un parc mixte Ubuntu + CentOS, le même
playbook installerait `apache2` sur les unes et `httpd` sur les autres, en un seul passage.

**Les cinq statuts d'une tâche :**

| Statut | Signification |
|:---|:---|
| `ok` | Exécutée, rien n'a changé |
| `changed` | Exécutée, l'état a été modifié |
| `skipping` | **Non exécutée** — condition `when` fausse |
| `failed` | Échec |
| `unreachable` | Machine injoignable (SSH) |

> 💡 Une tâche `skipped` n'est **pas** un échec. Elle n'apparaît pas dans le compteur
> `failed` du `PLAY RECAP`, mais dans `skipped`.

</details>

---

**Tâche 4 —** Les trois tâches font la même chose. Réécrivez-les en **une seule** tâche, à
l'aide d'un dictionnaire de correspondance entre famille d'OS et nom de paquet.

<details><summary>Correction — tâche 4</summary>

```yaml
# /tp/playbooks/10-conditions-bis.yml
---
- name: Installation multi-distribution (version idiomatique)
  hosts: web_servers
  become: true

  vars:
    webserver_package:
      Debian: apache2
      RedHat: httpd

  tasks:
    - name: Vérifier que la distribution est supportée
      ansible.builtin.fail:
        msg: "Distribution {{ ansible_distribution }} non prise en charge"
      when: ansible_os_family not in webserver_package

    - name: Installer le serveur web adapté à l'OS
      ansible.builtin.package:
        name: "{{ webserver_package[ansible_os_family] }}"
        state: present
```

```bash
ansible-playbook playbooks/10-conditions-bis.yml
```

**Ce qui change :**

| | Version tâche 2 | Version dictionnaire |
|:---|:---|:---|
| Nombre de tâches d'installation | 1 par famille d'OS | **1 seule** |
| Ajouter le support de Suse | +1 tâche complète | +1 ligne dans le dictionnaire |
| Module | `apt` / `dnf` (spécifiques) | `package` (générique) |
| Lisibilité de la sortie | 2 lignes dont 1 `skipping` | 1 ligne |

> 🔑 **C'est la façon idiomatique de gérer le multi-OS en Ansible.** Le dictionnaire de
> correspondance remplace élégamment une cascade de `when`. On le retrouvera au Lab 07 dans
> les `vars/` des rôles, où il permet à un rôle unique de fonctionner sur plusieurs
> distributions.

> ⚠️ `ansible_os_family not in webserver_package` teste l'appartenance aux **clés** du
> dictionnaire. C'est ce qui protège contre une erreur `dict object has no attribute` si la
> famille est inconnue.

</details>

---

### Exercice C2 — Combiner plusieurs conditions

**Spécifications :**

| Élément | Valeur |
|:---|:---|
| Fichier | `/tp/playbooks/11-conditions-avancees.yml` |
| Cible | tous les hôtes |

---

**Tâche 1 —** Écrivez une tâche qui ne s'exécute que si **les trois** conditions suivantes
sont réunies : distribution `Ubuntu`, version majeure `22`, et au moins 512 Mo de RAM.

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/playbooks/11-conditions-avancees.yml
---
- name: Conditions combinées
  hosts: all
  become: true

  tasks:
    - name: Tâche réservée aux Ubuntu 22.04 avec au moins 512 Mo
      ansible.builtin.debug:
        msg: "{{ inventory_hostname }} remplit tous les critères"
      when:
        - ansible_distribution == "Ubuntu"
        - ansible_distribution_major_version == "22"
        - ansible_memtotal_mb >= 512
```

> 🔑 **Une liste de conditions sous `when:` est un ET logique.** Toutes doivent être vraies.
> C'est la forme la plus lisible pour combiner plusieurs critères — préférez-la à
> `cond1 and cond2 and cond3` sur une seule ligne.

> ⚠️ **`ansible_distribution_major_version` est une chaîne**, pas un entier. On compare donc
> avec `"22"` et non `22`. Pour une comparaison numérique :
> `ansible_distribution_major_version | int >= 22`.

</details>

---

**Tâche 2 —** Écrivez une tâche qui s'exécute si la machine appartient au groupe
`web_servers` **ou** au groupe `backup`.

<details><summary>Correction — tâche 2</summary>

```yaml
    - name: Tâche pour les serveurs web ou de backup
      ansible.builtin.debug:
        msg: "{{ inventory_hostname }} est web ou backup"
      when: "'web_servers' in group_names or 'backup' in group_names"
```

**Le OU logique s'écrit sur une seule ligne**, avec l'opérateur `or`. Il n'existe pas de
forme en liste pour le OU.

| Opérateur | Écriture |
|:---|:---|
| ET | liste de conditions (recommandé) **ou** `and` sur une ligne |
| OU | `or` sur une seule ligne |
| NON | `not` |
| Combinaison | parenthèses : `(a or b) and c` |

> 💡 **`group_names`** est une variable magique : la **liste des groupes** auxquels
> appartient l'hôte courant. Testez-la :
> ```bash
> ansible all -m debug -a "var=group_names"
> ```

> ⚠️ Notez les guillemets encadrant toute l'expression : `when: "'web_servers' in
> group_names"`. Sans eux, YAML se perd dans les apostrophes internes.

</details>

---

**Tâche 3 —** Vérifiez la présence du fichier `/etc/apache2/apache2.conf`, puis écrivez
deux tâches : l'une qui le sauvegarde s'il existe, l'autre qui signale son absence.

<details><summary>Correction — tâche 3</summary>

```yaml
    - name: Vérifier la présence d'un fichier de configuration
      ansible.builtin.stat:
        path: /etc/apache2/apache2.conf
      register: apache_conf

    - name: Sauvegarder la configuration existante
      ansible.builtin.copy:
        src: /etc/apache2/apache2.conf
        dest: /etc/apache2/apache2.conf.bak
        remote_src: true          # ⭐ le fichier source est SUR LA CIBLE
      when: apache_conf.stat.exists

    - name: Signaler l'absence de configuration
      ansible.builtin.debug:
        msg: "Apache n'est pas installé sur {{ inventory_hostname }}"
      when: not apache_conf.stat.exists
```

```bash
ansible-playbook playbooks/11-conditions-avancees.yml
```

**Le module `stat`** inspecte un fichier sans le modifier. Explorez ce qu'il renvoie :

```yaml
    - ansible.builtin.debug:
        var: apache_conf
```

| Clé | Contenu |
|:---|:---|
| `stat.exists` | Booléen — le fichier existe-t-il ? |
| `stat.isdir` | Est-ce un répertoire ? |
| `stat.size` | Taille en octets |
| `stat.mode` | Permissions (`"0644"`) |
| `stat.pw_name` | Propriétaire |

> ⚠️ **`remote_src: true` est indispensable ici.** Sans lui, `copy` chercherait
> `/etc/apache2/apache2.conf` sur le **controller** et échouerait. C'est le piège vu au
> Lab 04, exercice 5.

</details>

---

**Tâche 4 —** Ajoutez une tâche qui ne s'exécute que si une variable `app_version` est
définie. Testez avec, puis sans, la variable.

<details><summary>Correction — tâche 4</summary>

```yaml
    - name: Tâche exécutée uniquement si la variable est définie
      ansible.builtin.debug:
        msg: "Déploiement de la version {{ app_version }}"
      when: app_version is defined
```

```bash
# Sans la variable → skipping
ansible-playbook playbooks/11-conditions-avancees.yml

# Avec la variable → exécutée
ansible-playbook playbooks/11-conditions-avancees.yml -e "app_version=3.0"
```

**Les tests Jinja2 les plus utiles dans `when` :**

| Test | Signification |
|:---|:---|
| `is defined` / `is not defined` | La variable existe-t-elle ? |
| `is none` | Vaut `null` |
| `\| bool` | Conversion en booléen (`"yes"` → `true`) |
| `in group_names` | L'hôte appartient-il à ce groupe ? |
| `\| length > 0` | Liste ou chaîne non vide |
| `is succeeded` / `is failed` / `is skipped` | Sur une variable `register` |
| `is match('regex')` | Correspondance d'expression régulière |

> 💡 **`is defined` vs `default()`** — deux façons de gérer une variable absente :
> ```yaml
> when: app_version is defined              # exécuter ou non la tâche
> msg: "{{ app_version | default('n/a') }}"  # exécuter avec une valeur de repli
> ```

</details>

---

### Exercice C3 — Le piège des accolades

**Tâche 1 —** Réécrivez la condition de la tâche 1 de l'exercice C1 en entourant la variable
d'accolades `{{ }}`. Exécutez et observez.

<details><summary>Correction — tâche 1</summary>

```yaml
    - name: Condition MAL écrite
      ansible.builtin.debug:
        msg: "Test"
      when: "{{ ansible_os_family }} == 'Debian'"
```

```bash
ansible-playbook playbooks/10-conditions.yml
```

Vous obtenez un avertissement :

```
[WARNING]: conditional statements should not include jinja2 templating delimiters
such as {{ }} or {% %}. Found: {{ ansible_os_family }} == 'Debian'
```

> ⚠️ **Le piège n°1 des conditions.** Dans `when`, on écrit le nom de la variable
> **sans** `{{ }}`.
>
> ```yaml
> when: ansible_os_family == "Debian"          # ✅ correct
> when: "{{ ansible_os_family }} == 'Debian'"  # ❌ faux
> ```
>
> **Pourquoi ?** `when` attend déjà une **expression Jinja2**. Ansible l'évalue comme telle,
> sans avoir besoin des délimiteurs. Les ajouter provoque une double interprétation : selon
> les versions et les valeurs, cela va de l'avertissement bénin au comportement franchement
> incorrect.

**Rétablissez l'écriture correcte avant de continuer.**

</details>

---

**Tâche 2 —** Quelle est la seule situation où `{{ }}` est nécessaire dans un `when` ?

<details><summary>Correction — tâche 2</summary>

**Quand la variable elle-même contient un nom de variable à résoudre** — cas rare, dit
« double indirection » :

```yaml
  vars:
    cible: ansible_os_family
  tasks:
    - ansible.builtin.debug:
        msg: "Debian détecté"
      when: vars[cible] == "Debian"      # ✅ sans accolades, via vars[]
```

En pratique, **considérez qu'il ne faut jamais d'accolades dans `when`**. Si vous croyez en
avoir besoin, c'est presque toujours le signe qu'il existe une écriture plus simple.

> 💡 La même règle s'applique à `failed_when`, `changed_when`, `until` et `assert.that` :
> tous attendent une expression Jinja2 **sans** délimiteurs.

</details>

---

## Partie 2 — Boucles

### Exercice B1 — Boucler sur une liste simple

**Spécifications :**

| Élément | Valeur |
|:---|:---|
| Fichier | `/tp/playbooks/12-boucles.yml` |
| Cible | tous les hôtes |
| Variable `outils` | `htop`, `tree`, `jq`, `ncdu` |

---

**Tâche 1 —** Déclarez la liste `outils` et écrivez une tâche qui installe chaque paquet à
l'aide d'une boucle.

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/playbooks/12-boucles.yml
---
- name: Découverte des boucles
  hosts: all
  become: true

  vars:
    outils:
      - htop
      - tree
      - jq
      - ncdu

  tasks:
    - name: Installer les outils d'administration
      ansible.builtin.apt:
        name: "{{ item }}"
        state: present
        update_cache: true
      loop: "{{ outils }}"
```

```bash
ansible-playbook playbooks/12-boucles.yml
```

**`item`** est la variable magique de boucle : elle contient l'élément courant à chaque
itération. Son nom peut être changé avec `loop_control.loop_var` (utile pour les boucles
imbriquées).

</details>

---

**Tâche 2 —** Observez la sortie : combien de fois la tâche s'exécute-t-elle ? Chronométrez
l'exécution, puis réécrivez la tâche **sans boucle** et comparez.

<details><summary>Correction — tâche 2</summary>

**Avec boucle** — la tâche s'exécute **4 fois par hôte** (une par paquet) :

```
TASK [Installer les outils d'administration] ****
changed: [node1] => (item=htop)
changed: [node1] => (item=tree)
changed: [node1] => (item=jq)
changed: [node1] => (item=ncdu)
```

```bash
ansible all -m apt -a "name=htop,tree,jq,ncdu state=absent" --become
time ansible-playbook playbooks/12-boucles.yml
```

**Sans boucle** — le module reçoit la liste entière :

```yaml
    - name: Installer les outils (une seule transaction)
      ansible.builtin.apt:
        name: "{{ outils }}"        # ← la liste directement
        state: present
        update_cache: true
```

```bash
ansible all -m apt -a "name=htop,tree,jq,ncdu state=absent" --become
time ansible-playbook playbooks/12-boucles.yml
```

> 🔑 **L'optimisation à retenir.** Pour les modules de paquets, passer la liste directement
> est **beaucoup** plus rapide :
>
> | | Avec `loop` | Avec une liste |
> |:---|:---|:---|
> | Transactions APT | 4 | **1** |
> | Connexions module | 4 | 1 |
> | Résolution de dépendances | 4 fois | 1 fois |
>
> Les modules `apt`, `yum`, `dnf`, `package`, `pip` acceptent nativement une liste. Sur un
> parc de 50 machines et 20 paquets, la différence se compte en **minutes**.

> 💡 `ansible-lint` signale d'ailleurs ce motif avec la règle
> `package-latest` / `no-loop-var-prefix` selon les cas.

</details>

---

### Exercice B2 — Boucler sur des dictionnaires

**Spécifications — utilisateurs à créer :**

| nom | shell | groupes |
|:---|:---|:---|
| `alice` | `/bin/bash` | `sudo` |
| `bob` | `/bin/sh` | `users` |
| `charlie` | `/bin/bash` | `users` |

---

**Tâche 1 —** Déclarez la variable `utilisateurs` sous forme de liste de dictionnaires,
puis écrivez la tâche de création.

<details><summary>Correction — tâche 1</summary>

```yaml
  vars:
    utilisateurs:
      - { nom: alice,   shell: /bin/bash, groupes: "sudo" }
      - { nom: bob,     shell: /bin/sh,   groupes: "users" }
      - { nom: charlie, shell: /bin/bash, groupes: "users" }

  tasks:
    - name: Créer les utilisateurs
      ansible.builtin.user:
        name: "{{ item.nom }}"
        shell: "{{ item.shell }}"
        groups: "{{ item.groupes }}"
        append: true
        state: present
      loop: "{{ utilisateurs }}"
```

```bash
ansible-playbook playbooks/12-boucles.yml
ansible all -m command -a "id alice" -o
```

**Deux écritures équivalentes** pour une liste de dictionnaires :

```yaml
# Forme compacte (JSON inline)
utilisateurs:
  - { nom: alice, shell: /bin/bash }

# Forme développée (plus lisible pour de nombreuses clés)
utilisateurs:
  - nom: alice
    shell: /bin/bash
    groupes: "sudo"
```

</details>

---

**Tâche 2 —** Exécutez et observez la sortie. Quel est le problème de lisibilité ?
Corrigez-le.

<details><summary>Correction — tâche 2</summary>

**Le problème :** Ansible affiche le **dictionnaire complet** à chaque itération.

```
changed: [node1] => (item={'nom': 'alice', 'shell': '/bin/bash', 'groupes': 'sudo'})
changed: [node1] => (item={'nom': 'bob', 'shell': '/bin/sh', 'groupes': 'users'})
```

Avec dix clés par élément et vingt éléments, la sortie devient illisible.

**La correction — `loop_control.label` :**

```yaml
    - name: Créer les utilisateurs
      ansible.builtin.user:
        name: "{{ item.nom }}"
        shell: "{{ item.shell }}"
        groups: "{{ item.groupes }}"
        append: true
        state: present
      loop: "{{ utilisateurs }}"
      loop_control:
        label: "{{ item.nom }}"      # ⭐ n'affiche que le nom
```

```
changed: [node1] => (item=alice)
changed: [node1] => (item=bob)
changed: [node1] => (item=charlie)
```

> 🔑 **`loop_control.label` est indispensable dès que vous bouclez sur des dictionnaires.**
> C'est aussi une protection : sans lui, un dictionnaire contenant un mot de passe
> l'afficherait en clair dans la sortie. (Le vrai remède reste `no_log: true` — Lab 08.)

</details>

---

**Tâche 3 —** Ajoutez une tâche qui crée un répertoire par outil, nommé
`/opt/app/instance-0`, `/opt/app/instance-1`, etc. Comment obtenir l'index de l'itération ?

<details><summary>Correction — tâche 3</summary>

```yaml
    - name: Créer des répertoires numérotés
      ansible.builtin.file:
        path: "/opt/app/instance-{{ idx }}"
        state: directory
        mode: "0755"
      loop: "{{ outils }}"
      loop_control:
        index_var: idx               # ⭐ index de l'itération (démarre à 0)
        label: "instance-{{ idx }}"
```

```bash
ansible-playbook playbooks/12-boucles.yml
ansible all -m command -a "ls /opt/app/" --become -o
```

**Les options de `loop_control` :**

| Option | Rôle |
|:---|:---|
| `label` | Ce qui s'affiche dans la sortie à chaque itération |
| `index_var` | Nom de la variable contenant l'index (démarre à **0**) |
| `loop_var` | Renomme `item` — indispensable pour les boucles imbriquées |
| `pause` | Secondes d'attente entre deux itérations |
| `extended` | Expose `ansible_loop.first`, `.last`, `.index`, `.length` |

> 💡 Avec `extended: true`, on accède à des métadonnées riches :
> ```yaml
>       loop_control:
>         extended: true
> # puis dans la tâche :
> #   {{ ansible_loop.first }}   → true à la 1re itération
> #   {{ ansible_loop.last }}    → true à la dernière
> #   {{ ansible_loop.index }}   → index à partir de 1
> ```

</details>

---

### Exercice B3 — Syntaxes historiques et boucles d'attente

**Tâche 1 —** Le code existant de votre entreprise utilise `with_items`. Convertissez cette
tâche en syntaxe moderne, et donnez la correspondance pour `with_dict` et `with_fileglob`.

```yaml
- name: Ancienne syntaxe
  ansible.builtin.apt:
    name: "{{ item }}"
  with_items: "{{ outils }}"
```

<details><summary>Correction — tâche 1</summary>

```yaml
# Syntaxe moderne (recommandée depuis Ansible 2.5)
- name: Syntaxe moderne
  ansible.builtin.apt:
    name: "{{ item }}"
  loop: "{{ outils }}"
```

**Correspondance `with_*` → `loop` + filtre :**

| Historique | Moderne |
|:---|:---|
| `with_items` | `loop` (aplatit une liste de listes : `\| flatten(1)`) |
| `with_dict` | `loop: "{{ mon_dict \| dict2items }}"` |
| `with_nested` | `loop: "{{ a \| product(b) \| list }}"` |
| `with_together` | `loop: "{{ a \| zip(b) \| list }}"` |
| `with_fileglob` | `loop: "{{ query('fileglob', '/chemin/*.conf') }}"` |
| `with_sequence` | `loop: "{{ range(1, 6) \| list }}"` |
| `with_subelements` | `loop: "{{ a \| subelements('b') }}"` |

> ⚠️ **Une différence de comportement à connaître :** `with_items` **aplatit**
> automatiquement les listes imbriquées, pas `loop`. Si votre liste contient des
> sous-listes, la conversion exacte est `loop: "{{ ma_liste | flatten(levels=1) }}"`.

> 💡 Les `with_*` ne sont **pas dépréciés** et fonctionnent toujours. Vous les rencontrerez
> constamment dans le code existant et sur Ansible Galaxy. `loop` est simplement la forme
> recommandée pour le nouveau code.

</details>

---

**Tâche 2 —** Écrivez une tâche qui boucle sur un **dictionnaire** de ports et affiche
`http → 80`, `https → 443`, `mysql → 3306`.

<details><summary>Correction — tâche 2</summary>

```yaml
  vars:
    ports:
      http: 80
      https: 443
      mysql: 3306

  tasks:
    - name: Afficher les ports
      ansible.builtin.debug:
        msg: "{{ item.key }} → {{ item.value }}"
      loop: "{{ ports | dict2items }}"
      loop_control:
        label: "{{ item.key }}"
```

**Le filtre `dict2items`** transforme un dictionnaire en liste de paires :

```yaml
# Avant
ports: { http: 80, https: 443 }

# Après | dict2items
- { key: http,  value: 80 }
- { key: https, value: 443 }
```

Le filtre inverse existe : `items2dict`.

> 💡 On peut renommer les clés produites :
> `{{ ports | dict2items(key_name='service', value_name='port') }}`
> → `item.service` et `item.port`.

</details>

---

**Tâche 3 —** Écrivez une tâche qui attend qu'Apache réponde en HTTP, avec 10 tentatives
espacées de 3 secondes. Donnez ensuite l'alternative avec un module dédié.

<details><summary>Correction — tâche 3</summary>

**Avec `until` / `retries` / `delay` :**

```yaml
    - name: Attendre qu'Apache réponde
      ansible.builtin.uri:
        url: http://localhost
        status_code: 200
      register: resultat
      until: resultat.status == 200
      retries: 10        # 10 tentatives maximum
      delay: 3           # 3 secondes entre chaque essai
```

**Mécanique :** la tâche est rejouée jusqu'à ce que la condition `until` soit vraie, ou
jusqu'à épuisement des `retries`. En cas d'épuisement, la tâche **échoue**.

```
FAILED - RETRYING: Attendre qu'Apache réponde (10 retries left).
FAILED - RETRYING: Attendre qu'Apache réponde (9 retries left).
ok: [node1]
```

**Alternative dédiée — le module `wait_for` :**

```yaml
    - name: Attendre l'ouverture du port 80
      ansible.builtin.wait_for:
        port: 80
        host: 127.0.0.1
        delay: 1
        timeout: 30
```

| Besoin | Module |
|:---|:---|
| Attendre qu'un **port** s'ouvre ou se ferme | `wait_for` |
| Attendre qu'un **fichier** apparaisse | `wait_for` (`path:`) |
| Attendre qu'une **chaîne** apparaisse dans un fichier | `wait_for` (`search_regex:`) |
| Attendre qu'un **endpoint HTTP** réponde correctement | `uri` + `until` |
| Attendre le **redémarrage complet** d'une machine | `wait_for_connection` |

> 💡 `until` fonctionne avec **n'importe quelle** tâche, pas seulement `uri`. C'est le
> mécanisme générique d'attente d'Ansible. On le réutilisera au Lab 09 pour attendre qu'un
> load balancer déclare un backend sain.

</details>

---

## Partie 3 — `block` / `rescue` / `always`

### Exercice E1 — Déploiement avec rattrapage automatique

**Spécifications :**

| Élément | Valeur |
|:---|:---|
| Fichier | `/tp/playbooks/13-blocks.yml` |
| Cible | `web_servers` |
| Fichier déployé | `/etc/apache2/conf-available/monapp-hardening.conf` |
| Validation | `apache2ctl configtest` |
| En cas d'échec | restaurer et désactiver la configuration fautive |
| Dans tous les cas | nettoyer `/tmp/deploy-monapp` |

---

**Tâche 1 —** Écrivez le `block` : sauvegarde de la configuration actuelle, déploiement du
nouveau fichier, activation, validation de la syntaxe Apache, rechargement.

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/playbooks/13-blocks.yml
---
- name: Gestion des erreurs avec block
  hosts: web_servers
  become: true

  tasks:
    - name: Déploiement applicatif sécurisé
      block:
        - name: Sauvegarder la configuration actuelle
          ansible.builtin.copy:
            src: /etc/apache2/apache2.conf
            dest: /etc/apache2/apache2.conf.backup
            remote_src: true
          failed_when: false

        - name: Déployer la nouvelle configuration
          ansible.builtin.copy:
            content: |
              # Configuration déployée par Ansible
              ServerName {{ inventory_hostname }}
              ServerTokens Prod
              ServerSignature Off
            dest: /etc/apache2/conf-available/monapp-hardening.conf
            mode: "0644"

        - name: Activer la configuration
          ansible.builtin.command: a2enconf monapp-hardening
          args:
            creates: /etc/apache2/conf-enabled/monapp-hardening.conf

        - name: Valider la syntaxe Apache
          ansible.builtin.command: apache2ctl configtest
          changed_when: false        # ← simple vérification, ne change rien

        - name: Recharger Apache
          ansible.builtin.service:
            name: apache2
            state: reloaded
```

> 💡 **`changed_when: false` sur la validation.** C'est une tâche de **lecture** : elle
> vérifie sans modifier. Sans cette directive, elle rapporterait `changed` à chaque
> exécution et polluerait votre objectif `changed=0`.

</details>

---

**Tâche 2 —** Ajoutez la section `rescue` : alerter, restaurer la sauvegarde, désactiver la
configuration fautive, redémarrer Apache dans son état stable.

<details><summary>Correction — tâche 2</summary>

```yaml
      rescue:
        - name: Alerter sur l'échec
          ansible.builtin.debug:
            msg: "⚠️ Échec du déploiement sur {{ inventory_hostname }} — restauration"

        - name: Restaurer la configuration précédente
          ansible.builtin.copy:
            src: /etc/apache2/apache2.conf.backup
            dest: /etc/apache2/apache2.conf
            remote_src: true
          failed_when: false

        - name: Désactiver la configuration fautive
          ansible.builtin.command: a2disconf monapp-hardening
          args:
            removes: /etc/apache2/conf-enabled/monapp-hardening.conf

        - name: Redémarrer Apache dans son état stable
          ansible.builtin.service:
            name: apache2
            state: restarted
```

**Le `rescue` ne s'exécute que si une tâche du `block` a échoué.** Si tout se passe bien, il
est intégralement ignoré.

> 💡 Deux variables sont disponibles dans un `rescue` :
>
> | Variable | Contenu |
> |:---|:---|
> | `ansible_failed_task` | La tâche qui a échoué (dont son `name`) |
> | `ansible_failed_result` | Le résultat complet de l'échec |
>
> ```yaml
>         - ansible.builtin.debug:
>             msg: "Échec sur : {{ ansible_failed_task.name }}"
> ```

</details>

---

**Tâche 3 —** Ajoutez la section `always` : nettoyage des fichiers temporaires et
journalisation de l'état final.

<details><summary>Correction — tâche 3</summary>

```yaml
      always:
        - name: Nettoyer les fichiers temporaires
          ansible.builtin.file:
            path: /tmp/deploy-monapp
            state: absent

        - name: Journaliser l'état final
          ansible.builtin.debug:
            msg: "Déploiement terminé sur {{ inventory_hostname }}"
```

```bash
ansible-playbook playbooks/13-blocks.yml
```

**Les trois sections :**

| Section | Exécution |
|:---|:---|
| `block` | Les tâches normales — le « try » |
| `rescue` | **Uniquement** si une tâche du `block` échoue — le « catch » |
| `always` | **Toujours**, succès ou échec — le « finally » |

> 💡 `always` est l'endroit du **nettoyage garanti** : suppression de fichiers temporaires,
> libération d'un verrou, réintégration d'un serveur dans un load balancer, notification.

</details>

---

**Tâche 4 —** Provoquez volontairement un échec pour vérifier que le `rescue` fonctionne.
Quel est le statut final du play ?

<details><summary>Correction — tâche 4</summary>

**Cassez la configuration Apache :**

```yaml
        - name: Déployer la nouvelle configuration
          ansible.builtin.copy:
            content: |
              CETTE LIGNE EST UNE ERREUR DE SYNTAXE APACHE !!!
            dest: /etc/apache2/conf-available/monapp-hardening.conf
            mode: "0644"
```

```bash
ansible-playbook playbooks/13-blocks.yml
```

```
TASK [Valider la syntaxe Apache] ****
fatal: [node1]: FAILED! => {"msg": "non-zero return code"}

TASK [Alerter sur l'échec] ****
ok: [node1] => {"msg": "⚠️ Échec du déploiement sur node1 — restauration"}

TASK [Restaurer la configuration précédente] ****
ok: [node1]

TASK [Désactiver la configuration fautive] ****
changed: [node1]

TASK [Redémarrer Apache dans son état stable] ****
changed: [node1]

TASK [Nettoyer les fichiers temporaires] ****
ok: [node1]

PLAY RECAP
node1 : ok=8  changed=3  failed=0        ← failed=0 !
```

> 🔑 **Le point clé : `failed=0`.** Si le `rescue` s'exécute **sans erreur**, le play est
> considéré comme **réussi**. L'échec a été « rattrapé », exactement comme un `try/catch`
> qui gère l'exception.
>
> **Conséquence importante :** si vous voulez qu'un échec rattrapé reste visible en CI/CD,
> terminez le `rescue` par un `fail:` explicite :
>
> ```yaml
>       rescue:
>         - name: Restaurer
>           ...
>         - name: Signaler l'échec malgré la restauration
>           ansible.builtin.fail:
>             msg: "Déploiement échoué, configuration restaurée"
> ```

**Rétablissez la configuration valide avant de continuer.**

</details>

---

### Exercice E2 — Maîtriser les statuts de tâche

**Spécifications :**

| Élément | Valeur |
|:---|:---|
| Fichier | `/tp/playbooks/14-erreurs.yml` |
| Cible | `node1` |

---

**Tâche 1 —** Écrivez une tâche qui exécute `/bin/false` (échoue toujours) **sans**
interrompre le playbook, et enregistrez son résultat.

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/playbooks/14-erreurs.yml
---
- name: Maîtriser les statuts de tâche
  hosts: node1
  become: true

  tasks:
    - name: Commande qui échoue mais ne bloque pas
      ansible.builtin.command: /bin/false
      ignore_errors: true
      register: r1

    - ansible.builtin.debug:
        msg: "failed={{ r1.failed }} · rc={{ r1.rc }}"
```

```bash
ansible-playbook playbooks/14-erreurs.yml
```

```
TASK [Commande qui échoue mais ne bloque pas] ****
fatal: [node1]: FAILED! => {"rc": 1, ...}
...ignoring

TASK [debug] ****
ok: [node1] => {"msg": "failed=True · rc=1"}
```

**`ignore_errors: true`** : la tâche est bien marquée `failed`, mais le play continue.

</details>

---

**Tâche 2 —** La commande `grep "chaine-absente" /etc/passwd` renvoie le code `1` quand elle
ne trouve rien — ce n'est **pas** une erreur. Écrivez la tâche pour qu'Ansible ne la
considère en échec qu'à partir du code `2`.

<details><summary>Correction — tâche 2</summary>

```yaml
    - name: Grep qui ne trouve rien (code retour 1, ce n'est PAS une erreur)
      ansible.builtin.command: grep "chaine-absente" /etc/passwd
      register: r2
      failed_when: r2.rc > 1          # 0 = trouvé, 1 = non trouvé, 2+ = vraie erreur
      changed_when: false
```

```bash
ansible-playbook playbooks/14-erreurs.yml
```

La tâche apparaît en `ok` alors que `grep` a renvoyé `1`.

**`failed_when` redéfinit le critère d'échec.** C'est indispensable pour toutes les
commandes dont le code retour non nul est significatif :

| Commande | Code 1 signifie |
|:---|:---|
| `grep` | Aucune correspondance trouvée |
| `diff` | Les fichiers diffèrent |
| `systemctl is-active` | Le service est inactif |
| `test -f` | Le fichier n'existe pas |

> 🔑 **`failed_when` est très supérieur à `ignore_errors`** : au lieu de masquer toutes les
> erreurs, il exprime **précisément** ce qui constitue un échec. Une vraie erreur (code 2 :
> fichier illisible) sera toujours détectée.

</details>

---

**Tâche 3 —** Écrivez une tâche qui liste les services actifs. Exécutez le playbook deux
fois : que constatez-vous sur son statut, et comment le corriger ?

<details><summary>Correction — tâche 3</summary>

**Version naïve :**

```yaml
    - name: Lister les services actifs
      ansible.builtin.command: systemctl list-units --type=service --state=running
      register: services
```

→ **`changed` à chaque exécution**, alors que la tâche n'a **rien modifié**. `command` ne
peut pas savoir si son exécution a changé quelque chose : il rapporte donc toujours
`changed`.

**Version corrigée :**

```yaml
    - name: Lister les services actifs
      ansible.builtin.command: systemctl list-units --type=service --state=running
      register: services
      changed_when: false             # ⭐ tâche de LECTURE
```

```yaml
    - ansible.builtin.debug:
        msg: "{{ services.stdout_lines | length }} services actifs"
```

> 🔑 **`changed_when: false` sur TOUTE tâche de lecture.** C'est la clé pour atteindre le
> fameux `changed=0` en seconde exécution — le critère de qualité d'un playbook.
>
> **Les tâches concernées :** `command`/`shell` de diagnostic, validations de syntaxe
> (`nginx -t`, `apache2ctl configtest`), requêtes SQL en lecture, appels d'API `GET`.

</details>

---

**Tâche 4 —** Une commande affiche `Configuration mise a jour` quand elle a effectivement
agi. Écrivez la tâche pour qu'Ansible rapporte `changed` **uniquement** dans ce cas.

<details><summary>Correction — tâche 4</summary>

```yaml
    - name: Appliquer une configuration via un script
      ansible.builtin.command: echo "Configuration mise a jour"
      register: r4
      changed_when: "'mise a jour' in r4.stdout"
```

**`changed_when` accepte une condition**, pas seulement `false`. On y exprime la règle
métier qui détermine si l'état a réellement changé.

**Autres formes courantes :**

```yaml
# Selon le code retour
changed_when: r.rc == 0

# Selon un motif dans la sortie
changed_when: "'updated' in r.stdout"

# Jamais changé (lecture)
changed_when: false

# Combinaison avec failed_when
- ansible.builtin.command: /opt/deploy.sh
  register: r
  changed_when: "'DEPLOYED' in r.stdout"
  failed_when: r.rc != 0 or 'ERROR' in r.stderr
```

> 💡 C'est ainsi qu'on rend un script `command`/`shell` presque aussi propre qu'un vrai
> module : il rapporte correctement son état, et les **handlers** peuvent se déclencher
> dessus.

</details>

---

**Tâche 5 —** Récapitulez : quand utiliser `ignore_errors`, `failed_when`, ou
`changed_when` ?

<details><summary>Correction — tâche 5</summary>

**Le tableau de décision :**

| Directive | Ce qu'elle fait | Quand l'utiliser |
|:---|:---|:---|
| `ignore_errors: true` | La tâche est marquée `failed` mais le play continue | Tâche **réellement** optionnelle. **À utiliser avec parcimonie** |
| `failed_when: <cond>` | **Redéfinit** ce qui constitue un échec | Commande dont le code retour ≠ 0 n'est pas une erreur (`grep`, `diff`…) |
| `changed_when: false` | La tâche ne rapporte **jamais** `changed` | **Toute** tâche de lecture/vérification |
| `changed_when: <cond>` | `changed` selon une condition métier | Script dont la sortie indique s'il a agi |
| `block`/`rescue` | Rattrape l'échec et compense | Échec prévisible avec un plan B |

> ⚠️ **`ignore_errors` masque les problèmes.** Le `PLAY RECAP` affiche `failed=0` alors que
> la tâche a échoué : en CI/CD, le pipeline passerait au vert. Préférez systématiquement
> `failed_when`, qui exprime votre intention, ou `block`/`rescue`, qui gère explicitement le
> cas d'erreur.

> 🔑 **`changed_when: false` sur toutes les tâches de lecture** est ce qui vous permettra
> d'atteindre `changed=0` en seconde exécution. C'est la marque d'un playbook professionnel,
> et c'est testable automatiquement en CI (voir Lab 11).

</details>

---

## Partie 4 — Tags et exécution partielle

### Exercice T1 — Taguer un playbook

**Spécifications — tags attendus par tâche :**

| Tâche | Tags |
|:---|:---|
| Mettre à jour le cache APT | `always` |
| Installer Apache | `web`, `install` |
| Installer PHP | `web`, `install`, `php` |
| Configurer Apache | `web`, `config` |
| Installer MariaDB | `db`, `install` |
| Configurer MariaDB | `db`, `config` |
| Diagnostic complet | `never`, `debug` |

| Élément | Valeur |
|:---|:---|
| Fichier | `/tp/playbooks/15-tags.yml` |
| Cible | tous les hôtes |

---

**Tâche 1 —** Écrivez le playbook avec les tags de composant (`web`, `db`) et de phase
(`install`, `config`).

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/playbooks/15-tags.yml
---
- name: Déploiement avec tags
  hosts: all
  become: true

  tasks:
    - name: Installer Apache
      ansible.builtin.apt:
        name: apache2
        state: present
      when: "'web_servers' in group_names"
      tags: [web, install]

    - name: Installer PHP
      ansible.builtin.apt:
        name: [php, libapache2-mod-php]
        state: present
      when: "'web_servers' in group_names"
      tags: [web, install, php]

    - name: Configurer Apache
      ansible.builtin.copy:
        content: "ServerName {{ inventory_hostname }}\n"
        dest: /etc/apache2/conf-available/servername.conf
        mode: "0644"
      when: "'web_servers' in group_names"
      tags: [web, config]

    - name: Installer MariaDB
      ansible.builtin.apt:
        name: mariadb-server
        state: present
      when: "'db_servers' in group_names"
      tags: [db, install]

    - name: Configurer MariaDB
      ansible.builtin.lineinfile:
        path: /etc/mysql/mariadb.conf.d/50-server.cnf
        regexp: '^bind-address'
        line: "bind-address = 0.0.0.0"
      when: "'db_servers' in group_names"
      tags: [db, config]
```

```bash
ansible-playbook playbooks/15-tags.yml --list-tags
```

```
TASK TAGS: [config, db, install, php, web]
```

</details>

---

**Tâche 2 —** Ajoutez la tâche de mise à jour du cache APT, taguée de sorte qu'elle
s'exécute **quel que soit** le `--tags` demandé. Pourquoi est-ce nécessaire ?

<details><summary>Correction — tâche 2</summary>

```yaml
    - name: Mettre à jour le cache APT
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      tags: [always]              # ← s'exécute TOUJOURS
```

**Placez-la en première position** dans la liste des tâches.

> 🔑 **Pourquoi `always` est nécessaire.** Si vous lancez `--tags install`, seules les
> tâches portant le tag `install` s'exécutent. La mise à jour du cache APT — qui n'a ni le
> tag `install` ni aucun autre — serait ignorée, et les installations échoueraient avec
> `Unable to locate package`.
>
> **Le tag `always` est fait pour les prérequis structurels** : rafraîchissement de cache,
> collecte de facts nécessaires, création d'un répertoire de base.

```bash
# Vérification : la tâche s'exécute malgré le filtre
ansible-playbook playbooks/15-tags.yml --tags config
```

> ⚠️ Pour l'exclure malgré tout : `--skip-tags always`.

</details>

---

**Tâche 3 —** Ajoutez une tâche de diagnostic lourde qui ne doit **jamais** s'exécuter sauf
demande explicite.

<details><summary>Correction — tâche 3</summary>

```yaml
    - name: Diagnostic complet (lourd)
      ansible.builtin.command: systemctl status
      changed_when: false
      failed_when: false
      tags: [never, debug]        # ← JAMAIS exécuté sauf --tags debug
```

```bash
# La tâche est ignorée
ansible-playbook playbooks/15-tags.yml

# La tâche s'exécute
ansible-playbook playbooks/15-tags.yml --tags debug
```

**Les deux tags spéciaux :**

| Tag | Comportement |
|:---|:---|
| `always` | Exécuté **quel que soit** le `--tags` (sauf `--skip-tags always`) |
| `never` | **Jamais** exécuté, sauf si explicitement demandé par `--tags` |

> 💡 **Usage typique de `never` :** tâches de debug verbeuses, opérations destructrices
> (purge de base, suppression de volumes), migrations à ne déclencher qu'une fois.
>
> Le second tag (`debug`) est ce qui permet de la déclencher : `--tags never` ne
> fonctionnerait pas de façon lisible.

</details>

---

**Tâche 4 —** Donnez les commandes permettant de : lister les tags ; n'exécuter que la
partie web ; n'exécuter que les configurations ; tout faire **sauf** les installations.

<details><summary>Correction — tâche 4</summary>

```bash
# Lister tous les tags disponibles
ansible-playbook playbooks/15-tags.yml --list-tags

# Lister les tâches qui seraient exécutées avec un filtre
ansible-playbook playbooks/15-tags.yml --tags config --list-tasks

# N'exécuter que la partie web
ansible-playbook playbooks/15-tags.yml --tags web

# N'exécuter que les configurations (web + db), sans réinstaller
ansible-playbook playbooks/15-tags.yml --tags config

# Tout SAUF les installations (rapide, pour un simple ajustement)
ansible-playbook playbooks/15-tags.yml --skip-tags install

# Combiner plusieurs tags (union)
ansible-playbook playbooks/15-tags.yml --tags "web,db"

# Déclencher explicitement une tâche taguée "never"
ansible-playbook playbooks/15-tags.yml --tags debug
```

> 💡 **`--list-tasks` combiné à `--tags`** est le réflexe de sécurité : il montre
> **exactement** quelles tâches seront jouées, sans rien exécuter.

</details>

---

### Exercice T2 — Définir une stratégie de tags

**Tâche 1 —** Quels sont les trois axes de tagging recommandés sur un projet réel ? Donnez
un exemple pour chacun.

<details><summary>Correction — tâche 1</summary>

**Trois axes, cumulables sur une même tâche :**

```yaml
tags:
  - web           # 1. AXE COMPOSANT : quelle partie de la stack
  - install       # 2. AXE PHASE     : install / config / deploy / test
  - apache        # 3. AXE TECHNO    : le logiciel précis
```

**Les phases standard :**

| Tag de phase | Contenu | Fréquence de rejeu |
|:---|:---|:---|
| `install` | Installation de paquets | Rare — lent |
| `config` | Fichiers de configuration | **Le plus souvent rejoué** |
| `deploy` | Déploiement du code applicatif | À chaque release |
| `test` | Vérifications post-déploiement | À chaque exécution |

**Ce que cela permet au quotidien :**

```bash
# Ajuster un paramètre de configuration en 20 secondes au lieu de 10 minutes
ansible-playbook site.yml --tags config

# Redéployer uniquement le code après un commit
ansible-playbook site.yml --tags deploy

# Valider l'infrastructure sans rien modifier
ansible-playbook site.yml --tags test --check
```

</details>

---

**Tâche 2 —** Vous lancez `--tags config` et l'exécution échoue parce qu'un fichier de
configuration référence un répertoire inexistant. Quelle est la cause, et comment
l'éviter ?

<details><summary>Correction — tâche 2</summary>

**La cause : une dépendance non taguée.** Le répertoire est créé par une tâche taguée
`install`, qui n'est pas jouée quand on demande `--tags config`.

```yaml
# ❌ Le problème
- name: Créer /var/www/monapp
  ansible.builtin.file:
    path: /var/www/monapp
    state: directory
  tags: [web, install]          # ← pas joué avec --tags config

- name: Déployer la config qui référence /var/www/monapp
  ansible.builtin.template:
    src: vhost.conf.j2
    dest: /etc/apache2/sites-available/monapp.conf
  tags: [web, config]           # ← joué, mais le répertoire manque
```

**Trois solutions :**

```yaml
# ✅ 1. Tagger le prérequis en always (le plus simple)
- name: Créer /var/www/monapp
  ansible.builtin.file: { path: /var/www/monapp, state: directory }
  tags: [always]

# ✅ 2. Ajouter le tag config au prérequis
  tags: [web, install, config]

# ✅ 3. Regrouper dans un block tagué
- block:
    - name: Créer le répertoire
      ...
    - name: Déployer la config
      ...
  tags: [web, config]
```

**Les erreurs de tagging à éviter :**

| Erreur | Conséquence |
|:---|:---|
| Tagger toutes les tâches avec le même tag | Aucune granularité — le tag ne sert à rien |
| Ne pas tagger du tout | Impossible de rejouer partiellement → on rejoue tout |
| Tags incohérents entre rôles | `--tags config` n'attrape qu'une partie des configs |
| Oublier `always` sur les prérequis | **Le cas ci-dessus** — échec en exécution partielle |

> 💡 **Le test de validation d'une stratégie de tags :** chaque `--tags <phase>` doit
> pouvoir s'exécuter **seul**, sur une machine vierge, sans échouer. Si ce n'est pas le cas,
> il manque un `always` quelque part.

</details>

---

## Partie 5 — Découper un playbook

### Exercice I1 — `import_tasks` et `include_tasks`

**Spécifications :**

| Fichier | Contenu |
|:---|:---|
| `/tp/playbooks/tasks/install-web.yml` | Installation d'Apache et PHP |
| `/tp/playbooks/tasks/config-web.yml` | Déploiement du ServerName et activation |
| `/tp/playbooks/16-includes.yml` | Playbook maître, cible `web_servers` |

---

**Tâche 1 —** Créez les deux fichiers de tâches. Quelle est leur particularité par rapport
à un playbook ?

<details><summary>Correction — tâche 1</summary>

```bash
mkdir -p /tp/playbooks/tasks
```

```yaml
# /tp/playbooks/tasks/install-web.yml
---
- name: Installer Apache
  ansible.builtin.apt:
    name: apache2
    state: present
    update_cache: true

- name: Installer PHP
  ansible.builtin.apt:
    name: [php, libapache2-mod-php]
    state: present
```

```yaml
# /tp/playbooks/tasks/config-web.yml
---
- name: Déployer le ServerName
  ansible.builtin.copy:
    content: "ServerName {{ inventory_hostname }}\n"
    dest: /etc/apache2/conf-available/servername.conf
    mode: "0644"

- name: Activer la configuration
  ansible.builtin.command: a2enconf servername
  args:
    creates: /etc/apache2/conf-enabled/servername.conf
```

> 🔑 **La particularité : ce sont des listes de tâches, pas des playbooks.** Il n'y a
> **ni `hosts:`, ni `become:`, ni `tasks:`** — seulement la liste de tâches elle-même. Ces
> paramètres sont hérités du play qui les inclut.
>
> C'est exactement le format de `roles/<rôle>/tasks/main.yml` que vous verrez au Lab 07.

</details>

---

**Tâche 2 —** Écrivez le playbook maître qui importe le fichier d'installation de manière
**statique** (tag `install`) et le fichier de configuration de manière **dynamique**
(tag `config`).

<details><summary>Correction — tâche 2</summary>

```yaml
# /tp/playbooks/16-includes.yml
---
- name: Playbook modulaire
  hosts: web_servers
  become: true

  tasks:
    # --- import_tasks : STATIQUE, résolu au parsing ---
    - name: Installation
      ansible.builtin.import_tasks: tasks/install-web.yml
      tags: [install]

    # --- include_tasks : DYNAMIQUE, résolu à l'exécution ---
    - name: Configuration
      ansible.builtin.include_tasks: tasks/config-web.yml
      tags: [config]
```

```bash
cd /tp
ansible-playbook playbooks/16-includes.yml
```

> 💡 Les chemins sont relatifs au **playbook**, pas au répertoire courant. `tasks/install-web.yml`
> est bien résolu en `/tp/playbooks/tasks/install-web.yml`.

</details>

---

**Tâche 3 —** Comparez `--list-tasks` sur ce playbook. Quelle différence observez-vous
entre les deux méthodes, et pourquoi ?

<details><summary>Correction — tâche 3</summary>

```bash
ansible-playbook playbooks/16-includes.yml --list-tasks
```

```
tasks:
  Installer Apache          TAGS: [install]     ← contenu de import_tasks VISIBLE
  Installer PHP             TAGS: [install]     ← contenu de import_tasks VISIBLE
  Configuration             TAGS: [config]      ← seul le nom de l'INCLUSION
```

**L'explication tient au moment de la résolution :**

| | `import_tasks` (statique) | `include_tasks` (dynamique) |
|:---|:---|:---|
| **Moment de résolution** | Au **parsing**, avant l'exécution | À l'**exécution**, au moment de la tâche |
| Visible dans `--list-tasks` | ✅ Oui, tâche par tâche | ❌ Non — contenu inconnu avant exécution |
| Nom de fichier variable | ❌ Impossible | ✅ Possible |
| Dans une boucle (`loop`) | ❌ Impossible | ✅ Possible |
| Héritage des tags | ✅ Les tâches héritent du tag | ⚠️ Le tag ne s'applique qu'à l'inclusion |
| Performance | Légèrement meilleure | Légèrement moindre |

> 🔑 **Règle de choix :**
> * Chemin **fixe** et connu → `import_tasks` (meilleure visibilité, tags corrects)
> * Chemin **variable**, boucle, ou condition dynamique → `include_tasks`

</details>

---

**Tâche 4 —** Lancez `--tags config`. La configuration s'exécute-t-elle réellement ? Si le
comportement vous surprend, corrigez-le.

<details><summary>Correction — tâche 4</summary>

```bash
ansible-playbook playbooks/16-includes.yml --tags config
```

Selon la version d'Ansible, les tâches **incluses** peuvent ne **pas** s'exécuter : le tag
`config` s'applique à l'instruction `include_tasks` elle-même, mais ne se **propage pas
automatiquement** aux tâches qu'elle charge.

> ⚠️ **C'est le piège classique des tags avec `include_tasks`.** L'inclusion est bien
> déclenchée, mais les tâches internes — qui n'ont aucun tag — sont ensuite filtrées.

**Deux corrections possibles :**

```yaml
# ✅ Solution 1 — propager explicitement avec apply
    - name: Configuration
      ansible.builtin.include_tasks:
        file: tasks/config-web.yml
        apply:
          tags: [config]
      tags: [config]
```

```yaml
# ✅ Solution 2 — taguer les tâches dans le fichier inclus
# /tp/playbooks/tasks/config-web.yml
---
- name: Déployer le ServerName
  ansible.builtin.copy:
    ...
  tags: [config]

- name: Activer la configuration
  ansible.builtin.command: a2enconf servername
  ...
  tags: [config]
```

```bash
ansible-playbook playbooks/16-includes.yml --tags config --list-tasks
ansible-playbook playbooks/16-includes.yml --tags config
```

> 💡 **C'est la principale raison de préférer `import_tasks`** quand le chemin est fixe :
> les tags se propagent naturellement, et `--list-tasks` reste exploitable.

</details>

---

**Tâche 5 —** Écrivez une inclusion dont le **nom de fichier** dépend de la famille d'OS de
la machine. Pourquoi `import_tasks` est-il impossible ici ?

<details><summary>Correction — tâche 5</summary>

```yaml
    - name: Charger les tâches spécifiques à l'OS
      ansible.builtin.include_tasks: "tasks/config-{{ ansible_os_family | lower }}.yml"
```

```bash
# Créez le fichier correspondant
cat > /tp/playbooks/tasks/config-debian.yml <<'EOF'
---
- name: Tâche spécifique Debian
  ansible.builtin.debug:
    msg: "Configuration Debian appliquée sur {{ inventory_hostname }}"
EOF

ansible-playbook playbooks/16-includes.yml
```

> 🔑 **`import_tasks` est impossible ici** parce qu'il est résolu au **parsing**, avant que
> la moindre connexion ne soit établie — donc **avant** que `ansible_os_family` ne soit
> connu. Le nom de fichier ne peut pas contenir de variable dépendant de la cible.
>
> `include_tasks`, résolu à l'exécution, dispose de tous les facts et peut construire le
> chemin dynamiquement.

**Version robuste avec repli** — si le fichier spécifique n'existe pas :

```yaml
    - name: Charger les tâches spécifiques à l'OS
      ansible.builtin.include_tasks: "{{ lookup('first_found', fichiers) }}"
      vars:
        fichiers:
          - "tasks/config-{{ ansible_distribution | lower }}.yml"
          - "tasks/config-{{ ansible_os_family | lower }}.yml"
          - "tasks/config-default.yml"
```

> 💡 C'est le motif standard des rôles multi-distribution, que vous retrouverez au Lab 07.

</details>

---

### Exercice I2 — Nettoyer et préparer le lab suivant

**Tâche 1 —** Supprimez les paquets, comptes et répertoires créés pendant ce lab.

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/playbooks/reset-lab05.yml
---
- name: Remise à zéro du lab 05
  hosts: all
  become: true

  vars:
    comptes: [alice, bob, charlie]
    paquets: [apache2, php, libapache2-mod-php, mariadb-server]

  tasks:
    - name: Arrêter les services
      ansible.builtin.service:
        name: "{{ item }}"
        state: stopped
      loop: [apache2, mariadb]
      failed_when: false

    - name: Désinstaller les paquets
      ansible.builtin.apt:
        name: "{{ paquets }}"
        state: absent
        purge: true
        autoremove: true

    - name: Supprimer les comptes
      ansible.builtin.user:
        name: "{{ item }}"
        state: absent
        remove: true
      loop: "{{ comptes }}"
      failed_when: false

    - name: Supprimer les répertoires
      ansible.builtin.file:
        path: "{{ item }}"
        state: absent
      loop:
        - /opt/app
        - /etc/apache2
```

```bash
ansible-playbook playbooks/reset-lab05.yml
```

</details>

---

**Tâche 2 —** Le Lab 06 utilise les groupes `web` et `db`. Adaptez l'inventaire en
conséquence, en conservant les anciens noms.

<details><summary>Correction — tâche 2</summary>

Un hôte pouvant appartenir à plusieurs groupes (Lab 02), il suffit de **déclarer les deux
jeux de noms** :

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
        # --- Noms utilisés à partir du Lab 06 ---
        web:
          hosts:
            node1:
            node2:
        db:
          hosts:
            node3:

    # --- Alias conservés depuis le Lab 04 ---
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
ansible web --list-hosts
ansible web_servers --list-hosts     # même résultat
```

> 💡 Les deux motifs ciblent les mêmes machines. Aucun de vos playbooks existants ne casse,
> et les labs suivants fonctionnent directement.
>
> ⚠️ **En production, on évite ce genre de doublon** : deux noms pour la même chose est une
> source de confusion. Ici, c'est une commodité pédagogique le temps de la transition.

</details>

---

## À retenir

| Point clé | Détail |
|:---|:---|
| **`when` sans `{{ }}`** | `when` attend déjà une expression Jinja2. Idem `failed_when`, `changed_when`, `until`. |
| **Liste dans `when`** | Une liste de conditions = **ET** logique. Pour un OU : `or` sur une ligne. |
| **`skipping` ≠ échec** | Une tâche non exécutée n'apparaît pas dans le compteur `failed`. |
| **Dictionnaire de correspondance** | Remplace élégamment plusieurs `when` sur l'OS. |
| **`loop` > `with_*`** | Syntaxe moderne. Les `with_*` restent partout dans le code existant. |
| **Liste native > boucle** | Pour `apt`/`yum` : passez la liste directement, c'est bien plus rapide. |
| **`loop_control.label`** | Indispensable quand on boucle sur des dictionnaires. |
| **`until` / `retries` / `delay`** | Le mécanisme générique d'attente, valable pour toute tâche. |
| **`block`/`rescue`/`always`** | Le try/catch/finally d'Ansible. Un `rescue` réussi = play **réussi**. |
| **`changed_when: false`** | Sur **toute** tâche de lecture. C'est la clé du `changed=0`. |
| **`failed_when` > `ignore_errors`** | Exprime l'intention au lieu de masquer le problème. |
| **Tags `always` / `never`** | Prérequis systématiques / tâches sur demande explicite. |
| **`import` vs `include`** | Statique (visible, tags OK) vs dynamique (variables, boucles). |

### Les commandes de ce lab

```bash
ansible-playbook site.yml --list-tags        # quels tags existent ?
ansible-playbook site.yml --list-tasks       # quelles tâches vont s'exécuter ?
ansible-playbook site.yml --tags config      # n'exécuter qu'une phase
ansible-playbook site.yml --skip-tags install
ansible-playbook site.yml --step             # validation interactive
```

### Ce qui sera approfondi plus loin

| Notion vue ici | Approfondie au |
|:---|:---|
| Filtres Jinja2 (`dict2items`, `selectattr`, `map`) | **Lab 06** — Templating |
| `tasks/main.yml` sous forme de rôle | **Lab 07** — Rôles |
| `until` pour attendre un backend sain | **Lab 09** — Orchestration |
| `changed_when` contrôlé automatiquement en CI | **Lab 11** — Industrialisation |

---

⬅️ **Lab précédent :** [Lab 04 — Premier playbook et stack LAMP](<../lab 04 - Premier playbook et stack LAMP/instructions.md>)
➡️ **Lab suivant :** [Lab 06 — Templating Jinja2 et facts](<../lab 06 - Templating Jinja2 et facts/instructions.md>)
