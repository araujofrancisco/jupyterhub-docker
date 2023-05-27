# Use Ubuntu 22.04 as base image
FROM ubuntu:22.04 AS base

# Set default admin password
ENV admin_password change.it!

# Set the timezone configuration to non-interactive
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && apt-get install -y tzdata

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3-pip \
    jupyterhub \ 
    curl \   
    sudo

# Create a local user account to run pip commands
RUN useradd -m -s /bin/bash -G sudo admin \
    && echo admin:${admin_password} | chpasswd \
    && echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers    

# Switch to the admin account
USER admin
WORKDIR /home/admin
COPY jupyterhub_config.py /home/admin/jupyterhub_config.py

# Install JupyterLab
FROM base AS jupyterlab

# Switch to the admin account
USER admin
WORKDIR /home/admin
ENV PATH="/home/admin/.local/bin:${PATH}"

# Install JupyterLab and its dependencies
RUN python3 -m pip install jupyterlab && \
    python3 -m pip install --upgrade jupyter_core jupyter_client

# Install support software required before installing library from requirements
FROM jupyterlab AS support

# Download and compile the required files for ta-lib
RUN curl -L http://prdownloads.sourceforge.net/ta-lib/ta-lib-0.4.0-src.tar.gz -O && tar xzvf ta-lib-0.4.0-src.tar.gz  
WORKDIR /home/admin/ta-lib

RUN ./configure --prefix=/usr && make && sudo make install
WORKDIR /home/admin

RUN echo 'export TA_LIBRARY_PATH=$PREFIX/lib' >> ~/.bashrc && echo 'export TA_INCLUDE_PATH=$PREFIX/include'

RUN echo "Installing Python support libraries:" && \
    python3 -m pip install ta-lib && python3 -m pip install hnswlib

# Install libraries specified in requirements.txt
FROM support AS libraries

COPY --from=support /home/admin/.local /home/admin/.local

COPY requirements.txt /home/admin/requirements.txt
RUN echo "Installing Python libraries from requirements:" && \
    python3 -m pip install -r requirements.txt

# Final image for build
FROM base

# Copy the .bashrc configuration
COPY --from=support /home/admin/.bashrc /home/admin/

# Copy the JupyterLab installation from the intermediate images
COPY --from=jupyterlab /home/admin/.local /home/admin/.local

# Copy the libraries installed from the libraries intermediate image
#COPY --from=libraries /usr/local/lib/python3.10/site-packages /usr/local/lib/python3.10/site-packages

#Switch to the jupyterhub_user account, set the working directory, and expose the JupyterHub and JupyterLab ports
USER admin
WORKDIR /home/admin
EXPOSE 8000

# Start JupyterHub
CMD ["jupyterhub", "-f", "/home/admin/jupyterhub_config.py"]