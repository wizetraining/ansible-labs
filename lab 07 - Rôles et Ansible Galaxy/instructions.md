# Lab 07 — Rôles et Ansible Galaxy

> ⭐ Niveau : ⭐⭐⭐ | ⏱ Durée estimée : 75 min | Module : **M7 — Rôles, Galaxy & collections**

## Objectifs pédagogiques

* Comprendre pourquoi un playbook monolithique ne passe pas à l'échelle
* Créer un rôle avec `ansible-galaxy role init` et connaître le rôle de chaque répertoire
* Distinguer `defaults/` et `vars/` — et savoir lequel utiliser
* Convertir le playbook LAMP du Lab 04 en rôles réutilisables
* Consommer un rôle de la communauté depuis Ansible Galaxy
* Gérer les dépendances avec `requirements.yml` et les collections

## Notions abordées

* Structure standard d'un rôle : `tasks/`, `handlers/`, `templates/`, `files/`, `vars/`, `defaults/`, `meta/`
* Chargement automatique de `main.yml` dans chaque répertoire
* `defaults/` (priorité faible) vs `vars/` (priorité forte)
* Trois façons d'appeler un rôle : `roles:`, `import_role`, `include_role`
* Dépendances entre rôles (`meta/main.yml`)
* `ansible-galaxy` : `role init`, `install`, `collection install`
* `requirements.yml` : rôles Galaxy, dépôts Git, collections
* Collections : namespace, `collections:` dans un playbook

## Documentation de référence

