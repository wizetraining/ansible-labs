# Lab 09 — Orchestration avancée et rolling update

> ⭐ Niveau : ⭐⭐⭐⭐ | ⏱ Durée estimée : 60 min | Module : **M9 — Orchestration avancée & fiabilité**

## Objectifs pédagogiques

* Réaliser une mise à jour progressive sans interruption de service (`serial`)
* Déléguer une tâche à une autre machine avec `delegate_to` et `run_once`
* Maîtriser les stratégies d'échec : `any_errors_fatal`, `max_fail_percentage`
* Structurer un playbook avec `pre_tasks` / `post_tasks`
* Valider l'infrastructure avec `assert`, `wait_for` et `uri`
* Régler le parallélisme (`forks`, `strategy`) et l'escalade de privilèges
* Découvrir l'inventaire dynamique

## Notions abordées

* `serial` : entier, pourcentage, liste progressive (*canary*)
* `delegate_to`, `delegate_facts`, `run_once`, `local_action`
* `any_errors_fatal`, `max_fail_percentage`, `throttle`
* `pre_tasks` / `post_tasks` / `force_handlers`
* `wait_for`, `uri`, `assert` — les tests d'infrastructure
* `strategy: linear | free | host_pinned`, `forks`
* `become`, `become_user`, `become_method`
* Inventaire dynamique : script et plugin

## Documentation de référence

