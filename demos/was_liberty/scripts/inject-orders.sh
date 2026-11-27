#!/usr/bin/env bash
# ==============================================================================
# Script: inject-orders.sh
# Description: Génère des fausses commandes via le générateur Java (faker) et les injecte
#              dans l'API de persistance OrderP (Liberty / PostgreSQL).
# ==============================================================================

set -euo pipefail

# Couleurs pour l'affichage console
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m' # No Color

# Valeurs par défaut
DEFAULT_COUNT=10
DEFAULT_FAKER_URL="${FAKER_URL:-http://localhost:9080/demo/api/order}"
DEFAULT_ORDERP_URL="${ORDERP_URL:-http://localhost:9080/demo/apip/orderp}"
DEFAULT_API_KEY="${API_KEY:-demo-api-key-change-me-in-production}"
DEFAULT_DELAY=0
INSECURE=""
VERBOSE=false

# Paramètres pour l'insertion manuelle d'une commande en dur
MANUAL_CUSTOMER=""
MANUAL_ITEM="Produit Test Manuel"
MANUAL_PRICE="49.99"
MANUAL_QTY="1"
MANUAL_REGION="EMEA"
MANUAL_CUSTOMER_ID=""

COUNT=$DEFAULT_COUNT
FAKER_URL=$DEFAULT_FAKER_URL
ORDERP_URL=$DEFAULT_ORDERP_URL
API_KEY=$DEFAULT_API_KEY
DELAY=$DEFAULT_DELAY

# Fonction d'aide
usage() {
    cat <<EOF
${BOLD}USAGE:${NC}
    $(basename "$0") [OPTIONS]

${BOLD}DESCRIPTION:${NC}
    Génère un nombre configurable de commandes via l'endpoint Faker (Java Datafaker)
    et les injecte une à une via une boucle dans l'endpoint de persistance OrderP.

${BOLD}OPTIONS:${NC}
    -n, --count <N>           Nombre de commandes à générer et injecter (défaut: ${DEFAULT_COUNT})
    -f, --faker-url <URL>     URL de base du générateur faker (défaut: ${DEFAULT_FAKER_URL})
    -t, --target-url <URL>    URL de base de l'API OrderP (défaut: ${DEFAULT_ORDERP_URL})
    -p, --orderp-url <URL>    Alias pour --target-url
    -k, --api-key <KEY>       Clé API pour le header X-API-Key (défaut: ${DEFAULT_API_KEY})
    -d, --delay <SECS>        Délai d'attente en secondes entre chaque injection (défaut: 0)
    -s, --insecure            Désactive la vérification TLS/SSL pour curl (-k)
    -v, --verbose             Affiche les détails complets des requêtes et réponses JSON
    -h, --help                Affiche ce message d'aide

${BOLD}OPTIONS D'INSERTION EN DUR (PERSONNE / COMMANDE UNIQUE) :${NC}
    -c, --customer <NOM>      Nom du client à insérer en dur (ex: "Salim Nekhla")
    --item <DESCRIPTION>      Description de l'article (défaut: "Produit Test Manuel")
    --price <PRIX>            Prix unitaire (défaut: 49.99)
    -q, --quantity <QTE>      Quantité (défaut: 1)
    -r, --region <REGION>     Région: EMEA, APAC, NA, SA, ANZ (défaut: EMEA)
    --customer-id <UUID>      UUID du client (généré automatiquement si omis)

${BOLD}VARIABLES D'ENVIRONNEMENT:${NC}
    FAKER_URL                 URL par défaut du faker
    ORDERP_URL                URL par défaut d'orderp
    API_KEY                   Clé API par défaut
    COUNT                     Nombre de commandes par défaut

${BOLD}EXEMPLES:${NC}
    # 1. Insertion d'une personne en dur :
    ./inject-orders.sh -c "Salim Nekhla" --item "MacBook Pro M3" --price 2499.00 -q 1 -r EMEA -s

    # 2. Injection locale par défaut (10 commandes aléatoires)
    ./inject-orders.sh -n 10

    # Avec URL faker et orderp personnalisées (OpenShift Route ou APIC Gateway)
    ./inject-orders.sh -n 50 \\
        --faker-url "https://orders-api.apps.mycluster.example.com/demo/api/order" \\
        --target-url "https://orders-api.apps.mycluster.example.com/demo/apip/orderp" \\
        --api-key "my-secure-prod-key"

    # Avec un délai de 0.5s entre chaque commande
    ./inject-orders.sh -n 20 --delay 0.5 --verbose

EOF
    exit 0
}

