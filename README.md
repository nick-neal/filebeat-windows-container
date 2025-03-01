# filebeat-windows-container
This is a Windows container solution for shipping containerd logs via filebeat. It acts as a Daemon that runs on all Windows worker nodes, parsing containerd logfiles and sending them to a filebeat compliant backend.

## pre-reqs
- a kubernetes cluster with Windows worker nodes
- a filebeat compliant backend (logstash, graylog, etc.)
- (optional) a github and docker hub account

## building the container (optional)
You can either fork this repository to build & push the container to your own dockerhub account, or use the versions available on my dockerhub account located at https://hub.docker.com/r/nealnick/filebeat-windows

before building, you'll need to setup a personal access token on docker hub, and configure the newly generated credentails in the forked github repository like so:
- create a repository variable called `DOCKER_USER` containing your docker hub username
- create a repository secret called `DOCKER_SECRET` containing the personal access token generated from docker hub

## deployment in the cluster
> [!NOTE]
> The manifests described in this repository assumes that your logstash backend is TLS encrypted. Client auth and certificate verification have been disabled for testing purposes. It is important that these features are enabled in your production environment.

### namespace
before deploying, you will need to create a namespace called `logging`:
```bash
kubectl create namespace logging
```

### configuration
The following configuration will parse log files in the `C:\var\log\containers` directory on your Windows worker nodes. This configuration also takes environment variables for the cluster name (K8S_CLUSTER_NAME), the logstash backend (LOGSTASH_HOST), as well as the port for connecting (LOGSTASH_PORT):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: windows-filebeat-config
  namespace: logging
  labels:
    k8s-app: filebeat
data:
  filebeat.yml: |-
    filebeat.inputs:
    - type: log
      enabled: true
      symlinks: true
      exclude_files: ['filebeat.*',
                      'logstash.*',
                      'azure.*',
                      'kube.*',
                      'ignite.*',
                      'influx.*',
                      'prometheus.*',
                      'rkubelog.*',
                      'node-exporter.*']
      paths:
        - C:\\var\\log\\containers\\*.log
    processors:
      - add_fields:
          fields:
            k8s_cluster_name: "${K8S_CLUSTER_NAME}" 
      - drop_fields:
          fields: ["host"]
          ignore_missing: true
      - dissect:
          tokenizer: "C:\\var\\log\\containers\\%{name}_%{host}_%{uuid}.log"
          field: "log.file.path"
          target_prefix: ""
          overwrite_keys: true
      - dissect:
          tokenizer: "%{header} F %{parsed}"
          field: "message"
          target_prefix: ""
          overwrite_keys: true
      - drop_fields:
          fields: ["message"]
          ignore_missing: true
      - rename:
          fields:
            - from: "parsed"
              to: "message"
          ignore_missing: true
          fail_on_error: false
    output.logstash:
      hosts: ["${LOGSTASH_HOST}:${LOGSTASH_PORT}"]
      ssl:
        enabled: true
        client_authentication: none
        verification_mode: none
```

### deployment
The deployment manifest creates a DaemonSet that will deploy a host process container that runs as `NT AUTHORITY\SYSTEM` on each of the Windows Kubernetes worker nodes in your cluster. It takes the configmap from the previous manifest, and mounts it as a config file located at `C:\filebeat\filebeat.yaml`. This yaml file will be is used by filebeat as detailed in the `docker-entrypoint.ps1` script:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: filebeat
  namespace: logging
  labels:
    k8s-app: filebeat
spec:
  selector:
    matchLabels:
      k8s-app: filebeat
  template:
    metadata:
      labels:
        k8s-app: filebeat
    spec:
      securityContext:
        windowsOptions:
          hostProcess: true
          runAsUserName: "NT AUTHORITY\\SYSTEM"
      terminationGracePeriodSeconds: 30
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      containers:
      - name: filebeat-windows
        image: nealnick/filebeat-windows:8.17.2
        imagePullPolicy: Always
        env:
        - name: K8S_CLUSTER_NAME
          value: "homelab"
        - name: LOGSTASH_HOST
          value: "graylog.local"
        - name: LOGSTASH_PORT
          value: "5044"
        resources:
          limits:
            memory: 200Mi
          requests:
            cpu: 100m
            memory: 100Mi
        volumeMounts:
        - name: config
          mountPath: C:\\filebeat\\filebeat.yml
          readOnly: true
          subPath: filebeat.yml
      nodeSelector: 
        kubernetes.io/os: windows
      volumes:
      - name: config
        configMap:
          defaultMode: 0600
          name: windows-filebeat-config
      tolerations:
      - key: taintedLabel
        operator: Equal
        value: specialNode
        effect: NoSchedule
```
