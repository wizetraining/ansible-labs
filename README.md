# Formation Ansible — 2 jours : Labs

> De débutant à expert · 11 modules · 11 labs · 1 nœud de contrôle + 3 nœuds cibles

Ce dépôt contient les travaux pratiques de la formation **Automatisation avec Ansible**.
Chaque module du support de cours est suivi d'un lab qui met immédiatement en pratique les
notions vues. Les corrections sont masquées dans des blocs dépliables `<details>` : essayez
**toujours** de résoudre l'exercice avant de les ouvrir.

---

## Parcours pédagogique

### Jour 1 — Des fondamentaux au premier déploiement

| Module | Thème | Lab associé | Durée |
|:---|:---|:---|:---|
| M1 | Fondamentaux : IaC, DevOps & positionnement d'Ansible | [Lab 01 — Mise en place de l'environnement](<lab 01 - Mise en place de l'environnement/instructions.md>) | 45 min |
| M2 | Architecture, configuration & inventaires | [Lab 02 — Installation, SSH et inventaires](<lab 02 - Installation, SSH et inventaires/instructions.md>) | 45 min |
| M3 | Commandes ad-hoc, modules & idempotence | [Lab 03 — Commandes ad-hoc et idempotence](<lab 03 - Commandes ad-hoc et idempotence/instructions.md>) | 45 min |
| M4 | Playbooks : structure, variables & handlers | [Lab 04 — Premier playbook et stack LAMP](<lab 04 - Premier playbook et stack LAMP/instructions.md>) | 120 min |
| M5 | Contrôle du flux : conditions, boucles, blocks, tags | [Lab 05 — Contrôle du flux et gestion des erreurs](<lab 05 - Contrôle du flux et gestion des erreurs/instructions.md>) | 60 min |

### Jour 2 — Industrialisation et expertise

| Module | Thème | Lab associé | Durée |
|:---|:---|:---|:---|
| M6 | Variables avancées, facts & templating Jinja2 | [Lab 06 — Templating Jinja2 et facts](<lab 06 - Templating Jinja2 et facts/instructions.md>) | 60 min |
| M7 | Rôles, Galaxy & collections | [Lab 07 — Rôles et Ansible Galaxy](<lab 07 - Rôles et Ansible Galaxy/instructions.md>) | 60 min |
| M8 | Ansible Vault & gestion des secrets | [Lab 08 — Ansible Vault et gestion des secrets](<lab 08 - Ansible Vault et gestion des secrets/instructions.md>) | 45 min |
| M9 | Orchestration avancée & fiabilité | [Lab 09 — Orchestration avancée et rolling update](<lab 09 - Orchestration avancée et rolling update/instructions.md>) | 60 min |
| M10 | Extensibilité : modules, plugins, filtres & lint | [Lab 10 — Module custom et qualité de code](<lab 10 - Module custom et qualité de code/instructions.md>) | 45 min |
| M11 | Industrialisation : Git, CI/CD & Automation Platform | [Lab 11 — Projet final industrialisation](<lab 11 - Projet final industrialisation/instructions.md>) | 90 min |

---

## Topologie du lab

```
                  ┌──────────────────────────┐
                  │      controller          │  Ansible installé ici
                  │    192.168.56.20         │  → on travaille TOUJOURS depuis cette machine
                  └────────────┬─────────────┘
                               │ SSH (agentless)
          ┌────────────────────┼────────────────────┐
          │                    │                    │
   ┌──────┴──────┐      ┌──────┴──────┐      ┌──────┴──────┐
   │   node1     │      │   node2     │      │   node3     │
   │192.168.56.21│      │192.168.56.22│      │192.168.56.23│
   │   [web]     │      │   [web]     │      │    [db]     │
   └─────────────┘      └─────────────┘      └─────────────┘
```

**Groupes d'inventaire utilisés tout au long de la formation :**

| Groupe | Membres | Rôle |
|:---|:---|:---|
| `web` | node1, node2 | Serveurs Apache/Nginx |
| `db` | node3 | Serveur MySQL/MariaDB |
| `prod` | node1, node2, node3 | Groupe de groupes (`web` + `db`) |

---

## Installation de l'environnement

Deux options : **Vagrant** (recommandé, environnement le plus proche de la production) ou
**Docker/Podman** (démarrage plus rapide, utile si VirtualBox n'est pas disponible).

### Option A — Vagrant + VirtualBox

**Prérequis :**
* [Vagrant](https://www.vagrantup.com/downloads)
* [VirtualBox](https://www.virtualbox.org/wiki/Downloads)

```bash
cd 0-setup
vagrant up          # ~10 min au premier lancement
vagrant status      # les 4 VMs doivent être "running"
```

Connexion au nœud de contrôle :

```bash
vagrant ssh controller
```

> Le répertoire `0-setup/tp` de votre machine hôte est monté sur `/tp` dans la VM
> `controller`. Vous pouvez donc éditer vos fichiers YAML avec votre éditeur préféré
> et les retrouver immédiatement dans la VM.

**Commandes Vagrant utiles :**

```bash
vagrant halt              # arrêter les VMs (fin de journée)
vagrant up                # les redémarrer
vagrant reload node1      # redémarrer un nœud
vagrant destroy -f        # tout supprimer et repartir de zéro
vagrant ssh node1         # se connecter à un nœud cible
```

### Option B — Docker / Podman

Utile sur les machines sans VirtualBox (notamment Apple Silicon récent). Les conteneurs
tournent avec `systemd` afin que les modules `service`/`systemd` d'Ansible fonctionnent
comme sur une vraie VM.

```bash
cd 0-setup/docker
docker compose up -d --build      # ou : podman-compose up -d --build
docker compose ps
```

Connexion au nœud de contrôle :

```bash
docker exec -it controller bash
```

**Commandes utiles :**

```bash
docker compose stop               # arrêter
docker compose start              # redémarrer
docker compose down -v            # tout supprimer
docker exec -it node1 bash        # se connecter à un nœud cible
```

> ⚠️ **Limites de l'option Docker** : le réseau est un bridge Docker (`172.28.0.0/16`) et non
> `192.168.56.0/24`. Les labs référencent les nœuds par leur **nom** (`node1`, `node2`,
> `node3`), donc tout fonctionne à l'identique. Seuls les exercices affichant explicitement
> une adresse IP donneront des valeurs différentes — c'est sans impact pédagogique.

---

## Comptes et accès

| Élément | Valeur |
|:---|:---|
| Utilisateur de travail | `vagrant` (Vagrant) / `root` (Docker) |
| Utilisateur applicatif | `admin` / mot de passe `admin` |
| Escalade de privilèges | `sudo` sans mot de passe pour `vagrant` et `admin` |
| Répertoire de travail | `/tp` sur le controller |

---

## Conventions des labs

Chaque lab suit la même structure :

* **En-tête** — niveau de difficulté, durée estimée, module de rattachement
* **Objectifs pédagogiques** — ce que vous saurez faire à la fin
* **Notions abordées** — les concepts Ansible travaillés
* **Documentation de référence** — liens officiels à consulter
* **Contexte** — la mise en situation réaliste
* **Parties numérotées** — les exercices progressifs
* **À retenir** — la synthèse des pièges et bonnes pratiques

Les corrections sont systématiquement masquées :

```markdown
<details><summary>Correction</summary>

... la solution ...

</details>
```

---

## Vérifier que tout fonctionne

Depuis le nœud de contrôle, après avoir terminé le Lab 02 :

```bash
ansible all -m ping
```

Résultat attendu :

```
node1 | SUCCESS => { "changed": false, "ping": "pong" }
node2 | SUCCESS => { "changed": false, "ping": "pong" }
node3 | SUCCESS => { "changed": false, "ping": "pong" }
```

---

## Remise à zéro entre deux labs

Certains labs installent des paquets. Pour repartir d'un état propre :

```bash
# Depuis le controller
ansible-playbook /tp/playbooks/reset.yml
```

Ou, plus radicalement :

```bash
vagrant destroy -f && vagrant up      # Vagrant
docker compose down -v && docker compose up -d --build   # Docker
```
