#!/bin/bash 

sudo apt-get update -yy
sudo apt-get install -yy git curl 

curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh