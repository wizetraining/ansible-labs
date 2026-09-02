# Lab 06 — Templating Jinja2 et facts

> ⭐ Niveau : ⭐⭐⭐ | ⏱ Durée estimée : 75 min | Module : **M6 — Variables avancées, facts & templating Jinja2**

## Objectifs pédagogiques

* Générer des fichiers de configuration dynamiques avec le module `template`
* Comprendre les trois syntaxes Jinja2 : `{{ }}`, `{% %}`, `{# #}`
* Exploiter les facts pour adapter une configuration au matériel de chaque machine
* Créer des facts personnalisés (`set_fact` et facts persistants via `facts.d`)
* Utiliser les plugins `lookup` pour lire des données côté controller
* Produire un tableau de bord HTML de l'ensemble du parc

## Notions abordées

* Module `template` vs `copy` : quand utiliser lequel
* Jinja2 : `{{ }}` (expression), `{% %}` (instruction), `{# #}` (commentaire)
* Filtres essentiels : `default`, `int`, `join`, `map`, `selectattr`, `to_nice_json`, `regex_replace`
* `set_fact`, facts persistants (`/etc/ansible/facts.d`), `ansible_local`
* Variables magiques : `hostvars`, `groups`, `inventory_hostname`, `ansible_play_hosts`, `group_names`
* Plugins `lookup` : `file`, `env`, `pipe`, `password`, `fileglob`
* `vars_prompt` : demander une valeur à l'exécution
* `validate:` : valider avant d'écrire

## Documentation de référence

