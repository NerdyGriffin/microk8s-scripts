# Ansible Architecture Decision: Single vs Multiple Controllers

## Your Infrastructure Overview

Based on your description:

```
Infrastructure Inventory:
├── Kubernetes Cluster (MicroK8s)
│   ├── 6 Linux nodes (Ubuntu)
│   └── Growing workload
├── Bare-Metal Servers
│   ├── 2 Windows nodes (Hyper-V hypervisors)
│   └── 1 Linux server (File server + KVM host)
└── VM Deployments (Growing)
    ├── KVM VMs (on Linux host)
    ├── Hyper-V VMs (on Windows hosts)
    └── Additional VMs expected over time
```

**Management Domains:**
1. **Kubernetes Operations** - MicroK8s cluster lifecycle, addons, repairs
2. **Bare-Metal Server Management** - OS updates, configuration, monitoring
3. **VM Lifecycle Management** - Create, destroy, snapshot, migrate VMs
4. **Hypervisor Management** - Hyper-V and KVM host configuration

---

## Architecture Option 1: Single Unified Controller ⭐ RECOMMENDED

### Overview
One Ansible controller managing all infrastructure with organized separation via:
- Directory structure (separate playbooks/roles per domain)
- Multiple inventory files (or groups within one inventory)
- Different credentials/vault files per domain
- Execution environments or Python venvs per use case

### Topology
```
┌─────────────────────────────────────────────────────────────────┐
│                    Unified Ansible Controller                    │
│                  (Single VM: 8 vCPU, 16GB RAM)                  │
│                                                                  │
│  /etc/ansible/                                                  │
│  ├── ansible.cfg (global settings)                             │
│  ├── inventories/                                              │
│  │   ├── kubernetes/                                           │
│  │   │   ├── hosts.yml (6 K8s nodes)                          │
│  │   │   └── group_vars/                                       │
│  │   ├── baremetal/                                            │
│  │   │   ├── hosts.yml (3 hypervisor hosts)                   │
│  │   │   └── group_vars/                                       │
│  │   └── virtual_machines/                                     │
│  │       ├── hosts.yml (dynamic VMs)                           │
│  │       └── group_vars/                                       │
│  ├── playbooks/                                                │
│  │   ├── kubernetes/                                           │
│  │   │   ├── restart_microk8s.yml                             │
│  │   │   ├── upgrade_microk8s.yml                             │
│  │   │   └── repair_database.yml                              │
│  │   ├── baremetal/                                            │
│  │   │   ├── os_updates.yml                                   │
│  │   │   ├── security_hardening.yml                           │
│  │   │   └── hypervisor_config.yml                            │
│  │   └── vms/                                                  │
│  │       ├── create_vm.yml                                     │
│  │       ├── snapshot_all.yml                                  │
│  │       └── cleanup_old_vms.yml                              │
│  └── roles/                                                    │
│      ├── microk8s_common/                                      │
│      ├── windows_hyperv/                                       │
│      ├── kvm_management/                                       │
│      └── common_baseline/                                      │
└──────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
   ┌────▼────┐           ┌────▼────┐          ┌────▼────┐
   │   K8s   │           │ Bare    │          │   VMs   │
   │ Cluster │           │ Metal   │          │ (Dynamic)│
   │6 nodes  │           │3 hosts  │          │ Growing │
   └─────────┘           └─────────┘          └─────────┘
```

### Advantages ✅

**1. Unified Workflow & Single Source of Truth**
- One place to manage ALL infrastructure
- Consistent tooling and patterns across all domains
- Single codebase to version control
- One CI/CD pipeline for infrastructure-as-code

**2. Cross-Domain Orchestration**
- Deploy VM → Join to K8s cluster → Configure ingress (one playbook)
- Backup bare-metal host → Snapshot VMs → Backup K8s data (coordinated)
- Security patch bare-metal → Migrate VMs → Patch K8s nodes (orchestrated sequence)

**3. Operational Efficiency**
- Learn one Ansible installation/configuration
- Single jump host/bastion integration
- Shared roles (monitoring, security, logging)
- One place to manage secrets (Ansible Vault)
- Unified reporting and logging

**4. Resource Optimization**
- One controller VM to maintain (not 3)
- Shared Python dependencies
- Consolidated backup of automation code
- Reduced licensing costs (if using AWX/Tower)

**5. Better for Growing Infrastructure**
- Easy to add new VM inventory dynamically
- Natural scaling as VMs increase
- Can add execution environments per domain without new hardware
- Future-proof for additional infrastructure types

