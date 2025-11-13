# Ansible Migration Plan for MicroK8s Scripts

## Executive Summary

This document outlines the hardware, network infrastructure, and planning considerations for converting the existing MicroK8s shell scripts to Ansible automation.

> **📘 Multi-Purpose Architecture:** If you're planning to manage Kubernetes, bare-metal servers, AND VM deployments with Ansible, see the companion document: [ANSIBLE_ARCHITECTURE_DECISION.md](./ANSIBLE_ARCHITECTURE_DECISION.md) for a detailed analysis of single vs multiple controller architectures.

---

## Current Infrastructure Analysis

### Existing Architecture (from scripts analysis)

**Access Pattern:**
- All scripts use SSH as `root@<node-fqdn>`
- Passwordless SSH key authentication (implied by automated scripts)
- Centralized control node running scripts
- Direct root access to all cluster nodes

**Node Naming Convention:**
- FQDNs used for node addressing
- Special handling for nodes with `kube-10*` prefix (in repair scripts)
- Nodes discovered dynamically via `kubectl get nodes`

**Operations Currently Performed:**
1. **Lifecycle Management**: restart, upgrade, shutdown
2. **Cluster Coordination**: drain/uncordon nodes
3. **Database Operations**: dqlite repair, backup/restore
4. **Status Monitoring**: health checks, addon status
5. **Configuration Management**: CoreDNS patches, addon configuration

---

## Hardware & Network Infrastructure Requirements

### 1. Control Node (Ansible Controller)

**Minimum Requirements:**
- **OS**: Ubuntu 22.04 LTS or newer (to match existing target nodes)
- **CPU**: 2+ cores
- **RAM**: 4GB minimum, 8GB recommended
- **Storage**: 20GB+ for Ansible, playbooks, and temporary artifacts
- **Network**: Reliable connection to all managed nodes
- **Software**:
  - Python 3.8+
  - Ansible 2.15+ (or ansible-core 2.15+)
  - kubectl (for k8s module operations)
  - SSH client
  - git (for version control)

**Can be:**
- Dedicated VM/physical machine
- One of the existing MicroK8s nodes (if you run Ansible locally)
- Your current workstation/laptop
- A Docker container (for ephemeral/CI operations)

**Recommended Setup:**
```bash
# Install Ansible on Ubuntu
sudo apt update
sudo apt install -y software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install -y ansible ansible-lint

# Install Python dependencies
pip3 install kubernetes pyyaml jinja2

# Install kubectl (if not already present)
snap install kubectl --classic
```

---

### 2. Managed Nodes (MicroK8s Cluster)

**Current Setup (inferred from scripts):**
- **OS**: Ubuntu-based (apt usage, snap-based MicroK8s)
- **MicroK8s**: Snap-based installation
- **Role**: Kubernetes cluster nodes
- **Count**: Multiple nodes (exact count unknown - dynamically discovered)

**Requirements per Node:**
- **SSH Access**: Root SSH access with key-based authentication
- **Python**: Python 3.6+ (required by Ansible)
- **Network**:
  - Bidirectional connectivity with control node
  - Inter-node connectivity for k8s cluster operations
  - Access to snap store (for MicroK8s upgrades)
  - NFS access (based on existing PVC/StorageClass manifests)

**SSH Configuration Needed:**
- Control node's SSH public key in each node's `/root/.ssh/authorized_keys`
- SSH config on control node for easy access (optional but recommended)
- Known hosts entries or `StrictHostKeyChecking=no` (with caution)

---

### 3. Network Infrastructure Planning

#### IP Addressing & DNS

**Current Observations:**
- Scripts use FQDNs for node addressing
- Suggests DNS resolution is in place

**Recommendations:**

**Option A: Static DNS Entries**
- Create DNS A records for all nodes
- Use consistent naming: `kube-01.example.com`, `kube-02.example.com`, etc.
- Update `/etc/hosts` on control node as backup

**Option B: Local /etc/hosts (small clusters)**
```
192.168.1.10  kube-01.local.lan kube-01
192.168.1.11  kube-02.local.lan kube-02
192.168.1.12  kube-03.local.lan kube-03
```

**Option C: Dynamic Inventory from kubectl**
- Use Ansible dynamic inventory script
- Pull node list from `kubectl get nodes` (matches current behavior)
- Resolve IPs dynamically

#### Network Segmentation

