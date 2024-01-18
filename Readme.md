# Private PHP packagist & Proxy in azure
## Repman
- Private PHP Package Repository Manager. [Docs](https://repman.io/docs/)
## Intro
I know Azure can be scary but trust me it will be just OKAY. Steps marked with `?` are optional and may not be needed if azure env. is already prepared  
<img src="./start.jpg" alt="alt text" width="300"/></br>

## Step 0 - Some helper variables
```sh
RESOURCE_GROUP=rempanGroup
DOCKER_REGISTRY_NAME=rempanregistry
LOCATION=eastus
SERVICE_PRINCIPAL_NAME=repmansp
STORAGE_ACCOUNT_NAME=repmanStorage
STORAGE_SHARE_NAME="repmanStorageShare"
```
## Step 1 - Azure resources
### ?Resource group
```sh
az group create --name $RESOURCE_GROUP --location $LOCATION
```
### ?Container registry
```sh
$DOCKER_REGISTRY_NAME=rempanregistry;
```
Create registry:
```sh
az acr create --resource-group $RESOURCE_GROUP --name $DOCKER_REGISTRY_NAME --sku Basic
```
Get registry id:
```sh
ACR_REGISTRY_ID=$(az acr show --name $DOCKER_REGISTRY_NAME --query "id" --output tsv)
```
### ?Service principal
Create principal and print password, don't forget to save it you may need to later ;-)
```sh
SP_PASSWORD=$(az ad sp create-for-rbac --name $SERVICE_PRINCIPAL_NAME --scopes $ACR_REGISTRY_ID --role acrpull --query "password" --output tsv)
```
Get s. principal id
```sh
SP_USER_NAME=$(az ad sp list --display-name $SERVICE_PRINCIPAL_NAME --query "[].appId" --output tsv)
```
### ?Azure storage
Create storage account
```sh
az storage account create \
  --resource-group $RESOURCE_GROUP \
  --name $STORAGE_ACCOUNT_NAME \
  --location "$LOCATION" \
  --kind StorageV2 \
  --sku Standard_LRS \
  --enable-large-file-share \
  --query provisioningState
```
Create azureFile with 10GB capacity
```sh
az storage share-rm create \
  --resource-group $RESOURCE_GROUP \
  --storage-account $STORAGE_ACCOUNT_NAME \
  --name $STORAGE_SHARE_NAME \
  --quota 10 \
  --enabled-protocols SMB \
  --output table
```
Get storage account key which is needed for auth later in process ;-)
```sh
STORAGE_ACCOUNT_KEY=`az storage account keys list -n $STORAGE_ACCOUNT_NAME --query "[0].value" -o tsv`
```
## Step 2 - Local resources
### Docker images
Build
```sh
docker build -f Dockerfile.app -t <some amazing tag> .
docker build -f Dockerfile.nginx -t <some amazing tag2> .
```
Login to azure container registry and push images
```sh
az acr login --name $DOCKER_REGISTRY_NAME
docker push <some amazing tag>
docker push <some amazing tag2>
```
or if you don't like azure cli magic, you can use docker login
```sh
docker login $DOCKER_REGISTRY_NAME.azurecr.io --username $SP_USER_NAME --password $SP_PASSWORD
docker push <some amazing tag>
docker push <some amazing tag2>
```
### Adjust `repman-azure.yaml` file
Image registry configuration
```yaml
...
  imageRegistryCredentials: # Credentials to pull a private image
  - server: $DOCKER_REGISTRY_NAME.azurecr.io
    username: $SP_USER_NAME
    password: $SP_PASSWORD
...
```
Images sources
```yaml
...
  - name: app
    properties:
      image: $DOCKER_REGISTRY_NAME.azurecr.io/<some amazing tag>
...
  - name: nginx
    properties:
      image: $DOCKER_REGISTRY_NAME.azurecr.io/<some amazing tag2>
...
```
Group volume definition
```yaml
...
  volumes:
  - name: repmanprivatepackages
    azureFile:
      shareName: $STORAGE_SHARE_NAME
      storageAccountName: $STORAGE_ACCOUNT_NAME
      storageAccountKey: $STORAGE_ACCOUNT_KEY
  - name: repmanproxypackages
    azureFile:
      shareName: $STORAGE_SHARE_NAME
      storageAccountName: $STORAGE_ACCOUNT_NAME
      storageAccountKey: $STORAGE_ACCOUNT_KEY
...
```
Adjust repman envs. if needed. [Docs](https://repman.io/docs/standalone/'#envdocker)
```yaml
...
      environmentVariables: &app_envs
          - name: PHP_URL
            value: localhost:9000
          - name: APP_HOST
...
```
## Step 3 - Deplooooy
```sh
az container create --resource-group $RESOURCE_GROUP --file repman-azure.yaml
```
If something went wrong you adjust conf. files and just call same cmd again, it may be named `create` but it updates too :-)  
But if something went terribly wrong you can delete container group and start again. I tried it numerous times and it works trust me:
```sh
az container delete --resource-group $RESOURCE_GROUP --name repman
```

### ?Setup Repman
If you properly set `MAILER_*` repman should be ready. If not create admin user manually:
```sh
az container exec -g $RESOURCE_GROUP --name repman --container-name app --exec-command "bin/console -n repman:create:admin <admin email> <super secure password>"
```

### Success 
If you are reading this you have set up everything properly or you suck at following the best step by step tutorial :-D. Whatever is true, here is command to show public ip of containers:
```sh
az container show --resource-group $RESOURCE_GROUP --name repman --output table
```
You should get something like:
```
Name       ResourceGroup    Status    Image                                                                                                              IP:ports              Network    CPU/Memory       OsType    Location
---------  ---------------  --------  -----------------------------------------------------------------------------------------------------------------  --------------------  ---------  ---------------  --------  ----------
repman-v3  repman           Running   repmanreg.azurecr.io/repman-app,postgres:11.20-alpine,buddy/repman:1.3.4,repmanreg.azurecr.io/repman-nginx:latest  20.62.239.191:80,443  Public     1.0 core/1.5 gb  Linux     eastus
```
<img src="./success-01.jpg" alt="alt text" width="300"/></br>

## Notes
- If something does not work as you would expect use `docker-compose.yml` and test it localy first ;-)
- If there is any problem with `az` cmds, you can use web ui but god help you to find everything you need
- Tutorial is written for azure container mostly because I wanted to try it but `repman-azure.yaml` can be very easily converted into kubernetes definitions or it could be deployed even in VM as last option (as VM needs to maintained, containers are almost care free)
- resources in configuration are just best guess, it should be adjusted 
- conf. file is missing readiness/liveness probes

<img src="./success.jpg" alt="alt text" width="300"/></br>
