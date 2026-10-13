# Instaladores - Central VoIP

## Instalación Rápida (1 comando)

```bash
cd ~/central-voip && make install-quick
```

O directamente:

```bash
cd ~/central-voip && ./instalar-rapido.sh
```

---

## Instalación Completa (con verificaciones)

```bash
cd ~/central-voip && make install
```

O directamente:

```bash
cd ~/central-voip && ./instalar.sh
```

---

## Qué hace el instalador

| Paso | Acción |
|------|--------|
| 1 | Verifica requisitos del sistema (RAM, disco, internet) |
| 2 | Instala Docker y Docker Compose si no existen |
| 3 | Detecta la IP del host y la red local |
| 4 | Genera certificados TLS autofirmados con **SAN** (incluye la IP del host) |
| 5 | Ajusta `conf/pjsip.conf` con la IP detectada |
| 6 | Prepara directorios (`logs`, `logs/remota`, `captures`, `softphones`) |
| 7 | Limpia archivos temporales/backup |
| 8 | Compila Asterisk 20 desde código fuente (10-20 min) |
| 9 | Inicia los contenedores Docker |
| 10 | Verifica que todo funcione correctamente |
| 11 | Opcionalmente instala Linphone (usa `wget` o `curl`) |
| 12 | Ejecuta prueba rápida de llamada |

---

## Instalación en otra computadora / red

El instalador está preparado para funcionar en cualquier red. No es necesario editar manualmente `conf/pjsip.conf` ni regenerar certificados con comandos de OpenSSL.

Cuando ejecutás `./instalar-rapido.sh` o `./instalar.sh`, el script:

1. Detecta la IP de salida de la máquina (ej: `192.168.1.100`).
2. Genera certificados TLS que incluyen esa IP en el **Subject Alternative Name (SAN)**.
3. Reemplaza los placeholders `__HOST_IP__` y `__LOCAL_NET__` en `conf/pjsip.conf`.

Esto permite que TLS funcione correctamente al conectar Linphone a la IP local de la máquina.

---

## Requisitos previos

- Linux (Fedora, Ubuntu, Debian, Arch)
- Conexión a internet (para compilar Asterisk)
- 4 GB RAM mínimo (8 GB recomendado)
- 10 GB de espacio en disco

> Nota: el instalador usa `wget` o `curl` para descargar Linphone. Si tu distro no trae `wget` instalado, usa `curl` o instalá `wget` antes de correr el instalador.

---

## Después de la instalación

### Verificar estado
```bash
make status
```

### Ver logs
```bash
make logs
```

### Probar llamada interna
```bash
make test-internal
```

### Ver todos los comandos
```bash
make help
```

---

## Credenciales por defecto

| Extensión | Usuario | Contraseña |
|-----------|---------|------------|
| 1001 (Adrian) | 1001 | nova1001 |
| 1002 (Aaron) | 1002 | nova1002 |
| 2001 (Remota) | 2001 | nova2001 |

---

## Solución de problemas

### Docker no inicia
```bash
sudo systemctl start docker
sudo usermod -aG docker $USER
newgrp docker
```

### Asterisk no responde
```bash
docker logs pbx-asterisk
docker restart pbx-asterisk
```

### Reconstruir imagen
```bash
docker compose down
docker rmi asterisk-custom:latest
docker build -t asterisk-custom:latest .
docker compose up -d
```

### Verificar configuración
```bash
docker exec pbx-asterisk asterisk -rx "pjsip show endpoints"
docker exec pbx-asterisk asterisk -rx "dialplan show"
docker exec pbx-asterisk asterisk -rx "core show version"
```

---

*Ultima actualizacion: 12 de octubre de 2026*
