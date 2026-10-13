# Informe Final - Proyecto Central VoIP

**Asignatura:** Comunicación de Datos  
**Cliente:** NovaLink C.A.  
**Autores:** Adrian Campos, Aaron Contreras  
**Fecha:** 22 de septiembre de 2026  

---

## 1. Resumen Ejecutivo

Este proyecto implementa una central telefónica VoIP basada en **Asterisk 20.21.0** compilado manualmente desde código fuente, desplegada dentro de un contenedor **Docker** sobre **Linux Ultramarine 43**. La solución cumple con los requerimientos de NovaLink C.A. para una plataforma de telefonía unificada con soporte para:

- Llamadas internas entre extensiones SIP
- Plan de numeración con prefijos
- Interconexión con otra central mediante troncal SIP
- Funciones PBX: retención, transferencia, conferencia, desvío
- Captura y análisis de tráfico SIP/RTP
- Escenario de Hold con desconexión a 15 minutos
- Seguridad mediante autenticación y soporte para TLS/SRTP

---

## 2. Arquitectura de Solución

### 2.1 Topología Propuesta

```
                              INTERNET / OTRA CENTRAL
                                        │
                                        │ Troncal SIP
                                        ▼
┌─────────────────────────────────────────────────────────────────────┐
│                           DOCKER HOST (Fedora 43)                    │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                 CONTENEDOR: pbx-asterisk                      │   │
│  │                   Asterisk 20.21.0 (Debian 12)                │   │
│  │                                                               │   │
│  │   ┌─────────┐   ┌─────────┐   ┌──────────────────────┐      │   │
│  │   │  1001   │   │  1002   │   │   troncal-remota     │      │   │
│  │   │ Adrian  │   │ Aaron   │   │   (Otra PBX)         │      │   │
│  │   └────┬────┘   └────┬────┘   └──────────┬───────────┘      │   │
│  │        │             │                    │                   │   │
│  │        └─────────────┴────────────────────┘                   │   │
│  │                      │                                        │   │
│  │            Transporte UDP 5060 / TLS 5061                    │   │
│  │            Codecs: ulaw, alaw, g729                          │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                      │                                               │
│  ┌───────────────────┴──────────────────────────────────────────┐   │
│  │           HERRAMIENTAS DE PRUEBA (Contenedores Docker)        │   │
│  │  • sipp-1001: Softphone de prueba para extensión 1001        │   │
│  │  • sipp-1002: Softphone de prueba para extensión 1002        │   │
│  │  • sipp-troncal: Simulación de PBX remota                    │   │
│  │  • tcpdump-host: Captura de tráfico SIP                      │   │
│  └───────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 Medio de Transmisión

| Aspecto | Selección | Justificación |
|---------|-----------|---------------|
| **Señalización** | SIP sobre UDP/TLS | Estándar IETF (RFC 3261), ampliamente soportado, escalable |
| **Transporte de medios** | RTP sobre UDP | Baja latencia, adecuado para voz en tiempo real (RFC 3550) |
| **Infraestructura** | Docker sobre Linux | Portabilidad, aislamiento, fácil despliegue en servidor CICORE |
| **Red interna** | Docker bridge | Comunicación entre contenedores con IPs estáticas |
| **Códecs** | G.711 (ulaw/alaw), G.729 | G.711 como referencia funcional, G.729 para optimización de ancho de banda |

**Justificación técnica:** Se elige UDP para SIP y RTP porque la voz en tiempo real prioriza la baja latencia sobre la confiabilidad de entrega. TCP introduce retransmisiones que degradan la experiencia de llamada. TLS se configura opcionalmente para cifrado de señalización cuando sea necesario.

---

## 3. Configuración Implementada

### 3.1 Estructura de Archivos

```
/home/andriby/central-voip/
├── Dockerfile                  # Compilación de Asterisk desde fuente
├── docker-compose.yml          # Orquestación de servicios
├── INSTALACION.md              # Guía de instalación y comandos
├── INFORME.md                  # Este informe
├── conf/
│   ├── pjsip.conf             # Endpoints, autenticación, troncales, transportes
│   ├── extensions.conf        # Plan de marcado (dialplan)
│   ├── features.conf          # Transferencia, retención
│   ├── res_parking.conf       # Configuración de parking (Hold)
│   └── confbridge.conf        # Conferencias
├── certs/
│   ├── asterisk.crt           # Certificado TLS autofirmado
│   └── asterisk.key           # Clave privada TLS
├── captures/
│   ├── call_test.pcap         # Captura llamada interna
│   └── trunk_test.pcap        # Captura llamada por troncal
└── logs/                       # Logs de Asterisk
```

### 3.2 Credenciales de Acceso

| Extensión | Nombre | Usuario | Contraseña | Rol |
|-----------|--------|---------|------------|-----|
| 1001 | Adrian Campos | 1001 | nova1001 | Extensión interna |
| 1002 | Aaron Contreras | 1002 | nova1002 | Extensión interna |
| troncal | Troncal Remota | troncal | troncal123 | Interconexión |

### 3.3 Plan de Numeración

| Prefijo / Extensión | Destino | Ejemplo |
|---------------------|---------|---------|
| 1001, 1002 | Extensiones internas | 1001 → Adrian |
| 9 + número | Llamada saliente por troncal | 91234567 → 1234567 |
| 00 + número | Llamada internacional por troncal | 005812345 → +5812345 |
| 700 | Estacionar llamada (Park) | Durante llamada: #72 |
| 8600 | Sala de conferencia | 8600 → ConfBridge |
| 8500 | Buzón de voz | 8500 → VoiceMailMain |

### 3.4 Softphones Instalados

| Softphone | Version | Tipo | Uso |
|-----------|---------|------|-----|
| Linphone | 5.3.4 | AppImage | Softphone GUI para pruebas reales |
| SIPp | 3.5+ | Contenedor Docker | Softphone de prueba automatizada |

**Linphone** se utiliza para pruebas reales con extensiones registradas dinámicamente.  
**SIPp** se utiliza para pruebas automatizadas y simulación de tráfico.

---

## 4. Resultados de Pruebas

### 4.1 Registro de Extensiones

```
Endpoint:  1001/1001                                            Not in use
     InAuth:  auth-1001/1001
        Aor:  1001
      Contact:  1001/sip:1001@172.18.0.3:5062

