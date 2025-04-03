#!/bin/bash

# Ensure script is run with bash
if [ -z "$BASH_VERSION" ]; then
    echo "⚠️  This script must be run with bash, not sh."
    echo "👉 Try: bash <(wget -O - https://raw.githubusercontent.com/Zikett/t3rn-installer/main/t3rn-installer.sh)"
    exit 1
fi

# Check if t3rn directory exists
if [ -d "t3rn" ]; then
    echo "📁 Directory 't3rn' already exists."

    if [ -d "t3rn/executor" ]; then
        read -p "🔄 Do you want to remove the existing 'executor' and reinstall it? (y/N): " reinstall
        reinstall=$(echo "$reinstall" | tr '[:upper:]' '[:lower:]' | xargs)

        if [[ "$reinstall" == "y" ]]; then
            echo "🧹 Removing old executor and archive..."
            rm -rf t3rn/executor
            rm -f t3rn/executor-linux-*.tar.gz
        else
            echo "❌ Installation cancelled. Existing 'executor' kept."
            exit 0
        fi
    fi
else
    mkdir t3rn || { echo "❌ Failed to create directory 't3rn'"; exit 1; }
fi

cd t3rn || { echo "❌ Failed to cd into 't3rn'"; exit 1; }

# Download and extract latest release
TAG=$(curl -s https://api.github.com/repos/t3rn/executor-release/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
echo "📦 Downloading latest release: $TAG"
wget https://github.com/t3rn/executor-release/releases/download/${TAG}/executor-linux-${TAG}.tar.gz
tar -xzf executor-linux-*.tar.gz
cd executor/executor/bin || { echo "❌ Failed to cd into binary folder"; exit 1; }

# Set base environment variables
export ENVIRONMENT=testnet
export LOG_LEVEL=debug
export LOG_PRETTY=false
export EXECUTOR_PROCESS_BIDS_ENABLED=true
export EXECUTOR_PROCESS_ORDERS_ENABLED=true
export EXECUTOR_PROCESS_CLAIMS_ENABLED=true

# New API-based flags with interactive toggle
read -p "🔧 EXECUTOR_PROCESS_PENDING_ORDERS_FROM_API (default: true) — press Enter to keep or type 'false': " pending_api
export EXECUTOR_PROCESS_PENDING_ORDERS_FROM_API=${pending_api:-true}

read -p "🔧 EXECUTOR_PROCESS_ORDERS_API_ENABLED (default: true) — press Enter to keep or type 'false': " orders_api
export EXECUTOR_PROCESS_ORDERS_API_ENABLED=${orders_api:-true}

# Ask for gas price
read -p "⛽ Enter max L3 gas price (default is 1000): " gas_price
export EXECUTOR_MAX_L3_GAS_PRICE=${gas_price:-1000}

# Ask for private key
echo "🔑 Enter your PRIVATE_KEY_LOCAL (without 0x):"
read -p "> " private_key
if [[ "$private_key" == 0x* ]]; then
    echo "⚠️  Please enter the key *without* the 0x prefix!"
    exit 1
fi
export PRIVATE_KEY_LOCAL=$private_key

# Default RPC endpoints
declare -A default_rpcs=(
    ["l2rn"]="https://b2n.rpc.caldera.xyz/http https://b2n-testnet.blockpi.network/v1/rpc/public"
    ["arbt"]="https://arbitrum-sepolia.gateway.tenderly.co https://arbitrum-sepolia.drpc.org https://sepolia-rollup.arbitrum.io/rpc https://arbitrum-sepolia-rpc.publicnode.com"
    ["bast"]="https://base-sepolia.drpc.org https://base-sepolia.gateway.tenderly.co https://base-sepolia-rpc.publicnode.com https://sepolia.base.org"
    ["blst"]="https://sepolia.blast.io"
    ["opst"]="https://sepolia.optimism.io https://optimism-sepolia.gateway.tenderly.co https://api.zan.top/opt-sepolia"
    ["unit"]="https://unichain-sepolia-rpc.publicnode.com https://unichain-sepolia.drpc.org https://unichain-sepolia.api.onfinality.io/public"
)

# Full readable network names
declare -A network_names=(
    ["arbt"]="Arbitrum Sepolia"
    ["bast"]="Base Sepolia"
    ["blst"]="Blast Sepolia"
    ["opst"]="Optimism Sepolia"
    ["unit"]="Unichain Sepolia"
    ["l2rn"]="L2RN Testnet"
)

declare -A user_rpcs

echo ""
read -p "🔁 Do you want to replace default RPC endpoints? (y/N): " change_rpc
echo ""

if [[ "$change_rpc" =~ ^[Yy]$ ]]; then
    echo "🔧 Custom RPC setup: you can enter multiple URLs separated by space."
    echo "Leave input empty to keep default value for each network."
    for network in "${!default_rpcs[@]}"; do
        full_name="${network_names[$network]}"
        full_name=${full_name:-$network}

        if [[ "$network" == "l2rn" ]]; then
            user_rpcs["$network"]="${default_rpcs[$network]}"
            echo "🌐 ${full_name} ($network) is fixed with endpoints:"
            IFS=' ' read -ra urls <<< "${default_rpcs[$network]}"
            for u in "${urls[@]}"; do
                echo " - $u"
            done
            continue
        fi

        read -p "🌐 Enter RPC URL(s) for ${full_name} ($network): " rpc_input
        user_rpcs["$network"]="${rpc_input:-${default_rpcs[$network]}}"
    done
else
    for network in "${!default_rpcs[@]}"; do
        user_rpcs["$network"]="${default_rpcs[$network]}"
    done
    echo "✅ Using default RPCs."
fi

# Convert RPCs to proper JSON
rpc_json='{'
for key in "${!user_rpcs[@]}"; do
    IFS=' ' read -ra urls <<< "${user_rpcs[$key]}"
    rpc_json+="\"$key\": ["
    for url in "${urls[@]}"; do
        rpc_json+="\"$url\", "
    done
    rpc_json="${rpc_json%, }], "
done
rpc_json="${rpc_json%, }"
rpc_json+='}'

export RPC_ENDPOINTS="$rpc_json"
export ENABLED_NETWORKS='arbitrum-sepolia,base-sepolia,optimism-sepolia,l2rn,blast-sepolia,unichain-sepolia'

# Run the executor
echo ""
echo "🚀 Starting executor..."
./executor

rm -f wget-log*
