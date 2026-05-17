# Ansible controller — push-based application deployment.
# Uses Foreman as dynamic inventory source.

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    openssh-client \
    sshpass \
    curl \
    && rm -rf /var/lib/apt/lists/*

ENV VIRTUAL_ENV=/opt/venv
RUN python3 -m venv "${VIRTUAL_ENV}"
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"

RUN pip install --no-cache-dir \
    ansible \
    requests

RUN ansible-galaxy collection install theforeman.foreman

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /opt/ansible

ENTRYPOINT ["/entrypoint.sh"]