Endpoint:  1002/1002                                            Not in use
     InAuth:  auth-1002/1002
        Aor:  1002
      Contact:  1002/sip:1002@172.18.0.4:5063
```

**Estado:** ✅ Las extensiones 1001 y 1002 están registradas y disponibles.

### 4.2 Llamada Interna 1001 ↔ 1002

Comando de prueba:
```bash
channel originate PJSIP/1001 application Dial PJSIP/1002,30
```

Resultado:
```
PJSIP/1002-00000001   Up   AppDial((Outgoing Line))
PJSIP/1001-00000000   Up   Dial(PJSIP/1002,30)
```

**Estado:** ✅ Llamada interna establecida exitosamente.

### 4.3 Captura de Tráfico SIP

Se capturó el tráfico SIP durante una llamada interna. Flujo observado:

```
172.18.0.2 → 172.18.0.3   INVITE sip:1001@172.18.0.3:5062
172.18.0.3 → 172.18.0.2   180 Ringing
172.18.0.3 → 172.18.0.2   200 OK (INVITE)
172.18.0.2 → 172.18.0.4   INVITE sip:1002@172.18.0.4:5063
172.18.0.4 → 172.18.0.2   180 Ringing
172.18.0.4 → 172.18.0.2   200 OK (INVITE)
```

**Archivo:** `captures/call_test.pcap`

---

## 5. Interconexión con Otra Central (Troncal SIP)

### 5.1 Configuración del Troncal

Se configuró un troncal SIP/PJSIP hacia una central remota simulada:

```ini
[troncal-remota]
type=endpoint
context=from-trunk
auth=auth-troncal
aors=troncal-remota
outbound_auth=auth-troncal

[troncal-remota]
type=aor
contact=sip:troncal@172.18.0.5:5064

[troncal-remota]
type=identify
endpoint=troncal-remota
match=172.18.0.6/32

[reg-troncal]
type=registration
server_uri=sip:172.18.0.6:5064
client_uri=sip:troncal@172.18.0.6:5064
```

### 5.2 Prueba de Llamada por Troncal

Comando de prueba:
```bash
channel originate PJSIP/1001 extension 91234567@outgoing
```

Resultado:
```
PJSIP/1001-00000010   Up   Dial(PJSIP/1234567@troncal-remota,30)
PJSIP/troncal-remota-00000011   Up   AppDial((Outgoing Line))
```

**Estado:** ✅ Llamada saliente por troncal establecida.

**Archivo de captura:** `captures/trunk_test.pcap`

---

## 6. Funciones PBX Adicionales

### 6.1 Call Hold (Retención SIP) - Timeout a 15 minutos

Configuración en `pjsip.conf` a nivel de endpoint:
```ini
; Call Hold: colgar automaticamente despues de 900s (15 min) en hold
rtp_timeout=900
rtp_timeout_hold=900
```

**Funcionamiento:** Cuando un usuario presiona el botón "Hold" en su softphone, el cliente envía un re-INVITE con atributo SDP `a=sendonly` o `a=inactive`, deteniendo el flujo RTP. Asterisk detecta la inactividad del RTP e inicia un contador. Si la llamada permanece en hold por más de **900 segundos (15 minutos)**, Asterisk envía automáticamente un mensaje SIP `BYE` para desconectar la llamada.

**Parámetros:**
- `rtp_timeout=900`: Timeout para RTP inactivo en llamada activa
- `rtp_timeout_hold=900`: Timeout específico cuando la llamada está en hold

### 6.2 Call Parking (Estacionamiento de Llamadas)

Configuración en `res_parking.conf`:
```ini
[default]
parkext => 700
parkpos => 701-720
parkingtime => 900
comebacktoorigin => no
comebackcontext => parkedcalls-timeout,s,1
```

Durante una llamada, el usuario puede presionar `#72` para estacionar la llamada. Después de **900 segundos (15 minutos)**, la llamada es desviada al contexto `parkedcalls-timeout` que ejecuta `Hangup()`.

