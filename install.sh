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

#--- Detección y configuración de subred Docker ---

get_free_subnet() {
    local candidates=(
        "172.31.254.0/24"
        "10.250.0.0/24"
        "172.30.254.0/24"
        "10.251.0.0/24"
        "192.168.254.0/24"
        "172.29.254.0/24"
        "10.252.0.0/24"
        "172.28.254.0/24"
    )
    
    for subnet in "${candidates[@]}"; do
        local base=$(echo "$subnet" | cut -d/ -f1 | rev | cut -d. -f2- | rev)
        local conflict=false
        
        while IFS= read -r route; do
            [ "$route" = "*" ] && continue
            local r3=$(echo "$route" | cut -d/ -f1 | rev | cut -d. -f2- | rev 2>/dev/null)
            if [ "$base" = "$r3" ]; then
                conflict=true
                break
            fi
        done < <(ip route show 2>/dev/null | awk '{print $1}' | grep -E '^(10\.|172\.|192\.168\.)')
        
        [ "$conflict" = true ] && continue
        
        if docker info &> /dev/null 2>&1; then
            while IFS= read -r net; do
                local n3=$(echo "$net" | cut -d/ -f1 | rev | cut -d. -f2- | rev 2>/dev/null)
                if [ "$base" = "$n3" ]; then
                    conflict=true
                    break
                fi
            done < <(docker network ls -q 2>/dev/null | xargs -I{} docker network inspect {} \
                --format '{{range .IPAM.Config}}{{.Subnet}} {{end}}' 2>/dev/null | tr ' ' '\n' | grep -v '^$')
        fi
        
        [ "$conflict" = false ] && echo "$subnet" && return 0
    done
    
    echo "172.31.254.0/24"
}

configure_docker_network() {
    local old_subnet=$(grep "subnet:" "$PROYECTO_DIR/docker-compose.yml" | awk '{print $2}')
    local old_gateway=$(grep "gateway:" "$PROYECTO_DIR/docker-compose.yml" | awk '{print $2}')
    local old_remota=$(grep "ipv4_address:" "$PROYECTO_DIR/docker-compose.yml" | awk '{print $2}')
    
    [ -z "$old_subnet" ] && return
    
    echo "Subnet actual: $old_subnet"
    
    local project_name=$(basename "$PROYECTO_DIR")
    docker network rm "${project_name}_voip-net" 2>/dev/null || true
    
    if ! docker info &> /dev/null 2>&1; then
        return
    fi
    
    local test_name="voip-subnet-check-$$"
    if docker network create --subnet="$old_subnet" "$test_name" 2>/dev/null; then
        docker network rm "$test_name" 2>/dev/null
        echo -e "${GREEN}Subnet $old_subnet disponible.${NC}"
    else
        docker network rm "$test_name" 2>/dev/null
        echo -e "${YELLOW}Subnet $old_subnet en conflicto, buscando alternativa...${NC}"
        
        local new_subnet=$(get_free_subnet)
        if [ "$new_subnet" = "$old_subnet" ]; then
            echo -e "${RED}No se encontro un subnet libre.${NC}"
            return
        fi
        
        local new_gateway="${new_subnet%/*}.1"
        local new_remota="${new_subnet%/*}.50"
        
        for f in "docker-compose.yml" "conf/pjsip.conf" "conf/remota/pjsip.conf"; do
            if [ -f "$PROYECTO_DIR/$f" ]; then
                sed -i "s|$old_subnet|$new_subnet|g" "$PROYECTO_DIR/$f"
                sed -i "s|$old_gateway|$new_gateway|g" "$PROYECTO_DIR/$f"
                sed -i "s|$old_remota|$new_remota|g" "$PROYECTO_DIR/$f"
            fi
        done
        
        echo -e "${GREEN}Subnet actualizado: $new_subnet${NC}"
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

#--- Configurar red Docker ---
echo -e "${YELLOW}Configurando red Docker...${NC}"
configure_docker_network

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
