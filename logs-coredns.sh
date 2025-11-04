#!/bin/bash
microk8s kubectl -n kube-system get pod | grep coredns | awk '{ print $1 }' | xargs microk8s kubectl -n kube-system logs