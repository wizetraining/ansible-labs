# Lab 08 — Ansible Vault et gestion des secrets

> ⭐ Niveau : ⭐⭐ | ⏱ Durée estimée : 45 min | Module : **M8 — Ansible Vault & gestion des secrets**

## Objectifs pédagogiques

* Constater concrètement la fuite de secrets dans un dépôt Git
* Chiffrer un fichier complet et une variable isolée avec Ansible Vault
* Exploiter un fichier chiffré dans un playbook et une commande ad-hoc
* Mettre en place un `vault-password-file` pour automatiser l'exécution
* Gérer plusieurs coffres avec les `vault-id`
* Appliquer les bonnes pratiques : `.gitignore`, `no_log`, rotation de clé

## Notions abordées

* `ansible-vault` : `create`, `edit`, `encrypt`, `decrypt`, `view`, `rekey`
* `encrypt_string` : chiffrer **une seule variable** dans un fichier en clair
* `--ask-vault-pass`, `--vault-password-file`, `ANSIBLE_VAULT_PASSWORD_FILE`
* `vault_identity_list` et les `--vault-id` multiples
* Convention `vars/main.yml` + `vault.yml` (le pattern recommandé)
* `no_log: true` pour ne pas fuiter dans la sortie
* Intégration Git : `.gitignore`, `.gitattributes`

## Documentation de référence

