# Central VoIP - NovaLink C.A.

Central telefónica VoIP basada en **Asterisk 20** compilado desde código fuente, empaquetado en **Docker** y desplegado con **Docker Compose**.

Proyecto de la asignatura **Comunicación de Datos** — UCV.

---

## Autores

- **Adrián Campos** — CI 30.513.493
- **Aarón Contreras** — CI 31.871.275

---

## Características

- ✅ Llamadas internas entre extensiones SIP (1001, 1002)
- ✅ Troncal SIP hacia PBX remota (extensión 2001)
- ✅ Transportes UDP, TCP y TLS
- ✅ Certificados TLS autofirmados con **SAN** (IP del host incluida)
- ✅ Detección automática de la IP del host durante la instalación
- ✅ Funciones PBX: transferencia, estacionamiento (park), conferencia
- ✅ Call hold con timeout configurable (`rtp_timeout_hold=900`)
- ✅ Captura de tráfico SIP/RTP con `tcpdump`
- ✅ Makefile con comandos útiles

---

## Requisitos

| Componente | Mínimo | Recomendado |
|------------|--------|-------------|
| Sistema operativo | Linux (Fedora, Ubuntu, Debian, Arch) | Fedora / Ultramarine 43 |
| RAM | 4 GB | 8 GB |
| Disco | 10 GB libres | 20 GB |
| CPU | 2 núcleos | 4 núcleos |
| Docker | 20.10+ | 29.x |
| Docker Compose | v2.0+ | v2.5+ |

---

## Instalación Rápida

```bash
cd central-voip
./instalar-rapido.sh
```

O con `make`:

```bash
cd central-voip
make install-quick
```

El instalador va a:

1. Verificar e instalar Docker si hace falta
2. Detectar la IP de la máquina automáticamente
3. Generar certificados TLS con la IP incluida en el SAN
4. Ajustar `conf/pjsip.conf` con la IP detectada
5. Compilar Asterisk 20 desde fuente (10–20 min la primera vez)
6. Iniciar los contenedores `pbx-asterisk` y `pbx-remota`

> Si ves error de permisos de Docker, cerrá sesión y volvé a entrar, o ejecutá `newgrp docker`.

Para una instalación con más verificaciones y pasos interactivos:

```bash
./instalar.sh
# o
make install
```

Ver guías detalladas en [`INSTALAR.md`](INSTALAR.md) y [`INSTALACION.md`](INSTALACION.md).

---

## Verificar que Funciona

```bash
make status
```

Debe mostrar el contenedor `pbx-asterisk` corriendo.

```bash
docker exec pbx-asterisk asterisk -rx "core show version"
docker exec pbx-asterisk asterisk -rx "pjsip show endpoints"
```

---

## Credenciales por Defecto

| Extensión | Nombre | Usuario | Contraseña |
|-----------|--------|---------|------------|
| 1001 | Adrián Campos | 1001 | nova1001 |
| 1002 | Aarón Contreras | 1002 | nova1002 |
| 2001 | Usuario Remoto | 2001 | nova2001 |

### Plan de numeración

| Destino | Ejemplo |
|---------|---------|
| Internas | `1001`, `1002` |
| Troncal saliente | `9` + número |
| Conferencia | `8600` |
| Estacionar llamada | `#72` durante la llamada |

---

## Pruebas con Softphone (Linphone)

### Descargar Linphone

```bash
make download-linphone
./softphones/linphone.AppImage
```

### Configuración para UDP

| Campo | Valor |
|-------|-------|
| Username | `1001` |
| Password | `nova1001` |
| Domain | `IP_DE_TU_MAQUINA` (ej: `192.168.1.100`) |
| Transport | **UDP** |
| Port | `5060` |
| Media encryption | **None** (si da error, probar con SRTP) |

### Configuración para TLS

| Campo | Valor |
|-------|-------|
| Username | `1001` |
| Password | `nova1001` |
| Domain | `IP_DE_TU_MAQUINA:5061` |
| Transport | **TLS** |
| Media encryption | **None** primero |

> Al conectar por TLS, Linphone va a mostrar una advertencia de certificado autofirmado. Aceptalo.

### Probar llamada interna

1. En una PC registrá `1001`.
2. En otra PC (o en la misma con otra instancia de Linphone) registrá `1002`.
3. Desde `1001` llamá a `1002`.

Si hay audio en ambos sentidos, ✅ la llamada interna funciona.

### Probar troncal (entre dos máquinas)