**6. Team Collaboration**
- One repository for infrastructure team
- Easier code reviews and knowledge sharing
- Consistent standards across domains
- Simpler onboarding for new team members

### Challenges & Mitigations ⚠️

| Challenge | Mitigation Strategy |
|-----------|---------------------|
| **Complexity in one place** | Clear directory structure, documentation, naming conventions |
| **Dependency conflicts** (e.g., K8s module vs WinRM) | Use Python virtual environments or Ansible execution environments |
| **Blast radius of mistakes** | Use `--check` mode, staging environment, branch protection in git |
| **Controller downtime affects all** | High availability setup (see below), frequent backups, documented recovery |
| **Different credential management** | Separate vault files per domain, use `ansible-vault` encryption |
| **Performance with many hosts** | Use `strategy: free`, parallelism tuning, fact caching |

### Implementation Structure

**Directory Layout:**
```
/opt/ansible/
├── ansible.cfg
├── inventories/
│   ├── production/
│   │   ├── kubernetes.yml          # 6 K8s nodes
│   │   ├── baremetal.yml          # 3 hypervisor hosts
│   │   ├── vms.yml                # VM inventory (could be dynamic)
│   │   └── group_vars/
│   │       ├── all.yml            # Global settings
│   │       ├── kubernetes.yml     # K8s-specific vars
│   │       ├── windows.yml        # Windows-specific vars
│   │       ├── linux_baremetal.yml
│   │       └── virtual_machines.yml
│   └── staging/
│       └── (similar structure)
├── playbooks/
│   ├── kubernetes/
│   │   ├── lifecycle/
│   │   ├── maintenance/
│   │   └── monitoring/
│   ├── baremetal/
│   │   ├── windows/
│   │   └── linux/
│   ├── vms/
│   │   ├── kvm/
│   │   └── hyperv/
│   └── orchestration/             # Cross-domain playbooks
│       ├── full_stack_backup.yml
│       ├── disaster_recovery.yml
│       └── provision_new_k8s_node.yml
├── roles/
│   ├── common/
│   │   ├── baseline_security/
│   │   ├── monitoring_agent/
│   │   └── logging_agent/
│   ├── kubernetes/
│   │   ├── microk8s_install/
│   │   ├── microk8s_upgrade/
│   │   └── microk8s_backup/
│   ├── hypervisor/
│   │   ├── kvm_host/
│   │   └── hyperv_host/
│   └── virtual_machine/
│       ├── kvm_guest/
│       └── hyperv_guest/
├── library/
│   └── custom_modules/
├── filter_plugins/
├── vaults/
│   ├── kubernetes.yml             # Encrypted K8s secrets
│   ├── windows.yml                # Encrypted Windows creds
│   └── vm_templates.yml           # Encrypted SSH keys, API tokens
└── docs/
    ├── runbooks/
    └── architecture/
```

**Sample ansible.cfg for multi-domain:**
```ini
[defaults]
inventory = ./inventories/production/
roles_path = ./roles
library = ./library
filter_plugins = ./filter_plugins
remote_user = ansible
host_key_checking = False
retry_files_enabled = False
gathering = smart
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts
fact_caching_timeout = 7200
stdout_callback = yaml
callbacks_enabled = profile_tasks, timer
forks = 20
timeout = 30

[inventory]
enable_plugins = yaml, ini, host_list, script, auto

[privilege_escalation]
become = True
become_method = sudo
become_user = root

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=3600s
pipelining = True
control_path = /tmp/ansible-ssh-%%h-%%p-%%r
```

**Sample Cross-Domain Playbook:**
```yaml
# playbooks/orchestration/provision_new_k8s_node.yml
---
- name: Provision new VM for Kubernetes
  hosts: localhost
  gather_facts: no
  tasks:
    - name: Create VM on KVM host
      include_role:
        name: virtual_machine/kvm_guest
      vars:
        vm_name: "kube-07"
        vm_memory: 16384
        vm_vcpus: 4
        vm_disk: 100G

    - name: Add new VM to inventory
      add_host:
        name: "kube-07.local.lan"
        groups: microk8s_cluster,worker_nodes
        ansible_host: "{{ vm_ip_address }}"

- name: Configure base OS
  hosts: kube-07.local.lan
  roles:
    - common/baseline_security
    - common/monitoring_agent

- name: Install and join MicroK8s cluster
  hosts: kube-07.local.lan
  roles:
    - kubernetes/microk8s_install
    - kubernetes/microk8s_join_cluster

- name: Update load balancer
  hosts: baremetal
  tasks:
    - name: Add new node to HAProxy config
      # ... tasks to update LB ...
```

