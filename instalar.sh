#!/bin/bash
#=============================================
# Instalador Automatico - Central VoIP
# Proyecto Comunicacion de Datos
# Adrian Campos (CI: 30513493)
# Aaron Contreras
#=============================================

set -e  # Salir si hay error

#--- Colores para output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'  # No Color

#--- Variables globales ---
PROYECTO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGEN="asterisk-custom:latest"
CONTENEDOR_PRINCIPAL="pbx-asterisk"
CONTENEDOR_REMOTA="pbx-remota"
MIN_RAM_MB=3500
MIN_DISCO_GB=8

#--- Funciones de utilidad ---

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[AVISO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo ""
    echo -e "${CYAN}${BOLD}━━━ $1 ━━━${NC}"
    echo ""
}

check_command() {
    command -v "$1" &> /dev/null
}

#--- Detección de red del host ---

get_host_ip() {
    local host_ip=""
    if check_command ip; then
        host_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
    fi
    if [ -z "$host_ip" ] && check_command hostname; then
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

#--- Banner de bienvenida ---

show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'
    ╔═══════════════════════════════════════════════════════════╗
    ║                                                           ║
    ║           CENTRAL VOIP - NOVALINK C.A.                   ║
    ║       Instalador Automatico v2.0                         ║
    ║                                                           ║
    ║   Proyecto: Comunicacion de Datos                         ║
    ║   Asterisk 20 + Docker + SIP/RTP                         ║
    ║                                                           ║
    ║   Autores: Adrian Campos & Aaron Contreras                ║
    ║                                                           ║
    ╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

#--- Verificaciones del sistema ---

check_system() {
    log_step "VERIFICANDO REQUISITOS DEL SISTEMA"
    
    # Verificar que estamos en Linux
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        log_error "Este instalador solo funciona en Linux"
        exit 1
    fi
    
    # Detectar distribucion
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
        log_info "Distribucion detectada: $PRETTY_NAME"
    else
        log_warn "No se pudo detectar la distribucion"
        DISTRO="unknown"
    fi
    
    # Verificar RAM
    local ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$ram_mb" -lt "$MIN_RAM_MB" ]; then
        log_warn "RAM insuficiente: ${ram_mb}MB (minimo recomendado: ${MIN_RAM_MB}MB)"
        read -p "Continuar de todos modos? (s/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            exit 1
        fi
    else
        log_success "RAM suficiente: ${ram_mb}MB"
    fi
    
    # Verificar espacio en disco
    local disco_gb=$(df -BG "$PROYECTO_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$disco_gb" -lt "$MIN_DISCO_GB" ]; then
        log_warn "Espacio en disco bajo: ${disco_gb}GB (minimo: ${MIN_DISCO_GB}GB)"
    else
        log_success "Espacio en disco suficiente: ${disco_gb}GB"
    fi
    
    # Verificar conexion a internet
    if ping -c 1 -W 2 8.8.8.8 &> /dev/null; then
        log_success "Conexion a internet verificada"
    else
        log_warn "Sin conexion a internet (necesaria para construir la imagen)"
    fi
}

#--- Instalacion de Docker ---

install_docker() {
    log_step "VERIFICANDO E INSTALANDO DOCKER"
    
    # Verificar si Docker ya esta instalado
    if check_command docker; then
        log_success "Docker ya esta instalado: $(docker --version)"
        
        # Verificar que el daemon esta corriendo
        if ! docker info &> /dev/null 2>&1; then
            log_warn "El demonio Docker no esta corriendo"
            log_info "Intentando iniciar Docker..."
            sudo systemctl start docker 2>/dev/null || sudo systemctl start docker.socket 2>/dev/null
            sleep 3
            
            if ! docker info &> /dev/null 2>&1; then
                log_error "No se pudo iniciar Docker. Ejecuta manualmente:"
                echo "  sudo systemctl start docker"
                exit 1
            fi
        fi
        
        # Verificar permisos del usuario
        if ! docker ps &> /dev/null 2>&1; then
            log_warn "El usuario actual no tiene permisos Docker"
            log_info "Agregando usuario al grupo docker..."
            sudo usermod -aG docker "$USER"
            log_warn "Necesitas cerrar y abrir sesion, o ejecutar: newgrp docker"
            log_info "Continuando con la instalacion..."
        fi
    else
        log_info "Docker no encontrado. Instalando..."
        
        case $DISTRO in
            fedora|rhel|centos)
                sudo dnf install -y docker docker-compose-plugin
                sudo systemctl enable --now docker
                ;;
            ubuntu|debian|linuxmint)
                sudo apt-get update
                sudo apt-get install -y docker.io docker-compose-plugin
                sudo systemctl enable --now docker
                ;;
            arch|manjaro)
                sudo pacman -S --noconfirm docker docker-compose
                sudo systemctl enable --now docker
                ;;
            *)
                log_error "Distribucion no soportada automaticamente"
                log_info "Instala Docker manualmente: https://docs.docker.com/get-docker/"
                exit 1
                ;;
        esac
        
        sudo usermod -aG docker "$USER"
        log_success "Docker instalado correctamente"
    fi
    
    # Verificar Docker Compose
    if docker compose version &> /dev/null 2>&1; then
        log_success "Docker Compose: $(docker compose version --short)"
    else
        log_warn "Docker Compose no encontrado. Intentando instalar..."
        case $DISTRO in
            fedora|rhel|centos)
                sudo dnf install -y docker-compose-plugin
                ;;
            ubuntu|debian|linuxmint)
                sudo apt-get install -y docker-compose-plugin
                ;;
        esac
        
        if ! docker compose version &> /dev/null 2>&1; then
            log_error "No se pudo instalar Docker Compose"
            exit 1
        fi
    fi
}

