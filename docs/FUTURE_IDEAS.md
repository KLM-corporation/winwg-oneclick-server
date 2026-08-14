# WinWG OneClick Server — idées futures et préparation publique

Ce document sert de bloc-notes pour réfléchir aux prochaines étapes du projet avant et après publication publique.

## Verdict actuel

Le projet est maintenant **public** et publié en **beta**.

```text
État actuel : public
Niveau maturité : beta utilisable
Version publiée : v0.2.0-beta
```

Positionnement conseillé :

```text
WinWG OneClick Server
A beta one-click Windows helper to turn a PC into a WireGuard remote access server.
```

À éviter pour l'instant :

```text
production-ready enterprise VPN solution
```

Le projet est adapté pour :

```text
home-lab
accès distant personnel
VPN appareil hors réseau local
LAN party par IP directe
auto-hébergement Windows
serveur WireGuard personnel
```


---

## Déjà réalisé

Ces idées ont été faites ou largement traitées depuis la première version de ce document :

- [x] Rendre le repo public.
- [x] Créer une release `v0.2.0-beta` avec ZIP téléchargeable.
- [x] Ajouter les topics GitHub principaux.
- [x] Mettre le README anglais par défaut et garder la documentation française.
- [x] Nettoyer la terminologie user-facing vers `device` / `appareil`.
- [x] Tester puis intégrer le renommage interne complet : `WinWGOneClickServer`, `winwg-server`, `devices`.
- [x] Ajouter la console unifiée.
- [x] Ajouter le QR code optionnel.
- [x] Ajouter le choix QR par appareil lors de l'ajout.
- [x] Ajouter le menu `QR code settings` / `Paramètres QR code` dans la console.
- [x] Ajouter la restauration d'une configuration existante.
- [x] Ajouter le compteur de vitesse par peer.
- [x] Ajouter le mode avancé avec avertissement.
- [x] Ajouter l'édition avancée du port, DNS, `AllowedIPs` et `PersistentKeepalive`.
- [x] Ajouter `DEBUG-UPNP.bat` pour diagnostiquer UPnP / PCP / NAT-PMP.
- [x] Ajouter les donations optionnelles BTC/ETH.

---

## Checklist avant publication publique

### Obligatoire

- [ ] Révoquer tout ancien token GitHub partagé pendant le développement.
- [ ] Vérifier qu'aucun fichier sensible n'est dans le repo :
  - `.conf`
  - `.key`
  - `.psk`
  - `.env`
  - logs contenant des clés
- [x] Vérifier que la CI GitHub Actions passe.
- [ ] Tester l'installation sur une machine Windows propre.
- [ ] Tester la désinstallation complète.
- [ ] Tester la restauration d'une configuration existante.
- [ ] Tester l'ajout d'un appareil.
- [ ] Tester la suppression d'un appareil.
- [ ] Tester la génération QR si activée.
- [ ] Tester le mode FR/EN.
- [x] Créer une release beta récente.

### Recommandé

- [ ] Ajouter des screenshots de la console.
- [ ] Ajouter une section `Use cases` / `Cas d'utilisation` dans le README.
- [x] Ajouter les topics GitHub.
- [x] Vérifier que le README anglais est bien le README par défaut.
- [x] Garder seulement les branches nécessaires :
  - `main`
  - `dev`

---

## Release actuelle

La release publique actuelle est :

```text
v0.2.0-beta
```

Pourquoi pas `v1.0.0` ?

```text
Le projet est utilisable, mais il reste encore à tester sur plusieurs machines Windows et plusieurs scénarios réseau.
```

Prochaine release possible après nouvelles fonctionnalités :

```text
v0.3.0-beta
```

---

## Topics GitHub appliqués

Topics actuellement ajoutés dans les paramètres GitHub du repo :

```text
wireguard
vpn
windows
powershell
remote-access
one-click
self-hosted
home-server
lan-party
gaming
game-server
nat
firewall
qr-code
dynamic-dns
```

Objectif : rendre le projet plus trouvable sur GitHub. Statut : fait.

---

## Section README proposée : Use cases

### Version anglaise

```md
## Use cases

WinWG OneClick Server can be used for:

- remote access to your home network;
- connecting your phone to your home VPN;
- self-hosted WireGuard VPN on Windows;
- gaming and LAN party scenarios where games support direct IP connection;
- accessing home services while outside the local network;
- private peer-to-peer access between trusted devices.

Note: WireGuard is a layer-3 VPN. Some games that rely only on LAN broadcast discovery may not automatically appear in the LAN server list. Direct IP connection is recommended.
```

### Version française

