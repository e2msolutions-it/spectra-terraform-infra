# The buildspec is generated here rather than committed to each application
# repo, so build behaviour stays in one reviewed place and both repos cannot
# drift apart.
#
# IMAGE TAGGING: tag = <12-char commit sha>-<codebuild build number>.
#   * traceable straight back to a commit
#   * unique per build, which MATTERS because the ECR repos are IMMUTABLE -
#     re-running a pipeline on the same commit with a sha-only tag would fail
#     on "tag already exists".
#
# Each image also writes its own imagedefinitions file, so one build can feed
# several ECS deploy actions (the api repo deploys agent-api AND worker).

locals {
  # ---------------------------------------------------------------------------
  # CHECKS, RUN BEFORE THE FIRST docker build.
  #
  # Everything below happens inside ONE postgres:16-alpine container, and that
  # is the whole trick. It already contains the server AND psql; `apk add
  # nodejs` gives it the third thing needed, and then node and psql are looking
  # at the same filesystem and the same localhost. The alternative - postgres in
  # a container, node on the build host - means the migration paths node reads
  # and the paths psql opens are different paths, which is a class of bug that
  # would be discovered in CI rather than here.
  #
  # It also removes any dependence on what the CodeBuild image happens to ship.
  # aws/codebuild/amazonlinux2-aarch64-standard:3.0 carries a Node, but which
  # one is AWS's choice and changes when the image is rebuilt. Pinning the
  # runtime to the container makes the check reproducible.
  #
  # The image comes from ECR Public for the same reason every other base image
  # here does: one NAT gateway means one IP, and Docker Hub rate-limits
  # anonymous pulls per IP. Login already happened above.
  #
  # NO npm install. test/rbac.test.mjs reads the source and asserts on its
  # shape, and test/check-sql.mjs shells out to psql - neither imports a single
  # dependency. So this adds an image pull and a package, not a node_modules
  # tree, and cannot fail on a registry outage.
  #
  # TYPES ARE ALREADY COVERED and deliberately not repeated: the portal's
  # Dockerfile runs next build, which runs a full TypeScript check, so a type
  # error has always failed this pipeline. The gap was never types. It was that
  # a query can be malformed in a way only Postgres can see, and nothing asked
  # Postgres until the request that reached it in production.
  # ---------------------------------------------------------------------------
  check_commands = var.sql_checks == null ? [] : [
    "echo '--- checks: replaying the SQL in this repo against a real Postgres ---'",

    # The schema lives in agent-api and these queries live in portal. The ops
    # bucket is the one place both already agree on, and reading it needs an
    # IAM statement rather than a cross-repo credential.
    "aws s3 sync '${try(var.sql_checks.migrations_s3_uri, "")}' /tmp/spectra-migrations --exclude '*' --include '0*.sql' --only-show-errors",
    "ls /tmp/spectra-migrations/0*.sql >/dev/null 2>&1 || { echo 'ERROR: no migration files were fetched - has spectra-db.sh publish been run?'; exit 1; }",

    # The same truncation guard run-bootstrap.sh keeps, for the same reason: a
    # half-copied .sql file applies cleanly up to the cut and then stops, and
    # every Spectra migration starts with '--'. Checking the schema against a
    # truncated copy of it would be worse than not checking at all.
    "for f in /tmp/spectra-migrations/0*.sql; do [ \"$(head -c 2 \"$f\")\" = '--' ] || { echo \"ERROR: $f does not start with '--' - truncated in transit\"; exit 1; }; done",

    "docker rm -f spectra-check-pg >/dev/null 2>&1 || true",
    "docker run -d --name spectra-check-pg -e POSTGRES_PASSWORD=check -e POSTGRES_DB=chk -v \"$CODEBUILD_SRC_DIR\":/src:ro -v /tmp/spectra-migrations:/migrations:ro public.ecr.aws/docker/library/postgres:16-alpine",

    # `until` rather than `cmd && break`, because under `set -e` a failing
    # command inside an && list ends the build; inside an until CONDITION it is
    # just a false. The bound is here so a container that never starts fails in
    # a minute with its own logs attached, instead of at the build timeout with
    # nothing to read.
    "n=0; until docker exec spectra-check-pg pg_isready -U postgres -d chk -q; do n=$((n+1)); [ $n -lt 60 ] || { echo 'ERROR: postgres never became ready'; docker logs spectra-check-pg; exit 1; }; sleep 1; done",
    "docker exec spectra-check-pg apk add --no-cache nodejs",

    # Structural assertions first: they need no database, so if the shape of
    # the code is wrong that is what the log says, rather than a planner error.
    "docker exec -w /src spectra-check-pg node test/rbac.test.mjs",

    # THEN the replay, with NO DECLARED PARAMETER TYPES. That is the entire
    # point of check-sql.mjs and the reason the 22 September outage survived
    # its own verification - see the header of that file.
    "docker exec -w /src -e PORTAL_DIR=/src -e MIG_DIR=/migrations -e PGCONN='postgresql://postgres:check@localhost/chk' spectra-check-pg node test/check-sql.mjs",

    "docker rm -f spectra-check-pg >/dev/null 2>&1 || true",
    "echo '--- checks passed ---'",
  ]

  registry = "${var.account_id}.dkr.ecr.${var.region}.amazonaws.com"

  build_commands = flatten([
    for img in var.images : [
      "echo \"--- building ${img.key} ---\"",
      "docker build --file ${img.dockerfile} --tag ${img.ecr_repository}:$IMAGE_TAG ${var.build_context}",
      "docker push ${img.ecr_repository}:$IMAGE_TAG",
    ]
  ])

  # imagedefinitions-<key>.json is what the ECS deploy action consumes.
  post_build_commands = [
    for img in var.images :
    "printf '[{\"name\":\"%s\",\"imageUri\":\"%s\"}]' '${img.container_name}' '${img.ecr_repository}:'$IMAGE_TAG > imagedefinitions-${img.key}.json"
  ]

  buildspec = yamlencode({
    version = "0.2"
    phases = {
      pre_build = {
        commands = concat([
          "set -euo pipefail",
          "aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${local.registry}",
          # Base images are pulled from ECR Public, not Docker Hub, because the
          # whole VPC shares one NAT IP and Docker Hub rate-limits anonymous
          # pulls per IP (HTTP 429 when two pipelines build at once).
          # Authenticating raises the ECR Public limit well above anything this
          # account will do. ECR Public lives ONLY in us-east-1, so the region is
          # fixed here regardless of var.region.
          "aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws",
          "SHORT_SHA=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c1-12)",
          "IMAGE_TAG=$SHORT_SHA-$CODEBUILD_BUILD_NUMBER",
          "echo \"image tag: $IMAGE_TAG\"",
          # Fail early and loudly rather than pushing an x86 image that ECS
          # would refuse to start on Graviton.
          "test \"$(uname -m)\" = \"aarch64\" || { echo 'ERROR: builder is not aarch64; images would be the wrong architecture'; exit 1; }",
          # Checks go LAST in pre_build and not in their own phase: a failure
          # here means the build phase never runs, so nothing is pushed to ECR
          # and the Deploy stage is never reached. ECS keeps serving the task
          # definition it already has.
        ], local.check_commands)
      }
      build = {
        commands = local.build_commands
      }
      post_build = {
        commands = concat(
          local.post_build_commands,
          ["cat imagedefinitions-*.json"]
        )
      }
    }
    artifacts = {
      files = ["imagedefinitions-*.json"]
    }
  })
}
