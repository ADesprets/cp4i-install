#!/usr/bin/env bash
# Exporte les accès IDIG (URLs + identifiants lus dans les secrets du cluster) vers un fichier local.
# Le fichier est créé HORS du dépôt git, avec des droits 600. Ne le commitez jamais.
# Usage : ./export-idig-credentials.sh [namespace] [fichier_sortie]
set -euo pipefail

NS="${1:-ibmint-idig}"
OUT="${2:-${HOME}/idig-credentials.txt}"
CR_KIND="DatapowerInteractGatewayCluster"

CR=$(oc -n "${NS}" get "${CR_KIND}" -o jsonpath='{.items[0].metadata.name}')
API=$(oc whoami --show-server)
CONSOLE=$(oc -n "${NS}" get "${CR_KIND}" "${CR}" -o jsonpath='{.status.endpoints[?(@.name=="idigWeb")].uri}')
DP_WEB=$(oc -n "${NS}" get route "${CR}-devportal-devportal-web" -o jsonpath='{.spec.host}')
DP_ADMIN=$(oc -n "${NS}" get route "${CR}-devportal-devportal-admin" -o jsonpath='{.spec.host}')
GW_DOMAIN=$(oc -n "${NS}" get "${CR_KIND}" "${CR}" -o jsonpath='{.spec.nanoGateway.gatewayDomain}')
VERSION=$(oc -n "${NS}" get "${CR_KIND}" "${CR}" -o jsonpath='{.spec.version}')
CONSOLE_PWD=$(oc -n "${NS}" get secret "${CR}-idig-admin-pass" -o jsonpath='{.data.password}' | base64 -d)
DP_PWD=$(oc -n "${NS}" get secret "${CR}-devportal-admin-secret" -o jsonpath='{.data.password}' | base64 -d)

umask 077
cat > "${OUT}" <<EOF
IBM DataPower Interact Gateway (IDIG) ${VERSION}
Genere le : $(date '+%Y-%m-%d %H:%M:%S')

CLUSTER
  API OpenShift : ${API}
  Namespace     : ${NS}
  CR            : ${CR_KIND}/${CR}

CONSOLE IDIG
  URL           : ${CONSOLE}
  Utilisateur   : administrator
  Mot de passe  : ${CONSOLE_PWD}
  Source        : secret ${CR}-idig-admin-pass (cle: password, namespace ${NS})

PORTAIL DEVELOPPEUR
  URL web       : https://${DP_WEB}
  URL admin/API : https://${DP_ADMIN}
  Utilisateur   : administrator
  Mot de passe  : ${DP_PWD}
  Source        : secret ${CR}-devportal-admin-secret (cle: password, namespace ${NS})

NANO GATEWAY (APIs publiees)
  Domaine       : *.${GW_DOMAIN}

RELIRE LES MOTS DE PASSE
  oc -n ${NS} get secret ${CR}-idig-admin-pass -o jsonpath='{.data.password}' | base64 -d; echo
  oc -n ${NS} get secret ${CR}-devportal-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
EOF
chmod 600 "${OUT}"
echo "Fichier genere : ${OUT}"
