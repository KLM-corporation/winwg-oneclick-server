# Dépannage WinWG OneClick Server


## Bail DHCP statique / réservation DHCP recommandé

Pour un serveur VPN à la maison, il vaut mieux éviter que l'adresse locale du PC Windows change.

La méthode recommandée est de créer un **bail DHCP statique** dans la box/routeur :

```text
Adresse MAC du PC Windows -> IP LAN réservée
```

Exemple :

```text
D4:3A:2E:85:CA:DF -> 192.168.1.14
```

Ensuite, configure la redirection de port vers cette IP réservée :

```text
UDP 51820 -> 192.168.1.14 -> UDP 51820
```

Termes possibles selon les box :

```text
Baux DHCP statiques
Réservation DHCP
Static DHCP lease
Address reservation
IP statique DHCP
```

C'est plus propre qu'une IP fixe configurée directement dans Windows, car la box continue de gérer le DHCP et limite les risques de conflit d'adresse.

## 1. Le téléphone ne se connecte pas du tout

Vérifie :

- Le téléphone est en 4G/5G, pas sur le Wi-Fi local.
- La redirection de port UDP est faite sur la box : `UDP 51820 -> IP locale du PC`.
- L'IP locale du PC n'a pas changé.
- Le pare-feu Windows contient une règle entrante UDP 51820.
- Le tunnel WireGuard est bien installé comme service.

Commandes utiles sur Windows :

```powershell
Get-NetFirewallRule -DisplayName "WireGuard Server UDP 51820"
Get-NetNat
Get-Service | Where-Object Name -like "WireGuardTunnel*"
```

## 2. Le téléphone se connecte mais Internet ne marche pas

Vérifie le NAT Windows :

```powershell
Get-NetNat -Name "WireGuardPhoneServerNAT"
```

Si absent :

```powershell
New-NetNat -Name "WireGuardPhoneServerNAT" -InternalIPInterfaceAddressPrefix "10.66.66.0/24"
```

Vérifie aussi le routage IPv4 :

```powershell
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name IPEnableRouter
Get-NetIPInterface -AddressFamily IPv4 | Select-Object InterfaceAlias,Forwarding
```

## 3. Tu es probablement derrière du CG-NAT

Symptômes :

- L'IP WAN affichée dans la box est différente de l'IP affichée par `https://ifconfig.me`.
- La redirection de port semble correcte mais aucun paquet n'arrive.

Solutions :

- Demander une IPv4 publique/full stack à l'opérateur.
- Utiliser IPv6 si disponible et compris.
- Utiliser un VPS relais WireGuard.
- Utiliser une solution type Tailscale/ZeroTier si tu acceptes de ne pas faire du WireGuard pur auto-hébergé.

## 4. Test de port

WireGuard utilise UDP : beaucoup de sites de test de port TCP ne sont pas fiables pour UDP.
Le meilleur test est de lancer le tunnel depuis le téléphone en 4G/5G puis de regarder les logs WireGuard côté Windows.

## 5. DNS dynamique conseillé

Si ton IP publique change, configure un DNS dynamique :

- DuckDNS
- No-IP
- Dynu
- Cloudflare avec script de mise à jour

Puis utilise ce nom comme endpoint client, par exemple :

```ini
Endpoint = vpn-maison.duckdns.org:51820
```


## 7. Le service tourne mais je veux couper temporairement le VPN

Utilise `SERVER-CONSOLE.bat`, puis appuie sur `D`. Tu peux le réactiver avec `A`.
