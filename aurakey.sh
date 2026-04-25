#!/bin/bash

# AuraKey - Steganographic LUKS Utility
# Author: Michael Janssen <m.janssen@lyrah.net>
# License: GPLv3 (See README.md for details)

VERSION="1.6-1"
TRIES=0 # needs to be zero to start the loop

# search for external config and load it
{ source ./aurakey.cfg || source /etc/aurakey.cfg || source /usr/local/etc/aurakey.cfg ; } 2>/dev/null || echo "Warning: No config file found!"

if [[ "$2" == "--silent" ]]
	then
		VERBOSE_MODE="0"
	elif [[ "$2" == "--verbose" ]]
	then
		VERBOSE_MODE="2"
	else
		VERBOSE_MODE="1"
	fi

	# only show if not in silent mode
	if [[ "$VERBOSE_MODE" != "0" ]]
	then
		echo ""
		echo "     o                                      oooo   oooo                       "
		echo "    888   oooo  oooo  oo oooooo   ooooooo    888  o88  ooooooooo8 oooo   oooo "
		echo "   8  88   888   888   888    888 ooooo888   888888   888oooooo8   888   888  "
		echo "  8oooo88  888   888   888      888    888   888  88o 888           888 888   "
		echo "o88o  o888o 888o88 8o o888o      88ooo88 8o o888o o888o 88oooo888     8888    "
		echo "                                                                   o8o888     "
		echo "                                                              Version : "$VERSION""
		echo "+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+"
		echo "|S|t|e|g|a|n|o|g|r|a|p|h|i|c| |L|U|K|S| |K|e|y|-|M|a|n|a|g|e|m|e|n|t|T|o|o|l|"
		echo "+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+"
	fi

# check if uuid of the luks-drive exist
if [ ! -b /dev/disk/by-uuid/"$LUKS_UUID" ]
then
	if [ "$VERBOSE_MODE" -ge "1" ]
	then
		echo "Error: LUKS drive not found!"
		echo "Please check the LUKS_UUID entry in your aurakey.cfg"
	fi
	sleep 1
	exit 1
fi

