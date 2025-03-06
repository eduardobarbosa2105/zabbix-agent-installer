#!/bin/bash

# Função para detectar a distribuição e versão do SO
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=${VERSION_ID%%.*}  # Pega apenas a parte principal da versão
    else
        echo "Sistema operacional não suportado." >&2
        exit 1
    fi
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

# Função para carregar configurações de hostname e metadata de arquivos externos
load_config() {
    CONFIG_FILE="config_hostmetada"
    ZABBIX_CONF="zabbix_agent2.conf"

    if [ -f "$CONFIG_FILE" ]; then
        echo "Carregando configurações de $CONFIG_FILE"
        source "$CONFIG_FILE"
    else
        echo "Arquivo de configuração não encontrado. Criando padrão..."
        echo "HOSTNAME_OVERRIDE=$(hostname)" > "$CONFIG_FILE"
    fi

    if [ -f "$ZABBIX_CONF" ]; then
        echo "Verificando integridade de $ZABBIX_CONF"
        cp "$ZABBIX_CONF" "$ZABBIX_CONF.bkp"
    fi
}

# Função para verificar se há mudanças no config ou versão antiga do Zabbix
check_changes() {
    local update_needed=0

    # Verifica a versão do Zabbix Agent
    if ! dpkg -l | grep -q "zabbix-agent2"; then
        echo "Zabbix Agent não instalado. Atualização necessária."
        update_needed=1
    fi

    # Verifica se houve alteração nos arquivos de configuração
    if [ -f "config_hostmetada.bkp" ] && ! cmp -s "config_hostmetada" "config_hostmetada.bkp"; then
        echo "Alteração detectada no config_hostmetada."
        update_needed=1
    fi

    if [ -f "zabbix_agent2.conf.bkp" ] && ! cmp -s "zabbix_agent2.conf" "zabbix_agent2.conf.bkp"; then
        echo "Alteração detectada no zabbix_agent2.conf."
        update_needed=1
    fi

    return $update_needed
}

# Função principal
main() {
    detect_os
    echo "Sistema detectado: $OS $VER"

    load_config
    check_changes
    if [ $? -eq 0 ]; then
        echo "Nenhuma atualização necessária. Saindo."
        exit 0
    fi

    echo "Iniciando atualização do Zabbix Agent..."

    # Remove o Zabbix Agent se já estiver instalado
    if command -v zabbix_agentd &>/dev/null || command -v zabbix_agent2 &>/dev/null; then
        echo "Zabbix Agent encontrado. Removendo..."
        cp -ra /etc/zabbix/ /etc/zabbix-backup/
        apt remove -y zabbix-agent zabbix-agent2
    fi

    install_repo
    apt install -y zabbix-agent2 zabbix-agent2-plugin-*

    # Configura o Zabbix Agent 2
    sed -i "s/^Server=.*/Server=zabbixproxy01.mobit.com.br/" zabbix_agent2.conf
    sed -i "s/^ServerActive=.*/ServerActive=zabbixproxy01.mobit.com.br/" zabbix_agent2.conf

    if grep -q "^Hostname=" zabbix_agent2.conf; then
        sed -i "s/^Hostname=.*/Hostname=$HOSTNAME/" zabbix_agent2.conf
    else
        echo "Hostname=$HOSTNAME" >> zabbix_agent2.conf
    fi

    if grep -q "^HostMetadata=" zabbix_agent2.conf; then
        sed -i "s/^HostMetadata=.*/HostMetadata=$HOSTMETADATA/" zabbix_agent2.conf
    else
        echo "HostMetadata=$HOSTMETADATA" >> zabbix_agent2.conf
    fi

    sed -i "s/^# Timeout=.*/Timeout=30/" zabbix_agent2.conf
    sed -i "s/^# DenyKey=system.run\[\*\]/AllowKey=system.run[*]/" zabbix_agent2.conf
    sed -i "s/^# Plugins.SystemRun.LogRemoteCommands=.*/Plugins.SystemRun.LogRemoteCommands=1/" zabbix_agent2.conf

    systemctl enable zabbix-agent2 --now
    echo "Instalação concluída com sucesso."
}

main

