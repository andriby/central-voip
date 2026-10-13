#=============================================
# Makefile - Central VoIP
# Proyecto Comunicacion de Datos
#=============================================

.PHONY: help install install-quick install-full start stop restart status logs test test-internal test-trunk test-park capture analyze reload extensions download-linphone clean

# Colores
GREEN=\033[0;32m
CYAN=\033[0;36m
NC=\033[0m

help: ## Mostrar esta ayuda
	@echo ""
	@echo "$(CYAN)============================================$(NC)"
	@echo "$(CYAN)  COMANDOS DISPONIBLES - CENTRAL VOIP$(NC)"
	@echo "$(CYAN)============================================$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "$(GREEN)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""

install: ## Instalar todo (Docker, certificados, imagen)
	@chmod +x instalar.sh
	@./instalar.sh

install-quick: ## Instalacion rapida (sin preguntas)
	@chmod +x instalar-rapido.sh
	@./instalar-rapido.sh

install-full: ## Instalacion completa con verificaciones
	@chmod +x instalar.sh
	@./instalar.sh

start: ## Iniciar todos los servicios
	@echo "$(CYAN)Iniciando servicios...$(NC)"
	@docker compose up -d
	@echo "$(GREEN)Servicios iniciados.$(NC)"
	@echo ""
	@sleep 3
	@$(MAKE) status

stop: ## Detener todos los servicios
	@echo "$(CYAN)Deteniendo servicios...$(NC)"
	@docker compose down
	@echo "$(GREEN)Servicios detenidos.$(NC)"

restart: ## Reiniciar todos los servicios
	@echo "$(CYAN)Reiniciando servicios...$(NC)"
	@docker compose down
	@docker compose up -d
	@echo "$(GREEN)Servicios reiniciados.$(NC)"
	@sleep 3
	@$(MAKE) status

status: ## Ver estado de todos los servicios
	@echo ""
	@echo "$(CYAN)============================================$(NC)"
	@echo "$(CYAN)  ESTADO DE SERVICIOS$(NC)"
	@echo "$(CYAN)============================================$(NC)"
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
	@echo ""
	@echo "$(CYAN)Endpoints SIP:$(NC)"
	@docker exec pbx-asterisk asterisk -rx "pjsip show endpoints" 2>/dev/null | grep -E "Endpoint:|Aor:|Contact:" || true
	@echo ""

logs: ## Ver logs en tiempo real
	@docker logs -f pbx-asterisk

logs-sipp: ## Ver logs de softphones de prueba
	@echo "$(CYAN)=== SIPP 1001 ===$(NC)"
	@docker logs sipp-1001 2>&1 | tail -10
	@echo ""
	@echo "$(CYAN)=== SIPP 1002 ===$(NC)"
	@docker logs sipp-1002 2>&1 | tail -10
	@echo ""
	@echo "$(CYAN)=== SIPP TRONCAL ===$(NC)"
	@docker logs sipp-troncal 2>&1 | tail -10

test: test-internal test-trunk ## Ejecutar todas las pruebas

test-internal: ## Probar llamada interna 1001 -> 1002
	@echo ""
	@echo "$(CYAN)=== PRUEBA: Llamada interna 1001 -> 1002 ===$(NC)"
	@docker exec pbx-asterisk asterisk -rx "channel originate PJSIP/1001 application Dial PJSIP/1002,30"
	@sleep 8
	@echo "$(GREEN)Canales activos:$(NC)"
	@docker exec pbx-asterisk asterisk -rx "core show channels"
	@docker exec pbx-asterisk asterisk -rx "core stop channels" 2>/dev/null || true
	@echo "$(GREEN)Prueba completada.$(NC)"
	@echo ""

test-trunk: ## Probar llamada por troncal (saliente)
	@echo ""
	@echo "$(CYAN)=== PRUEBA: Llamada por troncal ===$(NC)"
	@docker exec pbx-asterisk asterisk -rx "channel originate PJSIP/1001 extension 91234567@outgoing"
	@sleep 8
	@echo "$(GREEN)Canales activos:$(NC)"
	@docker exec pbx-asterisk asterisk -rx "core show channels"
	@docker exec pbx-asterisk asterisk -rx "core stop channels" 2>/dev/null || true
	@echo "$(GREEN)Prueba completada.$(NC)"
	@echo ""

test-park: ## Probar parking/hold
	@echo ""
	@echo "$(CYAN)=== PRUEBA: Parking (Hold) ===$(NC)"
	@echo "Configuracion actual:"
	@docker exec pbx-asterisk asterisk -rx "parking show" 2>/dev/null | grep -E "Parking Time|Comeback"
	@echo ""
	@echo "Iniciando llamada estacionada..."
	@docker exec pbx-asterisk asterisk -rx "channel originate PJSIP/1001 application Park"
	@sleep 3
	@echo "$(GREEN)Canales activos (deberia mostrar Park):$(NC)"
	@docker exec pbx-asterisk asterisk -rx "core show channels"
	@echo ""
	@echo "Esperando 12 segundos para verificar timeout..."
	@sleep 12
	@echo "$(GREEN)Canales despues de timeout (deberia estar vacio):$(NC)"
	@docker exec pbx-asterisk asterisk -rx "core show channels"
	@echo "$(GREEN)Prueba completada.$(NC)"
	@echo ""

capture: ## Capturar trafico SIP durante una llamada
	@echo ""
	@echo "$(CYAN)=== CAPTURA DE TRAFICO SIP ===$(NC)"
	@# Obtener ID de la red
	@NETWORK_ID=$$(docker network inspect $(notdir $(CURDIR))_voip-net --format '{{.ID}}' | cut -c1-12) && \
	BRIDGE_IF=$$(ip link show | grep "br-$$NETWORK_ID" | awk -F': ' '{print $$2}' | head -1) && \
	echo "Interface: $$BRIDGE_IF" && \
	echo "Iniciando captura..." && \
	docker run -d --net host --privileged --name tcpdump-capture \
		-v $(PWD)/captures:/captures:z \
		nicolaka/netshoot \
		tcpdump -i $$BRIDGE_IF -w /captures/captura_$$(date +%Y%m%d_%H%M%S).pcap -s 0 'port 5060 or portrange 10000-10100' && \
	echo "Captura iniciada. Realiza tu llamada ahora." && \
	echo "Cuando termines, ejecuta: make capture-stop"

capture-stop: ## Detener captura y mostrar archivo
	@echo "$(CYAN)Deteniendo captura...$(NC)"
	@docker stop tcpdump-capture 2>/dev/null || true
	@docker rm tcpdump-capture 2>/dev/null || true
	@echo "$(GREEN)Captura guardada en:$(NC)"
	@ls -la captures/*.pcap 2>/dev/null | tail -1
	@echo ""
	@echo "Para analizar con tshark:"
	@echo "  docker run --rm -v \$(pwd)/captures:/captures:z nicolaka/netshoot tshark -r /captures/*.pcap -Y sip"

analyze: ## Analizar la ultima captura SIP
	@echo ""
	@echo "$(CYAN)=== ANALISIS DE CAPTURA SIP ===$(NC)"
	@docker run --rm -v $(PWD)/captures:/captures:z nicolaka/netshoot tshark -r /captures/*.pcap -Y sip 2>/dev/null | head -30

reload: ## Recargar configuracion de Asterisk
	@echo "$(CYAN)Recargando configuracion...$(NC)"
	@docker exec pbx-asterisk asterisk -rx "pjsip reload"
	@docker exec pbx-asterisk asterisk -rx "dialplan reload"
	@docker exec pbx-asterisk asterisk -rx "module reload res_parking.so"
	@echo "$(GREEN)Configuracion recargada.$(NC)"

extensions: ## Ver todas las extensiones configuradas
	@echo ""
	@echo "$(CYAN)=== EXTENSIONES CONFIGURADAS ===$(NC)"
	@docker exec pbx-asterisk asterisk -rx "dialplan show" 2>/dev/null | grep -A2 "internas\|outgoing\|from-trunk" || true

download-linphone: ## Descargar Linphone (softphone)
	@echo "$(CYAN)Descargando Linphone 5.3.4...$(NC)"
	@mkdir -p softphones
	@if command -v wget >/dev/null 2>&1; then \
		wget -q --show-progress --timeout=120 \
			"https://download.linphone.org/releases/linux/app/Linphone-5.3.4.AppImage" \
			-O softphones/linphone.AppImage; \
	elif command -v curl >/dev/null 2>&1; then \
		curl -fsSL --progress-bar --max-time 120 \
			"https://download.linphone.org/releases/linux/app/Linphone-5.3.4.AppImage" \
			-o softphones/linphone.AppImage; \
	else \
		echo "$(RED)Error: se requiere wget o curl$(NC)"; \
		exit 1; \
	fi
	@chmod +x softphones/linphone.AppImage
	@echo "$(GREEN)Linphone descargado en: softphones/linphone.AppImage$(NC)"
	@echo "Ejecutar: ./softphones/linphone.AppImage"

clean: ## Limpiar contenedores y imagenes
	@echo "$(CYAN)Limpiando recursos...$(NC)"
	@docker compose down --remove-orphans 2>/dev/null || true
	@docker rm -f tcpdump-capture 2>/dev/null || true
	@echo "$(GREEN)Limpieza completada.$(NC)"
