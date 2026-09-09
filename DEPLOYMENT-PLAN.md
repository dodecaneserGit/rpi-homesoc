# 🛡️ [ HOME SOC ] — Plan de Despliegue y Decisiones de Arquitectura (v0.2)

**Fecha:** 1 de Septiembre de 2026  
**Estado:** Pospuesto por viaje. En pausa hasta la vuelta.

## 📌 Resumen de Decisiones

1. **Nodo 1 (RPi 4 Master)** y **Nodo 2 (RPi 3 Backup)** listos físicamente con MicroSD grabadas y fuentes de alimentación.
2. **Nodo 3 (Decoy/Honeypot)**: Al estar agotada la RPi Zero 2 W, se implementará como **nodo virtual en la RPi 4 mediante Docker `macvlan`** con IP propia `192.168.1.50` y MAC propia en la LAN doméstica.
3. **Bloqueador DNS**: Ratificado **AdGuard Home** frente a Pi-hole por arquitectura Go mono-binario, soporte nativo de DoH/DoT/DoQ, integración directa de CrowdSec y sincronización limpia vía API con `adguardhome-sync`.

## 🗺️ Mapa de Red (`192.168.1.0/24`)

* Router / Gateway: `192.168.1.1`
* **Nodo 1 (RPi 4 Master)**:
  - IP DHCP actual: `192.168.1.40`
  - MAC: `e4:5f:01:7c:c2:c2`
  - IP estática objetivo: `192.168.1.2`
* **Nodo 2 (RPi 3 Backup)**:
  - IP DHCP actual: `192.168.1.39`
  - MAC: `b8:27:eb:26:85:2d`
  - IP estática objetivo: `192.168.1.3`
* **Nodo 3 (Honeypot Virtual macvlan)**: IP asignada `192.168.1.50`
* Rango DHCP libre para clientes: `192.168.1.100` – `192.168.1.254`


## 🏁 Pasos para el regreso

1. Conectar por cable Ethernet RPi 4 y RPi 3 y arrancar.
2. Comprobar conectividad SSH.
3. Ejecutar scripts de optimización (`setup-cgroups.sh`, `install-docker.sh`, `setup-zram.sh`).
4. Desplegar `node1-rpi4-master` y verificar AdGuard + Unbound + WireGuard + CrowdSec.
5. Desplegar `node2-rpi3-backup` y verificar replicación `adguard-sync`.
6. Configurar red `macvlan` y levantar el Decoy `node3` en la RPi 4 con IP `.50`.
