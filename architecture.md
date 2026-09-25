<!-- Copyright 2025-2026 The MathWorks, Inc. -->
# Architecture of MATLAB Web App Server in Kubernetes

This document describes what one installation of the Helm® chart creates in your Kubernetes® cluster. You do not need this information to deploy MATLAB® Web App Server™. Read it when you size a cluster, set a resource quota, write a network policy, or find the cause of a problem.

For the deployment steps, see [README.md](README.md).

## Kubernetes Objects

One installation of the Helm chart creates these Kubernetes objects.

* A StatefulSet named `webapps`. The number of replicas comes from `webAppServerSettings.numServerPods`. The chart names the pods `webapps-0`, `webapps-1`, and so on. Each pod runs MATLAB Web App Server on container port 9988.
* A Service named `webapps-server-service` on port 9999. This service forwards traffic to container port 9988.
* One Deployment named `webapps-worker-<release>` for each entry in the `matlabRuntimes` array. The number of replicas comes from `numPrewarmedWorkers`. Each worker pod holds one MATLAB Runtime release.
* One ReplicaSet named `terminated-webapps-worker-<release>` for each MATLAB Runtime release. This ReplicaSet stays at zero replicas. For more information, see [How the Server Starts and Retires Sessions](#how-the-server-starts-and-retires-sessions).
* Up to four PersistentVolume and PersistentVolumeClaim pairs, for the apps, init, logs, and runtimes volumes. For more information, see [Volumes](#volumes).
* Two NetworkPolicy objects, one for the server pods and one for the worker pods. The chart enables both objects by default. For more information, see [Network Access for Web Apps](README.md#network-access-for-web-apps).
* Role-based access control (RBAC) objects. These objects let a server pod change pod labels and read the logs of a worker pod.
* Two ConfigMap objects and one TLS Secret. The chart builds these objects from the files in the `chart/settings` folder.

The chart creates an Ingress object named `webapps-ingress` only when you set a value for `ingressController.class`. If you leave that value empty, the chart creates no Ingress object and the cluster is not accessible from outside. For more information, see [Enable External Access](README.md#enable-external-access).

## Pod Types

The deployment has two pod types.

* **Server pods.** These pods run the server. They accept the client connections, serve the home page, and hold the web apps. The StatefulSet controls these pods.
* **Worker pods.** These pods run the web app sessions. One worker pod runs one session. Each worker pod holds one MATLAB Runtime release.

A server pod does not run web app code. A worker pod does not accept client connections.

## How the Server Starts and Retires Sessions

The server uses a pod label to move a worker pod through its life cycle. The label is `state`, and it has three values.

| `state` label | Meaning | Which object selects the pod |
|---------------|---------|------------------------------|
| `idle` | The pod waits for a session. | The `webapps-worker-<release>` Deployment |
| `running` | The pod runs a session. | None |
| `terminated` | The session is complete. | The `terminated-webapps-worker-<release>` ReplicaSet |

The chart creates each worker pod with the `idle` label. The sequence is as follows:

1. A user starts a web app. The server selects an idle worker pod and changes the `state` label to `running`.
2. The pod no longer matches the Deployment selector. The Deployment counts fewer pods than `numPrewarmedWorkers`, so it creates a replacement pod with the `idle` label. This behavior keeps a supply of idle pods ready.
3. The session ends. The server changes the `state` label to `terminated`.
4. The pod now matches the ReplicaSet selector. That ReplicaSet has zero replicas, so it deletes the pod.

This design is the reason the chart uses a Deployment for the workers instead of a StatefulSet. A StatefulSet does not create a new pod in response to a label change.

The server needs permission to change these labels. The RBAC objects give it that permission.

## Volumes

The deployment can use five volumes. The `apps` and `init` volumes are always present. The other three depend on a `mountType` setting.

| Volume | Present when | Server pod mount point | Worker pod mount point |
|--------|--------------|------------------------|------------------------|
| `apps` | Always | `/webapps/apps` | Not mounted |
| `init` | Always | `/webapps/init` | `/webapps/init` |
| `logs` | `volumes.logs.mountType` is not `none` | `/webapps/logs` | `/webapps/logs` |
| `runtimes` | `volumes.runtimes.mountType` is not `embedded` | `/webapps/runtimes` | `/matlab`, read-only |
| `server` | `volumes.server.mountType` is not `embedded` | `/webapps/server` | Not mounted |

The volumes have these roles.

* The `apps` volume holds the web apps (`.ctf` files). These files stay outside the container images, so an upload does not need a new image.
* The `init` volume holds session init data and tools. The server pods write to this volume. The worker pods read from it.
* The `logs` volume holds the server log files. This volume is necessary only when `webAppServerSettings.serverLogsDest` is `file`.
* The `runtimes` volume holds the MATLAB Runtime installations. By default, the MATLAB Runtime comes from the worker container image, and the chart creates no `runtimes` volume. When you use this volume, the location must hold one subdirectory for each release. The chart mounts the subdirectory that matches the `release` value, so each worker pod sees only its own MATLAB Runtime.
* The `server` volume holds the MATLAB Web App Server code. By default, the code comes from the server container image.

The `apps`, `init`, `logs`, and `runtimes` volumes use a PersistentVolumeClaim. The `server` volume does not. The chart mounts the `server` volume directly as a `hostPath` or an `nfs` volume, which is why the count of PersistentVolumeClaim objects is four and not five.

For the `pvc` mount type, you create the PersistentVolume and the PersistentVolumeClaim before you install the chart, and you give the claim name to the chart. For every other mount type, the chart creates both objects.

## Resource Limits

The chart applies a CPU and memory limit to each pod. The `resourceQuota` section of the `chart/values.yaml` file holds these limits. The section has one key for each pod type.

* `webapps-server` for the server pods.
* `webapps-worker-<release>`, in lowercase, for the worker pods of one MATLAB Runtime release.

Each MATLAB Runtime release needs its own key. If a key is absent, the chart creates the Deployment with no CPU or memory limit, and Helm reports no error. For more information, see [Configure Multiple MATLAB Runtime Versions](README.md#configure-multiple-matlab-runtime-versions).

## Network License Manager

The network license manager runs outside the cluster. Do not install the license manager in the cluster.

Each server pod gets a license from the license manager. A license checkout uses two connections and two ports. The server pods must have network access to both ports. For more information, see [Configure Network License Manager Ports](README.md#configure-network-license-manager-ports).

Only the server pods contact the license manager. By default, the worker network policy allows outbound traffic only to the server pods, to the server service on port 9999, and to DNS. If you add outbound rules for the worker pods, use `security.networkPolicy.workers.additionalAllowedPorts`.

## License

MATHWORKS CLOUD REFERENCE ARCHITECTURE LICENSE © 2026 The MathWorks, Inc.
