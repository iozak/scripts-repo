#!/bin/bash

set -e

# =========================================================
# Git + repository cloning automated setup
#
# Installs git via apt (works on Debian, Ubuntu and all
# their derivatives -- git lives in every base repo, so no
# special repository setup is needed) and clones the target
# repository into the VM user's tools directory.
#
# Optional: pass a repository URL as the first argument:
#   bash git-setup.sh https://github.com/user/repo.git
# =========================================================

VM_USER="iozak"

# Repository to clone (overridable via first argument).
REPO_URL="${1:-https://github.com/iozak/scripts-repo.git}"

TOOLS_DIR="/home/${VM_USER}/tools"
REPO_DIR="${TOOLS_DIR}/$(basename "${REPO_URL}" .git)"

echo "=========================================="
echo "Starting git and repository setup"
echo "=========================================="


# =========================================================
# Ensure script runs as root
# =========================================================

if [ "$EUID" -ne 0 ]; then
    echo "Root privileges required."
    echo "Re-running script with sudo..."
    exec sudo bash "$0" "$@"
fi


# =========================================================
# Verify the VM user exists
# =========================================================

if ! id "${VM_USER}" > /dev/null 2>&1; then
    echo "ERROR: User ${VM_USER} does not exist."
    exit 1
fi


# =========================================================
# Update package repositories
# =========================================================

echo ""
echo "Updating package repositories..."

apt-get update


# =========================================================
# Install git
# =========================================================

echo ""
echo "Installing git..."

if command -v git > /dev/null 2>&1; then
    echo "git is already installed: $(git --version)"
else
    apt-get install -y git
fi


# =========================================================
# Create tools directory
# =========================================================

echo ""
echo "Creating tools directory..."

mkdir -p "${TOOLS_DIR}"

chown -R "${VM_USER}:${VM_USER}" "${TOOLS_DIR}"


# =========================================================
# Clone the repository
# =========================================================

echo ""
echo "Cloning repository..."

cd "${TOOLS_DIR}"

if [ ! -d "${REPO_DIR}" ]; then

    sudo -u "${VM_USER}" git clone "${REPO_URL}" "${REPO_DIR}"

else

    echo "Repository already exists at ${REPO_DIR}."

fi

echo "=========================================="
echo "Setup completed successfully."
echo "=========================================="
