#!/usr/bin/env bash
# Install all host-level requirements for light.
#
# Supported OS:  Arch Linux, Manjaro, Ubuntu, Debian
# Installs:      Docker, VirtualBox, Vagrant, Terraform, Ansible, Python 3, netcat
#
# Usage (via startup.sh):
#   ./startup.sh --install-requirements
#
# Or directly:
#   sudo ./scripts/install-requirements.sh

set -euo pipefail

LIGHT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${LIGHT_ROOT}/lib/logging.sh"

# Run package manager commands as root.
# If already root, no prefix needed; otherwise use sudo.
if [[ "$(id -u)" -eq 0 ]]; then
    SUDO=""
    # When invoked via "sudo ./startup.sh --install-requirements", SUDO_USER is set
    INSTALL_USER="${SUDO_USER:-root}"
else
    SUDO="sudo"
    INSTALL_USER="${USER}"
fi


# ── OS detection ──────────────────────────────────────────────────────────────

detect_os() {
    [[ -f /etc/os-release ]] || log::die "Cannot detect OS: /etc/os-release not found"
    # shellcheck source=/dev/null
    source /etc/os-release
    PRETTY_NAME="${PRETTY_NAME:-${ID}}"
    OS_CODENAME="${VERSION_CODENAME:-}"

    case "${ID:-}" in
        arch)    DISTRO="arch"   ;;
        manjaro) DISTRO="manjaro" ;;
        ubuntu)  DISTRO="ubuntu" ; [[ -n "${OS_CODENAME}" ]] || log::die "Cannot detect Ubuntu codename" ;;
        debian)  DISTRO="debian" ; [[ -n "${OS_CODENAME}" ]] || log::die "Cannot detect Debian codename" ;;
        *)
            # Catch Arch-based distros that set ID_LIKE=arch
            if [[ "${ID_LIKE:-}" == *"arch"* ]]; then
                DISTRO="arch"
            else
                log::die "Unsupported OS: ${PRETTY_NAME}. Supported: Arch, Manjaro, Ubuntu, Debian"
            fi
            ;;
    esac

    log::info "Detected: ${PRETTY_NAME}"
}


# ── Arch / Manjaro ────────────────────────────────────────────────────────────

install_arch() {
    log::section "Installing requirements (${PRETTY_NAME})"

    log::info "Updating package database"
    $SUDO pacman -Sy --noconfirm

    log::info "Installing base tools"
    $SUDO pacman -S --noconfirm --needed \
        curl wget git python python-pip jq openbsd-netcat openssh

    _install_docker_arch
    _install_virtualbox_arch
    _install_vagrant_arch
    _install_terraform_arch
    _install_ansible_arch
}

_install_docker_arch() {
    if command -v docker &>/dev/null; then
        log::ok "Docker already installed: $(docker --version | head -1)"
        return
    fi
    log::info "Installing Docker"
    $SUDO pacman -S --noconfirm --needed docker docker-compose
    $SUDO systemctl enable --now docker
    $SUDO usermod -aG docker "${INSTALL_USER}"
    log::ok "Docker installed — log out and back in for group to take effect"
}

_install_virtualbox_arch() {
    if command -v VBoxManage &>/dev/null; then
        log::ok "VirtualBox already installed: $(VBoxManage --version)"
        return
    fi
    log::info "Installing VirtualBox"

    # virtualbox-host-dkms builds kernel modules for any kernel variant.
    # On Manjaro, mhwd handles kernel headers — prompt the user if needed.
    $SUDO pacman -S --noconfirm --needed virtualbox virtualbox-host-dkms

    if [[ "${DISTRO}" == "manjaro" ]]; then
        # Manjaro needs the headers for the running kernel (managed by mhwd)
        local kernel_ver
        kernel_ver="$(uname -r | grep -oP '^\d+\.\d+')"
        local header_pkg="linux$(echo "${kernel_ver}" | tr -d '.')-headers"
        if $SUDO pacman -Si "${header_pkg}" &>/dev/null; then
            $SUDO pacman -S --noconfirm --needed "${header_pkg}"
        else
            log::warn "Kernel headers package '${header_pkg}' not found."
            log::warn "Run: sudo mhwd-kernel -i linux$(echo "${kernel_ver}" | tr -d '.') headers"
        fi
    else
        # Standard Arch: linux-headers covers the default kernel
        $SUDO pacman -S --noconfirm --needed linux-headers
    fi

    $SUDO modprobe vboxdrv 2>/dev/null \
        || log::warn "modprobe vboxdrv failed — a reboot may be needed to load VirtualBox modules"
    log::ok "VirtualBox installed"
}

