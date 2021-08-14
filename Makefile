CROSS_COMPILE ?= aarch64-linux-gnu-
MKDIR ?= mkdir -p
CP ?= cp
CAT ?= cat
TAR ?= tar
SUDO ?= sudo
CONFIG ?= config/apple-m1-j293.config
PWD ?= $(shell pwd)

all: build/linux/done/pack

%/:
	$(MKDIR) $@

build/linux/done/copy: | build/linux/done/
	$(CP) -as $(PWD)/linux/ build/linux/build
	touch $@

build/linux/done/configure: $(CONFIG) build/linux/done/copy
	$(CP) $< build/linux/build/.config
	$(MAKE) -C build/linux/build ARCH=arm64 CROSS_COMPILE=$(CROSS_COMPILE) olddefconfig
	touch $@

build/linux/done/build: build/linux/done/configure
	$(MAKE) -C build/linux/build ARCH=arm64 CROSS_COMPILE=$(CROSS_COMPILE)
	touch $@

build/linux/done/install: build/linux/done/build
	$(MAKE) -C build/linux/build ARCH=arm64 CROSS_COMPILE=$(CROSS_COMPILE) INSTALL_MOD_PATH=$(PWD)/build/linux.modules.d modules_install
	touch $@

build/linux/done/pack: build/linux/done/install
	(cd build/linux.modules.d; tar czv .) > build/linux.modules.gz
	gzip < build/linux/build/arch/arm64/boot/Image > build/linux.image.gz
	touch $@

.github-init:
	bash github/artifact-init
	@touch $@

build/artifacts{push}: .github-init
	(cd build/artifacts/up; for file in *; do name=$$(basename "$$file"); (cd $(PWD); bash g/github/ul-artifact "$$name" "build/artifacts/up/$$name") && rm -f "build/artifacts/up/$$name"; done)

%{artifact}: % .github-init
	$(MKDIR) build/artifacts/up
	cp $< build/artifacts/up
	$(MAKE) build/artifacts{push}

.SECONDARY: %
