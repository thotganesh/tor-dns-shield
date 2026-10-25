# tor-dns-shield (Italiano)

[English](../README.md) · [Français](README.fr.md)

**DNS privato via Tor (Snowflake / obfs4 / diretto), con esclusione dei paesi di uscita, AdGuard Home opzionale e proxy Snowflake volontario opzionale.**

Uno script interattivo: scegli i paesi da evitare come nodo di uscita, il resolver a monte e il trasporto. Lo script genera un `docker-compose.yml` e avvia tutto.

```
dispositivi ──> [AdGuard Home] ──> dnscrypt-proxy ──> Tor (bridge Snowflake) ──> Quad9 / altro
                 opzionale          DoH/DNSCrypt         paese di uscita escluso
```

## Cosa protegge e cosa no

- Protegge: il resolver non vede il tuo IP; con Snowflake il tuo ISP non vede connessioni ai relay Tor noti; le query DNS sono cifrate.
- Non protegge: il tuo ISP vede comunque gli IP a cui ti connetti; non nasconde i metadati di navigazione e non protegge da avversari globali.

È **privacy DNS e resilienza**, non anonimato.

## Installazione

Non eseguire script scaricati alla cieca: scarica, leggi, verifica, esegui.

```bash
git clone https://github.com/thotganesh/tor-dns-shield && cd tor-dns-shield
sha256sum -c SHA256SUMS   # rileva solo file corrotti, non manomissioni
less install.sh
sudo ./install.sh
```

Esempio non interattivo:

```bash
sudo ./install.sh --non-interactive --countries fr,it --resolver quad9 --transport snowflake --adguard
```

Con `--dry-run` vedi i file generati senza cambiare nulla. `--countries` accetta qualsiasi codice ISO a due lettere (oggi `fr`, domani `it` o altro) e `none` per nessuna esclusione.

## Snowflake: due cose diverse

1. **Client Snowflake** (nel container `tor`): lo usi tu per raggiungere Tor senza che l'ISP veda connessioni ai relay Tor.
2. **Proxy Snowflake** (container separato, opzionale): lo usano **altre persone** in paesi che bloccano Tor. Non è il tuo punto di ingresso e non migliora la tua privacy; rifiutarlo non cambia nulla per te.

### Proxy volontario: cosa fa, cosa vede, quanto costa

- Fa da ponte per traffico cifrato: non sei un nodo di uscita e non puoi leggerlo.
- Il tuo IP pubblico è visibile agli utenti che passano da te.
- Consuma banda (in proporzione a `--capacity`); controlla le condizioni del tuo hosting.
- È preselezionato perché aiuta la rete; per rifiutare basta rispondere No (o usare `--no-snowflake-proxy`).

## Sicurezza

- La porta 53 è pubblicata su `127.0.0.1`. Se usi `--listen-ip` con un IP di rete, limita l'accesso con il firewall, altrimenti sei un open resolver.
- L'interfaccia di AdGuard è su `127.0.0.1:3000` (usa un tunnel SSH).
- AdGuard Home deve usare dnscrypt-proxy (`172.28.0.11:5353`) come **unico** upstream e non avere DNS di fallback: i suoi default sono connessioni dirette che aggirano Tor. In modalità interattiva l'installer apre il wizard, aspetta che tu finisca e imposta l'upstream da solo (`scripts/adguard-upstream.sh`, rieseguibile). `scripts/selftest.sh` segnala un errore se l'upstream o il fallback di AdGuard aggirano Tor.
- **Se hai installato v0.1.0/v0.1.1 con AdGuard:** l'upstream predefinito era una connessione DoH *diretta* verso Quad9, quindi il DNS non passava da Tor a meno di averlo cambiato a mano. Aggiorna e rilancia `sudo ./install.sh`, oppure esegui `sudo /opt/tor-dns-shield/scripts/adguard-upstream.sh`.
- Il SOCKS di Tor non è mai pubblicato sull'host.
- `StrictNodes 1`: se non si riesce a costruire un circuito, il DNS si ferma invece di usare nodi esclusi. È voluto.

Limiti noti: una sola istanza Tor (failover non ancora implementato); AdGuard richiede il wizard al primo avvio (l'installer lo apre, aspetta e imposta l'upstream; con `--non-interactive` esegui poi `scripts/adguard-upstream.sh`); i parametri dei bridge Snowflake cambiano nel tempo.

Licenza MIT. Sei responsabile del rispetto delle leggi del tuo paese.
