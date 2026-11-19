# distros/ubuntu

Ubuntu 26.04 LTS（代号 `resolute`）无 snap 服务器镜像的构建套件。

- 入口：`build.sh`；参数全在 `conf.sh`（也可用环境变量覆盖）
- 分区：`bios_grub` + `ESP(EFI, 256M)` + `ext4` 根，GRUB 同时装 UEFI 和 BIOS
- 产物：`out/<IMAGE_NAME>.qcow2`

默认组合：`WITH_DOCKER=0`、`WITH_FIRMWARE=0`、`WITH_OPS=1`（push 触发与手动触发一致，已在 workflow 里把空值归为默认）。

CI 触发：本目录任何文件变动 → `image-ubuntu` workflow；commit message 带 `[publish]` 才会更新 `image-latest` Release。

详细参数见 `README.md`（本目录）。