---

## Architecture Option 2: Multiple Specialized Controllers

### Overview
Separate Ansible controllers for each domain:
- **Controller A**: Kubernetes operations only
- **Controller B**: Bare-metal server management
- **Controller C**: VM lifecycle management

### Topology
```
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│  K8s Controller  │  │Baremetal Control.│  │  VM Controller   │
│  (Small VM)      │  │  (Small VM)      │  │  (Small VM)      │
└────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘
         │                     │                     │
         │                     │                     │
    ┌────▼────┐           ┌────▼────┐          ┌────▼────┐
    │   K8s   │           │ Bare    │          │   VMs   │
    │ Cluster │           │ Metal   │          │         │
    │6 nodes  │           │3 hosts  │          │         │
    └─────────┘           └─────────┘          └─────────┘
```

### Advantages ✅

**1. Domain Isolation**
- Failures in K8s automation don't affect VM management
- Each controller can have domain-specific tooling
- Security: separate credentials per domain

**2. Specialized Configuration**
- K8s controller: optimized for kubectl, helm integration
- VM controller: focused on libvirt/Hyper-V APIs
- Bare-metal: different privilege levels, connection methods

**3. Team Separation**
- Different teams can own different controllers
- Easier to delegate responsibilities
- Independent upgrade cycles

### Disadvantages ❌

**1. Operational Overhead**
- 3x the controller VMs to maintain
- 3x the Ansible installations to upgrade
- 3x the backup/monitoring configurations
- 3x the potential failure points

**2. No Cross-Domain Orchestration**
- Cannot easily coordinate operations across domains
- Manual handoffs between systems
- Duplicate roles/playbooks (monitoring, security)

**3. Inconsistency Risk**
- Different Ansible versions across controllers
- Divergent coding standards
- Fragmented documentation

**4. Resource Waste**
- Each controller needs CPU/RAM/storage
- Idle resources when not running playbooks
- Higher licensing costs (AWX/Tower)

**5. Complexity for Growing Infrastructure**
- Which controller manages a VM that joins K8s?
- How to coordinate backups across all three?
- More complex disaster recovery

---

## Architecture Option 3: Hybrid (Single Controller + Execution Environments)

### Overview
Single Ansible controller using **Execution Environments** (containerized runtimes) for domain isolation.

### Topology
```
┌─────────────────────────────────────────────────────────────────┐
│              Ansible Controller (with AWX/Tower)                 │
│                                                                  │
│  Execution Environments (Containers):                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │ K8s EE       │  │ Windows EE   │  │ VM Mgmt EE   │         │
│  │ - kubectl    │  │ - pywinrm    │  │ - libvirt    │         │
│  │ - helm       │  │ - PowerShell │  │ - pyvmomi    │         │
│  │ - k8s module │  │ - AD modules │  │ - hyperv API │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
└─────────────────────────────────────────────────────────────────┘
```

### Best of Both Worlds ✅

- Single controller (operational efficiency)
- Domain isolation (dependency conflicts solved)
- Clean separation without multiple VMs
- Requires Ansible 2.15+ or AWX/Tower

### When to Consider This
- If you adopt AWX/Ansible Tower
- Team grows beyond 2-3 people
- Need strict dependency isolation
- Want CI/CD integration with container-based execution

---

## Recommendation for Your Situation

### ⭐ **Use Option 1: Single Unified Controller**

**Why this is the best choice for you:**

1. **Small-to-Medium Scale (9 hosts currently)**
   - 6 K8s nodes + 3 bare-metal hosts = manageable from one controller
   - Even with VM growth, likely <50 total managed endpoints
   - Not enough scale to justify multi-controller overhead

2. **You're Starting Fresh with Ansible**
   - Simpler to learn and maintain one system
   - Build good practices in one place
   - Expand complexity only when needed

3. **Cross-Domain Operations Will Be Valuable**
   - Example: Create VM → Configure → Add to K8s cluster
   - Example: Backup sequence: Bare-metal → VMs → K8s data
   - Example: Security patching workflow across all infrastructure

4. **Resource Efficiency Matters**
   - One controller VM vs three saves resources
   - Your infrastructure is growing, so reserve capacity for workloads, not management

5. **Future-Proof for Execution Environments**
   - Start with unified controller
   - Add execution environments later if dependency conflicts emerge
   - Can transition to AWX without major refactoring