#--- Generacion de certificados TLS ---

generate_certs() {
    log_step "GENERANDO CERTIFICADOS TLS"
    
    mkdir -p "$PROYECTO_DIR/certs"
    
    if [ -f "$PROYECTO_DIR/certs/asterisk.crt" ] && [ -f "$PROYECTO_DIR/certs/asterisk.key" ]; then
        log_info "Los certificados ya existen"
        read -p "¿Deseas regenerarlos? (s/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            log_success "Manteniendo certificados existentes"
            return
        fi
    fi
    
    log_info "Generando certificado autofirmado RSA-2048..."
    
    local host_ip=$(get_host_ip)
    log_info "IP detectada para SAN: $host_ip"
    
    cat > /tmp/asterisk-openssl-san.cnf <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
C = VE
ST = Caracas
L = Caracas
O = NovaLink C.A.
OU = VoIP
CN = asterisk.novalink.local

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = asterisk.novalink.local
IP.1 = 127.0.0.1
IP.2 = $host_ip
EOF
    
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$PROYECTO_DIR/certs/asterisk.key" \
        -out "$PROYECTO_DIR/certs/asterisk.crt" \
        -config /tmp/asterisk-openssl-san.cnf \
        2>/dev/null
    
    chmod 600 "$PROYECTO_DIR/certs/asterisk.key"
    chmod 644 "$PROYECTO_DIR/certs/asterisk.crt"
    
    log_success "Certificados TLS generados correctamente"
    log_info "Certificado: certs/asterisk.crt (validez: 365 dias)"
    log_info "Clave privada: certs/asterisk.key"
    log_info "SAN incluido: DNS:asterisk.novalink.local, IP:127.0.0.1, IP:$host_ip"
}

#--- Construccion de la imagen Asterisk ---

build_image() {
    log_step "CONSTRUYENDO IMAGEN DE ASTERISK"
    
    log_info "Verificando si la imagen ya existe..."
    
    if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGEN}$"; then
        log_success "La imagen ${IMAGEN} ya existe"
        read -p "¿Deseas reconstruirla? (s/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            log_success "Usando imagen existente"
            return
        fi
    fi
    
    log_info "Compilando Asterisk 20 desde código fuente..."
    log_warn "Esto puede tardar 10-20 minutos dependiendo de tu CPU"
    echo ""
    
    cd "$PROYECTO_DIR"
    
    # Construir con output en tiempo real
    if docker build -t "$IMAGEN" . 2>&1 | tee /tmp/asterisk_build.log; then
        log_success "Imagen ${IMAGEN} construida correctamente"
        
        # Verificar que la imagen existe
        if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGEN}$"; then
            local img_size=$(docker images "$IMAGEN" --format '{{.Size}}')
            log_info "Tamaño de la imagen: ${img_size}"
        fi
    else
        log_error "Error al construir la imagen"
        log_info "Revisa el log: /tmp/asterisk_build.log"
        exit 1
    fi
}

#--- Preparacion de directorios ---

prepare_directories() {
    log_step "PREPARANDO ESTRUCTURA DE DIRECTORIOS"
    
    # Directorios necesarios
    local dirs=(
        "$PROYECTO_DIR/logs"
        "$PROYECTO_DIR/logs/remota"
        "$PROYECTO_DIR/captures"
        "$PROYECTO_DIR/softphones"
    )
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            log_info "Creado: $dir"
        fi
    done
    
    # Permisos para logs
    chmod 755 "$PROYECTO_DIR/logs" 2>/dev/null || true
    
    log_success "Estructura de directorios preparada"
}