* [Encrypting content with Ansible Vault](https://docs.ansible.com/ansible/latest/vault_guide/index.html)
* [Keeping vaulted variables safely visible](https://docs.ansible.com/ansible/latest/vault_guide/vault_best_practices.html)

## Contexte

Relisez le rôle `mysql` du Lab 07 :

```yaml
mysql_users:
  - name: monapp
    password: "ChangeMoi123!"      # ← en clair, dans un fichier versionné
```

Ce mot de passe est en clair dans un fichier destiné à Git. Il sera dans l'historique du
dépôt, dans tous les clones, dans les sauvegardes, et visible par toute personne ayant accès
en lecture au projet — **définitivement**, même après correction.

Votre mission : supprimer tous les secrets en clair du projet.

---

## Partie 1 — Mesurer le problème

### 1. Recensez tous les secrets en clair présents dans votre projet.

<details><summary>Correction</summary>

```bash
cd /tp

# Recherche par mots-clés
grep -rniE "(password|passwd|secret|token|api_key|private_key)" \
     --include="*.yml" --include="*.yaml" \
     . 2>/dev/null | grep -v "^\./roles/geerlingguy"
```

Résultats typiques :

```
./roles/mysql/defaults/main.yml:    password: "ChangeMoi123!"
./playbooks/lamp.yml:    db_password: "ChangeMoi123!"
```

**Pourquoi c'est un vrai problème et pas une négligence mineure :**

| Conséquence | Détail |
|:---|:---|
| **Historique Git permanent** | `git log -p` retrouve le secret même après suppression |
| **Diffusion incontrôlée** | Chaque clone, fork, sauvegarde contient le secret |
| **Portée d'accès** | Lire le code ≠ connaître les mots de passe de production |
| **Rotation impossible** | Changer le mot de passe exige de réécrire l'historique |
| **Conformité** | Rédhibitoire pour tout audit (ISO 27001, SOC 2, PCI-DSS) |

> 🔑 **La règle absolue :** un secret qui a été committé une fois doit être considéré comme
> **compromis**. La seule remédiation correcte est de le **révoquer et le remplacer**, pas
> de le supprimer du fichier.

</details>

---

## Partie 2 — Chiffrer un fichier complet

### 1. Créez un fichier de secrets chiffré avec `ansible-vault create`.

<details><summary>Correction</summary>

```bash
cd /tp
mkdir -p group_vars/db

# Créer et chiffrer en une opération — l'éditeur s'ouvre sur un fichier vide
ansible-vault create group_vars/db/vault.yml
# Mot de passe du coffre : Formation2024!
```

Saisissez dans l'éditeur :

```yaml
---
vault_mysql_root_password: "R00tS3cr3t!2024"
vault_mysql_app_password: "AppP@ssw0rd!2024"
vault_backup_encryption_key: "cle-de-chiffrement-des-sauvegardes"
```

**Vérifiez que le fichier est bien illisible :**

```bash
cat group_vars/db/vault.yml
```

```
$ANSIBLE_VAULT;1.1;AES256
33393835626661383735313963636531373862373533303236613762346261363338...
64383734363936633561643666366533343464613437363333383733363464633862...
```

**Les commandes du coffre :**

```bash
ansible-vault view   group_vars/db/vault.yml    # afficher sans modifier
ansible-vault edit   group_vars/db/vault.yml    # éditer (déchiffre/rechiffre en mémoire)
ansible-vault encrypt fichier.yml               # chiffrer un fichier existant
ansible-vault decrypt fichier.yml               # déchiffrer DÉFINITIVEMENT (⚠️)
ansible-vault rekey  group_vars/db/vault.yml    # changer le mot de passe du coffre
```

> 💡 `ansible-vault edit` ne laisse **jamais** de version en clair sur le disque : le
> déchiffrement se fait en mémoire, l'éditeur travaille dans un fichier temporaire, et le
> résultat est rechiffré à la fermeture.
>
> ⚠️ `ansible-vault decrypt` écrit le fichier **en clair sur le disque**. Ne l'utilisez que
> pour une migration, jamais dans un workflow courant.

</details>

---

### 2. Appliquez la convention `vars.yml` + `vault.yml` — le pattern recommandé.

<details><summary>Correction</summary>

Le problème du chiffrement intégral : `git diff` devient illisible, et on ne sait plus
**quelles** variables existent sans ouvrir le coffre.

**La solution : deux fichiers, une indirection.**

```yaml
# /tp/group_vars/db/vars.yml   — EN CLAIR, versionné, lisible
---
mysql_bind_address: "0.0.0.0"
mysql_port: 3306

mysql_databases:
  - name: monapp_db

mysql_users:
  - name: monapp
    password: "{{ vault_mysql_app_password }}"   # ← pointe vers le coffre
    priv: "monapp_db.*:ALL"
    host: "%"

mysql_root_password: "{{ vault_mysql_root_password }}"
```

```yaml
# /tp/group_vars/db/vault.yml  — CHIFFRÉ
---
vault_mysql_root_password: "R00tS3cr3t!2024"
vault_mysql_app_password: "AppP@ssw0rd!2024"
```

**Test :**

```bash
ansible-playbook site.yml --ask-vault-pass --tags mysql
```

**Pourquoi ce pattern est le standard :**

| Avantage | Détail |
|:---|:---|
| **Structure lisible** | On voit quelles variables existent sans ouvrir le coffre |
| **`git diff` exploitable** | Les changements de structure sont visibles en clair |
| **Coffre minimal** | Seules les **valeurs** sensibles sont chiffrées |
| **Convention `vault_`** | Le préfixe rend la provenance évidente à la lecture |
| **Revue de code possible** | Un relecteur valide la logique sans avoir le mot de passe |

> 🔑 **La convention de nommage `vault_<nom>`** est universellement adoptée. Quand vous
> lisez `password: "{{ vault_mysql_app_password }}"`, vous savez immédiatement que la valeur
> vient d'un coffre.

</details>

---

### 3. Automatisez la saisie du mot de passe avec un `vault-password-file`.

<details><summary>Correction</summary>

Taper le mot de passe à chaque exécution est impraticable, et impossible en CI/CD.

```bash
# Créer le fichier de mot de passe — JAMAIS versionné
echo 'Formation2024!' > ~/.vault_pass
chmod 600 ~/.vault_pass
```

**Trois façons de l'utiliser :**

```bash
# 1. En ligne de commande
ansible-playbook site.yml --vault-password-file ~/.vault_pass

# 2. Par variable d'environnement
export ANSIBLE_VAULT_PASSWORD_FILE=~/.vault_pass
ansible-playbook site.yml

# 3. Dans ansible.cfg — LA MÉTHODE RECOMMANDÉE pour un projet
```

```ini
# /tp/ansible.cfg
[defaults]
inventory = /tp/inventory.yml
roles_path = /tp/roles
remote_user = admin
host_key_checking = False
stdout_callback = yaml
vault_password_file = ~/.vault_pass
```

```bash
ansible-playbook site.yml        # plus aucune invite
```

**Variante avancée — un script au lieu d'un fichier :**

```bash
cat > ~/.vault_pass.sh <<'EOF'
#!/bin/bash
# Le mot de passe peut venir d'un gestionnaire de secrets d'entreprise
# Exemples :
#   vault kv get -field=ansible secret/infra          (HashiCorp Vault)
#   aws secretsmanager get-secret-value --secret-id ansible --query SecretString
#   op read "op://Infra/ansible-vault/password"       (1Password CLI)
echo "${ANSIBLE_VAULT_PASS:-Formation2024!}"
EOF
chmod 700 ~/.vault_pass.sh

ansible-playbook site.yml --vault-password-file ~/.vault_pass.sh
```

Ansible détecte qu'il s'agit d'un exécutable et l'appelle au lieu de lire son contenu.

> 🔑 **C'est le mécanisme d'intégration avec un gestionnaire de secrets d'entreprise.**
> En CI/CD, le pipeline injecte le mot de passe via une variable protégée, le script le
> récupère, et aucun secret ne touche jamais le disque.

> ⚠️ `~/.vault_pass` doit être en `600`, hors du dépôt Git, et **jamais** dans un
> répertoire partagé comme `/tp`.

</details>

---

## Partie 3 — Chiffrer une variable isolée

### 1. Utilisez `encrypt_string` pour chiffrer **une seule valeur** dans un fichier qui reste lisible.

<details><summary>Correction</summary>

```bash
cd /tp

ansible-vault encrypt_string \
  --vault-password-file ~/.vault_pass \
  'MonMotDePasseAPI-2024' \
  --name 'api_token'
```

Sortie à copier-coller dans un fichier YAML normal :

```yaml
api_token: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          62313365396662343061393464336163383764373764613633653634306232
          6238653136353362320a636164323265306439393764333730663936623431
          3838663139653261650a393163353837343233623063326131396235323932
```

**Intégration dans un fichier en clair :**

```yaml
# /tp/group_vars/web/vars.yml
---
app_name: monapp
app_port: 80
app_debug: false

# Cette SEULE valeur est chiffrée, le reste du fichier est lisible
api_token: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          62313365396662343061393464336163383764373764613633653634306232
          6238653136353362320a636164323265306439393764333730663936623431
          3838663139653261650a393163353837343233623063326131396235323932
```

**Test :**

```yaml
# /tp/playbooks/40-vault.yml
---
- name: Utilisation d'une variable chiffrée
  hosts: web
  gather_facts: no

  tasks:
    - name: Afficher le token (masqué)
      ansible.builtin.debug:
        msg: "Token chargé, longueur : {{ api_token | length }} caractères"

    - name: Utiliser le token dans un appel
      ansible.builtin.uri:
        url: "https://api.exemple.com/v1/status"
        headers:
          Authorization: "Bearer {{ api_token }}"
      no_log: true                # ← ne PAS écrire le header dans les logs
      failed_when: false
```

```bash
ansible-playbook playbooks/40-vault.yml
```

**Chiffrement de fichier vs `encrypt_string` :**

| | Fichier entier (`encrypt`) | `encrypt_string` |
|:---|:---|:---|
| Lisibilité du fichier | ❌ Tout est illisible | ✅ Seule la valeur est chiffrée |
| `git diff` | ❌ Inexploitable | ✅ Les autres lignes restent lisibles |
| Nombre de secrets | Beaucoup | 1 à 3 valeurs isolées |
| Cas d'usage | `vault.yml` dédié | Un token perdu dans une config |

> 💡 **Astuce :** lire la valeur depuis stdin évite qu'elle reste dans l'historique du
> shell.
>
> ```bash
> ansible-vault encrypt_string --stdin-name 'api_token'
> # tapez la valeur, puis Ctrl+D
> ```

</details>

---

### 2. Protégez la sortie avec `no_log`. Démontrez la fuite sans lui.

<details><summary>Correction</summary>

```yaml
# /tp/playbooks/41-nolog.yml
---
- name: Démonstration de la fuite de secrets
  hosts: node1
  gather_facts: no

  vars:
    mot_de_passe: "SuperSecret123"

  tasks:
    # ❌ FUITE : le mot de passe apparaît en clair avec -v
    - name: Tâche NON protégée
      ansible.builtin.debug:
        msg: "Connexion avec le mot de passe {{ mot_de_passe }}"

    # ❌ FUITE : la commande complète est journalisée
    - name: Commande NON protégée
      ansible.builtin.command: "echo {{ mot_de_passe }}"
      changed_when: false

    # ✅ PROTÉGÉ
    - name: Tâche protégée
      ansible.builtin.command: "echo {{ mot_de_passe }}"
      changed_when: false
      no_log: true
```

```bash
ansible-playbook playbooks/41-nolog.yml -v
```

La tâche protégée affiche :

```
TASK [Tâche protégée] ****
ok: [node1] => {"censored": "the output has been hidden due to the fact that
'no_log: true' was specified for this result"}
```

**Où appliquer `no_log` systématiquement :**

| Situation | Exemple |
|:---|:---|
| Création d'utilisateur avec mot de passe | `mysql_user`, `user` |
| Appel d'API avec token | `uri` avec header `Authorization` |
| Toute boucle sur une liste de secrets | `loop: "{{ secrets }}"` |
| `command`/`shell` recevant un secret en argument | `command: "mysql -p{{ pass }}"` |

**Au niveau du play entier :**

```yaml
- name: Play sensible
  hosts: db
  no_log: true          # toutes les tâches du play sont masquées
```

> ⚠️ **`no_log` complique le débogage** : en cas d'échec, vous n'avez plus le détail.
> Technique courante — le désactiver temporairement par une variable :
>
> ```yaml
> no_log: "{{ not (debug_mode | default(false)) }}"
> ```
> ```bash
> ansible-playbook site.yml -e debug_mode=true    # débogage ponctuel
> ```

> ⚠️ **`no_log` ne protège pas de tout.** Un secret passé en argument d'une commande shell
> reste visible dans la table des processus (`ps aux`) **sur la machine cible** pendant
> l'exécution. Pour les cas critiques, passez par un fichier temporaire en `0600` ou par
> l'entrée standard du programme.

</details>

---

## Partie 4 — Coffres multiples avec `vault-id`

### 1. Créez deux coffres distincts (dev et production) avec des mots de passe différents.

<details><summary>Correction</summary>

```bash
cd /tp
mkdir -p group_vars/all

# Deux mots de passe distincts
echo 'DevPass2024'  > ~/.vault_pass_dev
echo 'ProdPass2024' > ~/.vault_pass_prod
chmod 600 ~/.vault_pass_dev ~/.vault_pass_prod

# Coffre DEV
ansible-vault create --vault-id dev@~/.vault_pass_dev group_vars/all/vault_dev.yml
```

```yaml
---
vault_db_password: "dev-password-sans-importance"
vault_api_key: "dev-key-12345"
```

```bash
# Coffre PRODUCTION
ansible-vault create --vault-id prod@~/.vault_pass_prod group_vars/all/vault_prod.yml
```

```yaml
---
vault_db_password: "Pr0d-P@ssw0rd-Tr3s-S3cur1se!"
vault_api_key: "prod-key-reelle-a-proteger"
```

**Observation — l'en-tête porte désormais l'identifiant du coffre :**

```bash
head -1 group_vars/all/vault_dev.yml
# $ANSIBLE_VAULT;1.2;AES256;dev

head -1 group_vars/all/vault_prod.yml
# $ANSIBLE_VAULT;1.2;AES256;prod
```

**Utilisation :**

```bash
# Fournir les deux identités : Ansible choisit la bonne pour chaque fichier
ansible-playbook site.yml \
  --vault-id dev@~/.vault_pass_dev \
  --vault-id prod@~/.vault_pass_prod

# Ou seulement dev — le fichier prod restera illisible
ansible-playbook site.yml --vault-id dev@~/.vault_pass_dev
```

**Configuration permanente :**

```ini
# /tp/ansible.cfg
[defaults]
vault_identity_list = dev@~/.vault_pass_dev, prod@~/.vault_pass_prod
```

> 🔑 **L'intérêt réel des vault-id :** séparer les habilitations. L'équipe de développement
> reçoit `~/.vault_pass_dev` uniquement. Le mot de passe de production reste dans le
> coffre-fort de l'équipe d'exploitation et n'est injecté que par la CI/CD. Le même dépôt
> Git sert aux deux, sans que les développeurs puissent lire les secrets de production.

</details>

---

### 2. Effectuez une rotation de clé de coffre.

<details><summary>Correction</summary>

```bash
# Changer le mot de passe d'un coffre
ansible-vault rekey group_vars/db/vault.yml
# Ancien mot de passe : Formation2024!
# Nouveau mot de passe : NouveauMotDePasse2025!

# Version non interactive
ansible-vault rekey \
  --vault-password-file ~/.vault_pass \
  --new-vault-password-file ~/.vault_pass_nouveau \
  group_vars/db/vault.yml

# Rotation de TOUS les coffres du projet
find /tp -name "vault*.yml" -exec \
  ansible-vault rekey \
    --vault-password-file ~/.vault_pass \
    --new-vault-password-file ~/.vault_pass_nouveau {} \;
```

**Quand effectuer une rotation :**

| Déclencheur | Urgence |
|:---|:---|
| Départ d'un collaborateur ayant accès au coffre | **Immédiate** |
| Suspicion de fuite du mot de passe | **Immédiate** |
| Politique de sécurité interne | Périodique (6-12 mois) |
| Fin de mission d'un prestataire | À la clôture |

> ⚠️ **`rekey` ne change que le mot de passe du coffre, pas les secrets qu'il contient.**
> Si le contenu du coffre a fuité, il faut **aussi** changer les mots de passe applicatifs
> eux-mêmes (`ansible-vault edit` puis redéploiement).

</details>

---

## Partie 5 — Intégration Git

### 1. Configurez le dépôt pour qu'aucun secret ne puisse être committé par accident.

<details><summary>Correction</summary>

```bash
cd /tp
git init 2>/dev/null

cat > .gitignore <<'EOF'
# ============================================================
# SECRETS — ne JAMAIS versionner
# ============================================================
.vault_pass
.vault_pass_*
*.vault_pass
vault-password*
.secrets/

# Clés privées et certificats
*.pem
*.key
!*.pub
id_rsa*
id_ed25519*

# Fichiers déchiffrés par erreur
*_decrypted.yml
*.yml.clear

# ============================================================
# Artefacts Ansible
# ============================================================
*.retry
.ansible/
facts_cache/

# Rôles installés depuis Galaxy (réinstallables via requirements.yml)
roles/geerlingguy.*
roles/community.*
collections/

# ============================================================
# Environnement
# ============================================================
.venv/
__pycache__/
.DS_Store
*.swp
EOF
```

**Rendre les fichiers Vault lisibles dans `git diff` :**

```bash
cat > .gitattributes <<'EOF'
# Affiche le contenu DÉCHIFFRÉ dans git diff (pour les relecteurs habilités)
*vault*.yml diff=ansible-vault merge=binary
group_vars/*/vault.yml diff=ansible-vault merge=binary
EOF

# Configurer le driver de diff
git config --local diff.ansible-vault.textconv \
  "ansible-vault view --vault-password-file $HOME/.vault_pass"
```

Désormais `git diff group_vars/db/vault.yml` affiche les modifications **en clair** pour qui
possède le mot de passe — et du charabia chiffré pour les autres.

**Vérification avant le premier commit :**

```bash
git add -A
git status --short

# CONTRÔLE CRITIQUE : aucun fichier de mot de passe ne doit apparaître
git status --short | grep -iE "vault_pass|\.key$|\.pem$" && \
  echo "⛔ DANGER : un secret est sur le point d'être committé" || \
  echo "✅ Aucun fichier de mot de passe indexé"

# Vérifier que les fichiers vault sont bien chiffrés
for f in $(git diff --cached --name-only | grep vault); do
  head -1 "$f" | grep -q '\$ANSIBLE_VAULT' \
    && echo "✅ $f chiffré" \
    || echo "⛔ $f EN CLAIR"
done
```

</details>

---

### 2. Mettez en place un hook de pré-commit qui bloque les secrets en clair.

<details><summary>Correction</summary>

```bash
cat > /tp/.git/hooks/pre-commit <<'EOF'
#!/bin/bash
# Bloque le commit si un secret en clair est détecté
set -e

ERREURS=0

# --- 1. Fichiers vault non chiffrés ---
for f in $(git diff --cached --name-only --diff-filter=ACM | grep -i vault); do
  if [ -f "$f" ] && ! head -1 "$f" | grep -q '\$ANSIBLE_VAULT'; then
    echo "⛔ $f porte 'vault' dans son nom mais N'EST PAS CHIFFRÉ"
    ERREURS=1
  fi
done

# --- 2. Fichiers de mot de passe ---
if git diff --cached --name-only | grep -qE "vault_pass|\.pem$|\.key$"; then
  echo "⛔ Un fichier de mot de passe ou de clé privée est indexé"
  ERREURS=1
fi

# --- 3. Secrets en clair dans les YAML ---
MOTIF='(password|passwd|secret|token|api_key)\s*:\s*["'"'"']?[A-Za-z0-9!@#$%^&*_-]{8,}'
for f in $(git diff --cached --name-only --diff-filter=ACM | grep -E '\.ya?ml$'); do
  [ -f "$f" ] || continue
  head -1 "$f" | grep -q '\$ANSIBLE_VAULT' && continue          # coffre : OK
  if grep -qniE "$MOTIF" "$f" | grep -qv '{{'; then
    echo "⛔ Secret potentiel en clair dans $f :"
    grep -niE "$MOTIF" "$f" | grep -v '{{' | head -3
    ERREURS=1
  fi
done

if [ "$ERREURS" -ne 0 ]; then
  echo ""
  echo "Commit refusé. Chiffrez les secrets avec ansible-vault."
  echo "Pour forcer malgré tout (déconseillé) : git commit --no-verify"
  exit 1
fi

echo "✅ Aucun secret en clair détecté"
EOF

chmod +x /tp/.git/hooks/pre-commit
```

**Test :**

```bash
# Tenter de committer un secret
echo 'db_password: "MotDePasseEnClair123"' > /tp/mauvais.yml
git add /tp/mauvais.yml
git commit -m "test"      # → refusé par le hook

rm /tp/mauvais.yml
git reset
```

> 💡 En équipe, utilisez plutôt un outil dédié partagé par tous :
> * **[pre-commit](https://pre-commit.com/)** avec les hooks `detect-secrets` ou `gitleaks`
> * **[gitleaks](https://github.com/gitleaks/gitleaks)** en étape de CI
>
> Un hook local n'est pas versionné et chaque développeur doit l'installer — c'est sa
> principale limite.

</details>

---

### 3. Vérifiez le déploiement complet avec les secrets chiffrés.

<details><summary>Correction</summary>

```bash
cd /tp

# Aucune invite : le mot de passe vient de ansible.cfg
ansible-playbook site.yml

# Vérifier que la base est bien créée avec le mot de passe du coffre
ansible db -m shell \
  -a "mysql -e \"SELECT User,Host FROM mysql.user WHERE User='monapp';\"" --become

# Tester la connexion applicative avec le mot de passe du coffre
ansible db -m shell \
  -a "mysql -u monapp -p'{{ vault_mysql_app_password }}' -e 'SHOW DATABASES;'" \
  --become --no-log 2>/dev/null || echo "Test effectué"

# Contrôle final : plus aucun secret en clair
grep -rniE "password.*:.*['\"][A-Za-z0-9!@#$%]{8,}" \
     --include="*.yml" . 2>/dev/null | grep -v '{{' | grep -v geerlingguy
# → doit ne rien renvoyer
```

**Bilan de la structure sécurisée :**

```
/tp
├── .gitignore                      ← bloque les fichiers de mot de passe
├── .gitattributes                  ← git diff lisible pour les habilités
├── ansible.cfg                     ← vault_password_file
├── group_vars/
│   ├── all/
│   │   ├── vault_dev.yml           🔒 chiffré (id: dev)
│   │   └── vault_prod.yml          🔒 chiffré (id: prod)
│   └── db/
│       ├── vars.yml                📖 en clair — structure lisible
│       └── vault.yml               🔒 chiffré — valeurs sensibles
└── ~/.vault_pass                   🔑 HORS du dépôt, chmod 600
```

</details>

---

## À retenir

| Point clé | Détail |
|:---|:---|
| **Un secret committé = compromis** | Le supprimer ne suffit pas : il faut le **révoquer**. |
| **Pattern `vars.yml` + `vault.yml`** | Structure lisible + valeurs chiffrées. Le standard. |
| **Convention `vault_<nom>`** | Rend la provenance évidente à la lecture. |
| **`encrypt_string`** | Pour 1 à 3 valeurs isolées dans un fichier qui reste lisible. |
| **`vault_password_file`** | Dans `ansible.cfg`. Le fichier reste **hors du dépôt**, en `600`. |
| **Script de mot de passe** | Point d'intégration avec HashiCorp Vault, AWS Secrets Manager… |
| **`vault-id`** | Sépare les habilitations dev / production dans un même dépôt. |
| **`no_log: true`** | Sur toute tâche manipulant un secret. Ne protège pas de `ps aux`. |
| **`.gitignore`** | `*vault_pass*`, `*.pem`, `*.key` — la première ligne de défense. |
| **`rekey`** | Change le mot de passe du coffre, **pas** les secrets qu'il contient. |

### Les commandes du lab

```bash
ansible-vault create fichier.yml                  # créer chiffré
ansible-vault edit fichier.yml                    # éditer (jamais en clair sur disque)
ansible-vault view fichier.yml                    # consulter
ansible-vault encrypt / decrypt fichier.yml       # (dé)chiffrer un fichier existant
ansible-vault rekey fichier.yml                   # rotation du mot de passe
ansible-vault encrypt_string --stdin-name 'nom'   # chiffrer UNE valeur
ansible-playbook site.yml --ask-vault-pass
ansible-playbook site.yml --vault-password-file ~/.vault_pass
ansible-playbook site.yml --vault-id prod@~/.vault_pass_prod
```

---

⬅️ **Lab précédent :** [Lab 07 — Rôles et Ansible Galaxy](<../lab 07 - Rôles et Ansible Galaxy/instructions.md>)
➡️ **Lab suivant :** [Lab 09 — Orchestration avancée et rolling update](<../lab 09 - Orchestration avancée et rolling update/instructions.md>)