### When to Reconsider (Future Triggers)

Switch to multiple controllers or hybrid if:
- Infrastructure grows beyond 100+ managed hosts
- Team size exceeds 5-10 people with specialized roles
- Strict compliance requires domain separation
- Performance issues with single controller (rare below 200 hosts)
- Different change management processes per domain

---

## Implementation Specifications

### Recommended Controller Specs

**For your current setup (9 hosts + growing VMs):**

| Resource | Minimum | Recommended | Rationale |
|----------|---------|-------------|-----------|
| **vCPUs** | 4 | 8 | Parallel playbook execution |
| **RAM** | 8 GB | 16 GB | Fact caching, multiple Python processes |
| **Storage** | 50 GB | 100 GB SSD | Logs, facts, git repos, vault files |
| **Network** | 1 Gbps | 1 Gbps | Sufficient for config management traffic |
| **OS** | Ubuntu 22.04/24.04 LTS | Ubuntu 24.04 LTS | Match target nodes, long support |

**Sizing calculation:**
- Base OS: ~10 GB
- Ansible + dependencies: ~5 GB
- Git repositories: ~5 GB
- Fact cache (50 hosts × 100KB): ~5 GB
- Logs (30 days): ~10 GB
- Vault files and secrets: ~1 GB
- Headroom for growth: ~64 GB
- **Total: 100 GB**

### Network Requirements

**Controller Placement Options:**

**Option A: Dedicated Management VLAN (Recommended)**
```
VLAN 10 (Server Management, IPMI/BMC only): 10.9.10.0/24
  - Isolated: not routed to/from other VLANs
  - Purpose: out-of-band management only

VLAN 20 (LAN / Management & Servers): 10.9.20.0/24
├── Ansible Controller(s)
├── KVM Host: 10.9.20.150
├── Hyper-V Hosts: 10.9.20.220-221
└── Other management endpoints

VLAN 80 (Kubernetes Nodes): 10.9.80.0/24
├── kube-10 .. kube-13 (RPi)
└── kube-20 .. kube-21 (x86 VMs)

Kubernetes LoadBalancer (virtual, not a VLAN)
├── Pool: 10.64.140.0/24
└── Ingress LB IP: 10.64.140.1
```

**Option B: Co-located with K8s Nodes**
- If management VLAN not available
- Controller on same subnet as K8s cluster
- Still secure with proper SSH key management

**Required Connectivity:**

| Source | Destination | Port | Protocol | Purpose |
|--------|-------------|------|----------|---------|
| Controller | All Linux hosts | 22 | TCP | SSH (Ansible transport) |
| Controller | Windows hosts | 5985, 5986 | TCP | WinRM (HTTP, HTTPS) |
| Controller | KVM host | 16509 | TCP | libvirt (optional, for VM mgmt) |
| Controller | Hyper-V hosts | 5985, 5986 | TCP | PowerShell remoting |
| Controller | K8s API | 16443 | TCP | kubectl operations |
| Controller | Internet | 443 | TCP | Ansible Galaxy, package repos |

### High Availability Considerations

**For production-critical automation:**

1. **Controller VM Backup**
   - Daily snapshots of controller VM
   - Backup `/opt/ansible/` directory to NFS/remote
   - Document recovery procedure (restore time: <30 min)

2. **Git-Based Disaster Recovery**
   - All playbooks/inventory in Git (GitHub/GitLab)
   - Controller VM is ephemeral/replaceable
   - Recovery: Install Ansible → Clone repo → Restore vault password
   - Restore time: <1 hour

3. **Future: Redundant Controllers** (only if needed)
   - Active/Passive: Manual failover to secondary controller
   - Shared inventory/playbooks via Git
   - Requires tooling to prevent simultaneous execution

**For your scale, Option 2 (Git-Based DR) is sufficient.**

---

## Dependency Management Strategy

### Challenge: Different Python Dependencies

Your unified controller needs:
- **Kubernetes**: `kubernetes`, `pyyaml`, `jsonpatch`
- **Windows**: `pywinrm`, `requests-kerberos`
- **VMware** (if any): `pyvmomi`, `requests`
- **Libvirt/KVM**: `libvirt-python`, `lxml`

### Solution: Python Virtual Environments

