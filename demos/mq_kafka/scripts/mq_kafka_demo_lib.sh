################################################
# Create a jks truststore for a java application
# @param 1: resource name
# @param 2: source directory
function create_jks_truststore() {
  local lf_tracelevel=5
  trace_in $lf_tracelevel create_jks_truststore

  local lf_in_cr=$1
  local lf_in_source_directory=$2
  decho $lf_tracelevel "Parameters:\"$1\"|\"$2\"|\"$3\"|"

  if [[ $# -ne 2 ]]; then
    mylog error "You have to provide 2 arguments : resource name and source directory"
    trace_out $lf_tracelevel create_jks_truststore
    exit  1
  fi

  # We suppose that the p12 file has the following convention naming : <resource_name>.p12
  local lf_p12_file="${lf_in_source_directory}${lf_in_cr}.p12"
  local lf_jks_file="${lf_in_source_directory}${lf_in_cr}.jks"


  keytool -importkeystore -deststorepass $VAR_MQ_KAFKA_DEM0_PASSWORD -destkeypass $VAR_MQ_KAFKA_DEM0_PASSWORD -destkeystore $lf_in_cr \
          -srckeystore "${lf_p12_file}" -srcstoretype PKCS12 -srcstorepass $VAR_MQ_KAFKA_DEM0_PASSWORD -alias "${lf_in_cr}-pkcs12"

  trace_out $lf_tracelevel create_jks_truststore

${PREFIX}-ca.jks: ${PREFIX}-ca.crt
	rm -f ${PREFIX}-ca.jks
	keytool -keystore ${PREFIX}-ca.jks \
		-deststorepass passw0rd \
		-storetype jks \
		-importcert \
		-file ${PREFIX}-ca.crt \
		-alias ca-certificate \
		-noprompt

}

################################################
# Create a jks keystore for a java application
# @param 1: resource name
# @param 2: source directory
function create_jks_keystore() {
  local lf_tracelevel=5
  trace_in $lf_tracelevel create_jks_keystore

  local lf_in_cr=$1
  local lf_in_source_directory=$2
  decho $lf_tracelevel "Parameters:\"$1\"|\"$2\"|\"$3\"|"

  if [[ $# -ne 2 ]]; then
    mylog error "You have to provide 2 arguments : resource name and source directory"
    trace_out $lf_tracelevel create_jks_keystore
    exit  1
  fi

  # We suppose that the p12 file has the following convention naming : <resource_name>.p12
  local lf_p12_file="${lf_in_source_directory}${lf_in_cr}.p12"
  local lf_jks_file="${lf_in_source_directory}${lf_in_cr}.jks"


  keytool -importkeystore -deststorepass $VAR_MQ_KAFKA_DEM0_PASSWORD -destkeypass $VAR_MQ_KAFKA_DEM0_PASSWORD -destkeystore $lf_in_cr \
          -srckeystore "${lf_p12_file}" -srcstoretype PKCS12 -srcstorepass $VAR_MQ_KAFKA_DEM0_PASSWORD -alias "${lf_in_cr}-pkcs12"

  trace_out $lf_tracelevel create_jks_keystore
}

################################################
# Creates a pkcs p12 certificate from key and crt
# @param 1: the resource name
# @param 2: source directory (directory hosting the crt and key certificates)
# @param 3: target directory (directory where to save the pkcs p12 certificate
function create_p12_certificate() {
  local lf_tracelevel=5
  trace_in $lf_tracelevel create_p12_certificate

  local lf_in_cr=$1
  local lf_in_source_directory=$2
  local lf_in_target_directory=$3
  decho $lf_tracelevel "Parameters:\"$1\"|\"$2\"|\"$3\"|"

  if [[ $# -ne 3 ]]; then
    mylog error "You have to provide 2 arguments : resource name, crt file, key file and destination directory"
    trace_out $lf_tracelevel create_p12_certificate
    exit  1
  fi

  # We suppose that the crt and key files are stored in source directory and have the following convention naming : <resource_name>.crt and <resource_name>.key
  local lf_crt_file="${lf_in_source_directory}${lf_in_cr}.crt"
  local lf_key_file="${lf_in_source_directory}${lf_in_cr}.key"
  local lf_p12_file="${lf_in_target_directory}${lf_in_cr}.p12"

  #openssl pkcs12 -export $lf_in_crt_file -inkey $lf_in_key_file -out "${lf_p12_file}" -passout pass:$VAR_MQ_KAFKA_DEM0_PASSWORD -name "${lf_in_cr}-pkcs12"
  openssl pkcs12 -export -out "${lf_p12_file}" -inkey $lf_key_file -in $lf_crt_file -password pass:$VAR_MQ_KAFKA_DEM0_PASSWORD

  trace_out $lf_tracelevel create_p12_certificate
}

################################################
# Creates a jks keystore and trust store for a Java application
# @param 1: namespace where the secret exist
# @param 2: name of the secret
# @param 3: Data in the secret that contains the certificate
# @param 4: Directory where to save the certificate
##################################################
function create_jks_keystore_secret() {
  local lf_tracelevel=5
  trace_in $lf_tracelevel create_jks_keystore_secret

  local lf_in_ns=$1
  local lf_in_secret_name=$2
  local lf_in_data_name=$3
  local lf_in_destination_path=$4
  decho $lf_tracelevel "Parameters:\"$1\"|\"$2\"|\"$3\"|\"$4\"|"

  if [[ $# -ne 4 ]]; then
    mylog error "You have to provide 4 arguments : namespace, secret_name, data_name and destination directory path"
    trace_out $lf_tracelevel create_jks_keystore_secret
    exit  1
  fi

  local lf_data_normalised=$(sed 's/\./\\./g' <<< ${lf_in_data_name})

  mylog info "Save certificate ${lf_in_secret_name} to ${lf_in_destination_path}${lf_in_secret_name}.${lf_in_data_name}.pem" 0
  decho $lf_tracelevel "$MY_CLUSTER_COMMAND -n $lf_in_ns get secret ${lf_in_secret_name} -o jsonpath=\"{.data.$lf_data_normalised}\""
  local lf_cert=$($MY_CLUSTER_COMMAND -n $lf_in_ns get secret ${lf_in_secret_name} -o jsonpath="{.data.$lf_data_normalised}")

  echo $lf_cert | base64 --decode >"${lf_in_destination_path}${lf_in_secret_name}.${lf_in_data_name}.pem"

  trace_out $lf_tracelevel create_jks_keystore_secret
}

################################################
# Creates a jks keystore and trust store for a Java application
# @param 1: namespace where the secret exist
# @param 2: name of the secret
# @param 3: Data in the secret that contains the certificate
# @param 4: Directory where to save the certificate
##################################################
function create_jks_keystore_secret() {
  local lf_tracelevel=5
  trace_in $lf_tracelevel create_jks_keystore_secret

  local lf_in_ns=$1
  local lf_in_secret_name=$2
  local lf_in_data_name=$3
  local lf_in_destination_path=$4
  decho $lf_tracelevel "Parameters:\"$1\"|\"$2\"|\"$3\"|\"$4\"|"

  if [[ $# -ne 4 ]]; then
    mylog error "You have to provide 4 arguments : namespace, secret_name, data_name and destination directory path"
    trace_out $lf_tracelevel create_jks_keystore_secret
    exit  1
  fi

  local lf_data_normalised=$(sed 's/\./\\./g' <<< ${lf_in_data_name})

  mylog info "Save certificate ${lf_in_secret_name} to ${lf_in_destination_path}${lf_in_secret_name}.${lf_in_data_name}.pem" 0
  decho $lf_tracelevel "$MY_CLUSTER_COMMAND -n $lf_in_ns get secret ${lf_in_secret_name} -o jsonpath=\"{.data.$lf_data_normalised}\""
  local lf_cert=$($MY_CLUSTER_COMMAND -n $lf_in_ns get secret ${lf_in_secret_name} -o jsonpath="{.data.$lf_data_normalised}")

  echo $lf_cert | base64 --decode >"${lf_in_destination_path}${lf_in_secret_name}.${lf_in_data_name}.pem"

  trace_out $lf_tracelevel create_jks_keystore_secret
}

