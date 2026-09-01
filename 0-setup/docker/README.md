# Variante Docker / Podman

Alternative à Vagrant pour les postes sans VirtualBox (Apple Silicon récent, WSL2, CI…).

## Démarrage

```bash
docker compose up -d --build
docker compose ps          # controller, node1, node2, node3 doivent être "Up"
docker exec -it controller bash
```

Avec Podman :

```bash
podman-compose up -d --build
podman exec -it controller bash
```

## Différences avec la version Vagrant

| Point | Vagrant | Docker |
|:---|:---|:---|
| Réseau | `192.168.56.0/24` | `172.28.0.0/16` |
| Utilisateur par défaut | `vagrant` | `root` |
| Nœuds joignables par nom | ✅ `node1`, `node2`, `node3` | ✅ identique |
| Compte `admin` / `admin` | ✅ | ✅ |
| `sudo` sans mot de passe | ✅ | ✅ |
| Modules `service` / `systemd` | ✅ | ✅ (systemd actif dans les conteneurs) |
| Répertoire partagé | `/tp` | `/tp` |

**Les labs sont écrits pour fonctionner à l'identique sur les deux environnements.**
Ils référencent les nœuds par leur nom (`node1`…), jamais par leur IP — sauf quand
l'exercice porte justement sur la découverte d'adresses (`ansible_default_ipv4.address`),
auquel cas vous obtiendrez simplement des valeurs en `172.28.x.x`.

## Prérequis techniques

Les conteneurs cibles tournent en `privileged: true` avec `cgroup: host` car **systemd**
doit pouvoir démarrer à l'intérieur. C'est indispensable pour que `service`, `systemd`
et les **handlers** se comportent comme sur une vraie machine.

Si `systemctl` renvoie `Failed to connect to bus` dans un nœud :

```bash
docker compose down -v
docker compose up -d --build
docker exec -it node1 systemctl is-system-running    # doit répondre running ou degraded
```

## Nettoyage

```bash
docker compose down -v          # supprime conteneurs + réseau + volumes
```