**Authoritative VLAN/Subnet Layout (current environment):**

1. **Server Management (IPMI/BMC only)**
  - VLAN 10: 10.9.10.0/24
  - Isolated: not routed to/from other VLANs
  - Purpose: out-of-band access (iDRAC/iLO/IPMI)

2. **LAN / Management and Servers**
  - VLAN 20: 10.9.20.0/24
  - Examples: hl15-00 (10.9.20.150), Hyper-V hosts, controller(s)

3. **IoT**
  - VLAN 30: 192.168.30.0/24

4. **Guest**
  - VLAN 40: 192.168.40.0/24

5. **Placeholders**
  - VLAN 50: 10.9.50.0/24
  - VLAN 60: 10.9.60.0/24
  - VLAN 70: 10.9.70.0/24

6. **Kubernetes Nodes**
  - VLAN 80: 10.9.80.0/24
  - MicroK8s nodes reside here

7. **Kubernetes Virtual Networks (inside cluster)**
  - Pod CIDR (virtual): 10.1.0.0/16 (default)
  - Service CIDR (virtual): 10.152.183.0/24 (default)

8. **Kubernetes LoadBalancer Addresses (external but not a VLAN)**
  - LoadBalancer pool: 10.64.140.0/24
  - Ingress LoadBalancer IP: 10.64.140.1
  - Note: Provided by MetalLB or equivalent; these IPs are not tied to a physical VLAN

**Firewall Rules Required:**

Control Node → Managed Nodes:
- SSH (22/tcp) - for Ansible operations
- Optional: MicroK8s API (16443/tcp) - for kubectl operations

Managed Nodes ↔ Managed Nodes:
- MicroK8s dqlite (19001/tcp) - for database replication
- Kubernetes API (16443/tcp)
- Kubelet (10250/tcp)
- CNI ports (varies by CNI plugin)
- NodePort range (30000-32767/tcp)

All Nodes → Internet:
- HTTPS (443/tcp) - for snap updates, container registries
- DNS (53/udp) - for name resolution

---

### 4. Storage Infrastructure

**Current Usage (from manifests):**
- NFS-based PersistentVolumeClaims
- StorageClass: `nfs-client` or similar
- Backup storage: `/shared/microk8s/` (NFS mount assumed)

**Requirements:**
- **NFS Server**: Existing or dedicated NFS appliance
  - Export: `/shared/microk8s` → mounted on all nodes
  - Permissions: root_squash disabled or UID mapping configured
  - Performance: SSD-backed recommended for database workloads

- **Backup Storage**: Separate location for dqlite backups
  - Current: `/shared/microk8s/backend.bak/`
  - Consideration: Off-site backup for DR

**Ansible Implications:**
- Playbooks should validate NFS mounts before operations
- Backup tasks need sufficient space checks
- Consider Ansible roles for NFS client configuration

---

## Ansible Inventory Design

### Inventory Structure

**File: `inventory/production/hosts.yml`**
```yaml
all:
  vars:
    ansible_user: root
    ansible_python_interpreter: /usr/bin/python3
    kubectl_command: microk8s kubectl

  children:
    microk8s_cluster:
      vars:
        microk8s_channel: "1.34/stable"

      children:
        control_plane:
          hosts:
            kube-01.local.lan:
              ansible_host: 192.168.10.10
            kube-02.local.lan:
              ansible_host: 192.168.10.11
            kube-03.local.lan:
              ansible_host: 192.168.10.12

        worker_nodes:
          hosts:
            kube-04.local.lan:
              ansible_host: 192.168.10.14
            kube-05.local.lan:
              ansible_host: 192.168.10.15

    # Special group for database quorum node (avoids clearing backend)
    dqlite_primary:
      hosts:
        kube-01.local.lan:
```

**Alternative: Dynamic Inventory Script**
```python
#!/usr/bin/env python3
# File: inventory/dynamic_k8s.py
import subprocess
import json

def get_nodes():
    result = subprocess.run(
        ['kubectl', 'get', 'nodes', '-o', 'name'],
        capture_output=True, text=True
    )
    nodes = [n.replace('node/', '') for n in result.stdout.strip().split('\n')]

    inventory = {
        'microk8s_cluster': {
            'hosts': nodes
        },
        '_meta': {
            'hostvars': {}
        }
    }
    return inventory

if __name__ == '__main__':
    print(json.dumps(get_nodes(), indent=2))
```

