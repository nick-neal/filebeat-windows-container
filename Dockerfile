ARG BASE="mcr.microsoft.com/oss/kubernetes/windows-host-process-containers-base-image:v0.1.0"

FROM --platform=linux/amd64 ubuntu:jammy as bins
ARG filebeatVersion="8.17.2"

# https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-8.17.2-windows-x86_64.zip
WORKDIR /filebeat
RUN apt update && apt install -y unzip curl
RUN curl -Lo filebeat.zip https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-${filebeatVersion}-windows-x86_64.zip
RUN unzip -j "filebeat.zip" "filebeat-${filebeatVersion}-windows-x86_64/filebeat.exe" -d .

FROM $BASE

ENV PATH="C:\Windows\system32;C:\Windows;C:\WINDOWS\System32\WindowsPowerShell\v1.0\;"
COPY ./docker-entrypoint.ps1 /filebeat/docker-entrypoint.ps1
COPY --from=bins /filebeat/filebeat.exe /filebeat/filebeat.exe

ENTRYPOINT ["powershell", "/c", "$env:CONTAINER_SANDBOX_MOUNT_POINT/filebeat/docker-entrypoint.ps1"]