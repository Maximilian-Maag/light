# Ansible controller — push-based application deployment.
# Uses Foreman as dynamic inventory source.

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    openssh-client \
    sshpass \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir \
    ansible \
    requests \
    theforeman.foreman

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /opt/ansible

ENTRYPOINT ["/entrypoint.sh"]
