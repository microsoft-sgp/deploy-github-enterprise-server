# Deploying GitHub Enterprise Server to Azure with Terraform (Azure Cloud Shell + Bash)

This repository provisions a **GitHub Enterprise Server (GHES)** instance on Microsoft Azure using Terraform. The Terraform state is stored remotely in an Azure Storage Account (blob backend).

> **This guide is written for [Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/overview) using the _Bash_ environment.** Azure Cloud Shell comes with the Azure CLI pre-installed and is already authenticated to your subscription, so no local tooling setup is required. All commands below are Bash commands — run them in the Cloud Shell **Bash** prompt.

The deployment is split into two Terraform workspaces:

| Folder | Purpose |
| --- | --- |
| [`azure-storage-blob-backend/`](azure-storage-blob-backend/) | Bootstraps the Storage Account used to hold the remote Terraform state. Run this **once**, first. |
| [`ghes/`](ghes/) | Provisions the GHES VM, networking, disks, and security rules. Uses the backend created above. |

---

## Architecture

The `ghes/` workspace creates:

- A resource group, virtual network, and subnet (`10.0.0.0/16` / `10.0.1.0/24`)
- A **Standard SKU** static public IP
- A network interface with an attached network security group (NSG)
- NSG rules for web/git traffic (`22, 25, 80, 443, 8080, 8443, 9418`) and admin SSH (`122`)
- A **Linux VM** running the GitHub Enterprise Server marketplace image (Gen2)
- A 200 GB premium OS disk and a separate 200 GB premium data disk

---

## Prerequisites

