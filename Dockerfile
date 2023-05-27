# Use Ubuntu 22.04 as base image
FROM ubuntu:22.04 AS base

# Set the timezone configuration to non-interactive
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && apt-get install -y tzdata

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3-pip \
    jupyterhub \
    sudo

# Create a local user account to run pip commands
RUN useradd -m -s /bin/bash -G sudo jupyterhub_user \
    && echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Switch to the jupyterhub_user account
USER jupyterhub_user
WORKDIR /home/jupyterhub_user

# Create an intermediate image for generating the JupyterHub configuration
FROM base AS config

# Set the default user to admin and set the default password to 'change.it!'
RUN jupyterhub --generate-config \
    && sed -i "s/# c.Authenticator.admin_users = set()/c.Authenticator.admin_users = {'admin'}/g" /home/jupyterhub_user/jupyterhub_config.py \
    && echo "c.Authenticator.admin_password = 'change.it!'" >> /home/jupyterhub_user/jupyterhub_config.py

# Install JupyterLab
FROM base AS jupyterlab

# Switch to the jupyterhub_user account
USER jupyterhub_user
WORKDIR /home/jupyterhub_user
ENV PATH="/home/jupyterhub_user/.local/bin:${PATH}"

# Install JupyterLab and its dependencies
RUN python3 -m pip install jupyterlab && \
    python3 -m pip install --upgrade jupyter_core jupyter_client

# Install libraries specified in requirements.txt
FROM jupyterlab AS libraries

COPY requirements.txt /home/jupyterhub_user/requirements.txt
RUN echo "Installing Python libraries:" && \
    python3 -m pip install -r requirements.txt

# Final image for build
FROM base

# Copy the JupyterHub configuration and JupyterLab installation from the intermediate images
COPY --from=config /home/jupyterhub_user/jupyterhub_config.py /home/jupyterhub_user/
COPY --from=jupyterlab /home/jupyterhub_user/.local /home/jupyterhub_user/.local

# Copy the libraries installed from the libraries intermediate image
COPY --from=libraries /usr/local/lib/python3.10/site-packages /usr/local/lib/python3.10/site-packages

#Switch to the jupyterhub_user account, set the working directory, and expose the JupyterHub and JupyterLab ports
USER jupyterhub_user
WORKDIR /home/jupyterhub_user
EXPOSE 8000 8888

# Start JupyterHub
CMD ["jupyterhub", "-f", "/home/jupyterhub_user/jupyterhub_config.py"]