* [Templating (Jinja2)](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_templating.html)
* [Playbook filters](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_filters.html)
* [Discovering variables: facts](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_vars_facts.html)
* [Lookup plugins](https://docs.ansible.com/ansible/latest/plugins/lookup.html)

## Contexte

Vos fichiers de configuration sont pour l'instant écrits « en dur » avec `copy`. Résultat :
un fichier par serveur, un VirtualHost Apache identique sur toutes les machines quelle que
soit leur puissance, et aucune vue d'ensemble du parc.

Ce lab vous donne les outils pour aller plus loin : **un seul template** qui s'adapte
automatiquement au matériel, les **filtres Jinja2** pour manipuler n'importe quelle
structure de données, et une **page HTML** générée à la demande qui recense l'état complet
du parc.

---

## Partie 1 — Premier template

### Exercice TM1 — Remplacer la configuration Apache statique par un template

| | |
|:---|:---|
| **Fichiers créés** | `/tp/templates/monapp.conf.j2` · `/tp/playbooks/20-template.yml` |
| **Modules** | `template` · `apt` · `file` · `service` · `command` |
| **Notions** | `{{ }}` · filtre `default` · `validate:` · `ansible_fqdn` · handler |
| **Durée** | ~15 min |

#### Tâche 1 — Créer le répertoire `templates` et écrire le VirtualHost Jinja2.

Dans `/tp`, créez le répertoire `templates/` puis écrivez le fichier
`monapp.conf.j2` ci-dessous. Repérez chaque expression Jinja2 et identifiez
la variable qu'elle référence.

<details><summary>Correction — tâche 1</summary>

```bash
mkdir -p /tp/templates
```

```jinja
{# /tp/templates/monapp.conf.j2 #}
{#
  VirtualHost généré par Ansible — NE PAS ÉDITER À LA MAIN
  Machine  : {{ inventory_hostname }}
  Générateur : Ansible {{ ansible_version.full }}
#}
<VirtualHost *:{{ http_port | default(80) }}>
    ServerName    {{ ansible_fqdn }}
    ServerAdmin   {{ admin_email | default('ops@example.com') }}
    DocumentRoot  {{ document_root }}

    DirectoryIndex index.php index.html

    <Directory {{ document_root }}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ServerTokens Prod
    ServerSignature Off

    ErrorLog  ${APACHE_LOG_DIR}/{{ app_name }}_error.log
    CustomLog ${APACHE_LOG_DIR}/{{ app_name }}_access.log combined
</VirtualHost>
```

**Trois syntaxes Jinja2 dans ce seul fichier :**

| Syntaxe | Rôle | Rendu dans le fichier final |
|:---|:---|:---|
| `{{ variable }}` | Expression — affiche une valeur | ✅ Oui |
| `{% instruction %}` | Logique — conditions, boucles, set | ❌ Non |
| `{# commentaire #}` | Documentation du template | ❌ Non |

</details>

---

#### Tâche 2 — Écrire le playbook qui déploie ce template avec `validate:`.

Le playbook doit : installer Apache, créer la `document_root`, déployer le
template (avec validation avant écriture), activer le site, démarrer le service.
Utilisez un handler pour recharger Apache uniquement en cas de changement.

<details><summary>Correction — tâche 2</summary>

```yaml
# /tp/playbooks/20-template.yml
---
- name: Configuration Apache par template
  hosts: web
  become: yes

  vars:
    app_name: monapp
    document_root: /var/www/monapp
    http_port: 80
    admin_email: ops@example.com

  tasks:
    - name: Installer Apache
      ansible.builtin.apt:
        name: apache2
        state: present
        update_cache: yes

    - name: Créer la racine documentaire
      ansible.builtin.file:
        path: "{{ document_root }}"
        state: directory
        owner: www-data
        mode: "0755"

    - name: Générer le VirtualHost depuis le template
      ansible.builtin.template:
        src: ../templates/monapp.conf.j2
        dest: /etc/apache2/sites-available/{{ app_name }}.conf
        owner: root
        mode: "0644"
        validate: 'apache2ctl -f %s -t'
      notify: Recharger Apache

    - name: Activer le site
      ansible.builtin.command: a2ensite {{ app_name }}.conf
      args:
        creates: /etc/apache2/sites-enabled/{{ app_name }}.conf
      notify: Recharger Apache

    - name: Démarrer Apache
      ansible.builtin.service:
        name: apache2
        state: started
        enabled: yes

  handlers:
    - name: Recharger Apache
      ansible.builtin.service:
        name: apache2
        state: reloaded
```

```bash
ansible-playbook /tp/playbooks/20-template.yml --diff
```

> 🔑 **`validate:`** : Ansible génère le fichier dans un répertoire temporaire,
> exécute la commande de validation (`%s` = chemin temporaire), et n'écrit à
> destination **que si la validation réussit**. Un template cassé ne peut donc
> pas mettre un service hors service.

</details>

---

#### Tâche 3 — Provoquer une erreur de syntaxe Apache et constater que `validate:` protège le serveur.

Ajoutez la ligne `InvalidDirective boom` dans `monapp.conf.j2`, relancez le
playbook, et observez ce qu'Ansible fait. Vérifiez ensuite que le fichier
**déjà en place** sur les serveurs n'a pas été modifié.

<details><summary>Correction — tâche 3</summary>

```jinja
{# Ajoutez cette ligne n'importe où dans monapp.conf.j2 #}
InvalidDirective boom
```

```bash
ansible-playbook /tp/playbooks/20-template.yml --diff
```

Sortie attendue (Ansible échoue **avant** d'écrire le fichier) :

```
TASK [Générer le VirtualHost depuis le template]
fatal: [node1]: FAILED! => {"msg": "failed to validate: ...
AH00526: Syntax error on line N ...
Action: 'InvalidDirective' is not allowed here ..."}
```

Vérifiez que le fichier existant est intact :

```bash
ansible web -m command -a "apache2ctl -t"
# → Syntax OK  (le serveur tourne toujours avec l'ancien fichier)
```

```bash
ansible web -m command -a "grep -c 'InvalidDirective' /etc/apache2/sites-available/monapp.conf"
# → 0  (le fichier cassé n'a jamais été écrit)
```

**Corrigez le template** (supprimez la directive invalide) avant de passer
à la tâche suivante.

> Autres exemples de `validate:` utiles :
> ```yaml
> validate: 'nginx -t -c %s'
> validate: 'visudo -cf %s'
> validate: 'sshd -t -f %s'
> validate: 'named-checkconf %s'
> ```

</details>

---

#### Tâche 4 — Observer que le rendu diffère entre `node1` et `node2`.

Relancez le playbook (sans l'erreur), puis comparez le contenu du fichier
généré sur les deux machines. Pourquoi sont-ils différents alors qu'ils partagent
le même template ?

<details><summary>Correction — tâche 4</summary>

```bash
ansible web -m command -a "cat /etc/apache2/sites-available/monapp.conf"
```

Sortie attendue (les lignes `ServerName` diffèrent) :

```
node1 | SUCCESS | ...
<VirtualHost *:80>
    ServerName    node1.wizetraining.local
    ...

node2 | SUCCESS | ...
<VirtualHost *:80>
    ServerName    node2.wizetraining.local
    ...
```

**Pourquoi :** `{{ ansible_fqdn }}` est résolu au moment du rendu, **pour
chaque hôte séparément**. `ansible_fqdn` est un fact collecté sur la machine
cible — sa valeur est donc différente sur chaque machine.

`template` vs `copy` :

| | `copy` | `template` |
|:---|:---|:---|
| Rendu Jinja2 | ❌ Contenu copié tel quel | ✅ Variables interprétées |
| Extension source | Quelconque | `.j2` par convention |
| Répertoire cherché | `files/` | `templates/` |
| Cas d'usage | Binaire, certificat, fichier figé | **Toute configuration** |

> 💡 La règle pratique : dès qu'une `{{ variable }}` apparaît dans le fichier
> source, utilisez `template` plutôt que `copy`.

</details>

---

#### Tâche 5 — Utiliser le filtre `default` pour rendre le template tolérant aux variables absentes.

Supprimez la variable `admin_email` des `vars:` du playbook. Relancez. Que se
passe-t-il ? Quelle construction dans le template empêche l'échec ?

<details><summary>Correction — tâche 5</summary>

```yaml
  vars:
    app_name: monapp
    document_root: /var/www/monapp
    http_port: 80
    # admin_email supprimé
```

```bash
ansible-playbook /tp/playbooks/20-template.yml --diff
```

Le playbook réussit. La ligne générée dans le VirtualHost :

```
ServerAdmin   ops@example.com
```

**Pourquoi :** `{{ admin_email | default('ops@example.com') }}` renvoie la
valeur de repli quand `admin_email` est indéfinie.

Variantes du filtre `default` :

```jinja
{# Valeur de repli si variable indéfinie #}
{{ port | default(8080) }}

{# Valeur de repli si variable indéfinie OU vide OU false #}
{{ nom | default('anonyme', true) }}

{# Échouer explicitement si la variable est obligatoire #}
{{ db_password | mandatory }}
```

</details>

---

### Exercice TM2 — Dimensionner Apache selon le matériel

| | |
|:---|:---|
| **Fichiers créés** | `/tp/templates/mpm_prefork.conf.j2` |
| **Modules** | `template` · `setup` |
| **Notions** | `{% set %}` · calculs Jinja2 · `ansible_memtotal_mb` · `ansible_processor_vcpus` · filtre `int` · ternaire |
| **Durée** | ~10 min |

#### Tâche 1 — Explorer les facts de matériel disponibles.

Avant d'écrire le template, identifiez les facts qui décrivent la RAM et les
CPU de chaque machine.

<details><summary>Correction — tâche 1</summary>

```bash
# Voir tous les facts d'un coup
ansible node1 -m setup | grep -E '"ansible_mem|ansible_proc'

# Ou cibler directement les facts utiles
ansible node1 -m setup -a "filter=ansible_memtotal_mb"
ansible node1 -m setup -a "filter=ansible_processor_vcpus"
ansible node1 -m setup -a "filter=ansible_processor*"
```

Facts utiles pour le dimensionnement :

| Fact | Description |
|:---|:---|
| `ansible_memtotal_mb` | RAM totale en Mo |
| `ansible_memfree_mb` | RAM libre en Mo |
| `ansible_processor_vcpus` | Nombre de vCPU |
| `ansible_processor_count` | Nombre de processeurs physiques |
| `ansible_processor_cores` | Cœurs par processeur |

</details>

---

#### Tâche 2 — Écrire `mpm_prefork.conf.j2` avec des calculs Jinja2.

Le template doit calculer automatiquement le nombre de workers Apache selon la
RAM disponible : 256 Mo réservés au système, 25 Mo par worker, minimum 8 workers.

<details><summary>Correction — tâche 2</summary>

```jinja
{# /tp/templates/mpm_prefork.conf.j2 #}
{#
  Dimensionnement automatique basé sur les facts
  RAM   : {{ ansible_memtotal_mb }} Mo
  vCPU  : {{ ansible_processor_vcpus }}
#}
{% set ram_reservee    = 256 %}
{% set ram_par_process = 25 %}
{% set ram_dispo       = ansible_memtotal_mb - ram_reservee %}
{% set max_workers     = (ram_dispo / ram_par_process) | int %}
{% set max_workers     = [max_workers, 8] | max %}
{% set start_servers   = [(max_workers / 4) | int, 2] | max %}

<IfModule mpm_prefork_module>
    StartServers            {{ start_servers }}
    MinSpareServers         {{ start_servers }}
    MaxSpareServers         {{ (start_servers * 2) }}
    MaxRequestWorkers       {{ max_workers }}
    MaxConnectionsPerChild  {{ 10000 if ansible_memtotal_mb > 2048 else 1000 }}
</IfModule>

# Généré le {{ ansible_date_time.iso8601 }} pour {{ inventory_hostname }}
# RAM {{ ansible_memtotal_mb }} Mo / {{ ansible_processor_vcpus }} vCPU
```

**Constructions Jinja2 utilisées :**

| Syntaxe | Rôle |
|:---|:---|
| `{% set x = expr %}` | Variable locale au template (non rendue) |
| `{{ expr \| int }}` | Conversion en entier — une division Jinja2 renvoie un flottant |
| `{{ [a, b] \| max }}` | Valeur plancher — évite un résultat absurde sur petite machine |
| `{{ a if cond else b }}` | Ternaire |
| `{# ... #}` | Commentaire **absent** du fichier final |

</details>

---

#### Tâche 3 — Déployer et comparer le rendu sur les deux serveurs web.

Ajoutez la tâche de déploiement au playbook `20-template.yml`, relancez,
puis lisez le fichier généré sur chaque machine. Les valeurs doivent différer
si les machines ont des ressources différentes.

<details><summary>Correction — tâche 3</summary>

Ajoutez dans la section `tasks:` de `20-template.yml` :

```yaml
    - name: Dimensionner le MPM prefork selon le matériel
      ansible.builtin.template:
        src: ../templates/mpm_prefork.conf.j2
        dest: /etc/apache2/mods-available/mpm_prefork.conf
        mode: "0644"
      notify: Recharger Apache
```

```bash
ansible-playbook /tp/playbooks/20-template.yml --diff
ansible web -m command -a "cat /etc/apache2/mods-available/mpm_prefork.conf"
```

Sortie attendue (valeurs calculées selon la RAM réelle) :

```
<IfModule mpm_prefork_module>
    StartServers            9
    MinSpareServers         9
    MaxSpareServers         18
    MaxRequestWorkers       72
    MaxConnectionsPerChild  1000
</IfModule>

# Généré le 2026-09-02T10:15:00Z pour node1
# RAM 2048 Mo / 2 vCPU
```

> 💡 Sur des machines identiques (même RAM, même CPU), le rendu sera identique.
> C'est attendu — le template s'adapte au **matériel**, pas à l'hôte.

</details>

---

## Partie 2 — Jinja2 : conditions, boucles et filtres

### Exercice J1 — Générer `/etc/hosts` depuis l'inventaire

| | |
|:---|:---|
| **Fichiers créés** | `/tp/templates/hosts.j2` · `/tp/playbooks/21-hosts.yml` |
| **Modules** | `template` |
| **Notions** | `{% for %}` · `{% if %}` · `hostvars` · `groups` · `ansible_play_hosts` · `backup: yes` |
| **Durée** | ~10 min |

#### Tâche 1 — Écrire `hosts.j2` avec une boucle sur tous les hôtes de l'inventaire.

Le template doit produire une entrée `IP  FQDN  nom-court` pour chaque hôte,
avec un bloc de commentaires indiquant les groupes. Gérez proprement le cas
où les facts d'un hôte ne sont pas encore collectés.

<details><summary>Correction — tâche 1</summary>

```jinja
{# /tp/templates/hosts.j2 #}
127.0.0.1   localhost
127.0.1.1   {{ ansible_hostname }}

# ---- Parc géré par Ansible ({{ ansible_play_hosts | length }} machines) ----
{% for host in groups['all'] | sort %}
{%   if hostvars[host]['ansible_default_ipv4'] is defined %}
{{ hostvars[host]['ansible_default_ipv4']['address'] }}	{{ hostvars[host]['ansible_fqdn'] }}	{{ host }}
{%   else %}
# {{ host }} — facts non collectés
{%   endif %}
{% endfor %}

# ---- Groupes ----
{% for groupe, membres in groups.items() if groupe not in ['all', 'ungrouped'] %}
# {{ groupe }} : {{ membres | join(', ') }}
{% endfor %}

# Généré par Ansible le {{ ansible_date_time.date }}
```

</details>

---

#### Tâche 2 — Écrire le playbook `21-hosts.yml` et le lancer.

<details><summary>Correction — tâche 2</summary>

```yaml
# /tp/playbooks/21-hosts.yml
---
- name: Générer /etc/hosts depuis l'inventaire
  hosts: all
  become: yes

  tasks:
    - name: Déployer /etc/hosts
      ansible.builtin.template:
        src: ../templates/hosts.j2
        dest: /etc/hosts
        owner: root
        mode: "0644"
        backup: yes
```

```bash
ansible-playbook /tp/playbooks/21-hosts.yml --diff
ansible node1 -m command -a "cat /etc/hosts"
```

> `backup: yes` conserve une copie horodatée de l'ancien fichier avant
> écrasement. Utile pour les fichiers système critiques.

</details>

---

#### Tâche 3 — Piège `hostvars` : démontrer l'échec si les facts ne sont pas collectés.

Modifiez le playbook pour ne cibler que `web` (pas `all`). Relancez et observez
ce qui se passe pour l'entrée de `node3`. Pourquoi ? Quelle est la correction ?

<details><summary>Correction — tâche 3</summary>

```yaml
# Modifiez temporairement
  hosts: web   # ← au lieu de all
```

```bash
ansible-playbook /tp/playbooks/21-hosts.yml --diff
ansible web -m command -a "cat /etc/hosts"
```

Sortie attendue dans le `/etc/hosts` généré :

```
192.168.56.21	node1.wizetraining.local	node1
192.168.56.22	node2.wizetraining.local	node2
# node3 — facts non collectés          ← ligne de commentaire, pas d'IP
```

**Pourquoi :** `hostvars['node3']['ansible_default_ipv4']` est vide parce
que les facts de `node3` n'ont pas été collectés (il n'appartient pas au
play).

**Correction propre** : ajouter un premier play `hosts: all` qui collecte
les facts avant de générer le template :

```yaml
---
# Play 1 : collecter les facts de TOUTES les machines
- name: Collecte des facts
  hosts: all
  gather_facts: yes
  tasks: []

# Play 2 : déployer /etc/hosts sur web seulement
- name: Déployer /etc/hosts
  hosts: web
  become: yes
  tasks:
    - name: Générer /etc/hosts
      ansible.builtin.template:
        src: ../templates/hosts.j2
        dest: /etc/hosts
        owner: root
        mode: "0644"
        backup: yes
```

Restaurez `hosts: all` dans le playbook pour la suite du lab.

</details>

---

#### Tâche 4 — Explorer les variables magiques disponibles dans un template.

Affichez le contenu des variables magiques principales directement depuis
le controller (sans template) pour comprendre leur structure.

<details><summary>Correction — tâche 4</summary>

```yaml
# /tp/playbooks/debug-magic.yml
---
- name: Explorer les variables magiques
  hosts: node1
  gather_facts: yes

  tasks:
    - ansible.builtin.debug:
        msg:
          - "inventory_hostname  : {{ inventory_hostname }}"
          - "ansible_hostname    : {{ ansible_hostname }}"
          - "ansible_fqdn        : {{ ansible_fqdn }}"
          - "group_names         : {{ group_names }}"
          - "ansible_play_hosts  : {{ ansible_play_hosts }}"
          - "groups.web          : {{ groups['web'] }}"
          - "hostvars node2 IP   : {{ hostvars['node2']['ansible_default_ipv4']['address'] }}"
```

**Les variables magiques à connaître :**

| Variable | Contenu |
|:---|:---|
| `inventory_hostname` | Nom de l'hôte dans l'inventaire (pas forcément le FQDN) |
| `ansible_hostname` | Nom court retourné par `hostname` sur la machine |
| `ansible_fqdn` | FQDN complet (`hostname --fqdn`) |
| `group_names` | Liste des groupes de **l'hôte courant** |
| `groups` | Dictionnaire `{groupe → [hôtes]}` de tout l'inventaire |
| `hostvars[h]` | Toutes les variables et facts de l'hôte `h` |
| `ansible_play_hosts` | Hôtes du play **encore actifs** (exclut ceux en échec) |

</details>

---

### Exercice J2 — Configuration de load balancer auto-générée

| | |
|:---|:---|
| **Fichiers créés** | `/tp/templates/haproxy.cfg.j2` · `/tp/playbooks/22-lb.yml` |
| **Modules** | `template` · `debug` · `command` |
| **Notions** | `hostvars` depuis `localhost` · multi-play · `connection: local` · `{% if %}` conditionnel |
| **Durée** | ~10 min |

#### Tâche 1 — Écrire `haproxy.cfg.j2` listant automatiquement les backends `web`.

Le template génère une config HAProxy avec autant de lignes `server` qu'il y a
d'hôtes dans `groups['web']`. Un bloc `stats` n'apparaît qu'hors production.

<details><summary>Correction — tâche 1</summary>

```jinja
{# /tp/templates/haproxy.cfg.j2 #}
global
    log /dev/log local0
    maxconn {{ ansible_processor_vcpus * 2000 }}
    daemon

defaults
    mode    http
    timeout connect 5s
    timeout client  30s
    timeout server  30s

frontend web_front
    bind *:{{ lb_port | default(8080) }}
    default_backend web_pool

backend web_pool
    balance {{ lb_algorithm | default('roundrobin') }}
    option httpchk GET /
{% for host in groups['web'] | sort %}
    server {{ host }} {{ hostvars[host].ansible_default_ipv4.address }}:{{ hostvars[host].http_port | default(80) }} check weight {{ hostvars[host].lb_weight | default(100) }}
{% endfor %}

{# Statistiques uniquement hors production #}
{% if env | default('dev') != 'production' %}
listen stats
    bind *:9000
    stats enable
    stats uri /stats
{% endif %}
```

</details>

---

#### Tâche 2 — Écrire le playbook en deux plays : collecte sur `all`, rendu sur `localhost`.

Pour que `hostvars` soit peuplé pour tous les hôtes, il faut d'abord collecter
les facts. La configuration elle-même est générée sur le controller (pas besoin
de HAProxy installé sur les nœuds web).

<details><summary>Correction — tâche 2</summary>

```yaml
# /tp/playbooks/22-lb.yml
---
# Play 1 : peuple hostvars pour tous les hôtes
- name: Collecte des facts
  hosts: all
  gather_facts: yes
  tasks: []

# Play 2 : génère la config sur le controller
- name: Générer la configuration du load balancer
  hosts: localhost
  connection: local
  gather_facts: yes

  tasks:
    - name: Rendre le template HAProxy
      ansible.builtin.template:
        src: ../templates/haproxy.cfg.j2
        dest: /tp/haproxy.cfg
        mode: "0644"

    - name: Afficher le résultat
      ansible.builtin.command: cat /tp/haproxy.cfg
      changed_when: false
      register: cfg

    - ansible.builtin.debug:
        var: cfg.stdout_lines
```

```bash
ansible-playbook /tp/playbooks/22-lb.yml
```

</details>

---

#### Tâche 3 — Ajouter un poids différent pour `node2` et vérifier que le template se met à jour.

Ajoutez `lb_weight: 200` dans l'inventaire pour `node2` seulement. Relancez
le playbook. Le template doit refléter automatiquement ce changement sans
modification du fichier `.j2`.

<details><summary>Correction — tâche 3</summary>

Dans `/tp/inventory.yml`, ajoutez la variable :

```yaml
    node2:
      ansible_host: 192.168.56.22
      lb_weight: 200          # ← node2 reçoit deux fois plus de trafic
```

```bash
ansible-playbook /tp/playbooks/22-lb.yml
grep "server node" /tp/haproxy.cfg
```

Sortie attendue :

```
server node1 192.168.56.21:80 check weight 100
server node2 192.168.56.22:80 check weight 200
```

> 🔑 **C'est le cas d'usage emblématique du templating** : la configuration du
> load balancer se met à jour quand on ajoute ou retire un serveur de
> l'inventaire. Aucune édition manuelle, aucun oubli possible.

</details>

---

### Exercice F1 — Panorama des filtres Jinja2

| | |
|:---|:---|
| **Fichiers créés** | `/tp/playbooks/23-filtres.yml` |
| **Modules** | `debug` |
| **Notions** | `default` · `int`/`bool` · `join` · `map` · `selectattr` · `rejectattr` · `to_nice_json` · `b64encode` · générateur vs liste |
| **Durée** | ~10 min |

#### Tâche 1 — Filtres de base : valeur par défaut, conversions, chaînes.

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/playbooks/23-filtres.yml
---
- name: Panorama des filtres Jinja2
  hosts: localhost
  connection: local
  gather_facts: no

  vars:
    chaine: "  Ansible Est Puissant  "
    liste_nombres: [4, 8, 15, 16, 23, 42]

  tasks:
    - name: "Filtre 'default' — le plus utilisé"
      ansible.builtin.debug:
        msg:
          - "Port inexistant          : {{ port_indefini | default(8080) }}"
          - "Chaîne vide avec true    : {{ '' | default('non définie', true) }}"
          - "Variable obligatoire     : {{ db_pass | default('MANQUANT') }}"

    - name: Conversions de type
      ansible.builtin.debug:
        msg:
          - "int    : {{ '42' | int }}"
          - "float  : {{ '3.14' | float }}"
          - "bool   : {{ 'true' | bool }}"
          - "string : {{ 42 | string }}"

    - name: Manipulation de chaînes
      ansible.builtin.debug:
        msg:
          - "trim      : '{{ chaine | trim }}'"
          - "lower     : {{ chaine | trim | lower }}"
          - "upper     : {{ chaine | trim | upper }}"
          - "replace   : {{ chaine | trim | replace(' ', '-') }}"
          - "regex     : {{ chaine | trim | regex_replace('\\s+', '_') }}"
          - "split     : {{ chaine | trim | split(' ') }}"
```

```bash
ansible-playbook /tp/playbooks/23-filtres.yml
```

</details>

---

#### Tâche 2 — Filtres de liste : `join`, `sort`, `unique`, `max`, `sum`.

Ajoutez un bloc de tâches dans le même playbook pour les opérations sur listes.

<details><summary>Correction — tâche 2</summary>

Ajoutez dans `tasks:` :

```yaml
    - name: Opérations sur listes
      ansible.builtin.debug:
        msg:
          - "join      : {{ liste_nombres | join(', ') }}"
          - "max/min   : {{ liste_nombres | max }} / {{ liste_nombres | min }}"
          - "sum       : {{ liste_nombres | sum }}"
          - "unique    : {{ [1, 1, 2, 3, 3] | unique | list }}"
          - "sort asc  : {{ liste_nombres | sort | list }}"
          - "sort desc : {{ liste_nombres | sort(reverse=true) | list }}"
          - "random    : {{ liste_nombres | random }}"
```

</details>

---

#### Tâche 3 — `map` et `selectattr` : le piège du générateur.

Testez les filtres `map` et `selectattr` sur une liste de dictionnaires.
Commencez **sans** `| list` à la fin, puis ajoutez-le. Observez la différence.

<details><summary>Correction — tâche 3</summary>

Ajoutez dans `vars:` :

```yaml
    serveurs:
      - { nom: node1, role: web, ram: 1024, actif: true  }
      - { nom: node2, role: web, ram: 2048, actif: true  }
      - { nom: node3, role: db,  ram: 4096, actif: false }
```

Puis dans `tasks:` :

```yaml
    - name: "map sans | list — observer le résultat"
      ansible.builtin.debug:
        msg: "{{ serveurs | map(attribute='nom') }}"

    - name: "map avec | list — résultat lisible"
      ansible.builtin.debug:
        msg: "{{ serveurs | map(attribute='nom') | list }}"

    - name: selectattr et rejectattr
      ansible.builtin.debug:
        msg:
          - "Tous les noms   : {{ serveurs | map(attribute='nom') | list }}"
          - "Serveurs web    : {{ serveurs | selectattr('role', 'equalto', 'web') | map(attribute='nom') | list }}"
          - "Serveurs actifs : {{ serveurs | selectattr('actif') | map(attribute='nom') | list }}"
          - "Non-web         : {{ serveurs | rejectattr('role', 'equalto', 'web') | map(attribute='nom') | list }}"
          - "RAM totale      : {{ serveurs | map(attribute='ram') | sum }} Mo"
```

Sans `| list`, Ansible affiche un objet Python opaque du type
`<generator object do_map at 0x...>`. Cela n'est jamais ce qu'on veut.

> 💡 `map`, `selectattr`, `rejectattr` sont **paresseux** : ils renvoient un
> générateur. Terminez **toujours** par `| list` pour matérialiser le résultat.

</details>

---

#### Tâche 4 — Formats et sécurité : `to_nice_json`, `hash`, `b64encode`.

<details><summary>Correction — tâche 4</summary>

Ajoutez dans `tasks:` :

```yaml
    - name: Formats et sécurité
      ansible.builtin.debug:
        msg:
          - "JSON lisible  : {{ serveurs | to_nice_json }}"
          - "YAML lisible  : {{ serveurs | to_nice_yaml }}"
          - "hash SHA256   : {{ 'mon-secret' | hash('sha256') }}"
          - "base64 encode : {{ 'texte' | b64encode }}"
          - "base64 decode : {{ 'dGV4dGU=' | b64decode }}"
          - "ternary       : {{ true | ternary('activé', 'désactivé') }}"
          - "combine       : {{ {'a': 1} | combine({'b': 2}) }}"
```

**Récapitulatif des filtres clés :**

| Filtre | Usage |
|:---|:---|
| `default(x)` | Valeur de repli — **le plus utilisé** |
| `default(x, true)` | Remplace aussi les valeurs vides / `false` |
| `mandatory` | Échoue explicitement si indéfinie |
| `int` / `float` / `bool` / `string` | Conversion de type |
| `join(', ')` | Liste → chaîne |
| `map(attribute='k')` | Extraire un champ de chaque élément (+ `\| list`) |
| `selectattr` / `rejectattr` | Filtrer une liste de dicts (+ `\| list`) |
| `to_nice_json` / `to_nice_yaml` | Sérialisation lisible |
| `regex_replace(p, r)` | Substitution par expression régulière |
| `hash('sha256')` | Empreinte |
| `b64encode` / `b64decode` | Encodage base64 |
| `combine(dict2)` | Fusionner deux dictionnaires |
| `ternary(a, b)` | `condition \| ternary('oui', 'non')` |

</details>

---

## Partie 3 — Facts personnalisés

### Exercice FA1 — `set_fact` et facts persistants

| | |
|:---|:---|
| **Fichiers créés** | `/tp/playbooks/24-facts.yml` · `/etc/ansible/facts.d/parc.fact` · `/etc/ansible/facts.d/systeme.fact` |
| **Modules** | `set_fact` · `file` · `copy` · `setup` · `debug` |
| **Notions** | `set_fact` · `ansible_local` · facts INI · facts script exécutable · persistance |
| **Durée** | ~10 min |

#### Tâche 1 — Créer des facts calculés avec `set_fact`.

`set_fact` calcule et nomme une variable à partir de facts ou de variables
existants, et la rend accessible pour le reste du play.

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/playbooks/24-facts.yml
---
- name: Facts personnalisés
  hosts: all
  become: yes

  tasks:
    - name: Calculer des informations métier
      ansible.builtin.set_fact:
        role_metier: "{{ 'frontend' if 'web' in group_names else 'backend' }}"
        capacite_workers: "{{ (ansible_memtotal_mb / 128) | int }}"
        est_petite_machine: "{{ ansible_memtotal_mb < 2048 }}"

    - ansible.builtin.debug:
        msg: >-
          {{ inventory_hostname }} → {{ role_metier }},
          {{ capacite_workers }} workers max,
          petite machine : {{ est_petite_machine }}
```

```bash
ansible-playbook /tp/playbooks/24-facts.yml
```

> ⚠️ Les facts créés par `set_fact` durent **le temps du play**. À la prochaine
> exécution, ils sont recalculés depuis zéro. Pour persister entre deux
> exécutions, utilisez les facts locaux (`facts.d`).

</details>

---

#### Tâche 2 — Créer un fact persistant au format INI.

Les facts locaux sont des fichiers déposés dans `/etc/ansible/facts.d/` sur la
**cible**. Ils sont lus automatiquement à chaque `gather_facts` et exposés
dans `ansible_local`.

<details><summary>Correction — tâche 2</summary>

Ajoutez dans `tasks:` :

```yaml
    - name: Créer le répertoire des facts locaux
      ansible.builtin.file:
        path: /etc/ansible/facts.d
        state: directory
        mode: "0755"

    - name: Déposer un fact statique (format INI)
      ansible.builtin.copy:
        dest: /etc/ansible/facts.d/parc.fact
        mode: "0644"
        content: |
          [identite]
          proprietaire=equipe-infra
          criticite={{ 'haute' if 'db' in group_names else 'normale' }}
          contrat_support=24x7

          [application]
          nom=monapp
          environnement={{ env | default('production') }}
```

> 💡 Les fichiers `.fact` au format INI sont traités par `setup` comme des
> variables Jinja2 **au moment du dépôt**. Les valeurs calculées (comme
> `criticite`) sont résolues une seule fois lors de la création du fichier.

</details>

---

#### Tâche 3 — Créer un fact dynamique : un script exécutable renvoyant du JSON.

Un fact dynamique est un fichier exécutable (bash, Python…) que `setup` invoque
sur la cible. Il doit émettre du JSON sur `stdout`. L'intérêt : les valeurs sont
recalculées à chaque collecte (uptime, charge…).

<details><summary>Correction — tâche 3</summary>

Ajoutez dans `tasks:` :

```yaml
    - name: Déposer un fact dynamique (script exécutable → JSON)
      ansible.builtin.copy:
        dest: /etc/ansible/facts.d/systeme.fact
        mode: "0755"
        content: |
          #!/bin/bash
          cat <<JSON
          {
            "uptime_secondes": $(cut -d. -f1 /proc/uptime),
            "nb_paquets": $(dpkg -l 2>/dev/null | grep -c '^ii'),
            "kernel": "$(uname -r)",
            "charge_1min": "$(cut -d' ' -f1 /proc/loadavg)"
          }
          JSON

    - name: Recollecter les facts pour voir ansible_local
      ansible.builtin.setup:
        filter: ansible_local

    - name: Afficher les facts personnalisés
      ansible.builtin.debug:
        var: ansible_local
```

```bash
ansible-playbook /tp/playbooks/24-facts.yml
```

Sortie attendue dans `ansible_local` :

```json
{
  "parc": {
    "identite": { "proprietaire": "equipe-infra", "criticite": "normale" },
    "application": { "nom": "monapp", "environnement": "production" }
  },
  "systeme": {
    "uptime_secondes": "4821",
    "nb_paquets": "612",
    "kernel": "5.15.0-91-generic",
    "charge_1min": "0.02"
  }
}
```

</details>

---

#### Tâche 4 — Vérifier la persistance : relancer `setup` sans les tâches de création.

Lancez `setup` directement depuis la ligne de commande, **sans** re-exécuter le
playbook. `ansible_local` doit être alimenté automatiquement depuis les fichiers
déposés en tâche 2 et 3.

<details><summary>Correction — tâche 4</summary>

```bash
ansible all -m setup -a "filter=ansible_local"
```

Les facts sont là, sans aucun playbook :

```yaml
node1 | SUCCESS => {
    "ansible_local": {
        "parc": { ... },
        "systeme": { "uptime_secondes": "5042", ... }
    }
}
```

Et `charge_1min` a changé (le script est réexécuté à chaque collecte).

**Bilan `set_fact` vs facts persistants :**

| | `set_fact` | `/etc/ansible/facts.d/*.fact` |
|:---|:---|:---|
| Portée | Play en cours seulement | **Permanent** sur la machine |
| Stockage | Mémoire du controller | Fichier sur la **cible** |
| Collecte | Explicite (`set_fact`) | **Automatique** à chaque `gather_facts` |
| Usage | Calcul intermédiaire | Métadonnées durables (propriétaire, criticité…) |

Usage dans un template ou un playbook :

```yaml
- ansible.builtin.debug:
    msg: "Criticité : {{ ansible_local.parc.identite.criticite }}"
  when: ansible_local.parc is defined
```

</details>

---

### Exercice LK1 — Plugins `lookup`

| | |
|:---|:---|
| **Fichiers créés** | `/tp/playbooks/25-lookups.yml` · `/tp/version.txt` |
| **Modules** | `debug` · `set_fact` · `slurp` |
| **Notions** | `lookup()` · `query()` · `file` · `env` · `pipe` · `password` · `fileglob` · exécution sur controller |
| **Durée** | ~10 min |

#### Tâche 1 — Préparer les fichiers sources et utiliser `file`, `env`, `pipe`.

<details><summary>Correction — tâche 1</summary>

```bash
echo "v3.4.1" > /tp/version.txt
```

```yaml
# /tp/playbooks/25-lookups.yml
---
- name: Plugins lookup
  hosts: localhost
  connection: local
  gather_facts: no

  vars:
    # Les lookups s'exécutent sur le CONTROLLER
    version_app: "{{ lookup('file', '/tp/version.txt') | trim }}"
    home_user:   "{{ lookup('env', 'HOME') }}"
    date_build:  "{{ lookup('pipe', 'date +%Y%m%d-%H%M') }}"

  tasks:
    - ansible.builtin.debug:
        msg:
          - "Contenu d'un fichier     : {{ version_app }}"
          - "Variable d'environnement : {{ home_user }}"
          - "Sortie d'une commande    : {{ date_build }}"
```

```bash
ansible-playbook /tp/playbooks/25-lookups.yml
```

</details>

---

#### Tâche 2 — `password` : un lookup idempotent qui mémorise ce qu'il génère.

Le lookup `password` génère un mot de passe aléatoire lors du premier appel,
le stocke dans un fichier, et le rend identique à chaque appel suivant.

<details><summary>Correction — tâche 2</summary>

Ajoutez dans `tasks:` :

```yaml
    - name: Générer (ou relire) un mot de passe
      ansible.builtin.set_fact:
        db_password: "{{ lookup('password', '/tp/.secrets/db_pass length=24 chars=ascii_letters,digits') }}"

    - ansible.builtin.debug:
        msg: "Premier appel  : {{ db_password }}"

    - ansible.builtin.debug:
        msg: "Deuxième appel : {{ lookup('password', '/tp/.secrets/db_pass length=24 chars=ascii_letters,digits') }}"
```

```bash
ansible-playbook /tp/playbooks/25-lookups.yml
# Relancez une deuxième fois → le mot de passe est identique
```

Le fichier `/tp/.secrets/db_pass` contient le mot de passe en clair.
Pour les secrets en production, utilisez **Ansible Vault** (Lab 08).

</details>

---

#### Tâche 3 — `fileglob` avec `query()` : parcourir plusieurs fichiers.

`query()` est l'alias de `lookup(..., wantlist=True)` : il renvoie toujours
une liste, ce qui est nécessaire avec `loop`.

<details><summary>Correction — tâche 3</summary>

Ajoutez dans `tasks:` :

```yaml
    - name: Lister les templates disponibles
      ansible.builtin.debug:
        msg: "Template : {{ item | basename }}"
      loop: "{{ query('fileglob', '/tp/templates/*.j2') | sort }}"
```

**`lookup()` vs `query()` :**

| | `lookup()` | `query()` |
|:---|:---|:---|
| Résultat pour un seul fichier | Chaîne | Liste à un élément |
| Résultat pour plusieurs | Chaîne concaténée | **Liste** |
| Avec `loop:` | Potentiellement cassé | ✅ Toujours correct |

</details>

---

#### Tâche 4 — Piège : `lookup('file', ...)` lit sur le controller, pas sur la cible.

Utilisez `lookup('file', '/etc/hostname')` dans un play ciblant `node1`.
Observez quel nom de machine est retourné. Puis corrigez avec `slurp`.

<details><summary>Correction — tâche 4</summary>

```yaml
# /tp/playbooks/25b-lookup-piege.yml
---
- name: Démonstration du piège lookup
  hosts: node1
  gather_facts: no

  tasks:
    - name: "❌ Lecture via lookup — lit le CONTROLLER"
      ansible.builtin.debug:
        msg: "lookup : {{ lookup('file', '/etc/hostname') }}"

    - name: "✅ Lecture via slurp — lit la CIBLE"
      ansible.builtin.slurp:
        src: /etc/hostname
      register: fichier_hostname

    - ansible.builtin.debug:
        msg: "slurp  : {{ fichier_hostname.content | b64decode | trim }}"
```

```bash
ansible-playbook /tp/playbooks/25b-lookup-piege.yml
```

Sortie attendue :

```
"lookup : controller.anslab.com"    ← hostname du CONTROLLER
"slurp  : node1.wizetraining.local" ← hostname de NODE1
```

**La règle :** un `lookup` s'exécute **toujours sur le nœud de contrôle**,
même si le play cible des nœuds distants.

| Besoin | Solution |
|:---|:---|
| Lire un fichier du **controller** | `lookup('file', '/chemin')` |
| Lire un fichier de la **cible** | Module `slurp` + `b64decode` |
| Lire un fichier de la cible (texte) | `command: cat /chemin` + `register` |

</details>

---

## Partie 4 — Le tableau de bord du parc

### Exercice D1 — Page HTML récapitulant l'état complet du parc

| | |
|:---|:---|
| **Fichiers créés** | `/tp/templates/dashboard.html.j2` · `/tp/playbooks/26-dashboard.yml` |
| **Modules** | `template` · `shell` · `set_fact` · `debug` |
| **Notions** | `hostvars` · `ansible_mounts` · `selectattr` · `loop.last` · CSS conditionnel |
| **Durée** | ~10 min |

#### Tâche 1 — Écrire `dashboard.html.j2` : tableau de toutes les machines.

Le template génère une page HTML avec une ligne par machine : IP, OS, noyau,
vCPU, RAM (rouge si < 1 Go), disque (rouge si > 70 %), uptime.

<details><summary>Correction — tâche 1</summary>

```jinja
{# /tp/templates/dashboard.html.j2 #}
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <title>Tableau de bord du parc</title>
  <style>
    body   { font-family: system-ui, sans-serif; margin: 2rem; background: #f6f8fa; color: #24292f; }
    h1     { border-bottom: 3px solid #776AF4; padding-bottom: .5rem; }
    table  { border-collapse: collapse; width: 100%; background: #fff; box-shadow: 0 1px 3px rgba(0,0,0,.1); }
    th     { background: #776AF4; color: #fff; padding: .7rem; text-align: left; font-size: .85rem; }
    td     { padding: .6rem .7rem; border-bottom: 1px solid #e1e4e8; font-size: .9rem; }
    tr:hover td { background: #f0f3ff; }
    .badge { padding: .15rem .5rem; border-radius: 10px; font-size: .75rem; font-weight: 600; }
    .web   { background: #dbeafe; color: #1e40af; }
    .db    { background: #fce7f3; color: #9d174d; }
    .ok    { color: #16a34a; font-weight: 600; }
    .warn  { color: #d97706; font-weight: 600; }
    .meta  { color: #57606a; font-size: .8rem; margin-top: 1.5rem; }
  </style>
</head>
<body>

<h1>Tableau de bord — {{ groups['all'] | length }} machines</h1>

<table>
  <tr>
    <th>Machine</th><th>Groupes</th><th>IP</th><th>OS</th>
    <th>Noyau</th><th>vCPU</th><th>RAM</th><th>Disque /</th><th>Uptime</th>
  </tr>
{% for host in groups['all'] | sort %}
{%   set hv = hostvars[host] %}
{%   if hv.ansible_default_ipv4 is defined %}
  <tr>
    <td><strong>{{ host }}</strong></td>
    <td>
{%     for g in hv.group_names | sort %}
      <span class="badge {{ g }}">{{ g }}</span>
{%     endfor %}
    </td>
    <td>{{ hv.ansible_default_ipv4.address }}</td>
    <td>{{ hv.ansible_distribution }} {{ hv.ansible_distribution_version }}</td>
    <td>{{ hv.ansible_kernel }}</td>
    <td>{{ hv.ansible_processor_vcpus }}</td>
    <td class="{{ 'warn' if hv.ansible_memtotal_mb < 1024 else 'ok' }}">
      {{ hv.ansible_memtotal_mb }} Mo
    </td>
{%     set racine = hv.ansible_mounts | selectattr('mount', 'equalto', '/') | first %}
{%     set pct    = (100 - (racine.size_available / racine.size_total * 100)) | round | int %}
    <td class="{{ 'warn' if pct > 70 else 'ok' }}">{{ pct }} %</td>
    <td>{{ (hv.ansible_uptime_seconds / 86400) | round(1) }} j</td>
  </tr>
{%   endif %}
{% endfor %}
</table>

<p class="meta">
  Généré par Ansible le {{ ansible_date_time.iso8601 }}<br>
  Groupes de l'inventaire :
  {% for g, m in groups.items() if g not in ['all', 'ungrouped'] %}
    <strong>{{ g }}</strong> ({{ m | length }}){{ ", " if not loop.last }}
  {% endfor %}
</p>

</body>
</html>
```

</details>

---

#### Tâche 2 — Écrire le playbook `26-dashboard.yml` en deux plays.

Play 1 : collecter les facts sur toutes les machines **et** compter les
services actifs. Play 2 : générer le HTML sur le controller.

<details><summary>Correction — tâche 2</summary>

```yaml
# /tp/playbooks/26-dashboard.yml
---
- name: Collecte des informations du parc
  hosts: all
  gather_facts: yes

  tasks:
    - name: Compter les services systemd actifs
      ansible.builtin.shell: systemctl list-units --type=service --state=running --no-legend | wc -l
      register: nb_services
      changed_when: false

    - name: Mémoriser le décompte comme fact
      ansible.builtin.set_fact:
        services_actifs: "{{ nb_services.stdout | trim }}"

- name: Générer le tableau de bord
  hosts: localhost
  connection: local
  gather_facts: yes

  tasks:
    - name: Rendre la page HTML
      ansible.builtin.template:
        src: ../templates/dashboard.html.j2
        dest: /tp/dashboard.html
        mode: "0644"

    - ansible.builtin.debug:
        msg: "Tableau de bord disponible : ouvrez 0-setup/tp/dashboard.html dans votre navigateur"
```

```bash
ansible-playbook /tp/playbooks/26-dashboard.yml
```

</details>

---

#### Tâche 3 — Ouvrir le tableau de bord et analyser les techniques Jinja2 avancées.

Le répertoire `0-setup/tp/` est synchronisé avec votre machine hôte. Ouvrez
`dashboard.html` dans votre navigateur, puis repérez dans le template les
quatre constructions Jinja2 avancées utilisées.

<details><summary>Correction — tâche 3</summary>

**Sur la machine hôte (hors VM) :**

```bash
open 0-setup/tp/dashboard.html      # macOS
xdg-open 0-setup/tp/dashboard.html  # Linux
start 0-setup/tp/dashboard.html     # Windows
```

**Quatre techniques Jinja2 avancées dans ce template :**

| Technique | Ligne concernée | Rôle |
|:---|:---|:---|
| `{% set hv = hostvars[host] %}` | Début du `{% for %}` | Alias — évite de répéter `hostvars[host]` partout |
| `selectattr('mount','equalto','/') \| first` | Disque `/` | Extraire le seul point de montage racine d'une liste |
| `\| ternary('warn','ok')` (implicite) | Colonnes RAM et Disque | Classe CSS choisie selon un seuil numérique |
| `{{ ", " if not loop.last }}` | Liste des groupes | Supprimer la virgule après le dernier élément d'une boucle |

</details>

---

#### Tâche 4 — Enrichir le tableau de bord avec une colonne Python.

Ajoutez une deuxième table affichant `Python`, `Services actifs` pour chaque
machine, en réutilisant les facts collectés dans le play 1.

<details><summary>Correction — tâche 4</summary>

Ajoutez dans `dashboard.html.j2`, après la première table et avant `<p class="meta">` :

```jinja
<h2>Paquets clés installés</h2>
<table>
  <tr><th>Machine</th><th>Python</th><th>Services actifs</th></tr>
{% for host in groups['all'] | sort %}
{%   set hv = hostvars[host] %}
{%   if hv.ansible_python_version is defined %}
  <tr>
    <td><strong>{{ host }}</strong></td>
    <td>{{ hv.ansible_python_version }}</td>
    <td>{{ hv.services_actifs | default('n/a') }}</td>
  </tr>
{%   endif %}
{% endfor %}
</table>
```

```bash
ansible-playbook /tp/playbooks/26-dashboard.yml
```

`services_actifs` a été créé par `set_fact` dans le play 1 — `hostvars`
le transmet automatiquement au play 2.

</details>

---

### Exercice PR1 — Invite interactive avec `vars_prompt`

| | |
|:---|:---|
| **Fichiers créés** | `/tp/playbooks/27-prompt.yml` |
| **Modules** | `fail` · `debug` |
| **Notions** | `vars_prompt` · `private: yes` · `confirm: yes` · blocage CI · contournement `-e` |
| **Durée** | ~5 min |

#### Tâche 1 — Écrire le playbook avec une invite à trois champs.

Le playbook doit demander : l'environnement cible (texte visible, défaut `dev`),
une confirmation (visible), et un mot de passe (masqué, avec double saisie).
Il doit refuser un déploiement non confirmé.

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/playbooks/27-prompt.yml
---
- name: Déploiement avec invite interactive
  hosts: web
  become: yes

  vars_prompt:
    - name: environnement
      prompt: "Environnement cible (dev/staging/production)"
      private: no
      default: dev

    - name: confirmation
      prompt: "Confirmez-vous le déploiement ? (oui/non)"
      private: no
      default: non

    - name: db_password
      prompt: "Mot de passe de la base"
      private: yes
      confirm: yes

  tasks:
    - name: Interrompre si non confirmé
      ansible.builtin.fail:
        msg: "Déploiement annulé par l'opérateur."
      when: confirmation | lower not in ['oui', 'o', 'yes', 'y']

    - name: Refuser un déploiement direct en production hors CI
      ansible.builtin.fail:
        msg: "Le déploiement en production doit passer par la CI."
      when:
        - environnement == "production"
        - lookup('env', 'CI') | default('', true) == ''

    - ansible.builtin.debug:
        msg: "Déploiement en {{ environnement }} sur {{ inventory_hostname }}"
```

```bash
ansible-playbook /tp/playbooks/27-prompt.yml
```

</details>

---

#### Tâche 2 — Piège CI : démontrer que `vars_prompt` bloque l'automatisation et comment le contourner.

Essayez de lancer le playbook en redirigeant `stdin` depuis `/dev/null` (comme
le ferait un pipeline CI). Que se passe-t-il ? Quelle est la solution ?

<details><summary>Correction — tâche 2</summary>

```bash
# Simulation d'un environnement CI (stdin fermé)
ansible-playbook /tp/playbooks/27-prompt.yml < /dev/null
```

Le playbook se bloque ou échoue immédiatement : il attend une saisie qui ne
peut pas arriver.

**Solution : court-circuiter les invites avec `-e`.**

```bash
ansible-playbook /tp/playbooks/27-prompt.yml \
  -e "environnement=dev confirmation=oui db_password=MonMotDePasse42"
```

Les variables passées avec `-e` ont la priorité maximale (niveau 22) et
court-circuitent entièrement `vars_prompt`.

**À retenir :**

| Situation | Outil |
|:---|:---|
| Opération manuelle sensible | `vars_prompt` |
| Automatisation CI/CD | Variables d'environnement + Vault |
| Secret persistant | **Ansible Vault** (Lab 08) |

> ⚠️ `vars_prompt` avec `private: yes` masque la saisie à l'écran, mais la
> valeur circule en clair sur SSH et dans les logs Ansible si `no_log: false`.
> Pour les vrais secrets en production, Vault est la seule réponse fiable.

</details>

---

## À retenir

| Point clé | Détail |
|:---|:---|
| **`template` vs `copy`** | Dès qu'une `{{ variable }}` apparaît dans un fichier source → `template`. |
| **`validate:`** | Valide le fichier généré **avant** de l'écrire. Empêche de casser un service. |
| **`{{ }}` vs `{% %}`** | Expression (affiche) vs instruction (logique, n'affiche rien). |
| **`{# #}`** | Commentaire de template, absent du fichier final. |
| **`\| default(x)`** | Le filtre le plus utile. Rend un template tolérant aux variables absentes. |
| **`\| list`** | Obligatoire après `map`, `selectattr`, `rejectattr` — ils renvoient un générateur. |
| **`hostvars` + `groups`** | Générer la config d'une machine à partir des données des **autres**. |
| **`gather_facts` multi-play** | Pour utiliser `hostvars[h]` dans un play, il faut que `h` ait été dans un play précédent avec `gather_facts: yes`. |
| **`set_fact`** | Fact calculé, durée de vie = le play en cours. |
| **`facts.d`** | Facts persistants sur la cible, exposés automatiquement dans `ansible_local`. |
| **`lookup`** | S'exécute **sur le controller**. Pour lire sur la cible → `slurp`. |
| **`vars_prompt`** | Bloque l'automatisation. Contournable avec `-e`. À éviter en CI. |

### Le piège à retenir

```yaml
# ❌ Lit /etc/hostname du CONTROLLER, pas de la cible
- debug:
    msg: "{{ lookup('file', '/etc/hostname') }}"

# ✅ Lit /etc/hostname de la CIBLE
- ansible.builtin.slurp:
    src: /etc/hostname
  register: fichier
- debug:
    msg: "{{ fichier.content | b64decode | trim }}"
```

---

⬅️ **Lab précédent :** [Lab 05 — Contrôle du flux et gestion des erreurs](<../lab 05 - Contrôle du flux et gestion des erreurs/instructions.md>)
➡️ **Lab suivant :** [Lab 07 — Rôles et Ansible Galaxy](<../lab 07 - Rôles et Ansible Galaxy/instructions.md>)
