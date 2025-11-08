#!/bin/bash
set -eux

# Install and start nginx on Amazon Linux 2
amazon-linux-extras install -y nginx1
systemctl enable nginx
systemctl start nginx

# Create a simple Hello World page
webroot="/usr/share/nginx/html"
echo "Hello World from $(hostname)" > ${webroot}/index.html
chown root:root ${webroot}/index.html
chmod 644 ${webroot}/index.html