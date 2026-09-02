# Lab 10 — Module custom et qualité de code

> ⭐ Niveau : ⭐⭐⭐⭐ | ⏱ Durée estimée : 45 min | Module : **M10 — Extensibilité : modules, plugins, filtres & ansible-lint**

## Objectifs pédagogiques

* Développer un module Ansible personnalisé en Python
* Respecter le contrat d'un module : arguments, JSON de sortie, `changed`, `check_mode`
* Écrire un filtre Jinja2 personnalisé
* Déboguer un module en dehors d'Ansible
* Installer et exploiter `ansible-lint` pour garantir la qualité du code
* Corriger les règles les plus fréquemment enfreintes

## Notions abordées

* `AnsibleModule` : `argument_spec`, `required`, `type`, `default`, `no_log`
* `exit_json()` / `fail_json()` — le contrat de sortie
* `supports_check_mode` et gestion du mode simulation
* Emplacement des modules : `library/`, `ANSIBLE_LIBRARY`, `module_utils`
* Filtres personnalisés : `filter_plugins/`
* `ansible-lint` : profils, règles, `.ansible-lint`, `# noqa`
* `ansible-playbook --syntax-check` vs `ansible-lint` vs `yamllint`

## Documentation de référence

* [Developing modules](https://docs.ansible.com/ansible/latest/dev_guide/developing_modules_general.html)
* [Developing plugins](https://docs.ansible.com/ansible/latest/dev_guide/developing_plugins.html)
* [ansible-lint documentation](https://ansible.readthedocs.io/projects/lint/)

## Contexte

Votre équipe doit interroger une API interne pour récupérer des métadonnées lors de chaque
déploiement. Aujourd'hui, c'est fait avec un `shell: curl ... | jq ...` : non idempotent,
illisible, et sans gestion d'erreur.

Vous allez écrire un **vrai module Ansible** qui encapsule cet appel proprement — puis
mettre en place `ansible-lint` pour que ce genre de raccourci ne repasse plus en revue de
code.

---

## Partie 1 — Comprendre le contrat d'un module

### 1. Où Ansible cherche-t-il les modules ? Configurez un répertoire pour vos modules maison.

<details><summary>Correction</summary>

```bash
cd /tp
ansible-config dump | grep -i DEFAULT_MODULE_PATH
```

**Ordre de recherche des modules :**

| Priorité | Emplacement | Portée |
|:---|:---|:---|
| 1 | `library/` à côté du playbook | **Projet** ⭐ |
| 2 | `roles/<rôle>/library/` | Le rôle uniquement |
| 3 | `~/.ansible/plugins/modules/` | Utilisateur |
| 4 | `/usr/share/ansible/plugins/modules/` | Système |
| 5 | Collections installées | `ansible.builtin`, `community.*`… |

**Configuration du projet :**

```bash
mkdir -p /tp/library /tp/filter_plugins
```

```ini
# /tp/ansible.cfg
[defaults]
inventory = /tp/inventory.yml
roles_path = /tp/roles
library = /tp/library
filter_plugins = /tp/filter_plugins
remote_user = admin
host_key_checking = False
stdout_callback = yaml
```

> 💡 Le répertoire `library/` **à côté du playbook** est détecté automatiquement, même sans
> configuration. C'est la convention à privilégier : le module voyage avec le projet.

</details>

---

### 2. Quel est le contrat qu'un module doit respecter ?

<details><summary>Correction</summary>

Un module Ansible est un **programme** (généralement Python) qui :

1. **Reçoit** ses arguments (Ansible les lui transmet)
2. **Agit** ou **constate** l'état
3. **Renvoie du JSON** sur la sortie standard
4. **Sort avec le code 0** en cas de succès, non-zéro en cas d'échec

**Le JSON de sortie doit contenir au minimum :**

```json
{
  "changed": true,
  "msg": "Description de ce qui s'est passé"
}
```

**Clés reconnues par Ansible :**

| Clé | Rôle |
|:---|:---|
| `changed` | **Obligatoire** — l'état a-t-il été modifié ? |
| `failed` | La tâche a-t-elle échoué ? |
| `msg` | Message affiché à l'utilisateur |
| `rc` | Code retour |
| `skipped` | La tâche a-t-elle été ignorée ? |
| *(libre)* | Toute autre clé est accessible via `register` |

**Le squelette minimal :**

```python
#!/usr/bin/python
from ansible.module_utils.basic import AnsibleModule


def main():
    module = AnsibleModule(
        argument_spec=dict(
            nom=dict(type='str', required=True),
        ),
        supports_check_mode=True,
    )

    # ... logique ...

    module.exit_json(changed=False, msg="Rien à faire")


if __name__ == '__main__':
    main()
```

> 🔑 **`exit_json()` et `fail_json()` gèrent tout** : sérialisation JSON, code de sortie,
> masquage des valeurs `no_log`. N'écrivez **jamais** de `print()` ni de `sys.exit()` dans
> un module — cela casse le protocole.

</details>

---

## Partie 2 — Écrire un module

### 1. Développez le module `sysinfo` qui collecte des informations système et les renvoie proprement.

<details><summary>Correction</summary>

```python
#!/usr/bin/python
# -*- coding: utf-8 -*-
# /tp/library/sysinfo.py

from __future__ import absolute_import, division, print_function
__metaclass__ = type

DOCUMENTATION = r'''
---
module: sysinfo
short_description: Collecte des informations système synthétiques
description:
  - Renvoie un résumé de l'état d'une machine (charge, disque, mémoire).
  - Peut lever une alerte si un seuil est dépassé.
options:
  seuil_disque:
    description: Pourcentage d'occupation de / au-delà duquel alerter.
    type: int
    default: 80
  seuil_memoire:
    description: Pourcentage de mémoire utilisée au-delà duquel alerter.
    type: int
    default: 90
  point_montage:
    description: Point de montage à analyser.
    type: str
    default: /
  echouer_si_alerte:
    description: Faire échouer la tâche si un seuil est dépassé.
    type: bool
    default: false
author:
  - Equipe Infra
'''

EXAMPLES = r'''
- name: Collecter les informations système
  sysinfo:
  register: infos

- name: Alerter si le disque dépasse 70 %
  sysinfo:
    seuil_disque: 70
    echouer_si_alerte: true
'''

RETURN = r'''
disque:
  description: Utilisation du système de fichiers analysé.
  returned: always
  type: dict
memoire:
  description: Utilisation de la mémoire.
  returned: always
  type: dict
charge:
  description: Charge moyenne sur 1, 5 et 15 minutes.
  returned: always
  type: dict
alertes:
  description: Liste des seuils dépassés.
  returned: always
  type: list
'''

import os
from ansible.module_utils.basic import AnsibleModule


def info_disque(chemin):
    st = os.statvfs(chemin)
    total = st.f_blocks * st.f_frsize
    libre = st.f_bavail * st.f_frsize
    utilise = total - libre
    return {
        'total_mo': round(total / 1024 / 1024),
        'utilise_mo': round(utilise / 1024 / 1024),
        'libre_mo': round(libre / 1024 / 1024),
        'pourcentage': round(utilise / total * 100, 1) if total else 0,
    }


def info_memoire():
    valeurs = {}
    with open('/proc/meminfo') as f:
        for ligne in f:
            cle, _, reste = ligne.partition(':')
            valeurs[cle] = int(reste.strip().split()[0])

    total = valeurs.get('MemTotal', 0)
    dispo = valeurs.get('MemAvailable', valeurs.get('MemFree', 0))
    utilise = total - dispo
    return {
        'total_mo': round(total / 1024),
        'utilise_mo': round(utilise / 1024),
        'libre_mo': round(dispo / 1024),
        'pourcentage': round(utilise / total * 100, 1) if total else 0,
    }


def info_charge():
    un, cinq, quinze = os.getloadavg()
    return {'1min': round(un, 2), '5min': round(cinq, 2), '15min': round(quinze, 2)}


def main():
    module = AnsibleModule(
        argument_spec=dict(
            seuil_disque=dict(type='int', default=80),
            seuil_memoire=dict(type='int', default=90),
            point_montage=dict(type='str', default='/'),
            echouer_si_alerte=dict(type='bool', default=False),
        ),
        supports_check_mode=True,      # ce module ne fait que LIRE
    )

    p = module.params

    if not os.path.exists(p['point_montage']):
        module.fail_json(
            msg="Le point de montage '%s' n'existe pas" % p['point_montage']
        )

    try:
        disque = info_disque(p['point_montage'])
        memoire = info_memoire()
        charge = info_charge()
    except (IOError, OSError) as e:
        module.fail_json(msg="Impossible de collecter les informations : %s" % str(e))

    alertes = []
    if disque['pourcentage'] > p['seuil_disque']:
        alertes.append(
            "Disque %s à %.1f%% (seuil %d%%)"
            % (p['point_montage'], disque['pourcentage'], p['seuil_disque'])
        )
    if memoire['pourcentage'] > p['seuil_memoire']:
        alertes.append(
            "Mémoire à %.1f%% (seuil %d%%)"
            % (memoire['pourcentage'], p['seuil_memoire'])
        )

    resultat = dict(
        changed=False,          # ⭐ un module de LECTURE ne change JAMAIS rien
        disque=disque,
        memoire=memoire,
        charge=charge,
        alertes=alertes,
        alerte_active=bool(alertes),
    )

    if alertes and p['echouer_si_alerte']:
        module.fail_json(msg="Seuils dépassés : %s" % "; ".join(alertes), **resultat)

    resultat['msg'] = (
        "Disque %.1f%% | Mémoire %.1f%% | Charge %s"
        % (disque['pourcentage'], memoire['pourcentage'], charge['1min'])
    )
    module.exit_json(**resultat)


if __name__ == '__main__':
    main()
```

**Test :**

```yaml
# /tp/playbooks/60-module.yml
---
- name: Utilisation du module maison
  hosts: all
  gather_facts: no

  tasks:
    - name: Collecter les informations système
      sysinfo:
        seuil_disque: 70
        seuil_memoire: 85
      register: infos

    - name: Afficher la synthèse
      ansible.builtin.debug:
        msg: "{{ inventory_hostname }} → {{ infos.msg }}"

    - name: Détail du disque
      ansible.builtin.debug:
        var: infos.disque

    - name: Signaler les alertes
      ansible.builtin.debug:
        msg: "⚠️ {{ inventory_hostname }} : {{ infos.alertes | join(' | ') }}"
      when: infos.alerte_active

    - name: Version stricte — échoue si un seuil est dépassé
      sysinfo:
        seuil_disque: 1
        echouer_si_alerte: true
      ignore_errors: true
      register: strict

    - ansible.builtin.debug:
        msg: "Test strict : {{ 'échec attendu' if strict.failed else 'aucun dépassement' }}"
```

```bash
cd /tp
ansible-playbook playbooks/60-module.yml

# Le module fonctionne aussi en ad-hoc
ansible all -m sysinfo -a "seuil_disque=50"

# Et en mode check (supports_check_mode=True)
ansible-playbook playbooks/60-module.yml --check
```

**La documentation intégrée est exploitable :**

```bash
ansible-doc -M /tp/library sysinfo
```

> 🔑 **`changed=False` est essentiel ici.** Un module qui ne fait que **lire** ne doit
> jamais rapporter `changed`. C'est la différence avec `shell: df -h` qui rapporte
> systématiquement `changed` et pollue le rapport.

</details>

---

### 2. Écrivez un module qui **modifie** l'état, avec gestion correcte de `changed` et du `check_mode`.

<details><summary>Correction</summary>

```python
#!/usr/bin/python
# -*- coding: utf-8 -*-
# /tp/library/marqueur_deploiement.py

from __future__ import absolute_import, division, print_function
__metaclass__ = type

DOCUMENTATION = r'''
---
module: marqueur_deploiement
short_description: Gère un fichier marqueur de déploiement
description:
  - Écrit ou supprime un fichier JSON décrivant le déploiement en cours.
  - Idempotent : n'écrit que si le contenu diffère réellement.
options:
  chemin:
    description: Emplacement du fichier marqueur.
    type: path
    default: /var/lib/deploiement.json
  version:
    description: Version applicative déployée.
    type: str
  environnement:
    description: Environnement cible.
    type: str
    default: production
  state:
    description: Présence ou absence du marqueur.
    type: str
    choices: [present, absent]
    default: present
author:
  - Equipe Infra
'''

EXAMPLES = r'''
- name: Marquer le déploiement
  marqueur_deploiement:
    version: "2.1.0"
    environnement: production

- name: Supprimer le marqueur
  marqueur_deploiement:
    state: absent
'''

RETURN = r'''
chemin:
  description: Chemin du fichier marqueur.
  returned: always
  type: str
contenu:
  description: Contenu écrit dans le marqueur.
  returned: when state is present
  type: dict
'''

import json
import os
from datetime import datetime
from ansible.module_utils.basic import AnsibleModule


def lire_marqueur(chemin):
    """Retourne le contenu actuel, ou None si absent/illisible."""
    if not os.path.exists(chemin):
        return None
    try:
        with open(chemin) as f:
            return json.load(f)
    except (ValueError, IOError):
        return None


def main():
    module = AnsibleModule(
        argument_spec=dict(
            chemin=dict(type='path', default='/var/lib/deploiement.json'),
            version=dict(type='str'),
            environnement=dict(type='str', default='production'),
            state=dict(type='str', default='present', choices=['present', 'absent']),
        ),
        required_if=[('state', 'present', ['version'])],   # version obligatoire si present
        supports_check_mode=True,
    )

    p = module.params
    chemin = p['chemin']
    actuel = lire_marqueur(chemin)

    # ---------------------------------------------------------------- absent
    if p['state'] == 'absent':
        if actuel is None and not os.path.exists(chemin):
            module.exit_json(changed=False, chemin=chemin, msg="Marqueur déjà absent")

        if module.check_mode:
            module.exit_json(changed=True, chemin=chemin, msg="Serait supprimé")

        try:
            os.remove(chemin)
        except OSError as e:
            module.fail_json(msg="Suppression impossible : %s" % str(e))

        module.exit_json(changed=True, chemin=chemin, msg="Marqueur supprimé")

    # --------------------------------------------------------------- present
    souhaite = {
        'version': p['version'],
        'environnement': p['environnement'],
    }

    # ⭐ IDEMPOTENCE : comparer uniquement les champs signifiants.
    #    L'horodatage change à chaque exécution : l'inclure rendrait
    #    le module systématiquement "changed".
    if actuel is not None:
        if all(actuel.get(k) == v for k, v in souhaite.items()):
            module.exit_json(
                changed=False,
                chemin=chemin,
                contenu=actuel,
                msg="Marqueur déjà conforme",
            )

    souhaite['horodatage'] = datetime.now().isoformat()

    if module.check_mode:
        module.exit_json(
            changed=True, chemin=chemin, contenu=souhaite, msg="Serait écrit"
        )

    try:
        repertoire = os.path.dirname(chemin)
        if repertoire and not os.path.isdir(repertoire):
            os.makedirs(repertoire)
        with open(chemin, 'w') as f:
            json.dump(souhaite, f, indent=2)
    except (IOError, OSError) as e:
        module.fail_json(msg="Écriture impossible : %s" % str(e))

    module.exit_json(
        changed=True,
        chemin=chemin,
        contenu=souhaite,
        msg="Marqueur écrit (v%s)" % p['version'],
    )


if __name__ == '__main__':
    main()
```

**Test de l'idempotence :**

```yaml
# /tp/playbooks/61-marqueur.yml
---
- name: Marqueur de déploiement
  hosts: web
  become: yes
  gather_facts: no

  tasks:
    - name: Écrire le marqueur
      marqueur_deploiement:
        version: "2.1.0"
        environnement: production
      register: m

    - ansible.builtin.debug:
        msg: "{{ inventory_hostname }} → {{ m.msg }} (changed={{ m.changed }})"

    - name: Relire le fichier
      ansible.builtin.slurp:
        src: /var/lib/deploiement.json
      register: fichier

    - ansible.builtin.debug:
        msg: "{{ fichier.content | b64decode | from_json }}"
```

```bash
# 1re exécution → changed=true
ansible-playbook playbooks/61-marqueur.yml

# 2e exécution → changed=FALSE ⭐ (idempotence respectée)
ansible-playbook playbooks/61-marqueur.yml

# Changement de version → changed=true
ansible-playbook playbooks/61-marqueur.yml -e "version=2.2.0" 2>/dev/null || true

# Mode check → annonce le changement sans l'appliquer
ansible-playbook playbooks/61-marqueur.yml --check
```

> 🔑 **Les trois règles d'un module qui modifie l'état :**
>
> 1. **Lire l'état actuel d'abord**, comparer à l'état souhaité
> 2. **`changed=False`** si déjà conforme — c'est ça, l'idempotence
> 3. **Gérer `module.check_mode`** : annoncer le changement, ne pas l'appliquer
>
> ⚠️ **Le piège de l'horodatage :** inclure un timestamp dans la comparaison rendrait le
> module systématiquement `changed`. On ne compare que les champs signifiants.

</details>

---

### 3. Déboguez un module en dehors d'Ansible.

<details><summary>Correction</summary>

Un module n'est qu'un script Python : on peut l'exécuter directement.

```bash
# Créer un fichier d'arguments au format attendu
cat > /tmp/args.json <<'EOF'
{
  "ANSIBLE_MODULE_ARGS": {
    "seuil_disque": 50,
    "point_montage": "/"
  }
}
EOF

# Exécuter le module directement
python3 /tp/library/sysinfo.py /tmp/args.json | python3 -m json.tool
```

**Autres techniques de débogage :**

```bash
# 1. Verbosité maximale — montre les arguments transmis et le JSON reçu
ansible node1 -m sysinfo -a "seuil_disque=50" -vvv

# 2. Conserver les fichiers temporaires sur la cible pour inspection
ANSIBLE_KEEP_REMOTE_FILES=1 ansible node1 -m sysinfo -vvv
# puis, sur node1 : ls ~/.ansible/tmp/

# 3. Vérifier la syntaxe de la documentation intégrée
ansible-doc -M /tp/library sysinfo

# 4. Validation officielle (si ansible-test est disponible)
python3 -m py_compile /tp/library/sysinfo.py && echo "Syntaxe Python OK"
```

> ⚠️ **N'écrivez jamais sur stdout dans un module** (`print()`, `sys.stdout.write()`).
> Ansible attend **exclusivement** du JSON sur la sortie standard. Pour tracer,
> utilisez `module.log("message")` (journal syslog de la cible) ou renvoyez les
> informations dans le JSON de sortie.

</details>

---

## Partie 3 — Filtre Jinja2 personnalisé

### 1. Créez un filtre qui formate une taille en octets de façon lisible.

<details><summary>Correction</summary>

```python
# -*- coding: utf-8 -*-
# /tp/filter_plugins/formatage.py

from __future__ import absolute_import, division, print_function
__metaclass__ = type


def taille_lisible(octets, precision=1):
    """Convertit un nombre d'octets en chaîne lisible.

    Exemple : 1536000000 | taille_lisible  ->  '1.4 Gio'
    """
    try:
        octets = float(octets)
    except (TypeError, ValueError):
        return "n/a"

    for unite in ['o', 'Kio', 'Mio', 'Gio', 'Tio', 'Pio']:
        if abs(octets) < 1024.0:
            return "%.*f %s" % (precision, octets, unite)
        octets /= 1024.0
    return "%.*f Eio" % (precision, octets)


def duree_lisible(secondes):
    """Convertit un nombre de secondes en '3j 4h 12m'."""
    try:
        secondes = int(secondes)
    except (TypeError, ValueError):
        return "n/a"

    jours, reste = divmod(secondes, 86400)
    heures, reste = divmod(reste, 3600)
    minutes = reste // 60

    morceaux = []
    if jours:
        morceaux.append("%dj" % jours)
    if heures:
        morceaux.append("%dh" % heures)
    if minutes or not morceaux:
        morceaux.append("%dm" % minutes)
    return " ".join(morceaux)


def masquer_secret(valeur, visibles=4):
    """Masque une chaîne sensible en n'affichant que les derniers caractères."""
    texte = str(valeur)
    if len(texte) <= visibles:
        return "*" * len(texte)
    return "*" * (len(texte) - visibles) + texte[-visibles:]


def vers_nom_hote(valeur):
    """Normalise une chaîne en nom d'hôte valide."""
    import re
    texte = str(valeur).lower()
    texte = re.sub(r'[^a-z0-9-]+', '-', texte)
    return re.sub(r'-+', '-', texte).strip('-')


class FilterModule(object):
    """Point d'entrée reconnu par Ansible."""

    def filters(self):
        return {
            'taille_lisible': taille_lisible,
            'duree_lisible': duree_lisible,
            'masquer_secret': masquer_secret,
            'vers_nom_hote': vers_nom_hote,
        }
```

**Test :**

```yaml
# /tp/playbooks/62-filtres.yml
---
- name: Filtres personnalisés
  hosts: all
  gather_facts: yes

  tasks:
    - name: Formatage des tailles
      ansible.builtin.debug:
        msg:
          - "RAM totale : {{ (ansible_memtotal_mb * 1024 * 1024) | taille_lisible }}"
          - "RAM libre  : {{ (ansible_memfree_mb * 1024 * 1024) | taille_lisible(2) }}"

    - name: Formatage de l'uptime
      ansible.builtin.debug:
        msg: "Uptime de {{ inventory_hostname }} : {{ ansible_uptime_seconds | duree_lisible }}"

    - name: Masquage d'un secret
      ansible.builtin.debug:
        msg: "Clé API : {{ 'sk-1234567890abcdef' | masquer_secret }}"

    - name: Normalisation d'un nom
      ansible.builtin.debug:
        msg: "{{ 'Serveur Web PROD #1' | vers_nom_hote }}"

    - name: Usage dans une boucle
      ansible.builtin.debug:
        msg: "{{ item.mount }} → {{ item.size_total | taille_lisible }} ({{ item.size_available | taille_lisible }} libres)"
      loop: "{{ ansible_mounts }}"
      loop_control:
        label: "{{ item.mount }}"
```

```bash
ansible-playbook playbooks/62-filtres.yml
```

Sortie :

```
RAM totale : 1.9 Gio
Uptime de node1 : 2h 14m
Clé API : **************cdef
Serveur Web PROD #1 → serveur-web-prod-1
```

**Les autres types de plugins :**

| Type | Répertoire | Rôle |
|:---|:---|:---|
| Filtre | `filter_plugins/` | Transformer une valeur (`\| mon_filtre`) |
| Test | `test_plugins/` | Retourner un booléen (`is mon_test`) |
| Lookup | `lookup_plugins/` | Récupérer des données externes |
| Callback | `callback_plugins/` | Personnaliser la sortie, notifier |
| Connection | `connection_plugins/` | Nouveau transport (autre que SSH) |
| Inventory | `inventory_plugins/` | Source d'inventaire dynamique |

> 💡 **Filtre vs module :**
> * **Filtre** = transformation de données, **sur le controller**, sans effet de bord
> * **Module** = action **sur la cible**, avec notion d'état et de `changed`

</details>

---

## Partie 4 — `ansible-lint` : la qualité de code

### 1. Installez `ansible-lint` et lancez une première analyse.

<details><summary>Correction</summary>

```bash
python3 -m pip install --user ansible-lint
export PATH="$HOME/.local/bin:$PATH"
ansible-lint --version

cd /tp
ansible-lint site.yml
```

Sortie typique :

```
WARNING  Listing 14 violation(s) that are fatal
name[casing]: All names should start with an uppercase letter.
roles/apache/tasks/main.yml:3

fqcn[action-core]: Use FQCN for builtin module actions (apt).
roles/mysql/tasks/main.yml:5

risky-file-permissions: File permissions unset or incorrect.
roles/apache/tasks/main.yml:28

no-changed-when: Commands should not change things if nothing needs doing.
roles/apache/tasks/main.yml:15

yaml[truthy]: Truthy value should be one of [false, true]
site.yml:12
```

**Analyser tout le projet :**

```bash
ansible-lint                          # tout le répertoire courant
ansible-lint roles/apache             # un rôle précis
ansible-lint --format pep8            # format compact
ansible-lint --write                  # corriger automatiquement ce qui peut l'être
```

</details>

---

### 2. Corrigez les violations les plus fréquentes.

<details><summary>Correction</summary>

**Violation 1 — `fqcn[action-core]` : utiliser le nom complet du module**

```yaml
# ❌ Avant
- name: Installer Apache
  apt:
    name: apache2

# ✅ Après
- name: Installer Apache
  ansible.builtin.apt:
    name: apache2
```

**Violation 2 — `name[casing]` : majuscule initiale**

```yaml
# ❌ - name: installer apache
# ✅ - name: Installer Apache
```

**Violation 3 — `risky-file-permissions` : permissions explicites**

```yaml
# ❌ Avant — les permissions dépendent du umask, donc imprévisibles
- ansible.builtin.copy:
    src: app.conf
    dest: /etc/app.conf

# ✅ Après
- ansible.builtin.copy:
    src: app.conf
    dest: /etc/app.conf
    owner: root
    group: root
    mode: "0644"
```

**Violation 4 — `no-changed-when` : commande sans état de changement**

```yaml
# ❌ Avant — rapporte toujours "changed"
- ansible.builtin.command: apache2ctl configtest

# ✅ Après — c'est une vérification, elle ne change rien
- ansible.builtin.command: apache2ctl configtest
  changed_when: false
```

**Violation 5 — `yaml[truthy]` : booléens normalisés**

```yaml
# ❌  become: yes  /  enabled: True  /  gather_facts: no
# ✅  become: true /  enabled: true  /  gather_facts: false
```

**Violation 6 — `command-instead-of-module`**

```yaml
# ❌ Avant
- ansible.builtin.command: systemctl restart apache2

# ✅ Après
- ansible.builtin.service:
    name: apache2
    state: restarted
```

**Correction automatique :**

```bash
ansible-lint --write            # applique les corrections possibles
git diff                        # relisez TOUJOURS avant de committer
```

> ⚠️ `--write` modifie vos fichiers. Faites-le sur un dépôt Git propre pour pouvoir
> inspecter le diff et annuler si besoin.

</details>

---

### 3. Configurez `ansible-lint` pour votre projet.

<details><summary>Correction</summary>

```yaml
# /tp/.ansible-lint
---
# Profil de rigueur croissante :
#   min → basic → moderate → safety → shared → production
profile: moderate

exclude_paths:
  - .git/
  - .venv/
  - roles/geerlingguy.nginx/       # rôles tiers : pas à nous de les corriger
  - roles/geerlingguy.mysql/
  - collections/

# Règles désactivées, avec justification obligatoire
skip_list:
  - yaml[line-length]              # nos templates dépassent parfois 160 caractères

# Règles signalées sans faire échouer l'analyse
warn_list:
  - experimental
  - name[template]

# Règles activées explicitement (opt-in)
enable_list:
  - no-log-password
  - no-same-owner

# Variables définies ailleurs (CMDB, extra-vars) — évite les faux positifs
mock_modules:
  - community.mysql.mysql_db
  - community.mysql.mysql_user

kinds:
  - playbook: "**/playbooks/*.yml"
  - tasks: "**/tasks/*.yml"
  - vars: "**/{group,host}_vars/**/*.yml"
```

```bash
ansible-lint            # utilise automatiquement .ansible-lint
```

**Ignorer une règle ponctuellement — avec justification :**

```yaml
- name: Script legacy que l'on ne peut pas remplacer par un module
  ansible.builtin.command: /opt/legacy/deploy.sh   # noqa: command-instead-of-module
  changed_when: false
```

**Les profils :**

| Profil | Contenu |
|:---|:---|
| `min` | Erreurs bloquantes uniquement |
| `basic` | + conventions de nommage |
| `moderate` | + bonnes pratiques courantes ⭐ *bon point de départ* |
| `safety` | + règles de sécurité |
| `shared` | + exigences pour publier sur Galaxy |
| `production` | Le plus strict — pour du code critique |

> 💡 **Adoption progressive sur un projet existant :** commencez en `min`, corrigez, puis
> montez d'un cran. Passer directement en `production` sur du code hérité génère des
> centaines d'erreurs décourageantes.

</details>

---

### 4. Intégrez la vérification dans un pipeline CI.

<details><summary>Correction</summary>

```yaml
# /tp/.gitlab-ci.yml
---
stages: [lint, test, deploy]

variables:
  ANSIBLE_FORCE_COLOR: "1"

.python_setup: &python_setup
  image: python:3.11-slim
  before_script:
    - pip install --quiet ansible ansible-lint yamllint

# -----------------------------------------------------------------------------
yamllint:
  <<: *python_setup
  stage: lint
  script:
    - yamllint -c .yamllint .

ansible-lint:
  <<: *python_setup
  stage: lint
  script:
    - ansible-galaxy install -r requirements.yml
    - ansible-lint --format pep8

syntax-check:
  <<: *python_setup
  stage: lint
  script:
    - ansible-playbook site.yml --syntax-check -i inventory.yml

# -----------------------------------------------------------------------------
dry-run:
  <<: *python_setup
  stage: test
  script:
    - echo "$VAULT_PASSWORD" > /tmp/.vault_pass
    - chmod 600 /tmp/.vault_pass
    - ansible-playbook site.yml --check --diff --vault-password-file /tmp/.vault_pass
  after_script:
    - rm -f /tmp/.vault_pass
  only: [merge_requests]

# -----------------------------------------------------------------------------
deploy-production:
  <<: *python_setup
  stage: deploy
  script:
    - echo "$VAULT_PASSWORD" > /tmp/.vault_pass
    - chmod 600 /tmp/.vault_pass
    - ansible-playbook site.yml --vault-password-file /tmp/.vault_pass
  after_script:
    - rm -f /tmp/.vault_pass
  environment:
    name: production
  when: manual              # déclenchement humain explicite
  only: [main]
```

```yaml
# /tp/.yamllint
---
extends: default

rules:
  line-length:
    max: 160
    level: warning
  truthy:
    allowed-values: ['true', 'false']
  comments:
    min-spaces-from-content: 1
  indentation:
    spaces: 2
    indent-sequences: consistent
```

**Vérification locale avant de pousser :**

```bash
cd /tp
yamllint -c .yamllint . || true
ansible-lint --format pep8 || true
ansible-playbook site.yml --syntax-check
```

> 🔑 **La chaîne de qualité complète :**
>
> | Outil | Vérifie |
> |:---|:---|
> | `yamllint` | La syntaxe **YAML** (indentation, longueur, format) |
> | `ansible-playbook --syntax-check` | La structure **Ansible** (playbook valide) |
> | `ansible-lint` | Les **bonnes pratiques** Ansible |
> | `--check --diff` | L'**impact réel** sur l'infrastructure |
>
> Les quatre sont complémentaires — aucun ne remplace les autres.

</details>

---

## À retenir

| Point clé | Détail |
|:---|:---|
| **Contrat d'un module** | Reçoit des arguments, renvoie du **JSON** sur stdout, code de sortie 0/≠0. |
| **`exit_json` / `fail_json`** | Jamais de `print()` ni `sys.exit()` — cela casse le protocole. |
| **`changed` correct** | Module de lecture → `changed=False` **toujours**. |
| **Idempotence** | Lire l'état actuel, comparer, ne rien faire si déjà conforme. |
| **`supports_check_mode`** | Annoncer le changement sans l'appliquer. |
| **`library/`** | À côté du playbook — détecté automatiquement. |
| **Filtre vs module** | Filtre = transformation sur le controller ; module = action sur la cible. |
| **`ansible-lint`** | Commencez en profil `moderate`, montez progressivement. |
| **FQCN** | `ansible.builtin.apt` — exigé par `ansible-lint` en profil ≥ `basic`. |
| **`# noqa: <règle>`** | Ignorer ponctuellement, **avec justification**. |

### Débogage d'un module

```bash
# Exécuter le module hors Ansible
echo '{"ANSIBLE_MODULE_ARGS":{"arg":"valeur"}}' > /tmp/args.json
python3 library/mon_module.py /tmp/args.json | python3 -m json.tool

# Voir la documentation intégrée
ansible-doc -M ./library mon_module

# Trace complète
ansible node1 -m mon_module -a "arg=valeur" -vvv
```

---

⬅️ **Lab précédent :** [Lab 09 — Orchestration avancée et rolling update](<../lab 09 - Orchestration avancée et rolling update/instructions.md>)
➡️ **Lab suivant :** [Lab 11 — Projet final industrialisation](<../lab 11 - Projet final industrialisation/instructions.md>)