| Requirement | Version / Notes |
| --- | --- |
| [Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/overview) | **Bash** environment (this is the shell used throughout this guide) |
| [Terraform](https://developer.hashicorp.com/terraform/install) | `v1.15.6` |
| [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) | Pre-installed in Azure Cloud Shell |
| `azurerm` provider | `~> 4.0` (installed automatically by `terraform init`) |
| Azure subscription | Contributor rights to create resource groups, storage, networking, and VMs |
| SSH key pair | Public key supplied via the `ssh_public_key` variable |

> **Terraform version:** This guide targets **Terraform v1.15.6**. Azure Cloud Shell ships with Terraform pre-installed, but the bundled version may differ. Verify and, if needed, install the exact version as shown below.

> **GHES image / sizing:** Defaults to image SKU `github-enterprise-gen2`, version `3.21.1`, on a `Standard_D8s_v4` VM (8 vCPU / 32 GiB) to meet GHES 3.x minimum requirements.

---

## 1. Launch Azure Cloud Shell (Bash) and pin Terraform v1.15.6

Open [Azure Cloud Shell](https://shell.azure.com) and make sure the environment selector (top-left of the shell) is set to **Bash**.

Azure Cloud Shell is already signed in to your account. Select the target subscription:

```bash
az account set --subscription <SUBSCRIPTION_ID>
```

Export the subscription ID so the `azurerm` 4.x provider can pick it up (required):

```bash
export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
```

Verify (or install) **Terraform v1.15.6**:

```bash
# Check the installed version
terraform version

# If it is not v1.15.6, install that exact version into your Cloud Shell home directory
TF_VERSION="1.15.6"
curl -fsSL -o "terraform_${TF_VERSION}.zip" \
  "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip"
unzip -o "terraform_${TF_VERSION}.zip" -d "$HOME/bin"
export PATH="$HOME/bin:$PATH"

# Confirm
terraform version   # should report Terraform v1.15.6
```

See the [Azure CLI authentication guide](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/azure_cli) for service-principal and OIDC alternatives.

---

## 2. Create the Terraform state backend

This step creates the Storage Account that the GHES workspace uses for its remote state. It runs with **local** state. Run these commands in the Cloud Shell **Bash** prompt.

```bash
cd azure-storage-blob-backend
terraform init
terraform plan      # review the 3 resources to be created
terraform apply
```

After apply, note the outputs (`resource_group_name`, `storage_account_name`, `container_name`). They must match the `backend "azurerm"` block in [`ghes/main.tf`](ghes/main.tf):

```hcl
backend "azurerm" {
  resource_group_name  = "terraformbackend-resources"
  storage_account_name = "terraformbackendstoracct"
  container_name       = "terraformbackend-content"
  key                  = "terraform.tfstate"
  use_azuread_auth     = true
}
```

> If you change the `prefix` variable, update the backend block in `ghes/main.tf` accordingly.

---

## 3. Supply your own SSH public key (recommended)

> **Important:** The `ssh_public_key` variable in [`ghes/main.tf`](ghes/main.tf) ships with a **sample default key that belongs to someone else** (`yuichielectric@github.com`). If you deploy with that default you will **not** be able to SSH into the appliance's admin port (122), because you don't hold the matching private key. Always supply your **own** public key.

Generate a key pair in Azure Cloud Shell **Bash** (skip if you already have one):

```bash
ssh-keygen -t rsa -b 4096 -C "you@example.com" -f ~/.ssh/ghes_key
cat ~/.ssh/ghes_key.pub   # this is the public key to supply below
```

Then provide it to Terraform using **one** of the following (do not commit your key into the repo):

```bash
# Option A — pass at apply time (nothing stored in the repo)
terraform apply -var="ssh_public_key=$(cat ~/.ssh/ghes_key.pub)"

# Option B — environment variable
export TF_VAR_ssh_public_key="$(cat ~/.ssh/ghes_key.pub)"
terraform apply

# Option C — a terraform.tfvars file (keep it out of git)
echo "ssh_public_key = \"$(cat ~/.ssh/ghes_key.pub)\"" > terraform.tfvars
terraform apply
```

> **Best practice:** Consider removing the hardcoded `default` from the `ssh_public_key` variable so Terraform *requires* you to pass your own key and can never fall back to the sample. After connecting, verify with `ssh -p 122 admin@<public_ip>`.

---

## 4. Deploy GitHub Enterprise Server

```bash
cd ../ghes
terraform init     # connects to the remote backend created in step 2
terraform validate
terraform plan

# Deploy, supplying YOUR SSH public key (see step 3)
terraform apply -var="ssh_public_key=$(cat ~/.ssh/ghes_key.pub)"
```

When the apply completes, Terraform prints the `public_ip` output:

```text
Outputs:

public_ip = "20.x.x.x"
```

### Configurable variables

Override any of these via `-var`, a `*.tfvars` file, or environment variables (`TF_VAR_<name>`):

| Variable | Default | Description |
| --- | --- | --- |
| `prefix` | `ghes` | Name prefix for all resources |
| `location` | `japaneast` | Azure region |
| `ghes_version` | `3.21.1` | GHES marketplace image version |
| `image_sku` | `github-enterprise-gen2` | `github-enterprise-gen2` (Gen2) or `GitHub-Enterprise` (Gen1) |
| `vm_size` | `Standard_D8s_v4` | VM size (>= 8 vCPU / 32 GiB for GHES 3.x) |
| `admin_username` | `ghadmin` | VM admin user |
| `os_disk_size_gb` | `200` | Root OS disk size |
| `data_disk_size_gb` | `200` | GHES data disk size |
| `allowed_ssh_cidr` | `*` | CIDR allowed to reach admin SSH (port 122) — **restrict in production** |
| `ssh_public_key` | sample key (replace!) | SSH public key for VM access — **supply your own** (see step 3) |

Example:

```bash
terraform apply -var="location=eastus" -var="ghes_version=3.21.1" -var="allowed_ssh_cidr=203.0.113.0/24"
```

### Complete GHES setup

1. Open `https://<public_ip>` in a browser.
2. Upload your GitHub Enterprise license file and set the management console password.
3. Configure the instance (hostname, TLS, authentication) and let it restart.
4. Verify GitHub Actions, then register self-hosted runners against the new hostname.

---

## 5. Deploy with GitHub Actions (optional)

To deploy via CI/CD, fork this repository and create an Azure service principal (run in Cloud Shell **Bash**):

```bash
az ad sp create-for-rbac --name "ghes-terraform" --role Contributor \
  --scopes /subscriptions/<SUBSCRIPTION_ID>
```

Add the following repository **Actions secrets** (Settings -> Secrets and variables -> Actions):

| Secret name | Description |
| --- | --- |
| `ARM_CLIENT_ID` | Service principal client ID |
| `ARM_CLIENT_SECRET` | Service principal client secret |
| `ARM_SUBSCRIPTION_ID` | Subscription ID |
| `ARM_TENANT_ID` | Tenant ID |

Workflows:

- [`.github/workflows/pr.yml`](.github/workflows/pr.yml) — runs `fmt`, `init`, `validate`, and `plan` on pull requests.
- [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml) — runs `init` and `apply` on push to `main`/`master`.

Both workflows use `hashicorp/setup-terraform@v3` (pinned to Terraform `1.15.6`) and `actions/checkout@v4`.

> **Tip:** For improved security, replace the client-secret credentials with [OIDC federated credentials](https://learn.microsoft.com/azure/developer/github/connect-from-azure-openid-connect).

---

## 6. Maintenance

Run these in the Cloud Shell **Bash** prompt:

```bash
# Detect drift
terraform plan -detailed-exitcode

# Show the current public IP
terraform output public_ip

# Tear down (destroys the GHES instance — back up first)
terraform destroy
```

### GHES upgrade notes

- GHES supports skipping at most ~2 feature releases per upgrade hop. To move an existing appliance to `3.21.x`, upgrade **sequentially** (e.g. `2.20 -> 2.22 -> 3.0 -> ... -> 3.21`) using the appliance upgrade/hotpatch packages — you cannot jump the running appliance directly.
- Re-provisioning with a new `ghes_version` on this Terraform config replaces the VM; back up first with `ghe-backup`/`ghe-restore`.
- Always take a backup and snapshot the data disk before any upgrade.
