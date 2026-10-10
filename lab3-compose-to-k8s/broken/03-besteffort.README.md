# Why this one is a JSON patch and the others are YAML

Every other file in `broken/` **sets** a field, so a strategic-merge patch works.
This one needs to **remove** a field, and that is a different operation.

The obvious thing does not work:

```yaml
# broken/03-besteffort.yaml  -- WRONG, silently does nothing
spec:
  template:
    spec:
      containers:
        - name: api
          resources: {}
```

```console
$ kubectl -n lab3 patch deploy api --patch-file broken/03-besteffort.yaml
deployment.apps/api patched          # <- it says patched!
$ kubectl -n lab3 get deploy api -o jsonpath='{.spec.template.spec.containers[0].resources}'
{"limits":{"memory":"256Mi"},"requests":{"cpu":"100m","memory":"128Mi"}}
```

**A strategic merge patch merges. An empty map merges to no change.** There is no way to
express "delete this" — and `kubectl` reports success, so you only find out by checking.
This bites people constantly in CI, where a "patch" step goes green and changes nothing.

To delete, use a **JSON Patch (RFC 6902)** with an explicit `remove` op:

```bash
kubectl -n lab3 patch deploy api --type=json --patch-file broken/03-besteffort.json
```

The three patch types, since interviewers ask:

| Type | Flag | Deletes a field by |
|---|---|---|
| Strategic merge (default) | *(none)* | setting it to `null`, or `$patch: delete` |
| JSON merge (RFC 7386) | `--type=merge` | setting it to `null` — but it **replaces whole lists**, so patching one container drops the rest |
| JSON patch (RFC 6902) | `--type=json` | `{"op": "remove", "path": "..."}` — precise, and the only one that's unambiguous |
