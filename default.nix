# Documentation: https://nixos.org/manual/nixpkgs/stable/#sec-pkgs-dockerTools
# https://nixos.wiki/wiki/Docker
# Build and load into docker: docker load <(nix-build dyndns-updater.nix)
# Build and push into registry: skopeo copy docker-archive:/dev/stdin docker://docker.io/jceb/regfish-dyndns-updater:latest <(nix-build dyndns-updater.nix)
# Inspect the image: skopeo inspect docker-archive:/dev/stdin <(nix-build dyndns-updater.nix) | yq e '.Digest' | sed -n -e "s/sha256:.*\(......\)/$(date +%Y-%m-%d)-\1/p"
# TODO: replace with nixos-23.xx .. with the new buildImage API
{ pkgs ? import <nixpkgs-unstable> { system = "x86_64-linux"; } }:
let
  updater = (with pkgs;
    writeShellApplication {
      name = "updater.sh";
      runtimeInputs = [ curl iproute2 gawk gnugrep gnused ];
      text = ''
        # regfish.com DynDNS Version 2 fuer Linux
        # --------------------------------------------------
        # Fuehren Sie dieses Script jede Minute mit Hilfe
        # eines Cronjobs aus.
        # --------------------------------------------------
        # Version 2.05
        # Letzte Aenderung: 08.06.2016
        # Copyright (c) regfish.com
        # --------------------------------------------------

        # Folgende Werte muessen von Ihnen angepasst werden.
        # --------------------------------------------------
        # FQDN = Hostname (z.B. meinrechner.meinedomain.de.)
        # TOKEN = Secure-Token zur Authentifizierung
        # IPversion = ipv4 oder ipv46 (ipv4 und ipv6)
        # --------------------------------------------------
        # Generate token here: https://www.regfish.de/my/domains/*/com/41ppl/dyndns/
        # FQDN=domain.
        # TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

        #IPversion=ipv4
        IPversion=ipv46
        # --------------------------------------------------

        IPV4_FILE="/tmp/regfish_myIPv4_''${FQDN}"
        IPV6_FILE="/tmp/regfish_myIPv6_''${FQDN}"

        update_ipv4() {
        	aIPv4="$(curl -4 -s 'http://icanhazip.com/')"
        	touch "''${IPV4_FILE}"
        	SIPv4="$(cat "''${IPV4_FILE}")"

        	#
        	# Wenn die IP-Adresse sich geaendert hat, wird
        	# eine DynDNS-Aktualisierung durchgefuehrt.
        	#
        	if [ "''${aIPv4}" = "''${SIPv4}" ]; then
        		exit 0
        	else
        		if [ -z "''${aIPv4}" ]; then
        			exit 1
        		fi
        		rCode=$(curl -4 -s "https://dyndns.regfish.de/?fqdn=''${FQDN}&thisipv4=1&forcehost=1&authtype=secure&token=''${TOKEN}&ttl=300")
        		# echo curl -4 -s "https://dyndns.regfish.de/?fqdn=''${FQDN}&thisipv4=1&forcehost=1&authtype=secure&token=''${TOKEN}"
        		# rCode="success|100|update succeeded!"

        		if [ "''${rCode}" = "success|100|update succeeded!" ] || [ "''${rCode}" = "success|101|already up-to-date!" ]; then
        			echo "''${aIPv4}" | tee "''${IPV4_FILE}"
        		else
        			echo "''${rCode}"
        		fi
        	fi
        }

        update_ipv46() {
        	aIPv4="$(curl -4 -s 'http://icanhazip.com/')"
        	touch "''${IPV4_FILE}"
        	SIPv4="$(cat "''${IPV4_FILE}")"
        	# I've no idea of how to disable ipv6 privacy extensions temporarily for one connection so this is a workaround
        	aIPv6=$(curl -6 -s 'http://icanhazip.com/')
        	# aIPv6="$(ip -6 -o a s dynamic up primary scope global | grep -v deprecated | grep -v 'inet6 fd' | awk '{print $4}' | sed -ne 's#/.*##p' | head -n 1)"
        	touch "''${IPV6_FILE}"
        	SIPv6="$(cat "''${IPV6_FILE}")"

        	#
        	# Wenn die IP-Adresse sich geaendert hat, wird
        	# eine DynDNS-Aktualisierung durchgefuehrt.
        	#
        	if [ "''${aIPv4}" = "''${SIPv4}" ] && [ "''${aIPv6}" = "''${SIPv6}" ]; then
        		exit 0
        	else
        		if [ -z "''${aIPv4}" ] || [ -z "''${aIPv6}" ]; then
        			exit 1
        		fi
        		# echo curl -4 -s "https://dyndns.regfish.de/?fqdn=''${FQDN}&thisipv4=1&ipv6=''${aIPv6}&forcehost=1&authtype=secure&token=''${TOKEN}"
        		# rCode="success|100|update succeeded!"
        		rCode=$(curl -4 -s "https://dyndns.regfish.de/?fqdn=''${FQDN}&thisipv4=1&ipv6=''${aIPv6}&forcehost=1&authtype=secure&token=''${TOKEN}&ttl=300")

        		if [ "''${rCode}" = "success|100|update succeeded!" ] || [ "''${rCode}" = "success|101|already up-to-date!" ] || [ "''${rCode}" = "good ''${aIPv4}" ] || [ "''${rCode}" = "nochg" ]; then
        			echo "''${aIPv4}" | tee "''${IPV4_FILE}"
        			echo "''${aIPv6}" | tee "''${IPV6_FILE}"
        		else
        			echo "''${rCode}"
        		fi
        	fi
        }

        if [ "''${IPversion}" = "ipv4" ]; then
        	update_ipv4
        elif [ "''${IPversion}" = "ipv46" ]; then
        	update_ipv46
        fi
      '';
    });
  entrypoint = (with pkgs;
    writeShellApplication {
      name = "entrypoint.sh";
      runtimeInputs = [ updater ];
      text = ''
        while true; do
        	updater.sh
        	sleep "''${INTERVAL:-60}"
        done
      '';
    });
  # in pkgs.dockerTools.buildImage {
in pkgs.dockerTools.streamLayeredImage {
  name = "jceb/regfish-dyndns-updater";
  # created = "now";
  contents = with pkgs.dockerTools; [
    usrBinEnv
    binSh
    caCertificates
    fakeNss
    updater
    entrypoint
    pkgs.coreutils
  ];
  fakeRootCommands = ''
    mkdir /tmp
    chmod 1777 /tmp
  '';
  enableFakechroot = true;
  config = {
    # Valid values, see: https://github.com/moby/moby/blob/master/image/spec/v1.2.md#image-json-field-descriptions
    Cmd = [ "/bin/entrypoint.sh" ];
    # User and group noboby
    User = "65534";
    Group = "65534";
  };
}