**Setup per domain:**
```bash
# Base system Python packages
sudo apt install -y python3 python3-pip python3-venv

# Create venvs
python3 -m venv /opt/ansible/venv-kubernetes
python3 -m venv /opt/ansible/venv-windows
python3 -m venv /opt/ansible/venv-libvirt

# Activate and install per domain
source /opt/ansible/venv-kubernetes/bin/activate
pip install ansible kubernetes pyyaml

source /opt/ansible/venv-windows/bin/activate
pip install ansible pywinrm

source /opt/ansible/venv-libvirt/bin/activate
pip install ansible libvirt-python lxml
```

**Usage in playbooks:**
```yaml
# playbooks/kubernetes/upgrade_microk8s.yml
- hosts: microk8s_cluster
  vars:
    ansible_python_interpreter: /opt/ansible/venv-kubernetes/bin/python
  tasks:
    - name: Use K8s module
      kubernetes.core.k8s:
        # ... task definition ...

# playbooks/baremetal/windows/updates.yml
- hosts: windows
  vars:
    ansible_python_interpreter: /opt/ansible/venv-windows/bin/python
  tasks:
    - name: Use Windows module
      win_updates:
        # ... task definition ...
```

**Alternative: Ansible Collections with Requirements**

```yaml
# collections/requirements.yml
collections:
  - name: kubernetes.core
    version: ">=2.4.0"
  - name: community.windows
    version: ">=2.0.0"
  - name: community.libvirt
    version: ">=1.3.0"
```

Install: `ansible-galaxy collection install -r collections/requirements.yml`

---

## Sample Inventory for Your Setup

### inventories/production/all.yml
```yaml
---
all:
  vars:
    ansible_python_interpreter: /usr/bin/python3
    # Global settings
    backup_destination: /shared/microk8s/backup
    log_destination: /var/log/ansible

  children:
    # All Linux systems
    linux:
      vars:
        ansible_user: root
        ansible_connection: ssh
        ansible_ssh_private_key_file: ~/.ssh/id_ed25519_ansible
      children:
        kubernetes:
          vars:
            ansible_python_interpreter: /opt/ansible/venv-kubernetes/bin/python
            microk8s_channel: "1.34/stable"
          hosts:
            kube-01.local.lan:
              ansible_host: 192.168.10.10
            kube-02.local.lan:
              ansible_host: 192.168.10.11
            kube-03.local.lan:
              ansible_host: 192.168.10.12
            kube-04.local.lan:
              ansible_host: 192.168.10.13
            kube-05.local.lan:
              ansible_host: 192.168.10.14
            kube-06.local.lan:
              ansible_host: 192.168.10.15

        linux_baremetal:
          hosts:
            fileserver-kvm.local.lan:
              ansible_host: 192.168.10.20
              hypervisor_type: kvm

    # All Windows systems
    windows:
      vars:
        ansible_user: Administrator
        ansible_connection: winrm
        ansible_winrm_transport: ntlm
        ansible_winrm_server_cert_validation: ignore
        ansible_python_interpreter: /opt/ansible/venv-windows/bin/python
      children:
        windows_baremetal:
          hosts:
            hyperv-01.local.lan:
              ansible_host: 192.168.10.21
              hypervisor_type: hyperv
            hyperv-02.local.lan:
              ansible_host: 192.168.10.22
              hypervisor_type: hyperv

    # Virtual machines (dynamic, grows over time)
    virtual_machines:
      children:
        kvm_guests:
          # Can use dynamic inventory here
          vars:
            hypervisor_host: fileserver-kvm.local.lan
        hyperv_guests:
          # Can use dynamic inventory here
          vars:
            hypervisor_hosts:
              - hyperv-01.local.lan
              - hyperv-02.local.lan
```

### Group Variables Structure

```yaml
# inventories/production/group_vars/kubernetes.yml
---
microk8s_channel: "1.34/stable"
microk8s_addons:
  - dns
  - ingress
  - storage
  - cert-manager

kubectl_path: /snap/bin/microk8s.kubectl
drain_timeout_seconds: 600
backup_path: "{{ backup_destination }}/kubernetes"

# inventories/production/group_vars/windows.yml
---
windows_update_categories:
  - CriticalUpdates
  - SecurityUpdates
  - UpdateRollups

hyperv_vswitch: "External-vSwitch"
vm_default_path: "C:\\VMs"

# inventories/production/group_vars/linux_baremetal.yml
---
kvm_storage_pool: /var/lib/libvirt/images
kvm_network: default
nfs_exports:
  - path: /shared/microk8s
    clients: "192.168.10.0/24"
    options: "rw,sync,no_subtree_check,no_root_squash"
```

---

## Secrets Management

### Ansible Vault Setup

**Create separate vault files per domain:**