_install_vagrant_arch() {
    if command -v vagrant &>/dev/null; then
        log::ok "Vagrant already installed: $(vagrant --version)"
        return
    fi
    log::info "Installing Vagrant"

    # Vagrant is in the AUR; use any available AUR helper.
    local aur_helper=""
    for h in yay paru pikaur; do
        command -v "${h}" &>/dev/null && aur_helper="${h}" && break
    done

    if [[ -n "${aur_helper}" ]]; then
        log::info "Using AUR helper: ${aur_helper}"
        # AUR helpers must not be run as root
        if [[ "${INSTALL_USER}" == "root" ]]; then
            log::die "AUR helpers cannot run as root. Run startup.sh as a normal user with sudo access."
        fi
        sudo -u "${INSTALL_USER}" "${aur_helper}" -S --noconfirm vagrant
    else
        log::warn "No AUR helper (yay/paru/pikaur) found — installing Vagrant binary from HashiCorp"
        _install_vagrant_binary
    fi
    log::ok "Vagrant installed: $(vagrant --version)"
}

_install_vagrant_binary() {
    local ver
    ver=$(curl -fsSL "https://checkpoint-api.hashicorp.com/v1/check/vagrant" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['current_version'])")
    local url="https://releases.hashicorp.com/vagrant/${ver}/vagrant_${ver}_linux_amd64.zip"
    log::info "Downloading Vagrant ${ver}"
    curl -fsSL "${url}" -o /tmp/vagrant.zip
    $SUDO unzip -o /tmp/vagrant.zip -d /usr/local/bin vagrant
    $SUDO chmod +x /usr/local/bin/vagrant
    rm -f /tmp/vagrant.zip
}

_install_terraform_arch() {
    if command -v terraform &>/dev/null; then
        log::ok "Terraform already installed: $(terraform version | head -1)"
        return
    fi
    log::info "Installing Terraform"
    $SUDO pacman -S --noconfirm --needed terraform
    log::ok "Terraform installed: $(terraform version | head -1)"
}

_install_ansible_arch() {
    if command -v ansible &>/dev/null; then
        log::ok "Ansible already installed: $(ansible --version | head -1)"
        return
    fi
    log::info "Installing Ansible"
    $SUDO pacman -S --noconfirm --needed ansible
    log::ok "Ansible installed: $(ansible --version | head -1)"
}


# ── Ubuntu / Debian ───────────────────────────────────────────────────────────

install_deb() {
    log::section "Installing requirements (${PRETTY_NAME})"

    log::info "Updating package index"
    $SUDO apt-get update -qq

    log::info "Installing base tools"
    $SUDO apt-get install -y --no-install-recommends \
        curl wget git python3 python3-pip jq netcat-openbsd openssh-client \
        ca-certificates gnupg lsb-release apt-transport-https unzip

    _install_docker_deb
    _install_virtualbox_deb
    _install_hashicorp_deb     # Vagrant + Terraform via HashiCorp apt repo
    _install_ansible_deb
}

_add_apt_key() {
    local name="${1:?}" url="${2:?}"
    local keyfile="/etc/apt/keyrings/${name}.gpg"
    $SUDO install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "${url}" | $SUDO gpg --dearmor --yes -o "${keyfile}"
    $SUDO chmod a+r "${keyfile}"
    echo "${keyfile}"
}

_install_docker_deb() {
    if command -v docker &>/dev/null; then
        log::ok "Docker already installed: $(docker --version | head -1)"
    else
        log::info "Adding Docker apt repository"
        local keyfile
        keyfile=$(_add_apt_key "docker" \
            "https://download.docker.com/linux/${DISTRO}/gpg")
        printf 'deb [arch=%s signed-by=%s] https://download.docker.com/linux/%s %s stable\n' \
            "$(dpkg --print-architecture)" "${keyfile}" "${DISTRO}" "${OS_CODENAME}" \
            | $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null
        $SUDO apt-get update -qq
        $SUDO apt-get install -y \
            docker-ce docker-ce-cli containerd.io \
            docker-buildx-plugin docker-compose-plugin
    fi
    $SUDO systemctl enable --now docker
    $SUDO usermod -aG docker "${INSTALL_USER}"
    log::ok "Docker installed — log out and back in for group to take effect"
}

