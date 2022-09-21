### Terraform

This demo is `WIP`

Components added respected to the main branch

- Terraform for deploying the Alpha and Beta Scenarios
- HTTPs via AWS Certified Manager
- External DNS

Restore process gives a:

```sh
Name:         cbci-dr-20220921173213
Namespace:    velero
Labels:       <none>
Annotations:  <none>

Phase:  PartiallyFailed (run 'velero restore logs cbci-dr-20220921173213' for more information)

Started:    2022-09-21 17:32:15 +0200 CEST
Completed:  2022-09-21 17:32:16 +0200 CEST

Errors:
  Velero:   error parsing backup contents: directory "resources" does not exist
  Cluster:    <none>
  Namespaces: <none>

Backup:  cbci-dr-20220921145509

Namespaces:
  Included:  all namespaces found in the backup
  Excluded:  <none>

Resources:
  Included:        *
  Excluded:        nodes, events, events.events.k8s.io, backups.velero.io, restores.velero.io, resticrepositories.velero.io
  Cluster-scoped:  auto

Namespace mappings:  <none>

Label selector:  <none>

Restore PVs:  auto

Preserve Service NodePorts:  auto
```