# Parsing des arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--count)
            COUNT="$2"
            shift 2
            ;;
        -f|--faker-url)
            FAKER_URL="$2"
            shift 2
            ;;
        -t|--target-url|-p|--orderp-url)
            ORDERP_URL="$2"
            shift 2
            ;;
        -k|--api-key)
            API_KEY="$2"
            shift 2
            ;;
        -d|--delay)
            DELAY="$2"
            shift 2
            ;;
        -s|--insecure)
            INSECURE="-k"
            shift 1
            ;;
        -v|--verbose)
            VERBOSE=true
            shift 1
            ;;
        -c|--customer)
            MANUAL_CUSTOMER="$2"
            shift 2
            ;;
        --item|--description)
            MANUAL_ITEM="$2"
            shift 2
            ;;
        --price)
            MANUAL_PRICE="$2"
            shift 2
            ;;
        -q|--quantity)
            MANUAL_QTY="$2"
            shift 2
            ;;
        -r|--region)
            MANUAL_REGION="$2"
            shift 2
            ;;
        --customer-id)
            MANUAL_CUSTOMER_ID="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Erreur : Option inconnue '$1'${NC}" >&2
            echo "Utilisez -h ou --help pour afficher l'aide."
            exit 1
            ;;
    esac
done

# Validation des paramètres
if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [ "$COUNT" -le 0 ]; then
    echo -e "${RED}Erreur : Le nombre de commandes (--count) doit être un entier positif (> 0). Reçu: '$COUNT'${NC}" >&2
    exit 1
fi

# Vérification des prérequis
if ! command -v curl &> /dev/null; then
    echo -e "${RED}Erreur : 'curl' est requis mais non installé.${NC}" >&2
    exit 1
fi

# Détection de jq pour un affichage plus lisible si disponible
HAS_JQ=false
if command -v jq &> /dev/null; then
    HAS_JQ=true
fi

# Détection automatique de la route OpenShift si URL par défaut sur localhost
if [[ "$ORDERP_URL" == *"localhost"* ]] && command -v oc &> /dev/null; then
    OC_BACKEND=$(oc get route demo -n backend -o jsonpath='{.spec.host}' 2>/dev/null || true)
    if [ -n "$OC_BACKEND" ]; then
        FAKER_URL="https://${OC_BACKEND}/demo/api/order"
        ORDERP_URL="https://${OC_BACKEND}/demo/apip/orderp"
    fi
fi

# Nettoyage des URLs (suppression du slash final)
FAKER_URL="${FAKER_URL%/}"
ORDERP_URL="${ORDERP_URL%/}"

# Générateur d'UUID portable (Linux/Mac/fallback)
generate_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    elif [ -f /proc/sys/kernel/random/uuid ]; then
        cat /proc/sys/kernel/random/uuid
    else
        # Fallback pseudo-aléatoire
        python3 -c 'import uuid; print(uuid.uuid4())' 2>/dev/null || \
        od -x /dev/urandom | head -1 | awk '{printf "%s-%s-%s-%s-%s\n", $2, $3, $4, $5, $6$7$8}'
    fi
}

