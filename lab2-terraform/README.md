# Lab 2 — Terraform

**Closes your biggest gap.** Two days. Do this one first.

## Two tracks — start free

| Track | Cost | Purpose |
|---|---|---|
| **`envs/practice/`** | **£0** | Learn the *workflow* — plan, apply, state, drift, `for_each` vs `count`, `state mv`. Uses only `random`/`local`/`null` providers. **Start here.** |
| **`envs/dev/`** | 💰 real money | The real thing — Resource Group, ACR, AKS, Key Vault on Azure. Run once, then destroy. |

The practice track exists because **the expensive lessons in Terraform are about state, not about Azure.** You can learn 80% of what an interviewer will ask without spending anything.

---

## Track 1 — practice (free)

```bash
cd envs/practice
terraform init
terraform plan          # read this properly
terraform apply
```

Then work the exercises below. Each one teaches something you'd otherwise learn in production.

### Exercise 1 — read a plan

```bash
terraform plan
```
Identify in the output: what is **created** (`+`), **changed** (`~`), and **destroyed and recreated** (`-/+`).
> **A `-/+` on a database is data loss.** Learning to spot it is the single most important Terraform habit.

### Exercise 2 — inspect state

```bash
terraform state list
terraform state show random_pet.service_names[\"api\"]
cat terraform.tfstate | jq '.resources[0]'
```
Find the `sensitive_value` output in the state file. **It is in plaintext.** That is why state is a secret.

### Exercise 3 — cause drift

```bash
# simulate someone changing things outside Terraform
rm -f generated/api.conf
terraform plan          # watch it detect the missing file
terraform apply         # watch it restore
```
This is exactly what happens when someone edits a resource in the Azure portal.

### Exercise 4 — `count` vs `for_each` ⚠️ the important one

```bash
terraform state list | grep count_demo
```
Note the indices: `[0]`, `[1]`, `[2]`.

Now edit `main.tf` and **remove the MIDDLE element** (`"worker"`) from `var.count_services`:

```bash
terraform plan
```
**Watch Terraform plan to destroy and recreate everything after the removed index.** Then do the same with `var.foreach_services` and observe that only the removed one is affected.

*That contrast is a common interview question. Having seen it makes the answer automatic.*

### Exercise 5 — `state mv`

Rename `random_pet.count_demo` to `random_pet.renamed_demo` in `main.tf`, then:

```bash
terraform plan            # destroy + create — on a database this is catastrophic
terraform state mv 'random_pet.count_demo[0]' 'random_pet.renamed_demo[0]'
terraform plan            # now clean
```

### Exercise 6 — import

```bash
echo "manually-created" > generated/orphan.txt
# add a local_file resource for it in main.tf, then:
terraform import local_file.orphan generated/orphan.txt
```

### Clean up
```bash
terraform destroy
```

---

## Track 2 — real Azure 💰

⚠️ **An AKS cluster costs real money. Destroy it the same day.**

### Step 0 — bootstrap the state backend

The chicken-and-egg problem: the storage account holding your state can't be created by the Terraform that uses it.

```bash
cd bootstrap
./bootstrap.sh          # creates RG + storage account + container for state
```

Note the storage account name it prints, then put it in `envs/dev/backend.tf`.

### Step 1 — plan and apply

```bash
cd ../envs/dev
terraform init
terraform plan -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars
```

### Step 2 — the exercises that matter

**Drift:** delete the Key Vault's tag in the Azure portal, then `terraform plan`. Watch it detect the change.

**State locking:** run `terraform apply` in two terminals at once. The second should block on the blob lease.

**`prevent_destroy`:** try `terraform destroy` with the lifecycle block enabled on Key Vault and watch it refuse.

**Scan it:**
```bash
tflint
checkov -d .
```

### Step 3 — DESTROY

```bash
terraform destroy -var-file=dev.tfvars
```
Then **check the Azure portal** to confirm everything is gone. Purge-protected Key Vaults linger in a soft-deleted state — that's why `purge_protection_enabled` is conditional on environment in this code.

---

## What this earns you

> "I've built Terraform modules for resource groups, ACR, AKS and Key Vault, with remote state in a storage account and state locking. I use directory-per-environment rather than workspaces, because workspaces share a backend and it's too easy to apply to the wrong one. And I've broken state on purpose to see drift detection and `state mv` work — which is the part you only understand once you've done it."

See `../../src/05_Infrastructure_as_Code.md` for the theory.
