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
| 3 | Genera certificados TLS autofirmados |
| 4 | Limpia archivos temporales/backup |
| 5 | Prepara directorios (logs, captures, softphones) |
| 6 | Configura red y detecta IP del host |
| 7 | Compila Asterisk 20 desde código fuente (10-20 min) |
| 8 | Inicia los contenedores Docker |
| 9 | Verifica que todo funcione correctamente |
| 10 | Opcionalmente instala Linphone |
| 11 | Ejecuta prueba rápida de llamada |

---

## Requisitos previos

- Linux (Fedora, Ubuntu, Debian, Arch)
- Conexión a internet (para compilar Asterisk)
- 4 GB RAM mínimo (8 GB recomendado)
- 10 GB de espacio en disco

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
