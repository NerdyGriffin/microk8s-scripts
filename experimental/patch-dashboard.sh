#!/bin/bash
sudo microk8s kubectl patch -n kubernetes-dashboard svc kubernetes-dashboard-kong-proxy --patch='{"spec":{"loadBalancerIP":"10.64.140.8","type": "LoadBalancer"}}'
# sudo microk8s kubectl patch -n kube-system svc kubernetes-dashboard --patch='{"spec":{"loadBalancerIP":"10.64.140.9","type": "LoadBalancer"}}'
