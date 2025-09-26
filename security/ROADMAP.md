# 🛡️ Security / Network / VPN команда

**Стиль:** FFF — *Fast. Focused. Frictionless.*
Коротко, ясно и с конкретикой: цель — сделать безопасный, повторяемый и управляемый VPN-шлюз (IKEv2 / strongSwan), внутренний DNS, базовую сетевую сегментацию и процедуры backup / recovery для ключевых сетевых артефактов. Всё должно быть автоматизировано (Ansible/Playbooks) и задокументировано как runbook.

---

## 1. Краткая цель

Развернуть корпоративный VPN-шлюз `vpn.dev.box` на базе **strongSwan (IKEv2)**, дать безопасный доступ разработчикам к `*.dev.box` (git, nexus, k8s-dev), настроить split-tunnel (только internal routes), обеспечить MFA/PKI-путь в дальнейшем и простые, проверяемые runbook’ы для добавления/удаления пользователей, ротации ключей и восстановления.

---

## 2. Область ответственности команды

* Развертывание strongSwan IKEv2 на выделенной VM(ах).
* VPN-профили (policy): split-tunnel для dev-доступа к internal доменам.
* Internal DNS (push DNS сервер через VPN).
* Firewall / NAT / routing и IP forwarding.
* AuthN: краткосрочно — EAP (user+pass) или PSK для быстрого старта; среднесрочно — PKI / RADIUS.
* HA план для VPN (keepalived/VRRP или active-passive) — mid-term.
* Мониторинг и логирование (charon logs, alert on failures).
* Документация, скрипты добавления юзера, revoke, бэкап конфигов.

---

## 3. Архитектура (высокоуровнево)

* **VPN Gateway(s)**: 1 (fast start) → 2 (HA) VM(s), OS: Ubuntu LTS.
* **Auth**: initial — strongSwan + ipsec.secrets (EAP local) / PSK; mid-term — FreeRADIUS + LDAP/Keycloak.
* **PKI**: internal CA (strongSwan pki) для server/client certs — mid-term.
* **Routing**: VPN assigns client IPs from `10.240.0.0/24`. Routes pushed for internal subnets (e.g. `10.10.0.0/16` for k8s).
* **DNS**: internal DNS server (Bind or dnsmasq) — push via IKEv2 modeconfig `rightdns`.
* **Firewall**: allow UDP 500/4500, NAT for client IPs to internal networks if needed.
* **Backups**: `/etc/ipsec.conf`, `/etc/ipsec.secrets`, `/etc/ipsec.d/*`, iptables/ufw rules — offloaded to MinIO daily.

---

## 4. Near-term (0–7 дней) — Fast (практические шаги)

**Цель:** рабочий IKEv2 VPN, минимум конфигурации, devs подключаются, доступ к `git.dev.box` и `nexus.dev.box` через VPN.

### 4.1. Подготовка машины

* Ubuntu LTS VM, назначить публичный/внутренний IP; обеспечить доступ по SSH.
* Обновить и установить strongSwan:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y strongswan strongswan-pki libcharon-extra-plugins
```

* Включить IP forward:

```bash
sudo sysctl -w net.ipv4.ip_forward=1
# сохранить
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
```

* Открыть firewall:

```bash
sudo ufw allow 500,4500/udp
sudo ufw allow OpenSSH
```

### 4.2. Быстрый (темпоральный) вариант — EAP (user/pass) для теста

* Простой `ipsec.conf` (пример ` /etc/ipsec.conf` — редактируйте значения):

```conf
config setup
    charondebug="cfg 2, dmn 2, ike 1"

conn ikev2-vpn
    auto=add
    compress=no
    type=tunnel
    keyexchange=ikev2
    fragmentation=yes

    left=%any
    leftid=@vpn.dev.box
    leftcert=serverCert.pem     # создадим ниже
    leftsendcert=always
    leftfirewall=yes
    leftsubnet=0.0.0.0/0

    right=%any
    rightauth=eap-radius        # for later; for quick start: rightauth=eap-mschapv2
    rightsourceip=10.240.0.0/24
    rightsendcert=never
    rightdns=10.10.0.5          # internal DNS server
    eap_identity=%identity

    ike=aes256-sha256-modp2048
    esp=aes256-sha256
