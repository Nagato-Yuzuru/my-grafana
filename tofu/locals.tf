locals {
  # Absolute repo root, derived from the module dir so it survives clone/move.
  # Alloy (a separate process) reads op.env by this absolute path.
  repo_root = abspath("${path.module}/..")
  alloy_dir = "${local.repo_root}/alloy"
}
