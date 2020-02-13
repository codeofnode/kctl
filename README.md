# kctl
Easy kubectl for multiple clusters and namespaces.


## installation
```
bash init.sh [<kct_pod_yaml_path>] [<default_config_path>] [<nick_name_eg_qa>]
```

## Add a new cluster
```
kctl ln <nick_name_of_cluster_eg_dev> [<existing_path_of_kube_config_if_you_already_have_any>]
```

#### Optional configuration
```
# if you have the dashboard url else it will use port forward for dashboard svc
kctl cf ds.url https://34.200.213.249:30000
```

#### Setting up different config directory
```
export KCTL_CONFIG_DIR=/my/custom/kube/config/directory
```

# switch to different cluster
```
kctl ln <nick_name_of_cluster_eg_dev>
```

# Open dashboard
```
kctl ds
```
> TIP: Token will be automatically copied to your cliboard and dashboard will open in browser. Just paste the token and click sign in.

# Work with kubectl in current cluster
```
source kctl
```

# Various commands
```
kctl -h
```

# Debugging
> Just prepend -v for normal debugging, -vv for full debugging what is happening inside and -v0 to disable debugging completely
So commands like `kctl get pg` will become `kctl -v get pg`
