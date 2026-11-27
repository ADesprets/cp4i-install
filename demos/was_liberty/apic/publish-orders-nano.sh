#!/bin/bash
# Gère le projet API Studio Orders_Nano sur API Connect 12.1 (DataPower Nano Gateway).
#
#   ./publish-orders-nano.sh download [dossier]   API Manager -> disque  (apic export)
#   ./publish-orders-nano.sh upload               disque -> API Manager  (apic import, sans publier)
#   ./publish-orders-nano.sh publish              disque -> catalogue + gateway (apic build + publish-project)
#
# Sans argument : publish.
# La clé backend (Secret orders-api-keys) n'est JAMAIS écrite dans le dépôt ni dans API Manager par
# upload/download : elle est injectée uniquement dans le zip temporaire de publish.
# Prérequis : oc connecté, apic, jq, curl. Mot de passe org owner : APIC_ORG1_PASSWORD
# (sinon lu dans demos/apic_simple/properties/apic.properties).
set -euo pipefail

ACTION="${1:-publish}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT=Orders_Nano
APIC_NS="${APIC_NS:-iwhi-apic}"
BACKEND_NS="${BACKEND_NS:-backend}"
ORG="${APIC_ORG:-org1}"
CATALOG="${APIC_CATALOG:-sandbox}"
GATEWAY_SERVICE="${APIC_GATEWAY_SERVICE:-datapower-nano-gateway}"
PROPS="$HERE/../../apic_simple/properties/apic.properties"
PLACEHOLDER="__BACKEND_API_KEY__"
KEY_FILE=Orders_SetBackendKey.yml

log(){ printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die(){ log "ERREUR : $*" >&2; exit 1; }
apic_q(){ apic "$@" 2>&1 | grep -v -E "^\(node:|^\(Use .node|^WARNING|^Warning:|node --trace" || true; }

case "$ACTION" in download|upload|publish) ;; *) die "usage : $0 download [dossier] | upload | publish" ;; esac
for t in oc apic jq curl; do command -v "$t" >/dev/null || die "outil manquant : $t"; done
oc whoami >/dev/null 2>&1 || die "oc n'est pas connecté au cluster"

# ---------- 1. Accès API Manager ----------
OWNER="${APIC_ORG1_USERNAME:-$(grep -E '^APIC_ORG1_USERNAME=' "$PROPS" | cut -d= -f2-)}"
OWNER_PW="${APIC_ORG1_PASSWORD:-$(grep -E '^APIC_ORG1_PASSWORD=' "$PROPS" | cut -d= -f2-)}"
API="https://$(oc get route apic-mgmt-platform-api -n "$APIC_NS" -o jsonpath='{.spec.host}')"
log "Platform API : $API (org=$ORG, catalogue=$CATALOG, utilisateur=$OWNER, realm=provider/default-idp-2)"
CRED="$(oc get secret apic-mgmt-cli-cred -n "$APIC_NS" -o jsonpath='{.data.credential\.json}' | base64 --decode)"
TOKEN="$(jq -n --arg u "$OWNER" --arg p "$OWNER_PW" --arg i "$(jq -r .id <<<"$CRED")" --arg s "$(jq -r .secret <<<"$CRED")" \
  '{username:$u,password:$p,realm:"provider/default-idp-2",client_id:$i,client_secret:$s,grant_type:"password"}' \
  | curl -sk -X POST "$API/api/token" -H 'Content-Type: application/json' -H 'Accept: application/json' --data-binary @- \
  | jq -r '.access_token // empty')"
[ -n "$TOKEN" ] || die "échec d'authentification API Manager"
log "Jeton obtenu (client du CLI lu dans le Secret $APIC_NS/apic-mgmt-cli-cred)"

# ---------- download : API Manager -> disque ----------
if [ "$ACTION" = download ]; then
  DEST="${2:-$HERE/download/$(date +%Y%m%d-%H%M%S)}"
  mkdir -p "$DEST"
  log "download : export du projet $PROJECT depuis API Manager (apic export, org=$ORG)"
  OUT="$(apic_q export "$PROJECT" -s "$API" -o "$ORG" --token "$TOKEN" -l "$DEST")"
  echo "$OUT"
  ZIP="$DEST/studio-$PROJECT-export.zip"
  [ -s "$ZIP" ] || die "export introuvable ($ZIP) : le projet $PROJECT existe-t-il dans API Manager ? (lancer 'upload')"
  log "archive reçue : $ZIP ($(wc -c <"$ZIP" | tr -d ' ') octets)"
  mkdir -p "$DEST/$PROJECT"
  unzip -q -o "$ZIP" -d "$DEST/$PROJECT"
  # La clé backend ne doit jamais rester en clair sur le disque : on la remplace par le placeholder.
  if [ -f "$DEST/$PROJECT/$KEY_FILE" ]; then
    if grep -q "$PLACEHOLDER" "$DEST/$PROJECT/$KEY_FILE"; then
      log "$KEY_FILE contient déjà le placeholder $PLACEHOLDER (aucune clé en clair)"
    else
      sed -i.bak -E "s|^( *value: ).*|\1${PLACEHOLDER}|" "$DEST/$PROJECT/$KEY_FILE" && rm -f "$DEST/$PROJECT/$KEY_FILE.bak"
      log "clé backend retrouvée dans l'export et remplacée par $PLACEHOLDER dans $KEY_FILE"
    fi
  fi
  log "fichiers dans $DEST/$PROJECT :"; (cd "$DEST/$PROJECT" && find . -type f | sort | sed 's/^/    /')
  if diff -rq "$HERE/$PROJECT" "$DEST/$PROJECT" --exclude=.studio-project.json --exclude=Orders_Api-spec.yml >/tmp/.dl-diff 2>&1; then
    log "comparaison avec le dépôt : identique ($PROJECT)"
  else
    log "comparaison avec le dépôt : différences"; sed 's/^/    /' /tmp/.dl-diff
  fi
  rm -f /tmp/.dl-diff
  log "download terminé -> $DEST/$PROJECT"
  exit 0
