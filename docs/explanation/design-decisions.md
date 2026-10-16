# Design decisions

Why the module is shaped the way it is, and what it leaves out on purpose.

## One private bucket

Most buckets hold data that only named principals should read: application data,
reports, staging files, logs. The module makes that kind of bucket and stops. Who
may use it is the caller's decision, expressed in IAM policies or in `policy_json`,
because only the caller knows the principals. A module that tried to cover public
sites, data lakes and archives as well would need dozens of inputs and would make the
private case harder to get right.

## Block Public Access is not configurable

All four Block Public Access settings are on, and there is no input to turn them off.
With them on, no bucket policy and no ACL can make the bucket or its objects public,
whatever a later change adds. A bucket that must serve the public is a different
design: a private bucket behind CloudFront, or a purpose-built public bucket that
gets its own review. Keeping the switch out of the module means a public bucket can
never be one variable away.

## TLS only, by default

The `DenyInsecureTransport` statement denies every request that does not arrive over
TLS, whoever sends it. An explicit deny overrides every allow, so no grant added later
can reopen plain HTTP, and the statement itself grants nothing. AWS services that
write to buckets use TLS, so log delivery keeps working. The input that removes the
statement, `enforce_tls`, exists because some callers adopt buckets that never had
it and must not see a policy appear unannounced; its name says what turning it off
weakens.

## Versioning, by default

Versioning turns an overwrite or a delete into a new version instead of a loss. It is
the only S3 feature that recovers from both an accident and a deliberate deletion
with stolen credentials, and replication needs it. The cost is storage for old
versions, which a `noncurrent_version_expiration_days` rule bounds. S3 cannot turn
versioning off once it is on, only suspend it, so the module makes it the default
rather than something to add later.

## SSE-S3 by default, SSE-KMS when you bring a key

Every new S3 object is encrypted at rest. SSE-S3 needs no key, costs nothing extra,
and is the only encryption that load-balancer access logs and S3 server access logs
can be delivered to. SSE-KMS adds an audit trail of key use and a second place to
revoke access, at the price of a key policy to maintain and KMS requests to pay for.
The module turns on the S3 Bucket Key with SSE-KMS, which cuts those requests. It
creates no key: keys, their policies and their rotation are managed where the
caller's other keys are.

The module accepts a key ARN, not an alias. S3 resolves an alias in the account of
whoever writes the object, so with an alias a writer from another account could
encrypt objects with its own key instead of the bucket owner's.

## No Name tag

Other modules in this family add a `Name` tag. This one does not. A bucket's name is
already a unique, visible identifier, so a `Name` tag only repeats it, and buckets
that callers adopt either have no `Name` tag or one that differs from the bucket
name. Adding one would change their tags on adoption. The bucket gets exactly the
tags the caller passes.

## No ownership controls and no ACLs

S3 creates new buckets with the object ownership `BucketOwnerEnforced`, which
disables ACLs: the bucket owner owns every object and policies alone decide access.
Managing `aws_s3_bucket_ownership_controls` would only restate that default, and
would add a resource to the plan of every caller who adopts an existing bucket.
ACL-based access is legacy, so the module offers no way to grant it.

## A lifecycle rule that aborts incomplete uploads

A multipart upload that never completes leaves its parts in the bucket. They are
billed but do not appear in object listings, so nobody notices them. The default
rule deletes such parts after 7 days, long enough for any upload still in progress.
A bucket has a single lifecycle configuration, so every rule a caller passes carries
the same action, with the same default, and the bucket never loses it by accident.

## A flag decides whether the caller's policy is attached

Whether the bucket policy exists must be known when Terraform plans. A caller's
policy often names a role or another bucket created in the same apply, so its JSON is
not known until then. The module therefore decides by two booleans, `enforce_tls` and
`attach_policy_json`, and rejects `policy_json` without the flag, rather than
dropping it silently.

## Names and addresses are stable

Resource names inside the module are fixed (`main`), the bucket is named exactly
`var.name`, and the default rule and statement IDs never change. Callers who move
existing resources into the module with `moved` blocks keep a plan with no changes,
and the [reference](../reference/resources-policy-and-permissions.md) is the
contract: changing any of those values is a breaking change.

## Left out on purpose

| Not included | Why |
| --- | --- |
| Cross-Region replication | Needs a bucket in another Region, an IAM role and a decision about what to copy. Versioning is on by default, so `aws_s3_bucket_replication_configuration` can be added next to the module call |
| Object Lock | Chosen when a bucket is created and cannot be removed; retention periods are a records-management decision, not a default |
| Static website hosting | Website endpoints serve plain HTTP and need public access, which this module forbids; CloudFront with origin access control serves sites from a private bucket |
| CORS | Only buckets that browsers call directly need it, and the rules belong to the application |
| Event notifications | The consumer (a queue, topic, function or EventBridge) belongs to the caller, as does `aws_s3_bucket_notification` |
| Intelligent-Tiering and storage-class transitions | Cost decisions that depend on access patterns. Objects can be written with the `INTELLIGENT_TIERING` storage class, and a caller who needs transitions passes `lifecycle_rules = []` and manages the lifecycle configuration itself |
| Directory buckets (S3 Express One Zone) | A different bucket type with its own resource, naming rules and feature set |
| The account-regional namespace (`bucket_namespace`) | Would raise the provider minimum to 6.37, and moving an existing bucket into it means replacing the bucket |
| Blocking SSE-C (`blocked_encryption_types`) | S3 blocks SSE-C on new buckets by default; managing the setting would raise the provider minimum and change the encryption configuration of buckets callers adopt |
