# distros

两套构建套件，四套成品镜像：

| 套件 | suite | 产物 |
|---|---|---|
| `ubuntu/` | `resolute` / `noble` | Ubuntu 26.04 / 24.04 |
| `debian/` | `trixie` / `bookworm` | Debian 13 / 12 |

两套共用同一套优化（`files/**` 各一份副本，内容一致）：BBR、limits、timesyncd、首启 `sf-firstboot`（换源 + 按内存分档建 swap）。改优化时**两边都要改**，否则四套镜像会不一致。

## 默认用户

两边 `conf.sh` 都是 `USER_NAME=root`，镜像里不出预置密码，`sshd_config.d/10-image.conf` 写的是 `PermitRootLogin yes`。

想要普通用户的镜像，重建时改环境变量即可，不用改文件：

```bash
USER_NAME=ubuntu bash ./build.sh    # Ubuntu 套件
USER_NAME=debian bash ./build.sh    # Debian 套件
```

## 常用开关

`SUITE` `MIRROR` `GUEST_MIRROR_CN` `IMG_SIZE` `WITH_OPS` `WITH_QGA` `WITH_DOCKER` `WITH_FIRMWARE` `SWAP_MODE` `USER_PASSWORD`，全部可通过环境变量覆盖，详见 `conf.sh` 顶部注释。

完整构建与 CI 说明见 [`../docs/BUILD.md`](../docs/BUILD.md)。
