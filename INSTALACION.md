# Guia Completa de Instalacion - Central VoIP

**Proyecto:** Implementacion y Administracion de una Central VoIP  
**Asignatura:** Comunicacion de Datos  
**Autores:** Adrian Campos y Aaron Contreras  

---

## Tabla de Contenidos

1. [Requisitos del Sistema](#1-requisitos-del-sistema)
2. [Estructura del Proyecto](#2-estructura-del-proyecto)
3. [Paso 1: Copiar el Proyecto](#3-paso-1-copiar-el-proyecto)
4. [Paso 2: Instalar Docker](#4-paso-2-instalar-docker)
5. [Paso 3: Generar Certificados TLS](#5-paso-3-generar-certificados-tls)
6. [Paso 4: Construir la Imagen de Asterisk](#6-paso-4-construir-la-imagen-de-asterisk)
7. [Paso 5: Levantar los Servicios](#7-paso-5-levantar-los-servicios)
8. [Paso 6: Instalar Softphones](#8-paso-6-instalar-softphones)
9. [Paso 7: Verificar la Instalacion](#9-paso-7-verificar-la-instalacion)
10. [Paso 8: Probar Llamadas](#10-paso-8-probar-llamadas)
11. [Paso 9: Capturar Trafico](#11-paso-9-capturar-trafico)
12. [Credenciales y Plan de Numeracion](#12-credenciales-y-plan-de-numeracion)
13. [Comandos de Gestion](#13-comandos-de-gestion)
14. [Solucion de Problemas](#14-solucion-de-problemas)

---

## 1. Requisitos del Sistema

| Componente | Minimo | Recomendado |
|------------|--------|-------------|
| **SO** | Linux (Fedora 40+, Ubuntu 22+) | Ultramarine Linux 43 / Fedora 43 |
| **RAM** | 4 GB | 8 GB |
| **Disco** | 10 GB libres | 20 GB |
| **CPU** | 2 nucleos | 4 nucleos |
| **Red** | Conexion a internet (para construir imagen) | - |
| **Docker** | 20.10+ | 29.x |
| **Docker Compose** | v2.0+ | v2.5+ |

---

## 2. Estructura del Proyecto

```
central-voip/
├── Dockerfile                 # Compilacion de Asterisk 20 desde fuente
├── docker-compose.yml         # Orquestacion de servicios
├── INFORME.md                 # Informe final del proyecto
├── INSTALACION.md             # Esta guia de instalacion
├── conf/
│   ├── pjsip.conf            # Configuracion SIP (endpoints, auth, troncal, RTP timeout)
│   ├── extensions.conf       # Dialplan (plan de marcado)
│   ├── features.conf         # Transferencias y funciones
│   ├── res_parking.conf      # Configuracion de Call Parking
│   └── confbridge.conf       # Configuracion de conferencias
├── certs/
│   ├── asterisk.crt           # Certificado TLS autofirmado
│   └── asterisk.key           # Clave privada TLS
├── captures/
│   ├── call_test.pcap         # Captura de llamada interna
│   └── trunk_test.pcap        # Captura de llamada por troncal
├── softphones/
│   ├── linphone.AppImage      # Softphone Linphone 5.3.4
│   └── config_1001.conf       # Configuracion para ext 1001
└── logs/
    └── messages.log           # Logs de Asterisk
```

---

## 3. Paso 1: Copiar el Proyecto

### Desde memoria USB u otro medio:

```bash
# Copiar el proyecto al directorio del usuario
cp -r central-voip ~/

# Verificar que se copio correctamente
ls -la ~/central-voip/
```

### Desde repositorio Git (si aplica):

```bash
cd ~
git clone <URL_DEL_REPOSITORIO> central-voip
```

### Verificar la estructura:

```bash
ls -la ~/central-voip/
# Debe mostrar: Dockerfile, docker-compose.yml, conf/, certs/, captures/, logs/
```

---

## 4. Paso 2: Instalar Docker

### En Fedora / Ultramarine Linux:

```bash
# Instalar Docker
sudo dnf install -y docker docker-compose

# Agregar usuario al grupo docker (para no usar sudo)
sudo usermod -aG docker $USER

# Aplicar cambios de grupo (cerrar y abrir sesion, o ejecutar):
newgrp docker

# Verificar instalacion
docker --version
docker compose version
```

### En Ubuntu / Debian:

```bash
# Actualizar repositorios
sudo apt-get update

# Instalar dependencias
sudo apt-get install -y ca-certificates curl gnupg

# Agregar clave GPG de Docker
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Agregar repositorio
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Instalar Docker
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Agregar usuario al grupo docker
sudo usermod -aG docker $USER
newgrp docker
```

### Verificar Docker funciona:

```bash
docker run hello-world
```

---

## 5. Paso 3: Generar Certificados TLS

```bash
# Crear directorio de certificados
mkdir -p ~/central-voip/certs

# Generar certificado autofirmado (validez 1 ano)
openssl req -x509 -newkey rsa:2048 \
  -keyout ~/central-voip/certs/asterisk.key \
  -out ~/central-voip/certs/asterisk.crt \
  -days 365 -nodes \
  -subj "/C=VE/ST=Caracas/L=Caracas/O=NovaLink/OU=VoIP/CN=asterisk.novalink.local"

# Verificar que se generaron
ls -la ~/central-voip/certs/
# Debe mostrar: asterisk.crt (1.3K) y asterisk.key (1.7K)
```

---

## 6. Paso 4: Construir la Imagen de Asterisk

```bash
# Navegar al directorio del proyecto
cd ~/central-voip

# Construir la imagen (esto tarda 10-20 minutos la primera vez)
docker build -t asterisk-custom:latest .

# Verificar que la imagen se creo
docker images asterisk-custom
# Debe mostrar: asterisk-custom   latest   <hash>   ~2GB
```

**NOTA:** La imagen incluye Asterisk 20.21.0 compilado desde codigo fuente sobre Debian 12-slim.

---

## 7. Paso 5: Levantar los Servicios

### 7.1 Iniciar Asterisk:

```bash
cd ~/central-voip

# Levantar el contenedor
docker compose up -d

# Verificar que esta corriendo
docker ps
# Debe mostrar: pbx-asterisk   Up   0.0.0.0:5060->5060/udp, ...

# Verificar que Asterisk cargo correctamente
docker exec pbx-asterisk asterisk -rx "pjsip show endpoints"
# Debe mostrar: Endpoint 1001/1001, Endpoint 1002/1002, Endpoint troncal-remota/0
```

### 7.2 Iniciar herramientas de prueba (opcional):

```bash
# Iniciar sipp para simular softphones (pruebas automatizadas)
docker run -d --network central-voip_voip-net --name sipp-1001 \
  --entrypoint sipp ctaloi/sipp -sn uas -i 0.0.0.0 -p 5062

docker run -d --network central-voip_voip-net --name sipp-1002 \
  --entrypoint sipp ctaloi/sipp -sn uas -i 0.0.0.0 -p 5063

docker run -d --network central-voip_voip-net --name sipp-troncal \
  --entrypoint sipp ctaloi/sipp -sn uas -i 0.0.0.0 -p 5064

# Verificar que estan corriendo
docker ps --filter name=sipp
```

---

## 8. Paso 6: Instalar Softphones

### 8.1 Descargar Linphone:

```bash
# Crear directorio para softphones
mkdir -p ~/central-voip/softphones

# Descargar Linphone 5.3.4 (AppImage)
cd ~/central-voip/softphones
wget -q --timeout=120 \
  "https://download.linphone.org/releases/linux/app/Linphone-5.3.4.AppImage" \
  -O linphone.AppImage

# Hacer ejecutable
chmod +x linphone.AppImage

# Verificar
ls -la linphone.AppImage
# Debe mostrar: ~97MB y permisos rwxr-xr-x
```

### 8.2 Ejecutar Linphone:

```bash
cd ~/central-voip/softphones
./linphone.AppImage
```

### 8.3 Configurar softphone para Extension 1001 (Adrian):

1. En Linphone, ir a **Preferences** → **Manage accounts**
2. Click **Add account** → **SIP account**
3. Completar:
   - **Username:** `1001`
   - **Password:** `nova1001`
   - **Domain/SIP server:** `TU_IP_LOCAL` (ej: `192.168.1.100`)
   - **Transport:** UDP
4. Click **Apply** y **OK**

### 8.4 Configurar softphone para Extension 1002 (Aaron):

Aaron debe:
1. Descargar Linphone en su computadora
2. Ejecutar `./linphone.AppImage`
3. Configurar:
   - **Username:** `1002`
   - **Password:** `nova1002`
   - **Domain/SIP server:** `TU_IP_LOCAL`
   - **Transport:** UDP

### 8.5 Ver tu IP local:

```bash
# Ejecutar esto en tu computadora
ip addr show | grep "inet " | grep -v 127.0.0.1 | head -3

# O usar hostname
hostname -I
```

---

## 9. Paso 7: Verificar la Instalacion

### Verificar endpoints:

```bash
docker exec pbx-asterisk asterisk -rx "pjsip show endpoints"
```

**Salida esperada:**
```
Endpoint:  1001/1001   Unavailable   (esperando registro)
Endpoint:  1002/1002   Unavailable   (esperando registro)
Endpoint:  troncal-remota/0   Not in use   (troncal configurada)
```

### Verificar transportes:

```bash
docker exec pbx-asterisk asterisk -rx "pjsip show transports"
```

**Salida esperada:**
```
Transport:  transport-udp   udp   0   0   0.0.0.0:5060
Transport:  transport-tls   tls   0   0   0.0.0.0:5061
```

### Verificar dialplan:

```bash
docker exec pbx-asterisk asterisk -rx "dialplan show"
```

**Salida esperada:** Debe mostrar contextos `internas`, `outgoing`, `from-trunk`, etc.

### Verificar parking:

```bash
docker exec pbx-asterisk asterisk -rx "parking show"
```

**Salida esperada:**
```
Parking Lot: default
Parking Time: 900 sec
Comeback Context: parkedcalls-timeout,s,1
```

### Verificar Call Hold (RTP timeout):

```bash
docker exec pbx-asterisk asterisk -rx "pjsip show endpoint 1001" | grep rtp_timeout
```

**Salida esperada:**
```
 rtp_timeout                        : 900
 rtp_timeout_hold                   : 900
```

### Verificar features:

```bash
docker exec pbx-asterisk asterisk -rx "features show"
```

**Salida esperada:**
```
Blind Transfer     ##
Attended Transfer  *2
Park Call          #72
```

---

## 10. Paso 8: Probar Llamadas

### 10.1 Llamada interna 1001 -> 1002:

```bash
# Iniciar llamada
docker exec pbx-asterisk asterisk -rx "channel originate PJSIP/1001 application Dial PJSIP/1002,30"

# Esperar 8 segundos y verificar
sleep 8
docker exec pbx-asterisk asterisk -rx "core show channels"

# Colgar
docker exec pbx-asterisk asterisk -rx "core stop channels"
```

**Salida esperada:**
```
PJSIP/1002-00000001   Up   AppDial((Outgoing Line))
PJSIP/1001-00000000   Up   Dial(PJSIP/1002,30)
```

### 10.2 Llamada interna 1002 -> 1001:

```bash
docker exec pbx-asterisk asterisk -rx "channel originate PJSIP/1002 application Dial PJSIP/1001,30"
sleep 8
docker exec pbx-asterisk asterisk -rx "core show channels"
docker exec pbx-asterisk asterisk -rx "core stop channels"
```

### 10.3 Llamada por troncal (saliente):

```bash
docker exec pbx-asterisk asterisk -rx "channel originate PJSIP/1001 extension 91234567@outgoing"
sleep 8
docker exec pbx-asterisk asterisk -rx "core show channels"
docker exec pbx-asterisk asterisk -rx "core stop channels"
```

### 10.4 Prueba de Call Hold (Retencion):

```bash
# Verificar configuracion RTP timeout
docker exec pbx-asterisk asterisk -rx "pjsip show endpoint 1001" | grep rtp_timeout

# Iniciar llamada
docker exec pbx-asterisk asterisk -rx "channel originate PJSIP/1001 application Dial PJSIP/1002,30"
sleep 5

# Verificar que la llamada esta activa
docker exec pbx-asterisk asterisk -rx "core show channels"

# NOTA: Para probar el timeout de 15 minutos, presiona Hold en el softphone
# y espera 900 segundos. La llamada se desconectara automaticamente.
# Para una prueba rapida, cambiar rtp_timeout_hold a 10 segundos temporalmente.

# Colgar
docker exec pbx-asterisk asterisk -rx "core stop channels"
```

### 10.5 Prueba de Call Parking (Estacionamiento):

```bash
# Estacionar llamada
docker exec pbx-asterisk asterisk -rx "channel originate PJSIP/1001 application Park"

# Verificar que esta estacionada (debe mostrar 1 canal activo)
sleep 3
docker exec pbx-asterisk asterisk -rx "core show channels"

# Esperar 12 segundos para ver que se desconecta automaticamente
sleep 12
docker exec pbx-asterisk asterisk -rx "core show channels"
# Debe mostrar: 0 active channels
```

---

## 11. Paso 9: Capturar Trafico

### 11.1 Iniciar captura:

```bash
# Iniciar contenedor de captura en la interfaz bridge del host
docker run -d --net host --privileged --name tcpdump-host \
  -v ~/central-voip/captures:/captures:z \
  nicolaka/netshoot \
  tcpdump -i br-$(docker network inspect central-voip_voip-net --format '{{.ID}}' | cut -c1-12) \
  -w /captures/llamada_$(date +%Y%m%d_%H%M%S).pcap \
  -s 0 'port 5060 or portrange 10000-10100'

# Verificar que esta corriendo
docker ps --filter name=tcpdump-host
```

### 11.2 Realizar llamada y capturar:

```bash
# Hacer llamada (mientras tcpdump esta capturando)
docker exec pbx-asterisk asterisk -rx "channel originate PJSIP/1001 application Dial PJSIP/1002,30"
sleep 10

# Colgar
docker exec pbx-asterisk asterisk -rx "core stop channels"
sleep 2

# Detener captura
docker stop tcpdump-host

# Verificar archivo generado
ls -la ~/central-voip/captures/*.pcap
```

### 11.3 Analizar captura con tshark:

```bash
# Ver flujo SIP
docker run --rm -v ~/central-voip/captures:/captures:z \
  nicolaka/netshoot tshark -r /captures/*.pcap -Y sip | head -30

# Ver solo INVITEs
docker run --rm -v ~/central-voip/captures:/captures:z \
  nicolaka/netshoot tshark -r /captures/*.pcap -Y "sip.Method == INVITE"
```

---

## 12. Credenciales y Plan de Numeracion

### Extensiones:

| Extension | Nombre | Usuario | Contrasena | Contexto |
|-----------|--------|---------|------------|----------|
| 1001 | Adrian Campos | 1001 | nova1001 | internas |
| 1002 | Aaron Contreras | 1002 | nova1002 | internas |

### Troncal:

| Parametro | Valor |
|-----------|-------|
| Nombre | troncal-remota |
| Usuario | troncal |
| Contrasena | troncal123 |
| Puerto | 5064 |

### Plan de Numeracion:

| Prefijo | Destino | Ejemplo |
|---------|---------|---------|
| 1001, 1002 | Extensiones internas | 1001 -> Adrian |
| 9 + numero | Saliente por troncal | 91234567 |
| 00 + numero | Internacional por troncal | 005812345 |
| 700 | Estacionar (Park) | Durante llamada: #72 |
| 8600 | Conferencia | 8600 -> ConfBridge |
| 8500 | Buzon de voz | 8500 -> VoiceMailMain |
| *21*num | Activar desvio | *21*1002 |

### Funciones PBX:

| Funcion | Tecla |
|---------|-------|
| Transferencia ciega | ## |
| Transferencia atendida | *2 |
| Estacionar llamada | #72 |

---

## 13. Comandos de Gestion

### Contenedor:

```bash
# Ver contenedores corriendo
docker ps

# Ver logs en tiempo real
docker logs -f pbx-asterisk

# Entrar al CLI de Asterisk
docker exec -it pbx-asterisk asterisk -rvvv

# Detener servicios
cd ~/central-voip && docker compose down

# Reiniciar servicios
cd ~/central-voip && docker compose restart
```

### Asterisk (desde docker exec):

```bash
# Ver endpoints
docker exec pbx-asterisk asterisk -rx "pjsip show endpoints"

# Ver auth
docker exec pbx-asterisk asterisk -rx "pjsip show auths"

# Ver AORs
docker exec pbx-asterisk asterisk -rx "pjsip show aors"

# Ver transportes
docker exec pbx-asterisk asterisk -rx "pjsip show transports"

# Ver canales activos
docker exec pbx-asterisk asterisk -rx "core show channels"

# Ver dialplan
docker exec pbx-asterisk asterisk -rx "dialplan show"

# Ver parking
docker exec pbx-asterisk asterisk -rx "parking show"

# Ver features
docker exec pbx-asterisk asterisk -rx "features show"

# Recargar PJSIP
docker exec pbx-asterisk asterisk -rx "pjsip reload"

# Recargar dialplan
docker exec pbx-asterisk asterisk -rx "dialplan reload"

# Recargar parking
docker exec pbx-asterisk asterisk -rx "module reload res_parking.so"

# Colgar todos los canales
docker exec pbx-asterisk asterisk -rx "core stop channels"
```

---

## 14. Solucion de Problemas

### Error: "permission denied" al usar docker

**Causa:** El usuario no esta en el grupo docker.

**Solucion:**
```bash
sudo usermod -aG docker $USER
newgrp docker
```

### Error: SELinux bloquea volumenes Docker

**Causa:** SELinux en Fedora/Ultramarine bloquea archivos montados.

**Solucion:** Ya esta resuelto con el flag `:z` en docker-compose.yml.

### Error: "Could not create dialog to invalid URI"

**Causa:** Sintaxis incorrecta para marcar por troncal.

**Solucion:** Usar `PJSIP/<numero>@<endpoint>` en lugar de `PJSIP/<endpoint>/<numero>`.

### Error: Endpoint muestra "Unavailable"

**Causa:** No hay softphone registrado.

**Solucion:** Registrar softphone con las credenciales correctas (ver Paso 6).

### Error: "Asterisk module res_parking declined to load"

**Causa:** Archivo res_parking.conf con secciones incorrectas.

**Solucion:** Verificar que res_parking.conf solo tiene secciones de tipo `[default]`, no dialplan.

### Error: No se escucha audio en llamada

**Causa:** Firewall bloquea puertos RTP 10000-10100.

**Solucion:**
```bash
# Abrir puertos RTP
sudo firewall-cmd --add-port=10000-10100/udp --permanent
sudo firewall-cmd --reload

# O deshabilitar firewall temporalmente
sudo systemctl stop firewalld
```

### Error: Linphone no inicia

**Causa:** Falta FUSE para AppImages.

**Solucion:**
```bash
# En Fedora
sudo dnf install -y fuse fuse-libs

# En Ubuntu
sudo apt-get install -y fuse libfuse2
```

### Error: No se puede conectar desde otra computadora

**Causa:** Puertos no accesibles en la red.

**Solucion:**
```bash
# Verificar IP local
ip addr show | grep "inet " | grep -v 127.0.0.1

# Abrir puertos en firewall
sudo firewall-cmd --add-port=5060/udp --permanent
sudo firewall-cmd --add-port=5060/tcp --permanent
sudo firewall-cmd --add-port=5061/tcp --permanent
sudo firewall-cmd --add-port=10000-10100/udp --permanent
sudo firewall-cmd --reload
```

---

## Notas para Despliegue en Servidor CICORE

1. Copiar todo el directorio `~/central-voip/` al servidor
2. Instalar Docker (ver Paso 2)
3. Generar certificados (ver Paso 3)
4. Construir imagen (ver Paso 4)
5. Ajustar IP del troncal en `conf/pjsip.conf` si es necesario
6. Levantar servicios (ver Paso 5)
7. Verificar funcionamiento (ver Paso 7)
8. Para TLS en produccion, reemplazar certificados autofirmados por validos

---

## URLs Utiles

- **Asterisk:** https://www.asterisk.org
- **PJSIP Documentation:** https://docs.asterisk.org/Configuration/Channel-Drivers/SIP/
- **Linphone:** https://www.linphone.org
- **SIPp:** https://sipp.readthedocs.io
- **Wireshark:** https://www.wireshark.org

---

*Ultima actualizacion: 22 de septiembre de 2026*
