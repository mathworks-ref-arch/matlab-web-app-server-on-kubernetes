<!-- Copyright 2025-2026 The MathWorks, Inc. -->
# MATLAB Web App Server in Kubernetes

## Introduction

This guide helps you automate the process of running MATLAB® Web App
Server™ in a Kubernetes® cluster by using a Helm® chart. The chart is a collection of YAML
files that define the resources you need to deploy MATLAB Web App
Server in Kubernetes. After you deploy the server, you can manage it by using
the `kubectl` command-line tool.

For more information about MATLAB Web App Server, see the [MATLAB Web App Server documentation](https://www.mathworks.com/help/webappserver).

For more information about Kubernetes, see the [Kubernetes documentation](https://kubernetes.io/docs/home/).

One installation of the chart creates two pod types. The server pods accept the client connections and hold the web apps. The worker pods run the web app sessions, and each worker pod holds one MATLAB Runtime release. For a description of every object that the chart creates, see [Architecture of MATLAB Web App Server in Kubernetes](architecture.md).

## Requirements
Before starting, you need the following:

*   MATLAB Web App Server license that meets the following condition:
    * Configured to use a network license manager. The license manager must be accessible from the Kubernetes cluster where you deploy MATLAB Web App Server but must not be installed in the cluster. The cluster must be able to reach the license manager on TCP ports 27000 to 27010. For more information, see [Configure Network License Manager Ports](#configure-network-license-manager-ports).
*  Network access to the MathWorks container registry, `containers.mathworks.com`.    
* Container registry that all nodes in your Kubernetes cluster can pull from. You must push the MATLAB Web App Server and MATLAB Runtime container images to this registry. For more information, see [Push Container Images to Your Registry](#push-container-images-to-your-registry).
* SSL certificate and private key for the server. For more information, see [Add SSL Certificate and Private Key](#add-ssl-certificate-and-private-key).
* [Git™](https://git-scm.com/)
* [Docker®](https://www.docker.com/)
* Running [Kubernetes](https://kubernetes.io/) cluster that meets the following conditions: 
    * Uses Kubernetes version 1.30 or later.
    * Has at least 2 CPU cores and 4 GiB RAM. This figure is the minimum for a single-node cluster. For the resource limits that the Helm chart applies to each pod, see [Update Server Configuration Properties](#update-server-configuration-properties).
* [kubectl](https://kubernetes.io/docs/reference/kubectl/overview/) command-line tool that can access your Kubernetes cluster
* [Helm](https://helm.sh/) package manager to install Helm charts that contain preconfigured Kubernetes resources for MATLAB Web App Server
    * Uses Helm version v3.15 or later.

If you do not have a license, contact your MathWorks representative [here](https://www.mathworks.com/company/aboutus/contact_us/contact_sales.html) or [request a trial license](https://www.mathworks.com/campaigns/products/trials.html?prodcode=MW). 

## Deployment Steps

Do these steps in the order that follows. Every deployment needs them. When you complete them, the cluster serves a web app.

1. [Clone GitHub® Repository That Contains Helm Chart](#clone-github-repository-that-contains-helm-chart)
2. [Pull Container Images for MATLAB Web App Server and MATLAB Runtime](#pull-container-images-for-matlab-web-app-server-and-matlab-runtime)
3. [Push Container Images to Your Registry](#push-container-images-to-your-registry)
4. [Configure Your Deployment](#configure-your-deployment)
5. [Provide Mapping for Web Apps](#provide-mapping-for-web-apps)
6. [Provide Mapping for Server Init Data](#provide-mapping-for-server-init-data)
7. [Add SSL Certificate and Private Key](#add-ssl-certificate-and-private-key)
8. [Install Helm Chart](#install-helm-chart)
9. [Upload Web App](#upload-web-app)
10. [Enable External Access](#enable-external-access)
11. [Verification](#verification)

These steps use the default location for the server log, the MATLAB Runtime, and the server code. To change a location, or to change how the server behaves, see [Additional Configuration](#additional-configuration).

### Clone GitHub® Repository That Contains Helm Chart
The MATLAB Web App Server on Kubernetes GitHub repository contains a Helm chart that refers to Ubuntu-based container images for MATLAB Web App Server deployment.

1. Clone the MATLAB Web App Server on Kubernetes GitHub repository to your machine.
    ```
    git clone https://github.com/mathworks-ref-arch/matlab-web-app-server-on-kubernetes.git
    ```
    This repository includes a Helm chart folder for the MATLAB Web App Server release and a `values-overrides.yaml` file that contains the configuration options that you must override. To set more options, copy them from the `chart/values.yaml` file into this file.

2. Navigate to the repository folder. The commands in this guide use this folder as the current folder.
    ```
    cd matlab-web-app-server-on-kubernetes
    ```
    The `chart` folder contains these two files that together define the Helm chart used to deploy MATLAB Web App Server.
    * `Chart.yaml` &mdash; contains metadata about the Helm chart.
    * `values.yaml` &mdash; contains the full set of configuration options available for this release of the chart.

    The `chart` folder also contains these three folders.
    * `templates` &mdash; contains the definitions of the Kubernetes resources that the chart creates.
    * `security` &mdash; contains the AppArmor and seccomp profiles.
    * `settings` &mdash; contains the `webapps.config` server configuration file and the `webapps_private` folder. Put your server configuration files and your SSL certificate in the `webapps_private` folder.

### Pull Container Images for MATLAB Web App Server and MATLAB Runtime
**Note:** MATLAB Runtime R2025a or later is required.
1. Pull the container image for MATLAB Web App Server to your machine.

    ```
    docker pull containers.mathworks.com/matlab-web-app-server:<release-tag>
    ```
    * `containers.mathworks.com` is the name of the container registry.
    * `matlab-web-app-server` is the name of the image.
    * `<release-tag>` is the tag name of the MATLAB Web App Server release, for example, `r2026b`.

    The `values.yaml` file specifies the image name and the tag in the `images` section, in the `serverName` and `serverTag` variables. By default, the `serverName` variable holds the image name without a registry name. For more information, see [Push Container Images to Your Registry](#push-container-images-to-your-registry). If the server release that you pull is not the same as the release of the chart, add the value to the `serverRelease` variable. 

2. Pull the container image for the MATLAB Runtime to your machine.

    ```
    docker pull containers.mathworks.com/matlab-runtime:<release-tag>
    ```
    * `containers.mathworks.com` is the name of the container registry.
    * `<release-tag>` is the tag name of the MATLAB Runtime release. Update this value to the release of the MATLAB Runtime that you use, for example, `r2026b`.

    **Note:** Starting with R2025a, MATLAB Web App Server supports the current MATLAB Runtime plus the six previous releases.

    Tag the downloaded image with the name that the Helm chart requires. This name depends on the `volumes.runtimes.mountType` setting.

    | `volumes.runtimes.mountType` | Image Name That the Chart Uses | Reason |
    |------------------------------|--------------------------------|--------|
    | `embedded` (default) | `mw-webapps-worker-k8s-[MATLAB Runtime release]:[MATLAB Web App Server release]` | The MATLAB Runtime is part of the image. One server release can use MATLAB Runtime images with different update numbers. The release suffix keeps these images apart. |
    | `hostpath`, `nfs` | `mw-webapps-worker-k8s:[MATLAB Web App Server release]` | The chart cannot identify the MATLAB Runtime release when it renders. The server reads the release from the mounted file system. The tag is the server release. |

    For the default `embedded` mount type, use `r2026b` for both releases:
    
    ```
    docker tag containers.mathworks.com/matlab-runtime:r2026b mw-webapps-worker-k8s-r2026b:r2026b
    ```

    The `values.yaml` file specifies the image name and the tag in the `images` section, in the `workerName` and `workerTag` variables. For the `embedded` mount type, the chart adds the release suffix to the `workerName` value. For more information about the `volumes.runtimes` setting, see [Provide Mapping for MATLAB Runtime](#provide-mapping-for-matlab-runtime).

**Note:** The MATLAB Web App Server and MATLAB Runtime container images use MathWorks approved base images with dependencies that undergo CVE scanning.

### Push Container Images to Your Registry
A `docker pull` command puts an image in the local Docker store of one machine. The nodes of your Kubernetes cluster do not share that store. Push both images to a container registry that all nodes in the cluster can reach.

1. Tag both images for your registry.

    ```
    docker tag matlab-web-app-server:r2026b <your-registry>/matlab-web-app-server:r2026b
    docker tag mw-webapps-worker-k8s-r2026b:r2026b <your-registry>/mw-webapps-worker-k8s-r2026b:r2026b
    ```

2. Push both images.

    ```
    docker push <your-registry>/matlab-web-app-server:r2026b
    docker push <your-registry>/mw-webapps-worker-k8s-r2026b:r2026b
    ```

3. In the `values-overrides.yaml` file, set these variables in the `images` section.

    * Set `serverName` to `<your-registry>/matlab-web-app-server`.
    * Set `workerName` to `<your-registry>/mw-webapps-worker-k8s`.
    * Set `pullSecretName` to the name of the Kubernetes Secret that holds the credentials for your registry.

By default, the `images.serverName` variable holds no registry name. This default stops a cluster from pulling the image from `containers.mathworks.com` each time a pod starts. Repeated pulls put an unnecessary load on the MathWorks servers.

**Note:** If a node does not already hold an image, and the image name has no registry name, the pod reports `ImagePullBackOff`.

### Configure Your Deployment
The `chart/values.yaml` file holds every setting that the chart supports, and it has a comment for each one. Use this file as the reference for the settings and the values that each one accepts. Do not edit it.

Put your own settings in the top-level `values-overrides.yaml` file. Copy from `chart/values.yaml` only the settings that you change, then set your values. Helm merges the two files. Helm takes every setting that `values-overrides.yaml` does not name from `chart/values.yaml`.

A partial section is a valid override. For example, if `values-overrides.yaml` sets only `volumes.apps.mountType`, the chart still takes the `volumes.apps.size` value from `chart/values.yaml`. You do not need to copy a complete section.

The steps that follow describe the settings that a first deployment needs. For a complete example file, see [Install Helm Chart](#install-helm-chart). To change the behavior of the server after the deployment works, see [Update Server Configuration Properties](#update-server-configuration-properties).

**Note:** If a setting name is misspelled, Helm ignores it and reports no error. The deployment then uses the default value. Check each setting name against `chart/values.yaml`.

### Provide Mapping for Web Apps
Provide a mapping from the location where you store your web apps (`.ctf` files) to a storage resource in your cluster. You can store the web apps on the network file system, on the host node file system, in Azure File Share, or in a PersistentVolumeClaim that you create before the installation. 

To specify the storage location for storing web apps, under `volumes.apps`, set the following variables:

| Parameter     | Mount Type        | Description |
|---------------|-------------------|-------------|
| `mountType`   | All               | Specify the mount type. Options are `"hostpath"`, `"nfs"`, `"pvc"`, or `"azurefileshare"`. |
| `size`        | All               | Specify the size of the volume. The default is `100Mi`. This volume needs room for every `.ctf` file that the cluster serves. |
| `server`      | `nfs`             | Specify the hostname of your NFS server. |
| `path`        | `nfs`             | Specify the location of your web apps on the NFS server. |
| `hostpath`    | `hostpath`        | Specify the location of your web apps on the host node. |
| `shareName`   | `azurefileshare`  | Specify the Azure storage account file share name. |
| `secretName`  | `azurefileshare`  | Specify the Azure storage account key secret name. |
| `claimName`   | `pvc`             | Specify the name of the pre-created PVC in the same namespace. |
| `readOnly`    | `nfs`, `azurefileshare` | The default is `false`, which lets users upload web apps from the **Manage Apps** page. Set it to `true` to prevent uploads. For `hostpath` mounts, file system permissions control write access. |


For a `hostpath` mount, create this directory before you install the chart. Create it on each node that can run a server pod. The PersistentVolume that the chart creates uses `type: Directory`, so the pod stays in the `ContainerCreating` state if the directory does not exist. Use the absolute path that you set in `volumes.apps.hostpath`.

Create the directory and set the permissions on the file system as follows:

```
sudo mkdir -p /srv/webapps/apps
sudo chmod 770 /srv/webapps/apps
sudo chown root:1462 /srv/webapps/apps
```
These permissions let the server account upload web apps. The server account uses group ID 1462. The container image creates the account with a group ID that is equal to its user ID, which is the `internal.webappsServerUserId` value in the `chart/values.yaml` file. If you change that value, change the group ID in these commands and in the commands for the init volume and the logs volume.

### Provide Mapping for Server Init Data
MATLAB Web App Server requires a data volume for communication with workers. This volume must be writable by the server pod and readable by all worker pods. 

To specify the storage location for the server init data, under `volumes.init`, set the following variables:

| Parameter     | Mount Type        | Description |
|---------------|-------------------|-------------|
| `mountType`   | All               | Specify the mount type. Options are `"hostpath"`, `"nfs"`, `"pvc"`, or `"azurefileshare"`. |
| `size`        | All               | Specify the size of the volume. The default is `100Mi`. |
| `server`      | `nfs`             | Specify the hostname of your NFS server. |
| `path`        | `nfs`             | Specify the location of your files on the NFS server. |
| `hostpath`    | `hostpath`        | Specify the location of your files on the host node. |
| `shareName`   | `azurefileshare`  | Specify the Azure storage account file share name. |
| `secretName`  | `azurefileshare`  | Specify the Azure storage account key secret name. |
| `claimName`   | `pvc`             | Specify the name of the pre-created PVC in the same namespace. | 

For more information about the Kubernetes volume mount options, see [Volumes](https://kubernetes.io/docs/concepts/storage/volumes/) in the Kubernetes documentation.

For a `hostpath` mount, create this directory before you install the chart. Create it on each node that can run a server pod or a worker pod. Both pod types mount this volume.

Create the directory and set the permissions on the file system as follows:

```
sudo mkdir -p /srv/webapps/init
sudo chmod 771 /srv/webapps/init
sudo chown root:1462 /srv/webapps/init
```
Mode 771 lets the worker account open known files in this directory. It stops the worker account from listing the contents of the directory. 

### Add SSL Certificate and Private Key
MATLAB Web App Server in Kubernetes always uses SSL. Put an SSL certificate and a private key in place before you install the Helm chart. The server does not start without these two files.

1. Copy your certificate and your private key into the `chart/settings/webapps_private` folder of your clone. Use these file names.

    * `webapps_cert.pem` &mdash; the SSL certificate
    * `webapps_key.pem` &mdash; the private key

2. Confirm that both files are in the folder before you continue.

The Helm chart builds a Kubernetes TLS Secret from these two files. The chart also mounts the certificate into every worker pod.

**Note:** If these files are absent, the Helm chart creates an empty TLS Secret and the installation reports no error. The server pod then never reaches the **Ready** state.

### Install Helm Chart
The Helm chart is located in the `/chart` directory of this repository. Use the [helm install](https://helm.sh/docs/helm/helm_install/) command to deploy your desired release. Install the chart in a dedicated namespace. For more information on managing namespaces, see the Kubernetes documentation on [Share a Cluster with Namespaces](https://kubernetes.io/docs/tasks/administer-cluster/namespaces/).

Before installing the chart, first set parameters that state your agreement to the MathWorks cloud reference architecture license and specify the address of the network license manager. In the top-level `values-overrides.yaml` file, set these parameters:

- To accept the license terms, set `global` > `agreeToLicense` to `"yes"`.
- To specify the address of the license server, set `global` > `licenseServer` using the format `port_number@host`. The server pods must reach the license manager on both of its ports. For more information, see [Configure Network License Manager Ports](#configure-network-license-manager-ports).

This example shows a complete `values-overrides.yaml` file for a cluster that uses a private registry, an NGINX Ingress controller, and `hostpath` volumes. The file overrides only the settings that it names. Helm takes every other setting from the `chart/values.yaml` file.

```yaml
global:
  agreeToLicense: "yes"
  licenseServer: "27000@licenseserver.example.com"

images:
  serverName: myregistry.example.com/matlab-web-app-server
  workerName: myregistry.example.com/mw-webapps-worker-k8s
  pullSecretName: myregistry-credentials

ingressController:
  class: nginx
  hostName: webapps.example.com

volumes:
  apps:
    mountType: "hostpath"
    hostpath: "/srv/webapps/apps"
  init:
    mountType: "hostpath"
    hostpath: "/srv/webapps/init"
```

Create the namespace before you install the chart. If the namespace does not exist, the installation stops and reports an error. As an alternative, add the `--create-namespace` option to the `helm install` command.

```
kubectl create namespace <k8s-namespace>
```

Then, install the Helm chart for MATLAB Web App Server by using the `helm install` command:

```
helm install [<release_name> | --generate-name] -f <path/to/values-overrides.yaml> [-n <k8s-namespace>] <path/to/chart directory>
```

You can use the [kubectl get pods](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#get) command to confirm that MATLAB Web App Server is running. Each `kubectl` and `helm` command needs the `-n <k8s-namespace>` option, unless the namespace is the current default for your context.

```
kubectl get pods -n <k8s-namespace>
```

### Upload Web App
After the deployment is complete, upload your applications to the apps volume. Alternatively, if the feature is enabled, you can upload applications directly through the **Manage Apps** page.

**Note:** CLI tools, including tools for running web apps in Docker containers, are not supported in Kubernetes deployments. To deploy web apps to a Kubernetes cluster, compile your apps using MATLAB Compiler on a separate machine and upload the resulting `.ctf` files to the apps volume.

### Enable External Access

By default, your cluster is not accessible from outside. To give external access, enable the Ingress controller, the app gateway, or the load balancer, or use the [port-forward kubectl feature](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#port-forward) to forward the traffic to the MATLAB Web App Server service. 

To enable the [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) controller, set `ingressController.class` in your `values-overrides.yaml` file. Also set an `ingressController.hostName` value, which is the host name that clients use to reach the web apps cluster. On a single machine, the `hostname -f` command gives this value. The Ingress controller also functions as a load balancer. 

MathWorks tested this solution with these ingress controllers and load balancers: `nginx`, `webapprouting.kubernetes.azure.com`, `azure-application-gateway`, and `alb`. Set `ingressController.class` to the value that matches your controller. For the settings that each one accepts, see the `chart/values.yaml` file. 

If your cluster runs on a managed platform, use the Ingress class of that platform. For Azure Kubernetes Service, use `webapprouting.kubernetes.azure.com` or `azure-application-gateway`. For Amazon Elastic Kubernetes Service, use `alb`. Use `nginx` when no platform class applies, such as on a cluster that you manage yourself.

**Note:** The NGINX Ingress Controller project is retiring. Examples in this guide use the `nginx` class because it works on any cluster.

To use port forwarding, use the `kubectl port-forward` command. This example maps the default internal port 9999 to external port 9989. Clients from any IP address can then access the svc/webapps-server-service service from outside the cluster by connecting to port 9989:

```
kubectl port-forward --address 0.0.0.0 --namespace=<k8s-namespace> svc/webapps-server-service 9989:9999 &
```

Then, test the server connection by using a curl command like 

```
curl -vk https://localhost:9989/webapps/ready
```

The `--address 0.0.0.0` option makes the forwarded port available on the machine that runs `kubectl`. Run this curl command on that machine, or replace `localhost` with the host name of that machine.

On success, the server returns HTTP code 200:

```
HTTP/1.1 200 OK
```

### Verification
To verify that the Helm release was deployed successfully, use the [helm list](https://helm.sh/docs/helm/helm_list/) command.

```
helm list -n <k8s-namespace>
```

You can also use the [kubectl get pods](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#get) command to confirm that the MATLAB Web App Server pods (`webapps-*` and `webapps-worker-*`) are in a **Ready** state and that their status is **Running**.

```
kubectl get pods -n <k8s-namespace>
```

After you enable external access, open the MATLAB Web App Server home page in a browser. If you use an Ingress controller, the address is:

```
https://<ingressController.hostName>/webapps/home/
```

If you set the `ingressController.path` value to a context root, the address includes that context root. If you use port forwarding instead, the address uses the host and the external port from the `kubectl port-forward` command, for example `https://<host>:9989/webapps/home/`.

## Additional Configuration

The deployment works without the changes in this section. Read a section only when its condition applies to your cluster.

| Section | Read it when |
|---------|--------------|
| [Provide Mapping for Logs](#provide-mapping-for-logs) | You want the server to write its log to a file instead of to the pod log. |
| [Provide Mapping for MATLAB Runtime](#provide-mapping-for-matlab-runtime) | You want the MATLAB Runtime to come from a file system instead of from the worker container image. |
| [Provide Mapping for Server Code](#provide-mapping-for-server-code) | You want the server code to come from a file system instead of from the server container image. |
| [Configure Multiple MATLAB Runtime Versions](#configure-multiple-matlab-runtime-versions) | Your web apps need more than one MATLAB Runtime release. |
| [Network Access for Web Apps](#network-access-for-web-apps) | A web app must reach a database, a REST API, or another resource outside the cluster. |
| [Update Server Configuration Properties](#update-server-configuration-properties) | You change a server setting, such as the number of server pods or the session limit. |

To change a mount type after the cluster runs, you must uninstall and reinstall the release. To change a server setting, use the `helm upgrade` command. For more information, see [Update Server Configuration Properties](#update-server-configuration-properties).

### Provide Mapping for Logs
By default, the `webAppServerSettings.serverLogsDest` value is `console`, so the server writes its logs to the pod log and this volume is not needed. After the server starts, access logs using `kubectl logs -n <k8s-namespace> webapps-0` or a similar command. You can also configure the server to store logs in a persistent volume. Each server instance stores logs in its own subdirectory, and the volume must be writable by the server pod. 

To specify the storage location for storing logs, under `volumes.logs`, set the following variables:

| Parameter     | Mount Type        | Description |
|---------------|-------------------|-------------|
| `mountType`   | All               | Specify the mount type. Options are `"none"` (default), `"hostpath"`, `"nfs"`, `"pvc"`, or `"azurefileshare"`. |
| `size`        | All               | Specify the size of the volume. The default is `100Mi`. |
| `server`      | `nfs`             | Specify the hostname of your NFS server. |
| `path`        | `nfs`             | Specify the location of your files on the NFS server. |
| `hostpath`    | `hostpath`        | Specify the location of your files on the host node. |
| `shareName`   | `azurefileshare`  | Specify the Azure storage account file share name. |
| `secretName`  | `azurefileshare`  | Specify the Azure storage account key secret name. |
| `claimName`   | `pvc`             | Specify the name of the pre-created PVC in the same namespace. |
 

If you set the `webAppServerSettings.serverLogsDest` value to `file`, you must set a mount type for this volume. If you do not, the installation stops and reports `Logs volume needs to be mounted for serverLogsDest=file`.

For a `hostpath` mount, create this directory before you install the chart. Create it on each node that can run a server pod or a worker pod.

Create the directory and set the permissions on the file system as follows:

```
sudo mkdir -p /srv/webapps/logs
sudo chmod 770 /srv/webapps/logs
sudo chown root:1462 /srv/webapps/logs
```
Mode 770 gives write access to the server account only. This restriction is deliberate. Worker pods do not write their logs to this volume. The server collects the worker logs from the worker pods through the Kubernetes API.

**Note:** If you set the `webAppServerSettings.workerDiagnosticSpec` value, the worker account writes diagnostic output to this directory and needs write access to it. Widen the permissions while you collect diagnostics, then restore mode 770. 

### Provide Mapping for MATLAB Runtime
By default, each worker container image holds one MATLAB Runtime installation. You can instead read the MATLAB Runtime from a file system outside the container.

To specify where the MATLAB Runtime comes from, under `volumes.runtimes`, set the following variables:

| Parameter     | Mount Type        | Description |
|---------------|-------------------|-------------|
| `mountType`   | All               | Specify where the MATLAB Runtime comes from. Options are `"embedded"` (default), `"hostpath"`, or `"nfs"`. |
| `server`      | `nfs`             | Specify the hostname of your NFS server. |
| `path`        | `nfs`             | Specify the location of the MATLAB Runtime installations on the NFS server. |
| `hostpath`    | `hostpath`        | Specify the location of the MATLAB Runtime installations on the host node. |

For the `embedded` option, the MATLAB Runtime comes from the worker container image. For the `hostpath` and `nfs` options, all MATLAB Runtime installations must come from the same location. That location must hold one subdirectory for each release, and each subdirectory name must match a `release` value in the `matlabRuntimes` array.

This setting also decides which worker image name the Helm chart uses. For more information, see [Pull Container Images for MATLAB Web App Server and MATLAB Runtime](#pull-container-images-for-matlab-web-app-server-and-matlab-runtime).

### Provide Mapping for Server Code
By default, the MATLAB Web App Server code is part of the server container image. You can instead read the server code from a file system outside the container. Use this option to debug the server, or to control the server installation separately from the container image.

To specify where the server code comes from, under `volumes.server`, set the following variables:

| Parameter     | Mount Type        | Description |
|---------------|-------------------|-------------|
| `mountType`   | All               | Specify where the server code comes from. Options are `"embedded"` (default), `"hostpath"`, or `"nfs"`. |
| `server`      | `nfs`             | Specify the hostname of your NFS server. |
| `path`        | `nfs`             | Specify the location of the server installation on the NFS server. |
| `hostpath`    | `hostpath`        | Specify the location of the server installation on the host node. |

For the `embedded` option, the server code comes from the `/webapps/server` directory of the container image. For the `hostpath` and `nfs` options, the location must hold an installed MATLAB Web App Server.

### Configure Multiple MATLAB Runtime Versions
**Note:** MATLAB Runtime R2025a or later is required.

The `matlabRuntimes` array lists the MATLAB Runtime versions that the cluster uses. The `chart/values.yaml` file ships one entry.

```yaml
matlabRuntimes:
  - numPrewarmedWorkers: 2
    release: R2026b
    embeddedImageTag:
```

To use more than one version, add an entry for each version. Each entry takes these options.

* `numPrewarmedWorkers` &mdash; Specify the number of idle sessions to keep for this MATLAB Runtime version.
* `release` &mdash; Specify the MATLAB release name, for example `R2026b`. For the `nfs` and `hostpath` mount types, this value must match the name of the runtime subdirectory. Use the same capitalization as the subdirectory name. The chart lowercases this value for container image names and for `resourceQuota` keys.
* `embeddedImageTag` &mdash; Specify the custom tag of the embedded image. Leave this option empty to use the default tag.

Add a `resourceQuota` entry for each version that you add. Name the entry `webapps-worker-<release>`, in lowercase, for example `webapps-worker-r2025b`. If the entry is missing, the chart creates the worker Deployment with no CPU or memory limit and reports no error. In a namespace that enforces a LimitRange, the cluster rejects that pod.


### Network Access for Web Apps
The Helm chart applies two NetworkPolicy objects by default, one for the server pods and one for the worker pods. These policies restrict outbound network traffic. To turn a policy off, set `security.networkPolicy.server.enabled` or `security.networkPolicy.workers.enabled` to `false`.

A worker pod runs your web app. By default, a worker pod can reach only these destinations:

| Destination      | Port           | Purpose |
|------------------|----------------|---------|
| Any              | TCP 9999       | The server service |
| Server pods only | TCP 9988       | The server main port |
| Server pods only | TCP 27185      | The worker release handshake |
| Any              | TCP and UDP 53 | DNS |

A web app that reads a database, calls a REST API, or reaches the internet cannot connect until you allow the port. The cluster deploys without an error and the pods reach the **Ready** state, but the outbound call from the web app fails as a timeout in your MATLAB code.

To allow a port to any destination, add it to `security.networkPolicy.workers.additionalAllowedPorts` in your `values-overrides.yaml` file. This example allows access to MySQL on the standard port:

```
security:
  networkPolicy:
    workers:
      additionalAllowedPorts:
      - port: 3306
        protocol: TCP
```

To allow access to a specific host or to specific pods, use `security.networkPolicy.workers.additionalEgress` instead. To replace the default rules completely, use `security.networkPolicy.workers.egress`. The same three settings exist for the server pods, under `security.networkPolicy.server`.

#### Configure Network License Manager Ports
The server pods must reach the network license manager. By default, the server network policy allows outbound TCP traffic to ports 27000 to 27010.

A license checkout uses two connections. The first connection goes to the license manager daemon, `lmgrd`, which usually listens on a port in the range 27000 to 27010. The second connection goes to the MathWorks vendor daemon, `MLM`, which takes a random port by default. That random port is outside the allowed range. Use one of these two options to make the second connection work.

* **Option 1.** Assign the `MLM` vendor daemon a port in the range 27000 to 27010. To do this, add a `PORT=` entry to the `DAEMON` line of your license file. This option needs no change to the Helm chart.
* **Option 2.** Assign the `MLM` vendor daemon any other port. Then add that port to `security.networkPolicy.server.additionalAllowedPorts` in your `values-overrides.yaml` file.

If the vendor daemon port is not reachable, the license checkout stops responding and the server reports a license failure. The license server still answers on port 27000, so the license server looks healthy from the cluster.

For more information about network license manager ports, see [What ports does the Network License Manager use and how can I set those ports?](https://www.mathworks.com/matlabcentral/answers/96756-what-ports-does-the-network-license-manager-use-and-how-can-i-set-those-ports)

### Update Server Configuration Properties

The `webAppServerSettings` section of the `chart/values.yaml` file holds the server settings. To change one, copy it into your `values-overrides.yaml` file and set your value, as described in [Configure Your Deployment](#configure-your-deployment). The `chart/values.yaml` file lists every server setting that the chart supports. This table describes the settings that most deployments change.

| Setting | Default | Description |
|---------|---------|-------------|
| `numServerPods` | `1` | Specify the number of server pods. Increase this number for more capacity or for redundancy. |
| `maxSessionsPerServer` | `64` | Specify the maximum number of web app sessions for one server pod. MathWorks recommends 4 sessions for each CPU core. Do not configure more than 16 sessions for each CPU core. |
| `newSessionTimeout` | `60` | Specify the time in seconds to wait for a new session to start. After this time, the server reports a session start failure. |
| `loggingLevel` | `normal` | Specify how much detail the server writes to the log. Options are `verbose`, `normal`, or `minimal`. |
| `serverLogsDest` | `console` | Specify where the server writes the log. For `console`, read the log with the `kubectl logs` command. For `file`, the server writes the log to the logs volume, which you must configure first. For more information, see [Provide Mapping for Logs](#provide-mapping-for-logs). |
| `maxAppUploadSizeMB` | Empty | Specify the maximum size in MB of a web app that a user uploads from the **Manage Apps** page. If this setting is empty, the limit is 100 MB. |

The default of 64 sessions for each server pod needs a node with at least 4 CPU cores. At the recommended density of 4 sessions for each CPU core, 64 sessions need 16 CPU cores. Reduce `maxSessionsPerServer` to match the nodes in your cluster.

The Helm chart applies a CPU and memory limit to each pod. The `resourceQuota` section of the `chart/values.yaml` file sets these limits.

| Pod | CPU Request / Limit | Memory Request / Limit |
|-----|---------------------|------------------------|
| `webapps-server` | 250m / 750m | 512Mi / 1024Mi |
| `webapps-worker-r2026b` | 250m / 900m | 1024Mi / 2048Mi |

These limits are a starting point. You can change them to match the needs of your web apps.

In addition, place your Web App Server configuration files in the `chart/settings/webapps_private` directory. These are the same files used by the standalone MATLAB Web App Server installation. Supported configuration files include:

- [`webapps_authn.json`](https://www.mathworks.com/help/webappserver/ug/authentication.html)
- [`webapps_app_roles.json`](https://www.mathworks.com/help/webappserver/ug/role-based-access.html)
- [`webapps_acc_ctl.json`](https://www.mathworks.com/help/webappserver/ug/policy-based-access.html)
- [`webapps_secrets_acc_ctl.json`](https://www.mathworks.com/help/webappserver/ug/control-secrets-access.html)
- [`userinfo.json`](https://www.mathworks.com/help/webappserver/ug/customize-web-app-behavior-based-on-user.html)
- [`auditlog.json`](https://www.mathworks.com/help/webappserver/ug/audit-logging.html)

The SSL certificate and the private key go in the same directory, but they are not optional. For more information, see [Add SSL Certificate and Private Key](#add-ssl-certificate-and-private-key).

To apply the updated server properties to the deployment, use [helm upgrade](https://helm.sh/docs/helm/helm_upgrade/) command. Server instances automatically restart to take advantage of the new values.
```
helm upgrade <release_name> -f <path/to/values-overrides.yaml> [-n <k8s-namespace>] <path/to/chart directory>
```
Some changes (such as updating the volume path) cannot be applied dynamically. In these cases, you must uninstall and then reinstall the release using the [`helm uninstall`](https://helm.sh/docs/helm/helm_uninstall/) and [`helm install`](https://helm.sh/docs/helm/helm_install/) commands, as described earlier.

```
helm uninstall <release_name> [-n <k8s-namespace>]
```

The `helm uninstall` command removes the PersistentVolume objects that the Helm chart created. This behavior covers the `hostpath`, `nfs`, and `azurefileshare` mount types. The command does not remove a volume that existed before the installation, which is the `pvc` mount type.

Removing a PersistentVolume object does not delete the data behind it. For a `hostpath` mount, the directory and the `.ctf` files stay on the node, and a new installation uses them again.

## Troubleshooting

**A pod reports `ImagePullBackOff`.**

The node cannot get the container image. Confirm that you pushed both images to a registry that all nodes can reach. Confirm that `images.serverName` and `images.workerName` include that registry, and that `images.pullSecretName` names a Secret with valid credentials. For more information, see [Push Container Images to Your Registry](#push-container-images-to-your-registry).

**A server pod starts but never reaches the Ready state.**

The server cannot find its SSL certificate. Confirm that the `webapps_cert.pem` and `webapps_key.pem` files are in the `chart/settings/webapps_private` folder, then install the chart again. For more information, see [Add SSL Certificate and Private Key](#add-ssl-certificate-and-private-key). To read the server log, use the `kubectl logs -n <k8s-namespace> webapps-0` command.

**The cluster runs, but a web app cannot reach a database or a web service.**

The worker network policy blocks the connection. Allow the port that your web app uses. For more information, see [Network Access for Web Apps](#network-access-for-web-apps).

**The server reports a license failure, but the license server responds.**

The cluster cannot reach the MathWorks vendor daemon. For more information, see [Configure Network License Manager Ports](#configure-network-license-manager-ports).

**The installation stops and reports `Logs volume needs to be mounted for serverLogsDest=file`.**

You set the `webAppServerSettings.serverLogsDest` value to `file` and left the `volumes.logs.mountType` value at `none`. Set a mount type for the logs volume. For more information, see [Provide Mapping for Logs](#provide-mapping-for-logs).

## Request Enhancements

To suggest additional features or capabilities, see
[Request Reference Architectures](https://www.mathworks.com/products/reference-architectures/request-new-reference-architectures.html).

## Get Technical Support

If you require assistance, contact [MathWorks Technical Support](https://www.mathworks.com/support/contact_us.html).

## License

MATHWORKS CLOUD REFERENCE ARCHITECTURE LICENSE © 2026 The MathWorks, Inc.