1. Ambas máquinas deben estar en la misma red (LAN o ZeroTier).
2. En cada máquina ejecutar `./instalar-rapido.sh` para que detecte su propia IP.
3. Desde `1001` en la máquina principal, marcar `92001` para llamar al `2001` de la máquina remota.

> Si la IP detectada no es la de ZeroTier (por ejemplo, detecta `192.168.X.X` en lugar de `10.119.203.X`), avisá para ajustar la detección.

---

## Estructura del Proyecto

```
central-voip/
├── Dockerfile                 # Build de Asterisk 20 con SRTP
├── docker-compose.yml         # Servicios pbx-asterisk y pbx-remota
├── Makefile                   # Comandos útiles
├── README.md                  # Este archivo
├── INSTALAR.md               # Guía rápida de instalación
├── INSTALACION.md            # Guía completa paso a paso
├── INFORME.md                # Informe final del proyecto
├── conf/
│   ├── pjsip.conf            # Endpoints, transportes, troncal
│   ├── extensions.conf       # Dialplan
│   ├── features.conf         # Transferencias
│   ├── res_parking.conf      # Call parking
│   ├── confbridge.conf       # Conferencias
│   ├── rtp.conf              # Configuración RTP
│   ├── voicemail.conf        # Buzón de voz
│   └── remota/               # Configuración de pbx-remota
├── certs/                    # Certificados TLS (generados por el instalador)
├── logs/                     # Logs de Asterisk
├── captures/                 # Capturas de tráfico
└── softphones/               # Linphone AppImage
```

---

## Comandos Útiles (`make`)

```bash
make help              # Ver todos los comandos
make status            # Estado de los servicios
make logs              # Ver logs en tiempo real
make restart           # Reiniciar servicios
make test-internal     # Probar llamada 1001 -> 1002
make test-park         # Probar estacionamiento
make capture           # Capturar tráfico SIP/RTP
make capture-stop      # Detener captura
make analyze           # Analizar última captura
make download-linphone # Descargar Linphone
```

---

## Solución de Problemas Rápida

### No puedo usar Docker sin `sudo`

```bash
sudo usermod -aG docker $USER
newgrp docker
```

### Asterisk no inicia o el contenedor se reinicia

```bash
docker logs pbx-asterisk --tail 50
docker exec pbx-asterisk asterisk -rx "core show version"
```

### No se escucha audio

Verificar que el firewall no bloquee los puertos RTP:

```bash
# Fedora
sudo firewall-cmd --add-port=5060/udp --permanent
sudo firewall-cmd --add-port=5060/tcp --permanent
sudo firewall-cmd --add-port=5061/tcp --permanent
sudo firewall-cmd --add-port=10000-10100/udp --permanent
sudo firewall-cmd --reload

# Ubuntu
sudo ufw allow 5060/udp
sudo ufw allow 5060/tcp
sudo ufw allow 5061/tcp
sudo ufw allow 10000:10100/udp
```

### Error de TLS: certificado no válido

Asegurate de haber ejecutado `./instalar-rapido.sh` después de copiar el proyecto. Eso regenera el certificado con la IP de la máquina en el SAN.

```bash
openssl x509 -in certs/asterisk.crt -noout -text | grep -A2 "Subject Alternative Name"
```

Debe mostrar la IP de la máquina, por ejemplo:

```
DNS:asterisk.novalink.local, IP Address:127.0.0.1, IP Address:192.168.1.100
```

### Error de UDP con `media_encryption=sdes`

Si las llamadas UDP fallan con `488 Not Acceptable Here`, puede ser porque Asterisk está exigiendo SRTP y el softphone no lo soporta.

Como solución temporal, comentá la línea en `conf/pjsip.conf`:

```ini
;media_encryption=sdes
```

Y reiniciá:

```bash
docker compose restart pbx-asterisk
```

---

## Documentación Adicional

- [`INSTALAR.md`](INSTALAR.md) — Guía rápida de instalación
- [`INSTALACION.md`](INSTALACION.md) — Guía completa paso a paso
- [`INFORME.md`](INFORME.md) — Informe técnico final

---

## Notas

- El proyecto está diseñado para instalarse en cualquier red. El instalador detecta la IP del host y genera certificados y configuración acordes.
- El certificado TLS es autofirmado. En producción debe reemplazarse por uno emitido por una CA.
- El parámetro `media_encryption=sdes` está activo por defecto. Si el softphone no soporta SRTP, desactivalo temporalmente según se indica en la sección de solución de problemas.

---

*Última actualización: 12 de octubre de 2026*