#--- Configuracion de red ---

configure_network() {
    log_step "CONFIGURANDO RED"
    
    # Verificar que no haya conflictos de red Docker
    if docker network ls | grep -q "central-voip_voip-net"; then
        log_warn "La red voip-net ya existe"
        log_info "Verificando contenedores en esa red..."
        docker network inspect central-voip_voip-net --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || true
    fi
    
    # Obtener IP del host para configuracion
    local host_ip=$(get_host_ip)
    local local_net=$(get_local_net)
    log_info "IP del host detectada: $host_ip"
    log_info "Red local detectada: $local_net"
    
    # Actualizar IP en pjsip.conf (placeholders o valores antiguos hardcodeados)
    if [ -f "$PROYECTO_DIR/conf/pjsip.conf" ]; then
        sed -i "s/external_signaling_address=.*/external_signaling_address=$host_ip/g" \
            "$PROYECTO_DIR/conf/pjsip.conf"
        sed -i "s/external_media_address=.*/external_media_address=$host_ip/g" \
            "$PROYECTO_DIR/conf/pjsip.conf"
        sed -i "s|local_net=__LOCAL_NET__|local_net=$local_net|g" \
            "$PROYECTO_DIR/conf/pjsip.conf"
        log_success "IP y red local actualizadas en pjsip.conf"
    fi
    
    log_success "Red configurada"
}

#--- Limpieza de archivos temporales ---

cleanup_temp() {
    log_step "LIMPIANDO ARCHIVOS TEMPORALES"
    
    # Eliminar archivos backup si existen
    local bak_files=$(find "$PROYECTO_DIR/conf" -name "*.bak*" -type f 2>/dev/null)
    
    if [ -n "$bak_files" ]; then
        log_info "Archivos backup encontrados:"
        echo "$bak_files" | while read f; do echo "  - $(basename "$f")"; done
        
        read -p "¿Eliminar archivos backup? (s/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            echo "$bak_files" | xargs rm -f
            log_success "Archivos backup eliminados"
        fi
    else
        log_success "No hay archivos backup que limpiar"
    fi
}

#--- Inicio de servicios ---

start_services() {
    log_step "INICIANDO SERVICIOS"
    
    cd "$PROYECTO_DIR"
    
    # Detener servicios previos si existen
    log_info "Deteniendo servicios previos..."
    docker compose down --remove-orphans 2>/dev/null || true
    
    # Iniciar servicios
    log_info "Iniciando contenedores..."
    if docker compose up -d; then
        log_success "Contenedores iniciados"
    else
        log_error "Error al iniciar los contenedores"
        log_info "Intenta ejecutar manualmente: docker compose up -d"
        exit 1
    fi
    
    # Esperar a que Asterisk este listo
    log_info "Esperando a que Asterisk este listo..."
    local max_wait=60
    local waited=0
    
    while [ $waited -lt $max_wait ]; do
        if docker exec "$CONTENEDOR_PRINCIPAL" asterisk -rx "core show version" &> /dev/null 2>&1; then
            log_success "Asterisk esta listo"
            break
        fi
        
        sleep 3
        waited=$((waited + 3))
        echo -ne "${BLUE}[INFO]${NC} Esperando... (${waited}s/${max_wait}s)\r"
    done
    
    if [ $waited -ge $max_wait ]; then
        log_warn "Asterisk no responde despues de ${max_wait}s"
        log_info "Revisa los logs: docker logs $CONTENEDOR_PRINCIPAL"
    fi
}

#--- Verificacion de la instalacion ---