_install_virtualbox_deb() {
    if command -v VBoxManage &>/dev/null; then
        log::ok "VirtualBox already installed: $(VBoxManage --version)"
        return
    fi
    log::info "Adding VirtualBox apt repository"
    local keyfile
    keyfile=$(_add_apt_key "virtualbox" \
        "https://www.virtualbox.org/download/oracle_vbox_2016.asc")
    printf 'deb [arch=amd64 signed-by=%s] https://download.virtualbox.org/virtualbox/debian %s contrib\n' \
        "${keyfile}" "${OS_CODENAME}" \
        | $SUDO tee /etc/apt/sources.list.d/virtualbox.list > /dev/null
    $SUDO apt-get update -qq
    # Try 7.0; fall back to the latest available series if not in the repo
    if $SUDO apt-get install -y virtualbox-7.0 2>/dev/null; then
        log::ok "VirtualBox 7.0 installed"
    else
        log::warn "virtualbox-7.0 not available for ${OS_CODENAME} — trying virtualbox-6.1"
        $SUDO apt-get install -y virtualbox-6.1
        log::ok "VirtualBox 6.1 installed"
    fi
}

_install_hashicorp_deb() {
    log::info "Adding HashiCorp apt repository (Vagrant + Terraform)"
    local keyfile
    keyfile=$(_add_apt_key "hashicorp" "https://apt.releases.hashicorp.com/gpg")
    printf 'deb [arch=%s signed-by=%s] https://apt.releases.hashicorp.com %s main\n' \
        "$(dpkg --print-architecture)" "${keyfile}" "${OS_CODENAME}" \
        | $SUDO tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
    $SUDO apt-get update -qq

    if ! command -v vagrant &>/dev/null; then
        $SUDO apt-get install -y vagrant
        log::ok "Vagrant installed: $(vagrant --version)"
    else
        log::ok "Vagrant already installed: $(vagrant --version)"
    fi

    if ! command -v terraform &>/dev/null; then
        $SUDO apt-get install -y terraform
        log::ok "Terraform installed: $(terraform version | head -1)"
    else
        log::ok "Terraform already installed: $(terraform version | head -1)"
    fi
}

_install_ansible_deb() {
    if command -v ansible &>/dev/null; then
        log::ok "Ansible already installed: $(ansible --version | head -1)"
        return
    fi
    log::info "Installing Ansible"
    if [[ "${DISTRO}" == "ubuntu" ]]; then
        # The ubuntu universe package is often too old; use the official PPA
        $SUDO apt-get install -y --no-install-recommends software-properties-common
        $SUDO add-apt-repository --yes --update ppa:ansible/ansible
    fi
    $SUDO apt-get install -y ansible
    log::ok "Ansible installed: $(ansible --version | head -1)"
}


# ── Post-install notes ────────────────────────────────────────────────────────

post_install_notes() {
    log::section "Requirements installed"
    log::ok "All tools are ready"
    log::info ""
    log::info "  Next steps:"
    log::info ""
    log::info "  1. Log out and back in (or run 'newgrp docker') so the docker"
    log::info "     group takes effect without restarting your session"
    log::info ""
    log::info "  2. Reboot if VirtualBox kernel modules were just installed"
    log::info "     (required before 'vagrant up' will work)"
    log::info ""
    log::info "  3. Set up your config:"
    log::info "       cp config/light.env.example config/light.env"
    log::info "       \$EDITOR config/light.env"
    log::info ""
    log::info "  4. Declare your service bubbles:"
    log::info "       \$EDITOR config/topology.json"
    log::info ""
    log::info "  5. Start:"
    log::info "       ./startup.sh dev"
}


# ── Main ──────────────────────────────────────────────────────────────────────

detect_os
case "${DISTRO}" in
    arch|manjaro) install_arch ;;
    ubuntu|debian) install_deb ;;
esac
post_install_notes