fi

# ---------- préparation locale commune à upload et publish ----------
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
log "dossier temporaire : $STAGE (supprimé à la fin)"
(cd "$STAGE" && apic_q create "$PROJECT" -l "$STAGE" >/dev/null)
[ -d "$STAGE/$PROJECT" ] || die "apic create n'a pas créé le projet"
cp "$HERE/$PROJECT/"*.yml "$STAGE/$PROJECT/"
cp "$HERE/../openapi-orderp.yaml" "$STAGE/$PROJECT/Orders_Api-spec.yml"
log "copié $(ls "$HERE/$PROJECT/"*.yml | wc -l | tr -d ' ') fichiers YAML + openapi-orderp.yaml (-> Orders_Api-spec.yml)"

if [ "$ACTION" = publish ]; then
  BACKEND_KEY="$(oc get secret orders-api-keys -n "$BACKEND_NS" -o jsonpath='{.data.api-keys}' | base64 --decode | cut -d, -f1)"
  [ -n "$BACKEND_KEY" ] || die "clé backend introuvable (Secret $BACKEND_NS/orders-api-keys)"
  sed -i.bak "s|$PLACEHOLDER|${BACKEND_KEY}|" "$STAGE/$PROJECT/$KEY_FILE" && rm -f "$STAGE/$PROJECT/"*.bak
  log "clé backend (1re de la liste du Secret $BACKEND_NS/orders-api-keys) injectée dans $KEY_FILE du zip temporaire uniquement"
fi

LINT="$(apic_q lint "$PROJECT" -l "$STAGE")"
grep -q "No errors or warnings found" <<<"$LINT" || { echo "$LINT" >&2; die "lint en erreur"; }
log "apic lint : aucune erreur ni avertissement"

# ---------- upload : disque -> API Manager (sans publier) ----------
if [ "$ACTION" = upload ]; then
  log "upload : import du projet $PROJECT dans API Manager (org=$ORG), sans publication"
  OUT="$(apic_q import "$PROJECT" -l "$STAGE" -s "$API" -o "$ORG" --token "$TOKEN")"
  echo "$OUT"
  grep -qiE "error|fail" <<<"$OUT" && die "l'import a échoué"
  PROJ="$(curl -sk -H "Authorization: Bearer $TOKEN" -H 'Accept: application/json' "$API/api/orgs/$ORG/projects/$PROJECT")"
  log "projet dans API Manager : $(jq -r '[.name,.title,.created_at // .updated_at]|map(select(.!=null))|join(" | ")' <<<"$PROJ")"
  log "upload terminé (la clé backend n'est pas stockée : elle reste $PLACEHOLDER)"
  exit 0
fi

# ---------- publish : disque -> catalogue + gateway ----------
apic_q build "$PROJECT" -l "$STAGE" -o "$STAGE/project.zip" >/dev/null
[ -s "$STAGE/project.zip" ] || die "apic build a échoué"
log "apic build : $(basename "$STAGE/project.zip") $(wc -c <"$STAGE/project.zip" | tr -d ' ') octets"

log "publish : POST $API/api/catalogs/$ORG/$CATALOG/publish-project?gateway_services=$GATEWAY_SERVICE&migrate_subscriptions=true"
RESP="$(curl -sk -w '\n%{http_code}' -X POST \
  -H "Authorization: Bearer $TOKEN" -H 'Accept: application/json' \
  -F "project=@$STAGE/project.zip;type=application/zip" \
  "$API/api/catalogs/$ORG/$CATALOG/publish-project?gateway_services=$GATEWAY_SERVICE&migrate_subscriptions=true")"
CODE="$(tail -n1 <<<"$RESP")"; BODY="$(sed '$d' <<<"$RESP")"
log "réponse HTTP $CODE"
if [ "$CODE" = 201 ]; then
  jq -r '(.products // [])[]? | "    produit \(.name) \(.version) : \(.state)"' <<<"$BODY" 2>/dev/null || true
  jq -r '(.apis // [])[]? | "    API \(.name) \(.version) : \(.state)"' <<<"$BODY" 2>/dev/null || true
  log "publish terminé"
else
  echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
  die "publish refusé (HTTP $CODE)"
fi
