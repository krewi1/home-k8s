kubectl exec -n garage deployment/garage -- /garage key create thanos-key
kubectl exec -n garage deployment/garage -- /garage bucket create thanos
kubectl exec -n garage deployment/garage -- /garage bucket allow --read --write thanos --key thanos-key