---

## Architecture Decision Records

### ADR-001: Ansible Control Node Location

**Decision:** Use existing workstation/dedicated VM as control node, NOT a cluster node

**Rationale:**
- Avoids circular dependencies during cluster maintenance
- Control node remains available during node upgrades/reboots
- Easier troubleshooting when cluster is down
- Follows Ansible best practices

**Alternatives Considered:**
- Running Ansible from a cluster node: Rejected due to availability concerns
- CI/CD pipeline execution: Possible future enhancement

---

### ADR-002: Root vs Non-Root Ansible User

**Current State:** Scripts use `root@node` SSH access

**Decision:** Continue using root initially, migrate to sudo-enabled user later

**Rationale:**
- Minimal disruption to existing setup
- MicroK8s operations often require root/sudo
- Faster initial migration path
- Can refactor to non-root in phase 2

**Security Considerations:**
- Use SSH key with passphrase
- Restrict control node access
- Implement Ansible Vault for secrets
- Audit SSH key usage regularly

**Future Enhancement:**
```yaml
ansible_user: microk8s-admin
ansible_become: yes
ansible_become_method: sudo
```

---

### ADR-003: Inventory Management Strategy

**Decision:** Start with static inventory, add dynamic option later

**Rationale:**
- Static inventory easier to understand and debug
- Explicit node definitions prevent accidents
- Group variables provide clear configuration
- Dynamic inventory can be added without changing playbooks

**Migration Path:**
1. Phase 1: Static YAML inventory
2. Phase 2: Add dynamic inventory script as alternative
3. Phase 3: Hybrid approach (static for core nodes, dynamic for workers)

---

### ADR-004: Playbook Organization

**Decision:** Create role-based structure matching existing script functions

**Structure:**
```
ansible/
├── ansible.cfg
├── inventory/
│   ├── production/
│   │   ├── hosts.yml
│   │   └── group_vars/
│   └── staging/
├── playbooks/
│   ├── restart_microk8s.yml
│   ├── upgrade_microk8s.yml
│   ├── get_status.yml
│   ├── repair_database.yml
│   └── shutdown_all.yml
├── roles/
│   ├── microk8s_common/
│   ├── microk8s_upgrade/
│   ├── microk8s_backup/
│   └── dqlite_repair/
└── library/
    └── custom_modules/
```

---

## Network Topology Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        Internet / Upstream                       │
└────────────────────────────────┬────────────────────────────────┘
                                 │
                    ┌────────────┴────────────┐
                    │   Router / Firewall     │
                    │   DNS, DHCP, NAT        │
                    └────────────┬────────────┘
                                 │
         ┌───────────────────────┼───────────────────────┐
         │                       │                       │
┌────────┴────────┐    ┌─────────┴────────┐   ┌─────────┴────────┐
│    LAN / Mgmt   │    │ Kubernetes Nodes │   │  IPMI / BMC Net  │
│    VLAN 20      │    │     VLAN 80      │   │     VLAN 10      │
│  10.9.20.0/24   │    │   10.9.80.0/24   │   │   10.9.10.0/24   │
└────────┬────────┘    └─────────┬────────┘   └─────────┬────────┘
         │                       │                       │
    ┌────┴────┐             ┌────┴────┐             ┌────┴────┐
    │Control  │             │  kube-  │             │  IPMI   │
    │Node(s)  │             │  10-21  │             │ Gateways│
    │ .20.x   │             │ .80.x   │             │ .10.x   │
    └─────────┘             └─────────┘             └─────────┘
         │                       │                       │
      └───────SSH (22)────────┘                       │
          │                                   │
        ┌────┴────┐                              │
        │  LB IPs │ 10.64.140.0/24 (virtual pool)│
        │(MetalLB)│ 10.64.140.1 (Ingress)        │
        └─────────┘                              │
