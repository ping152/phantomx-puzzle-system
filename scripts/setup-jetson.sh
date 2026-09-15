#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
machine="$(uname -m)"
tegra_release="$(cat /etc/nv_tegra_release 2>/dev/null || true)"

echo "Architecture: ${machine}"
cat /etc/os-release
python3 "${ROOT}/scripts/deployment_guard.py" --require-jetson

jetpack_version="$(dpkg-query -W -f='${Version}' nvidia-jetpack 2>/dev/null || true)"
if [[ -z "${jetpack_version}" ]]; then
  echo "JetPack package version is unknown. This script will not flash or replace the Jetson BSP." >&2
  echo "Install/confirm a supported JetPack release, then rerun setup-jetson.sh." >&2
  exit 2
fi
echo "JetPack: ${jetpack_version}"
echo "L4T: ${tegra_release}"

if ! command -v docker >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y docker.io docker-compose-v2
fi

if ! command -v nvidia-ctk >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y nvidia-container-toolkit
fi
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
sudo usermod -aG docker,video,dialout "${USER}"

if [[ -n "${CM530_USB_VENDOR_ID:-}" && -n "${CM530_USB_PRODUCT_ID:-}" ]]; then
  rule="SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"${CM530_USB_VENDOR_ID}\", ATTRS{idProduct}==\"${CM530_USB_PRODUCT_ID}\", SYMLINK+=\"phantomx-cm530\", GROUP=\"dialout\", MODE=\"0660\""
  printf '%s\n' "${rule}" | sudo tee /etc/udev/rules.d/99-phantomx-cm530.rules >/dev/null
  sudo udevadm control --reload-rules
  sudo udevadm trigger
  echo "Created /dev/phantomx-cm530 udev alias."
else
  echo "CM530_USB_VENDOR_ID/CM530_USB_PRODUCT_ID not set; fixed serial alias was not created."
  echo "Use udevadm info --attribute-walk --name=/dev/ttyUSB0 to find both IDs."
fi

if [[ ! -f "${ROOT}/.env" ]]; then
  cp "${ROOT}/.env.example" "${ROOT}/.env"
fi
git -C "${ROOT}" submodule update --init --recursive

echo "Setup complete. Log out and back in for group changes. No hardware command was sent."

