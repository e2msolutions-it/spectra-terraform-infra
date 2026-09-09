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
        ])
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