# ==============================================================================
# MODE 1 : Insertion manuelle d'une personne en dur (-c / --customer)
# ==============================================================================
if [ -n "$MANUAL_CUSTOMER" ]; then
    ORDER_UUID=$(generate_uuid)
    [ -z "$MANUAL_CUSTOMER_ID" ] && MANUAL_CUSTOMER_ID=$(generate_uuid)

    echo -e "${CYAN}=================================================================${NC}"
    echo -e "${BOLD}       👤 Insertion Manuelle d'une Commande (OrderP)${NC}"
    echo -e "${CYAN}=================================================================${NC}"
    echo -e "  • ${BOLD}Client (en dur)     :${NC} ${GREEN}${MANUAL_CUSTOMER}${NC}"
    echo -e "  • ${BOLD}Customer ID         :${NC} ${MANUAL_CUSTOMER_ID}"
    echo -e "  • ${BOLD}Article             :${NC} ${MANUAL_ITEM}"
    echo -e "  • ${BOLD}Prix unitaire       :${NC} ${MANUAL_PRICE}$"
    echo -e "  • ${BOLD}Quantité            :${NC} ${MANUAL_QTY}"
    echo -e "  • ${BOLD}Région              :${NC} ${MANUAL_REGION}"
    echo -e "  • ${BOLD}URL Cible (OrderP)  :${NC} ${BLUE}${ORDERP_URL}${NC}"
    echo -e "  • ${BOLD}Vérification TLS    :${NC} $([ -n "$INSECURE" ] && echo -e "${YELLOW}Désactivée (-k)${NC}" || echo "Activée")"
    echo -e "${CYAN}=================================================================${NC}"
    echo ""

    # Construction du JSON payload
    if [ "$HAS_JQ" = true ]; then
        PAYLOAD=$(jq -n \
            --arg id "$ORDER_UUID" \
            --arg cust "$MANUAL_CUSTOMER" \
            --arg cid "$MANUAL_CUSTOMER_ID" \
            --arg desc "$MANUAL_ITEM" \
            --arg price "$MANUAL_PRICE" \
            --arg qty "$MANUAL_QTY" \
            --arg reg "$MANUAL_REGION" \
            '{id: $id, customer: $cust, customerid: $cid, description: $desc, price: ($price | tonumber), quantity: ($qty | tonumber), region: $reg}')
    else
        PAYLOAD="{\"id\":\"$ORDER_UUID\",\"customer\":\"$MANUAL_CUSTOMER\",\"customerid\":\"$MANUAL_CUSTOMER_ID\",\"description\":\"$MANUAL_ITEM\",\"price\":$MANUAL_PRICE,\"quantity\":$MANUAL_QTY,\"region\":\"$MANUAL_REGION\"}"
    fi

    if [ "$VERBOSE" = true ]; then
        echo -e "${CYAN}📤 Payload envoyé :${NC} ${PAYLOAD}"
    fi

    HTTP_INJECT_RESPONSE=$(curl -s $INSECURE -w "\nHTTP_STATUS:%{http_code}" \
        -X POST "${ORDERP_URL}" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: ${API_KEY}" \
        -H "Accept: application/json" \
        -d "${PAYLOAD}")

    HTTP_INJECT_BODY=$(echo "$HTTP_INJECT_RESPONSE" | sed -e '$d')
    HTTP_INJECT_STATUS=$(echo "$HTTP_INJECT_RESPONSE" | tail -n 1 | sed 's/HTTP_STATUS://')

    if [[ "$HTTP_INJECT_STATUS" -eq 200 || "$HTTP_INJECT_STATUS" -eq 201 ]]; then
        echo -e "${GREEN}✅ Succès [HTTP $HTTP_INJECT_STATUS] Commande créée pour ${BOLD}${MANUAL_CUSTOMER}${NC}${GREEN} !${NC}"
        echo -e "   ID Commande : ${ORDER_UUID}"
        echo -e "   Réponse : ${HTTP_INJECT_BODY}"
        exit 0
    else
        echo -e "${RED}❌ Échec de l'insertion (HTTP $HTTP_INJECT_STATUS)${NC}"
        echo -e "   URL : ${ORDERP_URL}"
        echo -e "   Body: ${HTTP_INJECT_BODY}"
        exit 1
    fi
fi

# ==============================================================================
# MODE 2 : Injection aléatoire par lot (Faker)
# ==============================================================================
echo -e "${CYAN}=================================================================${NC}"
echo -e "${BOLD}       🚀 Génération et Injection par Lot (Faker -> OrderP)${NC}"
echo -e "${CYAN}=================================================================${NC}"
echo -e "  • ${BOLD}Nombre de commandes :${NC} ${YELLOW}${COUNT}${NC}"
echo -e "  • ${BOLD}URL Faker (Java)    :${NC} ${BLUE}${FAKER_URL}${NC}"
echo -e "  • ${BOLD}URL Cible (OrderP)  :${NC} ${BLUE}${ORDERP_URL}${NC}"
echo -e "  • ${BOLD}Clé API             :${NC} ${API_KEY:0:4}***${API_KEY: -4}"
echo -e "  • ${BOLD}Délai par requête   :${NC} ${DELAY}s"
echo -e "  • ${BOLD}Vérification TLS    :${NC} $([ -n "$INSECURE" ] && echo -e "${YELLOW}Désactivée (-k)${NC}" || echo "Activée")"
echo -e "${CYAN}=================================================================${NC}"
echo ""

SUCCESS_COUNT=0
FAILURE_COUNT=0
START_TIME=$(date +%s)

for (( i=1; i<=COUNT; i++ )); do
    ORDER_UUID=$(generate_uuid)
    
    # 1. Appel au générateur Java (Faker)
    # Si l'URL faker contient déjà un pattern d'ID ou non, on appelle ${FAKER_URL}/${ORDER_UUID}
    FAKER_ENDPOINT="${FAKER_URL}/${ORDER_UUID}"
    
    if [ "$VERBOSE" = true ]; then
        echo -e "${CYAN}[$i/$COUNT]${NC} 📡 Appel du Faker: GET ${FAKER_ENDPOINT}"
    fi

    HTTP_FAKER_RESPONSE=$(curl -s $INSECURE -w "\nHTTP_STATUS:%{http_code}" \
        -X GET "${FAKER_ENDPOINT}" \
        -H "X-API-Key: ${API_KEY}" \
        -H "Accept: application/json")

    HTTP_FAKER_BODY=$(echo "$HTTP_FAKER_RESPONSE" | sed -e '$d')
    HTTP_FAKER_STATUS=$(echo "$HTTP_FAKER_RESPONSE" | tail -n 1 | sed 's/HTTP_STATUS://')

    if [[ "$HTTP_FAKER_STATUS" -ne 200 ]]; then
        echo -e "${RED}[$i/$COUNT] ❌ Échec Faker (HTTP $HTTP_FAKER_STATUS)${NC}"
        echo -e "     URL : ${FAKER_ENDPOINT}"
        echo -e "     Body: ${HTTP_FAKER_BODY}"
        FAILURE_COUNT=$((FAILURE_COUNT + 1))
        continue
    fi

    if [ "$VERBOSE" = true ]; then
        echo -e "${CYAN}[$i/$COUNT]${NC} 📦 Données Faker reçues: ${HTTP_FAKER_BODY}"
    fi

    # Extraction des infos pour un affichage propre
    CUSTOMER="Inconnu"
    PRICE="0"
    QTY="0"
    REGION="N/A"
    if [ "$HAS_JQ" = true ]; then
        CUSTOMER=$(echo "$HTTP_FAKER_BODY" | jq -r '.customer // "Inconnu"' 2>/dev/null || echo "Inconnu")
        PRICE=$(echo "$HTTP_FAKER_BODY" | jq -r '.price // 0' 2>/dev/null || echo "0")
        QTY=$(echo "$HTTP_FAKER_BODY" | jq -r '.quantity // 0' 2>/dev/null || echo "0")
        REGION=$(echo "$HTTP_FAKER_BODY" | jq -r '.region // "N/A"' 2>/dev/null || echo "N/A")
    fi

    # 2. Injection dans OrderP
    if [ "$VERBOSE" = true ]; then
        echo -e "${CYAN}[$i/$COUNT]${NC} 📤 Injection vers OrderP: POST ${ORDERP_URL}"
    fi

    HTTP_INJECT_RESPONSE=$(curl -s $INSECURE -w "\nHTTP_STATUS:%{http_code}" \
        -X POST "${ORDERP_URL}" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: ${API_KEY}" \
        -H "Accept: application/json" \
        -d "${HTTP_FAKER_BODY}")

    HTTP_INJECT_BODY=$(echo "$HTTP_INJECT_RESPONSE" | sed -e '$d')
    HTTP_INJECT_STATUS=$(echo "$HTTP_INJECT_RESPONSE" | tail -n 1 | sed 's/HTTP_STATUS://')

    if [[ "$HTTP_INJECT_STATUS" -eq 200 || "$HTTP_INJECT_STATUS" -eq 201 ]]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        echo -e "${GREEN}[$i/$COUNT] ✅ [HTTP $HTTP_INJECT_STATUS] ID: ${ORDER_UUID:0:8}... | Client: ${CUSTOMER} | Région: ${REGION} | Qte: ${QTY} | Prix: ${PRICE}$ ${NC}"
    else
        FAILURE_COUNT=$((FAILURE_COUNT + 1))
        echo -e "${RED}[$i/$COUNT] ❌ Échec Injection OrderP (HTTP $HTTP_INJECT_STATUS)${NC}"
        echo -e "     URL : ${ORDERP_URL}"
        echo -e "     Body: ${HTTP_INJECT_BODY}"
    fi

    # Délai optionnel entre les requêtes
    if (( $(echo "$DELAY > 0" | bc -l 2>/dev/null || echo 0) )); then
        sleep "$DELAY"
    fi
done

END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))

echo ""
echo -e "${CYAN}=================================================================${NC}"
echo -e "${BOLD}                     📊 Résumé de l'exécution${NC}"
echo -e "${CYAN}=================================================================${NC}"
echo -e "  • ${BOLD}Total demandé        :${NC} ${COUNT}"
echo -e "  • ${BOLD}Succès               :${NC} ${GREEN}${SUCCESS_COUNT}${NC}"
echo -e "  • ${BOLD}Échecs               :${NC} $([ "$FAILURE_COUNT" -gt 0 ] && echo -e "${RED}${FAILURE_COUNT}${NC}" || echo -e "${GREEN}0${NC}")"
echo -e "  • ${BOLD}Durée totale         :${NC} ${TOTAL_DURATION}s"
echo -e "${CYAN}=================================================================${NC}"

if [ "$FAILURE_COUNT" -gt 0 ]; then
    exit 1
fi

exit 0
