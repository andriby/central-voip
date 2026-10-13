#!/bin/bash
#=============================================
# Script de Instalacion - Central VoIP
# Proyecto Comunicacion de Datos
# Adrian Campos y Aaron Contreras
#=============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PROYECTO_DIR="$(pwd)"
IMAGEN="asterisk-custom:latest"

#--- Detección de red ---
get_host_ip() {
    local host_ip=""
    if command -v ip &> /dev/null; then
        host_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
    fi
    if [ -z "$host_ip" ] && command -v hostname &> /dev/null; then
        host_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    if [ -z "$host_ip" ]; then
        host_ip="127.0.0.1"
    fi
    echo "$host_ip"
}

get_local_net() {
    local host_ip=$(get_host_ip)
    if [ "$host_ip" = "127.0.0.1" ]; then
        echo "127.0.0.1/32"
    else
        echo "${host_ip%.*}.0/24"
    fi
}

echo -e "${CYAN}"
echo "============================================"
echo "  INSTALADOR CENTRAL VOIP - NOVALINK C.A."
echo "  Proyecto Comunicacion de Datos"
echo "  Adrian Campos y Aaron Contreras"
echo "============================================"
echo -e "${NC}"

#--- Verificar Docker ---
echo -e "${YELLOW}[1/6] Verificando Docker...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker no esta instalado.${NC}"
    echo "Instalando Docker..."
    
    if command -v dnf &> /dev/null; then
        sudo dnf install -y docker docker-compose
    elif command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y docker.io docker-compose-plugin
    else
        echo -e "${RED}No se pudo detectar el gestor de paquetes.${NC}"
        echo "Instala Docker manualmente: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker $USER
    echo -e "${GREEN}Docker instalado correctamente.${NC}"
    echo -e "${YELLOW}NOTA: Puede ser necesario cerrar y abrir sesion para usar docker sin sudo.${NC}"
else
    echo -e "${GREEN}Docker ya esta instalado: $(docker --version)${NC}"
fi

#--- Verificar Docker Compose ---
echo -e "${YELLOW}[2/6] Verificando Docker Compose...${NC}"
if ! docker compose version &> /dev/null; then
    echo -e "${RED}Docker Compose no esta disponible.${NC}"
    echo "Instalando plugin de Docker Compose..."
    
    if command -v dnf &> /dev/null; then
        sudo dnf install -y docker-compose-plugin
    elif command -v apt-get &> /dev/null; then
        sudo apt-get install -y docker-compose-plugin
    fi
else
    echo -e "${GREEN}Docker Compose: $(docker compose version --short)${NC}"
fi

#--- Verificar permisos Docker ---
echo -e "${YELLOW}[3/6] Verificando permisos Docker...${NC}"
if ! docker ps &> /dev/null 2>&1; then
    echo -e "${YELLOW}Se necesitan permisos de docker. Ejecutando newgrp...${NC}"
    echo "Si ves errores, ejecuta: newgrp docker"
fi

#--- Generar certificados TLS ---
echo -e "${YELLOW}[4/6] Generando certificados TLS...${NC}"
mkdir -p "$PROYECTO_DIR/certs"

if [ ! -f "$PROYECTO_DIR/certs/asterisk.crt" ]; then
    HOST_IP=$(get_host_ip)
    echo "IP detectada para SAN: $HOST_IP"
    cat > /tmp/asterisk-openssl-san.cnf <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
C = VE
ST = Caracas
L = Caracas
O = NovaLink
OU = VoIP
CN = asterisk.novalink.local

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = asterisk.novalink.local
IP.1 = 127.0.0.1
IP.2 = $HOST_IP
EOF
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$PROYECTO_DIR/certs/asterisk.key" \
        -out "$PROYECTO_DIR/certs/asterisk.crt" \
        -config /tmp/asterisk-openssl-san.cnf \
        2>/dev/null
    
    chmod 600 "$PROYECTO_DIR/certs/asterisk.key"
    chmod 644 "$PROYECTO_DIR/certs/asterisk.crt"
    echo -e "${GREEN}Certificados TLS generados correctamente.${NC}"
else
    echo -e "${GREEN}Certificados TLS ya existen.${NC}"
fi

#--- Crear directorios necesarios ---
echo -e "${YELLOW}[5/6] Preparando estructura...${NC}"
mkdir -p "$PROYECTO_DIR/logs"
mkdir -p "$PROYECTO_DIR/logs/remota"
mkdir -p "$PROYECTO_DIR/captures"
mkdir -p "$PROYECTO_DIR/softphones"

# Actualizar IP en pjsip.conf
HOST_IP=$(get_host_ip)
LOCAL_NET=$(get_local_net)
echo "IP del host detectada: $HOST_IP"
echo "Red local detectada: $LOCAL_NET"
if [ -f "$PROYECTO_DIR/conf/pjsip.conf" ]; then
    sed -i "s/external_signaling_address=.*/external_signaling_address=$HOST_IP/g" "$PROYECTO_DIR/conf/pjsip.conf"
    sed -i "s/external_media_address=.*/external_media_address=$HOST_IP/g" "$PROYECTO_DIR/conf/pjsip.conf"
    sed -i "s|local_net=__LOCAL_NET__|local_net=$LOCAL_NET|g" "$PROYECTO_DIR/conf/pjsip.conf"
fi
echo -e "${GREEN}Estructura preparada.${NC}"

#--- Construir imagen Asterisk ---
echo -e "${YELLOW}[6/6] Construyendo imagen Asterisk (esto tarda 10-20 min)...${NC}"
if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGEN}$"; then
    echo -e "${GREEN}Imagen Asterisk ya existe.${NC}"
    read -p "Reconstruir imagen? (s/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        docker build -t asterisk-custom:latest .
    fi
else
    docker build -t asterisk-custom:latest .
fi

echo -e "${GREEN}"
echo "============================================"
echo "  INSTALACION COMPLETADA"
echo "============================================"
echo -e "${NC}"
echo "Para iniciar la central VoIP:"
echo -e "  ${CYAN}docker compose up -d${NC}"
echo ""
echo "Para verificar que funciona:"
echo -e "  ${CYAN}docker exec pbx-asterisk asterisk -rx \"pjsip show endpoints\"${NC}"
echo ""
echo "Para ver todos los comandos disponibles:"
echo -e "  ${CYAN}make help${NC}"
echo ""
echo "Guia completa de instalacion:"
echo -e "  ${CYAN}cat INSTALACION.md${NC}"
echo ""
