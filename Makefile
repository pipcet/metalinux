CROSS_COMPILE ?= aarch64-linux-gnu-
MKDIR ?= mkdir -p
CP ?= cp
CAT ?= cat
TAR ?= tar
SUDO ?= sudo
ARCH ?= arm64
CONFIG ?= config/apple-m1-j293.config
PWD ?= $(shell pwd)
BUILD ?= build

all: $(BUILD)/linux/done/pack

%/:
	$(MKDIR) $@

$(BUILD)/debian/debootstrap/done/checkout:
	$(MKDIR) $(BUILD)/debian/debootstrap/done
	$(MKDIR) debian/debootstrap
	(cd debian/debootstrap; git clone https://github.com/pipcet/debootstrap)
	touch $@

$(BUILD)/debian/debootstrap/stage1.tar: $(BUILD)/debian/debootstrap/done/checkout | $(BUILD)/debian/debootstrap/
	$(SUDO) DEBOOTSTRAP_DIR=$(PWD)/debian/debootstrap/debootstrap ./debian/debootstrap/debootstrap/debootstrap --foreign --arch=arm64 --include=dash,wget,busybox,busybox-static,network-manager,openssh-client,net-tools,libpam-systemd,cryptsetup,lvm2,memtool,nvme-cli,watchdog,minicom,device-tree-compiler,file,gpm sid $(BUILD)/debian/debootstrap/stage1 http://deb.debian.org/debian
	(cd $(BUILD)/debian/debootstrap/stage1; $(SUDO) tar c .) > $@

$(BUILD)/debian/debootstrap/stage15.tar: $(BUILD)/debian/debootstrap/stage1.tar $(BUILD)/linux/done/pack
	$(MKDIR) $(BUILD)/debian/debootstrap/stage15
	(cd $(BUILD)/debian/debootstrap/stage15; $(SUDO) tar x) < $<
	(cd $(BUILD)/debian/debootstrap/stage15/var/cache/apt/archives/; for a in *.deb; do $(SUDO) dpkg-deb -R $$a $$a.d; $(SUDO) dpkg-deb -b -Znone $$a.d; $(SUDO) mv $$a.d.deb $$a; $(SUDO) rm -rf $$a.d; done)
	for a in $(BUILD)/debian/debootstrap/stage15/var/cache/apt/archives/*.deb; do $(SUDO) dpkg -x $$a $(BUILD)/debian/debootstrap/stage15; done
	(echo "root:x:0:0:root:/root:/bin/bash" | $(SUDO) tee $(BUILD)/debian/debootstrap/stage15/etc/passwd)
	(echo "root::0:::::" | $(SUDO) tee $(BUILD)/debian/debootstrap/stage15/etc/shadow)
	(cd $(BUILD)/debian/debootstrap/stage15; $(SUDO) tar xz) < $(BUILD)/linux.modules.gz
	(echo "#!/bin/sh"; echo "/debootstrap/debootstrap --second-stage"; echo "(echo x; echo x) | passwd"; echo "exec /sbin/init") > $(BUILD)/debian/debootstrap/stage15/init
	chmod a+x $(BUILD)/debian/debootstrap/stage15/init
	(cd $(BUILD)/debian/debootstrap/stage15; $(SUDO) tar c .) > $@

$(BUILD)/debian.cpio: $(BUILD)/debian/debootstrap/stage15.tar
	$(MKDIR) $(BUILD)/debian/cpio.d
	(cd $(BUILD)/debian/cpio.d; $(SUDO) tar x) < $<
	$(SUDO) ln -sf bin/bash $(BUILD)/debian/cpio.d/init
	(cd $(BUILD)/debian/cpio.d; $(SUDO) find | $(SUDO) cpio -o -H newc) > $@

$(BUILD)/debian.cpio.gz: $(BUILD)/debian.cpio
	gzip < $< > $@

$(BUILD)/linux/done/copy: | $(BUILD)/linux/done/
	$(CP) -as $(PWD)/linux/ $(BUILD)/linux/build
	touch $@

menuconfig: $(CONFIG)
	$(CP) $< $(BUILD)/linux/build/.config
	$(MAKE) -C $(BUILD)/linux/build ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) menuconfig
	$(CP) $< $<.old
	$(CP) $(BUILD)/linux/build/.config $<

$(BUILD)/linux/done/configure: $(CONFIG) $(BUILD)/linux/done/copy
	$(CP) $< $(BUILD)/linux/build/.config
	$(MAKE) -C $(BUILD)/linux/build ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) olddefconfig
	touch $@

$(BUILD)/linux/done/build: $(BUILD)/linux/done/configure
	$(MAKE) -C $(BUILD)/linux/build ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE)
	touch $@

$(BUILD)/linux/done/install: $(BUILD)/linux/done/build
	$(MAKE) -C $(BUILD)/linux/build ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) INSTALL_MOD_PATH=$(PWD)/$(BUILD)/linux.modules.d modules_install
	touch $@

$(BUILD)/linux/done/pack: $(BUILD)/linux/done/install
	(cd $(BUILD)/linux.modules.d; tar czv .) > $(BUILD)/linux.modules.gz
	gzip < $(BUILD)/linux/build/arch/arm64/boot/Image > $(BUILD)/linux.image.gz
	touch $@

.github-init:
	bash github/artifact-init
	@touch $@

$(BUILD)/artifacts{push}: .github-init
	(cd $(BUILD)/artifacts/up; for file in *; do name=$$(basename "$$file"); (cd $(PWD); bash github/ul-artifact "$$name" "$(BUILD)/artifacts/up/$$name") && rm -f "$(BUILD)/artifacts/up/$$name"; done)

%{artifact}: % .github-init
	$(MKDIR) $(BUILD)/artifacts/up
	cp $< $(BUILD)/artifacts/up
	$(MAKE) $(BUILD)/artifacts{push}

.PHONY: menuconfig
.SECONDARY: %
