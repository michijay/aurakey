# AuraKey
> Steganographic LUKS management tool for hiding GPG-encrypted keys in JPEGs with integrated Nuke functionality.

## AuraKey (V. 1.5-2)
**Steganographic LUKS Key-Management & Nuke Utility**

AuraKey is a specialized security tool designed to manage LUKS-encrypted volumes using steganography. It allows users to hide GPG-encrypted keyfiles inside common image files (JPEG), providing a layer of "security by obscurity." 

Additionally, it features an integrated "Nuke" function to instantly neutralize data and headers in case of physical compromise.

### Features
- **Key Camouflage**: Hide LUKS keys within harmless image files using binary offsets.
- **GPG Protection**: Double-layer security—keys are GPG-encrypted before being embedded.
- **Nuke Function**: A specific "Nuke" passphrase triggers the immediate destruction of the keyfile and the LUKS header.
- **Systemd Integration**: Automated secure unlocking during the boot process.
- **External Configuration**: Decouples program logic from sensitive hardware UUIDs and hashes.

---

## Installation and Setup

### 1. Script Deployment
Place the script in `/opt/aurakey.sh` and ensure it is executable:
```bash
chmod 750 /opt/aurakey.sh
```
### 2. Configuration
Create a configuration file at /etc/aurakey.cfg:
```bash
# AuraKey Configuration
# UUID of the encrypted partiton. use: blkid | grep "crypto_LUKS" | cut -d"\"" -f2
LUKS_UUID="your-luks-uuid-here"
# mappername for the encrypted drive
MAPPER_NAME="cryptdrive"
# mountpoint to mount the encrypted drive to. maybe /home
MOUNT_POINT="/home"
# array with UUIDs of USB-Sticks with the keyfile. use: blkid to find it.
KEY_UUIDS=("USB-STICK-UUID")
# name of GPG encrypted keyfile. JPG hidden
KEYFILE="camouflage_image.jpg"
# generate your nuke-hash via: "read -r -s -p "Nuke-Password: " p; echo; printf '%s' "$p" | sha256sum; unset p"
NUKE_HASH="your_sha256_nuke_hash"
# max tries to enter password before entering emergencymode
MAX_TRIES=3
```
### 3. Systemd Integration
To unlock your drive automatically at boot, create /etc/systemd/system/aurakey.service:
```bash
[Unit]
Description=AuraKey Drivecrypt Service
DefaultDependencies=no
After=systemd-udev-settle.service systemd-remount-fs.service plymouth-start.service
Before=local-fs.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/opt/aurakey.sh --decrypt
StandardInput=tty
TTYPath=/dev/tty1
StandardOutput=journal

[Install]
WantedBy=local-fs.target
```
Enable the service:
```bash
systemctl enable aurakey.service
```
## Usage Guide
Generate and hide a Key

## 1. Generate a high-entropy 4KB key
```bash
./aurakey.sh --create-keyfile /tmp/raw.bin
```
## 2. Hide the GPG-encrypted key inside a JPEG
```bash
./aurakey.sh --hide-keyfile secret_key.gpg original.jpg output.jpg
```
## 3. Register the hidden key to a LUKS slot
```bash
./aurakey.sh --add-keyfile-to-drive output.jpg
```
## Manual Decryption
```bash
./aurakey.sh --decrypt
```
## Changelog

    1.5-2 (2026-APR-16): Switched to external config; fixed systemd-ask-password TTY issues.
    1.4-0 (2026-APR-14): Added steganography functions and ASCII banner.
    1.3-0 (2026-APR-13): Added search functionality for keys on external USB media.
    1.1-0 (2026-APR-10): Added GPG Keyfile support; dropped ZFS support.
    1.0-0 (2026-APR-08): Initial release by Michael Janssen.

## License and credits

Author: Michael Janssen (m.janssen@lyrah.net)

License: This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License Version 3 as published by the Free Software Foundation.