if [[ "$1" == "--decrypt" ]]
then

	# startup delay
	if [[ "$DELAY" != "0" ]]
	then
		sleep "$DELAY"
	fi

	for i in "${KEY_UUIDS[@]}"
	do
		if [ -b /dev/disk/by-uuid/"$i" ]
		then
			mkdir -p /media/"$i"
			mount /dev/disk/by-uuid/"$i" /media/"$i"

			# locate keyfile on the usbstick
			KEYFILE2=$(/usr/bin/find /media/"$i" -iname "$KEYFILE" -print -quit)
			if [ "$VERBOSE_MODE" == "2" ]
			then
				echo "AuraKey : keyfile found : $KEYFILE2"
			fi

			while [ $TRIES -lt $MAX_TRIES ]
			do
				if [ $TRIES -eq 0 ]
				then
					PASS_MSG="AuraKey : Enter password for cryptdrive :"
				else
					PASS_MSG="AuraKey : Enter password for cryptdrive (failed tries: $TRIES) :"
				fi
				# securely capture password using systemd agent
				PASSWORD=$(systemd-ask-password "$PASS_MSG")

				# calculate hash of entered password
				INPUT_HASH=$(/usr/bin/printf "%s" "$PASSWORD" | sha256sum | awk '{print $1}')

				# Duke, nuke them!
				if [ "$INPUT_HASH" == "$NUKE_HASH" ]
				then
					if [ "$VERBOSE_MODE" == "2" ]
					then
						echo "AuraKey : Nuke-Password entered! Destroying LUKS-Header and keyfile : $KEYFILE2"
						DDSTATUS="progress"
					else
						DDSTATUS="none"
					fi

					# destroy the keyfile
					dd if=/dev/urandom of="$KEYFILE2" bs=1 count=4096 conv=fsync status="$DDSTATUS"
					# destroy the LUKS-Header
					dd if=/dev/urandom of=/dev/disk/by-uuid/"$LUKS_UUID" bs=1M count=32 conv=fsync status="$DDSTATUS"
					sync

					if [ "$VERBOSE_MODE" != "0" ]
					then
						echo "Data neutralized."
						umount /media/"$i"
						rmdir /media/"$i"
						shutdown -h now
					fi
					umount /media/"$i"
					rmdir /media/"$i"
					exit 0
				fi

				# 1. Find the marker position in the file
				OFFSET=$(grep -aob "MYKEYSTART" "$KEYFILE2" | head -n 1 | cut -d: -f1)

				if [ -n "$OFFSET" ]
				then
					# Calculate start of encrypted data (Marker is 10 bytes long)
					KEY_START=$((OFFSET + 10))
					if [ "$VERBOSE_MODE" == "2" ]
					then
						echo "AuraKey : Found GPG-Encrypted keyfile at : $KEY_START inside of : $KEYFILE2"
					fi
					# Use dd to skip the image part and feed the rest into GPG
					DECRYPT_CMD=(/usr/bin/dd "if=$KEYFILE2" bs=1 "skip=$KEY_START")
				else
					if [ "$VERBOSE_MODE" == "2" ]
					then
						echo "AuraKey : No GPG-Encrypted keyfile found inside of : $KEYFILE2 !"
						echo "I will try to use it directly..."
					fi
					# Fallback: If no marker is found, try to read the file normally
					DECRYPT_CMD=(/usr/bin/cat "$KEYFILE2")
				fi

				TMP_KEY="/tmp/luks_tmp_$(date +%s).bin"
				if [ "$VERBOSE_MODE" != "0" ]
				then
					echo "Decrypting GPG payload to RAM..."
				fi
    
				if "${DECRYPT_CMD[@]}" 2>/dev/null | /usr/bin/gpg --decrypt --pinentry-mode loopback --homedir /tmp --no-permission-warning --batch --no-tty --passphrase-fd 3 3<<< "$PASSWORD" > "$TMP_KEY"
				then
					/usr/sbin/cryptsetup open /dev/disk/by-uuid/"$LUKS_UUID" "$MAPPER_NAME" --key-file="$TMP_KEY"
					mount /dev/mapper/"$MAPPER_NAME" "$MOUNT_POINT"
					if [ "$VERBOSE_MODE" != "0" ]
					then
						echo "AuraKey : LUKS drive successfully mounted at $MOUNT_POINT"
						RMMODE="rm -v -f"
					else
						RMMODE="rm -f"
					fi
					umount /media/"$i"
					rmdir /media/"$i"
					dd if=/dev/urandom of="$TMP_KEY" bs=1024 count=4 status="$DDSTATUS" && "$RMMODE" "$TMP_KEY"
					exit 0
				else
					echo "AuraKey : Wrong password or corrupted key! Attempt $((TRIES+1)) of $MAX_TRIES."
					((TRIES++))
				fi

			done

			# boot into emergencymode after $MAX_TRIES
			if [ "$VERBOSE_MODE" != "0" ]
			then
				echo "AuraKey : Too many failed attempts. System will enter emergency mode."
				umount /media/"$i"
				rmdir /media/"$i"
				sleep 1
				systemctl emergency
			else
				umount /media/"$i"
				rmdir /media/"$i"
			fi
			unset PASSWORD
		fi
	done
fi

if [[ "$1" == "--create-keyfile" ]]
then
	echo "Creating new keyfile..."

	# Check if a specific path was provided as second argument
	if [[ -z "$2" ]]
	then
		echo "No path specified. Using default: /tmp/raw_keyfile.bin"
		RAW_KEYFILE="/tmp/raw_keyfile.bin"
	else
		RAW_KEYFILE="$2"
	fi

	# Generate 4KB of high-entropy random data
	dd if=/dev/urandom of="$RAW_KEYFILE" bs=4096 count=1 status=progress
	chmod 400 "$RAW_KEYFILE"

	# Encrypt the raw key using GPG (AES-256)
	echo "Encrypting keyfile with GPG..."
	gpg --symmetric --cipher-algo AES256 --pinentry-mode loopback --homedir /tmp --passphrase-fd 0 -o ./secret_key.gpg "$RAW_KEYFILE"

	# Securely overwrite the temporary raw key with random data before deletion
	echo "Wiping temporary file..."
	dd if=/dev/urandom of="$RAW_KEYFILE" bs=4096 count=1 conv=fsync status=progress
	rm -f "$RAW_KEYFILE"

	echo "Success: 'secret.key.gpg' created."
	echo "Temporary file '$RAW_KEYFILE' has been securely destroyed."
	exit 0
fi

if [[ "$1" == "--hide-keyfile" ]]
then
	echo "Hiding keyfile in JPG..."

	# Check if all 3 required arguments are present
	if [[ -z "$2" ]] || [[ -z "$3" ]] || [[ -z "$4" ]]
	then
		echo "Error: Missing arguments!"
		echo "Usage: decrypt_drive.sh --hide-keyfile <secret_key.gpg> <original.jpg> <output.jpg>"
		sleep 2
		exit 1
	fi

	# $2 = Keyfile, $3 = Original Image, $4 = Output Image
	cat "$3" <(printf "MYKEYSTART") "$2" > "$4"
	echo "Success: Keyfile '$2' embedded into '$3' and saved as '$4'!"
	sleep 1
	exit 0
