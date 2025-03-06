#!/bin/bash

# Função para detectar a distribuição e versão do SO
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=${VERSION_ID%%.*}
    else
        echo "Sistema operacional não suportado." >&2
        exit 1
    fi
}

# Função para obter a versão do Zabbix instalada
get_installed_version() {
    dpkg-query -W -f='${Version}' zabbix-agent2 2>/dev/null || echo "0"
}

# Função para obter a versão disponível no repositório
get_available_version() {
    apt-cache show zabbix-agent2 2>/dev/null | grep -m1 Version | awk '{print $2}' || echo "0"
}

# Função para instalar o repositório correto
install_repo() {
    case "$OS" in
        debian)
            wget -q "https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_latest_7.0+debian${VER}_all.deb" -O /tmp/zabbix-release.deb
            ;;
        ubuntu)
            wget -q "https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu${VER}.04_all.deb" -O /tmp/zabbix-release.deb
            ;;
        *)
            echo "Distribuição não suportada." >&2
            exit 1
            ;;
    esac
    dpkg -i /tmp/zabbix-release.deb && apt update
}

# Função para carregar configurações de hostname e metadata de arquivo externo
load_config() {
    CONFIG_FILE="config_hostmetada"
    HASH_FILE="config_hash"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Arquivo de configuração não encontrado." >&2
        exit 1
    fi
    
    # Calcula o hash do arquivo atual
    NEW_HASH=$(md5sum "$CONFIG_FILE" | awk '{print $1}')
    
    # Verifica se o hash mudou desde a última execução
    if [ -f "$HASH_FILE" ]; then
        OLD_HASH=$(cat "$HASH_FILE")
        if [ "$NEW_HASH" == "$OLD_HASH" ]; then
            CONFIG_CHANGED=0
        else
            CONFIG_CHANGED=1
        fi
    else
        CONFIG_CHANGED=1
    fi
    
    # Atualiza o hash armazenado
    echo "$NEW_HASH" > "$HASH_FILE"
    
    HOSTMETADATA=$(grep -E '^HOSTMETADATA=' "$CONFIG_FILE" | cut -d'=' -f2 | tr -d '"')
    HOSTNAME=$(grep -E '^HOSTNAME=' "$CONFIG_FILE" | cut -d'=' -f2 | tr '[:lower:]' '[:upper:]')
}

# Função principal
main() {
    detect_os
    echo "Sistema detectado: $OS $VER"
    
    load_config
    
    INSTALLED_VERSION=$(get_installed_version)
    AVAILABLE_VERSION=$(get_available_version)
    
    echo "Versão instalada: $INSTALLED_VERSION"
    echo "Versão disponível: $AVAILABLE_VERSION"
    
    if [ "$INSTALLED_VERSION" == "$AVAILABLE_VERSION" ] && [ "$CONFIG_CHANGED" -eq 0 ]; then
        echo "Zabbix Agent já está atualizado e a configuração não mudou. Nada a fazer."
        exit 0
    fi
    
    echo "Atualizando Zabbix Agent..."
    
    # Verifica se o Zabbix Agent já está instalado e remove antes da atualização
    if command -v zabbix_agentd &>/dev/null || command -v zabbix_agent2 &>/dev/null; then
        echo "Zabbix Agent encontrado. Removendo..."
        cp -ra /etc/zabbix/ /etc/zabbix-backup/
        apt remove -y zabbix-agent zabbix-agent2
    fi

    install_repo
    apt install -y zabbix-agent2 zabbix-agent2-plugin-*
    
    CONFIG_FILE="/etc/zabbix/zabbix_agent2.conf"
    
    # Aplica as configurações necessárias
    sed -i "s/^Server=.*/Server=zabbixproxy01.mobit.com.br/" "$CONFIG_FILE"
    sed -i "s/^ServerActive=.*/ServerActive=zabbixproxy01.mobit.com.br/" "$CONFIG_FILE"
    
    if grep -q "^Hostname=" "$CONFIG_FILE"; then
        sed -i "s/^Hostname=.*/Hostname=$HOSTNAME/" "$CONFIG_FILE"
    else
        echo "Hostname=$HOSTNAME" >> "$CONFIG_FILE"
    fi
    
    if grep -q "^HostMetadata=" "$CONFIG_FILE"; then
        sed -i "s/^HostMetadata=.*/HostMetadata=$HOSTMETADATA/" "$CONFIG_FILE"
    else
        echo "HostMetadata=$HOSTMETADATA" >> "$CONFIG_FILE"
    fi
    
    sed -i "s/^# Timeout=.*/Timeout=30/" "$CONFIG_FILE"
    sed -i "s/^# DenyKey=system.run\[\*\]/AllowKey=system.run[*]/" "$CONFIG_FILE"
    sed -i "s/^# Plugins.SystemRun.LogRemoteCommands=.*/Plugins.SystemRun.LogRemoteCommands=1/" "$CONFIG_FILE"
    
    systemctl enable zabbix-agent2 --now
    echo "Instalação concluída com sucesso."
}

main