```bash
# Create vault password file (store securely, e.g., 1Password)
echo "your-strong-vault-password" > ~/.ansible_vault_pass
chmod 600 ~/.ansible_vault_pass

# Create encrypted vault files
ansible-vault create inventories/production/group_vars/kubernetes/vault.yml
ansible-vault create inventories/production/group_vars/windows/vault.yml
ansible-vault create inventories/production/group_vars/linux_baremetal/vault.yml
```

**Configure ansible.cfg:**
```ini
[defaults]
vault_password_file = ~/.ansible_vault_pass
```

**Example vault content:**
```yaml
# inventories/production/group_vars/kubernetes/vault.yml
---
vault_microk8s_join_token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
vault_kubectl_admin_token: "kubeconfig-token-here"

# inventories/production/group_vars/windows/vault.yml
---
vault_windows_admin_password: "SecurePassword123!"
vault_hyperv_domain_join_password: "DomainPassword456!"

# inventories/production/group_vars/linux_baremetal/vault.yml
---
vault_nfs_export_password: "NFSPassword789!"
vault_kvm_libvirt_uri: "qemu+ssh://root@fileserver-kvm.local.lan/system"
```

**Reference in playbooks:**
```yaml
- name: Join Windows to domain
  win_domain_membership:
    dns_domain_name: corp.local
    domain_admin_user: "Administrator@corp.local"
    domain_admin_password: "{{ vault_hyperv_domain_join_password }}"
```

---

## Operational Workflows

### Daily Operations

**1. Check Status Across All Infrastructure**
```bash
# Run unified status check
ansible-playbook playbooks/monitoring/check_all_status.yml

# Or per domain
ansible-playbook playbooks/kubernetes/get_status.yml
ansible-playbook playbooks/baremetal/health_check.yml
ansible-playbook playbooks/vms/inventory_report.yml
```

**2. Apply Security Updates**
```bash
# K8s cluster patching (with draining)
ansible-playbook playbooks/kubernetes/security_updates.yml --check
ansible-playbook playbooks/kubernetes/security_updates.yml

# Bare-metal patching
ansible-playbook playbooks/baremetal/linux/os_updates.yml
ansible-playbook playbooks/baremetal/windows/windows_updates.yml

# VM patching (parallel across hypervisors)
ansible-playbook playbooks/vms/update_all_guests.yml
```

**3. Backup Everything**
```bash
# Orchestrated backup across all domains
ansible-playbook playbooks/orchestration/full_backup.yml
```

### Weekly Operations

**1. VM Lifecycle Management**
```bash
# Create new VM from template
ansible-playbook playbooks/vms/create_vm.yml -e "vm_name=test-vm-01 vm_memory=4096"

# Snapshot all VMs before maintenance
ansible-playbook playbooks/vms/snapshot_all.yml -e "snapshot_name=weekly-$(date +%Y%m%d)"

# Cleanup old snapshots
ansible-playbook playbooks/vms/cleanup_snapshots.yml -e "older_than_days=30"
```

**2. Kubernetes Maintenance**
```bash
# Restart MicroK8s nodes (rolling restart)
ansible-playbook playbooks/kubernetes/restart_microk8s.yml --limit kube-03.local.lan

# Repair database quorum (if needed)
ansible-playbook playbooks/kubernetes/repair_database.yml --check
```

### Monthly Operations

**1. Upgrade MicroK8s**
```bash
# Check upgrade path
ansible-playbook playbooks/kubernetes/upgrade_microk8s.yml --check

# Upgrade with draining
ansible-playbook playbooks/kubernetes/upgrade_microk8s.yml -e "target_channel=1.35/stable"
```

**2. Infrastructure Review**
```bash
# Generate capacity report
ansible-playbook playbooks/monitoring/capacity_report.yml

# Security compliance scan
ansible-playbook playbooks/security/compliance_check.yml
```

---

## Migration Path from Shell Scripts

### Phase 1: Setup Foundation (Week 1-2)

1. **Provision Controller VM**
   - [ ] Create VM with recommended specs
   - [ ] Install Ubuntu 24.04 LTS
   - [ ] Configure static IP on management network
   - [ ] Set hostname: `ansible-controller.local.lan`

2. **Install Ansible**
   - [ ] Run: `sudo apt install -y ansible ansible-lint`
   - [ ] Install Python venvs for each domain
   - [ ] Install kubectl: `snap install kubectl --classic`
   - [ ] Configure git: `git config --global user.name "Your Name"`

