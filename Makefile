.PHONY: all build seed boot smoke lint clean

all: build

build:            ## 构建 qcow2
	./build.sh

seed:             ## 生成 cloud-init seed.iso
	./scripts/make-seed.sh

boot:             ## 本地 KVM 试启动
	./scripts/test-boot.sh

smoke:            ## 无 KVM 冒烟启动（CI 用）
	./scripts/smoke-test.sh

lint:             ## bash 语法 + shellcheck
	@for f in build.sh conf.sh hooks/*.sh scripts/*.sh; do bash -n "$$f" && echo "ok  $$f"; done
	@command -v shellcheck >/dev/null && shellcheck -S warning -x build.sh conf.sh hooks/*.sh scripts/*.sh || true

clean:
	rm -rf out work build.log
