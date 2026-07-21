#!/bin/bash
# get-cert-sans.sh
# Retrieves all Subject Alternative Names (SANs) from every TLS secret
# backing a cert-manager Certificate in a given namespace.
#
# Usage: ./get-cert-sans.sh [namespace]
#   namespace: defaults to iwhi-apic

NAMESPACE="${1:-iwhi-apic}"

echo "=== Certificate SANs in namespace: ${NAMESPACE} ==="
echo ""

# Iterate over every cert-manager Certificate resource
while IFS= read -r cert_name; do
  # Get the secretName the Certificate writes its TLS data into
  secret_name=$(oc get certificate "${cert_name}" -n "${NAMESPACE}" \
    -o jsonpath='{.spec.secretName}' 2>/dev/null)

  if [[ -z "${secret_name}" ]]; then
    echo "  [${cert_name}] WARNING: could not determine secretName, skipping"
    continue
  fi

  # Extract the base64-encoded TLS cert from the secret
  tls_crt=$(oc get secret "${secret_name}" -n "${NAMESPACE}" \
    -o jsonpath='{.data.tls\.crt}' 2>/dev/null)

  if [[ -z "${tls_crt}" ]]; then
    echo "Certificate: ${cert_name}  (secret: ${secret_name})"
    echo "  WARNING: secret not found or tls.crt is empty"
    echo ""
    continue
  fi

  # Decode and extract SANs via openssl
  sans=$(echo "${tls_crt}" | base64 -d 2>/dev/null \
    | openssl x509 -noout -ext subjectAltName 2>/dev/null \
    | grep -v "^X509v3" \
    | tr ',' '\n' \
    | sed 's/^ */  /')

  echo "Certificate: ${cert_name}  (secret: ${secret_name})"
  if [[ -z "${sans}" ]]; then
    echo "  (no SANs found)"
  else
    echo "${sans}"
  fi
  echo ""

done < <(oc get certificates -n "${NAMESPACE}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)
