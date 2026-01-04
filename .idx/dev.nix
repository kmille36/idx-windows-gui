{ pkgs, ... }: {
  channel = "stable-24.11";

  packages = [
    pkgs.qemu
    pkgs.OVMF
    pkgs.htop
    pkgs.cloudflared
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.wget
    pkgs.git
    pkgs.python3
  ];

  idx.workspace.onStart = {
    qemu = ''
      set -e

      # =========================
      # One-time cleanup
      # =========================
      if [ ! -f /home/user/.cleanup_done ]; then
        rm -rf /home/user/.gradle/* /home/user/.emu/* || true
        find /home/user -mindepth 1 -maxdepth 1 \
          ! -name 'idx-windows-gui' \
          ! -name '.cleanup_done' \
          ! -name '.*' \
          -exec rm -rf {} + || true
        touch /home/user/.cleanup_done
      fi

      # =========================
      # Paths
      # =========================
      VM_DIR="$HOME/qemu"
      RAW_DISK="$VM_DIR/windows.qcow2"
      WIN_ISO="$VM_DIR/automic11.iso"
      VIRTIO_ISO="$VM_DIR/virtio-win.iso"
      NOVNC_DIR="$HOME/noVNC"

      OVMF_CODE="${pkgs.ovmf}/share/OVMF/OVMF_CODE.fd"
      OVMF_VARS="${pkgs.ovmf}/share/OVMF/OVMF_VARS.fd"

      mkdir -p "$VM_DIR"

      # =========================
      # Download Windows ISO if missing
      # =========================
      if [ ! -f "$WIN_ISO" ]; then
        echo "Downloading Windows ISO..."
        wget -O "$WIN_ISO" \
          https://github.com/kmille36/idx-windows-gui/releases/download/1.0/automic11.iso
      else
        echo "Windows ISO already exists, skipping download."
      fi

      # =========================
      # Download VirtIO drivers ISO if missing
      # =========================
      if [ ! -f "$VIRTIO_ISO" ]; then
        echo "Downloading VirtIO drivers ISO..."
        wget -O "$VIRTIO_ISO" \
          https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.271-1/virtio-win.iso
      else
        echo "VirtIO ISO already exists, skipping download."
      fi

      # =========================
      # Clone noVNC if missing
      # =========================
      if [ ! -d "$NOVNC_DIR/.git" ]; then
        echo "Cloning noVNC..."
        mkdir -p "$NOVNC_DIR"
        git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"
      else
        echo "noVNC already exists, skipping clone."
      fi

      # =========================
      # Create QCOW2 disk if missing
      # =========================
      if [ ! -f "$RAW_DISK" ]; then
        echo "Creating QCOW2 disk..."
        qemu-img create -f qcow2 "$RAW_DISK" 11G
      else
        echo "QCOW2 disk already exists, skipping creation."
      fi

      # =========================
      # Start QEMU (KVM + VirtIO + UEFI)
      # =========================
      echo "Starting QEMU..."
      nohup qemu-system-x86_64 \
        -enable-kvm \
        -machine type=q35,accel=kvm \
        -cpu host \
        -m 28672 \
        -smp 8 \
        \
        # UEFI firmware
        -drive if=pflash,format=raw,readonly=on,file=$OVMF_CODE \
        -drive if=pflash,format=raw,file=$OVMF_VARS \
        \
        # VirtIO disk
        -drive file="$RAW_DISK",format=qcow2,if=virtio,id=vdisk \
        -device virtio-blk-pci,drive=vdisk \
        \
        # Windows ISO + VirtIO ISO as virtio CD-ROM
        -drive file="$WIN_ISO",media=cdrom,if=virtio,id=cd1 \
        -drive file="$VIRTIO_ISO",media=cdrom,if=virtio,id=cd2 \
        \
        # Boot menu enabled
        -boot menu=on,order=cd \
        \
        # Networking
        -netdev user,id=net0 \
        -device virtio-net-pci,netdev=net0 \
        \
        # Video
        -device virtio-vga \
        \
        # VNC for noVNC
        -vnc :0 \
        -display none \
        \
        > /tmp/qemu.log 2>&1 &

      # =========================
      # Start noVNC on port 8888
      # =========================
      echo "Starting noVNC..."
      nohup "$NOVNC_DIR/utils/novnc_proxy" \
        --vnc 127.0.0.1:5900 \
        --listen 8888 \
        > /tmp/novnc.log 2>&1 &

      # =========================
      # Start Cloudflared tunnel
      # =========================
      echo "Starting Cloudflared tunnel..."
      nohup cloudflared tunnel \
        --no-autoupdate \
        --url http://localhost:8888 \
        > /tmp/cloudflared.log 2>&1 &

      sleep 10

      if grep -q "trycloudflare.com" /tmp/cloudflared.log; then
        URL=$(grep -o "https://[a-z0-9.-]*trycloudflare.com" /tmp/cloudflared.log | head -n1)
        echo "========================================="
        echo " 🌍 Windows 11 QEMU + noVNC ready:"
        echo "     $URL/vnc.html"
        echo "========================================="
      else
        echo "❌ Cloudflared tunnel failed"
      fi

      # =========================
      # Keep workspace alive
      # =========================
      elapsed=0
      while true; do
        echo "Time elapsed: $elapsed min"
        ((elapsed++))
        sleep 60
      done
    '';
  };

  idx.previews = {
    enable = true;
    previews = {
      qemu = {
        manager = "web";
        command = [
          "bash" "-lc"
          "echo 'noVNC running on port 8888'"
        ];
      };
      terminal = {
        manager = "web";
        command = [ "bash" ];
      };
    };
  };
}
