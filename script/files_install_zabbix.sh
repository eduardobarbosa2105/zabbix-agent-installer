#!/bin/bash

# Diretório onde o repositório será clonado
REPO_DIR="/opt/zabbix-agent-installer"
REPO_URL="https://github.com/eduardobarbosa2105/zabbix-agent-installer.git"

# Verifica se o Git está instalado
if ! command -v git &> /dev/null; then
    echo "Git não encontrado. Instalando..."
    apt update && apt install -y git
fi

# Clona ou atualiza o repositório
if [ -d "$REPO_DIR" ]; then
    echo "Repositório já existe. Atualizando..."
    cd "$REPO_DIR" && git pull
else
    echo "Clonando repositório..."
    git clone "$REPO_URL" "$REPO_DIR"
fi

# Verifica se o diretório contém os arquivos esperados
cd "$REPO_DIR" || exit 1

if [ ! -f "install_agent_zabbix.sh" ] || [ ! -f "config_hostmetada.txt" ]; then
    echo "Erro: Arquivos necessários não encontrados no repositório." >&2
    exit 1
fi

# Concede permissão de execução ao script
chmod +x install_agent_zabbix.sh

echo "Repositório pronto para uso. Execute ./install_agent_zabbix.sh para instalar o Zabbix Agent."

