#!/bin/bash

set -e

# =========================================================
# Docker Engine + Docker Compose automated installation
#
# Supports Debian, Ubuntu and their derivatives
# (Linux Mint, Pop!_OS, Kali, Raspberry Pi OS, etc.).
#
# Optional overrides (run as root):
#   DOCKER_DISTRO=debian DOCKER_CODENAME=bookworm bash docker-install.sh
# =========================================================

echo "=========================================="
echo "Starting Docker installation"
echo "=========================================="


# =========================================================
# Detect distribution and codename
# =========================================================

DISTRO="${DOCKER_DISTRO:-}"
CODENAME="${DOCKER_CODENAME:-}"

if [ -z "${DISTRO}" ] || [ -z "${CODENAME}" ]; then

    if [ -r /etc/os-release ]; then
        . /etc/os-release
    else
        echo "ERROR: /etc/os-release not found. Cannot detect distribution."
        exit 1
    fi

fi

if [ -z "${DISTRO}" ]; then

    # ID_LIKE lists the parent distro(s), e.g. Mint reports
    # "debian ubuntu", Kali reports "debian". Ubuntu-based
    # derivatives are matched first so they use Docker's
    # Ubuntu repository.
    case "${ID:-} ${ID_LIKE:-}" in
        *raspbian*) DISTRO="raspbian" ;;
        *ubuntu*)   DISTRO="ubuntu" ;;
        *debian*)   DISTRO="debian" ;;
        *)
            echo "ERROR: Unsupported distribution '${PRETTY_NAME:-${ID:-unknown}}'."
            echo "This script supports Debian, Ubuntu and their derivatives."
            exit 1
            ;;
    esac

fi

if [ -z "${CODENAME}" ]; then

    case "${DISTRO}" in
        ubuntu)
            # Derivatives of Ubuntu publish the codename of the
            # Ubuntu release they are based on.
            CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
            ;;
        debian|raspbian)
            CODENAME="${VERSION_CODENAME:-}"
            ;;
    esac

fi


# ---------------------------------------------------------
# Resolve the codename to a suite published by Docker
# ---------------------------------------------------------

DEBIAN_SUITES="bullseye bookworm trixie forky"

if [ "${DISTRO}" = "debian" ] || [ "${DISTRO}" = "raspbian" ]; then

    case " ${DEBIAN_SUITES} " in
        *" ${CODENAME} "*) ;;   # already a valid suite
        *)
            # Rolling derivatives report non-standard codenames
            # (e.g. Kali's "kali-rolling"); derive the parent
            # Debian suite from /etc/debian_version instead.
            if [ -r /etc/debian_version ]; then
                dv="$(head -n 1 /etc/debian_version)"
                dv="${dv%%/*}"

                case "${dv}" in
                    bullseye|11*) CODENAME="bullseye" ;;
                    bookworm|12*) CODENAME="bookworm" ;;
                    trixie|13*)   CODENAME="trixie" ;;
                    forky|14*)    CODENAME="forky" ;;
                    *)            CODENAME="" ;;
                esac
            else
                CODENAME=""
            fi
            ;;
    esac

fi

if [ -z "${DISTRO}" ] || [ -z "${CODENAME}" ]; then
    echo "ERROR: Could not determine the Docker repository suite for this system."
    echo "Set it manually and re-run, e.g.:"
    echo "  DOCKER_DISTRO=debian DOCKER_CODENAME=bookworm bash $0"
    exit 1
fi

echo "Detected distribution: ${DISTRO} (${CODENAME})"


# =========================================================
# Ensure script runs as root
# =========================================================

if [ "$EUID" -ne 0 ]; then
    echo "Root privileges required."
    echo "Re-running script with sudo..."
    exec sudo DOCKER_DISTRO="${DISTRO}" DOCKER_CODENAME="${CODENAME}" bash "$0" "$@"
fi


# =========================================================
# Update package repositories
# =========================================================

echo ""
echo "Updating package repositories..."

apt-get update


# =========================================================
# Install prerequisites
# =========================================================

echo ""
echo "Installing prerequisites..."

apt-get install -y \
    ca-certificates \
    curl


# =========================================================
# Install Docker
# =========================================================

echo ""
echo "Installing Docker..."


# Remove conflicting packages if they exist.
apt-get remove -y \
    docker.io \
    docker-compose \
    docker-doc \
    podman-docker \
    containerd \
    runc 2>/dev/null || true


# ---------------------------------------------------------
# Add Docker GPG key
# ---------------------------------------------------------

install -m 0755 -d /etc/apt/keyrings

curl -fsSL \
    "https://download.docker.com/linux/${DISTRO}/gpg" \
    -o /etc/apt/keyrings/docker.asc

chmod a+r /etc/apt/keyrings/docker.asc


# ---------------------------------------------------------
# Add Docker repository
# ---------------------------------------------------------

tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/${DISTRO}
Suites: ${CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF


# ---------------------------------------------------------
# Install Docker Engine + Compose
# ---------------------------------------------------------

apt-get update

apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin


# =========================================================
# Start Docker
# =========================================================

echo ""
echo "Starting Docker..."

if [ -d /run/systemd/system ]; then
    systemctl enable docker
    systemctl start docker
else
    # Non-systemd systems (e.g. Devuan).
    service docker start || service docker restart || true
fi


# Wait for the Docker daemon to come up.

for _ in {1..30}; do
    if docker info > /dev/null 2>&1; then
        break
    fi
    sleep 1
done

if ! docker info > /dev/null 2>&1; then

    echo "ERROR: Docker failed to start."

    if [ -d /run/systemd/system ]; then
        systemctl status docker --no-pager || true
    else
        service docker status || true
    fi

    exit 1

fi

echo "Docker is running."

docker compose version
echo "Docker Compose is available."


# =========================================================
# Add invoking user to Docker group
# =========================================================

echo ""
echo "Configuring Docker permissions..."

if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    TARGET_USER="${SUDO_USER}"
elif [ "$(id -un)" != "root" ]; then
    TARGET_USER="$(id -un)"
else
    TARGET_USER=""
fi

if [ -n "${TARGET_USER}" ]; then

    if ! getent group docker > /dev/null 2>&1; then
        groupadd docker
    fi

    usermod -aG docker "${TARGET_USER}"

    echo "User ${TARGET_USER} added to Docker group (log out and back in to apply)."

else
    echo "Running as root; skipping Docker group configuration."
fi


echo "=========================================="
echo "Setup completed successfully."
echo "=========================================="
