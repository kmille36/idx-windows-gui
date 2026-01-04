{ pkgs, ... }: {
  channel = "stable-24.11";

  packages = [
    pkgs.qemu
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
          ! -name 'idx-ubuntu22-gui' \
          ! -name '.cleanup_done' \
          ! -name '.*' \
          -exec rm -rf {} + || true
        touch /home/user/.cleanup_done
      fi

      # =========================
      # Paths
      # =========================
      VM_DIR="$HOME/qemu"
      RAW_DISK="$VM_DIR/windows.raw"
      WIN_ISO="$VM_DIR/automic11.iso"
      VIRTIO_ISO="$VM_DIR/virtio-win.iso"
      NOVNC_DIR="$HOME/noVNC"

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
      # Clone noVNC if missing, else skip
      # =========================
      if [ ! -d "$NOVNC_DIR/.git" ]; then
        echo "Cloning noVNC..."
        mkdir -p "$NOVNC_DIR"
        git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"
      else
        echo "noVNC already exists, skipping clone."
      fi

      # =========================
      # Create RAW disk if missing
      # =========================
      if [ ! -f "$RAW_DISK" ]; then
        echo "Creating RAW disk..."
        qemu-img create -f raw "$RAW_DISK" 11G
      else
        echo "RAW disk already exists, skipping creation."
      fi

      # =========================
      # Start QEMU (KVM + VirtIO)
      # =========================
      echo "Starting QEMU..."
      nohup qemu-system-x86_64 \
        -enable-kvm \
        -machine type=q35,accel=kvm \
        -cpu host \
        -m 28672 \
        -smp 8 \
        \
        -drive file="$RAW_DISK",format=raw,if=none,id=vdisk \
        -device virtio-blk-pci,drive=vdisk \
        \
        -drive file="$WIN_ISO",media=cdrom,if=none,id=cd1 \
        -device ide-cd,drive=cd1,bus=ide.0 \
        \
        -drive file="$VIRTIO_ISO",media=cdrom,if=none,id=cd2 \
        -device ide-cd,drive=cd2,bus=ide.1 \
        \
        -boot order=d \
        \
        -netdev user,id=net0 \
        -device virtio-net-pci,netdev=net0 \
        \
        -device virtio-vga \
        \
        -vnc :0 \
        -display none \
        \
        > /tmp/qemu.log 2>&1 &

      # =========================
      # Start noVNC (port 8888)
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
        echo " 🌍 Windows QEMU + noVNC ready:"
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
        manager = "terminal";
        command = [ "bash" ];
      };
    };
  };
}