verify_installation() {
    log_step "VERIFICANDO INSTALACION"
    
    local all_ok=true
    
    # 1. Verificar contenedores
    log_info "Verificando contenedores..."
    if docker ps --format '{{.Names}}' | grep -q "$CONTENEDOR_PRINCIPAL"; then
        log_success "Contenedor $CONTENEDOR_PRINCIPAL: corriendo"
    else
        log_error "Contenedor $CONTENEDOR_PRINCIPAL: NO CORRIENDO"
        all_ok=false
    fi
    
    if docker ps --format '{{.Names}}' | grep -q "$CONTENEDOR_REMOTA"; then
        log_success "Contenedor $CONTENEDOR_REMOTA: corriendo"
    else
        log_warn "Contenedor $CONTENEDOR_REMOTA: no corriendo (opcional)"
    fi
    
    # 2. Verificar Asterisk
    log_info ""
    log_info "Verificando Asterisk..."
    local asterisk_version=$(docker exec "$CONTENEDOR_PRINCIPAL" asterisk -rx "core show version" 2>/dev/null | head -1)
    if [ -n "$asterisk_version" ]; then
        log_success "Asterisk: $asterisk_version"
    else
        log_error "Asterisk no responde"
        all_ok=false
    fi
    
    # 3. Verificar endpoints
    log_info ""
    log_info "Verificando endpoints SIP..."
    local endpoints=$(docker exec "$CONTENEDOR_PRINCIPAL" asterisk -rx "pjsip show endpoints" 2>/dev/null | grep -c "Endpoint:")
    
    if [ "$endpoints" -ge 2 ]; then
        log_success "Endpoints configurados: $endpoints"
        docker exec "$CONTENEDOR_PRINCIPAL" asterisk -rx "pjsip show endpoints" 2>/dev/null | grep -E "Endpoint:|Aor:" | head -10
    else
        log_warn "Pocos endpoints configurados: $endpoints"
    fi
    
    # 4. Verificar transportes
    log_info ""
    log_info "Verificando transportes..."
    local transports=$(docker exec "$CONTENEDOR_PRINCIPAL" asterisk -rx "pjsip show transports" 2>/dev/null | grep -c "Transport:")
    
    if [ "$transports" -ge 1 ]; then
        log_success "Transportes configurados: $transports"
    else
        log_error "No hay transportes configurados"
        all_ok=false
    fi
    
    # 5. Verificar dialplan
    log_info ""
    log_info "Verificando dialplan..."
    local dialplan=$(docker exec "$CONTENEDOR_PRINCIPAL" asterisk -rx "dialplan show" 2>/dev/null | grep -c "exten")
    
    if [ "$dialplan" -ge 5 ]; then
        log_success "Extensiones en dialplan: $dialplan"
    else
        log_warn "Pocas extensiones en dialplan: $dialplan"
    fi
    
    # 6. Verificar parking
    log_info ""
    log_info "Verificando parking..."
    if docker exec "$CONTENEDOR_PRINCIPAL" asterisk -rx "parking show" 2>/dev/null | grep -q "Parking"; then
        log_success "Parking configurado"
    else
        log_warn "Parking no disponible"
    fi
    
    echo ""
    if [ "$all_ok" = true ]; then
        echo -e "${GREEN}${BOLD}════════════════════════════════════════════${NC}"
        echo -e "${GREEN}${BOLD}  INSTALACION COMPLETADA EXITOSAMENTE${NC}"
        echo -e "${GREEN}${BOLD}════════════════════════════════════════════${NC}"
    else
        echo -e "${YELLOW}${BOLD}════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}${BOLD}  INSTALACION COMPLETADA CON ADVERTENCIAS${NC}"
        echo -e "${YELLOW}${BOLD}════════════════════════════════════════════${NC}"
    fi
}

#--- Instalacion de Linphone (opcional) ---

install_linphone() {
    echo ""
    read -p "¿Deseas instalar Linphone (softphone)? (s/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        log_info "Omitiendo instalacion de Linphone"
        return
    fi
    
    log_step "INSTALANDO LINPHONE"
    
    mkdir -p "$PROYECTO_DIR/softphones"
    
    # Verificar si ya existe
    if [ -f "$PROYECTO_DIR/softphones/linphone.AppImage" ]; then
        log_success "Linphone ya esta descargado"
        chmod +x "$PROYECTO_DIR/softphones/linphone.AppImage"
        return
    fi
    
    log_info "Descargando Linphone 5.3.4 (AppImage)..."
    log_warn "Esto puede tardar varios minutos..."
    
    local linphone_url="https://download.linphone.org/releases/linux/app/Linphone-5.3.4.AppImage"
    local download_ok=false
    
    if check_command wget; then
        if wget -q --show-progress --timeout=120 "$linphone_url" \
            -O "$PROYECTO_DIR/softphones/linphone.AppImage" 2>/dev/null; then
            download_ok=true
        fi
    elif check_command curl; then
        if curl -fsSL --progress-bar --max-time 120 "$linphone_url" \
            -o "$PROYECTO_DIR/softphones/linphone.AppImage" 2>/dev/null; then
            download_ok=true
        fi
    else
        log_error "No se encontro wget ni curl para descargar Linphone"
        log_info "Puedes descargarlo manualmente desde: https://www.linphone.org/technical-pages/installs"
        return
    fi
    
    if [ "$download_ok" = true ]; then
        chmod +x "$PROYECTO_DIR/softphones/linphone.AppImage"
        log_success "Linphone descargado correctamente"
        log_info "Para ejecutar: ./softphones/linphone.AppImage"
    else
        log_error "Error al descargar Linphone"
        log_info "Puedes descargarlo manualmente desde: https://www.linphone.org/technical-pages/installs"
    fi
}