```md
## Cas d'utilisation

WinWG OneClick Server peut servir pour :

- accéder à ton réseau maison à distance ;
- connecter ton appareil à ton VPN maison ;
- héberger un serveur WireGuard sur Windows ;
- jouer en LAN party à distance si le jeu accepte la connexion directe par IP ;
- accéder à tes services maison hors réseau local ;
- connecter plusieurs appareils de confiance entre eux.

Note : WireGuard est un VPN de couche 3. Certains jeux qui dépendent uniquement de la découverte LAN broadcast/multicast peuvent ne pas apparaître automatiquement dans la liste LAN. La connexion directe par IP est recommandée.
```

---

# Idées futures classées par priorité

## Priorité haute

### 1. Screenshots dans le README

Ajouter des images pour rendre le repo plus clair et attirant.

Exemples :

```text
docs/images/console-main.png
docs/images/installer-language.png
docs/images/qr-code-flow.png
docs/images/advanced-mode.png
```

Section README possible :

```md
## Screenshots
```

Pourquoi c'est utile :

```text
Un utilisateur comprend plus vite ce que fait le projet.
Ça donne plus confiance avant de télécharger un script Windows.
```

---

### 2. LAN Party helper

Ajouter un mode dans la console :

```text
LAN Party helper
```

Fonctions possibles :

- afficher les IP VPN de chaque joueur ;
- recommander `AllowedIPs = 10.66.66.0/24` ;
- expliquer la connexion directe par IP ;
- afficher un avertissement sur la découverte LAN automatique ;
- générer un petit résumé copiable dans Discord.

Exemple :

```text
LAN Party info
Server VPN IP: 10.66.66.1
Players:
- Kylian-PC : 10.66.66.2
- Friend1   : 10.66.66.3

Use direct IP connection in games.
LAN auto-discovery is not guaranteed.
```

---

### 3. Export pack invité

Créer un ZIP par appareil :

```text
C:\ProgramData\WinWGOneClickServer\exports\friend1.zip
```

Contenu possible :

```text
friend1.conf
friend1.png
README_IMPORT.txt
```

Le `README_IMPORT.txt` pourrait expliquer :

```text
1. Installe WireGuard.
2. Importe le fichier .conf ou scanne le QR code.
3. Active le tunnel.
4. Teste la connexion.
```

Intérêt :

```text
Très pratique pour envoyer une configuration à un ami non technique.
```

---

### 4. Health check intégré

Ajouter dans la console :

```text
Health check / Diagnostic rapide
```

Vérifications possibles :

- service WireGuard lancé ;
- règle pare-feu présente ;
- NAT présent ;
- dernier handshake ;
- endpoint visible ;
- IP locale du PC ;
- rappel port forwarding ;
- rappel CG-NAT.

Affichage possible :

```text
[OK] Service WireGuard running
[OK] Firewall rule present
[OK] NAT present
[WARN] No recent handshake
[INFO] Check UDP 51820 forwarding on router
```

---

### 5. Diagnostic CG-NAT

Ajouter un assistant pour aider l'utilisateur à comprendre si sa box est derrière CG-NAT.

Indications possibles :

```text
Si l'IP WAN de la box est dans :
- 10.0.0.0/8
- 172.16.0.0/12
- 192.168.0.0/16
- 100.64.0.0/10
alors CG-NAT ou double NAT probable.
```

Le script peut déjà détecter l'IP publique Internet, mais l'IP WAN de la box est plus difficile à récupérer automatiquement.

Donc idée réaliste :

```text
Assistant semi-manuel : l'utilisateur entre l'IP WAN affichée par sa box, WinWG compare avec l'IP publique détectée.
```

---

## Priorité moyenne

### 6. Assistant DNS dynamique

Ajouter une documentation ou un assistant pour :

```text
DuckDNS
No-IP
Dynu
Cloudflare DDNS
```

Objectif : éviter que les configs cassent quand l'IP publique change.

Exemple :

```text
home-vpn.duckdns.org:51820
```

---

### 7. Mode split tunnel plus accessible

Aujourd'hui, `AllowedIPs` est configurable en mode avancé.

État : nettoyage user-facing largement appliqué. Idée restante : rendre le choix plus accessible lors de l'ajout d'un appareil :

```text
Traffic mode:
1 - Full tunnel: all IPv4 traffic through VPN
2 - VPN only: 10.66.66.0/24
3 - VPN + home LAN: 10.66.66.0/24, 192.168.1.0/24
```

Cela éviterait aux utilisateurs de devoir passer par le mode avancé.

---

### 8. Nettoyage terminologique device/appareil — fait

État : réalisé.

Le projet utilise maintenant majoritairement `device` / `appareil` côté interface et documentation.

Les anciens termes historiques `phone` / `telephone` ont été nettoyés autant que possible, et le renommage interne expérimental a été intégré :