fi

if [[ "$1" == "--add-keyfile-to-drive" ]]
then
    echo "Preparing to register hidden key in LUKS..."

    # Check for required argument (the image containing the key)
    if [[ -z "$2" ]]
    then
        echo "Error: Missing argument!"
        echo "Usage: $0 --add-keyfile-to-drive <image_with_key.jpg>"
        sleep 2
        exit 1
    fi

    # 1. Check LUKS Slot Status
    echo "Checking occupied slots for drive: $LUKS_UUID"
    OCCUPIED_SLOTS=$(cryptsetup luksDump /dev/disk/by-uuid/"$LUKS_UUID" | sed -n '/Keyslots:/,/Tokens:/p' | grep -E '^[[:space:]]+[0-7]:' | awk -F'[: ]+' '{print $2}')
    SLOT_COUNT=$(echo "$OCCUPIED_SLOTS" | grep -c [0-7] || echo 0)

    echo "--------------------------------"
    for slot in $OCCUPIED_SLOTS; do
        echo "Slot $slot: [OCCUPIED]"
    done
    echo "Total: $SLOT_COUNT/8 slots used."
    echo "--------------------------------"

    if [ "$SLOT_COUNT" -ge 8 ]; then
        echo "Error: No free LUKS slots available (8/8)."
        sleep 2
        exit 1
    fi

    # 2. Extract and Decrypt Key
    echo "Locating hidden key in '$2'..."
    OFFSET=$(grep -aob "MYKEYSTART" "$2" | head -n 1 | cut -d: -f1)

    if [ -z "$OFFSET" ]; then
        echo "Error: No 'MYKEYSTART' marker found in image!"
        sleep 2
        exit 1
    fi

	# ask for the password via systemd
	GPG_PW=$(systemd-ask-password "AuraKey: Enter GPG-Passphrase for hidden key")

    if [ -z "$GPG_PW" ]; then
        echo "Error: No passphrase entered!"
        exit 1
    fi

    TMP_KEY="/tmp/luks_tmp_$(date +%s).bin"
    echo "Decrypting GPG payload to RAM..."
    
	if ! dd if="$2" bs=1 skip=$((OFFSET + 10)) 2>/dev/null | gpg --decrypt --batch --no-tty --pinentry-mode loopback --homedir /tmp --passphrase-fd 3 3<<< "$GPG_PW" > "$TMP_KEY"
    then
        echo "Error: GPG decryption failed!"
        [ -f "$TMP_KEY" ] && rm -f "$TMP_KEY"
        sleep 2
        exit 1
    fi

    # 3. Add to LUKS
    echo "Adding extracted key to LUKS. Please provide an EXISTING password:"
    if cryptsetup luksAddKey /dev/disk/by-uuid/"$LUKS_UUID" "$TMP_KEY"
    then
        echo "Success: New key from '$2' added to LUKS drive."
        sleep 1
    else
        echo "Error: Failed to add key to LUKS!"
        sleep 2
        # Secure cleanup before exit
        dd if=/dev/urandom of="$TMP_KEY" bs=1024 count=4 status=none && rm -f "$TMP_KEY"
        exit 1
    fi

    # 4. Cleanup
    dd if=/dev/urandom of="$TMP_KEY" bs=1024 count=4 status=none && rm -f "$TMP_KEY"
    echo "Cleanup complete."
    exit 0
fi

if [[ -z "$1" ]] || [[ "$1" == "--help" ]]
then
	echo "Usage: $0 [OPTION] [ARGUMENTS]"
	echo ""
	echo "Options:"
	echo "   --decrypt [ --silent | --verbose ]" "Start the decryption process and mount the drive."
	echo "   --create-keyfile [path]" "Generate a new 4KB random key and encrypt it via GPG."
	echo "   --hide-keyfile <key> <img_in> <img_out>" "Hide a GPG-keyfile inside a JPG image."
	echo "   --add-keyfile-to-drive <img_key>" "Add the hidden key from an image to a LUKS slot."
	echo "   --help" "Show this help message."
	echo ""
	echo "Examples:"
	echo "     $0 --hide-keyfile secret.key.gpg photo.jpg key_image.jpg"
	echo "     $0 --add-keyfile-to-drive key_image.jpg"
	echo ""
	exit 1
fi