#--- Prueba rapida de conectividad ---

quick_test() {
    log_step "PRUEBA RAPIDA DE CONECTividad"
    
    # Probar registro de endpoints
    log_info "Verificando estado de endpoints..."
    docker exec "$CONTENEDOR_PRINCIPAL" asterisk -rx "pjsip show endpoints" 2>/dev/null | grep -A2 "Endpoint:" | head -20
    
    echo ""
    log_info "¿Deseas realizar una prueba de llamada interna?"
    read -p "¿Ejecutar prueba de llamada 1001 -> 1002? (s/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        log_info "Iniciando llamada de prueba..."
        docker exec "$CONTENEDOR_PRINCIPAL" asterisk -rx "channel originate PJSIP/1001 application Dial PJSIP/1002,15" 2>/dev/null || true
        sleep 5
        
        log_info "Canales activos:"
        docker exec "$CONTENEDOR_PRINCIPAL" asterisk -rx "core show channels" 2>/dev/null || true
        
        # Colgar llamadas
        docker exec "$CONTENEDOR_PRINCIPAL" asterisk -rx "core stop channels" 2>/dev/null || true
        log_success "Prueba completada"
    fi
}

#--- Informacion final ---

show_final_info() {
    log_step "INFORMACION DE LA CENTRAL VOIP"
    
    echo -e "${BOLD}Credenciales de acceso:${NC}"
    echo -e "  ${CYAN}Extension 1001${NC} (Adrian):  usuario=1001  clave=nova1001"
    echo -e "  ${CYAN}Extension 1002${NC} (Aaron):   usuario=1002  clave=nova2002"
    echo -e "  ${CYAN}Extension 2001${NC} (Remota):  usuario=2001  clave=nova2001"
    echo ""
    echo -e "${BOLD}Plan de numeracion:${NC}"
    echo -e "  ${CYAN}1001, 1002${NC}  → Llamadas internas"
    echo -e "  ${CYAN}9 + numero${NC}  → Saliente por troncal"
    echo -e "  ${CYAN}00 + numero${NC} → Internacional"
    echo -e "  ${CYAN}8600${NC}        → Sala de conferencia"
    echo -e "  ${CYAN}8500${NC}        → Buzon de voz"
    echo -e "  ${CYAN}#72${NC}         → Estacionar llamada (Park)"
    echo ""
    echo -e "${BOLD}Comandos utiles:${NC}"
    echo -e "  ${CYAN}make status${NC}        → Ver estado de servicios"
    echo -e "  ${CYAN}make logs${NC}          → Ver logs en tiempo real"
    echo -e "  ${CYAN}make test-internal${NC} → Probar llamada interna"
    echo -e "  ${CYAN}make test-park${NC}     → Probar parking/hold"
    echo -e "  ${CYAN}make capture${NC}       → Capturar trafico SIP"
    echo -e "  ${CYAN}make help${NC}          → Ver todos los comandos"
    echo ""
    echo -e "${BOLD}Acceso a Asterisk CLI:${NC}"
    echo -e "  ${CYAN}docker exec -it pbx-asterisk asterisk -rvvv${NC}"
    echo ""
    echo -e "${BOLD}Documentacion:${NC}"
    echo -e "  ${CYAN}INFORME.md${NC}     → Informe del proyecto"
    echo -e "  ${CYAN}INSTALACION.md${NC} → Guia detallada"
    echo ""
    echo -e "${GREEN}${BOLD}¡La central VoIP esta lista para usar!${NC}"
}

#--- Funcion principal ---

main() {
    show_banner
    
    echo -e "${BOLD}Directorio del proyecto:${NC} $PROYECTO_DIR"
    echo ""
    
    read -p "¿Comenzar la instalacion? (S/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "Instalacion cancelada"
        exit 0
    fi
    
    # Ejecutar pasos
    check_system
    install_docker
    generate_certs
    cleanup_temp
    prepare_directories
    configure_network
    build_image
    start_services
    verify_installation
    install_linphone
    quick_test
    show_final_info
    
    echo ""
    log_success "Instalacion finalizada!"
}

#--- Manejo de errores ---

trap 'log_error "La instalacion fallo en la linea $LINENO"; exit 1' ERR

#--- Ejecutar ---

main "$@"
