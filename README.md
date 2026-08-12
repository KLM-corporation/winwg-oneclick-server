# WinWG OneClick Server

![Status](https://img.shields.io/badge/status-beta-orange) ![Platform](https://img.shields.io/badge/platform-Windows-blue) ![License](https://img.shields.io/badge/license-MIT-green)

[English documentation](README.en.md) | Documentation française

**One script. One click. Ton PC Windows devient un serveur VPN WireGuard.**

Un projet Windows simple et propre pour transformer un PC Windows 10/11 en **serveur d’accès distant WireGuard** avec une installation en **un seul script / un seul double-clic**. Il génère aussi la configuration à importer sur ton téléphone, ta tablette ou ton PC portable.




## Statut du projet

WinWG OneClick Server est actuellement en **beta**. Il est utilisable, mais il doit encore être testé sur plusieurs machines Windows avant d'être considéré comme stable.

À utiliser d'abord pour un usage personnel, home-lab ou test. Évite de l'installer directement sur une machine critique sans validation.

## Promesse du projet

Le but de WinWG OneClick Server est simple :

```text
1 script
1 double-clic
1 serveur WireGuard fonctionnel sur Windows
```

Le projet configure automatiquement ce qui est normalement pénible à faire à la main :

- installation de WireGuard pour Windows si absent ;
- génération des clés serveur et appareil distant ;
- création du service tunnel WireGuard ;
- pare-feu Windows ;
- NAT Windows ;
- tentative de redirection UPnP ;
- fichier `.conf` prêt à importer dans l'app WireGuard mobile ;
- console de supervision ;
- bouton d'activation/désactivation du service ;
- désinstallation propre.


> Compatibilité : certains chemins internes gardent le nom historique `WireGuardPhoneServer`, par exemple `C:\ProgramData\WireGuardPhoneServer`. C'est volontaire pour ne pas casser les installations existantes.

## Installation one-click recommandée

Sur le PC Windows qui doit devenir serveur VPN :

1. Télécharge/copie ce repo sur le PC.
2. Double-clique simplement :

```text
INSTALLER-ONE-CLICK.bat
```

L'installeur demande les droits administrateur Windows, installe WireGuard si besoin, génère la configuration serveur + téléphone, configure le pare-feu, le routage, le NAT, puis ouvre le dossier contenant le fichier `.conf` à importer dans l'application WireGuard du téléphone.

Il tente aussi de créer automatiquement la redirection de port sur la box via UPnP. Si ta box refuse ou si UPnP est désactivé, l'installeur affiche l'IP locale du PC et tu devras faire la redirection manuellement :

```text
UDP 51820 -> IP locale du PC Windows -> UDP 51820
```

> Note : aucune installation ne peut contourner automatiquement le CG-NAT de ton opérateur. Si tu es derrière CG-NAT, il faut demander une IPv4 publique/full stack ou utiliser un VPS relais.

> ⚠️ Important : pour se connecter depuis l'extérieur, il faut que le PC soit joignable depuis Internet. Dans la majorité des cas, cela veut dire :
> 1. ouvrir/forwarder un port UDP sur la box/routeur vers le PC Windows ;
> 2. utiliser l'IP publique de la box, ou un nom DNS dynamique ;
> 3. éviter le CG-NAT, ou demander une IPv4 publique à l'opérateur.

## Ce que le projet automatise

- Installation de WireGuard pour Windows via `winget` si nécessaire.
- Génération des clés serveur/client.
- Création d'un tunnel WireGuard serveur.
- Activation du routage IPv4 Windows.
- Création d'une règle pare-feu UDP.
- Création d'une règle NAT Windows pour permettre au téléphone de sortir vers Internet via le PC.
- Génération d'un fichier client `.conf` à importer dans l'app WireGuard mobile.

## Pré-requis

- Windows 10/11.
- PowerShell lancé **en administrateur**.
- Accès administrateur au routeur/à la box pour faire une redirection de port.
- WireGuard mobile installé sur le téléphone :
  - Android : Google Play / F-Droid.
  - iPhone : App Store.




## Attribution

Licence : MIT.

Tu peux utiliser, copier, modifier, redistribuer et intégrer ce projet, y compris commercialement, à condition de conserver la notice de copyright et la licence.

Projet original : **WinWG OneClick Server**  
Auteur : **KLM-DEV**  
Dépôt : `https://github.com/KLM-corporation/winwg-oneclick-server`

## Originalité, attribution et marque WireGuard

WinWG OneClick Server est un projet indépendant. Il n'est pas un fork et n'est pas basé sur une copie d'un autre projet open source.

Le projet utilise les outils officiels WireGuard pour Windows (`wg.exe` et `wireguard.exe`) et des commandes natives Windows/PowerShell (`New-NetNat`, `New-NetFirewallRule`, services Windows, etc.).

WireGuard est un projet et une marque appartenant à ses auteurs respectifs. Ce dépôt n'est pas affilié, sponsorisé, validé ou approuvé par le projet WireGuard.

Le nom `WinWG` signifie simplement :

```text
Windows + WireGuard helper
```

## Serveur WireGuard vs configuration téléphone

Sur Windows, il n'existe pas vraiment de paquet officiel séparé "serveur seulement". L'application WireGuard Windows installe aussi les composants nécessaires au mode serveur : `wg.exe`, `wireguard.exe`, le driver et le service tunnel.

Le projet ne transforme pas ton PC en "client VPN". Il utilise WireGuard pour créer un **tunnel serveur** sur le PC.

Quand le script parle de fichier `client` ou de dossier `clients`, cela veut dire :

```text
configuration à importer sur le téléphone
```

Le téléphone est le client VPN. Le PC Windows reste le serveur.

## Installation rapide

Ouvre PowerShell **en administrateur**, puis :

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
cd .\winwg-oneclick-server
.\scripts\Install-WireGuardServer.ps1 -Endpoint "MON_IP_PUBLIQUE_OU_DNS" -ClientName "telephone"
```

Exemple :

```powershell
.\scripts\Install-WireGuardServer.ps1 -Endpoint "vpn-maison.duckdns.org" -ClientName "iphone"
```

À la fin, le script affiche le chemin du fichier client, par exemple :

```text
C:\ProgramData\WireGuardPhoneServer\clients\iphone.conf
```

Copie ce fichier sur ton téléphone puis importe-le dans l'application WireGuard.

## Redirection de port sur la box

Dans l'interface de ta box/routeur :

| Paramètre | Valeur par défaut |
|---|---|
| Protocole | UDP |
| Port externe | 51820 |
| IP locale cible | IP LAN du PC Windows |
| Port interne | 51820 |

Astuce : donne une IP fixe au PC Windows dans ta box, sinon la redirection peut casser si son IP locale change.


## Désinstallation one-click

Pour supprimer proprement tout ce que le projet a configuré sur le PC Windows, double-clique :

```text
UNINSTALLER-ONE-CLICK.bat
```

Le désinstalleur supprime :

- le tunnel/service WireGuard `wg-phone-server` ;
- la règle pare-feu UDP `51820` ;
- le NAT Windows `WireGuardPhoneServerNAT` ;
- la redirection UPnP UDP `51820` si elle avait été créée automatiquement ;
- les configurations et clés dans `C:\ProgramData\WireGuardPhoneServer` ;
- optionnellement l'application WireGuard elle-même.

Si tu avais créé une redirection de port manuelle sur ta box, il faut aussi la supprimer dans l'interface de la box.

> Sécurité : le désinstalleur ne désactive plus le routage IPv4 global de Windows, afin d'éviter de casser Hyper-V, WSL, le partage de connexion ou d'autres outils réseau.

Mode silencieux avancé :

```powershell
.\Uninstall-WireGuard-Server.ps1 -Quiet -RemoveWireGuardApp
```




## Console serveur unifiée

WireGuard Windows tourne comme un service en arrière-plan. WinWG regroupe maintenant la supervision et le contrôle du serveur dans une seule console :

```text
SERVER-CONSOLE.bat
```

Cette console permet de :

- voir l'état du service WireGuard ;
- voir les téléphones/appareils connectés et leurs handshakes ;
- vérifier le pare-feu, le NAT et le port UDP ;
- activer/démarrer le serveur VPN ;
- désactiver/arrêter le serveur VPN sans supprimer les configurations ;
- redémarrer le serveur VPN ;
- ajouter un téléphone, une tablette ou un PC portable ;
- supprimer un appareil existant.

Menu disponible dans la console :

```text
1 / A - Activer / démarrer le serveur VPN
2 / D - Désactiver / arrêter le serveur VPN
3     - Redémarrer le serveur VPN
4 / N - Ajouter un nouvel appareil
5 / R - Retirer / supprimer un appareil
S     - Rafraîchir le statut
V     - Activer/désactiver le mode ultra verbeux
Q     - Quitter la console
```

La console ne se rafraîchit pas automatiquement toutes les 5 secondes : elle attend ton choix au clavier, ce qui évite les problèmes de saisie et l’affichage qui bouge tout seul.

Dans cette version, `R` veut dire `Retirer un appareil`. Pour redémarrer le serveur VPN, utilise le numéro `3`, afin d’éviter la confusion entre `redémarrer` et `retirer`.

Si le désinstalleur a supprimé les configurations, la console ne peut plus réactiver le VPN et demandera de relancer `INSTALLER-ONE-CLICK.bat`.

> Note : l'ancien script séparé `WIREGUARD-SERVICE-TOGGLE.bat` a été retiré dans cette version de test, car ses fonctions sont maintenant intégrées dans `SERVER-CONSOLE.bat`.




### Mode ultra verbeux

Dans `SERVER-CONSOLE.bat`, appuie sur :

```text
V
```

Ce mode affiche davantage de détails pendant les actions sensibles, notamment :

- script PowerShell appelé ;
- paramètres utilisés ;
- code retour ;
- sortie complète du script ;
- résultat de vérification après ajout/suppression d'appareil ;
- chemin du fichier log.

Un fichier log est aussi écrit dans :

```text
C:\ProgramData\WireGuardPhoneServer\logs
```

C'est utile pour diagnostiquer les cas où l'appareil est bien créé/supprimé mais où le rechargement du service WireGuard retourne un avertissement.

## Gestion des appareils depuis la console

Depuis `SERVER-CONSOLE.bat`, tu peux maintenant gérer les appareils sans commande PowerShell manuelle :

```text
N - Ajouter un nouvel appareil
X - Supprimer un appareil
```

L'ajout d'appareil :

- demande le nom de l'appareil ;
- propose automatiquement l'endpoint public/DNS déjà utilisé si possible ;
- choisit automatiquement la prochaine IP VPN disponible ;
- génère le fichier `.conf` à importer ;
- ouvre le dossier contenant la configuration générée.

> Note : si l'ajout crée bien le fichier `.conf` et le peer mais qu'un message d'erreur apparaît pendant le rechargement du service, la console le signale comme un ajout réussi avec avertissement. Tu peux ensuite utiliser `3` pour redémarrer le serveur VPN.

La suppression d'appareil :

- liste les fichiers `.conf` existants ;
- s’il n’y a qu’un seul appareil, le sélectionne automatiquement ;
- demande confirmation ;
- supprime le peer du serveur ;
- supprime le fichier `.conf` local correspondant ;
- recharge le service WireGuard.

> Note : si la suppression retire bien le fichier `.conf` et le peer mais qu'un message d'erreur apparaît pendant le rechargement du service, la console le signale comme une suppression réussie avec avertissement. Tu peux ensuite utiliser `3` pour redémarrer le serveur VPN.


## Utilisation

### Ajouter un deuxième téléphone

```powershell
.\scripts\Add-WireGuardPeer.ps1 -ClientName "android" -Endpoint "vpn-maison.duckdns.org"
```

### Supprimer un client

```powershell
.\scripts\Remove-WireGuardPeer.ps1 -ClientName "android"
```

### Voir les clients configurés

```powershell
Get-ChildItem "C:\ProgramData\WireGuardPhoneServer\clients"
```

### Redémarrer le tunnel

```powershell
& "$env:ProgramFiles\WireGuard\wireguard.exe" /uninstalltunnelservice "wg-phone-server"
& "$env:ProgramFiles\WireGuard\wireguard.exe" /installtunnelservice "C:\ProgramData\WireGuardPhoneServer\server\wg-phone-server.conf"
```

## Configuration par défaut

| Option | Valeur |
|---|---|
| Nom tunnel | `wg-phone-server` |
| Port WireGuard | `51820/UDP` |
| Réseau VPN | `10.66.66.0/24` |
| IP serveur VPN | `10.66.66.1` |
| DNS client | `1.1.1.1, 8.8.8.8` |
| Mode client | full-tunnel IPv4 : `AllowedIPs = 0.0.0.0/0` |

## Tester depuis le téléphone

1. Désactive le Wi-Fi du téléphone.
2. Active la 4G/5G.
3. Active le tunnel WireGuard.
4. Ouvre un site comme `https://ifconfig.me`.
5. L'IP affichée doit être celle de ta connexion maison.

## Dépannage rapide

Consulte [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md).


## Avertissement sécurité

Ce projet configure un serveur VPN et peut exposer un port UDP sur Internet. Tu es responsable de ta configuration réseau.

Avant usage public ou prolongé :

- garde Windows et WireGuard à jour ;
- ne partage jamais les fichiers `.conf` générés ;
- supprime immédiatement un appareil perdu ou compromis ;
- vérifie ta redirection de port ;
- comprends les limites CG-NAT ;
- teste la désinstallation avant de dépendre du serveur.

## Sécurité

- Ne partage jamais les fichiers `.conf` générés : ils contiennent des clés privées.
- Utilise un nom DNS dynamique plutôt qu'une IP copiée partout.
- Garde Windows et WireGuard à jour.
- Supprime immédiatement un peer si un téléphone est perdu.

## Limites connues

- Si ton opérateur utilise du CG-NAT, la redirection de port ne fonctionnera pas. Solutions : demander une IPv4 publique, utiliser IPv6, ou passer par un VPS relais.
- Le script configure l'IPv4. L'IPv6 n'est pas activé par défaut.
- Certains antivirus/firewalls tiers peuvent bloquer le trafic UDP.
