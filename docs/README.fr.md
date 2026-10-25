# tor-dns-shield (Français)

[English](../README.md) · [Italiano](README.it.md)

**DNS privé via Tor (Snowflake / obfs4 / direct), avec exclusion des pays de sortie, AdGuard Home optionnel et proxy Snowflake bénévole optionnel.**

Un seul script interactif : vous choisissez les pays dont vous voulez éviter les nœuds de sortie, le résolveur amont et le transport. Il génère un `docker-compose.yml` et démarre tout.

```
appareils ──> [AdGuard Home] ──> dnscrypt-proxy ──> Tor (bridge Snowflake) ──> Quad9 / autre
                optionnel         DoH/DNSCrypt        pays de sortie exclu
```

## Ce que ça protège, et ce que ça ne protège pas

- Protège : le résolveur ne voit pas votre IP (il voit une sortie Tor) ; avec Snowflake, votre FAI ne voit pas de connexions vers les relais Tor connus ; les requêtes DNS sont chiffrées de bout en bout.
- Ne protège pas : votre FAI voit toujours les adresses IP auxquelles vous vous connectez ; les métadonnées de navigation (SNI, empreintes) ne sont pas masquées ; aucune protection contre un adversaire global.

C'est de la **confidentialité DNS et de la résilience**, pas de l'anonymat.

## Pourquoi ce projet existe

Les résolveurs publics reçoivent de plus en plus d'ordres judiciaires de blocage de domaines. Quad9 s'y est publiquement opposé : il a gagné en 2023 un procès intenté par Sony Music en Allemagne, et il a annoncé qu'il cessera de servir les utilisateurs en France à partir du 24 novembre plutôt que de bloquer des domaines (vérifiez la [page presse de Quad9](https://quad9.net/news/press/) avant de vous y fier). Quel que soit votre avis sur ces affaires, le point technique reste : du DNS chiffré via Tor, avec des sorties hors d'un pays donné, est un bon réglage par défaut pour tout le monde.

Le projet ne prend pas position au-delà. L'installateur fonctionne de la même façon quel que soit le pays choisi.

## Installation

Ne jamais exécuter un script téléchargé sans l'avoir lu : téléchargez, lisez, vérifiez, exécutez.

```bash
git clone https://github.com/thotganesh/tor-dns-shield && cd tor-dns-shield
sha256sum -c SHA256SUMS   # détecte une copie corrompue, pas une falsification
less install.sh
sudo ./install.sh
```

Exemple non interactif :

```bash
sudo ./install.sh --non-interactive --countries fr,it --resolver quad9 --transport snowflake --adguard
```

`--dry-run` affiche les fichiers générés sans rien modifier. `--countries` accepte n'importe quel code ISO à deux lettres (aujourd'hui `fr`, demain `it` ou un autre) et `none` pour aucune exclusion.

## Snowflake : deux choses différentes

1. **Client Snowflake** (dans le conteneur `tor`) : c'est *vous* qui l'utilisez pour joindre Tor sans que votre FAI voie de connexions vers les relais Tor.
2. **Proxy Snowflake** (conteneur séparé, optionnel) : utilisé par **d'autres personnes** dans des pays qui bloquent Tor. Ce n'est pas votre point d'entrée et il n'améliore pas votre propre confidentialité ; le refuser ne change rien pour vous.

### Proxy bénévole : ce qu'il fait, voit, coûte

- Il relaie du trafic chiffré : vous n'êtes pas un nœud de sortie et vous ne pouvez pas le lire.
- Votre adresse IP publique est visible des personnes qui passent par vous.
- Il consomme de la bande passante (en proportion de `--capacity`) ; vérifiez les conditions de votre hébergeur.
- Il est présélectionné parce qu'il aide le réseau ; pour refuser, répondez Non (ou utilisez `--no-snowflake-proxy`).

## Sécurité

- Le port 53 est publié sur `127.0.0.1`. Avec `--listen-ip` sur une adresse réseau, limitez l'accès par pare-feu, sinon vous exploitez un résolveur ouvert.
- L'interface d'AdGuard est sur `127.0.0.1:3000` (utilisez un tunnel SSH).
- AdGuard Home doit utiliser dnscrypt-proxy (`172.28.0.11:5353`) comme **seul** amont et n'avoir aucun DNS de secours : ses valeurs par défaut sont des connexions directes qui contournent Tor. En mode interactif, l'installateur ouvre l'assistant, attend que vous ayez terminé puis règle l'amont lui-même (`scripts/adguard-upstream.sh`, relançable). `scripts/selftest.sh` signale une erreur si l'amont ou le secours d'AdGuard contournent Tor.
- **Si vous avez installé v0.1.0/v0.1.1 avec AdGuard :** l'amont par défaut était une connexion DoH *directe* vers Quad9, donc le DNS ne passait pas par Tor sauf modification manuelle. Mettez à jour et relancez `sudo ./install.sh`, ou exécutez `sudo /opt/tor-dns-shield/scripts/adguard-upstream.sh`.
- Le SOCKS de Tor n'est jamais publié sur l'hôte.
- `StrictNodes 1` : si aucun circuit ne peut être construit, le DNS s'arrête plutôt que d'utiliser des nœuds exclus. C'est voulu.

Limites connues : une seule instance Tor (pas encore de basculement) ; AdGuard demande son assistant de première configuration (l'installateur l'ouvre, attend et règle l'amont ; avec `--non-interactive`, lancez ensuite `scripts/adguard-upstream.sh`) ; les paramètres des bridges Snowflake changent avec le temps.

Licence MIT. Vous êtes responsable du respect des lois de votre pays.
