#!/bin/bash

# Example functions
function f1() {
    echo "f1 called with: $@"
}

function f2() {
    echo "f2 called with: $@"
}

function f3() {
    echo "f3 called with: $@"
}

# Function to process calls
process_calls() {
    calls="$1"  # Get the full string of calls and parameters

    # Split the calls by comma and loop through each
    IFS=',' read -ra commands <<< "$calls"
    for cmd in "${commands[@]}"; do
        # Trim leading/trailing spaces from the command
        cmd=$(echo "$cmd" | xargs)

        # Extract the function name and parameters
        func=$(echo "$cmd" | awk '{print $1}')
        params=$(echo "$cmd" | cut -d' ' -f2-)

        # Check if the function exists and call it
        if declare -f "$func" > /dev/null; then
            $func $params
        else
            echo "Error: Function '$func' not found."
        fi
    done
}

# Main script logic
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --call)
            shift
            calls="$1"
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done
echo "calls=$calls"

# Call processing function if --call was used
if [[ -n $calls ]]; then
    process_calls "$calls"
fi
