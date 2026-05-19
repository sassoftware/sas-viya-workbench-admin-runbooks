# SAS® Viya® Workbench Admin Runbooks

## Overview

Operational runbooks and automation scripts for manangement of SAS® Viya® Workbench clusters.

## Available Runbooks

- **[Schedule Cluster Shutdown and Start-up for AWS Infrastructure](./scripts/runbooks/cluster_parking/aws/README.md)** - Automatic shut down and start up for Workbench AWS EKS cluster on a schedule (e.g. 9-5pm).

## Build Tools (for project maintainers)
> Note: If you are consuming the runbooks, you can ignore this section.

These scripts are internal development utilities for working on this repository.

The repository includes several build and development tools for creating runbooks located in `scripts/build/`:

### Scripts

- **`build.sh`** - Builds each runbook into single executable scripts in the `dist/` directory. Combines main.sh files with their dependencies by inlining sourced files. Generates cloud provider-specific scripts (e.g., `aws_cluster_parking.sh`).

- **`check.sh`** - Runs shellcheck on all `.sh` files in the `scripts/` directory for static analysis and linting. Helps ensure shell script quality and catches common issues.

- **`fmt.sh`** - Formats all shell scripts using `shfmt` with consistent indentation (2 spaces), compact if statements, and simplified formatting. Maintains code style consistency across the project.

### Usage

```bash
# Build all runbooks
./scripts/build/build.sh

# Check all scripts for issues
./scripts/build/check.sh

# Format all shell scripts
./scripts/build/fmt.sh
```

## Contributing

Contributions are not currently accepted.

## License

This project is licensed under the [Apache 2.0 License](LICENSE).