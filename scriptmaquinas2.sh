#!/bin/bash
# Script para despliegue de VMs en Proxmox

# Configuración común
ISO_PATH="/var/lib/vz/template/iso"
BRIDGE="vmbr0"
CPU_TYPE="host"
MACHINE_TYPE="q35"
BIOS_TYPE="ovmf"  # OVMF para Ubuntu, pero pfSense usará SeaBIOS

# Nombres de ISOs
UBUNTU_ISO="ubuntu-24.04.1-live-server-amd64.iso"
PFSENSE_ISO="pfSense-CE-2.7.2-RELEASE-amd64.iso"

# Verificar ISOs
check_isos() {
    for iso in "$UBUNTU_ISO" "$PFSENSE_ISO"; do
        if [ ! -f "${ISO_PATH}/$iso" ]; then
            echo "ERROR: Falta ISO $iso en ${ISO_PATH}/"
            exit 1
        fi
    done
}

# 1. pfSense con almacenamiento local
create_pfsense() {
  qm create 100 \
    --name pfSense \
    --memory 4096 \
    --cores 4 \
    --net0 virtio,bridge=${BRIDGE} \
    --net1 virtio,bridge=${BRIDGE} \
    --net2 virtio,bridge=${BRIDGE} \
    --scsi0 local-lvm:32 \
    --scsihw virtio-scsi-pci \
    --ostype other \
    --onboot 1 \
    --cpu ${CPU_TYPE} \
    --machine ${MACHINE_TYPE}
  
  # Usar SeaBIOS en lugar de OVMF para pfSense
  qm set 100 --bios seabios
  
  # Añadir el CD-ROM con la ISO de pfSense
  qm set 100 --ide2 local:iso/${PFSENSE_ISO},media=cdrom
  
  # Configurar orden de arranque (primero disco, luego CD-ROM)
  qm set 100 --boot order=scsi0,ide2
}

# 2. Ubuntu MySQL con almacenamiento local
create_ubuntu_mysql() {
  qm create 101 \
    --name MySQL-Server \
    --memory 32768 \
    --cores 16 \
    --net0 virtio,bridge=${BRIDGE} \
    --scsi0 local-lvm:100 \
    --scsihw virtio-scsi-pci \
    --ostype l26 \
    --onboot 1 \
    --cpu ${CPU_TYPE} \
    --machine ${MACHINE_TYPE}
  
  # Añadir disco EFI
  qm set 101 --efidisk0 local-lvm:1
  
  # Añadir disco adicional para datos
  qm set 101 --scsi1 local-lvm:500
  
  # Añadir CD-ROM con ISO de Ubuntu
  qm set 101 --ide2 local:iso/${UBUNTU_ISO},media=cdrom
  
  # Configurar BIOS y orden de arranque (primero disco, luego CD-ROM)
  qm set 101 --bios ${BIOS_TYPE}
  qm set 101 --boot order=scsi0,ide2
}

# 3. Ubuntu Apache con almacenamiento local
create_ubuntu_apache() {
  qm create 102 \
    --name Web-Server \
    --memory 16384 \
    --cores 8 \
    --net0 virtio,bridge=${BRIDGE} \
    --scsi0 local-lvm:80 \
    --scsihw virtio-scsi-pci \
    --ostype l26 \
    --onboot 1 \
    --cpu ${CPU_TYPE} \
    --machine ${MACHINE_TYPE}
  
  # Añadir disco EFI
  qm set 102 --efidisk0 local-lvm:1
  
  # Añadir disco adicional para contenido
  qm set 102 --scsi1 local-lvm:200
  
  # Añadir CD-ROM con ISO de Ubuntu
  qm set 102 --ide2 local:iso/${UBUNTU_ISO},media=cdrom
  
  # Configurar BIOS y orden de arranque (primero disco, luego CD-ROM)
  qm set 102 --bios ${BIOS_TYPE}
  qm set 102 --boot order=scsi0,ide2
}

# Main
check_isos

# Menú
echo "=== Despliegue de VMs en Proxmox ==="
echo "1) Despliegue completo"
echo "2) Solo pfSense"
echo "3) Solo MySQL"
echo "4) Solo Apache"
read -p "Selección: " choice

case $choice in
  1) create_pfsense; create_ubuntu_mysql; create_ubuntu_apache ;;
  2) create_pfsense ;;
  3) create_ubuntu_mysql ;;
  4) create_ubuntu_apache ;;
  *) echo "Opción inválida!"; exit 1 ;;
esac

# Iniciar VMs
start_vms() {
  for vm in 100 101 102; do
    if qm config $vm &>/dev/null; then
      echo -n "Iniciando VM $vm... "
      qm start $vm && echo "OK" || echo "Error"
    fi
  done
}

start_vms

echo "
Despliegue completado usando almacenamiento local
================================================
Configuración:
- Almacenamiento principal: local-lvm
- ISOs ubicadas en: ${ISO_PATH}

Instrucciones para instalación:
1. Las VMs se han iniciado con las ISOs correspondientes
2. Conectarse a la consola de cada VM a través de Proxmox para completar la instalación
3. Las máquinas están configuradas para arrancar primero desde el disco principal

Recomendaciones post-instalación:
1. Configurar los servicios correspondientes
2. Configurar backups en caso necesario
3. Verificar la conectividad de red
"
