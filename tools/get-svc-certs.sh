#!/bin/bash
# get-svc-certs.sh
# For every Service in a namespace, reports the cert-manager Certificate(s)
# whose dnsNames or secretName are associated with that service, together with
# the hostnames (cluster-internal FQDN and any OpenShift Route host) for that service.
#
# Three association strategies are applied in order:
#   1. Direct secret annotation   - service has annotation cert-manager.io/secret-name
#   2. Secret volume mount        - pods backing the service mount a TLS secret that is
#                                   also the secretName of a Certificate
#   3. DNS name match             - a Certificate's spec.dnsNames contains a name that
#                                   includes the service name (svc, svc.ns, svc.ns.svc.cluster.local)
#
# Usage: ./get-svc-certs.sh [namespace]
#   namespace: defaults to iwhi-apic

NAMESPACE="${1:-iwhi-apic}"

echo "=== Service → Certificate mapping in namespace: ${NAMESPACE} ==="
echo ""

# ── helper: look up cert by secretName ───────────────────────────────────────
cert_for_secret() {
  local secret="$1"
  oc get certificates -n "${NAMESPACE}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.secretName}{"\n"}{end}' \
    2>/dev/null \
    | awk -v s="${secret}" '$2 == s { print $1 }'
}

# ── helper: certs whose dnsNames mention a given service name ─────────────────
certs_for_svc_dns() {
  local svc="$1"
  # Match patterns: <svc>, <svc>.<ns>, <svc>.<ns>.svc, <svc>.<ns>.svc.cluster.local
  oc get certificates -n "${NAMESPACE}" \
    -o json 2>/dev/null \
    | jq -r --arg svc "${svc}" --arg ns "${NAMESPACE}" '
        .items[] |
        . as $cert |
        (.spec.dnsNames // [])[] |
        select(
          . == $svc or
          . == ($svc + "." + $ns) or
          startswith($svc + "." + $ns + ".svc")
        ) |
        $cert.metadata.name
      ' \
    | sort -u
}

# ── pre-load: map Route host(s) per service (spec.to.name → host) ────────────
declare -A SVC_ROUTE_HOSTS
while IFS=$'\t' read -r svc_ref route_host; do
  [[ -z "${svc_ref}" || -z "${route_host}" ]] && continue
  if [[ -n "${SVC_ROUTE_HOSTS[$svc_ref]}" ]]; then
    SVC_ROUTE_HOSTS["${svc_ref}"]="${SVC_ROUTE_HOSTS[$svc_ref]}, ${route_host}"
  else
    SVC_ROUTE_HOSTS["${svc_ref}"]="${route_host}"
  fi
done < <(oc get routes -n "${NAMESPACE}" \
  -o jsonpath='{range .items[*]}{.spec.to.name}{"\t"}{.spec.host}{"\n"}{end}' \
  2>/dev/null)

# ── pre-load: map secretName → cert name for volume-mount strategy ───────────
declare -A SECRET_TO_CERT
while IFS=$'\t' read -r cert_name secret_name; do
  [[ -n "${secret_name}" ]] && SECRET_TO_CERT["${secret_name}"]="${cert_name}"
done < <(oc get certificates -n "${NAMESPACE}" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.secretName}{"\n"}{end}' \
  2>/dev/null)

# ── iterate over every Service ────────────────────────────────────────────────
found_any=false

while IFS= read -r svc_name; do
  [[ -z "${svc_name}" ]] && continue
  found_any=true

  # Build hostname label: internal FQDN + any Route hosts
  internal_fqdn="${svc_name}.${NAMESPACE}.svc.cluster.local"
  hostnames="${internal_fqdn}"
  if [[ -n "${SVC_ROUTE_HOSTS[$svc_name]}" ]]; then
    hostnames="${hostnames}, ${SVC_ROUTE_HOSTS[$svc_name]}"
  fi

  declare -A seen_certs=()
  results=()

  # Strategy 1 – annotation
  ann_secret=$(oc get svc "${svc_name}" -n "${NAMESPACE}" \
    -o jsonpath='{.metadata.annotations.cert-manager\.io/secret-name}' 2>/dev/null)
  if [[ -n "${ann_secret}" ]]; then
    cert=$(cert_for_secret "${ann_secret}")
    if [[ -n "${cert}" && -z "${seen_certs[$cert]}" ]]; then
      results+=("${cert} (via annotation → secret: ${ann_secret})")
      seen_certs["${cert}"]=1
    fi
  fi

  # Strategy 2 – secret volumes on pods selected by the service
  selector=$(oc get svc "${svc_name}" -n "${NAMESPACE}" \
    -o jsonpath='{.spec.selector}' 2>/dev/null)
  if [[ -n "${selector}" && "${selector}" != "{}" ]]; then
    label_sel=$(oc get svc "${svc_name}" -n "${NAMESPACE}" \
      -o jsonpath='{range .spec.selector}{@key}{"="}{@value}{","}{end}' 2>/dev/null \
      | sed 's/,$//')
    if [[ -n "${label_sel}" ]]; then
      # Collect TLS secrets mounted in backing pods
      while IFS= read -r vol_secret; do
        [[ -z "${vol_secret}" ]] && continue
        cert="${SECRET_TO_CERT[$vol_secret]:-}"
        if [[ -n "${cert}" && -z "${seen_certs[$cert]}" ]]; then
          results+=("${cert} (via pod volume → secret: ${vol_secret})")
          seen_certs["${cert}"]=1
        fi
      done < <(oc get pods -n "${NAMESPACE}" -l "${label_sel}" \
        -o jsonpath='{range .items[*]}{range .spec.volumes[*]}{.secret.secretName}{"\n"}{end}{end}' \
        2>/dev/null | sort -u)
    fi
  fi

  # Strategy 3 – DNS name match
  while IFS= read -r cert; do
    [[ -z "${cert}" ]] && continue
    if [[ -z "${seen_certs[$cert]}" ]]; then
      results+=("${cert} (via dnsNames)")
      seen_certs["${cert}"]=1
    fi
  done < <(certs_for_svc_dns "${svc_name}")

  # Output
  if [[ ${#results[@]} -eq 0 ]]; then
    echo "Service: ${svc_name} (${hostnames})"
    echo "  (no associated Certificate found)"
  else
    echo "Service: ${svc_name} (${hostnames})"
    for r in "${results[@]}"; do
      echo "  Certificate: ${r}"
    done
  fi
  echo ""

  unset seen_certs

done < <(oc get svc -n "${NAMESPACE}" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)

if ! $found_any; then
  echo "No services found in namespace ${NAMESPACE}."
fi