* [Roles](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_reuse_roles.html)
* [Ansible Galaxy](https://docs.ansible.com/ansible/latest/galaxy/user_guide.html)
* [Collections](https://docs.ansible.com/ansible/latest/collections_guide/index.html)
* [galaxy.ansible.com](https://galaxy.ansible.com)

## Contexte

Votre playbook LAMP fonctionne, mais il fait 200 lignes dans un seul fichier. L'équipe voisine
veut réutiliser « juste la partie Apache » — impossible sans copier-coller. Et quand deux
personnes modifient le fichier en même temps, les conflits Git sont ingérables.

La réponse d'Ansible : les **rôles**. Vous allez découper la stack en composants autonomes,
versionnables et partageables.

---

## Partie 1 — Remise à zéro et création du premier rôle

### 1. Repartez d'un parc propre. Écrivez un playbook qui désinstalle les paquets des labs précédents.

<details><summary>Correction</summary>

```yaml
# /tp/playbooks/reset.yml
---
- name: Remise à zéro du parc
  hosts: all
  become: yes

  vars:
    paquets_a_supprimer:
      - apache2
      - nginx
      - mariadb-server
      - php
      - libapache2-mod-php

  tasks:
    - name: Arrêter les services
      ansible.builtin.service:
        name: "{{ item }}"
        state: stopped
      loop: [apache2, nginx, mariadb]
      failed_when: false

    - name: Désinstaller les paquets
      ansible.builtin.apt:
        name: "{{ paquets_a_supprimer }}"
        state: absent
        purge: yes
        autoremove: yes

    - name: Supprimer les répertoires applicatifs
      ansible.builtin.file:
        path: "{{ item }}"
        state: absent
      loop:
        - /var/www/monapp
        - /etc/apache2
        - /etc/nginx
```

```bash
cd /tp
ansible-playbook playbooks/reset.yml
ansible all -m command -a "systemctl is-active apache2" -o    # tout doit être inactive
```

</details>

---

### 2. Réorganisez l'inventaire en 3 groupes : `web` (node1), `proxy` (node2), `db` (node3).

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
          hosts:
            node1:
        proxy:
          hosts:
            node2:
        db:
          hosts:
            node3:
```

```bash
ansible-inventory --graph
```

```
@all:
  |--@prod:
  |  |--@db:
  |  |  |--node3
  |  |--@proxy:
  |  |  |--node2
  |  |--@web:
  |  |  |--node1
```

</details>

---

### 3. Créez le squelette du rôle `apache` avec `ansible-galaxy`. Décrivez le rôle de chaque répertoire.

<details><summary>Correction</summary>

```bash
mkdir -p /tp/roles && cd /tp/roles
ansible-galaxy role init apache
tree apache
```

```
apache/
├── defaults/main.yml      ← variables par défaut  (priorité FAIBLE)
├── files/                 ← fichiers copiés tels quels (module copy)
├── handlers/main.yml      ← handlers du rôle
├── meta/main.yml          ← métadonnées + dépendances
├── tasks/main.yml         ← point d'entrée des tâches ⭐
├── templates/             ← templates Jinja2 (.j2)
├── tests/                 ← playbook de test
└── vars/main.yml          ← variables internes (priorité FORTE)
```

| Répertoire | Contenu | Chargement |
|:---|:---|:---|
| `tasks/main.yml` | **Point d'entrée** — les tâches du rôle | Automatique |
| `handlers/main.yml` | Handlers déclenchés par `notify` | Automatique |
| `defaults/main.yml` | Valeurs par défaut **surchargeables** | Automatique |
| `vars/main.yml` | Variables internes **peu surchargeables** | Automatique |
| `templates/` | Fichiers `.j2` — chemin relatif automatique | À la demande |
| `files/` | Fichiers statiques — chemin relatif automatique | À la demande |
| `meta/main.yml` | Auteur, licence, plateformes, **dépendances** | Automatique |

> 🔑 **Le mécanisme central :** Ansible charge **automatiquement** le fichier `main.yml` de
> chaque répertoire. Vous n'écrivez aucun `include`. Et dans `tasks/main.yml`, un
> `template: src: vhost.conf.j2` cherche **tout seul** dans `templates/` du rôle — pas de
> chemin relatif à gérer.

</details>

---

## Partie 2 — Écrire le rôle `apache`

### Exercice R1 — Remplir les fichiers du rôle `apache`

| | |
|:---|:---|
| **Fichiers créés** | `roles/apache/defaults/main.yml` · `vars/main.yml` · `tasks/main.yml` · `handlers/main.yml` · `meta/main.yml` · `templates/*.j2` |
| **Modules** | `apt` · `file` · `template` · `lineinfile` · `command` · `service` |
| **Notions** | Structure de rôle · `defaults/` vs `vars/` · chemins relatifs automatiques · `tags:` |
| **Durée** | ~15 min |

#### Tâche 1 — Écrire `defaults/main.yml` : l'API publique du rôle.

`defaults/main.yml` contient toutes les variables que l'**utilisateur** du rôle
peut surcharger. C'est l'API du rôle. Elle doit être riche et commentée.

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/roles/apache/defaults/main.yml
---
# Variables SURCHARGEABLES — c'est l'API publique du rôle
apache_port: 80
apache_app_name: monapp
apache_document_root: /var/www/monapp
apache_server_admin: ops@wizetraining.com
apache_max_workers: 0            # 0 = calcul automatique selon la RAM

apache_modules:
  - rewrite
  - headers

apache_php_enabled: true
apache_php_packages:
  - php
  - php-mysql
  - libapache2-mod-php
```

</details>

---

#### Tâche 2 — Écrire `vars/main.yml` : les variables internes du rôle.

`vars/main.yml` contient ce que le rôle utilise en interne et qui ne devrait
**pas** être modifié par l'utilisateur. Si ces valeurs changeaient, le rôle
cesserait de fonctionner.

<details><summary>Correction — tâche 2</summary>

```yaml
# /tp/roles/apache/vars/main.yml
---
# Variables INTERNES — ne devraient pas être surchargées
apache_service_name: apache2
apache_package_name: apache2
apache_config_dir: /etc/apache2
apache_user: www-data
```

**Règle de répartition :**

| Variable | Où la mettre | Pourquoi |
|:---|:---|:---|
| `apache_port` | `defaults/` | L'utilisateur peut légitimement changer le port |
| `apache_php_enabled` | `defaults/` | Choix de déploiement de l'appelant |
| `apache_service_name` | `vars/` | Toujours `apache2` sur Ubuntu — si ça change, le rôle est cassé |
| `apache_config_dir` | `vars/` | Chemin système imposé par la distribution |

</details>

---

#### Tâche 3 — Écrire `tasks/main.yml`.

<details><summary>Correction — tâche 3</summary>

```yaml
# /tp/roles/apache/tasks/main.yml
---
- name: Installer Apache
  ansible.builtin.apt:
    name: "{{ apache_package_name }}"
    state: present
    update_cache: yes
    cache_valid_time: 3600
  tags: [apache, install]

- name: Installer PHP et ses modules
  ansible.builtin.apt:
    name: "{{ apache_php_packages }}"
    state: present
  when: apache_php_enabled | bool
  notify: Redemarrer Apache
  tags: [apache, install, php]

- name: Activer les modules Apache requis
  ansible.builtin.command: "a2enmod {{ item }}"
  args:
    creates: "{{ apache_config_dir }}/mods-enabled/{{ item }}.load"
  loop: "{{ apache_modules }}"
  notify: Redemarrer Apache
  tags: [apache, config]

- name: Créer la racine documentaire
  ansible.builtin.file:
    path: "{{ apache_document_root }}"
    state: directory
    owner: "{{ apache_user }}"
    group: "{{ apache_user }}"
    mode: "0755"
  tags: [apache, config]

- name: Générer le VirtualHost
  ansible.builtin.template:
    src: vhost.conf.j2          # ← cherché dans templates/ du rôle automatiquement
    dest: "{{ apache_config_dir }}/sites-available/{{ apache_app_name }}.conf"
    mode: "0644"
    validate: 'apache2ctl -f %s -t'
  notify: Recharger Apache
  tags: [apache, config]

- name: Dimensionner le MPM selon le matériel
  ansible.builtin.template:
    src: mpm_prefork.conf.j2
    dest: "{{ apache_config_dir }}/mods-available/mpm_prefork.conf"
    mode: "0644"
  notify: Redemarrer Apache
  tags: [apache, config, tuning]

- name: Configurer le port d'écoute
  ansible.builtin.lineinfile:
    path: "{{ apache_config_dir }}/ports.conf"
    regexp: '^Listen '
    line: "Listen {{ apache_port }}"
  notify: Redemarrer Apache
  tags: [apache, config]

- name: Activer le site applicatif
  ansible.builtin.command: "a2ensite {{ apache_app_name }}.conf"
  args:
    creates: "{{ apache_config_dir }}/sites-enabled/{{ apache_app_name }}.conf"
  notify: Recharger Apache
  tags: [apache, config]

- name: Désactiver le site par défaut
  ansible.builtin.command: a2dissite 000-default.conf
  args:
    removes: "{{ apache_config_dir }}/sites-enabled/000-default.conf"
  notify: Recharger Apache
  tags: [apache, config]

- name: Déployer la page applicative
  ansible.builtin.template:
    src: index.php.j2
    dest: "{{ apache_document_root }}/index.php"
    owner: "{{ apache_user }}"
    mode: "0644"
  tags: [apache, deploy]

- name: Démarrer et activer Apache
  ansible.builtin.service:
    name: "{{ apache_service_name }}"
    state: started
    enabled: yes
  tags: [apache, service]
```

</details>

---

#### Tâche 4 — Écrire `handlers/main.yml` et les trois templates.

<details><summary>Correction — tâche 4</summary>

```yaml
# /tp/roles/apache/handlers/main.yml
---
- name: Redemarrer Apache
  ansible.builtin.service:
    name: "{{ apache_service_name }}"
    state: restarted

- name: Recharger Apache
  ansible.builtin.service:
    name: "{{ apache_service_name }}"
    state: reloaded
```

```jinja
{# /tp/roles/apache/templates/vhost.conf.j2 #}
<VirtualHost *:{{ apache_port }}>
    ServerName {{ ansible_fqdn }}
    ServerAdmin {{ apache_server_admin }}
    DocumentRoot {{ apache_document_root }}
    DirectoryIndex index.php index.html

    <Directory {{ apache_document_root }}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ServerTokens Prod
    ServerSignature Off

    ErrorLog  ${APACHE_LOG_DIR}/{{ apache_app_name }}_error.log
    CustomLog ${APACHE_LOG_DIR}/{{ apache_app_name }}_access.log combined
</VirtualHost>
```

```jinja
{# /tp/roles/apache/templates/mpm_prefork.conf.j2 #}
{% if apache_max_workers | int > 0 %}
{%   set workers = apache_max_workers | int %}
{% else %}
{%   set workers = [((ansible_memtotal_mb - 256) / 25) | int, 8] | max %}
{% endif %}
<IfModule mpm_prefork_module>
    StartServers            {{ [(workers / 4) | int, 2] | max }}
    MinSpareServers         {{ [(workers / 4) | int, 2] | max }}
    MaxSpareServers         {{ [(workers / 2) | int, 4] | max }}
    MaxRequestWorkers       {{ workers }}
    MaxConnectionsPerChild  {{ 10000 if ansible_memtotal_mb > 2048 else 1000 }}
</IfModule>
```

```jinja
{# /tp/roles/apache/templates/index.php.j2 #}
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>{{ apache_app_name }}</title></head>
<body style="font-family:system-ui;margin:3rem">
  <h1>{{ apache_app_name }}</h1>
  <ul>
    <li>Serveur      : <strong>{{ inventory_hostname }}</strong></li>
    <li>Environnement : {{ env | default('dev') }}</li>
    <li>Port          : {{ apache_port }}</li>
    <li>PHP           : <?php echo phpversion(); ?></li>
    <li>Généré le     : {{ ansible_date_time.iso8601 }}</li>
  </ul>
</body></html>
```

> 🔑 **Le chemin relatif automatique** : `src: vhost.conf.j2` dans `tasks/main.yml`
> cherche **automatiquement** dans `templates/` du rôle. Vous n'écrivez jamais
> `src: ../templates/vhost.conf.j2` à l'intérieur d'un rôle.

</details>

---

#### Tâche 5 — Remplir `meta/main.yml`.

<details><summary>Correction — tâche 5</summary>

```yaml
# /tp/roles/apache/meta/main.yml
---
galaxy_info:
  author: Equipe Infra
  description: Installe et configure Apache avec PHP
  license: MIT
  min_ansible_version: "2.12"
  platforms:
    - name: Ubuntu
      versions: [jammy, focal]
  galaxy_tags: [web, apache, php]

dependencies: []    # sera complété à la Partie 5
```

</details>

---

### Exercice R2 — Utiliser le rôle dans un playbook

| | |
|:---|:---|
| **Fichiers créés** | `/tp/playbooks/30-role-apache.yml` · `/tp/ansible.cfg` (ajout `roles_path`) |
| **Modules** | `uri` |
| **Notions** | `roles:` · `roles_path` · surcharge de `defaults/` par l'appelant · idempotence |
| **Durée** | ~5 min |

#### Tâche 1 — Configurer `roles_path` et écrire le playbook.

Sans `roles_path`, Ansible cherche les rôles dans le répertoire courant. Ajoutez
cette configuration dans `ansible.cfg` pour éviter les chemins relatifs.

<details><summary>Correction — tâche 1</summary>

```bash
grep -q roles_path /tp/ansible.cfg || \
  sed -i '/^\[defaults\]/a roles_path = /tp/roles' /tp/ansible.cfg

grep roles_path /tp/ansible.cfg
# → roles_path = /tp/roles
```

```yaml
# /tp/playbooks/30-role-apache.yml
---
- name: Déployer Apache via le rôle
  hosts: web
  become: yes
  roles:
    - apache
```

```bash
ansible-playbook /tp/playbooks/30-role-apache.yml
```

</details>

---

#### Tâche 2 — Vérifier le déploiement et l'idempotence.

<details><summary>Correction — tâche 2</summary>

```bash
# Le site répond
ansible web -m uri -a "url=http://localhost return_content=yes" | grep -o "monapp"

# Deuxième passage → aucun changement
ansible-playbook /tp/playbooks/30-role-apache.yml
# → changed=0 attendu sur les deux nœuds
```

</details>

---

#### Tâche 3 — Surcharger les `defaults/` pour un déploiement sur un port alternatif.

Déployez une seconde instance Apache sur le port 8080, sans PHP, avec un nom
d'application différent. Tout se fait au niveau du playbook, sans toucher au rôle.

<details><summary>Correction — tâche 3</summary>

```yaml
# /tp/playbooks/30b-role-apache-alt.yml
---
- name: Apache sur port alternatif, sans PHP
  hosts: web
  become: yes
  roles:
    - role: apache
      apache_port: 8080
      apache_app_name: monsite
      apache_document_root: /var/www/monsite
      apache_php_enabled: false
      apache_max_workers: 50
```

```bash
ansible-playbook /tp/playbooks/30b-role-apache-alt.yml
ansible web -m uri -a "url=http://localhost:8080 status_code=200,404"
```

> 💡 C'est **la valeur d'un rôle bien écrit** : un même rôle, deux configurations
> totalement différentes, sans dupliquer une seule ligne de code. C'est impossible
> avec un playbook monolithique.

</details>

---

### Exercice R3 — `defaults/` vs `vars/` : démonstration concrète

| | |
|:---|:---|
| **Notions** | Priorité des variables · niveaux 1 vs 18 · surcharge via `-e` |
| **Durée** | ~5 min |

#### Tâche 1 — Surcharger une variable de `defaults/` : succès attendu.

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/playbooks/30c-test-surcharge.yml
---
- name: Test de surcharge des variables de rôle
  hosts: web
  become: yes
  roles:
    - role: apache
      apache_port: 9090           # dans defaults/ → SURCHARGEABLE ✅
```

```bash
ansible-playbook /tp/playbooks/30c-test-surcharge.yml
ansible web -m command -a "grep Listen /etc/apache2/ports.conf"
# → Listen 9090
```

</details>

---

#### Tâche 2 — Tenter de surcharger une variable de `vars/` : ignoré, sauf `-e`.

<details><summary>Correction — tâche 2</summary>

```yaml
# Dans 30c-test-surcharge.yml, ajoutez :
    - role: apache
      apache_port: 9090
      apache_service_name: httpd   # dans vars/ → priorité trop haute
```

```bash
ansible-playbook /tp/playbooks/30c-test-surcharge.yml -v
```

La valeur `httpd` est silencieusement ignorée. Le rôle continue d'utiliser
`apache2`. Pour forcer quand même :

```bash
ansible-playbook /tp/playbooks/30c-test-surcharge.yml -e "apache_service_name=httpd"
# → La valeur -e écrase tout, même vars/
```

**Tableau des priorités (extrait) :**

| | `defaults/main.yml` | `vars/main.yml` |
|:---|:---|:---|
| **Niveau de priorité** | 1 (le plus faible) | 18 (très haute) |
| **Surchargeable par l'appelant** | ✅ Facilement | ❌ Seulement via `-e` |
| **Contenu attendu** | Ce que l'**utilisateur** peut régler | Ce qui est **interne** au rôle |

> 🔑 **La règle :** tout ce que l'utilisateur du rôle a le droit de changer va dans
> `defaults/`. Ce qui casserait le rôle s'il était modifié va dans `vars/`.

</details>

---

## Partie 3 — Rôles `mysql` et `proxy`, orchestration complète

### Exercice RL1 — Créer les rôles `mysql` et `nginx_proxy`

| | |
|:---|:---|
| **Fichiers créés** | `roles/mysql/` · `roles/nginx_proxy/` complets |
| **Modules** | `apt` · `service` · `lineinfile` · `template` · `file` · `command` · `community.mysql.mysql_db` · `community.mysql.mysql_user` |
| **Notions** | `no_log: true` · `meta: flush_handlers` · `loop_control.label` · reverse proxy Nginx |
| **Durée** | ~10 min |

#### Tâche 1 — Créer le rôle `mysql`.

<details><summary>Correction — tâche 1</summary>

```bash
cd /tp/roles && ansible-galaxy role init mysql
```

```yaml
# /tp/roles/mysql/defaults/main.yml
---
mysql_bind_address: "0.0.0.0"
mysql_port: 3306
mysql_databases:
  - name: monapp_db
mysql_users:
  - name: monapp
    password: "ChangeMoi123!"    # sera chiffré au Lab 08
    priv: "monapp_db.*:ALL"
    host: "%"
```

```yaml
# /tp/roles/mysql/vars/main.yml
---
mysql_service_name: mariadb
mysql_packages:
  - mariadb-server
  - python3-pymysql
mysql_config_file: /etc/mysql/mariadb.conf.d/50-server.cnf
mysql_socket: /var/run/mysqld/mysqld.sock
```

```yaml
# /tp/roles/mysql/tasks/main.yml
---
- name: Installer MariaDB et le connecteur Python
  ansible.builtin.apt:
    name: "{{ mysql_packages }}"
    state: present
    update_cache: yes
  tags: [mysql, install]

- name: Démarrer et activer MariaDB
  ansible.builtin.service:
    name: "{{ mysql_service_name }}"
    state: started
    enabled: yes
  tags: [mysql, service]

- name: Configurer l'écoute réseau
  ansible.builtin.lineinfile:
    path: "{{ mysql_config_file }}"
    regexp: '^bind-address'
    line: "bind-address = {{ mysql_bind_address }}"
  notify: Redemarrer MariaDB
  tags: [mysql, config]

- name: Appliquer la configuration en attente
  ansible.builtin.meta: flush_handlers

- name: Créer les bases de données
  community.mysql.mysql_db:
    name: "{{ item.name }}"
    state: present
    login_unix_socket: "{{ mysql_socket }}"
  loop: "{{ mysql_databases }}"
  loop_control:
    label: "{{ item.name }}"
  tags: [mysql, config]

- name: Créer les utilisateurs applicatifs
  community.mysql.mysql_user:
    name: "{{ item.name }}"
    password: "{{ item.password }}"
    priv: "{{ item.priv }}"
    host: "{{ item.host }}"
    state: present
    login_unix_socket: "{{ mysql_socket }}"
  loop: "{{ mysql_users }}"
  loop_control:
    label: "{{ item.name }}"
  no_log: true                   # ne pas afficher les mots de passe en clair
  tags: [mysql, config]
```

```yaml
# /tp/roles/mysql/handlers/main.yml
---
- name: Redemarrer MariaDB
  ansible.builtin.service:
    name: "{{ mysql_service_name }}"
    state: restarted
```

> 💡 `meta: flush_handlers` force l'exécution immédiate des handlers en attente.
> Sans ça, MariaDB redémarrerait **après** la création des bases, ce qui
> provoquerait un échec de connexion pendant la création.

</details>

---

#### Tâche 2 — Créer le rôle `nginx_proxy`.

<details><summary>Correction — tâche 2</summary>

```bash
ansible-galaxy role init nginx_proxy
```

```yaml
# /tp/roles/nginx_proxy/defaults/main.yml
---
proxy_listen_port: 80
proxy_backend_group: web
proxy_backend_port: 80
proxy_algorithm: ""    # "" = round-robin, "least_conn", "ip_hash"
```

```yaml
# /tp/roles/nginx_proxy/tasks/main.yml
---
- name: Installer Nginx
  ansible.builtin.apt:
    name: nginx
    state: present
    update_cache: yes
  tags: [proxy, install]

- name: Générer la configuration du reverse proxy
  ansible.builtin.template:
    src: reverse-proxy.conf.j2
    dest: /etc/nginx/sites-available/reverse-proxy.conf
    mode: "0644"
  notify: Recharger Nginx
  tags: [proxy, config]

- name: Activer le site
  ansible.builtin.file:
    src: /etc/nginx/sites-available/reverse-proxy.conf
    dest: /etc/nginx/sites-enabled/reverse-proxy.conf
    state: link
  notify: Recharger Nginx
  tags: [proxy, config]

- name: Désactiver le site par défaut
  ansible.builtin.file:
    path: /etc/nginx/sites-enabled/default
    state: absent
  notify: Recharger Nginx
  tags: [proxy, config]

- name: Valider la configuration Nginx
  ansible.builtin.command: nginx -t
  changed_when: false
  tags: [proxy, config]

- name: Démarrer et activer Nginx
  ansible.builtin.service:
    name: nginx
    state: started
    enabled: yes
  tags: [proxy, service]
```

```jinja
{# /tp/roles/nginx_proxy/templates/reverse-proxy.conf.j2 #}
upstream backend_pool {
{% if proxy_algorithm %}
    {{ proxy_algorithm }};
{% endif %}
{% for host in groups[proxy_backend_group] | sort %}
    server {{ hostvars[host].ansible_default_ipv4.address }}:{{ proxy_backend_port }} max_fails=3 fail_timeout=10s;
{% endfor %}
}

server {
    listen {{ proxy_listen_port }};
    server_name {{ ansible_fqdn }};

    access_log /var/log/nginx/proxy_access.log;
    error_log  /var/log/nginx/proxy_error.log;

    location / {
        proxy_pass         http://backend_pool;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }

    location /health {
        access_log off;
        return 200 "proxy {{ inventory_hostname }} ok\n";
        add_header Content-Type text/plain;
    }
}
```

```yaml
# /tp/roles/nginx_proxy/handlers/main.yml
---
- name: Recharger Nginx
  ansible.builtin.service:
    name: nginx
    state: reloaded
```

</details>

---

#### Tâche 3 — Installer la collection `community.mysql` requise par le rôle.

<details><summary>Correction — tâche 3</summary>

```bash
ansible-galaxy collection install community.mysql
ansible-galaxy collection list | grep community.mysql
```

Sans cette collection, les modules `community.mysql.mysql_db` et
`community.mysql.mysql_user` ne sont pas disponibles. Ansible échoue avec
`MODULE NOT FOUND`. La collection sera formalisée dans `requirements.yml`
à la Partie 4.

</details>

---

### Exercice RL2 — Orchestration avec `site.yml`

| | |
|:---|:---|
| **Fichiers créés** | `/tp/site.yml` |
| **Notions** | Ordre des plays · `tags: [always]` pour peupler `hostvars` · `--limit` · `--tags` |
| **Durée** | ~10 min |

#### Tâche 1 — Écrire `site.yml` avec le play de collecte des facts en tête.

Expliquez pourquoi ce premier play `hosts: all` est indispensable au bon
fonctionnement du template Nginx.

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/site.yml
---
# =================================================================
# Play 0 : peuple hostvars pour TOUS les hôtes avant tout le reste.
# Indispensable : le template nginx_proxy lit les IPs des web servers
# via hostvars, qui est vide si ces hôtes n'ont pas passé gather_facts.
# =================================================================
- name: Collecte des facts sur l'ensemble du parc
  hosts: all
  gather_facts: yes
  tags: [always]
  tasks: []

- name: Couche base de données
  hosts: db
  become: yes
  roles:
    - mysql

- name: Couche applicative
  hosts: web
  become: yes
  roles:
    - role: apache
      apache_port: 80
      apache_app_name: monapp

- name: Couche reverse proxy
  hosts: proxy
  become: yes
  roles:
    - role: nginx_proxy
      proxy_listen_port: 80
      proxy_backend_group: web
```

**Sans le play 0 :** le play `proxy` s'exécute après `web`, mais Ansible
n'a collecté les facts de `web` **que** pendant le play `web`. Quand le template
Nginx essaie d'accéder à
`hostvars['node1'].ansible_default_ipv4.address`, la valeur est vide →
erreur de template.

`tags: [always]` garantit que ce play **s'exécute même si vous filtrez avec
`--tags`**. Sans ça, un `ansible-playbook site.yml --tags proxy` lancerait
le play proxy avec des `hostvars` vides.

</details>

---

#### Tâche 2 — Lancer `site.yml` et vérifier la stack de bout en bout.

<details><summary>Correction — tâche 2</summary>

```bash
cd /tp
ansible-playbook site.yml --syntax-check
ansible-playbook site.yml
```

**Vérification de bout en bout :**

```bash
# Le proxy répond en santé
ansible proxy -m uri -a "url=http://localhost/health return_content=yes"

# Le proxy route vers le backend Apache
ansible proxy -m uri -a "url=http://localhost/ return_content=yes" | grep -o "monapp"

# La base est joignable depuis le serveur web
ansible web -m shell -a "nc -zv node3 3306 2>&1"

# Idempotence globale
ansible-playbook site.yml
# → changed=0 attendu sur toutes les machines
```

</details>

---

#### Tâche 3 — Exécution partielle : `--tags` et `--limit`.

<details><summary>Correction — tâche 3</summary>

```bash
# Reconfigurer uniquement Apache (pas toucher à MySQL ni Nginx)
ansible-playbook site.yml --tags apache

# Ne mettre à jour que les configs (pas l'installation)
ansible-playbook site.yml --tags config

# Ne toucher qu'à node1
ansible-playbook site.yml --limit node1

# Combiner : reconfigurer Apache seulement sur node1
ansible-playbook site.yml --tags apache --limit node1

# Voir les tâches qui seraient exécutées sans les lancer
ansible-playbook site.yml --tags mysql --list-tasks
```

> 🔑 Les tags définis dans les tâches du rôle (`tags: [apache, config]`) sont
> accessibles depuis le playbook maître. C'est l'un des avantages d'avoir tagué
> les tâches dès la création du rôle.

</details>

---

### Exercice RL3 — Les trois façons d'appeler un rôle

| | |
|:---|:---|
| **Fichiers créés** | `/tp/playbooks/31-appels-roles.yml` |
| **Notions** | `roles:` · `import_role` · `include_role` · ordre d'exécution · `pre_tasks` |
| **Durée** | ~5 min |

#### Tâche 1 — Observer l'ordre réel avec `roles:` : les tâches s'exécutent APRÈS le rôle.

Écrivez une tâche **avant** la section `roles:` dans un play. Lancez et observez
dans quel ordre Ansible l'exécute réellement.

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/playbooks/31-appels-roles.yml
---
- name: Démonstration de l'ordre d'exécution
  hosts: web
  become: yes

  tasks:
    - name: "TÂCHE 1 — écrite en premier dans le fichier"
      ansible.builtin.debug:
        msg: "Où apparaît-elle dans l'exécution ?"

  roles:
    - role: apache
      apache_port: 80
```

```bash
ansible-playbook /tp/playbooks/31-appels-roles.yml --list-tasks
```

Sortie attendue :

```
play #1 (web): Démonstration de l'ordre d'exécution
  tasks:
    apache : Installer Apache    ← le RÔLE passe EN PREMIER
    apache : Installer PHP ...
    ...
    TÂCHE 1 — écrite en premier ← la task écrite en premier passe EN DERNIER
```

**L'ordre réel d'un play :**
`pre_tasks` → **`roles:`** → `tasks:` → `post_tasks` → handlers

Pour un ordre précis entre une tâche et un rôle, utilisez `import_role`
dans `tasks:` plutôt que la section `roles:`.

</details>

---

#### Tâche 2 — `import_role` vs `include_role` : statique vs dynamique.

<details><summary>Correction — tâche 2</summary>

Ajoutez dans `tasks:` de `31-appels-roles.yml` :

```yaml
  tasks:
    - name: "TÂCHE 1 — avant le rôle (grâce à import_role dans tasks:)"
      ansible.builtin.debug:
        msg: "Je s'exécute maintenant, avant le rôle"

    - name: Import statique — à la position exacte dans tasks
      ansible.builtin.import_role:
        name: apache
      vars:
        apache_port: 8080

    - name: "TÂCHE 2 — après le rôle importé"
      ansible.builtin.debug:
        msg: "Je s'exécute après le rôle importé"

    - name: Inclusion dynamique — permet conditions et boucles
      ansible.builtin.include_role:
        name: apache
      vars:
        apache_port: 9090
      when: ansible_memtotal_mb > 512
```

| Méthode | Moment | Position | Boucle / variable dans le nom | `--list-tasks` |
|:---|:---|:---|:---|:---|
| `roles:` | Parsing | **Avant** toutes les `tasks:` | ❌ | ✅ |
| `import_role` | Parsing | À sa position dans `tasks:` | ❌ | ✅ |
| `include_role` | Exécution | À sa position dans `tasks:` | ✅ | ❌ |

> `include_role` avec `loop:` ou un nom dynamique
> (`name: "{{ mon_role }}"`) — cas impossible avec `import_role`.

</details>

---

## Partie 4 — Ansible Galaxy et collections

### Exercice G1 — Installer et utiliser un rôle Galaxy

| | |
|:---|:---|
| **Modules** | `uri` |
| **Notions** | `ansible-galaxy role search/info/install/list` · `defaults/main.yml` comme documentation · versionnage |
| **Durée** | ~5 min |

#### Tâche 1 — Rechercher, inspecter et installer `geerlingguy.nginx`.

Avant toute chose, lisez `defaults/main.yml` du rôle — c'est son API.

<details><summary>Correction — tâche 1</summary>

```bash
# Rechercher
ansible-galaxy role search nginx --author geerlingguy

# Voir les informations (version stable, plateformes supportées)
ansible-galaxy role info geerlingguy.nginx

# Installer dans le roles_path configuré
ansible-galaxy role install geerlingguy.nginx:3.1.4 -p /tp/roles

# Lire l'API du rôle avant de l'utiliser
cat /tp/roles/geerlingguy.nginx/defaults/main.yml | head -40

# Lister les rôles installés
ansible-galaxy role list -p /tp/roles
```

</details>

---

#### Tâche 2 — Utiliser le rôle dans un playbook.

<details><summary>Correction — tâche 2</summary>

```yaml
# /tp/playbooks/32-galaxy.yml
---
- name: Nginx via un rôle Galaxy
  hosts: proxy
  become: yes

  roles:
    - role: geerlingguy.nginx
      nginx_vhosts:
        - listen: "8081"
          server_name: "{{ ansible_fqdn }}"
          root: /var/www/galaxy-demo
          index: "index.html"
```

```bash
ansible-playbook /tp/playbooks/32-galaxy.yml
ansible proxy -m uri -a "url=http://localhost:8081 status_code=200,404"
```

</details>

---

#### Tâche 3 — Précautions avant d'utiliser un rôle Galaxy en production.

Avant d'intégrer un rôle Galaxy dans un projet réel, appliquez cette checklist.

<details><summary>Correction — tâche 3</summary>

```bash
# Date du dernier commit (un rôle non maintenu est un risque)
ls -la /tp/roles/geerlingguy.nginx/.git/FETCH_HEAD

# Lire les tâches que vous allez exécuter en root
less /tp/roles/geerlingguy.nginx/tasks/main.yml

# Plateformes supportées
grep -A 10 platforms /tp/roles/geerlingguy.nginx/meta/main.yml
```

| Vérification | Pourquoi |
|:---|:---|
| Date du dernier commit | Un rôle sans commit depuis 3 ans posera problème |
| Nombre d'étoiles / téléchargements | Indicateur d'adoption et de fiabilité |
| Lecture de `defaults/main.yml` | C'est l'API — ce que vous pouvez régler |
| Lecture de `tasks/main.yml` | Vous exécutez ce code **en root** sur votre parc |
| Plateformes supportées (`meta/`) | Compatible avec votre distribution ? |
| **Épingler la version** | `3.1.4` — sinon un `install` futur peut casser tout |

> `geerlingguy.*` (Jeff Geerling) est la référence de qualité de l'écosystème.

</details>

---

### Exercice G2 — `requirements.yml` et collections

| | |
|:---|:---|
| **Fichiers créés** | `/tp/requirements.yml` |
| **Notions** | `requirements.yml` · `ansible-galaxy install -r` · FQCN · `ansible-doc` · `collections:` dans un play |
| **Durée** | ~5 min |

#### Tâche 1 — Écrire `requirements.yml` : le `package.json` d'Ansible.

<details><summary>Correction — tâche 1</summary>

```yaml
# /tp/requirements.yml
---
# ---------- Rôles ----------
roles:
  - name: geerlingguy.nginx
    version: "3.1.4"           # toujours épingler la version

  - name: geerlingguy.mysql
    version: "4.3.4"

  # Depuis un dépôt Git (rôle interne d'entreprise)
  - name: role-interne
    src: https://github.com/exemple/ansible-role-interne.git
    scm: git
    version: v1.2.0            # tag, branche ou commit SHA

# ---------- Collections ----------
collections:
  - name: community.general
    version: ">=8.0.0"

  - name: community.mysql
    version: ">=3.9.0"

  - name: ansible.posix
    version: ">=1.5.4"
```

```bash
# Installer tout d'un coup
ansible-galaxy install -r /tp/requirements.yml -p /tp/roles

# Rôles seulement
ansible-galaxy role install -r /tp/requirements.yml -p /tp/roles

# Collections seulement
ansible-galaxy collection install -r /tp/requirements.yml
```

> 🔑 `requirements.yml` est **le** fichier qui rend un projet reproductible :
> n'importe qui clone le dépôt, lance `ansible-galaxy install -r requirements.yml`
> et obtient exactement les mêmes dépendances.
>
> ⚠️ Sans `version:`, l'installation prend la dernière version disponible.
> Votre projet peut casser du jour au lendemain sans qu'une seule ligne de votre
> code n'ait changé.

</details>

---

#### Tâche 2 — Explorer les collections installées et les FQCN.

<details><summary>Correction — tâche 2</summary>

```bash
# Lister les collections installées
ansible-galaxy collection list

# Anatomie d'un FQCN
ansible-doc community.mysql.mysql_db

# Où sont installées les collections ?
ansible-config dump | grep COLLECTIONS_PATHS
```

**Anatomie d'un nom de module qualifié (FQCN) :**

```
community  .  mysql  .  mysql_db
─────────     ─────     ────────
namespace   collection   module
```

| Collection | Contenu principal |
|:---|:---|
| `ansible.builtin` | `apt`, `copy`, `file`, `service`… — toujours disponible |
| `ansible.posix` | `mount`, `sysctl`, `firewalld`, `authorized_key` |
| `community.general` | `ufw`, `timezone`, `snap`, `docker_*`… |
| `community.mysql` | `mysql_db`, `mysql_user`, `mysql_replication` |
| `amazon.aws` / `google.cloud` | Cloud providers |

> 🔑 **Bonne pratique : utilisez systématiquement le FQCN complet**
> (`ansible.builtin.apt` plutôt que `apt`). Aucune ambiguïté si deux collections
> définissent un module du même nom, et `ansible-lint` (Lab 10) l'exige par défaut.

</details>

---

## Partie 5 — Dépendances entre rôles

### Exercice D1 — Rôle `common` et dépendances via `meta/`

| | |
|:---|:---|
| **Fichiers créés** | `roles/common/` complet · `roles/apache/meta/main.yml` (ajout dépendance) |
| **Modules** | `apt` · `community.general.timezone` · `copy` |
| **Notions** | `meta/dependencies` · exécution unique par play · `allow_duplicates` · orchestration explicite vs implicite |
| **Durée** | ~5 min |

#### Tâche 1 — Créer le rôle `common`.

<details><summary>Correction — tâche 1</summary>

```bash
cd /tp/roles && ansible-galaxy role init common
```

```yaml
# /tp/roles/common/defaults/main.yml
---
common_packages:
  - htop
  - curl
  - vim
  - tree
  - jq
common_timezone: Europe/Paris
```

```yaml
# /tp/roles/common/tasks/main.yml
---
- name: Installer les outils de base
  ansible.builtin.apt:
    name: "{{ common_packages }}"
    state: present
    update_cache: yes
    cache_valid_time: 3600
  tags: [common, install]

- name: Configurer le fuseau horaire
  community.general.timezone:
    name: "{{ common_timezone }}"
  tags: [common, config]

- name: Déployer une bannière d'identification
  ansible.builtin.copy:
    dest: /etc/motd
    mode: "0644"
    content: |
      ============================================
       {{ inventory_hostname | upper }}
       Rôles  : {{ group_names | join(', ') }}
       Env    : {{ env | default('dev') }}
       Géré par Ansible — ne pas modifier à la main
      ============================================
  tags: [common, config]
```

</details>

---

#### Tâche 2 — Déclarer `common` en dépendance du rôle `apache`.

<details><summary>Correction — tâche 2</summary>

```yaml
# /tp/roles/apache/meta/main.yml
---
galaxy_info:
  author: Equipe Infra
  description: Installe et configure Apache avec PHP
  license: MIT
  min_ansible_version: "2.12"
  platforms:
    - name: Ubuntu
      versions: [jammy, focal]
  galaxy_tags: [web, apache, php]

dependencies:
  - role: common
    common_timezone: Europe/Paris
```

```bash
ansible-playbook /tp/playbooks/30-role-apache.yml
```

</details>

---

#### Tâche 3 — Observer l'exécution automatique de `common` et le piège de l'exécution unique.

Comparez ce qui se passe quand `apache` ET `mysql` déclarent tous deux `common`
en dépendance. Combien de fois `common` s'exécute-t-il ?

<details><summary>Correction — tâche 3</summary>

Ajoutez la même dépendance dans `roles/mysql/meta/main.yml` :

```yaml
# /tp/roles/mysql/meta/main.yml
dependencies:
  - role: common
```

```bash
ansible-playbook /tp/site.yml --list-tasks | grep "common"
```

Sortie attendue :

```
common : Installer les outils de base    ← exécuté UNE seule fois
common : Configurer le fuseau horaire
common : Déployer une bannière
apache : Installer Apache
...
mysql : Installer MariaDB                ← common n'apparaît PAS ici
```

`common` ne s'exécute **qu'une fois par play**, même si plusieurs rôles en
dépendent. Pour forcer la réexécution : `allow_duplicates: true` dans le
`meta/main.yml` du rôle dépendant.

**Orchestration explicite — alternative préférée en équipe :**

```yaml
# /tp/site.yml — rendre les dépendances visibles
- name: Couche commune
  hosts: all
  become: yes
  roles:
    - common            # ← visible, l'ordre est explicite

- name: Couche base de données
  hosts: db
  become: yes
  roles:
    - mysql             # ← pas de dépendance cachée dans meta/

- name: Couche applicative
  hosts: web
  become: yes
  roles:
    - apache
```

> ⚠️ Une dépendance dans `meta/` rend le rôle inutilisable sans elle. Beaucoup
> d'équipes préfèrent l'orchestration explicite dans le playbook : plus verbeux,
> mais l'ordre réel d'exécution est **immédiatement lisible**.

</details>

---

#### Tâche 4 — Vérifier l'architecture finale du projet.

<details><summary>Correction — tâche 4</summary>

```bash
tree -L 3 /tp -I '.secrets|*.retry|__pycache__'
```

```
/tp
├── ansible.cfg
├── inventory.yml
├── requirements.yml
├── site.yml                         ← point d'entrée unique
├── group_vars/
│   ├── all.yml
│   ├── web.yml
│   └── db.yml
├── roles/
│   ├── common/
│   ├── apache/
│   │   ├── defaults/main.yml
│   │   ├── handlers/main.yml
│   │   ├── meta/main.yml
│   │   ├── tasks/main.yml
│   │   └── templates/
│   ├── mysql/
│   ├── nginx_proxy/
│   └── geerlingguy.nginx/           ← installé depuis Galaxy
└── playbooks/
```

**C'est la structure standard recommandée par Ansible :**

| Élément | Rôle |
|:---|:---|
| `site.yml` | Point d'entrée unique — orchestre les rôles |
| `inventory.yml` | Le parc |
| `group_vars/` `host_vars/` | Les données, séparées du code |
| `roles/` | Le code réutilisable |
| `requirements.yml` | Les dépendances externes |
| `ansible.cfg` | La configuration du projet |

```bash
# Validation finale
ansible-playbook site.yml --syntax-check
ansible-playbook site.yml    # → changed=0
```

</details>

---

## À retenir

| Point clé | Détail |
|:---|:---|
| **`main.yml` automatique** | Chaque répertoire d'un rôle charge son `main.yml` sans `include`. |
| **Chemins relatifs automatiques** | `template: src: x.j2` cherche dans `templates/` du rôle — pas de `../`. |
| **`defaults/` = API publique** | Priorité la plus faible. Fait **pour** être surchargé. |
| **`vars/` = interne** | Priorité forte (niveau 18). Surchargeable uniquement via `-e`. |
| **`roles:` s'exécute avant `tasks:`** | Ordre réel : `pre_tasks` → `roles` → `tasks` → `post_tasks`. |
| **`include_role` pour le dynamique** | Seul à supporter boucles et noms de rôles variables. |
| **`hostvars` multi-play** | Toujours un premier play `hosts: all, gather_facts: yes` pour peupler `hostvars`. |
| **`requirements.yml`** | Le `package.json` d'Ansible. **Épinglez toujours les versions.** |
| **FQCN** | `ansible.builtin.apt` plutôt que `apt` — sans ambiguïté, exigé par `ansible-lint`. |
| **Rôle Galaxy** | Lisez `tasks/main.yml` avant usage : vous l'exécutez **en root** sur votre parc. |
| **Dépendances `meta/`** | Exécutées une seule fois par play. Souvent préférable de les expliciter dans le playbook. |

### Les commandes du lab

```bash
ansible-galaxy role init <nom>                         # créer un squelette
ansible-galaxy role install <auteur>.<rôle>:<ver> -p roles/  # installer depuis Galaxy
ansible-galaxy collection install <ns>.<coll>          # installer une collection
ansible-galaxy install -r requirements.yml -p roles/   # tout installer
ansible-galaxy role list / collection list             # inventorier
ansible-doc <fqcn>                                     # documenter un module
```

---

⬅️ **Lab précédent :** [Lab 06 — Templating Jinja2 et facts](<../lab 06 - Templating Jinja2 et facts/instructions.md>)
➡️ **Lab suivant :** [Lab 08 — Ansible Vault et gestion des secrets](<../lab 08 - Ansible Vault et gestion des secrets/instructions.md>)