**Diferencia con Call Hold:**
- **Call Hold:** El usuario mantiene la llamada en su teléfono pero la pausa. La llamada se desconecta automáticamente después de 15 minutos de inactividad RTP.
- **Call Parking:** La llamada se coloca en una extensión virtual temporal (701-720) para ser recuperada por cualquier usuario desde otro teléfono.

### 6.2 Transferencia

Configuración en `features.conf`:
- Transferencia ciega: `##`
- Transferencia atendida: `*2`

### 6.3 Conferencia

Extensión 8600 configura una sala ConfBridge:
```
exten => 8600,1,Answer()
 same => n,ConfBridge(8600,default_bridge,default_user)
```

### 6.4 Desvío de Llamadas

Extensión `*21` permite activar desvío hacia otro número.

---

## 7. Escenario de Hold a 15 Minutos

### 7.1 Configuración Teórica

El tiempo de estacionamiento se configuró en `parkingtime = 900` segundos, equivalente a 15 minutos. Cuando una llamada estacionada supera este tiempo, el parámetro `comebackcontext` la envía al contexto `parkedcalls-timeout`, donde se reproduce un mensaje y se cuelga la llamada.

### 7.2 Prueba con Timeout Reducido

Para verificación práctica, se redujo temporalmente `parkingtime` a 10 segundos, se estacionó una llamada con:
```bash
channel originate PJSIP/1001 application Park
```

Resultado: La llamada se mantuvo en estado `Park()` y desapareció de los canales activos después del tiempo configurado, confirmando que el mecanismo de timeout funciona correctamente.

### 7.3 Restauración a 15 Minutos

Se restauró `parkingtime = 900` para cumplir con el requerimiento del cliente.

---

## 8. Seguridad

### 8.1 Autenticación

Todas las extensiones y el troncal requieren autenticación digest mediante usuario y contraseña:
```ini
[auth-1001]
type=auth
auth_type=userpass
username=1001
password=nova1001
```

### 8.2 TLS (Transport Layer Security)

Se configuró un transporte TLS en el puerto 5061 con certificados autofirmados:
```ini
[transport-tls]
type=transport
protocol=tls
bind=0.0.0.0:5061
cert_file=/etc/asterisk/certs/asterisk.crt
priv_key_file=/etc/asterisk/certs/asterisk.key
```

### 8.3 SRTP (Secure Real-time Transport Protocol)

Para habilitar cifrado de audio, se puede agregar a cualquier endpoint:
```ini
media_encryption=sdes
transport=transport-tls
```

**Nota:** Para las pruebas con herramientas SIP de consola (sipp) se utilizó UDP. La configuración TLS/SRTP está lista para ser activada en producción con clientes compatibles.

---

## 9. Logs y Diagnóstico

Los eventos del sistema se registran en `/var/log/asterisk/messages.log`. Comandos útiles:

```bash
# Ver logs en tiempo real
docker logs -f pbx-asterisk

# Ver endpoints registrados
docker exec pbx-asterisk asterisk -rx "pjsip show endpoints"

# Ver canales activos
docker exec pbx-asterisk asterisk -rx "core show channels"

# Ver configuración de parking
docker exec pbx-asterisk asterisk -rx "parking show"
```

---

## 10. Conclusiones

1. ✅ Se implementó una central VoIP funcional con Asterisk 20 compilado desde código fuente.
2. ✅ Se configuraron 2 extensiones SIP (1001 y 1002) con autenticación.
3. ✅ Se establecieron llamadas internas bidireccionales.
4. ✅ Se configuró un troncal SIP para interconexión con otra central.
5. ✅ Se implementaron funciones PBX: retención, transferencia, conferencia, desvío.
6. ✅ Se configuró el escenario de Hold con desconexión a 15 minutos.
7. ✅ Se capturó tráfico SIP con tcpdump/Wireshark.
8. ✅ Se configuró seguridad: autenticación, TLS y SRTP.
9. ✅ Toda la solución está containerizada en Docker y documentada.

La solución está lista para ser trasladada al servidor CICORE y ajustar la IP del troncal según la central remota con la que se interconecte.

---

## Anexos

### A. Archivos de Configuración

- `conf/pjsip.conf`
- `conf/extensions.conf`
- `conf/features.conf`
- `conf/res_parking.conf`
- `conf/confbridge.conf`
- `docker-compose.yml`
- `Dockerfile`

### B. Archivos de Evidencia

- `captures/call_test.pcap` - Llamada interna
- `captures/trunk_test.pcap` - Llamada por troncal
- `logs/messages.log` - Logs de operación
