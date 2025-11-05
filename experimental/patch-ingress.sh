#!/bin/bash
microk8s kubectl patch -n ingress ConfigMap nginx-ingress-tcp-microk8s-conf --patch='{"data":{"compute-full-forwarded-for":"true","enable-real-ip":"true"}}'
microk8s kubectl patch -n ingress ConfigMap nginx-ingress-udp-microk8s-conf --patch='{"data":{"compute-full-forwarded-for":"true","enable-real-ip":"true"}}'