3. **Setup SSH Access**
   - [ ] Generate SSH key: `ssh-keygen -t ed25519 -C "ansible-controller"`
   - [ ] Copy to all 9 hosts: `ssh-copy-id root@kube-01.local.lan` (repeat)
   - [ ] Test passwordless access to each host
   - [ ] Configure WinRM on Windows hosts (see appendix)

4. **Create Directory Structure**
   ```bash
   mkdir -p /opt/ansible/{inventories,playbooks,roles,library,vaults,docs}
   cd /opt/ansible
   git init
   ```

5. **Create Initial Inventory**
   - [ ] Copy the sample inventory above
   - [ ] Update with your actual hostnames/IPs
   - [ ] Test: `ansible all -m ping`

### Phase 2: Convert First Playbook (Week 3-4)

**Start with `get-status.sh` (safest, read-only)**

**Original script:**
```bash
#!/usr/bin/env bash
readarray -t nodeArray < <(${KUBECTL} get nodes -o name | sed 's|node/||')
for nodeFQDN in "${nodeArray[@]}"; do
    ${KUBECTL} get node "$nodeFQDN"
    ssh "root@$nodeFQDN" microk8s status | head -n 4
done
```

**New playbook: `playbooks/kubernetes/get_status.yml`**
```yaml
---
- name: Get MicroK8s cluster status
  hosts: kubernetes
  gather_facts: no
  tasks:
    - name: Get node status from kubectl
      command: microk8s kubectl get node {{ inventory_hostname }}
      register: node_status
      delegate_to: localhost
      changed_when: false

    - name: Get MicroK8s status on node
      command: microk8s status
      register: microk8s_status
      changed_when: false

    - name: Display results
      debug:
        msg: |
          Node: {{ inventory_hostname }}
          {{ node_status.stdout }}
          {{ microk8s_status.stdout_lines[:4] | join('\n') }}
```

**Test:**
```bash
ansible-playbook playbooks/kubernetes/get_status.yml --check
ansible-playbook playbooks/kubernetes/get_status.yml
```

### Phase 3: Convert Remaining Scripts (Month 2-3)

**Priority order:**
1. ✅ `get-status.sh` (done above)
2. `restart-microk8s.sh` - Low risk, frequent use
3. `shutdown-all-nodes.sh` - Emergency procedure
4. `upgrade-microk8s.sh` - Complex but high value
5. `repair-database-quorum.sh` - Most complex, test extensively

### Phase 4: Add Bare-Metal & VM Playbooks (Month 3-4)

**New playbooks to create:**
- `playbooks/baremetal/linux/os_updates.yml`
- `playbooks/baremetal/windows/windows_updates.yml`
- `playbooks/baremetal/windows/configure_hyperv.yml`
- `playbooks/vms/kvm/create_vm.yml`
- `playbooks/vms/hyperv/create_vm.yml`
- `playbooks/vms/snapshot_all.yml`

---

## Windows Host Configuration

### Prerequisites for Ansible Management

**On each Hyper-V host (run in PowerShell as Administrator):**

```powershell
# Enable WinRM
Enable-PSRemoting -Force

# Configure WinRM for Ansible
Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true
Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $true

# Set firewall rule
New-NetFirewallRule -Name "WinRM-HTTP" -DisplayName "WinRM HTTP" `
    -Enabled True -Direction Inbound -Protocol TCP -LocalPort 5985

# For HTTPS (recommended for production)
New-NetFirewallRule -Name "WinRM-HTTPS" -DisplayName "WinRM HTTPS" `
    -Enabled True -Direction Inbound -Protocol TCP -LocalPort 5986

# Create self-signed cert for HTTPS (or use proper cert)
$cert = New-SelfSignedCertificate -DnsName "hyperv-01.local.lan" -CertStoreLocation "Cert:\LocalMachine\My"
New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $cert.Thumbprint -Force

# Test from Ansible controller
# (On controller): ansible windows -m win_ping
```

### Sample Windows Playbook

```yaml
# playbooks/baremetal/windows/configure_hyperv.yml
---
- name: Configure Hyper-V hosts
  hosts: windows_baremetal
  tasks:
    - name: Ensure Hyper-V feature is installed
      win_feature:
        name: Hyper-V
        include_management_tools: yes
        state: present
      register: hyperv_feature

    - name: Reboot if Hyper-V was just installed
      win_reboot:
      when: hyperv_feature.reboot_required

    - name: Create external virtual switch
      win_shell: |
        $switch = Get-VMSwitch -Name "External-vSwitch" -ErrorAction SilentlyContinue
        if (-not $switch) {
          $adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | Select-Object -First 1
          New-VMSwitch -Name "External-vSwitch" -NetAdapterName $adapter.Name -AllowManagementOS $true
        }
      register: vswitch_result
      changed_when: "'External-vSwitch' not in vswitch_result.stdout"

    - name: Set default VM storage path
      win_shell: |
        Set-VMHost -VirtualHardDiskPath "C:\VMs\VHDs" -VirtualMachinePath "C:\VMs"
```

---

## KVM/Libvirt Management

### Sample KVM Playbooks

```yaml
# playbooks/baremetal/linux/configure_kvm.yml
---
- name: Configure KVM host
  hosts: linux_baremetal
  vars:
    storage_pool_path: /var/lib/libvirt/images
  tasks:
    - name: Install KVM and libvirt packages
      apt:
        name:
          - qemu-kvm
          - libvirt-daemon-system
          - libvirt-clients
          - bridge-utils
          - virt-manager
        state: present
        update_cache: yes

    - name: Ensure libvirtd is running
      service:
        name: libvirtd
        state: started
        enabled: yes

    - name: Create storage pool
      virt_pool:
        command: define
        name: default
        xml: |
          <pool type='dir'>
            <name>default</name>
            <target>
              <path>{{ storage_pool_path }}</path>
            </target>
          </pool>

    - name: Start and autostart storage pool
      virt_pool:
        name: default
        state: active
        autostart: yes

# playbooks/vms/kvm/create_vm.yml
---
- name: Create KVM virtual machine
  hosts: linux_baremetal
  vars:
    vm_name: "{{ vm_name | default('new-vm') }}"
    vm_memory: "{{ vm_memory | default(2048) }}"
    vm_vcpus: "{{ vm_vcpus | default(2) }}"
    vm_disk_size: "{{ vm_disk_size | default('20G') }}"
    vm_template: "{{ vm_template | default('ubuntu-22.04-template') }}"
  tasks:
    - name: Create VM disk from template
      command: >
        qemu-img create -f qcow2 -F qcow2
        -b /var/lib/libvirt/images/{{ vm_template }}.qcow2
        /var/lib/libvirt/images/{{ vm_name }}.qcow2
        {{ vm_disk_size }}

    - name: Define VM
      virt:
        command: define
        xml: "{{ lookup('template', 'vm_template.xml.j2') }}"

    - name: Start VM
      virt:
        name: "{{ vm_name }}"
        state: running

    - name: Wait for VM to get IP
      shell: >
        virsh domifaddr {{ vm_name }} | grep ipv4 | awk '{print $4}' | cut -d'/' -f1
      register: vm_ip
      until: vm_ip.stdout != ""
      retries: 30
      delay: 10

    - name: Add VM to inventory
      add_host:
        name: "{{ vm_name }}"
        ansible_host: "{{ vm_ip.stdout }}"
        groups: virtual_machines,kvm_guests
```

---

## Summary & Next Steps

### Decision: Single Unified Controller ✅

**Benefits for your infrastructure:**
- Manage 6 K8s nodes + 3 bare-metal hosts + growing VMs from one place
- Cross-domain orchestration (deploy VM → add to K8s)
- Operational efficiency (one system to maintain)
- Future-proof (can add execution environments later)
- Cost-effective (one controller VM, ~16GB RAM, 100GB disk)

### Your Action Items

**This week:**
1. [ ] Provision controller VM (8 vCPU, 16GB RAM, 100GB disk)
2. [ ] Install Ubuntu 24.04 and Ansible
3. [ ] Configure SSH access to all 9 hosts
4. [ ] Create initial inventory file with your actual hostnames/IPs

**Next 2 weeks:**
5. [ ] Convert `get-status.sh` to playbook (practice run)
6. [ ] Create directory structure and git repository
7. [ ] Set up Ansible Vault for secrets

**Month 2:**
8. [ ] Convert remaining K8s scripts to playbooks
9. [ ] Add bare-metal server management playbooks
10. [ ] Create VM lifecycle playbooks for KVM and Hyper-V

### Questions?

Reply with:
- Your 6 K8s node hostnames/IPs
- 3 bare-metal host details
- Where you'll run the Ansible controller
- Which script you want to convert first

I'll help you create the specific inventory files and first playbooks!

---

**Document Version:** 1.0
**Date:** 2025-11-13
**Decision:** Single Unified Ansible Controller (Option 1)
**Status:** Recommended Architecture
