# WinWG OneClick Server — idées futures et préparation publique

Ce document sert de bloc-notes pour réfléchir aux prochaines étapes du projet avant et après publication publique.

## Verdict actuel

Le projet est publiable en public, mais plutôt en **beta** qu'en version stable.

```text
État actuel : publiable
Niveau maturité : environ 8/10 pour une beta
Version conseillée : v0.2.0-beta
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
VPN téléphone hors réseau local
LAN party par IP directe
auto-hébergement Windows
serveur WireGuard personnel
```

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
- [ ] Vérifier que la CI GitHub Actions passe.
- [ ] Tester l'installation sur une machine Windows propre.
- [ ] Tester la désinstallation complète.
- [ ] Tester la restauration d'une configuration existante.
- [ ] Tester l'ajout d'un appareil.
- [ ] Tester la suppression d'un appareil.
- [ ] Tester la génération QR si activée.
- [ ] Tester le mode FR/EN.
- [ ] Créer une release beta récente.

### Recommandé

- [ ] Ajouter des screenshots de la console.
- [ ] Ajouter une section `Use cases` / `Cas d'utilisation` dans le README.
- [ ] Ajouter les topics GitHub.
- [ ] Vérifier que le README anglais est bien le README par défaut.
- [ ] Garder seulement les branches nécessaires :
  - `main`
  - `test-debug-feature` ou éventuellement `dev`

---

## Release conseillée

La release actuelle peut devenir obsolète si beaucoup de fonctionnalités ont été ajoutées depuis.

Version recommandée pour la prochaine publication :

```text
v0.2.0-beta
```

Pourquoi pas `v1.0.0` ?

```text
Le projet est utilisable, mais il reste encore à tester sur plusieurs machines Windows et plusieurs scénarios réseau.
```

---

## Topics GitHub recommandés

À ajouter dans les paramètres GitHub du repo :

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

Objectif : rendre le projet plus trouvable sur GitHub.

---

## Section README à ajouter : Use cases

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
- connecter ton téléphone à ton VPN maison ;
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
C:\ProgramData\WireGuardPhoneServer\exports\friend1.zip
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

Idée : rendre le choix plus accessible lors de l'ajout d'un appareil :

```text
Traffic mode:
1 - Full tunnel: all IPv4 traffic through VPN
2 - VPN only: 10.66.66.0/24
3 - VPN + home LAN: 10.66.66.0/24, 192.168.1.0/24
```

Cela éviterait aux utilisateurs de devoir passer par le mode avancé.

---

### 8. Nettoyage terminologique phone/device

Historiquement, certains noms internes utilisent :

```text
Phone
telephone
WireGuardPhoneServer
wg-phone-server
```

Pour compatibilité, on peut garder les chemins internes.

Mais côté interface et documentation publique, il serait préférable d'utiliser :

```text
device
remote device
appareil
```

Objectif : montrer que le projet marche aussi pour :

```text
téléphone
tablette
PC portable
PC ami
machine de jeu
```

---

### 9. Journal d'événements propre

Créer un log principal :

```text
C:\ProgramData\WireGuardPhoneServer\logs\winwg.log
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

### 10. Activer/désactiver QR depuis la console

Aujourd'hui, la fonctionnalité QR est choisie à l'installation.

Idée : ajouter dans la console :

```text
QR feature settings
1 - Enable QR feature
2 - Disable QR feature
3 - Reinstall QRCoder dependency
```

Cela évite de relancer l'installateur uniquement pour changer ce choix.

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
un téléphone est perdu
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
client configs
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

## 23. Faire une release v0.2.0-beta

Quand les derniers changements seront validés :

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

# Recommandation stratégique

Avant publication publique :

```text
1. Ajouter les topics GitHub
2. Ajouter quelques screenshots
3. Vérifier la CI
4. Créer v0.2.0-beta
5. Rendre public
```

Après publication :

```text
1. LAN Party helper
2. Export pack invité
3. Health check
4. QR feature enable/disable depuis console
5. Diagnostic CG-NAT
```
