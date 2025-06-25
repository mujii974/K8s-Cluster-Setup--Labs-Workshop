# Kubernetes Cluster Setup and Certification Labs Workshop


---
In this workshop, we will first set up the Kubernetes cluster and then move on to practical tasks, covering a range of topics included in the CKA (Certified Kubernetes Administrator), CKAD (Certified Kubernetes Application Developer), and CKS (Certified Kubernetes Security Specialist) certification labs.
If you want to see all the commands I run on my master cluster then all the history is captured in "logs" folder.

## Note!
Each heading has its own folder. Inside each folder, you'll find all the steps and commands needed. Follow the markdown files in each folder in numeric order to complete the workshop.
## (A).Prerequisites

1. **System Requirements:**
   - **Host system:** 6-core CPU, 16GB RAM
   - **Hypervisor:** Hyper-V
   - **Guest VMs:**
     - 1 Master Node (e.g., 192.168.100.34)
     - 2 Worker Nodes (e.g., 192.168.100.35, 192.168.100.36)
     - Ubuntu 20.04 installed on all nodes

2. **Network Configuration:**
   - Static IPs assigned to all VMs.
   - Ensure inter-node communication using `ping`.

3. **Required Tools Installed on Each Node:**
   - `openssh-server`
   - `kubeadm`
   - `kubelet`
   - `kubectl`
   - `containerd` (as the container runtime)

4. **Optional:** Install `helm` on master node (if using Helm charts).

---