```text
WireGuardPhoneServer -> WinWGOneClickServer
wg-phone-server -> winwg-server
clients -> devices
```

À surveiller : il peut rester quelques occurrences légitimes dans les exemples, par exemple `iPhone` ou des explications historiques.

---

### 9. Journal d'événements propre

Créer un log principal :

```text
C:\ProgramData\WinWGOneClickServer\logs\winwg.log
```

Événements à journaliser :

```text
install
uninstall
restore existing configuration
add device
remove device
generate QR
advanced config change
errors
```

Intérêt :

```text
Support plus facile via GitHub Issues.
```

---

### 10. Activer/désactiver QR depuis la console — fait

État : réalisé.

La console contient maintenant :

```text
7 / K - QR code settings
```

Ce menu permet :

```text
1 - Enable QR feature and install QRCoder
2 - Disable QR feature
3 - Reinstall/check QRCoder
4 - Open QR codes folder
```

Le comportement actuel :

```text
QR désactivé globalement -> l'option de génération QR est cachée
QR activé globalement    -> la console demande à chaque ajout si un QR doit être généré
```

---

## Priorité basse mais intéressante

### 11. Interface graphique simple

Créer une petite interface WinForms/WPF :

```text
Install
Console
Add device
Remove device
Generate QR
Advanced settings
```

Attention : plus lourd à maintenir que la console.

---

### 12. Branding / identité visuelle

Créer :

```text
logo WinWG
icône
banner ASCII
badges README
```

Objectif : rendre le projet plus identifiable.

---

### 13. GitHub Pages

Créer une page web simple :

```text
https://klm-corporation.github.io/winwg-oneclick-server
```

Contenu :

```text
présentation
screenshots
download latest release
FAQ
use cases
```

---

### 14. Package Winget

À long terme :

```powershell
winget install KLM-DEV.WinWGOneClickServer
```

Mais cela demande un projet plus stable.

---

### 15. Signature / checksums

Ajouter :

```text
SHA256 des releases
signature de scripts PowerShell
instructions de vérification
```

Utile pour rassurer les utilisateurs avant d'exécuter un script Windows.

---

# Idées sécurité

## 16. Rotation des clés

Ajouter en console :

```text
Rotate device keys
Rotate server keys
```

Cas d'usage :

```text
un fichier .conf a été partagé par erreur
un appareil est perdu
une clé privée est exposée
```

---

## 17. Appareil temporaire / expiration

Créer un appareil temporaire :

```text
guest-lan-party
expires in 24h
```

Puis proposer :

```text
Remove expired devices
```

Utile pour LAN party ou accès invité.

---

## 18. Backup chiffré

Ajouter :

```text
Export encrypted backup
Restore encrypted backup
```

Contenu possible :

```text
server config
device configs
QR flags
settings
```

À protéger par mot de passe.

---

# Idées gaming / LAN

## 19. Profils de jeux

Ajouter une doc ou un assistant pour :

```text
Minecraft
ARK
Valheim
Terraria
Factorio
Counter-Strike
Project Zomboid
```

Pour chaque jeu :

```text
connexion directe IP possible ?
ports utiles ?
serveur dédié recommandé ?
LAN discovery nécessaire ?
```

---

## 20. Affichage liste joueurs

Dans le mode LAN party :

```text
Connected devices:
- Kylian-PC : 10.66.66.2 online
- Friend1   : 10.66.66.3 offline
```

Avec sortie copiable :

```text
Join my game at 10.66.66.2
```

---

## 21. Ping test entre peers

Depuis le serveur :

```text
ping 10.66.66.2
ping 10.66.66.3
```

Afficher :

```text
reachable
unreachable
```

Limite : certains appareils bloquent le ping par firewall.

---

# Idées publication

## 22. Ajouter les topics GitHub

Topics recommandés :

```text
wireguard
vpn
windows
powershell
remote-access
one-click
self-hosted
home-server
lan-party
gaming
game-server
nat
firewall
qr-code
dynamic-dns
```

---

## 23. Faire une release v0.2.0-beta — fait

Release publiée :

```text
v0.2.0-beta
```

Contenu notable :

```text
FR/EN
console unifiée
QR optionnel
mode avancé
restauration config existante
compteur vitesse peer
organisation scripts/docs
```

---

# Recommandation stratégique mise à jour

Déjà fait :

```text
- Repo public
- Topics GitHub
- CI OK
- Release v0.2.0-beta
- QR feature settings
```

Priorités restantes après publication :

```text
1. Ajouter quelques screenshots
2. Ajouter une section Use cases / Cas d'utilisation dans le README
3. LAN Party helper
4. Export pack invité
5. Health check
6. Diagnostic CG-NAT
```
