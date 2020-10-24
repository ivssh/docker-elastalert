#!/usr/bin/dumb-init /bin/sh
set -eo pipefail

# Check the rules and see if they are valid, otherwise exit
__check_rules() {
    if [ "$(ls "${RULES_FOLDER}")" ]; then
        find "${RULES_FOLDER}" -type f -name "*.yaml" -o -name "*.yml" > /tmp/rulelist
        while IFS= read -r file; do
            echo "=> ${scriptName}: Checking syntax on Elastalert rule ${file}....."
            elastalert-test-rule \
                --schema-only \
                --stop-error \
                "${file}"
        done < /tmp/rulelist
        rm /tmp/rulelist
    else
        echo "=> ${scriptName}: Rules folder ${RULES_FOLDER} is empty. Skipping checking"
    fi
}

__create_elastalert_index() {
    # Check if the Elastalert index exists in Elasticsearch and create it if it does not.
    if ! wget -q -T 3 -O - "${wgetSchema}${wgetAuth}${ELASTICSEARCH_HOST}:${ELASTICSEARCH_PORT}/${ELASTALERT_INDEX}" >/dev/null 2>&1
    then
        echo "=> ${scriptName}: Creating Elastalert index in Elasticsearch..."
        elastalert-create-index ${createEaOptions} \
            --config "${ELASTALERT_CONFIG}" \
            --host "${ELASTICSEARCH_HOST}" \
            --index "${ELASTALERT_INDEX}" \
            --old-index "" \
            --port "${ELASTICSEARCH_PORT}"
    else
        echo "=> ${scriptName}: Elastalert index \`${ELASTALERT_INDEX}\` already exists in Elasticsearch."
    fi
}


__set_script_variables() {
    # Set name of the script for logging purposes
    scriptName="$(basename "${0}")"

    # Set schema and elastalert options
    case "${ELASTICSEARCH_USE_SSL}:${ELASTICSEARCH_VERIFY_CERTS}" in
        "True:True")
            wgetSchema="https://"
            createEaOptions="--ssl --verify-certs"
        ;;
        "True:False")
            wgetSchema="--no-check-certificate https://"
            createEaOptions="--ssl --no-verify-certs"
        ;;
        *)
            wgetSchema="http://"
            createEaOptions="--no-ssl"
        ;;
    esac

    # Set authentication if needed
    if [ -n "${ELASTICSEARCH_USER}" ] && [ -n "${ELASTICSEARCH_PASSWORD}" ]; then
        wgetAuth="${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD}@"
    else
        wgetAuth=""
    fi
}

__set_folder_permissions() {
    if [ "$(stat -c %u "${CONFIG_FOLDER}")" != "$(id -u "${ELASTALERT_SYSTEM_USER}")" ]; then
        chown -R "${ELASTALERT_SYSTEM_USER}":"${ELASTALERT_SYSTEM_GROUP}" "${CONFIG_FOLDER}"
    fi
    if [ "$(stat -c %u "${RULES_FOLDER}")" != "$(id -u "${ELASTALERT_SYSTEM_USER}")" ]; then
        chown -R "${ELASTALERT_SYSTEM_USER}":"${ELASTALERT_SYSTEM_GROUP}" "${RULES_FOLDER}"
    fi
}

__start_elastalert() {
    echo "=> ${scriptName}: Starting Elastalert..."
    exec su-exec "${ELASTALERT_SYSTEM_USER}":"${ELASTALERT_SYSTEM_GROUP}" \
         python -u -m elastalert.elastalert \
             --config "${ELASTALERT_CONFIG}" \
             --verbose
}

__wait_for_elasticsearch() {
    # Wait until Elasticsearch is online since otherwise Elastalert will fail.
    while ! wget -q -T 3 -O - ${wgetSchema}${wgetAuth}${ELASTICSEARCH_HOST}:${ELASTICSEARCH_PORT}
    do
        echo "=> ${scriptName}: Waiting for Elasticsearch..."
        sleep 1
    done
    sleep 5
}

init() {
    echo "------------------"
    __check_rules
}

init

exec "$@"