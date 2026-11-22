# 发布标签

镜像每次自动重建后，会同时发布到两类 Release：

| 标签 | 内容 | 是否 latest |
|---|---|---|
| `ubuntu-26.04` | 仅该镜像的 qcow2 + `.sha256` | 否 |
| `ubuntu-24.04` | 同上 | 否 |
| `debian-13` | 同上 | 否 |
| `debian-12` | 同上 | 否 |
| `image-latest` | 全部镜像汇总 | 是 |

标签名由 `image-build.yml` 的 matrix `id` 直接得出，新增发行版只需在 matrix 里加一条。

## 链接形式

单镜像（固定标签，适合固定版本引用）：

```text
https://github.com/Asunano/snapfree-os/releases/download/ubuntu-26.04/ubuntu-26.04-server-snapfree-amd64.qcow2
```

汇总（始终指向最近一次发布，`catalog/catalog.tsv` 用的就是这个）：

```text
https://github.com/Asunano/snapfree-os/releases/latest/download/debian-13-server-snapfree-amd64.qcow2
```

## 发布时机

- 定时：每日 01:00（UTC+8）后随机延迟 0–60 分钟触发
- 手动：Actions 里跑 `image-build`；或推入 commit 且 message 包含 `[publish]`

发布前必须先过四套冒烟启动（`needs: [build, smoke]`），冒烟失败则不发布。