```

---

## Pre-Migration Checklist

### Infrastructure Readiness

- [ ] **Control Node Setup**
  - [ ] Operating system installed and updated
  - [ ] Ansible 2.15+ installed
  - [ ] Python 3.8+ with required modules
  - [ ] kubectl configured and tested
  - [ ] Git repository cloned
  - [ ] Network connectivity to all nodes verified

- [ ] **SSH Access Configuration**
  - [ ] SSH key pair generated (ed25519 or RSA 4096-bit)
  - [ ] Public key deployed to all nodes' authorized_keys
  - [ ] Passwordless SSH tested from control node to each managed node
  - [ ] SSH config file created (optional but recommended)
  - [ ] Known hosts populated or StrictHostKeyChecking configured

- [ ] **Network Validation**
  - [ ] All nodes can resolve each other by FQDN
  - [ ] Control node can reach all management IPs
  - [ ] Firewall rules allow required ports
  - [ ] NFS mounts accessible from all nodes
  - [ ] Internet connectivity for package updates
  - [ ] Network latency acceptable (<10ms for cluster operations)

- [ ] **Node Prerequisites**
  - [ ] Python 3 installed on all nodes (`apt install python3`)
  - [ ] Sudo configured (if not using root)
  - [ ] NFS client packages installed
  - [ ] Sufficient disk space for operations (20GB+ free)
  - [ ] System clocks synchronized (NTP configured)

- [ ] **Documentation & Inventory**
  - [ ] Node inventory spreadsheet created (hostname, IP, role)
  - [ ] Network diagram documented
  - [ ] Current MicroK8s version recorded
  - [ ] Addon list documented
  - [ ] Backup locations identified
  - [ ] Emergency rollback plan documented

### Testing Environment

- [ ] **Staging Cluster Available**
  - [ ] Mirror production node count
  - [ ] Same Ubuntu version
  - [ ] Same MicroK8s version
  - [ ] Non-production data
  - [ ] Safe for destructive testing

- [ ] **Validation Scripts**
  - [ ] Test playbooks written
  - [ ] Dry-run mode tested
  - [ ] Rollback procedures validated
  - [ ] Monitoring/alerting configured

---

## Hardware Recommendations by Cluster Size

### Small Cluster (3-5 nodes)

**Control Node:**
- VM: 2 vCPU, 4GB RAM, 20GB storage
- Can be your laptop/workstation
- Estimated cost: $0 (existing hardware)

**Managed Nodes:**
- Raspberry Pi 4 (8GB) or equivalent x86_64 SBC
- Or repurposed desktop/laptop
- Estimated cost: $75-150 per node

**Network:**
- Single gigabit switch
- Consumer router with VLAN support
- Estimated cost: $50-150

**Total Investment:** $300-1000

---

### Medium Cluster (5-10 nodes)

**Control Node:**
- Dedicated VM: 4 vCPU, 8GB RAM, 50GB storage
- Running on existing hypervisor
- Estimated cost: $0-200

**Managed Nodes:**
- Intel NUC or similar mini-PC
- 4-core CPU, 16-32GB RAM, 256GB SSD per node
- Estimated cost: $400-700 per node

**Network:**
- Managed switch with VLAN support
- Separate management and data networks
- 10GbE uplinks (optional)
- Estimated cost: $200-500

**Storage:**
- Dedicated NAS (Synology, QNAP, TrueNAS)
- 4-8TB usable capacity
- Estimated cost: $500-1500

**Total Investment:** $3000-8000

---

### Large Cluster (10+ nodes)

**Control Node:**
- Dedicated physical or VM: 8 vCPU, 16GB RAM, 100GB storage
- High availability (consider redundant control nodes)
- Estimated cost: $500-1500

**Managed Nodes:**
- Rackmount servers (1U/2U)
- Dual-socket or high-core-count CPUs
- 64-128GB RAM, NVMe storage per node
- Estimated cost: $1500-3000 per node

**Network:**
- Enterprise-grade switches with 10GbE/25GbE
- Redundant network paths
- Separate OOB management network
- Estimated cost: $2000-10000

**Storage:**
- Enterprise SAN or distributed storage (Ceph)
- 20TB+ usable capacity
- Redundant connections
- Estimated cost: $5000-20000

**Total Investment:** $20,000-60,000+

---

## Next Steps

### Immediate Actions (Week 1)

1. **Inventory Current Infrastructure**
   - Document all node hostnames, IPs, specs
   - Record current MicroK8s version and addons
   - Map network topology
   - Identify backup/restore requirements

2. **Set Up Control Node**
   - Install Ubuntu on designated control machine
   - Install Ansible and dependencies
   - Configure SSH keys
   - Clone this repository

3. **Validate Connectivity**
   - Test SSH to all nodes as root
   - Verify kubectl access
   - Confirm NFS mounts
   - Run `scripts/get-status.sh` successfully

### Short-term Goals (Weeks 2-4)

1. **Create Initial Inventory**
   - Write `inventory/production/hosts.yml`
   - Define group variables
   - Test with `ansible all -m ping`

2. **Convert First Script**
   - Start with `get-status.sh` (read-only, low risk)
   - Create `playbooks/get_status.yml`
   - Test extensively in staging

3. **Develop Ansible Roles**
   - Extract common tasks to roles
   - Implement error handling
   - Add idempotency checks

4. **Documentation**
   - Write playbook usage guides
   - Document variables and tags
   - Create troubleshooting guide

### Mid-term Goals (Months 2-3)

1. **Convert Remaining Scripts**
   - Restart operations
   - Upgrade workflows
   - Backup/restore
   - Database repair (most complex)

2. **Implement CI/CD**
   - Automated testing of playbooks
   - Linting (ansible-lint, yamllint)
   - Version control workflows

3. **Advanced Features**
   - Dynamic inventory
   - Ansible Tower/AWX (optional)
   - Integration with monitoring
   - Scheduled operations

---

## Questions to Answer Before Proceeding

To finalize this plan, please provide the following information:

### About Your Current Setup

1. **How many nodes are in your MicroK8s cluster?**
   - Current count:
   - Expected growth:

2. **What are your node hostnames/IPs?**
   - Naming convention:
   - IP addressing scheme:
   - DNS or /etc/hosts?

3. **What hardware are the nodes running on?**
   - Raspberry Pi / x86_64 / VM / Physical servers:
   - Specs (CPU/RAM/Storage):

4. **Where will the Ansible control node run?**
   - Existing workstation:
   - New dedicated VM:
   - One of the cluster nodes:
   - Other:

5. **What is your network topology?**
   - Single flat network:
   - VLANs/subnets:
   - Switch capabilities:
   - Firewall in place:

### About Your Requirements

6. **What scripts do you want to convert first?**
   - High priority:
   - Medium priority:
   - Low priority / can skip:

7. **Do you have a staging/test environment?**
   - Yes, similar to production:
   - Yes, but limited:
   - No, will test in production carefully:

8. **What is your risk tolerance?**
   - Conservative (staging only, slow rollout):
   - Moderate (careful testing, phased approach):
   - Aggressive (move fast, accept some downtime risk):

9. **Who will maintain the Ansible code?**
   - You alone:
   - Small team (how many):
   - Team Ansible experience level:

10. **What are your automation goals?**
    - Replace manual scripts:
    - Add CI/CD integration:
    - Scheduled operations:
    - Self-healing capabilities:
    - Other:

---

## Reference Materials

### Ansible Resources
- [Ansible Documentation](https://docs.ansible.com/)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
- [Kubernetes Ansible Module](https://docs.ansible.com/ansible/latest/collections/kubernetes/core/index.html)

### MicroK8s Resources
- [MicroK8s Documentation](https://microk8s.io/docs)
- [MicroK8s Clustering](https://microk8s.io/docs/clustering)
- [MicroK8s Addons](https://microk8s.io/docs/addons)

### Network Planning
- [Kubernetes Networking Guide](https://kubernetes.io/docs/concepts/cluster-administration/networking/)
- [MicroK8s Networking](https://microk8s.io/docs/services-and-ports)

---

## Appendix: Sample Ansible Configuration

### ansible.cfg
```ini
[defaults]
inventory = ./inventory/production/hosts.yml
remote_user = root
host_key_checking = False
retry_files_enabled = False
gathering = smart
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts
fact_caching_timeout = 3600
stdout_callback = yaml
callbacks_enabled = profile_tasks, timer

[privilege_escalation]
become = False
become_method = sudo
become_user = root

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=no
pipelining = True
```

### Sample Group Variables
```yaml
# inventory/production/group_vars/microk8s_cluster.yml
---
microk8s_channel: "1.34/stable"
microk8s_enable_addons:
  - dns
  - ingress
  - storage
  - cert-manager

kubectl_context: microk8s

backup_path: /shared/microk8s/backup
manifest_path: /shared/microk8s/manifests

nfs_server: 192.168.30.1
nfs_path: /shared/microk8s
nfs_mount_point: /shared/microk8s

drain_timeout: 600
grace_period: 600
```

---

**Document Version:** 1.0
**Last Updated:** 2025-11-13
**Author:** Based on existing scripts in /shared/microk8s/scripts/
**Status:** Planning Phase
