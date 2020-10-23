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

init() {
    echo "------------------"
    __check_rules
}

init

exec "$@"