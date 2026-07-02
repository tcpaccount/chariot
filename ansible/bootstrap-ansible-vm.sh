#!/usr/bin/env bash
# Recreates the chariot ansible/ directory structure and files on the
# dedicated Ansible VM. Run from the directory where you want "ansible/"
# created (e.g. your home directory).
set -euo pipefail

BASE="ansible"

mkdir -p "$BASE/inventory"
mkdir -p "$BASE/group_vars"
mkdir -p "$BASE/roles/deploy_velo/tasks"
mkdir -p "$BASE/roles/deploy_velo/defaults"

cat > "$BASE/deploy-velo.yml" <<'EOF'
- name: "Path D: Deploy Velociraptor Agent via Ansible"
  hosts: windows
  gather_facts: false
  roles:
    - deploy_velo
EOF

cat > "$BASE/rollback-velo.yml" <<'EOF'
- name: "Rollback: Remove Velociraptor Agent"
  hosts: windows
  gather_facts: false
  tasks:
    - name: Uninstall Velociraptor MSI
      ansible.windows.win_package:
        path: C:\Windows\Temp\velociraptor-client.msi
        arguments: /qn
        state: absent

    - name: Ensure service is removed
      ansible.windows.win_shell: sc.exe delete Velociraptor
      ignore_errors: true
EOF

cat > "$BASE/inventory/hosts.yml" <<'EOF'
all:
  children:
    windows:
      hosts:
        # Add target IPs on-site, one per line:
        # 192.168.1.10:
        # 192.168.1.11:
        # 192.168.1.12:
EOF

cat > "$BASE/group_vars/windows.yml" <<'EOF'
ansible_connection: winrm
ansible_winrm_transport: ntlm
ansible_winrm_port: 5985
ansible_winrm_scheme: http
ansible_winrm_server_cert_validation: ignore
EOF

cat > "$BASE/roles/deploy_velo/defaults/main.yml" <<'EOF'
msi_source: ./velociraptor-client-repacked.msi
msi_remote_path: C:\Windows\Temp\velociraptor-client.msi
velo_service_name: Velociraptor
EOF

cat > "$BASE/roles/deploy_velo/tasks/main.yml" <<'EOF'
- name: Copy repacked MSI to target
  ansible.windows.win_copy:
    src: "{{ msi_source }}"
    dest: "{{ msi_remote_path }}"

- name: Install Velociraptor agent
  ansible.windows.win_package:
    path: "{{ msi_remote_path }}"
    arguments: /qn /norestart
    state: present

- name: Ensure Velociraptor service is running
  ansible.windows.win_service:
    name: "{{ velo_service_name }}"
    state: started
    start_mode: auto

- name: Verify service status
  ansible.windows.win_service_info:
    name: "{{ velo_service_name }}"
  register: velo_service

- name: Report result
  ansible.builtin.debug:
    msg: "Velociraptor on {{ inventory_hostname }}: {{ velo_service.services[0].state }}"
EOF

echo "[+] ansible/ structure created in $(pwd)/$BASE"
echo "[!] Don't forget to copy velociraptor-client-repacked.msi into $BASE/"