```

* `ipsec.secrets` (пример для EAP local auth — testing only):

```
# server private key
: RSA /etc/ipsec.d/private/serverKey.pem

# user credentials (only for quick start; move to RADIUS asap)
alice : EAP "alice_password"
bob   : EAP "bob_password"
```

> **Важно:** хранить пароли в Vault/secure store. EAP passwords в `ipsec.secrets` — только для PoC.

### 4.3. Генерация CA и server cert (strongSwan pki)

```bash
# создать CA
ipsec pki --gen --type rsa --size 4096 --outform pem > caKey.pem
ipsec pki --self --ca --lifetime 3650 --in caKey.pem --type rsa \
  --dn "CN=DevBox CA" --outform pem > caCert.pem

# server key + cert
ipsec pki --gen --type rsa --size 4096 --outform pem > serverKey.pem
ipsec pki --pub --in serverKey.pem | ipsec pki --issue --lifetime 1825 \
  --cacert caCert.pem --cakey caKey.pem \
  --dn "CN=vpn.dev.box" --san "vpn.dev.box" --flag serverAuth \
  --outform pem > serverCert.pem

# install
sudo mkdir -p /etc/ipsec.d/{private,certs,cacerts}
sudo cp serverKey.pem /etc/ipsec.d/private/
sudo cp serverCert.pem /etc/ipsec.d/certs/
sudo cp caCert.pem /etc/ipsec.d/cacerts/
```

### 4.4. NAT и routing (пример)

* NAT через iptables (если нужно, чтобы VPN clients выходили в внутреннюю сетку):

```bash
# допустим интерфейс к internal network - eth0
sudo iptables -t nat -A POSTROUTING -s 10.240.0.0/24 -o eth0 -j MASQUERADE
# сохранить правила (ubuntu)
sudo apt install -y iptables-persistent
sudo netfilter-persistent save
```

### 4.5. Push DNS & internal routing

* Настроить internal DNS (Bind/dnsmasq) на IP `10.10.0.5` и в `ipsec.conf` указать `rightdns=10.10.0.5`. Это даёт клиентам разрешение `git.dev.box` в VPN.

### 4.6. Запуск и тест

```bash
sudo ipsec restart
sudo ipsec statusall
```

* Подключение: Android strongSwan app (IKEv2 EAP), Windows 10 Connection (IKEv2), Linux (NetworkManager-strongswan). Test reachability:

```bash
# from client after connect
ping git.dev.box
curl https://git.dev.box
```

### 4.7. Backups (VPN config & certs)

* Ежедневно копировать `/etc/ipsec.conf`, `/etc/ipsec.secrets`, `/etc/ipsec.d/*` в MinIO (backup.dev.box). Используйте backup-runner or ansible to copy and upload:

```bash
tar -C /etc -czf /tmp/ipsec-backup-$(date +%F).tgz ipsec.conf ipsec.secrets ipsec.d
mc cp /tmp/ipsec-backup-$(date +%F).tgz localminio/minio-backups/vpn/
```

---

## 5. Mid-term (2–8 недель) — Focused (надёжность и безопасность)

**Цель:** перейти на production-grade: PKI, RADIUS/LDAP auth, HA, automation, monitoring, key rotation, DR drills.

### 5.1. PKI & cert-based auth

* Мigrate away from `ipsec.secrets` EAP-local → use client certificates for machines and users where possible.
* Implement internal CA (either strongSwan pki or enterprise PKI) + issuance process (Ansible + `ipsec pki` automation).
* Document client import steps (Windows, macOS, Android, Linux).

### 5.2. RADIUS / LDAP integration

* Deploy **FreeRADIUS** (or use corporate LDAP/Keycloak) for user auth (EAP-MSCHAPv2) and accounting.
* Benefits: centralized user management, deprovisioning via LDAP group removal.

### 5.3. High Availability

* Run 2 VPN gateway VMs + **keepalived** (VRRP) for virtual IP, shared certs/CA.
* Ensure stateful failover: session re-establishment will be required; design expectations.

### 5.4. Automation

* Create Ansible role `strongswan`:

  * Templates for `/etc/ipsec.conf`, `/etc/ipsec.secrets`, pki tasks, firewall rules, iptables NAT.
  * Playbook for adding/removing users and issuing certs.

### 5.5. Monitoring & Logging

* Export strongSwan metrics (charon logs); integrate with Prometheus and Grafana.
* Centralize logs (ELK/Loki) — alert on repeated failed auth, high error rates, down nodes.

### 5.6. Security hardening

* Disable IKEv1; allow only IKEv2.
* Cipher recommendations:

  * IKE: `chacha20poly1305-prfsha256` / `aes256gcm16-prfsha384` with P-256 or P-384 for DH.
  * ESP: `chacha20poly1305`, `aes128gcm16`, `aes256gcm16`.
  * Enforce PFS (DH) and reject weak algorithms (MD5, 3DES).
* Enforce `leftsendcert=always` only if needed.
* Keep `charondebug` conservative in prod.

### 5.7. Key rotation & CRL

* Implement lifetime policy: server cert rotate yearly; client certs 1 year or less.
* Implement CRL handling: `ipsec pki --signcrl` and place in `/etc/ipsec.d/crls/`. Ensure clients check CRL.

### 5.8. DR drills & runbooks

* Monthly: attempt add/remove user, revoke cert, rotate server cert in test environment.
* Quarterly: spin up new VM from Ansible, restore `/etc/ipsec.*` from MinIO, verify VPN comes up (target restore time < 15–30 min).

---

## 6. Adding/removing users — quick runbook (Fast)

### Add user (EAP local, quick)

1. Edit `/etc/ipsec.secrets`:

```
newuser : EAP "supersecret"
```

2. Restart or reload:

```bash
sudo ipsec reload
```

3. Give instructions to user (server address `vpn.dev.box`, username `newuser`, password).

### Add user (certificate-based recommended)

1. Generate key & CSR on client or server (preferred on server for automation).
2. Issue cert signed by CA:

```bash
ipsec pki --gen --type rsa --size 2048 > newuserKey.pem
ipsec pki --pub --in newuserKey.pem | ipsec pki --issue --cacert caCert.pem --cakey caKey.pem --dn "CN=newuser" --outform pem > newuserCert.pem
```

3. Provide `newuserCert.pem` + `newuserKey.pem` to user securely (use secure transfer / onboarding portal).
4. Add CRL/OCSP entry when revoking.

### Revoke user

1. Add serial to CRL:

```bash
ipsec pki --signcrl --in crlRequests --cakey caKey.pem --cacert caCert.pem --outform pem > crl.pem
# place crl.pem in /etc/ipsec.d/crls/
```

2. Reload strongSwan:

```bash
sudo ipsec rereadcrls
```

---

## 7. DNS + split tunneling — practical guidance

* **Split tunnel**: push internal prefixes only:

  * `rightsourceip=10.240.0.0/24`
  * `leftsubnet=10.10.0.0/16` (internal infra networks)
* **DNS push**: set `rightdns=10.10.0.5` in `ipsec.conf` so clients use internal DNS for `*.dev.box`.
* If clients are on mobile devices, ensure they accept the pushed DNS (Android strongSwan supports it).

---

## 8. Backup & restore for VPN (concrete)

* **What to backup**

  * `/etc/ipsec.conf`, `/etc/ipsec.secrets`
  * `/etc/ipsec.d/` (private keys, certs, cacerts, crls)
  * firewall rules (`iptables-save`) and `keepalived` config if HA.
* **Simple backup script**

```bash
TS=$(date -u +%FT%H%M%SZ)
tar -C /etc -czf /tmp/vpn-backup-$TS.tgz ipsec.conf ipsec.secrets ipsec.d
iptables-save > /tmp/iptables-$TS.rules
mc cp /tmp/vpn-backup-$TS.tgz localminio/minio-backups/vpn/
mc cp /tmp/iptables-$TS.rules localminio/minio-backups/vpn/
```

* **Restore**

  1. Stop strongSwan: `sudo ipsec stop`
  2. Restore files into `/etc` and permissions: private keys `600`, owner root:root.
  3. Restore iptables: `sudo iptables-restore < /tmp/iptables.rules`
  4. Start strongSwan: `sudo ipsec start`
  5. Test connectivity from client.

---

## 9. Monitoring & alerting (minimum viable)

* Watch:

  * `systemctl status strongswan` / charon logs `/var/log/syslog` or `/var/log/auth.log` depending on distro.
  * CPU/Memory on VPN VM.
  * Failed authentication spikes.
  * Disk usage of `/etc/ipsec.d` and backup store.
* Export metrics for Prometheus using `strongswan_exporter` or parse `charon` metrics; create Grafana alert for: VPN down, repeated failed logins > threshold, auth failures.

---

## 10. Acceptance criteria (DoD)

* Dev can connect to `vpn.dev.box` (IKEv2) using Android strongSwan client and reach `git.dev.box` and `nexus.dev.box`.
* VPN assigns IPs from `10.240.0.0/24` and DNS resolves internal names.
* `/etc/ipsec.*` and certs are backed up to MinIO daily.
* Runbook exists and tested: restore VPN config on clean VM in ≤ 30 min.
* Admins can add/remove users and revoke certs via documented steps.
* Monitoring alerts for VPN down and failed auth exist.

---

## 11. Security rules & hardening checklist

* [ ] Only IKEv2 enabled; IKEv1 disabled.
* [ ] Strong ciphers & PFS enabled (AES-GCM / ChaCha20, P-256/384).
* [ ] Private keys protected (`600` perms, root owner).
* [ ] No plaintext passwords in repos — use Vault/GitLab protected variables.
* [ ] Admin access to VPN host via SSH with key-only access and 2FA.
* [ ] Audit logs collection & retention policy.

---

## 12. Automation & repo layout (suggestion)

Place in `security/vpn/` in infra repo:

```
security/vpn/
  ansible/
    roles/strongswan/
      templates/ipsec.conf.j2
      templates/ipsec.secrets.j2
      tasks/main.yml
  pki/
    README.md (how to issue/revoke certs)
    scripts/generate-server-cert.sh
    scripts/generate-client-cert.sh
  runbook/
    add-user.md
    revoke-user.md
    restore.md
  monitoring/
    grafana-dashboard.json
  playbooks/
    deploy_vpn.yml
```

---

## 13. Risks & mitigations

* **Compromised credentials** → Use certs, central auth (RADIUS), rotate keys, keep audit.
* **Single VPN gateway fail** → Mitigation: HA with keepalived, test failover.
* **DNS leakage (public)** → enforce split-tunnel and push only internal DNS.
* **Unauthorized lateral movement** → enforce network policies and limit which subnets are routed.

---

## 14. Next immediate actions (today / tomorrow)

1. Provision 1 VM for VPN gateway (owner?).
2. Install strongSwan and generate server cert with `ipsec pki` (scriptize).
3. Configure quick EAP test profile (ipsec.conf + ipsec.secrets) and document credentials handling.
4. Open UDP 500/4500 in firewall and enable IP forwarding + NAT for client subnets.
5. Test client connection (Android strongSwan) and access to `git.dev.box`.
6. Implement daily backup script to MinIO and verify restore of config on test VM.

---

Если хочешь — могу прямо сейчас сгенерировать:

1. `ansible` role skeleton (`templates` + `tasks`) для strongSwan.
2. `ipsec.conf` + `ipsec.secrets` **пример** (вставить placeholders, без реальных паролей).
3. `pki` scripts (`generate-ca.sh`, `generate-server-cert.sh`, `generate-client-cert.sh`) с командами `ipsec pki`.

Что делаем первым — role skeleton, pki scripts или sample ipsec configs?