* [Controlling playbook execution](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_strategies.html)
* [Delegation](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_delegation.html)
* [Dynamic inventory](https://docs.ansible.com/ansible/latest/inventory_guide/intro_dynamic_inventory.html)

## Contexte

Votre plateforme est en production : `node1` et `node2` servent l'application derrière le
reverse proxy `node3`. Une nouvelle version doit être déployée **en heures ouvrées**, sans
la moindre coupure visible pour les utilisateurs.

La méthode : traiter **un serveur à la fois**, en le retirant du pool avant intervention et
en ne le réintégrant qu'après validation. Si un serveur échoue, le déploiement s'arrête —
il vaut mieux une version partiellement déployée qu'un service totalement interrompu.

---

## Partie 1 — Préparer la plateforme cible

### 1. Reconfigurez l'inventaire : `node1` et `node2` en backends, `node3` en load balancer.

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
            app_version: "1.0.0"
          hosts:
            node1:
            node2:
        lb:
          hosts:
            node3:
```

```bash
cd /tp
ansible-inventory --graph
```

</details>

---

### 2. Déployez la plateforme initiale : Apache sur `web`, HAProxy sur `lb`.

<details><summary>Correction</summary>

```yaml
# /tp/playbooks/50-plateforme.yml
---
- name: Collecte des facts
  hosts: all
  gather_facts: yes
  tasks: []

# -----------------------------------------------------------------------------
- name: Backends applicatifs
  hosts: web
  become: yes

  tasks:
    - name: Installer Apache
      ansible.builtin.apt:
        name: apache2
        state: present
        update_cache: yes

    - name: Déployer la page applicative versionnée
      ansible.builtin.copy:
        dest: /var/www/html/index.html
        mode: "0644"
        content: |
          <html><body>
            <h1>monapp v{{ app_version }}</h1>
            <p>Servi par {{ inventory_hostname }}</p>
          </body></html>

    - name: Point de contrôle de santé
      ansible.builtin.copy:
        dest: /var/www/html/health
        mode: "0644"
        content: "OK {{ inventory_hostname }}\n"

    - name: Démarrer Apache
      ansible.builtin.service:
        name: apache2
        state: started
        enabled: yes

# -----------------------------------------------------------------------------
- name: Load balancer
  hosts: lb
  become: yes

  tasks:
    - name: Installer HAProxy
      ansible.builtin.apt:
        name: haproxy
        state: present
        update_cache: yes

    - name: Configurer HAProxy
      ansible.builtin.template:
        src: ../templates/haproxy-lb.cfg.j2
        dest: /etc/haproxy/haproxy.cfg
        mode: "0644"
        validate: 'haproxy -c -f %s'
      notify: Recharger HAProxy

    - name: Activer le socket d'administration
      ansible.builtin.file:
        path: /run/haproxy
        state: directory
        owner: haproxy
        group: haproxy
        mode: "0755"

    - name: Démarrer HAProxy
      ansible.builtin.service:
        name: haproxy
        state: started
        enabled: yes

  handlers:
    - name: Recharger HAProxy
      ansible.builtin.service:
        name: haproxy
        state: reloaded
```

```jinja
{# /tp/templates/haproxy-lb.cfg.j2 #}
global
    log /dev/log local0
    stats socket /run/haproxy/admin.sock mode 660 level admin
    maxconn 4096
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    http
    option  httplog
    timeout connect 5s
    timeout client  30s
    timeout server  30s
    retries 3

frontend web_front
    bind *:80
    default_backend web_pool

backend web_pool
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200
{% for host in groups['web'] | sort %}
    server {{ host }} {{ hostvars[host].ansible_default_ipv4.address }}:{{ hostvars[host].http_port | default(80) }} check inter 2s fall 2 rise 2
{% endfor %}

listen stats
    bind *:9000
    stats enable
    stats uri /
    stats refresh 5s
```

```bash
ansible-playbook playbooks/50-plateforme.yml
```

**Vérification :**

```bash
# Le LB répartit bien entre les deux backends
ansible lb -m shell -a "for i in 1 2 3 4; do curl -s localhost | grep 'Servi par'; done"
```

Sortie attendue — les deux nœuds apparaissent en alternance :

```
<p>Servi par node1</p>
<p>Servi par node2</p>
<p>Servi par node1</p>
<p>Servi par node2</p>
```

</details>

---

## Partie 2 — `serial` : la mise à jour progressive

### 1. Écrivez un playbook de rolling update qui traite **un seul serveur à la fois**.

<details><summary>Correction</summary>

```yaml
# /tp/playbooks/51-rolling.yml
---
- name: Collecte des facts (nécessaire pour delegate_to)
  hosts: all
  gather_facts: yes
  tags: [always]
  tasks: []

# =============================================================================
- name: Rolling update sans interruption de service
  hosts: web
  become: yes

  serial: 1                     # ⭐ UN SEUL serveur à la fois
  any_errors_fatal: true        # ⭐ le moindre échec arrête TOUT le déploiement
  max_fail_percentage: 0

  vars:
    app_version: "2.0.0"
    lb_host: node3

  pre_tasks:
    # ------------------------------------------------------------------
    # 1. RETIRER le serveur du pool AVANT toute intervention
    # ------------------------------------------------------------------
    - name: Retirer {{ inventory_hostname }} du load balancer
      ansible.builtin.shell: |
        echo "disable server web_pool/{{ inventory_hostname }}" \
          | socat stdio /run/haproxy/admin.sock
      delegate_to: "{{ lb_host }}"      # ⭐ exécuté SUR LE LB, pas sur le backend
      become: yes
      changed_when: true

    - name: Laisser les connexions en cours se terminer
      ansible.builtin.pause:
        seconds: 3

    - name: Vérifier que le serveur ne reçoit plus de trafic
      ansible.builtin.shell: |
        echo "show stat" | socat stdio /run/haproxy/admin.sock \
          | grep "web_pool,{{ inventory_hostname }}" | cut -d, -f18
      delegate_to: "{{ lb_host }}"
      become: yes
      register: statut_backend
      changed_when: false

    - name: Confirmer la mise hors service
      ansible.builtin.debug:
        msg: "{{ inventory_hostname }} → statut LB : {{ statut_backend.stdout | trim }}"

  tasks:
    # ------------------------------------------------------------------
    # 2. DÉPLOYER la nouvelle version
    # ------------------------------------------------------------------
    - name: Arrêter Apache
      ansible.builtin.service:
        name: apache2
        state: stopped

    - name: Déployer la version {{ app_version }}
      ansible.builtin.copy:
        dest: /var/www/html/index.html
        mode: "0644"
        content: |
          <html><body>
            <h1>monapp v{{ app_version }}</h1>
            <p>Servi par {{ inventory_hostname }}</p>
            <p>Déployé le {{ ansible_date_time.iso8601 }}</p>
          </body></html>

    - name: Redémarrer Apache
      ansible.builtin.service:
        name: apache2
        state: started

  post_tasks:
    # ------------------------------------------------------------------
    # 3. VALIDER avant de réintégrer
    # ------------------------------------------------------------------
    - name: Attendre que le port 80 réponde
      ansible.builtin.wait_for:
        port: 80
        host: 127.0.0.1
        delay: 1
        timeout: 30

    - name: Vérifier le point de santé
      ansible.builtin.uri:
        url: "http://localhost/health"
        status_code: 200
      register: sante
      retries: 5
      delay: 2
      until: sante.status == 200

    - name: Vérifier que la BONNE version est servie
      ansible.builtin.uri:
        url: "http://localhost/"
        return_content: yes
      register: page

    - name: Valider le contenu déployé
      ansible.builtin.assert:
        that:
          - "'v' ~ app_version in page.content"
        success_msg: "✅ {{ inventory_hostname }} sert bien la v{{ app_version }}"
        fail_msg: "❌ {{ inventory_hostname }} : mauvaise version déployée"

    # ------------------------------------------------------------------
    # 4. RÉINTÉGRER dans le pool
    # ------------------------------------------------------------------
    - name: Remettre {{ inventory_hostname }} dans le load balancer
      ansible.builtin.shell: |
        echo "enable server web_pool/{{ inventory_hostname }}" \
          | socat stdio /run/haproxy/admin.sock
      delegate_to: "{{ lb_host }}"
      become: yes
      changed_when: true

    - name: Attendre que le LB le détecte comme sain
      ansible.builtin.shell: |
        echo "show stat" | socat stdio /run/haproxy/admin.sock \
          | grep "web_pool,{{ inventory_hostname }}" | cut -d, -f18
      delegate_to: "{{ lb_host }}"
      become: yes
      register: sante_lb
      until: sante_lb.stdout | trim == "UP"
      retries: 10
      delay: 2
      changed_when: false

    - name: Serveur réintégré
      ansible.builtin.debug:
        msg: "✅ {{ inventory_hostname }} est de nouveau en service"
```

**Installer `socat` sur le LB (prérequis) :**

```bash
ansible lb -m apt -a "name=socat state=present" --become
```

**Exécution — gardez un second terminal ouvert pour observer :**

```bash
# Terminal 1 — trafic continu vers le LB
vagrant ssh node3 -c 'while true; do curl -s -o /dev/null -w "%{http_code} " localhost; sleep 0.3; done'

# Terminal 2 — lancer le rolling update
cd /tp && ansible-playbook playbooks/51-rolling.yml
```

**Observation clé :** le terminal 1 affiche `200 200 200 200...` **en continu**, sans un
seul `000` ni `503`. Le service n'a jamais été interrompu.

</details>

---

### 2. Explorez les différentes valeurs de `serial`.

<details><summary>Correction</summary>

```yaml
# --- 1. Un seul hôte à la fois — le plus sûr, le plus lent ---
serial: 1

# --- 2. Deux hôtes à la fois ---
serial: 2

# --- 3. Pourcentage — s'adapte à la taille du parc ---
serial: "25%"

# --- 4. Progressif (CANARY) — LE PATTERN DE PRODUCTION ⭐ ---
serial:
  - 1        # 1er lot : UN serveur → on valide sur un cobaye
  - 5        # 2e lot  : 5 serveurs → on confirme
  - "30%"    # 3e lot  : 30 % du parc restant
  - "100%"   # 4e lot  : tout le reste
```

**Pourquoi le déploiement progressif (*canary*) est le standard :**

| Lot | Objectif | Si ça casse |
|:---|:---|:---|
| 1 serveur | Détecter un problème de fond | 1 seul serveur impacté |
| 5 serveurs | Confirmer sous charge réelle | Impact limité, retour arrière rapide |
| 30 % | Valider à l'échelle | Le parc reste majoritairement sain |
| 100 % | Généraliser | Le risque a déjà été écarté |

**Le trio de directives à connaître :**

| Directive | Effet |
|:---|:---|
| `serial: N` | Taille du lot traité simultanément |
| `any_errors_fatal: true` | **Un** échec sur **un** hôte → tout le play s'arrête |
| `max_fail_percentage: 20` | Tolérer jusqu'à 20 % d'échecs avant d'arrêter |

```yaml
- hosts: web
  serial: "25%"
  max_fail_percentage: 10      # sur un lot de 20, on tolère 2 échecs
```

> ⚠️ **Sans `serial`, Ansible traite tous les hôtes en parallèle** (dans la limite de
> `forks`). Un playbook qui redémarre un service sur `hosts: web` **coupe tout le service
> simultanément**. `serial: 1` est la différence entre une mise à jour transparente et une
> interruption généralisée.

> 💡 `max_fail_percentage` est évalué **par lot**, pas sur l'ensemble du play.

</details>

---

## Partie 3 — Délégation

### 1. Comparez `delegate_to`, `run_once` et `local_action`.

<details><summary>Correction</summary>

```yaml
# /tp/playbooks/52-delegation.yml
---
- name: Collecte
  hosts: all
  gather_facts: yes
  tasks: []

- name: Mécanismes de délégation
  hosts: web
  gather_facts: no

  tasks:
    # --- 1. Tâche normale : exécutée SUR CHAQUE hôte du play ---
    - name: Sur chaque backend
      ansible.builtin.command: hostname
      register: r1
      changed_when: false

    - ansible.builtin.debug:
        msg: "Exécuté sur {{ r1.stdout }} (pour {{ inventory_hostname }})"

    # --- 2. delegate_to : exécutée SUR UNE AUTRE MACHINE ---
    #     mais UNE FOIS PAR HÔTE du play (2 fois ici)
    - name: Déléguée au load balancer
      ansible.builtin.command: hostname
      delegate_to: node3
      register: r2
      changed_when: false

    - ansible.builtin.debug:
        msg: "{{ inventory_hostname }} a délégué à {{ r2.stdout }}"

    # --- 3. run_once : exécutée UNE SEULE FOIS pour tout le play ---
    - name: Une seule fois, sur le premier hôte
      ansible.builtin.debug:
        msg: "Exécuté une seule fois (par {{ inventory_hostname }})"
      run_once: true

    # --- 4. run_once + delegate_to : LE COMBO le plus utile ---
    #     Une seule fois, sur une machine précise
    - name: Une fois, sur le controller
      ansible.builtin.command: date
      delegate_to: localhost
      run_once: true
      become: no
      register: r4
      changed_when: false

    - ansible.builtin.debug:
        msg: "Horodatage central : {{ r4.stdout }}"
      run_once: true

    # --- 5. local_action : raccourci pour delegate_to: localhost ---
    - name: Écrire un journal sur le controller
      ansible.builtin.lineinfile:
        path: /tp/deploiement.log
        line: "{{ ansible_date_time.iso8601 | default('n/a') }} — {{ inventory_hostname }} traité"
        create: yes
      delegate_to: localhost
      become: no
```

```bash
ansible-playbook playbooks/52-delegation.yml
cat /tp/deploiement.log
```

**Tableau de synthèse :**

| Directive | Où s'exécute la tâche | Combien de fois |
|:---|:---|:---|
| *(rien)* | Sur l'hôte courant | 1 fois **par hôte** |
| `delegate_to: X` | Sur `X` | 1 fois **par hôte** du play |
| `run_once: true` | Sur le **premier** hôte | **1 seule fois** |
| `run_once` + `delegate_to: X` | Sur `X` | **1 seule fois** ⭐ |
| `delegate_to: localhost` | Sur le **controller** | 1 fois par hôte |

**Cas d'usage réels :**

```yaml
# Notifier Slack une seule fois en fin de déploiement
- name: Notification
  ansible.builtin.uri:
    url: "{{ slack_webhook }}"
    method: POST
    body_format: json
    body: { text: "Déploiement v{{ app_version }} terminé" }
  delegate_to: localhost
  run_once: true

# Créer une entrée DNS pour chaque serveur, sur le serveur DNS
- name: Enregistrement DNS
  ansible.builtin.lineinfile:
    path: /etc/bind/db.interne
    line: "{{ inventory_hostname }} IN A {{ ansible_default_ipv4.address }}"
  delegate_to: dns01

# Sauvegarder la base depuis le serveur de backup
- name: Déclencher la sauvegarde
  ansible.builtin.command: /opt/backup.sh {{ inventory_hostname }}
  delegate_to: backup01
```

> ⚠️ **`delegate_facts`** : par défaut, les facts collectés lors d'une tâche déléguée sont
> attribués à l'hôte **courant**, pas à la machine déléguée. Pour les attribuer à la cible
> réelle : `delegate_facts: true`.

</details>

---

### 2. Utilisez `throttle` et réglez le parallélisme.

<details><summary>Correction</summary>

```yaml
# /tp/playbooks/53-parallelisme.yml
---
- name: Contrôle du parallélisme
  hosts: all
  gather_facts: no

  # strategy: linear (défaut) — toutes les machines terminent une tâche
  #                             avant de passer à la suivante
  # strategy: free            — chaque machine avance à son rythme
  strategy: linear

  tasks:
    - name: Tâche normale (limitée par forks)
      ansible.builtin.command: sleep 1
      changed_when: false

    - name: Tâche limitée à 1 machine à la fois
      ansible.builtin.command: sleep 1
      throttle: 1                # ⭐ même avec forks=10, une seule à la fois
      changed_when: false
```

```bash
# forks par défaut
time ansible-playbook playbooks/53-parallelisme.yml

# Augmenter le parallélisme
time ansible-playbook playbooks/53-parallelisme.yml --forks 20

# Voir la valeur configurée
ansible-config dump | grep -i forks
```

**Les leviers de performance :**

| Levier | Effet | Valeur typique |
|:---|:---|:---|
| `forks` (ansible.cfg / `-f`) | Nombre d'hôtes traités en parallèle | 5 (défaut) → 20-50 |
| `serial` | Taille du lot — **sécurité**, pas performance | 1 à 25 % |
| `throttle` | Limite **une tâche précise** | 1 pour les ressources partagées |
| `strategy: free` | Chaque hôte avance sans attendre les autres | Parcs hétérogènes |
| `gather_facts: no` | Économise 1-3 s par hôte | Si aucun fact n'est utilisé |
| `pipelining = True` | Réduit le nombre d'opérations SSH | ⭐ Gain de 30-50 % |

**Configuration de performance recommandée :**

```ini
# /tp/ansible.cfg
[defaults]
forks = 20
gathering = smart               # ne recollecte pas si déjà en cache
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts
fact_caching_timeout = 7200

[ssh_connection]
pipelining = True               # ⭐ le gain le plus important
ssh_args = -o ControlMaster=auto -o ControlPersist=60s
control_path = /tmp/ansible-%%h-%%p-%%r
```

> ⚠️ **`pipelining = True` exige que `requiretty` soit désactivé** dans `/etc/sudoers` sur
> les cibles. C'est le cas par défaut sur Debian/Ubuntu, mais pas toujours sur RHEL/CentOS.

> 💡 **`throttle` a un vrai cas d'usage** : quand 50 serveurs téléchargent simultanément un
> artefact depuis le même dépôt, `throttle: 5` évite de saturer le serveur de fichiers.

</details>

---

## Partie 4 — Tests et validation d'infrastructure

### 1. Écrivez un playbook de validation complet de la plateforme.

<details><summary>Correction</summary>

```yaml
# /tp/playbooks/54-validation.yml
---
- name: Collecte
  hosts: all
  gather_facts: yes
  tasks: []

# =============================================================================
- name: Validation des backends
  hosts: web
  become: yes
  gather_facts: no

  tasks:
    - name: Le service Apache est actif
      ansible.builtin.command: systemctl is-active apache2
      register: svc
      changed_when: false
      failed_when: svc.stdout != "active"

    - name: Le port 80 est en écoute
      ansible.builtin.wait_for:
        port: 80
        host: 127.0.0.1
        timeout: 5

    - name: Le point de santé répond
      ansible.builtin.uri:
        url: http://localhost/health
        status_code: 200
        return_content: yes
      register: sante

    - name: La page applicative répond
      ansible.builtin.uri:
        url: http://localhost/
        status_code: 200
        return_content: yes
      register: page

    - name: Contrôles fonctionnels
      ansible.builtin.assert:
        that:
          - sante.status == 200
          - inventory_hostname in sante.content
          - "'monapp' in page.content"
          - page.elapsed < 2
        success_msg: "✅ {{ inventory_hostname }} conforme ({{ page.elapsed }}s)"
        fail_msg: "❌ {{ inventory_hostname }} non conforme"

    - name: Contrôles système
      ansible.builtin.assert:
        that:
          - ansible_memfree_mb > 50
          - ansible_processor_vcpus >= 1
        success_msg: "✅ Ressources suffisantes sur {{ inventory_hostname }}"
        fail_msg: "❌ Ressources insuffisantes sur {{ inventory_hostname }}"

# =============================================================================
- name: Validation du load balancer
  hosts: lb
  become: yes
  gather_facts: no

  tasks:
    - name: HAProxy est actif
      ansible.builtin.command: systemctl is-active haproxy
      register: svc_lb
      changed_when: false
      failed_when: svc_lb.stdout != "active"

    - name: Tous les backends sont vus comme UP
      ansible.builtin.shell: |
        echo "show stat" | socat stdio /run/haproxy/admin.sock \
          | grep "^web_pool," | grep -v BACKEND | cut -d, -f2,18
      register: backends
      changed_when: false

    - name: Afficher l'état des backends
      ansible.builtin.debug:
        var: backends.stdout_lines

    - name: Aucun backend ne doit être DOWN
      ansible.builtin.assert:
        that:
          - "'DOWN' not in backends.stdout"
        success_msg: "✅ Tous les backends sont UP"
        fail_msg: "❌ Au moins un backend est DOWN"

    - name: Test de répartition de charge
      ansible.builtin.uri:
        url: http://localhost/
        return_content: yes
      register: reponses
      loop: "{{ range(1, 9) | list }}"
      loop_control:
        label: "requête {{ item }}"

    - name: Les DEUX backends répondent (répartition effective)
      ansible.builtin.assert:
        that:
          - reponses.results | map(attribute='content') | select('search', 'node1') | list | length > 0
          - reponses.results | map(attribute='content') | select('search', 'node2') | list | length > 0
        success_msg: "✅ La répartition de charge fonctionne"
        fail_msg: "❌ Un seul backend reçoit le trafic"

# =============================================================================
- name: Rapport final
  hosts: localhost
  connection: local
  gather_facts: yes

  tasks:
    - name: Synthèse
      ansible.builtin.debug:
        msg:
          - "═══════════════════════════════════════"
          - " VALIDATION DE LA PLATEFORME — SUCCÈS"
          - "═══════════════════════════════════════"
          - " Backends : {{ groups['web'] | join(', ') }}"
          - " LB       : {{ groups['lb'] | join(', ') }}"
          - " Date     : {{ ansible_date_time.iso8601 }}"
          - "═══════════════════════════════════════"
```

```bash
ansible-playbook playbooks/54-validation.yml
```

> 🔑 **C'est un test d'infrastructure automatisé.** Il peut être joué :
> * après chaque déploiement (validation immédiate)
> * périodiquement en supervision (détection de dérive)
> * en étape de CI/CD (porte de qualité avant promotion)
>
> `assert` échoue le play si une condition n'est pas remplie — ce qui fait échouer le
> pipeline. C'est exactement le comportement attendu d'un test.

</details>

---

### 2. Simulez une panne et vérifiez que le déploiement s'arrête proprement.

<details><summary>Correction</summary>

```bash
# Casser volontairement node2
ansible node2 -m service -a "name=apache2 state=stopped" --become

# Relancer la validation
ansible-playbook playbooks/54-validation.yml
```

Résultat attendu :

```
TASK [Le service Apache est actif] ****
ok: [node1]
fatal: [node2]: FAILED! => {"changed": false, "cmd": ["systemctl","is-active","apache2"], ...}

PLAY RECAP ****
node1 : ok=6  changed=0  failed=0
node2 : ok=0  changed=0  failed=1
```

**Testez maintenant `any_errors_fatal` sur le rolling update :**

```bash
# node2 est toujours cassé
ansible-playbook playbooks/51-rolling.yml
```

Avec `serial: 1` + `any_errors_fatal: true`, si `node1` réussit mais `node2` échoue, le play
s'arrête **immédiatement** — aucun autre serveur n'est touché.

**Réparer :**

```bash
ansible node2 -m service -a "name=apache2 state=started" --become
ansible-playbook playbooks/54-validation.yml
```

**Les stratégies d'échec :**

| Directive | Comportement |
|:---|:---|
| *(défaut)* | L'hôte en échec est retiré du play ; les autres continuent |
| `any_errors_fatal: true` | **Tout** le play s'arrête au premier échec |
| `max_fail_percentage: N` | Arrêt si plus de N % du **lot** échoue |
| `ignore_errors: true` | L'échec est ignoré (⚠️ masque les problèmes) |
| `ignore_unreachable: true` | Continue même si l'hôte est injoignable |
| `force_handlers: true` | Exécute les handlers même après un échec |

> 🔑 **En production, `any_errors_fatal: true` sur un rolling update est presque toujours le
> bon choix.** Mieux vaut une version partiellement déployée qu'un déploiement qui continue
> à propager un problème sur tout le parc.

</details>

---

## Partie 5 — Inventaire dynamique

### 1. Créez un inventaire dynamique par script.

<details><summary>Correction</summary>

Un inventaire dynamique est un **exécutable** qui renvoie du JSON. Ansible l'appelle avec
`--list` et utilise sa sortie comme inventaire.

```bash
mkdir -p /tp/inventories
```

```python
#!/usr/bin/env python3
# /tp/inventories/dynamic.py
"""
Inventaire dynamique — démonstration.

En production, ce script interrogerait une source de vérité :
  - une API de CMDB
  - AWS EC2 / Azure / GCP
  - une base de données d'exploitation
  - Kubernetes, VMware, Proxmox…

Contrat d'interface Ansible :
  --list       → l'inventaire complet au format JSON
  --host <h>   → les variables d'un hôte précis
"""
import json
import sys

# En conditions réelles : appel API, requête SQL, lecture d'un référentiel…
SOURCE_DE_VERITE = [
    {"nom": "node1", "ip": "192.168.56.21", "role": "web", "env": "production"},
    {"nom": "node2", "ip": "192.168.56.22", "role": "web", "env": "production"},
    {"nom": "node3", "ip": "192.168.56.23", "role": "lb",  "env": "production"},
]


def construire_inventaire():
    inventaire = {
        "_meta": {"hostvars": {}},
        "all": {"children": ["ungrouped"]},
    }

    for machine in SOURCE_DE_VERITE:
        nom = machine["nom"]

        # Variables de l'hôte
        inventaire["_meta"]["hostvars"][nom] = {
            "ansible_host": machine["ip"],
            "ansible_user": "admin",
            "role_metier": machine["role"],
            "env": machine["env"],
        }

        # Groupe par rôle
        groupe_role = machine["role"]
        inventaire.setdefault(groupe_role, {"hosts": []})
        inventaire[groupe_role]["hosts"].append(nom)
        if groupe_role not in inventaire["all"]["children"]:
            inventaire["all"]["children"].append(groupe_role)

        # Groupe par environnement
        groupe_env = f"env_{machine['env']}"
        inventaire.setdefault(groupe_env, {"hosts": []})
        inventaire[groupe_env]["hosts"].append(nom)
        if groupe_env not in inventaire["all"]["children"]:
            inventaire["all"]["children"].append(groupe_env)

    return inventaire


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--list":
        print(json.dumps(construire_inventaire(), indent=2))
    elif len(sys.argv) == 3 and sys.argv[1] == "--host":
        print(json.dumps(
            construire_inventaire()["_meta"]["hostvars"].get(sys.argv[2], {})
        ))
    else:
        print("Usage: dynamic.py --list | --host <hôte>", file=sys.stderr)
        sys.exit(1)
```

```bash
chmod +x /tp/inventories/dynamic.py

# Tester le contrat d'interface
/tp/inventories/dynamic.py --list | jq
/tp/inventories/dynamic.py --host node1 | jq

# Utiliser avec Ansible
ansible-inventory -i /tp/inventories/dynamic.py --graph
ansible -i /tp/inventories/dynamic.py all -m ping
ansible -i /tp/inventories/dynamic.py web -m command -a "hostname"
```

Sortie de `--graph` :

```
@all:
  |--@lb:
  |  |--node3
  |--@web:
  |  |--node1
  |  |--node2
  |--@env_production:
  |  |--node1
  |  |--node2
  |  |--node3
```

> 💡 **La clé `_meta.hostvars`** est une optimisation majeure : elle permet à Ansible de
> récupérer **toutes** les variables en un seul appel `--list`, au lieu d'appeler
> `--host <nom>` une fois par machine. Sur un parc de 500 serveurs, la différence est de
> plusieurs minutes.

</details>

---

### 2. Découvrez les plugins d'inventaire — l'approche moderne.

<details><summary>Correction</summary>

Les scripts sont l'ancienne méthode. Les **plugins d'inventaire** se configurent en YAML,
sans écrire de code.

```yaml
# /tp/inventories/demo.yml — plugin constructed
---
plugin: ansible.builtin.constructed
strict: false

# Créer des groupes à partir d'expressions
groups:
  machines_web: "'web' in group_names"
  petite_ram: ansible_memtotal_mb | default(0) < 2048

# Créer des groupes à partir d'une valeur de variable
keyed_groups:
  - key: ansible_distribution
    prefix: os
  - key: env | default('inconnu')
    prefix: env
```

**Exemples de plugins pour le cloud :**

```yaml
# AWS EC2
---
plugin: amazon.aws.aws_ec2
regions: [eu-west-1, eu-west-3]
filters:
  tag:Environment: production
  instance-state-name: running
keyed_groups:
  - key: tags.Role
    prefix: role
  - key: placement.availability_zone
    prefix: az
hostnames:
  - tag:Name
  - private-ip-address
compose:
  ansible_host: private_ip_address
```

```yaml
# Docker
---
plugin: community.docker.docker_containers
docker_host: unix://var/run/docker.sock
connection_type: docker
```

```bash
# Lister les plugins disponibles
ansible-doc -t inventory -l | head -30

# Documentation d'un plugin
ansible-doc -t inventory amazon.aws.aws_ec2
```

**Plugins vs scripts :**

| | Script (`.py`) | Plugin (`.yml`) |
|:---|:---|:---|
| Écriture | Code à maintenir | Configuration YAML |
| Cache | À implémenter soi-même | Intégré |
| `keyed_groups` | À coder | Natif |
| Maintenance | À votre charge | Assurée par la collection |
| Sources exotiques | ✅ Flexible | Selon disponibilité |

> 🔑 **En production, l'inventaire dynamique est la norme** dès que l'infrastructure est
> élastique. Un serveur créé par Terraform apparaît automatiquement dans l'inventaire —
> aucune édition manuelle, aucun oubli, aucune dérive entre l'infrastructure réelle et sa
> description.

</details>

---

## À retenir

| Point clé | Détail |
|:---|:---|
| **`serial`** | Sans lui, tous les hôtes sont traités en parallèle → coupure totale. |
| **`serial` progressif** | `[1, 5, "30%", "100%"]` — le pattern *canary* de production. |
| **`any_errors_fatal`** | Un échec arrête tout. Le bon réflexe sur un rolling update. |
| **`max_fail_percentage`** | Évalué **par lot**, pas sur l'ensemble du play. |
| **`delegate_to`** | Exécute ailleurs, 1 fois **par hôte** du play. |
| **`run_once` + `delegate_to`** | Le combo : 1 seule fois, sur une machine précise. |
| **`wait_for` / `uri` / `assert`** | Le trio des tests d'infrastructure. |
| **`pipelining = True`** | Le gain de performance le plus rentable (30-50 %). |
| **`throttle`** | Limite une tâche précise — utile pour les ressources partagées. |
| **`_meta.hostvars`** | Optimisation indispensable d'un inventaire dynamique. |

### Le squelette d'un rolling update

```yaml
- hosts: web
  serial: 1
  any_errors_fatal: true

  pre_tasks:
    - name: Retirer du LB
      delegate_to: "{{ lb_host }}"

  tasks:
    - name: Déployer

  post_tasks:
    - name: Valider la santé          # wait_for + uri + assert
    - name: Réintégrer au LB
      delegate_to: "{{ lb_host }}"
```

---

⬅️ **Lab précédent :** [Lab 08 — Ansible Vault et gestion des secrets](<../lab 08 - Ansible Vault et gestion des secrets/instructions.md>)
➡️ **Lab suivant :** [Lab 10 — Module custom et qualité de code](<../lab 10 - Module custom et qualité de code/instructions.md>)
