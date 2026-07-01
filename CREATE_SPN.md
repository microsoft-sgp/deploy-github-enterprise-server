
# Azure SHELL Bash Command

SUB_ID=<yoursubid>
TENANT_ID=<yourtenantid>

# Create SPN
az ad sp create-for-rbac \
  --name spn-ghes \
  --role Contributor \
  --scopes /subscriptions/${SUB_ID}

# Login using SPN (from your environment - github pipeline)

SUB_ID=<yoursubid>
TENANT_ID=<yourtenantid>
APP_ID=<yourappid>
CLIENT_SECRET=<yourpassword>

az login --service-principal \
  --username ${APP_ID} \
  --password ${CLIENT_SECRET} \
  --tenant ${TENANT_ID}

# Set subscription
az account set --subscription ${SUB_ID}

# Test
az group list

